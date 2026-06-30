#!/usr/bin/env bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

mainnet_prepare_dirs
mainnet_require_command jq
mainnet_require_command bc
mainnet_require_binary

allocations_file="$(mainnet_allocations_file)"
rm -rf "${MAINNET_TEMPLATE_HOME}" "${MAINNET_RUNTIME_HOME}" "${MAINNET_OUTPUT_DIR}"
rm -f "${PHASE16_BLOCKER_PATH}"

mainnet_require_allocations_file
mainnet_validate_allocations_json "${allocations_file}"

genesis_time="$(mainnet_allocations_genesis_time "${allocations_file}")"
candidate_only="$(mainnet_allocations_candidate_only "${allocations_file}")"
candidate_reason="$(mainnet_allocations_candidate_reason "${allocations_file}")"
allocation_1_address="$(jq -r '.allocations[0].address' "${allocations_file}")"
allocation_2_address="$(jq -r '.allocations[1].address' "${allocations_file}")"
distribution_module_address="$(mainnet_module_address distribution)"
gentx_count="$(find "${MAINNET_GENTX_DIR}" -mindepth 1 -maxdepth 1 -type f -name '*.json' | wc -l | tr -d ' ')"
launch_ready="true"
launch_ready_blockers=()

if [[ "${candidate_only}" == "true" ]]; then
  launch_ready="false"
  launch_ready_blockers+=("${candidate_reason}")
fi

if [[ "${gentx_count}" == "0" ]]; then
  launch_ready="false"
  launch_ready_blockers+=("missing real validator gentx files")
fi

launch_ready_reason="$(mainnet_join_by '; ' "${launch_ready_blockers[@]}")"

mkdir -p "${MAINNET_TEMPLATE_HOME}" "${MAINNET_TEMPLATE_HOME}/config/gentx" "${MAINNET_OUTPUT_DIR}"

"${KUDORA_BINARY}" init kudora-mainnet \
  --chain-id "${MAINNET_CHAIN_ID}" \
  --default-denom "${MAINNET_BASE_DENOM}" \
  --home "${MAINNET_TEMPLATE_HOME}" \
  >/dev/null 2>&1

"${KUDORA_BINARY}" genesis add-genesis-account \
  "${allocation_1_address}" \
  "${MAINNET_ALLOCATION_1_AKUD}${MAINNET_BASE_DENOM}" \
  --home "${MAINNET_TEMPLATE_HOME}" \
  >/dev/null 2>&1

"${KUDORA_BINARY}" genesis add-genesis-account \
  "${allocation_2_address}" \
  "${MAINNET_ALLOCATION_2_AKUD}${MAINNET_BASE_DENOM}" \
  --home "${MAINNET_TEMPLATE_HOME}" \
  >/dev/null 2>&1

"${KUDORA_BINARY}" genesis add-genesis-account \
  "${distribution_module_address}" \
  "${MAINNET_COMMUNITY_POOL_AKUD}${MAINNET_BASE_DENOM}" \
  --module-name distribution \
  --home "${MAINNET_TEMPLATE_HOME}" \
  >/dev/null 2>&1

if [[ "${gentx_count}" != "0" ]]; then
  cp "${MAINNET_GENTX_DIR}"/*.json "${MAINNET_TEMPLATE_HOME}/config/gentx/"
  "${KUDORA_BINARY}" genesis collect-gentxs --home "${MAINNET_TEMPLATE_HOME}" >/dev/null 2>&1
fi

jq \
  --arg chain_id "${MAINNET_CHAIN_ID}" \
  --arg genesis_time "${genesis_time}" \
  --arg denom "${MAINNET_BASE_DENOM}" \
  --arg amount "${MAINNET_COMMUNITY_POOL_AKUD}.000000000000000000" \
  '
    .chain_id = $chain_id
    | .genesis_time = $genesis_time
    | .app_state.distribution.fee_pool.community_pool = [
        {
          denom: $denom,
          amount: $amount
        }
      ]
  ' "${MAINNET_TEMPLATE_HOME}/config/genesis.json" >"${MAINNET_TEMPLATE_HOME}/config/genesis.json.tmp"
mv "${MAINNET_TEMPLATE_HOME}/config/genesis.json.tmp" "${MAINNET_TEMPLATE_HOME}/config/genesis.json"

"${KUDORA_BINARY}" genesis validate --home "${MAINNET_TEMPLATE_HOME}" >/dev/null 2>&1
cp "${MAINNET_TEMPLATE_HOME}/config/genesis.json" "${MAINNET_GENESIS_OUTPUT_PATH}"

jq -n \
  --arg allocations_file "${allocations_file}" \
  --arg chain_id "${MAINNET_CHAIN_ID}" \
  --arg genesis_time "${genesis_time}" \
  --arg denom "${MAINNET_BASE_DENOM}" \
  --arg display_denom "${MAINNET_DISPLAY_DENOM}" \
  --arg decimals "${MAINNET_DECIMALS}" \
  --arg evm_chain_id "${MAINNET_EVM_CHAIN_ID}" \
  --arg eth_chain_id "${MAINNET_ETH_CHAIN_ID}" \
  --arg total_supply "${MAINNET_TOTAL_SUPPLY_AKUD}" \
  --arg allocation_1_address "${allocation_1_address}" \
  --arg allocation_1_amount "${MAINNET_ALLOCATION_1_AKUD}" \
  --arg allocation_2_address "${allocation_2_address}" \
  --arg allocation_2_amount "${MAINNET_ALLOCATION_2_AKUD}" \
  --arg community_pool_amount "${MAINNET_COMMUNITY_POOL_AKUD}" \
  --arg distribution_module_address "${distribution_module_address}" \
  --arg gentx_count "${gentx_count}" \
  --arg allocation_mode "$(if [[ "${candidate_only}" == "true" ]]; then echo candidate_generated; else echo final_public; fi)" \
  --arg candidate_only "${candidate_only}" \
  --arg candidate_reason "${candidate_reason}" \
  --arg launch_ready "${launch_ready}" \
  --arg launch_ready_reason "${launch_ready_reason}" \
  --argjson launch_ready_blockers "$(printf '%s\n' "${launch_ready_blockers[@]}" | jq -R . | jq -s .)" \
  --arg genesis_output "${MAINNET_GENESIS_OUTPUT_PATH}" \
  '{
    generated_at_utc: (now | todateiso8601),
    allocations_file: $allocations_file,
    chain_id: $chain_id,
    genesis_time: $genesis_time,
    denom: $denom,
    display_denom: $display_denom,
    decimals: ($decimals | tonumber),
    evm_chain_id: ($evm_chain_id | tonumber),
    eth_chain_id: $eth_chain_id,
    allocation_mode: $allocation_mode,
    allocation_candidate_only: ($candidate_only == "true"),
    allocation_candidate_reason: $candidate_reason,
    total_supply: $total_supply,
    allocations: [
      {
        address: $allocation_1_address,
        amount: $allocation_1_amount
      },
      {
        address: $allocation_2_address,
        amount: $allocation_2_amount
      }
    ],
    community_pool_amount: $community_pool_amount,
    distribution_module_address: $distribution_module_address,
    gentx_count: ($gentx_count | tonumber),
    genesis_template_valid: true,
    mainnet_launch_ready: ($launch_ready == "true"),
    mainnet_launch_ready_reason: $launch_ready_reason,
    launch_ready_blockers: $launch_ready_blockers,
    genesis_output: $genesis_output
  }' >"${MAINNET_METADATA_OUTPUT_PATH}"

if [[ "${launch_ready}" == "true" ]]; then
  echo "mainnet-genesis-build: PASS (${MAINNET_GENESIS_OUTPUT_PATH}; launch-ready with ${gentx_count} gentx file(s))"
else
  echo "mainnet-genesis-build: PASS (${MAINNET_GENESIS_OUTPUT_PATH}; template-valid, not launch-ready: ${launch_ready_reason})"
fi
