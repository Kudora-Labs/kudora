#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

source "${ROOT_DIR}/deploy/localnet/scripts/common.sh"
source "${ROOT_DIR}/scripts/localnet-validation-common.sh"

OUT_DIR="out"
REPORT_PATH="${OUT_DIR}/phase-12.1-lite-validation.md"
BLOCKER_PATH="${OUT_DIR}/phase-12.1-lite-blocker.md"
EXPECTED_BRANCH="Upgrade"
INTEGRITY_RESULT_PATH="${ROOT_DIR}/tmp/phase-12-integrity-smoke/result.json"
DOC_PATH="docs/modules/phase-12.1-lite-integrity-ownership-transfer.md"

mkdir -p "${OUT_DIR}"
rm -f "${BLOCKER_PATH}" "${REPORT_PATH}"
rm -rf "${ROOT_DIR}/tmp/phase-12-integrity-smoke"

branch_name="$(git branch --show-current)"
if [[ "${branch_name}" != "${EXPECTED_BRANCH}" ]]; then
  echo "phase-12.1-lite-validate: expected branch ${EXPECTED_BRANCH}, found ${branch_name}" >&2
  exit 1
fi

starting_commit="$(git rev-parse HEAD)"
head_before_report="$(git rev-parse HEAD)"
working_tree_status_before="$(git status --short)"
generated_at="$(date -u '+%Y-%m-%d %H:%M:%S UTC')"
validation_start_epoch="$(date +%s)"
go_version="$(go version)"
ignite_version="$(ignite version 2>&1 | sed 's/\t/ /g')"
docker_version="$(docker version 2>&1 || true)"
docker_image_tag="$(awk -F':= ' '/^DOCKER_IMAGE :=/ {print $2; exit}' Makefile)"

results=()
last_failure_label=""
last_failure_status=0
last_failure_output=""

cleanup() {
  rm -f "${ROOT_DIR}/tmp/phase-12.1-lite-transfer.log"
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

check_phase121_artifacts() {
  local required_files=(
    "${DOC_PATH}"
    "scripts/phase-12.1-lite-validate.sh"
    "x/integrity/keeper/msg_server_transfer_tenant_ownership.go"
    "x/integrity/keeper/msg_server_accept_tenant_ownership.go"
    "x/integrity/keeper/msg_server_cancel_tenant_ownership_transfer.go"
    "x/integrity/keeper/tenant_ownership.go"
  )
  local path

  for path in "${required_files[@]}"; do
    [[ -f "${path}" ]] || {
      echo "phase-12.1-lite-validate: required artifact missing: ${path}" >&2
      return 1
    }
  done
}

check_integrity_smoke_current_run() {
  [[ -f "${INTEGRITY_RESULT_PATH}" ]] || {
    echo "phase-12.1-lite-validate: integrity smoke result missing at ${INTEGRITY_RESULT_PATH}" >&2
    return 1
  }

  local mtime
  mtime="$(localnet_validation_file_mtime "${INTEGRITY_RESULT_PATH}")"
  (( mtime >= validation_start_epoch )) || {
    echo "phase-12.1-lite-validate: integrity smoke result is stale" >&2
    return 1
  }

  jq -e --argjson start "${validation_start_epoch}" '
    (.run_id // "" | length > 0) and
    .run_started_epoch >= $start and
    .run_finished_epoch >= .run_started_epoch and
    .tenant_registration_status == "PASS" and
    .ownership_transfer_status == "PASS" and
    .pending_owner_visibility_status == "PASS" and
    .pending_owner_commit_rejected_status == "PASS" and
    .old_owner_preaccept_commit_status == "PASS" and
    .ownership_acceptance_status == "PASS" and
    .old_owner_postaccept_rejected_status == "PASS" and
    .new_owner_postaccept_commit_status == "PASS" and
    .root_match_status == "PASS" and
    .records_sorted_status == "PASS" and
    .record_query_status == "PASS" and
    .plaintext_leak_status == "PASS"
  ' "${INTEGRITY_RESULT_PATH}" >/dev/null || {
    echo "phase-12.1-lite-validate: integrity smoke result is incomplete or failed" >&2
    return 1
  }
}

write_blocker() {
  {
    echo "# Phase 12.1-lite Blocker"
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
  local phase12_status="not run"
  local tidy_status="not run"
  local mod_verify_status="not run"
  local build_status="not run"
  local test_status="not run"
  local lint_status="not run"
  local no_forks_status="not run"
  local clean_reset_status="not run"
  local no_secrets_status="not run"
  local generic_guard_status="not run"
  local dependency_audit_status="not run"
  local vulncheck_status="not run"
  local docker_build_status="not run"
  local docker_smoke_status="not run"
  local integrity_smoke_status="not run"
  local archive_status="not run"
  local ownership_lifecycle_status="not run"
  local ownership_cancel_status="not run"
  local artifacts_status="not run"
  local current_run_status="not run"

  for result in "${results[@]}"; do
    case "${result}" in
      PASS\|make\ phase-12-validate) phase12_status="PASS" ;;
      FAIL\|make\ phase-12-validate) phase12_status="FAIL" ;;
      PASS\|Phase\ 12.1-lite\ required\ artifacts) artifacts_status="PASS" ;;
      FAIL\|Phase\ 12.1-lite\ required\ artifacts) artifacts_status="FAIL" ;;
      PASS\|make\ tidy) tidy_status="PASS" ;;
      FAIL\|make\ tidy) tidy_status="FAIL" ;;
      PASS\|go\ mod\ verify) mod_verify_status="PASS" ;;
      FAIL\|go\ mod\ verify) mod_verify_status="FAIL" ;;
      PASS\|make\ build) build_status="PASS" ;;
      FAIL\|make\ build) build_status="FAIL" ;;
      PASS\|make\ test) test_status="PASS" ;;
      FAIL\|make\ test) test_status="FAIL" ;;
      PASS\|make\ lint) lint_status="PASS" ;;
      FAIL\|make\ lint) lint_status="FAIL" ;;
      PASS\|make\ verify-no-forks) no_forks_status="PASS" ;;
      FAIL\|make\ verify-no-forks) no_forks_status="FAIL" ;;
      PASS\|make\ verify-clean-reset) clean_reset_status="PASS" ;;
      FAIL\|make\ verify-clean-reset) clean_reset_status="FAIL" ;;
      PASS\|make\ verify-no-secrets) no_secrets_status="PASS" ;;
      FAIL\|make\ verify-no-secrets) no_secrets_status="FAIL" ;;
      PASS\|make\ verify-integrity-generic) generic_guard_status="PASS" ;;
      FAIL\|make\ verify-integrity-generic) generic_guard_status="FAIL" ;;
      PASS\|make\ dependency-audit) dependency_audit_status="PASS" ;;
      FAIL\|make\ dependency-audit) dependency_audit_status="FAIL" ;;
      PASS\|make\ vulncheck) vulncheck_status="PASS" ;;
      FAIL\|make\ vulncheck) vulncheck_status="FAIL" ;;
      PASS\|make\ docker-build) docker_build_status="PASS" ;;
      FAIL\|make\ docker-build) docker_build_status="FAIL" ;;
      PASS\|make\ docker-smoke-test) docker_smoke_status="PASS" ;;
      FAIL\|make\ docker-smoke-test) docker_smoke_status="FAIL" ;;
      PASS\|go\ test\ ./x/integrity/keeper\ -run\ TestTenantOwnershipTransferLifecycle\ -count=1) ownership_lifecycle_status="PASS" ;;
      FAIL\|go\ test\ ./x/integrity/keeper\ -run\ TestTenantOwnershipTransferLifecycle\ -count=1) ownership_lifecycle_status="FAIL" ;;
      PASS\|go\ test\ ./x/integrity/keeper\ -run\ TestTenantOwnershipTransferCancellationAndValidation\ -count=1) ownership_cancel_status="PASS" ;;
      FAIL\|go\ test\ ./x/integrity/keeper\ -run\ TestTenantOwnershipTransferCancellationAndValidation\ -count=1) ownership_cancel_status="FAIL" ;;
      PASS\|make\ integrity-smoke-test) integrity_smoke_status="PASS" ;;
      FAIL\|make\ integrity-smoke-test) integrity_smoke_status="FAIL" ;;
      PASS\|Phase\ 12.1-lite\ integrity\ smoke\ current-run\ verification) current_run_status="PASS" ;;
      FAIL\|Phase\ 12.1-lite\ integrity\ smoke\ current-run\ verification) current_run_status="FAIL" ;;
      PASS\|make\ zip) archive_status="PASS" ;;
      FAIL\|make\ zip) archive_status="FAIL" ;;
    esac
  done

  local tenant_registration_result="not run"
  local ownership_transfer_result="not run"
  local ownership_acceptance_result="not run"
  local cancel_transfer_result="${ownership_cancel_status}"
  local pending_owner_rejection_result="not run"
  local old_owner_postaccept_rejection_result="not run"
  local final_owner_commit_result="not run"

  if [[ -f "${INTEGRITY_RESULT_PATH}" ]]; then
    tenant_registration_result="$(jq -r '.tenant_registration_status // "not run"' "${INTEGRITY_RESULT_PATH}")"
    ownership_transfer_result="$(jq -r '.ownership_transfer_status // "not run"' "${INTEGRITY_RESULT_PATH}")"
    ownership_acceptance_result="$(jq -r '.ownership_acceptance_status // "not run"' "${INTEGRITY_RESULT_PATH}")"
    pending_owner_rejection_result="$(jq -r '.pending_owner_commit_rejected_status // "not run"' "${INTEGRITY_RESULT_PATH}")"
    old_owner_postaccept_rejection_result="$(jq -r '.old_owner_postaccept_rejected_status // "not run"' "${INTEGRITY_RESULT_PATH}")"
    final_owner_commit_result="$(jq -r '.new_owner_postaccept_commit_status // .commit_status // "not run"' "${INTEGRITY_RESULT_PATH}")"
  fi

  {
    echo "# Phase 12.1-lite Validation Report"
    echo
    echo "- Validation generated at: ${generated_at}"
    echo "- Branch: ${branch_name}"
    echo "- Starting commit: ${starting_commit}"
    echo "- Current HEAD before report generation: ${head_before_report}"
    echo "- Go version: \`${go_version}\`"
    echo "- Docker image tag: \`${docker_image_tag}\`"
    echo
    echo "## Working Tree Status Before Validation"
    echo
    echo '```text'
    echo "${working_tree_status_before:-clean}"
    echo '```'
    echo
    echo "## Ignite Version"
    echo
    echo '```text'
    printf '%s\n' "${ignite_version}"
    echo '```'
    echo
    echo "## Results"
    echo
    for result in "${results[@]}"; do
      local status="${result%%|*}"
      local label="${result#*|}"
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
    echo "## Ownership Transfer Summary"
    echo
    echo "- Tenant ownership transfer result: ${ownership_transfer_result}"
    echo "- Pending owner acceptance result: ${ownership_acceptance_result}"
    echo "- Cancel ownership transfer result: ${cancel_transfer_result}"
    echo "- Non-owner rejection result: ${pending_owner_rejection_result}"
    echo "- Old owner post-accept rejection result: ${old_owner_postaccept_rejection_result}"
    echo "- Final new-owner commit result: ${final_owner_commit_result}"
    echo
    echo "## Integrity Smoke Summary"
    echo
    echo "- Integrity smoke result: ${integrity_smoke_status}"
    echo "- Current-run integrity smoke verification: ${current_run_status}"
    echo "- Tenant registration smoke result: ${tenant_registration_result}"
    echo
    echo "## Dependency And Security Summary"
    echo
    echo "- Dependency audit result: ${dependency_audit_status}"
    echo "- Vulnerability scan result: ${vulncheck_status}"
    echo "- No-forks result: ${no_forks_status}"
    echo "- Clean-reset result: ${clean_reset_status}"
    echo "- No-secrets result: ${no_secrets_status}"
    echo "- Generic production-module guard result: ${generic_guard_status}"
    echo
    echo "## Archive"
    echo
    echo "- Phase 12 archive: \`out/kudora-phase-12-integrity-module.zip\`"
    echo "- Latest inspection archive: \`out/kudora-latest-inspection.zip\`"
    echo "- Archive generation result: ${archive_status}"
    echo
    echo "## Confirmations"
    echo
    echo "- No secrets were committed."
    echo "- No generated local state was committed."
    echo "- Production \`x/integrity\` code remains generic."
    echo "- No registrar, governance, or freeze tenant model was added."
    echo "- No additional business module besides \`x/integrity\` was added."
    echo "- No IBC product, tokenfactory, packet-forward, rate-limit, ICA, or 08-wasm work was added."
    echo "- No Docker registry push was performed."
    echo
    echo "> Note: the final pushed commit may differ if this report itself is committed afterward."
  } >"${REPORT_PATH}"
}

run_check "Phase 12.1-lite required artifacts" check_phase121_artifacts || { write_blocker; write_report; echo "phase-12.1-lite-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make phase-12-validate" make phase-12-validate || { write_blocker; write_report; echo "phase-12.1-lite-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make tidy" make tidy || { write_blocker; write_report; echo "phase-12.1-lite-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "go mod verify" go mod verify || { write_blocker; write_report; echo "phase-12.1-lite-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make build" make build || { write_blocker; write_report; echo "phase-12.1-lite-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make test" make test || { write_blocker; write_report; echo "phase-12.1-lite-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make lint" make lint || { write_blocker; write_report; echo "phase-12.1-lite-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make verify-no-forks" make verify-no-forks || { write_blocker; write_report; echo "phase-12.1-lite-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make verify-clean-reset" make verify-clean-reset || { write_blocker; write_report; echo "phase-12.1-lite-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make verify-no-secrets" make verify-no-secrets || { write_blocker; write_report; echo "phase-12.1-lite-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make verify-integrity-generic" make verify-integrity-generic || { write_blocker; write_report; echo "phase-12.1-lite-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make dependency-audit" make dependency-audit || { write_blocker; write_report; echo "phase-12.1-lite-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make vulncheck" make vulncheck || { write_blocker; write_report; echo "phase-12.1-lite-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make docker-build" make docker-build || { write_blocker; write_report; echo "phase-12.1-lite-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make docker-smoke-test" make docker-smoke-test || { write_blocker; write_report; echo "phase-12.1-lite-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "go test ./x/integrity/keeper -run TestTenantOwnershipTransferLifecycle -count=1" go test ./x/integrity/keeper -run TestTenantOwnershipTransferLifecycle -count=1 || { write_blocker; write_report; echo "phase-12.1-lite-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "go test ./x/integrity/keeper -run TestTenantOwnershipTransferCancellationAndValidation -count=1" go test ./x/integrity/keeper -run TestTenantOwnershipTransferCancellationAndValidation -count=1 || { write_blocker; write_report; echo "phase-12.1-lite-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make integrity-smoke-test" make integrity-smoke-test || { write_blocker; write_report; echo "phase-12.1-lite-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "Phase 12.1-lite integrity smoke current-run verification" check_integrity_smoke_current_run || { write_blocker; write_report; echo "phase-12.1-lite-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make zip" make zip || { write_blocker; write_report; echo "phase-12.1-lite-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }

write_report
rm -f "${BLOCKER_PATH}"
echo "phase-12.1-lite-validate: PASS (${REPORT_PATH})"
