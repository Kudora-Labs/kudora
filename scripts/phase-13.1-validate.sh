#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

source "${ROOT_DIR}/deploy/localnet/scripts/common.sh"
source "${ROOT_DIR}/scripts/localnet-validation-common.sh"

OUT_DIR="out"
REPORT_PATH="${OUT_DIR}/phase-13.1-validation.md"
BLOCKER_PATH="${OUT_DIR}/phase-13.1-blocker.md"
EXPECTED_BRANCH="Upgrade"

mkdir -p "${OUT_DIR}"
rm -f "${BLOCKER_PATH}"

branch_name="$(git branch --show-current)"
if [[ "${branch_name}" != "${EXPECTED_BRANCH}" ]]; then
  echo "phase-13.1-validate: expected branch ${EXPECTED_BRANCH}, found ${branch_name}" >&2
  exit 1
fi

starting_commit="$(git rev-parse HEAD)"
head_before_report="$(git rev-parse HEAD)"
working_tree_status_before="$(git status --short)"
generated_at="$(date -u '+%Y-%m-%d %H:%M:%S UTC')"
docker_version="$(docker version 2>&1 || true)"
docker_compose_version="$(compose_version_string)"
docker_image_tag="$(awk -F':= ' '/^DOCKER_IMAGE :=/ {print $2; exit}' Makefile)"
results=()
last_failure_label=""
last_failure_status=0
last_failure_output=""

check_phase131_artifacts() {
  local required_files=(
    "docs/docker/phase-13-localnet.md"
    "docs/docker/phase-13.1-localnet-portability.md"
    "deploy/localnet/docker-compose.yml"
    "deploy/localnet/scripts/init-localnet.sh"
    "deploy/localnet/scripts/smoke-localnet.sh"
    "scripts/localnet-validation-common.sh"
    "scripts/phase-13.1-validate.sh"
  )
  local path

  for path in "${required_files[@]}"; do
    [[ -f "${path}" ]] || {
      echo "phase-13.1-validate: required artifact missing: ${path}" >&2
      return 1
    }
  done
}

check_localnet_state_not_tracked() {
  local tracked
  tracked="$(git ls-files .localnet tmp/localnet deploy/localnet/state)"
  if [[ -n "${tracked}" ]]; then
    echo "phase-13.1-validate: localnet state must not be tracked" >&2
    printf '%s\n' "${tracked}" >&2
    return 1
  fi
}

write_blocker() {
  {
    echo "# Phase 13.1 Blocker"
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

write_report() {
  local phase13_status="not run"
  local localnet_init_status="not run"
  local localnet_metadata_status="not run"
  local localnet_up_status="not run"
  local localnet_container_user_status="not run"
  local localnet_smoke_status="not run"
  local localnet_smoke_current_run_status="not run"
  local no_forks_status="not run"
  local no_secrets_status="not run"
  local dependency_audit_status="not run"
  local vulncheck_status="not run"
  local archive_status="not run"
  local localnet_state_status="not run"
  local init_mode_summary="unknown"
  local host_binary_required_summary="unknown"
  local host_go_required_summary="unknown"
  local container_user_summary="unknown"
  local local_uid_summary="${LOCALNET_UID}"
  local local_gid_summary="${LOCALNET_GID}"
  local height_before_summary="not available"
  local height_after_summary="not available"
  local height_delta_summary="not available"
  local evm_smoke_status="not run"
  local evm_tx_status="not run"
  local evm_contract_status="not run"
  local wasm_smoke_status="not run"

  for result in "${results[@]}"; do
    case "${result}" in
      PASS\|make\ phase-13-validate) phase13_status="PASS" ;;
      FAIL\|make\ phase-13-validate) phase13_status="FAIL" ;;
      PASS\|make\ localnet-init) localnet_init_status="PASS" ;;
      FAIL\|make\ localnet-init) localnet_init_status="FAIL" ;;
      PASS\|Phase\ 13.1\ docker-first\ localnet\ init\ metadata) localnet_metadata_status="PASS" ;;
      FAIL\|Phase\ 13.1\ docker-first\ localnet\ init\ metadata) localnet_metadata_status="FAIL" ;;
      PASS\|make\ localnet-up) localnet_up_status="PASS" ;;
      FAIL\|make\ localnet-up) localnet_up_status="FAIL" ;;
      PASS\|Phase\ 13.1\ localnet\ container\ user) localnet_container_user_status="PASS" ;;
      FAIL\|Phase\ 13.1\ localnet\ container\ user) localnet_container_user_status="FAIL" ;;
      PASS\|make\ localnet-smoke-test) localnet_smoke_status="PASS" ;;
      FAIL\|make\ localnet-smoke-test) localnet_smoke_status="FAIL" ;;
      PASS\|Phase\ 13.1\ localnet\ smoke\ current-run\ verification) localnet_smoke_current_run_status="PASS" ;;
      FAIL\|Phase\ 13.1\ localnet\ smoke\ current-run\ verification) localnet_smoke_current_run_status="FAIL" ;;
      PASS\|make\ verify-no-forks) no_forks_status="PASS" ;;
      FAIL\|make\ verify-no-forks) no_forks_status="FAIL" ;;
      PASS\|make\ verify-no-secrets) no_secrets_status="PASS" ;;
      FAIL\|make\ verify-no-secrets) no_secrets_status="FAIL" ;;
      PASS\|make\ dependency-audit) dependency_audit_status="PASS" ;;
      FAIL\|make\ dependency-audit) dependency_audit_status="FAIL" ;;
      PASS\|make\ vulncheck) vulncheck_status="PASS" ;;
      FAIL\|make\ vulncheck) vulncheck_status="FAIL" ;;
      PASS\|make\ zip) archive_status="PASS" ;;
      FAIL\|make\ zip) archive_status="FAIL" ;;
      PASS\|Phase\ 13.1\ localnet\ state\ is\ not\ tracked) localnet_state_status="PASS" ;;
      FAIL\|Phase\ 13.1\ localnet\ state\ is\ not\ tracked) localnet_state_status="FAIL" ;;
    esac
  done

  if [[ -f "${METADATA_PATH}" ]]; then
    init_mode_summary="$(jq -r '.init_mode // "unknown"' "${METADATA_PATH}")"
    host_binary_required_summary="$(jq -r 'if has("host_binary_required") then (.host_binary_required | tostring) else "unknown" end' "${METADATA_PATH}")"
    host_go_required_summary="$(jq -r 'if has("host_go_required") then (.host_go_required | tostring) else "unknown" end' "${METADATA_PATH}")"
    container_user_summary="$(jq -r '.container_user // "unknown"' "${METADATA_PATH}")"
  fi

  if [[ -f "${LOCALNET_VALIDATION_SMOKE_RESULT_PATH}" ]]; then
    evm_smoke_status="$(jq -r '.evm_smoke_status // "not run"' "${LOCALNET_VALIDATION_SMOKE_RESULT_PATH}")"
    evm_tx_status="$(jq -r '.evm_transaction_status // "not run"' "${LOCALNET_VALIDATION_SMOKE_RESULT_PATH}")"
    evm_contract_status="$(jq -r '.evm_contract_status // "not run"' "${LOCALNET_VALIDATION_SMOKE_RESULT_PATH}")"
    wasm_smoke_status="$(jq -r '.wasm_smoke_status // "not run"' "${LOCALNET_VALIDATION_SMOKE_RESULT_PATH}")"
    height_before_summary="$(jq -r '.height_before // "not available"' "${LOCALNET_VALIDATION_SMOKE_RESULT_PATH}")"
    height_after_summary="$(jq -r '.height_after // "not available"' "${LOCALNET_VALIDATION_SMOKE_RESULT_PATH}")"
    height_delta_summary="$(jq -r '.height_delta // "not available"' "${LOCALNET_VALIDATION_SMOKE_RESULT_PATH}")"
  fi

  {
    echo "# Phase 13.1 Validation Report"
    echo
    echo "- Validation generated at: ${generated_at}"
    echo "- Branch: ${branch_name}"
    echo "- Starting commit: ${starting_commit}"
    echo "- Current HEAD before report generation: ${head_before_report}"
    echo "- Docker image tag: \`${docker_image_tag}\`"
    echo "- Localnet init mode: \`${init_mode_summary}\`"
    echo "- Whether host build/kudorad was required: \`${host_binary_required_summary}\`"
    echo "- Whether host Go was required: \`${host_go_required_summary}\`"
    echo "- Container user strategy: \`${container_user_summary}\`"
    echo "- LOCAL_UID: \`${local_uid_summary}\`"
    echo "- LOCAL_GID: \`${local_gid_summary}\`"
    echo "- Block height before: \`${height_before_summary}\`"
    echo "- Block height after: \`${height_after_summary}\`"
    echo "- Block height delta: \`${height_delta_summary}\`"
    echo
    echo "## Working Tree Status Before Validation"
    echo
    echo '```text'
    echo "${working_tree_status_before:-clean}"
    echo '```'
    echo
    echo "## Tooling"
    echo
    echo '```text'
    echo "${docker_version}"
    echo
    echo "${docker_compose_version}"
    echo '```'
    echo
    echo "## Results"
    echo
    for result in "${results[@]}"; do
      status="${result%%|*}"
      label="${result#*|}"
      echo "- ${status}: \`${label}\`"
    done
    echo
    if [[ -n "${last_failure_label}" ]]; then
      echo "## First Failure"
      echo
      echo "- Label: \`${last_failure_label}\`"
      echo "- Exit status: \`${last_failure_status}\`"
      echo
      echo '```text'
      echo "${last_failure_output}"
      echo '```'
      echo
    fi
    echo "## Runtime Summary"
    echo
    echo "- Phase 13 validation result: ${phase13_status}"
    echo "- Localnet init result: ${localnet_init_status}"
    echo "- Localnet docker-first metadata verification: ${localnet_metadata_status}"
    echo "- Localnet startup result: ${localnet_up_status}"
    echo "- Localnet container user verification: ${localnet_container_user_status}"
    echo "- Localnet smoke result: ${localnet_smoke_status}"
    echo "- Localnet smoke current-run verification: ${localnet_smoke_current_run_status}"
    echo "- EVM smoke result: ${evm_smoke_status}"
    echo "- EVM transaction result: ${evm_tx_status}"
    echo "- EVM contract result: ${evm_contract_status}"
    echo "- Wasm smoke result: ${wasm_smoke_status}"
    echo
    echo "## Security And Dependency Summary"
    echo
    echo "- Dependency audit result: ${dependency_audit_status}"
    echo "- Vulnerability scan result: ${vulncheck_status}"
    echo "- No-forks result: ${no_forks_status}"
    echo "- No-secrets result: ${no_secrets_status}"
    echo "- Localnet state tracking check: ${localnet_state_status}"
    echo
    echo "## Archive Paths"
    echo
    echo "- Phase 13 archive: \`out/kudora-phase-13-localnet-docker.zip\`"
    echo "- Latest inspection archive: \`out/kudora-latest-inspection.zip\`"
    echo "- Archive generation result: ${archive_status}"
    echo
    echo "## Confirmations"
    echo
    echo "- Localnet smoke artifact is from the current run: ${localnet_smoke_current_run_status}"
    echo "- No generated localnet state is tracked: ${localnet_state_status}"
    echo "- No generated keys are tracked: ${no_secrets_status}"
    echo "- No business modules were added."
    echo "- No IBC product/tokenfactory/packet-forward/rate-limit/ICA/08-wasm/monitoring work was added."
    echo "- Later local-only explorer work from Phase 14 does not invalidate the Phase 13.1 portability baseline."
    echo "- No Docker registry push was performed."
  } >"${REPORT_PATH}"
}

cleanup() {
  make localnet-down >/dev/null 2>&1 || true
}
trap cleanup EXIT

run_check "Phase 13.1 artifacts exist" check_phase131_artifacts || { write_blocker; write_report; echo "phase-13.1-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make phase-13-validate" make phase-13-validate || { write_blocker; write_report; echo "phase-13.1-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make tidy" make tidy || { write_blocker; write_report; echo "phase-13.1-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "go mod verify" go mod verify || { write_blocker; write_report; echo "phase-13.1-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make build" make build || { write_blocker; write_report; echo "phase-13.1-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make test" make test || { write_blocker; write_report; echo "phase-13.1-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make lint" make lint || { write_blocker; write_report; echo "phase-13.1-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make verify-no-forks" make verify-no-forks || { write_blocker; write_report; echo "phase-13.1-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make verify-clean-reset" make verify-clean-reset || { write_blocker; write_report; echo "phase-13.1-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make verify-no-secrets" make verify-no-secrets || { write_blocker; write_report; echo "phase-13.1-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make dependency-audit" make dependency-audit || { write_blocker; write_report; echo "phase-13.1-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make vulncheck" make vulncheck || { write_blocker; write_report; echo "phase-13.1-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make docker-build" make docker-build || { write_blocker; write_report; echo "phase-13.1-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make docker-smoke-test" make docker-smoke-test || { write_blocker; write_report; echo "phase-13.1-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make localnet-reset" make localnet-reset || { write_blocker; write_report; echo "phase-13.1-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make localnet-init" localnet_validation_run_default_docker_init || { write_blocker; write_report; echo "phase-13.1-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "Phase 13.1 docker-first localnet init metadata" localnet_validation_check_init_metadata || { write_blocker; write_report; echo "phase-13.1-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make localnet-up" make localnet-up || { write_blocker; write_report; echo "phase-13.1-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "Phase 13.1 localnet container user" localnet_validation_check_container_user || { write_blocker; write_report; echo "phase-13.1-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make localnet-smoke-test" localnet_validation_run_smoke || { write_blocker; write_report; echo "phase-13.1-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "Phase 13.1 localnet smoke current-run verification" localnet_validation_check_smoke_current_run || { write_blocker; write_report; echo "phase-13.1-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make localnet-down" make localnet-down || { write_blocker; write_report; echo "phase-13.1-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make zip" make zip || { write_blocker; write_report; echo "phase-13.1-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "Phase 13.1 localnet state is not tracked" check_localnet_state_not_tracked || { write_blocker; write_report; echo "phase-13.1-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }

write_report

echo "phase-13.1-validate: PASS (${REPORT_PATH})"
