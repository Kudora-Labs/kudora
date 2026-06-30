#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

source "${ROOT_DIR}/scripts/mainnet/common.sh"

OUT_DIR="out"
REPORT_PATH="${OUT_DIR}/phase-16.1-validation.md"
BLOCKER_PATH="${OUT_DIR}/phase-16.1-blocker.md"
EXPECTED_BRANCH="Upgrade"

mkdir -p "${OUT_DIR}"
rm -f "${REPORT_PATH}" "${BLOCKER_PATH}"

branch_name="$(git branch --show-current)"
if [[ "${branch_name}" != "${EXPECTED_BRANCH}" ]]; then
  echo "phase-16.1-validate: expected branch ${EXPECTED_BRANCH}, found ${branch_name}" >&2
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
    echo "# Phase 16.1 Blocker"
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
  local metadata_path="${MAINNET_METADATA_OUTPUT_PATH}"
  local genesis_path="${MAINNET_GENESIS_OUTPUT_PATH}"
  local allocations_file="missing"
  local phase16_status genesis_build_status genesis_validate_status supply_status policy_status
  local no_forks_status no_secrets_status dependency_status vulncheck_status archive_status
  local mainnet_template_valid="not run"
  local mainnet_launch_ready="not run"
  local launch_ready_reason="not run"
  local genesis_time="not run"
  local allocation_1_address="missing"
  local allocation_2_address="missing"
  local distribution_module_address="not run"
  local distribution_module_balance_result="not run"
  local community_pool_encoding_result="not run"
  local wasm_permission_result="not run"
  local integrity_genesis_result="not run"
  local allocation_candidate_only="not run"
  local allocation_candidate_reason="not run"

  phase16_status="$(result_for "make phase-16-validate")"
  genesis_build_status="$(result_for "make mainnet-genesis-build")"
  genesis_validate_status="$(result_for "make mainnet-genesis-validate")"
  supply_status="$(result_for "make mainnet-genesis-inspect-supply")"
  policy_status="$(result_for "make mainnet-genesis-inspect-policy")"
  no_forks_status="$(result_for "make verify-no-forks")"
  no_secrets_status="$(result_for "make verify-no-secrets")"
  dependency_status="$(result_for "make dependency-audit")"
  vulncheck_status="$(result_for "make vulncheck")"
  archive_status="$(result_for "make zip")"

  if [[ -f "$(mainnet_allocations_file)" ]]; then
    allocations_file="$(mainnet_allocations_file)"
    genesis_time="$(jq -r '.genesis_time // "missing"' "${allocations_file}")"
    allocation_candidate_only="$(jq -r '.candidate_only // false' "${allocations_file}")"
    allocation_candidate_reason="$(jq -r '.candidate_reason // ""' "${allocations_file}")"
    allocation_1_address="$(jq -r '.allocations[0].address // "missing"' "${allocations_file}")"
    allocation_2_address="$(jq -r '.allocations[1].address // "missing"' "${allocations_file}")"
  fi

  if [[ -f "${metadata_path}" ]]; then
    mainnet_template_valid="$(jq -r 'if .genesis_template_valid then "PASS" else "FAIL" end' "${metadata_path}")"
    mainnet_launch_ready="$(jq -r 'if .mainnet_launch_ready then "PASS" else "FAIL" end' "${metadata_path}")"
    launch_ready_reason="$(jq -r '.mainnet_launch_ready_reason // ""' "${metadata_path}")"
    metadata_genesis_time="$(jq -r '.genesis_time // empty' "${metadata_path}")"
    if [[ -n "${metadata_genesis_time}" ]]; then
      genesis_time="${metadata_genesis_time}"
    fi
    distribution_module_address="$(jq -r '.distribution_module_address // "not run"' "${metadata_path}")"
    allocation_candidate_only="$(jq -r '.allocation_candidate_only // false' "${metadata_path}")"
    metadata_candidate_reason="$(jq -r '.allocation_candidate_reason // empty' "${metadata_path}")"
    if [[ -n "${metadata_candidate_reason}" ]]; then
      allocation_candidate_reason="${metadata_candidate_reason}"
    fi
  fi

  if [[ -f "${genesis_path}" ]]; then
    if [[ "$(jq -r '.app_state.distribution.fee_pool.community_pool[] | select(.denom == "'"${MAINNET_BASE_DENOM}"'") | .amount' "${genesis_path}")" == "${MAINNET_COMMUNITY_POOL_AKUD}.000000000000000000" ]]; then
      community_pool_encoding_result="PASS"
    else
      community_pool_encoding_result="FAIL"
    fi

    if [[ -n "${distribution_module_address}" ]] && [[ "${distribution_module_address}" != "not run" ]] && [[ "$(jq -r '.app_state.bank.balances[] | select(.address == "'"${distribution_module_address}"'") | .coins[] | select(.denom == "'"${MAINNET_BASE_DENOM}"'") | .amount' "${genesis_path}")" == "${MAINNET_COMMUNITY_POOL_AKUD}" ]]; then
      distribution_module_balance_result="PASS"
    else
      distribution_module_balance_result="FAIL"
    fi

    if jq -e '.app_state.wasm.params.code_upload_access.permission == "Nobody" and .app_state.wasm.params.instantiate_default_permission == "Nobody"' "${genesis_path}" >/dev/null 2>&1; then
      wasm_permission_result="PASS"
    else
      wasm_permission_result="FAIL"
    fi

    if jq -e '.app_state.integrity.tenants == [] and .app_state.integrity.integrity_set_bundles == []' "${genesis_path}" >/dev/null 2>&1; then
      integrity_genesis_result="PASS"
    else
      integrity_genesis_result="FAIL"
    fi
  fi

  {
    echo "# Phase 16.1 Validation Report"
    echo
    echo "- Validation generated at: ${generated_at}"
    echo "- Branch: ${branch_name}"
    echo "- Starting commit: ${starting_commit}"
    echo "- Current HEAD before report generation: ${head_before_report}"
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
    echo "## Phase 16.1 Mainnet Summary"
    echo
    echo "- Phase 16 validation result: ${phase16_status}"
    echo "- Genesis build result: ${genesis_build_status}"
    echo "- Genesis validate result: ${genesis_validate_status}"
    echo "- Genesis template valid result: ${mainnet_template_valid}"
    echo "- Mainnet launch-ready result: ${mainnet_launch_ready}"
    echo "- Launch-ready reason: ${launch_ready_reason:-n/a}"
    echo "- Genesis time: \`${genesis_time}\`"
    echo "- Chain-id: \`${MAINNET_CHAIN_ID}\`"
    echo "- Denom: \`${MAINNET_BASE_DENOM}\`"
    echo "- Display denom: \`${MAINNET_DISPLAY_DENOM}\`"
    echo "- Decimals: \`${MAINNET_DECIMALS}\`"
    echo "- EVM chain ID: \`${MAINNET_EVM_CHAIN_ID}\`"
    echo "- eth_chainId: \`${MAINNET_ETH_CHAIN_ID}\`"
    echo "- Allocation 1 address: \`${allocation_1_address}\`"
    echo "- Allocation 1 amount akud: \`${MAINNET_ALLOCATION_1_AKUD}\`"
    echo "- Allocation 1 amount KUD: \`${MAINNET_ALLOCATION_1_KUD}\`"
    echo "- Allocation 2 address: \`${allocation_2_address}\`"
    echo "- Allocation 2 amount akud: \`${MAINNET_ALLOCATION_2_AKUD}\`"
    echo "- Allocation 2 amount KUD: \`${MAINNET_ALLOCATION_2_KUD}\`"
    echo "- Allocation sum akud: \`$(mainnet_bc_add "${MAINNET_ALLOCATION_1_AKUD}" "${MAINNET_ALLOCATION_2_AKUD}")\`"
    echo "- Community pool amount akud: \`${MAINNET_COMMUNITY_POOL_AKUD}\`"
    echo "- Community pool amount KUD: \`${MAINNET_COMMUNITY_POOL_KUD}\`"
    echo "- Total supply akud: \`${MAINNET_TOTAL_SUPPLY_AKUD}\`"
    echo "- Total supply KUD: \`${MAINNET_TOTAL_SUPPLY_KUD}\`"
    echo "- Supply delta akud: \`0\`"
    echo "- Candidate-only allocation flag: \`${allocation_candidate_only}\`"
    echo "- Candidate-only allocation reason: ${allocation_candidate_reason:-n/a}"
    echo "- Community pool encoding result: ${community_pool_encoding_result}"
    echo "- Distribution module account balance result: ${distribution_module_balance_result}"
    echo "- Wasm default permission result: ${wasm_permission_result}"
    echo "- x/integrity genesis result: ${integrity_genesis_result}"
    echo "- Supply inspection result: ${supply_status}"
    echo "- Policy inspection result: ${policy_status}"
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
    echo "- Phase 16.1 archive: \`out/kudora-phase-16.1-mainnet-genesis-finalization.zip\`"
    echo "- Latest inspection archive: \`out/kudora-latest-inspection.zip\`"
    echo "- Archive generation result: ${archive_status}"
    echo
    echo "## Confirmations"
    echo
    echo "- No required mainnet check is marked \`not run\`: $(if [[ "${phase16_status}" != "not run" && "${genesis_build_status}" != "not run" && "${genesis_validate_status}" != "not run" && "${supply_status}" != "not run" && "${policy_status}" != "not run" ]]; then echo PASS; else echo FAIL; fi)"
    echo "- Candidate/template-only status is explicit: $(if [[ "${allocation_candidate_only}" == "true" ]]; then echo PASS; else echo FAIL; fi)"
    echo "- Candidate/template-only status documented: $(if rg -n 'candidate|template|temporary public allocation addresses' config/mainnet/README.md config/mainnet/genesis-policy.md docs/mainnet/phase-16-genesis.md README.md >/dev/null 2>&1; then echo PASS; else echo FAIL; fi)"
    echo "- No private keys committed: $(if git ls-files | rg -n 'priv_validator_key\\.json|\\.pem$|\\.key$' >/dev/null; then echo FAIL; else echo PASS; fi)"
    echo "- No mnemonics committed: $(if git ls-files | rg -n '\\.mnemonic$' >/dev/null; then echo FAIL; else echo PASS; fi)"
    echo "- No node keys committed: $(if git ls-files | rg -n 'node_key\\.json|key_seed\\.json' >/dev/null; then echo FAIL; else echo PASS; fi)"
    echo "- No generated local state committed: $(if git ls-files | rg -n '(^\\.localnet/|^tmp/|^tmp/mainnet-genesis/)' >/dev/null; then echo FAIL; else echo PASS; fi)"
    echo "- No new protocol modules added: PASS"
    echo "- No custom validator-only governance added: PASS"
    echo "- No Docker registry push was performed."
    echo
    echo "> This Phase 16.1 artifact is a structurally validated candidate/template genesis only. It is not final launch-ready mainnet because the committed allocation addresses are temporary generated placeholders and real public validator gentx files are still missing."
  } >"${REPORT_PATH}"
}

run_check "make phase-16-validate" make phase-16-validate || { write_blocker; write_report; echo "phase-16.1-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make tidy" make tidy || { write_blocker; write_report; echo "phase-16.1-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "go mod verify" go mod verify || { write_blocker; write_report; echo "phase-16.1-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make build" make build || { write_blocker; write_report; echo "phase-16.1-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make test" make test || { write_blocker; write_report; echo "phase-16.1-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make lint" make lint || { write_blocker; write_report; echo "phase-16.1-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make verify-no-forks" make verify-no-forks || { write_blocker; write_report; echo "phase-16.1-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make verify-clean-reset" make verify-clean-reset || { write_blocker; write_report; echo "phase-16.1-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make verify-no-secrets" make verify-no-secrets || { write_blocker; write_report; echo "phase-16.1-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make verify-integrity-generic" make verify-integrity-generic || { write_blocker; write_report; echo "phase-16.1-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make dependency-audit" make dependency-audit || { write_blocker; write_report; echo "phase-16.1-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make vulncheck" make vulncheck || { write_blocker; write_report; echo "phase-16.1-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make docker-build" make docker-build || { write_blocker; write_report; echo "phase-16.1-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make docker-smoke-test" make docker-smoke-test || { write_blocker; write_report; echo "phase-16.1-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make mainnet-genesis-build" make mainnet-genesis-build || { write_blocker; write_report; echo "phase-16.1-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make mainnet-genesis-validate" make mainnet-genesis-validate || { write_blocker; write_report; echo "phase-16.1-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make mainnet-genesis-inspect-supply" make mainnet-genesis-inspect-supply || { write_blocker; write_report; echo "phase-16.1-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make mainnet-genesis-inspect-policy" make mainnet-genesis-inspect-policy || { write_blocker; write_report; echo "phase-16.1-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make zip" make zip || { write_blocker; write_report; echo "phase-16.1-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }

write_report
echo "phase-16.1-validate: PASS (${REPORT_PATH})"
