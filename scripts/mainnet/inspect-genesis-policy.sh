#!/usr/bin/env bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

mainnet_prepare_dirs
mainnet_require_command jq
mainnet_require_binary

allocations_file="$(mainnet_allocations_file)"
mainnet_require_allocations_file
mainnet_validate_allocations_json "${allocations_file}"
[[ -f "${MAINNET_GENESIS_OUTPUT_PATH}" ]] || mainnet_die "phase-16: generated genesis not found at ${MAINNET_GENESIS_OUTPUT_PATH}; run make mainnet-genesis-build first"
[[ -f "${MAINNET_POLICY_DOC}" ]] || mainnet_die "phase-16: genesis policy document is missing at ${MAINNET_POLICY_DOC}"
[[ -f "${MAINNET_METADATA_OUTPUT_PATH}" ]] || mainnet_die "phase-16: metadata output not found at ${MAINNET_METADATA_OUTPUT_PATH}"
[[ -f "${MAINNET_TEMPLATE_HOME}/config/app.toml" ]] || mainnet_die "phase-16: template app.toml not found at ${MAINNET_TEMPLATE_HOME}"

genesis_time="$(mainnet_allocations_genesis_time "${allocations_file}")"
candidate_only="$(mainnet_allocations_candidate_only "${allocations_file}")"
candidate_reason="$(mainnet_allocations_candidate_reason "${allocations_file}")"

rg -n --fixed-strings "${MAINNET_GOVERNANCE_CAVEAT}" "${MAINNET_POLICY_DOC}" >/dev/null || mainnet_die "phase-16: governance caveat is missing from ${MAINNET_POLICY_DOC}"
[[ "$(jq -r '.chain_id' "${MAINNET_GENESIS_OUTPUT_PATH}")" == "${MAINNET_CHAIN_ID}" ]] || mainnet_die "phase-16: chain-id policy mismatch"
[[ "$(jq -r '.genesis_time' "${MAINNET_GENESIS_OUTPUT_PATH}")" == "${genesis_time}" ]] || mainnet_die "phase-16: genesis_time policy mismatch"
[[ "$(jq -r '.app_state.bank.supply[] | select(.denom == "'"${MAINNET_BASE_DENOM}"'") | .amount' "${MAINNET_GENESIS_OUTPUT_PATH}")" == "${MAINNET_TOTAL_SUPPLY_AKUD}" ]] || mainnet_die "phase-16: supply policy mismatch"
[[ "$(jq -r '.app_state.distribution.fee_pool.community_pool[] | select(.denom == "'"${MAINNET_BASE_DENOM}"'") | .amount' "${MAINNET_GENESIS_OUTPUT_PATH}")" == "${MAINNET_COMMUNITY_POOL_AKUD}.000000000000000000" ]] || mainnet_die "phase-16: community pool policy mismatch"
[[ "$(jq -r '.app_state.wasm.params.code_upload_access.permission' "${MAINNET_GENESIS_OUTPUT_PATH}")" == "Nobody" ]] || mainnet_die "phase-16: wasm upload policy mismatch"
[[ "$(jq -r '.app_state.wasm.params.instantiate_default_permission' "${MAINNET_GENESIS_OUTPUT_PATH}")" == "Nobody" ]] || mainnet_die "phase-16: wasm instantiate policy mismatch"
[[ "$(jq -r '.app_state.evm.params.evm_denom' "${MAINNET_GENESIS_OUTPUT_PATH}")" == "${MAINNET_BASE_DENOM}" ]] || mainnet_die "phase-16: EVM denom policy mismatch"
rg -n '^evm-chain-id = 120001$' "${MAINNET_TEMPLATE_HOME}/config/app.toml" >/dev/null || mainnet_die "phase-16: EVM chain-id policy mismatch"
[[ "$(jq -r '.app_state.integrity.tenants | length' "${MAINNET_GENESIS_OUTPUT_PATH}")" == "0" ]] || mainnet_die "phase-16: x/integrity tenant policy mismatch"
[[ "$(jq -r '.app_state.integrity.integrity_set_bundles | length' "${MAINNET_GENESIS_OUTPUT_PATH}")" == "0" ]] || mainnet_die "phase-16: x/integrity bundle policy mismatch"
[[ "$(jq -r '.genesis_time' "${MAINNET_METADATA_OUTPUT_PATH}")" == "${genesis_time}" ]] || mainnet_die "phase-16: metadata genesis_time policy mismatch"

if [[ "${candidate_only}" == "true" ]]; then
  [[ "$(jq -r '.allocation_candidate_only' "${MAINNET_METADATA_OUTPUT_PATH}")" == "true" ]] || mainnet_die "phase-16: candidate-only metadata flag mismatch"
  [[ "$(jq -r '.allocation_candidate_reason // ""' "${MAINNET_METADATA_OUTPUT_PATH}")" == "${candidate_reason}" ]] || mainnet_die "phase-16: candidate-only metadata reason mismatch"
  rg -n 'candidate|template|temporary public allocation addresses' "${MAINNET_POLICY_DOC}" >/dev/null || mainnet_die "phase-16: candidate/template allocation policy must be documented"
fi

if git ls-files | rg -n '(^\.localnet/|^tmp/|^tmp/mainnet-genesis/|^deploy/localnet/state/)' >/dev/null; then
  mainnet_die "phase-16: local/test artifacts must not be tracked"
fi

declare -a policy_secret_scan_targets=(
  "${MAINNET_GENESIS_OUTPUT_PATH}"
  "${MAINNET_METADATA_OUTPUT_PATH}"
)

if [[ -f "${allocations_file}" ]]; then
  policy_secret_scan_targets+=("${allocations_file}")
fi

while IFS= read -r gentx_file; do
  policy_secret_scan_targets+=("${gentx_file}")
done < <(find "${MAINNET_GENTX_DIR}" -mindepth 1 -maxdepth 1 -type f -name '*.json' | sort)

if rg -n --pcre2 \
  -e '-----BEGIN (?:OPENSSH|RSA|EC|DSA|PGP|[A-Z ]*PRIVATE KEY)-----' \
  -e 'PRIVATE KEY-----' \
  -e 'priv_validator_key' \
  -e 'node_key' \
  -e 'mnemonic' \
  -e 'seed phrase' \
  "${policy_secret_scan_targets[@]}" >/dev/null 2>&1; then
  mainnet_die "phase-16: mainnet config or output artifacts contain secret-like content"
fi

cat <<EOF
chain_id_policy=PASS
genesis_time_policy=PASS
supply_policy=PASS
community_pool_policy=PASS
governance_policy_caveat=PASS
wasm_policy=PASS
evm_policy=PASS
integrity_policy=PASS
candidate_template_policy=$(if [[ "${candidate_only}" == "true" ]]; then echo PASS; else echo n/a; fi)
no_test_or_localnet_artifacts=PASS
no_secrets=PASS
EOF
