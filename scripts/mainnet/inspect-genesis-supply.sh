#!/usr/bin/env bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

mainnet_prepare_dirs
mainnet_require_command jq
mainnet_require_command bc

allocations_file="$(mainnet_allocations_file)"
mainnet_require_real_allocations
mainnet_validate_allocations_json "${allocations_file}"
[[ -f "${MAINNET_GENESIS_OUTPUT_PATH}" ]] || mainnet_die "phase-16: generated genesis not found at ${MAINNET_GENESIS_OUTPUT_PATH}; run make mainnet-genesis-build first"

allocation_1_address="$(jq -r '.allocations[0].address' "${allocations_file}")"
allocation_2_address="$(jq -r '.allocations[1].address' "${allocations_file}")"

total_supply_akud="$(jq -r '.app_state.bank.supply[] | select(.denom == "'"${MAINNET_BASE_DENOM}"'") | .amount' "${MAINNET_GENESIS_OUTPUT_PATH}")"
allocation_1_akud="$(jq -r '.app_state.bank.balances[] | select(.address == "'"${allocation_1_address}"'") | .coins[] | select(.denom == "'"${MAINNET_BASE_DENOM}"'") | .amount' "${MAINNET_GENESIS_OUTPUT_PATH}")"
allocation_2_akud="$(jq -r '.app_state.bank.balances[] | select(.address == "'"${allocation_2_address}"'") | .coins[] | select(.denom == "'"${MAINNET_BASE_DENOM}"'") | .amount' "${MAINNET_GENESIS_OUTPUT_PATH}")"
community_pool_akud="$(jq -r '.app_state.distribution.fee_pool.community_pool[] | select(.denom == "'"${MAINNET_BASE_DENOM}"'") | .amount' "${MAINNET_GENESIS_OUTPUT_PATH}" | sed 's/\.000000000000000000$//')"
allocation_sum_akud="$(mainnet_bc_add "${allocation_1_akud}" "${allocation_2_akud}")"
supply_delta_akud="$(mainnet_bc_sub "${total_supply_akud}" "$(mainnet_bc_add "${allocation_sum_akud}" "${community_pool_akud}")")"

[[ "${total_supply_akud}" == "${MAINNET_TOTAL_SUPPLY_AKUD}" ]] || mainnet_die "phase-16: total_supply_akud mismatch"
[[ "${allocation_1_akud}" == "${MAINNET_ALLOCATION_1_AKUD}" ]] || mainnet_die "phase-16: allocation_1_akud mismatch"
[[ "${allocation_2_akud}" == "${MAINNET_ALLOCATION_2_AKUD}" ]] || mainnet_die "phase-16: allocation_2_akud mismatch"
[[ "${community_pool_akud}" == "${MAINNET_COMMUNITY_POOL_AKUD}" ]] || mainnet_die "phase-16: community_pool_akud mismatch"
[[ "${supply_delta_akud}" == "0" ]] || mainnet_die "phase-16: supply delta must be zero"

cat <<EOF
total_supply_akud=${total_supply_akud}
allocation_1_akud=${allocation_1_akud}
allocation_2_akud=${allocation_2_akud}
community_pool_akud=${community_pool_akud}
allocation_sum_akud=${allocation_sum_akud}
supply_delta_akud=${supply_delta_akud}
total_supply_KUD=$(mainnet_akud_to_kud "${total_supply_akud}")
allocation_1_KUD=$(mainnet_akud_to_kud "${allocation_1_akud}")
allocation_2_KUD=$(mainnet_akud_to_kud "${allocation_2_akud}")
community_pool_KUD=$(mainnet_akud_to_kud "${community_pool_akud}")
EOF
