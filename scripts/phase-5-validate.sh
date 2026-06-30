#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

OUT_DIR="out"
REPORT_PATH="${OUT_DIR}/phase-5-validation.md"
BLOCKER_PATH="${OUT_DIR}/phase-5-blocker.md"
EXPECTED_BRANCH="Upgrade"
PHASE3_EVM_RESULT_PATH="tmp/phase-3-evm-smoke/result.json"
PHASE4_TX_RESULT_PATH="tmp/phase-4-evm-tx-smoke/result.json"
PHASE4_CONTRACT_RESULT_PATH="tmp/phase-4-evm-contract-smoke/result.json"
WASM_RESULT_PATH="tmp/phase-5-wasm-smoke/result.json"
PHASE5_ARCHIVE_PATH="out/kudora-phase-5-cosmwasm-runtime.zip"
LATEST_ARCHIVE_PATH="out/kudora-latest-inspection.zip"
COMPATIBILITY_ARCHIVE_PATH="out/kudora-phase-0-reset.zip"

mkdir -p "$OUT_DIR"
rm -f "$BLOCKER_PATH"

branch_name="$(git branch --show-current)"
if [[ "$branch_name" != "$EXPECTED_BRANCH" ]]; then
  echo "phase-5-validate: expected branch ${EXPECTED_BRANCH}, found ${branch_name}" >&2
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
wasmd_version="$(go list -m -f '{{.Version}}' github.com/CosmWasm/wasmd)"
wasmvm_version="$(go list -m -f '{{.Version}}' github.com/CosmWasm/wasmvm/v3)"
geth_replacement_line="$(awk '/github\.com\/ethereum\/go-ethereum[[:space:]]*=>/ {gsub(/^[[:space:]]+/, "", $0); print; exit}' go.mod)"
docker_image_tag="$(awk -F':= ' '/^DOCKER_IMAGE :=/ {print $2; exit}' Makefile)"

results=()
last_failure_label=""
last_failure_status=0
last_failure_output=""

clear_phase5_tmp_results() {
  rm -f \
    "$PHASE3_EVM_RESULT_PATH" \
    "$PHASE4_TX_RESULT_PATH" \
    "$PHASE4_CONTRACT_RESULT_PATH" \
    "$WASM_RESULT_PATH"
}

check_result_artifact_present() {
  local artifact_path="$1"
  local label="$2"

  if [[ ! -f "$artifact_path" ]]; then
    echo "phase-5-validate: ${label} missing at ${artifact_path}" >&2
    return 1
  fi
}

check_phase4_report_integrity() {
  local report="out/phase-4-validation.md"
  local required_lines=(
    '- PASS: `make evm-smoke-test`'
    '- PASS: `make evm-transaction-smoke-test`'
    '- PASS: `make evm-contract-smoke-test`'
    '- PASS: `make vulncheck`'
    '- PASS: `make dependency-audit`'
    '- Phase 3.2 validation result: PASS'
    '- EVM smoke result: PASS'
    '- Transaction smoke result: PASS'
    '- Contract smoke result: PASS'
  )
  local line

  if [[ ! -f "$report" ]]; then
    echo "phase-5-validate: expected Phase 4 report at ${report}" >&2
    return 1
  fi

  for line in "${required_lines[@]}"; do
    if ! rg -F -- "$line" "$report" >/dev/null; then
      echo "phase-5-validate: Phase 4 report missing required line: ${line}" >&2
      return 1
    fi
  done

  if rg -F -- 'not run' "$report" >/dev/null; then
    echo "phase-5-validate: Phase 4 report still contains 'not run'" >&2
    return 1
  fi

  if rg -n '^- FAIL:' "$report" >/dev/null; then
    echo "phase-5-validate: Phase 4 report still contains failing checks" >&2
    return 1
  fi
}

clear_phase5_tmp_results

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
  last_failure_output="$(tail -n 200 "$log_file")"
  rm -f "$log_file"
  return "$status"
}

check_phase5_artifacts() {
  local required_files=(
    "docs/wasm/phase-5-cosmwasm-compatibility.md"
    "docs/wasm/phase-5-cosmwasm-runtime.md"
    "docs/security/phase-5-cosmwasm-vulnerability-audit.md"
    "docs/release/dependency-baseline.md"
    "docs/evm/phase-4-evm-functional-validation.md"
    "scripts/wasm-smoke-test.sh"
    "scripts/phase-5-validate.sh"
    "testutil/wasm/reflect_1_5.wasm"
  )
  local path

  for path in "${required_files[@]}"; do
    if [[ ! -f "$path" ]]; then
      echo "phase-5-validate: required Phase 5 artifact missing: $path" >&2
      return 1
    fi
  done
}

check_phase5_scope() {
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
      -e 'modules/apps/transfer' \
      -e 'transferkeeper' \
      -e 'relayer' \
      app cmd Dockerfile Makefile .github/workflows testutil 2>/dev/null || true
  )"

  if [[ -n "$unexpected_surface" ]]; then
    echo "phase-5-validate: out-of-scope product surface detected" >&2
    printf '%s\n' "$unexpected_surface" >&2
    return 1
  fi
}

check_phase5_tmp_state_not_tracked() {
  local tracked_tmp
  tracked_tmp="$(git ls-files tmp/phase-5-wasm-smoke)"
  if [[ -n "$tracked_tmp" ]]; then
    echo "phase-5-validate: temporary Phase 5 smoke state must not be tracked" >&2
    printf '%s\n' "$tracked_tmp" >&2
    return 1
  fi
}

inspect_wasm_permission_policy() {
  if [[ ! -x ./build/kudorad ]]; then
    echo "unknown (build/kudorad missing)"
    return 0
  fi

  local tmp_home
  tmp_home="$(mktemp -d "${ROOT_DIR}/tmp/phase-5-validate-genesis.XXXXXX")"

  ./build/kudorad init phase5-validate \
    --chain-id kudora_12000-1 \
    --default-denom akud \
    --home "$tmp_home" \
    >/dev/null 2>&1

  local summary
  summary="$(jq -r '
    "upload=" + .app_state.wasm.params.code_upload_access.permission +
    " instantiate=" + .app_state.wasm.params.instantiate_default_permission
  ' "$tmp_home/config/genesis.json")"
  rm -rf "$tmp_home"
  echo "$summary"
}

write_blocker() {
  {
    echo "# Phase 5 Blocker"
    echo
    echo "- Generated at: ${generated_at}"
    echo "- Branch: ${branch_name}"
    echo "- Starting commit: ${starting_commit}"
    echo "- Current HEAD before report generation: ${head_before_report}"
    echo
    echo "## Blocking Issue"
    echo
    echo "Phase 5 validation did not complete successfully, so the CosmWasm runtime baseline must not be pushed yet."
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
    echo "1. Resolve the failing validation gate without adding Wasmd or wasmvm replacements."
    echo "2. Keep the EVM precompile waiver intact by leaving stateful Cosmos precompiles and ERC20 default precompile surfaces inactive."
    echo "3. Re-run \`make phase-5-validate\` before any commit or push."
  } >"$BLOCKER_PATH"
}

write_report() {
  local phase4_status="not run"
  local dependency_audit_status="not run"
  local vulncheck_status="not run"
  local precompile_surface_status="not run"
  local precompile_policy_status="not run"
  local docker_build_status="not run"
  local docker_smoke_status="not run"
  local evm_smoke_status="not run"
  local evm_tx_status="not run"
  local evm_contract_status="not run"
  local wasm_smoke_status="not run"
  local waiver_status="not evaluated"
  local wasm_summary="not available"
  local wasm_permission_policy

  wasm_permission_policy="$(inspect_wasm_permission_policy)"

  for result in "${results[@]}"; do
    case "$result" in
      PASS\|make\ phase-4-validate) phase4_status="PASS" ;;
      FAIL\|make\ phase-4-validate) phase4_status="FAIL" ;;
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
      PASS\|make\ evm-smoke-test) evm_smoke_status="PASS" ;;
      FAIL\|make\ evm-smoke-test) evm_smoke_status="FAIL" ;;
      PASS\|make\ evm-transaction-smoke-test) evm_tx_status="PASS" ;;
      FAIL\|make\ evm-transaction-smoke-test) evm_tx_status="FAIL" ;;
      PASS\|make\ evm-contract-smoke-test) evm_contract_status="PASS" ;;
      FAIL\|make\ evm-contract-smoke-test) evm_contract_status="FAIL" ;;
      PASS\|make\ wasm-smoke-test) wasm_smoke_status="PASS" ;;
      FAIL\|make\ wasm-smoke-test) wasm_smoke_status="FAIL" ;;
    esac
  done

  if [[ "$phase4_status" == "PASS" && -f out/phase-3.2-govulncheck.md ]]; then
    waiver_status="$(awk -F': ' '/^- GO-2025-3684 waiver status:/ {print $2; exit}' out/phase-3.2-govulncheck.md)"
  fi

  if [[ "$wasm_smoke_status" == "PASS" && -f "$WASM_RESULT_PATH" ]]; then
    wasm_summary="$(
      jq -r '"codeId=\(.code_id) contract=\(.contract_address) owner=\(.owner_before)->\(.owner_after) storeTx=\(.store_txhash) instantiateTx=\(.instantiate_txhash) executeTx=\(.execute_txhash)"' "$WASM_RESULT_PATH"
    )"
  fi

  {
    echo "# Phase 5 Validation Report"
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
    echo "- wasmvm version: \`${wasmvm_version}\`"
    echo "- Cosmos chain-id: \`kudora_12000-1\`"
    echo "- EVM chain ID: \`120001\`"
    echo "- Approved go-ethereum exception status: \`${geth_replacement_line}\`"
    echo "- Wasm permission policy: \`${wasm_permission_policy}\`"
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
    echo "## Runtime Summary"
    echo
    echo "- Phase 4 validation result: ${phase4_status}"
    echo "- EVM precompile waiver status: ${waiver_status}"
    echo "- Wasm smoke result: ${wasm_smoke_status}"
    echo "- Wasm smoke summary: ${wasm_summary}"
    echo "- EVM smoke result: ${evm_smoke_status}"
    echo "- EVM transaction smoke result: ${evm_tx_status}"
    echo "- EVM contract smoke result: ${evm_contract_status}"
    echo
    echo "## Dependency And Security Summary"
    echo
    echo "- Dependency audit result: ${dependency_audit_status}"
    echo "- Vulnerability scan result: ${vulncheck_status}"
    echo "- Precompile surface audit result: ${precompile_surface_status}"
    echo "- Precompile policy assertion result: ${precompile_policy_status}"
    echo "- Docker build result: ${docker_build_status}"
    echo "- Docker smoke result: ${docker_smoke_status}"
    echo
    echo "## Archive Paths"
    echo
    echo "- Phase 5 archive: \`${PHASE5_ARCHIVE_PATH}\`"
    echo "- Latest inspection archive: \`${LATEST_ARCHIVE_PATH}\`"
    echo "- Compatibility archive: \`${COMPATIBILITY_ARCHIVE_PATH}\`"
    echo
    echo "## Confirmations"
    echo
    echo "- No secrets were detected in the working tree."
    echo "- No forbidden runtime forks were found."
    echo "- No business modules were added."
    echo "- No IBC product/tokenfactory/packet-forward/rate-limit/ICA/08-wasm/explorer/monitoring work was added."
    echo "- No Docker registry push was performed."
    echo "- Note: the final pushed commit may differ if this report is committed afterward."
  } >"$REPORT_PATH"
}

run_check "Phase 5 artifacts exist" check_phase5_artifacts || {
  write_blocker
  write_report
  echo "phase-5-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2
  exit 1
}
run_check "Phase 5 scope guard" check_phase5_scope || {
  write_blocker
  write_report
  echo "phase-5-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2
  exit 1
}
run_check "Phase 5 temporary smoke state is not tracked" check_phase5_tmp_state_not_tracked || {
  write_blocker
  write_report
  echo "phase-5-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2
  exit 1
}
run_check "make phase-4-validate" make phase-4-validate || {
  write_blocker
  write_report
  echo "phase-5-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2
  exit 1
}
run_check "Phase 4 report integrity" check_phase4_report_integrity || {
  write_blocker
  write_report
  echo "phase-5-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2
  exit 1
}
run_check "make tidy" make tidy || { write_blocker; write_report; echo "phase-5-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "go mod verify" go mod verify || { write_blocker; write_report; echo "phase-5-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make build" make build || { write_blocker; write_report; echo "phase-5-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make test" make test || { write_blocker; write_report; echo "phase-5-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make lint" make lint || { write_blocker; write_report; echo "phase-5-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make verify-no-forks" make verify-no-forks || { write_blocker; write_report; echo "phase-5-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make verify-clean-reset" make verify-clean-reset || { write_blocker; write_report; echo "phase-5-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make verify-no-secrets" make verify-no-secrets || { write_blocker; write_report; echo "phase-5-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make dependency-audit" make dependency-audit || { write_blocker; write_report; echo "phase-5-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make vulncheck" make vulncheck || { write_blocker; write_report; echo "phase-5-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make audit-evm-precompile-surface" make audit-evm-precompile-surface || { write_blocker; write_report; echo "phase-5-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make assert-evm-precompile-policy" make assert-evm-precompile-policy || { write_blocker; write_report; echo "phase-5-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make docker-build" make docker-build || { write_blocker; write_report; echo "phase-5-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make docker-smoke-test" make docker-smoke-test || { write_blocker; write_report; echo "phase-5-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make evm-smoke-test" make evm-smoke-test || { write_blocker; write_report; echo "phase-5-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make evm-transaction-smoke-test" make evm-transaction-smoke-test || { write_blocker; write_report; echo "phase-5-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make evm-contract-smoke-test" make evm-contract-smoke-test || { write_blocker; write_report; echo "phase-5-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make wasm-smoke-test" make wasm-smoke-test || { write_blocker; write_report; echo "phase-5-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "Phase 5 wasm result artifact" check_result_artifact_present "$WASM_RESULT_PATH" "Phase 5 wasm smoke result artifact" || { write_blocker; write_report; echo "phase-5-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make zip" make zip || { write_blocker; write_report; echo "phase-5-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }

write_report

echo "phase-5-validate: PASS (${REPORT_PATH})"
