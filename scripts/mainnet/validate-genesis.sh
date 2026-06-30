#!/usr/bin/env bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

mainnet_prepare_dirs
mainnet_require_command jq
mainnet_require_command curl
mainnet_require_binary

allocations_file="$(mainnet_allocations_file)"
mainnet_require_allocations_file
mainnet_validate_allocations_json "${allocations_file}"

[[ -f "${MAINNET_GENESIS_OUTPUT_PATH}" ]] || mainnet_die "phase-16: generated genesis not found at ${MAINNET_GENESIS_OUTPUT_PATH}; run make mainnet-genesis-build first"
[[ -f "${MAINNET_METADATA_OUTPUT_PATH}" ]] || mainnet_die "phase-16: mainnet metadata not found at ${MAINNET_METADATA_OUTPUT_PATH}; run make mainnet-genesis-build first"
[[ -f "${MAINNET_TEMPLATE_HOME}/config/genesis.json" ]] || mainnet_die "phase-16: template genesis home not found at ${MAINNET_TEMPLATE_HOME}"
[[ -f "${MAINNET_TEMPLATE_HOME}/config/app.toml" ]] || mainnet_die "phase-16: template app.toml not found at ${MAINNET_TEMPLATE_HOME}"

genesis_path="${MAINNET_GENESIS_OUTPUT_PATH}"
genesis_time="$(mainnet_allocations_genesis_time "${allocations_file}")"
candidate_only="$(mainnet_allocations_candidate_only "${allocations_file}")"
candidate_reason="$(mainnet_allocations_candidate_reason "${allocations_file}")"
allocation_1_address="$(jq -r '.allocations[0].address' "${allocations_file}")"
allocation_2_address="$(jq -r '.allocations[1].address' "${allocations_file}")"
distribution_module_address="$(mainnet_module_address distribution)"
launch_ready="$(jq -r '.mainnet_launch_ready' "${MAINNET_METADATA_OUTPUT_PATH}")"
launch_ready_reason="$(jq -r '.mainnet_launch_ready_reason // ""' "${MAINNET_METADATA_OUTPUT_PATH}")"
gentx_count="$(jq -r '.gentx_count // 0' "${MAINNET_METADATA_OUTPUT_PATH}")"

jq -e . "${genesis_path}" >/dev/null || mainnet_die "phase-16: generated genesis JSON is invalid"
[[ "$(jq -r '.chain_id' "${genesis_path}")" == "${MAINNET_CHAIN_ID}" ]] || mainnet_die "phase-16: generated genesis chain-id mismatch"
[[ "$(jq -r '.genesis_time' "${genesis_path}")" == "${genesis_time}" ]] || mainnet_die "phase-16: generated genesis_time mismatch"
[[ "$(jq -r '.app_state.bank.denom_metadata[0].base' "${genesis_path}")" == "${MAINNET_BASE_DENOM}" ]] || mainnet_die "phase-16: generated genesis base denom mismatch"
[[ "$(jq -r '.app_state.bank.denom_metadata[0].display' "${genesis_path}")" == "${MAINNET_DISPLAY_DENOM}" ]] || mainnet_die "phase-16: generated genesis display denom mismatch"
[[ "$(jq -r '.app_state.bank.denom_metadata[0].denom_units[1].exponent' "${genesis_path}")" == "${MAINNET_DECIMALS}" ]] || mainnet_die "phase-16: generated genesis decimals mismatch"
[[ "$(jq -r '.app_state.bank.supply[] | select(.denom == "'"${MAINNET_BASE_DENOM}"'") | .amount' "${genesis_path}")" == "${MAINNET_TOTAL_SUPPLY_AKUD}" ]] || mainnet_die "phase-16: generated genesis total supply mismatch"
[[ "$(jq -r '.app_state.bank.balances[] | select(.address == "'"${allocation_1_address}"'") | .coins[] | select(.denom == "'"${MAINNET_BASE_DENOM}"'") | .amount' "${genesis_path}")" == "${MAINNET_ALLOCATION_1_AKUD}" ]] || mainnet_die "phase-16: allocation 1 balance mismatch"
[[ "$(jq -r '.app_state.bank.balances[] | select(.address == "'"${allocation_2_address}"'") | .coins[] | select(.denom == "'"${MAINNET_BASE_DENOM}"'") | .amount' "${genesis_path}")" == "${MAINNET_ALLOCATION_2_AKUD}" ]] || mainnet_die "phase-16: allocation 2 balance mismatch"
[[ "$(jq -r '.app_state.bank.balances[] | select(.address == "'"${distribution_module_address}"'") | .coins[] | select(.denom == "'"${MAINNET_BASE_DENOM}"'") | .amount' "${genesis_path}")" == "${MAINNET_COMMUNITY_POOL_AKUD}" ]] || mainnet_die "phase-16: distribution module bank balance mismatch"
[[ "$(jq -r '.app_state.distribution.fee_pool.community_pool[] | select(.denom == "'"${MAINNET_BASE_DENOM}"'") | .amount' "${genesis_path}")" == "${MAINNET_COMMUNITY_POOL_AKUD}.000000000000000000" ]] || mainnet_die "phase-16: community pool encoding mismatch"
[[ "$(jq -r '.app_state.wasm.params.code_upload_access.permission' "${genesis_path}")" == "Nobody" ]] || mainnet_die "phase-16: wasm upload permission must remain Nobody"
[[ "$(jq -r '.app_state.wasm.params.instantiate_default_permission' "${genesis_path}")" == "Nobody" ]] || mainnet_die "phase-16: wasm instantiate default permission must remain Nobody"
[[ "$(jq -r '.app_state.integrity.tenants | length' "${genesis_path}")" == "0" ]] || mainnet_die "phase-16: x/integrity genesis must not preload tenants"
[[ "$(jq -r '.app_state.integrity.integrity_set_bundles | length' "${genesis_path}")" == "0" ]] || mainnet_die "phase-16: x/integrity genesis must not preload integrity sets"
[[ "$(jq -r '.app_state.evm.params.evm_denom' "${genesis_path}")" == "${MAINNET_BASE_DENOM}" ]] || mainnet_die "phase-16: EVM denom must remain ${MAINNET_BASE_DENOM}"
[[ "$(jq -r '.genesis_time' "${MAINNET_METADATA_OUTPUT_PATH}")" == "${genesis_time}" ]] || mainnet_die "phase-16: metadata genesis_time mismatch"
[[ "$(jq -r '.allocation_candidate_only' "${MAINNET_METADATA_OUTPUT_PATH}")" == "${candidate_only}" ]] || mainnet_die "phase-16: metadata candidate_only mismatch"
[[ "$(jq -r '.allocation_candidate_reason // empty' "${MAINNET_METADATA_OUTPUT_PATH}")" == "${candidate_reason}" ]] || mainnet_die "phase-16: metadata candidate_reason mismatch"

rg -n '^evm-chain-id = 120001$' "${MAINNET_TEMPLATE_HOME}/config/app.toml" >/dev/null || mainnet_die "phase-16: template app.toml must preserve evm-chain-id = 120001"

if rg -n 'BEGIN (OPENSSH|RSA|EC|DSA|PGP|[A-Z ]*PRIVATE KEY)|mnemonic|seed phrase|priv_validator_key|node_key' "${genesis_path}" "${MAINNET_METADATA_OUTPUT_PATH}" >/dev/null 2>&1; then
  mainnet_die "phase-16: generated mainnet artifacts must not contain secrets, mnemonics, or private key material"
fi

"${KUDORA_BINARY}" genesis validate --home "${MAINNET_TEMPLATE_HOME}" >/dev/null 2>&1

rm -rf "${MAINNET_RUNTIME_HOME}"
cp -R "${MAINNET_TEMPLATE_HOME}" "${MAINNET_RUNTIME_HOME}"

runtime_genesis_time="$(perl -MPOSIX=strftime -e 'print strftime("%Y-%m-%dT%H:%M:%SZ", gmtime(time() - 60))')"
jq --arg runtime_genesis_time "${runtime_genesis_time}" '.genesis_time = $runtime_genesis_time' \
  "${MAINNET_RUNTIME_HOME}/config/genesis.json" >"${MAINNET_RUNTIME_HOME}/config/genesis.json.tmp"
mv "${MAINNET_RUNTIME_HOME}/config/genesis.json.tmp" "${MAINNET_RUNTIME_HOME}/config/genesis.json"

perl -0pi -e 's#laddr = "tcp://127\.0\.0\.1:26657"#laddr = "tcp://127.0.0.1:27657"#g' "${MAINNET_RUNTIME_HOME}/config/config.toml"
perl -0pi -e 's#proxy_app = "tcp://127\.0\.0\.1:26658"#proxy_app = "tcp://127.0.0.1:27658"#g' "${MAINNET_RUNTIME_HOME}/config/config.toml"
perl -0pi -e 's#pprof_laddr = "localhost:6060"#pprof_laddr = "localhost:6160"#g' "${MAINNET_RUNTIME_HOME}/config/config.toml"
perl -0pi -e 's#address = "tcp://localhost:1317"#address = "tcp://127.0.0.1:1417"#g' "${MAINNET_RUNTIME_HOME}/config/app.toml"
perl -0pi -e 's#address = "localhost:9090"#address = "127.0.0.1:9190"#g' "${MAINNET_RUNTIME_HOME}/config/app.toml"
perl -0pi -e 's#address = "127\.0\.0\.1:8545"#address = "127.0.0.1:8645"#g' "${MAINNET_RUNTIME_HOME}/config/app.toml"
perl -0pi -e 's#ws-address = "127\.0\.0\.1:8546"#ws-address = "127.0.0.1:8646"#g' "${MAINNET_RUNTIME_HOME}/config/app.toml"

if [[ "${launch_ready}" != "true" ]]; then
  "${KUDORA_BINARY}" keys add phase16-validator --keyring-backend test --home "${MAINNET_RUNTIME_HOME}" --output json >/dev/null 2>&1
  phase16_validator_address="$("${KUDORA_BINARY}" keys show phase16-validator --address --keyring-backend test --home "${MAINNET_RUNTIME_HOME}")"
  "${KUDORA_BINARY}" genesis add-genesis-account \
    "${phase16_validator_address}" \
    "1000000000000000000${MAINNET_BASE_DENOM}" \
    --home "${MAINNET_RUNTIME_HOME}" \
    >/dev/null 2>&1
  "${KUDORA_BINARY}" genesis gentx \
    phase16-validator \
    "1000000000000000000${MAINNET_BASE_DENOM}" \
    --chain-id "${MAINNET_CHAIN_ID}" \
    --home "${MAINNET_RUNTIME_HOME}" \
    --keyring-backend test \
    >/dev/null 2>&1
  "${KUDORA_BINARY}" genesis collect-gentxs --home "${MAINNET_RUNTIME_HOME}" >/dev/null 2>&1
  "${KUDORA_BINARY}" genesis validate --home "${MAINNET_RUNTIME_HOME}" >/dev/null 2>&1
fi

runtime_log="${MAINNET_RUNTIME_HOME}/start.log"
runtime_pid=""
cleanup() {
  if [[ -n "${runtime_pid}" ]] && kill -0 "${runtime_pid}" >/dev/null 2>&1; then
    kill "${runtime_pid}" >/dev/null 2>&1 || true
    wait "${runtime_pid}" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

"${KUDORA_BINARY}" start --home "${MAINNET_RUNTIME_HOME}" >"${runtime_log}" 2>&1 &
runtime_pid="$!"

runtime_started=0
for _ in $(seq 1 60); do
  if curl -sf "http://127.0.0.1:27657/status" >/dev/null 2>&1; then
    runtime_started=1
    break
  fi
  sleep 1
done

[[ "${runtime_started}" == "1" ]] || mainnet_die "phase-16: temporary node failed to start from the generated mainnet genesis template"

if [[ "${launch_ready}" != "true" ]]; then
  [[ "$(jq -r '.launch_ready_blockers | length' "${MAINNET_METADATA_OUTPUT_PATH}")" != "0" ]] || mainnet_die "phase-16: non-launch-ready metadata must include at least one blocker"
  if [[ "${candidate_only}" == "true" ]]; then
    jq -e --arg reason "${candidate_reason}" '.launch_ready_blockers | index($reason) != null' "${MAINNET_METADATA_OUTPUT_PATH}" >/dev/null 2>&1 \
      || mainnet_die "phase-16: candidate-only metadata must list the candidate allocation reason"
  fi
  if [[ "${gentx_count}" == "0" ]]; then
    jq -e '.launch_ready_blockers | index("missing real validator gentx files") != null' "${MAINNET_METADATA_OUTPUT_PATH}" >/dev/null 2>&1 \
      || mainnet_die "phase-16: non-launch-ready metadata must list missing real validator gentx files when gentx_count is zero"
  fi
fi

echo "mainnet-genesis-validate: PASS (template-valid=${MAINNET_GENESIS_OUTPUT_PATH}; launch-ready=${launch_ready})"
