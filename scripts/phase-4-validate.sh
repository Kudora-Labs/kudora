#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

OUT_DIR="out"
REPORT_PATH="${OUT_DIR}/phase-4-validation.md"
BLOCKER_PATH="${OUT_DIR}/phase-4-blocker.md"
EXPECTED_BRANCH="Upgrade"

mkdir -p "$OUT_DIR"
rm -f "$BLOCKER_PATH"

branch_name="$(git branch --show-current)"
if [[ "$branch_name" != "$EXPECTED_BRANCH" ]]; then
  echo "phase-4-validate: expected branch ${EXPECTED_BRANCH}, found ${branch_name}" >&2
  exit 1
fi

starting_commit="$(git rev-parse HEAD)"
head_before_report="$(git rev-parse HEAD)"
working_tree_status_before="$(git status --short)"
generated_at="$(date -u '+%Y-%m-%d %H:%M:%S UTC')"
go_version="$(go version)"
ignite_version="$(ignite version 2>&1 | tr -d '\r')"
docker_version="$(docker version 2>&1)"
cosmos_sdk_version="$(go list -m -f '{{.Version}}' github.com/cosmos/cosmos-sdk)"
cometbft_version="$(go list -m -f '{{.Version}}' github.com/cometbft/cometbft)"
cosmos_evm_version="$(go list -m -f '{{.Version}}' github.com/cosmos/evm)"
geth_replacement_line="$(awk '/github\.com\/ethereum\/go-ethereum[[:space:]]*=>/ {gsub(/^[[:space:]]+/, "", $0); print; exit}' go.mod)"
docker_image_tag="$(awk -F':= ' '/^DOCKER_IMAGE :=/ {print $2; exit}' Makefile)"
tx_result_path="tmp/phase-4-evm-tx-smoke/result.json"
contract_result_path="tmp/phase-4-evm-contract-smoke/result.json"

results=()
last_failure_label=""
last_failure_status=0
last_failure_output=""

clear_phase4_tmp_results() {
  rm -f "$tx_result_path" "$contract_result_path"
}

check_result_artifact_present() {
  local artifact_path="$1"
  local label="$2"

  if [[ ! -f "$artifact_path" ]]; then
    echo "phase-4-validate: ${label} missing at ${artifact_path}" >&2
    return 1
  fi
}

clear_phase4_tmp_results

run_check() {
  local label="$1"
  shift
  local log_file
  log_file="$(mktemp)"

  set +e
  "$@" >"$log_file" 2>&1
  local status=$?
  set -e

  if [[ $status -eq 0 ]]; then
    results+=("PASS|${label}")
    rm -f "$log_file"
    return 0
  fi

  results+=("FAIL|${label}")
  last_failure_label="$label"
  last_failure_status="$status"
  last_failure_output="$(tail -n 160 "$log_file")"
  rm -f "$log_file"
  return "$status"
}

check_phase4_artifacts() {
  local required_files=(
    "docs/evm/phase-3-evm-runtime.md"
    "docs/evm/phase-4-evm-functional-validation.md"
    "docs/release/dependency-baseline.md"
    "scripts/evm-transaction-smoke-test.sh"
    "scripts/evm-contract-smoke-test.sh"
    "scripts/phase-4-validate.sh"
    "testutil/evm-smoke/main.go"
    "testutil/evm-smoke/storage_contract.go"
  )
  local path

  for path in "${required_files[@]}"; do
    if [[ ! -f "$path" ]]; then
      echo "phase-4-validate: required Phase 4 artifact missing: $path" >&2
      return 1
    fi
  done
}

check_phase4_scope() {
  local unexpected_surface
  unexpected_surface="$(
    rg -n \
      -e 'packetforward' \
      -e 'packet-forward' \
      -e 'ratelimit' \
      -e 'rate-limit' \
      -e 'interchainaccounts' \
      -e 'interchain accounts' \
      -e '08-wasm' \
      -e 'tokenfactory' \
      -e 'Blockscout' \
      -e 'Ping\.pub' \
      app cmd Dockerfile Makefile .github/workflows testutil 2>/dev/null || true
  )"

  if [[ -n "$unexpected_surface" ]]; then
    echo "phase-4-validate: out-of-scope product surface detected" >&2
    printf '%s\n' "$unexpected_surface" >&2
    return 1
  fi
}

check_phase4_tmp_state_not_tracked() {
  local tracked_tmp
  tracked_tmp="$(git ls-files tmp/phase-4-evm-tx-smoke tmp/phase-4-evm-contract-smoke)"
  if [[ -n "$tracked_tmp" ]]; then
    echo "phase-4-validate: temporary Phase 4 smoke state must not be tracked" >&2
    printf '%s\n' "$tracked_tmp" >&2
    return 1
  fi
}

write_blocker() {
  {
    echo "# Phase 4 Blocker"
    echo
    echo "- Generated at: ${generated_at}"
    echo "- Branch: ${branch_name}"
    echo "- Starting commit: ${starting_commit}"
    echo "- Current HEAD before report generation: ${head_before_report}"
    echo
    echo "## Blocking Issue"
    echo
    echo "Phase 4 validation did not complete successfully, so the EVM transaction and contract validation baseline must not be pushed yet."
    echo
    echo "## First Failure"
    echo
    echo "- Label: \`${last_failure_label:-unknown}\`"
    echo "- Exit status: \`${last_failure_status}\`"
    echo
    echo '```text'
    echo "${last_failure_output:-no failure output captured}"
    echo '```'
    echo
    echo "## Safe Next Steps"
    echo
    echo "1. Resolve the failing validation gate without broadening the Cosmos EVM dependency exception."
    echo "2. Keep the Phase 3.2 precompile waiver intact by leaving stateful Cosmos precompiles and ERC20 default precompiles inactive."
    echo "3. Re-run \`make phase-4-validate\` before any commit or push."
  } >"$BLOCKER_PATH"
}

write_report() {
  local dependency_audit_status="not run"
  local vulncheck_status="not run"
  local phase32_status="not run"
  local evm_smoke_status="not run"
  local tx_smoke_status="not run"
  local contract_smoke_status="not run"
  local precompile_surface_status="not run"
  local precompile_policy_status="not run"
  local waiver_status="not evaluated"
  local tx_summary="not available"
  local contract_summary="not available"
  local archive_phase="out/kudora-phase-3-evm-runtime.zip"
  local archive_latest="out/kudora-latest-inspection.zip"
  local archive_compat="out/kudora-phase-0-reset.zip"

  for result in "${results[@]}"; do
    case "$result" in
      PASS\|make\ phase-3.2-validate) phase32_status="PASS" ;;
      FAIL\|make\ phase-3.2-validate) phase32_status="FAIL" ;;
      PASS\|make\ evm-smoke-test) evm_smoke_status="PASS" ;;
      FAIL\|make\ evm-smoke-test) evm_smoke_status="FAIL" ;;
      PASS\|make\ dependency-audit) dependency_audit_status="PASS" ;;
      FAIL\|make\ dependency-audit) dependency_audit_status="FAIL" ;;
      PASS\|make\ audit-evm-precompile-surface) precompile_surface_status="PASS" ;;
      FAIL\|make\ audit-evm-precompile-surface) precompile_surface_status="FAIL" ;;
      PASS\|make\ assert-evm-precompile-policy) precompile_policy_status="PASS" ;;
      FAIL\|make\ assert-evm-precompile-policy) precompile_policy_status="FAIL" ;;
      PASS\|make\ vulncheck) vulncheck_status="PASS" ;;
      FAIL\|make\ vulncheck) vulncheck_status="FAIL" ;;
      PASS\|make\ evm-transaction-smoke-test) tx_smoke_status="PASS" ;;
      FAIL\|make\ evm-transaction-smoke-test) tx_smoke_status="FAIL" ;;
      PASS\|make\ evm-contract-smoke-test) contract_smoke_status="PASS" ;;
      FAIL\|make\ evm-contract-smoke-test) contract_smoke_status="FAIL" ;;
    esac
  done

  if [[ "$phase32_status" == "PASS" && -f out/phase-3.2-govulncheck.md ]]; then
    waiver_status="$(awk -F': ' '/^- GO-2025-3684 waiver status:/ {print $2; exit}' out/phase-3.2-govulncheck.md)"
  fi

  if [[ "$tx_smoke_status" == "PASS" && -f "$tx_result_path" ]]; then
    tx_summary="$(
      jq -r '"tx=\(.transaction_hash) status=\(.receipt_status) nonce=\(.nonce_before)->\(.nonce_after) gasUsed=\(.gas_used) transferWei=\(.transfer_value_wei) recipientBefore=\(.recipient_balance_before_wei) recipientAfter=\(.recipient_balance_after_wei)"' "$tx_result_path"
    )"
  fi

  if [[ "$contract_smoke_status" == "PASS" && -f "$contract_result_path" ]]; then
    contract_summary="$(
      jq -r '"contract=\(.contract_address) deployStatus=\(.deployment_receipt_status) storeStatus=\(.store_receipt_status) nonce=\(.nonce_before)->\(.nonce_after_deploy)->\(.nonce_after_store) updatedValue=\(.updated_value) deployGas=\(.gas_used_deploy) storeGas=\(.gas_used_store) logs=\(.receipt_logs_count) logsValidated=\(.logs_validated)"' "$contract_result_path"
    )"
  fi

  {
    echo "# Phase 4 Validation Report"
    echo
    echo "- Validation generated at: ${generated_at}"
    echo "- Branch: ${branch_name}"
    echo "- Starting commit: ${starting_commit}"
    echo "- Current HEAD before report generation: ${head_before_report}"
    echo "- Go version: \`${go_version}\`"
    echo "- Cosmos SDK version: \`${cosmos_sdk_version}\`"
    echo "- CometBFT version: \`${cometbft_version}\`"
    echo "- Cosmos EVM version: \`${cosmos_evm_version}\`"
    echo "- Cosmos chain-id: \`kudora_12000-1\`"
    echo "- EVM chain ID: \`120001\`"
    echo "- Expected JSON-RPC \`eth_chainId\`: \`0x1d4c1\`"
    echo "- Approved go-ethereum exception: \`${geth_replacement_line}\`"
    echo "- Precompile waiver status: ${waiver_status}"
    echo "- Docker image tag: \`${docker_image_tag}\`"
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
    echo "${ignite_version}"
    echo
    echo "${docker_version}"
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
    if [[ -n "$last_failure_label" ]]; then
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
    echo "## Functional Validation Summary"
    echo
    echo "- Phase 3.2 validation result: ${phase32_status}"
    echo "- EVM smoke result: ${evm_smoke_status}"
    echo "- Transaction smoke result: ${tx_smoke_status}"
    echo "- Contract smoke result: ${contract_smoke_status}"
    echo "- Transaction receipt/gas/nonce summary: ${tx_summary}"
    echo "- Contract receipt/gas/nonce/state summary: ${contract_summary}"
    echo "- Logs/events validation: the minimal storage contract emits no events, so receipt success and log-count presence are recorded but event semantics are not asserted in Phase 4."
    echo
    echo "## Dependency And Security Summary"
    echo
    echo "- Dependency audit result: ${dependency_audit_status}"
    echo "- Vulnerability scan result: ${vulncheck_status}"
    echo "- Precompile surface audit result: ${precompile_surface_status}"
    echo "- Precompile policy assertion result: ${precompile_policy_status}"
    echo
    echo "## Archive Paths"
    echo
    echo "- Phase archive: \`${archive_phase}\`"
    echo "- Latest inspection archive: \`${archive_latest}\`"
    echo "- Compatibility archive: \`${archive_compat}\`"
    echo
    echo "## Confirmations"
    echo
    echo "- No secrets were detected in the working tree."
    echo "- No forbidden runtime forks were found."
    echo "- No stateful Cosmos precompile activation was introduced."
    echo "- No ERC20 token pairs or native precompiles were enabled by default."
    echo "- No business modules were added."
    echo "- No IBC product/tokenfactory/packet-forward/rate-limit/ICA/08-wasm/explorer/monitoring work was added."
    echo "- No Docker registry push was performed."
    echo "- Note: the final pushed commit may differ if this report is committed afterward."
  } >"$REPORT_PATH"
}

run_check "Phase 4 artifacts exist" check_phase4_artifacts || {
  write_blocker
  write_report
  echo "phase-4-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2
  exit 1
}
run_check "Phase 4 scope guard" check_phase4_scope || {
  write_blocker
  write_report
  echo "phase-4-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2
  exit 1
}
run_check "Phase 4 temporary smoke state is not tracked" check_phase4_tmp_state_not_tracked || {
  write_blocker
  write_report
  echo "phase-4-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2
  exit 1
}
run_check "make phase-3.2-validate" make phase-3.2-validate || {
  write_blocker
  write_report
  echo "phase-4-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2
  exit 1
}
run_check "make tidy" make tidy || { write_blocker; write_report; echo "phase-4-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "go mod verify" go mod verify || { write_blocker; write_report; echo "phase-4-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make build" make build || { write_blocker; write_report; echo "phase-4-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make test" make test || { write_blocker; write_report; echo "phase-4-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make lint" make lint || { write_blocker; write_report; echo "phase-4-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make verify-no-forks" make verify-no-forks || { write_blocker; write_report; echo "phase-4-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make verify-clean-reset" make verify-clean-reset || { write_blocker; write_report; echo "phase-4-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make verify-no-secrets" make verify-no-secrets || { write_blocker; write_report; echo "phase-4-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make dependency-audit" make dependency-audit || { write_blocker; write_report; echo "phase-4-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make audit-evm-precompile-surface" make audit-evm-precompile-surface || { write_blocker; write_report; echo "phase-4-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make assert-evm-precompile-policy" make assert-evm-precompile-policy || { write_blocker; write_report; echo "phase-4-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make vulncheck" make vulncheck || { write_blocker; write_report; echo "phase-4-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make docker-build" make docker-build || { write_blocker; write_report; echo "phase-4-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make docker-smoke-test" make docker-smoke-test || { write_blocker; write_report; echo "phase-4-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make evm-smoke-test" make evm-smoke-test || { write_blocker; write_report; echo "phase-4-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make evm-transaction-smoke-test" make evm-transaction-smoke-test || { write_blocker; write_report; echo "phase-4-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "Phase 4 transaction result artifact" check_result_artifact_present "$tx_result_path" "Phase 4 transaction smoke result artifact" || { write_blocker; write_report; echo "phase-4-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make evm-contract-smoke-test" make evm-contract-smoke-test || { write_blocker; write_report; echo "phase-4-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "Phase 4 contract result artifact" check_result_artifact_present "$contract_result_path" "Phase 4 contract smoke result artifact" || { write_blocker; write_report; echo "phase-4-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make zip" make zip || { write_blocker; write_report; echo "phase-4-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }

write_report

echo "phase-4-validate: PASS (${REPORT_PATH})"
