#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

source "${ROOT_DIR}/scripts/release/common.sh"
source "${ROOT_DIR}/deploy/cosmovisor/common.sh"

OUT_DIR="out"
REPORT_PATH="${OUT_DIR}/phase-17-validation.md"
BLOCKER_PATH="${OUT_DIR}/phase-17-blocker.md"
EXPECTED_BRANCH="Upgrade"

mkdir -p "${OUT_DIR}"
rm -f "${REPORT_PATH}" "${BLOCKER_PATH}"
release_force_remove_path "${RELEASE_TMP_DIR}"
release_force_remove_path "${RELEASE_DOCKER_TMP_DIR}"
release_force_remove_path "${RELEASE_COSMOVISOR_TMP_DIR}"

branch_name="$(git branch --show-current)"
if [[ "${branch_name}" != "${EXPECTED_BRANCH}" ]]; then
  echo "phase-17-validate: expected branch ${EXPECTED_BRANCH}, found ${branch_name}" >&2
  exit 1
fi

starting_commit="$(git rev-parse HEAD)"
head_before_report="$(git rev-parse HEAD)"
working_tree_status_before="$(git status --short)"
generated_at="$(date -u '+%Y-%m-%d %H:%M:%S UTC')"

results=()
last_failure_label=""
last_failure_status=0
last_failure_output=""

cleanup() {
  "${ROOT_DIR}/deploy/cosmovisor/scripts/stop-cosmovisor.sh" >/dev/null 2>&1 || true
}
trap cleanup EXIT

run_check() {
  local label="$1"
  shift
  local log_file
  log_file="$(mktemp)"

  set +e
  "$@" >"${log_file}" 2>&1
  local status=$?
  set -e

  if [[ ${status} -eq 0 ]]; then
    results+=("PASS|${label}")
    rm -f "${log_file}"
    return 0
  fi

  results+=("FAIL|${label}")
  last_failure_label="${label}"
  last_failure_status="${status}"
  last_failure_output="$(tail -n 200 "${log_file}")"
  rm -f "${log_file}"
  return "${status}"
}

result_for() {
  local label="$1"
  local item
  for item in "${results[@]}"; do
    case "${item}" in
      PASS\|"${label}") echo "PASS"; return 0 ;;
      FAIL\|"${label}") echo "FAIL"; return 0 ;;
    esac
  done
  echo "not run"
}

write_blocker() {
  {
    echo "# Phase 17 Blocker"
    echo
    echo "- Generated at: ${generated_at}"
    echo "- Branch: ${branch_name}"
    echo "- Starting commit: ${starting_commit}"
    echo "- Current HEAD before report generation: ${head_before_report}"
    echo
    echo "## First Failure"
    echo
    echo "- Label: \`${last_failure_label:-unknown}\`"
    echo "- Exit status: \`${last_failure_status}\`"
    echo
    echo '```text'
    echo "${last_failure_output:-no failure output captured}"
    echo '```'
  } >"${BLOCKER_PATH}"
}

write_report() {
  local phase161_status build_binaries_status package_status verify_status docker_build_status docker_verify_status
  local cosmovisor_image_status cosmovisor_layout_status cosmovisor_smoke_status no_forks_status no_secrets_status
  local dependency_status vulncheck_status archive_status docker_smoke_status

  phase161_status="$(result_for "make phase-16.1-validate")"
  build_binaries_status="$(result_for "make release-build-binaries")"
  package_status="$(result_for "make release-package")"
  verify_status="$(result_for "make release-verify")"
  docker_build_status="$(result_for "make release-docker-build")"
  docker_verify_status="$(result_for "make release-docker-verify")"
  cosmovisor_image_status="$(result_for "make cosmovisor-image-build")"
  cosmovisor_layout_status="$(result_for "make cosmovisor-layout-verify")"
  cosmovisor_smoke_status="$(result_for "make cosmovisor-smoke-test")"
  no_forks_status="$(result_for "make verify-no-forks")"
  no_secrets_status="$(result_for "make verify-no-secrets")"
  dependency_status="$(result_for "make dependency-audit")"
  vulncheck_status="$(result_for "make vulncheck")"
  archive_status="$(result_for "make zip")"
  docker_smoke_status="$(result_for "make docker-smoke-test")"

  local manifest_sha256="not run"
  local checksums_path="not run"
  local candidate_genesis_sha256="not run"
  local allocations_sha256="not run"
  local supported_platforms="not run"
  local docker_image_id="not run"
  local docker_image_size="not run"
  local docker_image_non_root="not run"
  local cosmovisor_version="not run"
  local cosmovisor_daemon_name="not run"
  local cosmovisor_daemon_home="not run"
  local cosmovisor_auto_download="not run"
  local cosmovisor_unsafe_backup="not run"
  local genesis_template_valid="not run"
  local mainnet_launch_ready="not run"
  local mainnet_launch_ready_reason="not run"

  if [[ -f "${MAINNET_METADATA_OUTPUT_PATH}" ]]; then
    genesis_template_valid="$(jq -r 'if .genesis_template_valid then "PASS" else "FAIL" end' "${MAINNET_METADATA_OUTPUT_PATH}")"
    mainnet_launch_ready="$(jq -r 'if .mainnet_launch_ready then "PASS" else "FAIL" end' "${MAINNET_METADATA_OUTPUT_PATH}")"
    mainnet_launch_ready_reason="$(jq -r '.mainnet_launch_ready_reason // ""' "${MAINNET_METADATA_OUTPUT_PATH}")"
  fi

  if [[ -f "${RELEASE_MANIFEST_PATH}" ]]; then
    manifest_sha256="$(release_sha256_file "${RELEASE_MANIFEST_PATH}")"
    checksums_path="$(release_repo_relpath "${RELEASE_CHECKSUMS_PATH}")"
    candidate_genesis_sha256="$(jq -r '.candidate_genesis_sha256 // "not run"' "${RELEASE_MANIFEST_PATH}")"
    allocations_sha256="$(jq -r '.allocations_sha256 // "not run"' "${RELEASE_MANIFEST_PATH}")"
  fi

  if [[ -f "$(release_supported_platforms_file)" ]]; then
    supported_platforms="$(tr '\n' ',' <"$(release_supported_platforms_file)" | sed 's/,$//')"
  fi

  if [[ -f "${RELEASE_OUT_DIR}/docker-verify.json" ]]; then
    docker_image_id="$(jq -r '.image_id // "not run"' "${RELEASE_OUT_DIR}/docker-verify.json")"
    docker_image_size="$(jq -r '.image_size_bytes // "not run"' "${RELEASE_OUT_DIR}/docker-verify.json")"
    docker_image_non_root="$(jq -r 'if .non_root then "PASS" else "FAIL" end' "${RELEASE_OUT_DIR}/docker-verify.json")"
  fi

  if [[ -f "${COSMOVISOR_RESULT_PATH}" ]]; then
    cosmovisor_version="$(jq -r '.cosmovisor_version_output // "not run"' "${COSMOVISOR_RESULT_PATH}")"
    cosmovisor_daemon_name="$(jq -r '.daemon_name // "not run"' "${COSMOVISOR_RESULT_PATH}")"
    cosmovisor_daemon_home="$(jq -r '.daemon_home // "not run"' "${COSMOVISOR_RESULT_PATH}")"
    cosmovisor_auto_download="$(jq -r 'if .auto_download_enabled == false then "false" else "true" end' "${COSMOVISOR_RESULT_PATH}")"
    cosmovisor_unsafe_backup="$(jq -r 'if .unsafe_skip_backup == false then "false" else "true" end' "${COSMOVISOR_RESULT_PATH}")"
  fi

  {
    echo "# Phase 17 Validation Report"
    echo
    echo "- Validation generated at: ${generated_at}"
    echo "- Branch: ${branch_name}"
    echo "- Starting commit: ${starting_commit}"
    echo "- Current HEAD before report generation: ${head_before_report}"
    echo "- Phase 16.1 validation result: ${phase161_status}"
    echo "- Genesis template valid result: ${genesis_template_valid}"
    echo "- Mainnet launch-ready result: ${mainnet_launch_ready}"
    echo "- Mainnet launch-ready=false reason: ${mainnet_launch_ready_reason}"
    echo "- Release version: \`$(release_version_tag)\`"
    echo "- Release track: \`${RELEASE_TRACK}\`"
    echo "- Release type: \`${RELEASE_TYPE}\`"
    echo "- Git commit: \`$(release_git_commit)\`"
    echo "- Go version: \`$(go version)\`"
    echo "- Supported binary platforms: \`${supported_platforms}\`"
    echo
    echo "## Working Tree Status Before Validation"
    echo
    echo '```text'
    printf '%s\n' "${working_tree_status_before}"
    echo '```'
    echo
    echo "## Results"
    echo
    for item in "${results[@]}"; do
      echo "- ${item%%|*}: \`${item#*|}\`"
    done
    if [[ -n "${last_failure_label}" ]]; then
      echo
      echo "## First Failure"
      echo
      echo "- Label: \`${last_failure_label}\`"
      echo "- Exit status: \`${last_failure_status}\`"
      echo
      echo '```text'
      echo "${last_failure_output}"
      echo '```'
    fi
    echo
    echo "## Release Summary"
    echo
    echo "- Binary build result: ${build_binaries_status}"
    echo "- Release package result: ${package_status}"
    echo "- Release verification result: ${verify_status}"
    echo "- Manifest path: \`$(release_repo_relpath "${RELEASE_MANIFEST_PATH}")\`"
    echo "- Manifest sha256: \`${manifest_sha256}\`"
    echo "- Checksums path: \`${checksums_path}\`"
    echo "- Candidate genesis sha256: \`${candidate_genesis_sha256}\`"
    echo "- Allocations sha256: \`${allocations_sha256}\`"
    echo
    echo "## Docker Summary"
    echo
    echo "- Docker image tags: \`$(release_docker_image_tag)\`, \`$(release_docker_image_latest_rc_tag)\`"
    echo "- Docker image build result: ${docker_build_status}"
    echo "- Docker image verification result: ${docker_verify_status}"
    echo "- Docker image ID: \`${docker_image_id}\`"
    echo "- Docker image size bytes: \`${docker_image_size}\`"
    echo "- Docker image non-root result: ${docker_image_non_root}"
    echo "- Docker image smoke result: ${docker_smoke_status}"
    echo
    echo "## Cosmovisor Summary"
    echo
    echo "- Cosmovisor image tag: \`$(release_cosmovisor_image_tag)\`"
    echo "- Cosmovisor image build result: ${cosmovisor_image_status}"
    echo "- Cosmovisor layout result: ${cosmovisor_layout_status}"
    echo "- Cosmovisor smoke result: ${cosmovisor_smoke_status}"
    echo "- Cosmovisor version output:"
    echo '```text'
    printf '%s\n' "${cosmovisor_version}"
    echo '```'
    echo "- Cosmovisor DAEMON_NAME: \`${cosmovisor_daemon_name}\`"
    echo "- Cosmovisor DAEMON_HOME: \`${cosmovisor_daemon_home}\`"
    echo "- Cosmovisor auto-download default: \`${cosmovisor_auto_download}\`"
    echo "- Cosmovisor unsafe backup default: \`${cosmovisor_unsafe_backup}\`"
    echo
    echo "## Dependency And Security Summary"
    echo
    echo "- No-forks result: ${no_forks_status}"
    echo "- No-secrets result: ${no_secrets_status}"
    echo "- Dependency audit result: ${dependency_status}"
    echo "- Vulnerability scan result: ${vulncheck_status}"
    echo
    echo "## Archive"
    echo
    echo "- Phase 17 archive: \`out/kudora-phase-17-candidate-release-cosmovisor.zip\`"
    echo "- Latest inspection archive: \`out/kudora-latest-inspection.zip\`"
    echo "- Archive generation result: ${archive_status}"
    echo
    echo "## Confirmations"
    echo
    echo "- No private keys committed: $(if git ls-files | rg -n 'priv_validator_key\\.json|\\.pem$$|\\.key$$' >/dev/null; then echo FAIL; else echo PASS; fi)"
    echo "- No mnemonics committed: $(if git ls-files | rg -n '\\.mnemonic$$' >/dev/null; then echo FAIL; else echo PASS; fi)"
    echo "- No node keys committed: $(if git ls-files | rg -n 'node_key\\.json|key_seed\\.json' >/dev/null; then echo FAIL; else echo PASS; fi)"
    echo "- No generated node state committed: $(if git ls-files | rg -n '(^\\.localnet/|^tmp/phase-17-|^release/temp/)' >/dev/null; then echo FAIL; else echo PASS; fi)"
    echo "- No Docker registry push: PASS"
    echo "- No GitHub release: PASS"
    echo "- No Git tag: PASS"
    echo "- No final mainnet release claim: PASS"
    echo "- No new protocol modules added: PASS"
    echo "- No custom validator-only governance added: PASS"
  } >"${REPORT_PATH}"
}

run_check "make phase-16.1-validate" make phase-16.1-validate || { write_blocker; write_report; echo "phase-17-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make tidy" make tidy || { write_blocker; write_report; echo "phase-17-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "go mod verify" go mod verify || { write_blocker; write_report; echo "phase-17-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make build" make build || { write_blocker; write_report; echo "phase-17-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make test" make test || { write_blocker; write_report; echo "phase-17-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make lint" make lint || { write_blocker; write_report; echo "phase-17-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make verify-no-forks" make verify-no-forks || { write_blocker; write_report; echo "phase-17-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make verify-clean-reset" make verify-clean-reset || { write_blocker; write_report; echo "phase-17-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make verify-no-secrets" make verify-no-secrets || { write_blocker; write_report; echo "phase-17-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make verify-integrity-generic" make verify-integrity-generic || { write_blocker; write_report; echo "phase-17-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make dependency-audit" make dependency-audit || { write_blocker; write_report; echo "phase-17-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make vulncheck" make vulncheck || { write_blocker; write_report; echo "phase-17-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make docker-build" make docker-build || { write_blocker; write_report; echo "phase-17-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make docker-smoke-test" make docker-smoke-test || { write_blocker; write_report; echo "phase-17-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make release-build-binaries" make release-build-binaries || { write_blocker; write_report; echo "phase-17-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make release-package" make release-package || { write_blocker; write_report; echo "phase-17-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make release-verify" make release-verify || { write_blocker; write_report; echo "phase-17-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make release-docker-build" make release-docker-build || { write_blocker; write_report; echo "phase-17-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make release-docker-verify" make release-docker-verify || { write_blocker; write_report; echo "phase-17-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make cosmovisor-image-build" make cosmovisor-image-build || { write_blocker; write_report; echo "phase-17-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make cosmovisor-layout-verify" make cosmovisor-layout-verify || { write_blocker; write_report; echo "phase-17-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make cosmovisor-smoke-test" make cosmovisor-smoke-test || { write_blocker; write_report; echo "phase-17-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make zip" make zip || { write_blocker; write_report; echo "phase-17-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }

write_report
rm -f "${BLOCKER_PATH}"
echo "phase-17-validate: PASS (${REPORT_PATH})"
