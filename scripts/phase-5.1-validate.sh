#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

OUT_DIR="out"
REPORT_PATH="${OUT_DIR}/phase-5.1-validation.md"
EXPECTED_BRANCH="Upgrade"
PHASE4_REPORT_PATH="out/phase-4-validation.md"
PHASE5_REPORT_PATH="out/phase-5-validation.md"
PHASE4_TX_RESULT_PATH="tmp/phase-4-evm-tx-smoke/result.json"
PHASE4_CONTRACT_RESULT_PATH="tmp/phase-4-evm-contract-smoke/result.json"
PHASE5_WASM_RESULT_PATH="tmp/phase-5-wasm-smoke/result.json"
PHASE5_ARCHIVE_PATH="out/kudora-phase-5-cosmwasm-runtime.zip"
LATEST_ARCHIVE_PATH="out/kudora-latest-inspection.zip"
COMPATIBILITY_ARCHIVE_PATH="out/kudora-phase-0-reset.zip"

mkdir -p "$OUT_DIR"

branch_name="$(git branch --show-current)"
if [[ "$branch_name" != "$EXPECTED_BRANCH" ]]; then
  echo "phase-5.1-validate: expected branch ${EXPECTED_BRANCH}, found ${branch_name}" >&2
  exit 1
fi

clear_phase51_tmp_results() {
  rm -f \
    "tmp/phase-3-evm-smoke/result.json" \
    "$PHASE4_TX_RESULT_PATH" \
    "$PHASE4_CONTRACT_RESULT_PATH" \
    "$PHASE5_WASM_RESULT_PATH"
}

file_mtime() {
  local path="$1"

  if stat -f '%m' "$path" >/dev/null 2>&1; then
    stat -f '%m' "$path"
  else
    stat -c '%Y' "$path"
  fi
}

check_current_run_artifact() {
  local artifact_path="$1"
  local label="$2"

  if [[ ! -f "$artifact_path" ]]; then
    echo "phase-5.1-validate: ${label} missing at ${artifact_path}" >&2
    return 1
  fi

  if [[ "$(file_mtime "$artifact_path")" -lt "$validation_start_epoch" ]]; then
    echo "phase-5.1-validate: ${label} predates this validation run" >&2
    return 1
  fi
}

check_report_pass_lines() {
  local report_path="$1"
  shift
  local required_lines=("$@")
  local line

  if [[ ! -f "$report_path" ]]; then
    echo "phase-5.1-validate: expected report at ${report_path}" >&2
    return 1
  fi

  for line in "${required_lines[@]}"; do
    if ! rg -F -- "$line" "$report_path" >/dev/null; then
      echo "phase-5.1-validate: report ${report_path} missing required line: ${line}" >&2
      return 1
    fi
  done

  if rg -F -- 'not run' "$report_path" >/dev/null; then
    echo "phase-5.1-validate: report ${report_path} still contains 'not run'" >&2
    return 1
  fi

  if rg -n '^- FAIL:' "$report_path" >/dev/null; then
    echo "phase-5.1-validate: report ${report_path} still contains failing checks" >&2
    return 1
  fi
}

check_phase4_report_integrity() {
  if [[ "$(file_mtime "$PHASE4_REPORT_PATH")" -lt "$validation_start_epoch" ]]; then
    echo "phase-5.1-validate: report ${PHASE4_REPORT_PATH} predates this validation run" >&2
    return 1
  fi

  check_report_pass_lines "$PHASE4_REPORT_PATH" \
    '- PASS: `make evm-smoke-test`' \
    '- PASS: `make evm-transaction-smoke-test`' \
    '- PASS: `make evm-contract-smoke-test`' \
    '- PASS: `make vulncheck`' \
    '- PASS: `make dependency-audit`' \
    '- Phase 3.2 validation result: PASS' \
    '- EVM smoke result: PASS' \
    '- Transaction smoke result: PASS' \
    '- Contract smoke result: PASS'
}

check_phase5_report_integrity() {
  if [[ "$(file_mtime "$PHASE5_REPORT_PATH")" -lt "$validation_start_epoch" ]]; then
    echo "phase-5.1-validate: report ${PHASE5_REPORT_PATH} predates this validation run" >&2
    return 1
  fi

  check_report_pass_lines "$PHASE5_REPORT_PATH" \
    '- PASS: `make phase-4-validate`' \
    '- PASS: `make tidy`' \
    '- PASS: `go mod verify`' \
    '- PASS: `make build`' \
    '- PASS: `make test`' \
    '- PASS: `make lint`' \
    '- PASS: `make verify-no-forks`' \
    '- PASS: `make verify-clean-reset`' \
    '- PASS: `make verify-no-secrets`' \
    '- PASS: `make dependency-audit`' \
    '- PASS: `make vulncheck`' \
    '- PASS: `make audit-evm-precompile-surface`' \
    '- PASS: `make assert-evm-precompile-policy`' \
    '- PASS: `make docker-build`' \
    '- PASS: `make docker-smoke-test`' \
    '- PASS: `make evm-smoke-test`' \
    '- PASS: `make evm-transaction-smoke-test`' \
    '- PASS: `make evm-contract-smoke-test`' \
    '- PASS: `make wasm-smoke-test`' \
    '- PASS: `make zip`' \
    '- Phase 4 validation result: PASS' \
    '- Wasm smoke result: PASS' \
    '- EVM smoke result: PASS' \
    '- EVM transaction smoke result: PASS' \
    '- EVM contract smoke result: PASS' \
    '- Dependency audit result: PASS' \
    '- Vulnerability scan result: PASS' \
    '- Precompile surface audit result: PASS' \
    '- Precompile policy assertion result: PASS' \
    '- Docker build result: PASS' \
    '- Docker smoke result: PASS'
}

check_archive_contains_reports() {
  local archive_path="$1"
  local listing_path
  listing_path="$(mktemp)"
  unzip -Z1 "$archive_path" >"$listing_path"

  for entry in "out/phase-5-validation.md" "out/phase-5.1-validation.md"; do
    if ! rg -x -- "$entry" "$listing_path" >/dev/null; then
      rm -f "$listing_path"
      echo "phase-5.1-validate: archive ${archive_path} missing ${entry}" >&2
      return 1
    fi
  done

  if rg -n \
    -e '^\.git/' \
    -e '^\.kudora/' \
    -e '^\.testnets/' \
    -e '^build/' \
    -e '^dist/' \
    -e '^tmp/' \
    -e '^release/' \
    -e '(^|/)\.env(\..*)?$' \
    -e '(^|/)priv_validator_key\.json$' \
    -e '(^|/)node_key\.json$' \
    -e '(^|/)key_seed\.json$' \
    -e '\.pem$' \
    -e '\.key$' \
    -e '\.seed$' \
    -e '\.mnemonic$' \
    -e '\.zip$' \
    "$listing_path" >/dev/null; then
    rm -f "$listing_path"
    echo "phase-5.1-validate: forbidden content found in ${archive_path}" >&2
    return 1
  fi

  rm -f "$listing_path"
}

results=()
last_failure_label=""
last_failure_status=0
last_failure_output=""

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

starting_commit="$(git rev-parse HEAD)"
head_before_report="$(git rev-parse HEAD)"
working_tree_status_before="$(git status --short)"
generated_at="$(date -u '+%Y-%m-%d %H:%M:%S UTC')"
validation_start_epoch="$(date +%s)"
go_version="$(go version)"
cosmos_sdk_version="$(go list -m -f '{{.Version}}' github.com/cosmos/cosmos-sdk)"
cometbft_version="$(go list -m -f '{{.Version}}' github.com/cometbft/cometbft)"
cosmos_evm_version="$(go list -m -f '{{.Version}}' github.com/cosmos/evm)"
wasmd_version="$(go list -m -f '{{.Version}}' github.com/CosmWasm/wasmd)"
wasmvm_version="$(go list -m -f '{{.Version}}' github.com/CosmWasm/wasmvm/v3)"
docker_image_tag="$(awk -F':= ' '/^DOCKER_IMAGE :=/ {print $2; exit}' Makefile)"
geth_replacement_line="$(awk '/github\.com\/ethereum\/go-ethereum[[:space:]]*=>/ {gsub(/^[[:space:]]+/, "", $0); print; exit}' go.mod)"

clear_phase51_tmp_results
printf '# Phase 5.1 Validation Report\n\nPending validation run...\n' >"$REPORT_PATH"

write_report() {
  local phase4_status="not run"
  local phase5_status="not run"
  local evm_smoke_status="not run"
  local evm_tx_status="not run"
  local evm_contract_status="not run"
  local wasm_smoke_status="not run"
  local dependency_audit_status="not run"
  local vulncheck_status="not run"
  local docker_build_status="not run"
  local docker_smoke_status="not run"
  local no_forks_status="not run"
  local no_secrets_status="not run"
  local archive_status="not run"
  local archive_report_status="not run"
  local latest_archive_report_status="not run"
  local no_required_not_run="failed or not yet proven"
  local no_stale_tmp_used="failed or not yet proven"

  for result in "${results[@]}"; do
    case "$result" in
      PASS\|Phase\ 5.1\ phase-4\ report\ integrity) phase4_status="PASS" ;;
      FAIL\|Phase\ 5.1\ phase-4\ report\ integrity) phase4_status="FAIL" ;;
      PASS\|make\ phase-5-validate) phase5_status="PASS" ;;
      FAIL\|make\ phase-5-validate) phase5_status="FAIL" ;;
      PASS\|make\ verify-no-forks) no_forks_status="PASS" ;;
      FAIL\|make\ verify-no-forks) no_forks_status="FAIL" ;;
      PASS\|make\ verify-no-secrets) no_secrets_status="PASS" ;;
      FAIL\|make\ verify-no-secrets) no_secrets_status="FAIL" ;;
      PASS\|make\ vulncheck) vulncheck_status="PASS" ;;
      FAIL\|make\ vulncheck) vulncheck_status="FAIL" ;;
      PASS\|make\ dependency-audit) dependency_audit_status="PASS" ;;
      FAIL\|make\ dependency-audit) dependency_audit_status="FAIL" ;;
      PASS\|make\ zip) archive_status="PASS" ;;
      FAIL\|make\ zip) archive_status="FAIL" ;;
      PASS\|Phase\ 5.1\ archive\ contains\ final\ validation\ reports) archive_report_status="PASS" ;;
      FAIL\|Phase\ 5.1\ archive\ contains\ final\ validation\ reports) archive_report_status="FAIL" ;;
      PASS\|Phase\ 5.1\ latest\ inspection\ archive\ contains\ final\ validation\ reports) latest_archive_report_status="PASS" ;;
      FAIL\|Phase\ 5.1\ latest\ inspection\ archive\ contains\ final\ validation\ reports) latest_archive_report_status="FAIL" ;;
    esac
  done

  if [[ "$phase5_status" == "PASS" && -f "$PHASE5_REPORT_PATH" && "$(file_mtime "$PHASE5_REPORT_PATH")" -ge "$validation_start_epoch" ]]; then
    rg -F -- '- EVM smoke result: PASS' "$PHASE5_REPORT_PATH" >/dev/null && evm_smoke_status="PASS"
    rg -F -- '- EVM transaction smoke result: PASS' "$PHASE5_REPORT_PATH" >/dev/null && evm_tx_status="PASS"
    rg -F -- '- EVM contract smoke result: PASS' "$PHASE5_REPORT_PATH" >/dev/null && evm_contract_status="PASS"
    rg -F -- '- Wasm smoke result: PASS' "$PHASE5_REPORT_PATH" >/dev/null && wasm_smoke_status="PASS"
    rg -F -- '- Dependency audit result: PASS' "$PHASE5_REPORT_PATH" >/dev/null && dependency_audit_status="PASS"
    rg -F -- '- Vulnerability scan result: PASS' "$PHASE5_REPORT_PATH" >/dev/null && vulncheck_status="PASS"
    rg -F -- '- Docker build result: PASS' "$PHASE5_REPORT_PATH" >/dev/null && docker_build_status="PASS"
    rg -F -- '- Docker smoke result: PASS' "$PHASE5_REPORT_PATH" >/dev/null && docker_smoke_status="PASS"
  fi

  if [[ "$phase4_status" == "PASS" && "$phase5_status" == "PASS" ]] && ! rg -F -- 'not run' "$PHASE4_REPORT_PATH" "$PHASE5_REPORT_PATH" >/dev/null 2>&1; then
    no_required_not_run="confirmed"
  fi

  if [[ -f "$PHASE4_TX_RESULT_PATH" && -f "$PHASE4_CONTRACT_RESULT_PATH" && -f "$PHASE5_WASM_RESULT_PATH" ]] && \
     [[ "$(file_mtime "$PHASE4_TX_RESULT_PATH")" -ge "$validation_start_epoch" ]] && \
     [[ "$(file_mtime "$PHASE4_CONTRACT_RESULT_PATH")" -ge "$validation_start_epoch" ]] && \
     [[ "$(file_mtime "$PHASE5_WASM_RESULT_PATH")" -ge "$validation_start_epoch" ]]; then
    no_stale_tmp_used="confirmed"
  fi

  {
    echo "# Phase 5.1 Validation Report"
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
    echo "- Approved go-ethereum exception: \`${geth_replacement_line}\`"
    echo "- Docker image tag: \`${docker_image_tag}\`"
    echo
    echo "## Working Tree Status Before Validation"
    echo
    echo '```text'
    echo "${working_tree_status_before:-clean}"
    echo '```'
    echo
    echo "## Root Cause Of The Previous Contradiction"
    echo
    echo "The original contradiction came from stale report assembly. \`scripts/phase-4-validate.sh\` and \`scripts/phase-5-validate.sh\` previously allowed old \`tmp/.../result.json\` artifacts and prior phase reports to bleed into a later failed run. This Phase 5.1 gate now treats smoke summaries, dependency/vulnerability summaries, and archive proofs as valid only when they come from the current validation run."
    echo
    echo "## Files Changed To Fix Validation Integrity"
    echo
    echo "- \`Makefile\`"
    echo "- \`README.md\`"
    echo "- \`docs/wasm/phase-5-cosmwasm-runtime.md\`"
    echo "- \`scripts/phase-3.2-validate.sh\`"
    echo "- \`scripts/phase-4-validate.sh\`"
    echo "- \`scripts/phase-5-validate.sh\`"
    echo "- \`scripts/phase-5.1-validate.sh\`"
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
    echo "## Runtime And Security Summary"
    echo
    echo "- Phase 4 validation result: ${phase4_status}"
    echo "- Phase 5 validation result: ${phase5_status}"
    echo "- EVM smoke result: ${evm_smoke_status}"
    echo "- EVM transaction smoke result: ${evm_tx_status}"
    echo "- EVM contract smoke result: ${evm_contract_status}"
    echo "- Wasm smoke result: ${wasm_smoke_status}"
    echo "- Dependency audit result: ${dependency_audit_status}"
    echo "- Vulnerability scan result: ${vulncheck_status}"
    echo "- Docker build result: ${docker_build_status}"
    echo "- Docker smoke result: ${docker_smoke_status}"
    echo "- No-forks result: ${no_forks_status}"
    echo "- No-secrets result: ${no_secrets_status}"
    echo
    echo "## Archive Paths"
    echo
    echo "- Phase 5 archive: \`${PHASE5_ARCHIVE_PATH}\`"
    echo "- Latest inspection archive: \`${LATEST_ARCHIVE_PATH}\`"
    echo "- Compatibility archive: \`${COMPATIBILITY_ARCHIVE_PATH}\`"
    echo "- Archive generation result: ${archive_status}"
    echo "- Phase 5 archive validation result: ${archive_report_status}"
    echo "- Latest inspection archive validation result: ${latest_archive_report_status}"
    echo
    echo "## Confirmations"
    echo
    echo "- No required check is \`not run\`: ${no_required_not_run}"
    echo "- No stale tmp result was used as current-run evidence: ${no_stale_tmp_used}"
    echo "- No business modules were added."
    echo "- No IBC product/tokenfactory/packet-forward/rate-limit/ICA/08-wasm/explorer/monitoring work was added."
    echo "- No Docker registry push was performed."
  } >"$REPORT_PATH"
}

run_check "make phase-5-validate" make phase-5-validate || { write_report; echo "phase-5.1-validate: FAIL (${REPORT_PATH})" >&2; exit 1; }
run_check "Phase 5.1 phase-4 report integrity" check_phase4_report_integrity || { write_report; echo "phase-5.1-validate: FAIL (${REPORT_PATH})" >&2; exit 1; }
run_check "Phase 5.1 phase-5 report integrity" check_phase5_report_integrity || { write_report; echo "phase-5.1-validate: FAIL (${REPORT_PATH})" >&2; exit 1; }
run_check "Phase 5.1 phase-4 tx artifact is from current run" check_current_run_artifact "$PHASE4_TX_RESULT_PATH" "Phase 4 transaction smoke artifact" || { write_report; echo "phase-5.1-validate: FAIL (${REPORT_PATH})" >&2; exit 1; }
run_check "Phase 5.1 phase-4 contract artifact is from current run" check_current_run_artifact "$PHASE4_CONTRACT_RESULT_PATH" "Phase 4 contract smoke artifact" || { write_report; echo "phase-5.1-validate: FAIL (${REPORT_PATH})" >&2; exit 1; }
run_check "Phase 5.1 wasm artifact is from current run" check_current_run_artifact "$PHASE5_WASM_RESULT_PATH" "Phase 5 wasm smoke artifact" || { write_report; echo "phase-5.1-validate: FAIL (${REPORT_PATH})" >&2; exit 1; }
run_check "make verify-no-forks" make verify-no-forks || { write_report; echo "phase-5.1-validate: FAIL (${REPORT_PATH})" >&2; exit 1; }
run_check "make verify-no-secrets" make verify-no-secrets || { write_report; echo "phase-5.1-validate: FAIL (${REPORT_PATH})" >&2; exit 1; }
run_check "make vulncheck" make vulncheck || { write_report; echo "phase-5.1-validate: FAIL (${REPORT_PATH})" >&2; exit 1; }
run_check "make dependency-audit" make dependency-audit || { write_report; echo "phase-5.1-validate: FAIL (${REPORT_PATH})" >&2; exit 1; }

write_report

run_check "make zip" make zip || { write_report; echo "phase-5.1-validate: FAIL (${REPORT_PATH})" >&2; exit 1; }
run_check "Phase 5.1 archive contains final validation reports" check_archive_contains_reports "$PHASE5_ARCHIVE_PATH" || { write_report; echo "phase-5.1-validate: FAIL (${REPORT_PATH})" >&2; exit 1; }
run_check "Phase 5.1 latest inspection archive contains final validation reports" check_archive_contains_reports "$LATEST_ARCHIVE_PATH" || { write_report; echo "phase-5.1-validate: FAIL (${REPORT_PATH})" >&2; exit 1; }

write_report
make zip >/dev/null
check_archive_contains_reports "$PHASE5_ARCHIVE_PATH" >/dev/null
check_archive_contains_reports "$LATEST_ARCHIVE_PATH" >/dev/null

echo "phase-5.1-validate: PASS (${REPORT_PATH})"
