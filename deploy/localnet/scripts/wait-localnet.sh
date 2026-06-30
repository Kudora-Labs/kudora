#!/usr/bin/env bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

require_command curl
require_command jq

deadline=$(( $(date +%s) + LOCALNET_WAIT_TIMEOUT ))
status_file="${LOCALNET_SMOKE_DIR}/wait-status.json"
chain_id_response_file="${LOCALNET_SMOKE_DIR}/wait-eth-chainid.json"

mkdir -p "${LOCALNET_SMOKE_DIR}"

wait_for_url() {
  local url="$1"
  while (( $(date +%s) < deadline )); do
    if curl -sf "${url}" >/dev/null; then
      return 0
    fi
    sleep 1
  done
  return 1
}

wait_for_url "${LOCALNET_RPC_URL}/health" || die "localnet-wait: CometBFT RPC never became healthy at ${LOCALNET_RPC_URL}"
wait_for_url "${LOCALNET_REST_URL}/cosmos/base/tendermint/v1beta1/node_info" || die "localnet-wait: REST API never became healthy at ${LOCALNET_REST_URL}"

while (( $(date +%s) < deadline )); do
  if curl -sf "${LOCALNET_RPC_URL}/status" >"${status_file}" 2>/dev/null; then
    height="$(jq -r '.result.sync_info.latest_block_height // "0"' "${status_file}")"
    if [[ "${height}" =~ ^[0-9]+$ ]] && (( height > 0 )); then
      break
    fi
  fi
  sleep 1
done

[[ "${height:-0}" =~ ^[0-9]+$ ]] && (( height > 0 )) || die "localnet-wait: block height never advanced"

while (( $(date +%s) < deadline )); do
  if curl -sS -H 'Content-Type: application/json' \
    --data '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' \
    "${LOCALNET_EVM_RPC_URL}" >"${chain_id_response_file}" 2>/dev/null; then
    if jq -e --arg expected "${LOCALNET_ETH_CHAIN_ID}" '.error == null and .result == $expected' "${chain_id_response_file}" >/dev/null; then
      echo "localnet-wait: PASS (height=${height} eth_chainId=${LOCALNET_ETH_CHAIN_ID})"
      exit 0
    fi
  fi
  sleep 1
done

die "localnet-wait: eth_chainId never became ${LOCALNET_ETH_CHAIN_ID} at ${LOCALNET_EVM_RPC_URL}"
