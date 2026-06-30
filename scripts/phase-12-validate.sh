#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

source "${ROOT_DIR}/deploy/localnet/scripts/common.sh"
source "${ROOT_DIR}/scripts/localnet-validation-common.sh"
source "${ROOT_DIR}/deploy/explorers/common.sh"

OUT_DIR="out"
REPORT_PATH="${OUT_DIR}/phase-12-validation.md"
BLOCKER_PATH="${OUT_DIR}/phase-12-blocker.md"
EXPECTED_BRANCH="Upgrade"
INTEGRITY_RESULT_PATH="${LOCALNET_SMOKE_DIR}/integrity-smoke/result.json"
SCAFFOLD_COMMANDS_FILE="$(mktemp)"
MANUAL_DEVIATIONS_FILE="$(mktemp)"

cat <<'EOF' >"${SCAFFOLD_COMMANDS_FILE}"
ignite scaffold module integrity --dep bank -p .
ignite scaffold chain github.com/Kudora-Labs/kudora --address-prefix kudo --coin-type 60 --default-denom akud --no-module --skip-git -p <temporary-scaffold-dir>
ignite scaffold module integrity --dep bank -p <temporary-scaffold-dir> -y
ignite scaffold type integrity-record tag nonce ciphertext --module integrity --no-message -p <temporary-scaffold-dir> -y
ignite scaffold message register-tenant tenant --module integrity -p <temporary-scaffold-dir> -y
ignite scaffold message commit-integrity-set tenant dataset-type period root --module integrity -p <temporary-scaffold-dir> -y
ignite scaffold query tenant tenant --module integrity -p <temporary-scaffold-dir> -y
ignite scaffold query integrity-set tenant dataset-type period --module integrity -p <temporary-scaffold-dir> -y
ignite scaffold query integrity-record tenant dataset-type period tag --module integrity -p <temporary-scaffold-dir> -y
EOF

cat <<'EOF' >"${MANUAL_DEVIATIONS_FILE}"
- The current Kudora repository is manually wired and does not contain Ignite injection hooks, so the scaffold had to be generated in a disposable temporary chain and then applied back into this repository.
- Ignite could not express a field literally named `type` through the scaffold command, so the scaffolded `dataset_type` field was manually refined to `type` in the proto and keeper layers.
- The repeated `records []IntegrityRecord` payload plus richer full-set and single-record query responses required manual proto and keeper refinement after scaffold.
- Kudora's runtime command tree does not consume AutoCLI directly, so the scaffolded module still needed explicit `cmd/kudorad` CLI wiring.
EOF

mkdir -p "${OUT_DIR}"
rm -f "${BLOCKER_PATH}" "${REPORT_PATH}"
rm -rf "${LOCALNET_SMOKE_DIR}/integrity-smoke" "${LOCALNET_SMOKE_DIR}/phase-13-smoke"
rm -rf "${BLOCKSCOUT_RESULT_DIR}" "${PING_DASHBOARD_RESULT_DIR}"

branch_name="$(git branch --show-current)"
if [[ "${branch_name}" != "${EXPECTED_BRANCH}" ]]; then
  echo "phase-12-validate: expected branch ${EXPECTED_BRANCH}, found ${branch_name}" >&2
  exit 1
fi

starting_commit="$(git rev-parse HEAD)"
head_before_report="$(git rev-parse HEAD)"
working_tree_status_before="$(git status --short)"
generated_at="$(date -u '+%Y-%m-%d %H:%M:%S UTC')"
validation_start_epoch="$(date +%s)"
go_version="$(go version)"
ignite_version="$(ignite version 2>&1 | sed 's/\t/ /g')"
cosmos_sdk_version="$(go list -m -f '{{.Version}}' github.com/cosmos/cosmos-sdk)"
cometbft_version="$(go list -m -f '{{.Version}}' github.com/cometbft/cometbft)"
cosmos_evm_version="$(go list -m -f '{{.Version}}' github.com/cosmos/evm)"
wasmd_version="$(go list -m -f '{{.Version}}' github.com/CosmWasm/wasmd)"
docker_image_tag="$(awk -F':= ' '/^DOCKER_IMAGE :=/ {print $2; exit}' Makefile)"

results=()
last_failure_label=""
last_failure_status=0
last_failure_output=""

cleanup() {
  make explorers-down >/dev/null 2>&1 || true
  make localnet-down >/dev/null 2>&1 || true
  rm -f "${SCAFFOLD_COMMANDS_FILE}" "${MANUAL_DEVIATIONS_FILE}"
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

check_phase12_artifacts() {
  local required_files=(
    "docs/modules/phase-12-integrity.md"
    "scripts/integrity-smoke-test.sh"
    "scripts/verify-integrity-generic.sh"
    "scripts/phase-12-validate.sh"
    "proto/kudora/integrity/v1/tx.proto"
    "proto/kudora/integrity/v1/query.proto"
    "proto/kudora/integrity/v1/integrity_record.proto"
    "proto/kudora/integrity/v1/integrity_set.proto"
    "proto/kudora/integrity/v1/tenant.proto"
    "proto/kudora/integrity/v1/genesis.proto"
    "x/integrity/keeper/msg_server_register_tenant.go"
    "x/integrity/keeper/msg_server_commit_integrity_set.go"
    "x/integrity/types/validation.go"
    "x/integrity/types/canonical.go"
    "x/integrity/types/merkle.go"
    "x/integrity/client/cli/tx.go"
    "x/integrity/client/cli/query.go"
    "testutil/integritymock/mock.go"
    "testutil/integrity-smoke/main.go"
  )
  local path

  for path in "${required_files[@]}"; do
    [[ -f "${path}" ]] || {
      echo "phase-12-validate: required artifact missing: ${path}" >&2
      return 1
    }
  done
}

check_business_module_whitelist() {
  mapfile -t module_dirs < <(find x -mindepth 1 -maxdepth 1 -type d | sort)
  mapfile -t proto_dirs < <(find proto/kudora -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort)

  if [[ ${#module_dirs[@]} -ne 1 || "${module_dirs[0]}" != "x/integrity" ]]; then
    echo "phase-12-validate: only x/integrity is allowed as a business module in Phase 12" >&2
    printf '%s\n' "${module_dirs[@]}" >&2
    return 1
  fi

  if [[ ${#proto_dirs[@]} -ne 1 || "${proto_dirs[0]}" != "proto/kudora/integrity" ]]; then
    echo "phase-12-validate: only proto/kudora/integrity is allowed as a custom proto namespace in Phase 12" >&2
    printf '%s\n' "${proto_dirs[@]}" >&2
    return 1
  fi
}

check_integrity_smoke_current_run() {
  [[ -f "${INTEGRITY_RESULT_PATH}" ]] || {
    echo "phase-12-validate: integrity smoke result missing at ${INTEGRITY_RESULT_PATH}" >&2
    return 1
  }

  local mtime
  mtime="$(localnet_validation_file_mtime "${INTEGRITY_RESULT_PATH}")"
  (( mtime >= validation_start_epoch )) || {
    echo "phase-12-validate: integrity smoke result is stale" >&2
    return 1
  }

  jq -e --argjson start "${validation_start_epoch}" '
    (.run_id // "" | length > 0) and
    .run_started_epoch >= $start and
    .run_finished_epoch >= .run_started_epoch and
    .tenant_registration_status == "PASS" and
    ((.commit_status // .new_owner_postaccept_commit_status // "") == "PASS") and
    .root_match_status == "PASS" and
    .records_sorted_status == "PASS" and
    .record_query_status == "PASS" and
    .plaintext_leak_status == "PASS"
  ' "${INTEGRITY_RESULT_PATH}" >/dev/null || {
    echo "phase-12-validate: integrity smoke result is incomplete or failed" >&2
    return 1
  }
}

check_blockscout_result_current_run() {
  [[ -f "${BLOCKSCOUT_RESULT_PATH}" ]] || {
    echo "phase-12-validate: Blockscout result missing at ${BLOCKSCOUT_RESULT_PATH}" >&2
    return 1
  }

  local mtime
  mtime="$(explorer_file_mtime "${BLOCKSCOUT_RESULT_PATH}")"
  (( mtime >= validation_start_epoch )) || {
    echo "phase-12-validate: Blockscout result is stale" >&2
    return 1
  }

  jq -e --argjson start "${validation_start_epoch}" '
    (.run_id // "" | length > 0) and
    .run_started_epoch >= $start and
    .run_finished_epoch >= .run_started_epoch and
    .frontend_status == "PASS" and
    .api_status == "PASS" and
    .indexing_status == "PASS" and
    (.latest_indexed_block // 0) > 0 and
    ((.transaction_visibility_status == "PASS") or (.transaction_visibility_status == "NOT_OBSERVED"))
  ' "${BLOCKSCOUT_RESULT_PATH}" >/dev/null || {
    echo "phase-12-validate: Blockscout smoke result is incomplete or stale" >&2
    return 1
  }
}

check_ping_result_current_run() {
  [[ -f "${PING_DASHBOARD_RESULT_PATH}" ]] || {
    echo "phase-12-validate: Ping Dashboard result missing at ${PING_DASHBOARD_RESULT_PATH}" >&2
    return 1
  }

  local mtime
  mtime="$(explorer_file_mtime "${PING_DASHBOARD_RESULT_PATH}")"
  (( mtime >= validation_start_epoch )) || {
    echo "phase-12-validate: Ping Dashboard result is stale" >&2
    return 1
  }

  jq -e --argjson start "${validation_start_epoch}" '
    (.run_id // "" | length > 0) and
    .run_started_epoch >= $start and
    .run_finished_epoch >= .run_started_epoch and
    .frontend_status == "PASS" and
    .chain_presence_status == "PASS" and
    .endpoint_reachability_status == "PASS" and
    .configured_chain == "Kudora Localnet"
  ' "${PING_DASHBOARD_RESULT_PATH}" >/dev/null || {
    echo "phase-12-validate: Ping Dashboard smoke result is incomplete or stale" >&2
    return 1
  }
}

write_blocker() {
  {
    echo "# Phase 12 Blocker"
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
  local build_status="not run"
  local test_status="not run"
  local lint_status="not run"
  local no_forks_status="not run"
  local clean_reset_status="not run"
  local no_secrets_status="not run"
  local dependency_audit_status="not run"
  local vulncheck_status="not run"
  local precompile_surface_status="not run"
  local precompile_policy_status="not run"
  local docker_build_status="not run"
  local docker_smoke_status="not run"
  local localnet_smoke_status="not run"
  local integrity_smoke_status="not run"
  local explorers_smoke_status="not run"
  local generic_guard_status="not run"
  local module_whitelist_status="not run"
  local archive_status="not run"
  local root_recalculation_status="not run"
  local canonicalization_status="not run"
  local tenant_registration_smoke_status="not run"
  local integrity_commit_smoke_status="not run"
  local full_set_query_status="not run"
  local record_query_status="not run"
  local plaintext_leak_status="not run"

  for result in "${results[@]}"; do
    case "${result}" in
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
      PASS\|make\ dependency-audit) dependency_audit_status="PASS" ;;
      FAIL\|make\ dependency-audit) dependency_audit_status="FAIL" ;;
      PASS\|make\ vulncheck) vulncheck_status="PASS" ;;
      FAIL\|make\ vulncheck) vulncheck_status="FAIL" ;;
      PASS\|make\ audit-evm-precompile-surface) precompile_surface_status="PASS" ;;
      FAIL\|make\ audit-evm-precompile-surface) precompile_surface_status="FAIL" ;;
      PASS\|make\ assert-evm-precompile-policy) precompile_policy_status="PASS" ;;
      FAIL\|make\ assert-evm-precompile-policy) precompile_policy_status="FAIL" ;;
      PASS\|make\ docker-build) docker_build_status="PASS" ;;
      FAIL\|make\ docker-build) docker_build_status="FAIL" ;;
      PASS\|make\ docker-smoke-test) docker_smoke_status="PASS" ;;
      FAIL\|make\ docker-smoke-test) docker_smoke_status="FAIL" ;;
      PASS\|make\ localnet-smoke-test) localnet_smoke_status="PASS" ;;
      FAIL\|make\ localnet-smoke-test) localnet_smoke_status="FAIL" ;;
      PASS\|make\ integrity-smoke-test) integrity_smoke_status="PASS" ;;
      FAIL\|make\ integrity-smoke-test) integrity_smoke_status="FAIL" ;;
      PASS\|make\ explorers-smoke-test) explorers_smoke_status="PASS" ;;
      FAIL\|make\ explorers-smoke-test) explorers_smoke_status="FAIL" ;;
      PASS\|make\ verify-integrity-generic) generic_guard_status="PASS" ;;
      FAIL\|make\ verify-integrity-generic) generic_guard_status="FAIL" ;;
      PASS\|Phase\ 12\ business-module\ whitelist) module_whitelist_status="PASS" ;;
      FAIL\|Phase\ 12\ business-module\ whitelist) module_whitelist_status="FAIL" ;;
      PASS\|make\ zip) archive_status="PASS" ;;
      FAIL\|make\ zip) archive_status="FAIL" ;;
    esac
  done

  if [[ -f "${INTEGRITY_RESULT_PATH}" ]]; then
    tenant_registration_smoke_status="$(jq -r '.tenant_registration_status // "not run"' "${INTEGRITY_RESULT_PATH}")"
    integrity_commit_smoke_status="$(jq -r '(.commit_status // .new_owner_postaccept_commit_status // "not run")' "${INTEGRITY_RESULT_PATH}")"
    root_recalculation_status="$(jq -r '.root_match_status // "not run"' "${INTEGRITY_RESULT_PATH}")"
    canonicalization_status="$(jq -r '.records_sorted_status // "not run"' "${INTEGRITY_RESULT_PATH}")"
    record_query_status="$(jq -r '.record_query_status // "not run"' "${INTEGRITY_RESULT_PATH}")"
    plaintext_leak_status="$(jq -r '.plaintext_leak_status // "not run"' "${INTEGRITY_RESULT_PATH}")"
    if [[ "${root_recalculation_status}" == "PASS" && "${canonicalization_status}" == "PASS" ]]; then
      full_set_query_status="PASS"
    else
      full_set_query_status="FAIL"
    fi
  fi

  {
    echo "# Phase 12 Validation Report"
    echo
    echo "- Validation generated at: ${generated_at}"
    echo "- Branch: ${branch_name}"
    echo "- Starting commit: ${starting_commit}"
    echo "- Current HEAD before report generation: ${head_before_report}"
    echo "- Go version: \`${go_version}\`"
    echo "- Cosmos SDK version: \`${cosmos_sdk_version}\`"
    echo "- CometBFT version: \`${cometbft_version}\`"
    echo "- Cosmos EVM version: \`${cosmos_evm_version}\`"
    echo "- Wasmd version: \`${wasmd_version}\`"
    echo "- Cosmos chain-id: \`${LOCALNET_CHAIN_ID}\`"
    echo "- EVM chain ID: \`${LOCALNET_EVM_CHAIN_ID}\`"
    echo "- x/integrity module status: \`${module_whitelist_status}\`"
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
    echo "## Ignite Scaffold Commands Used"
    echo
    echo '```bash'
    cat "${SCAFFOLD_COMMANDS_FILE}"
    echo '```'
    echo
    echo "## Manual Deviations From Scaffold"
    echo
    cat "${MANUAL_DEVIATIONS_FILE}"
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
    echo "## Integrity Module Summary"
    echo
    echo "- Tenant registration smoke result: ${tenant_registration_smoke_status}"
    echo "- Integrity commit smoke result: ${integrity_commit_smoke_status}"
    echo "- Full set query result: ${full_set_query_status}"
    echo "- Record by tag query result: ${record_query_status}"
    echo "- Root recalculation result: ${root_recalculation_status}"
    echo "- Canonicalization result: ${canonicalization_status}"
    echo "- Generic module guard result: ${generic_guard_status}"
    echo "- Plaintext leak guard result: ${plaintext_leak_status}"
    echo
    echo "## Runtime Preservation Summary"
    echo
    echo "- Localnet smoke result: ${localnet_smoke_status}"
    echo "- Explorers smoke result: ${explorers_smoke_status}"
    echo "- Docker build result: ${docker_build_status}"
    echo "- Docker smoke result: ${docker_smoke_status}"
    echo "- EVM precompile surface audit result: ${precompile_surface_status}"
    echo "- EVM precompile policy assertion result: ${precompile_policy_status}"
    echo
    echo "## Dependency And Security Summary"
    echo
    echo "- Dependency audit result: ${dependency_audit_status}"
    echo "- Vulnerability scan result: ${vulncheck_status}"
    echo "- No-forks result: ${no_forks_status}"
    echo "- Clean-reset result: ${clean_reset_status}"
    echo "- No-secrets result: ${no_secrets_status}"
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
    echo "- No forbidden forks were introduced."
    echo "- No plaintext Orbitrum-like business data is stored by \`x/integrity\`; only encrypted \`tag\`, \`nonce\`, and \`ciphertext\` are persisted."
    echo "- No business module other than \`x/integrity\` was added."
    echo "- No IBC product, tokenfactory, packet-forward, rate-limit, ICA, or 08-wasm work was added."
    echo "- No Docker registry push was performed."
    echo
    echo "> Note: the final pushed commit may differ if this report itself is committed afterward."
  } >"${REPORT_PATH}"
}

run_check "Phase 12 required artifacts" check_phase12_artifacts || { write_blocker; write_report; echo "phase-12-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "Phase 12 business-module whitelist" check_business_module_whitelist || { write_blocker; write_report; echo "phase-12-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make tidy" make tidy || { write_blocker; write_report; echo "phase-12-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "go mod verify" go mod verify || { write_blocker; write_report; echo "phase-12-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make build" make build || { write_blocker; write_report; echo "phase-12-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make test" make test || { write_blocker; write_report; echo "phase-12-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make lint" make lint || { write_blocker; write_report; echo "phase-12-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make verify-no-forks" make verify-no-forks || { write_blocker; write_report; echo "phase-12-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make verify-clean-reset" make verify-clean-reset || { write_blocker; write_report; echo "phase-12-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make verify-no-secrets" make verify-no-secrets || { write_blocker; write_report; echo "phase-12-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make verify-integrity-generic" make verify-integrity-generic || { write_blocker; write_report; echo "phase-12-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make dependency-audit" make dependency-audit || { write_blocker; write_report; echo "phase-12-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make vulncheck" make vulncheck || { write_blocker; write_report; echo "phase-12-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make audit-evm-precompile-surface" make audit-evm-precompile-surface || { write_blocker; write_report; echo "phase-12-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make assert-evm-precompile-policy" make assert-evm-precompile-policy || { write_blocker; write_report; echo "phase-12-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make docker-build" make docker-build || { write_blocker; write_report; echo "phase-12-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make docker-smoke-test" make docker-smoke-test || { write_blocker; write_report; echo "phase-12-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make localnet-reset" make localnet-reset || { write_blocker; write_report; echo "phase-12-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make localnet-init" make localnet-init || { write_blocker; write_report; echo "phase-12-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make localnet-up" make localnet-up || { write_blocker; write_report; echo "phase-12-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make localnet-smoke-test" make localnet-smoke-test || { write_blocker; write_report; echo "phase-12-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "Phase 12 localnet smoke current-run verification" localnet_validation_check_smoke_current_run || { write_blocker; write_report; echo "phase-12-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make integrity-smoke-test" env KUDORA_USE_EXISTING_NODE=1 KUDORA_HOME="${LOCALNET_HOME}" KUDORA_RPC_URL="${LOCALNET_RPC_URL}" KUDORA_EVM_RPC_URL="${LOCALNET_EVM_RPC_URL}" KUDORA_CHAIN_ID="${LOCALNET_CHAIN_ID}" KUDORA_EVM_CHAIN_ID="${LOCALNET_EVM_CHAIN_ID}" KUDORA_ETH_CHAIN_ID="${LOCALNET_ETH_CHAIN_ID}" KUDORA_RESULT_DIR="${LOCALNET_SMOKE_DIR}" make integrity-smoke-test || { write_blocker; write_report; echo "phase-12-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "Phase 12 integrity smoke current-run verification" check_integrity_smoke_current_run || { write_blocker; write_report; echo "phase-12-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make explorers-reset" make explorers-reset || { write_blocker; write_report; echo "phase-12-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make explorers-up" make explorers-up || { write_blocker; write_report; echo "phase-12-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make explorers-smoke-test" make explorers-smoke-test || { write_blocker; write_report; echo "phase-12-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "Phase 12 Blockscout current-run result" check_blockscout_result_current_run || { write_blocker; write_report; echo "phase-12-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "Phase 12 Ping current-run result" check_ping_result_current_run || { write_blocker; write_report; echo "phase-12-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make explorers-down" make explorers-down || { write_blocker; write_report; echo "phase-12-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make localnet-down" make localnet-down || { write_blocker; write_report; echo "phase-12-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make zip" make zip || { write_blocker; write_report; echo "phase-12-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }

write_report
rm -f "${BLOCKER_PATH}"
echo "phase-12-validate: PASS (${REPORT_PATH})"
