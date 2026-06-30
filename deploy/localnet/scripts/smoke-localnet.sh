#!/usr/bin/env bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

require_command curl
require_command jq
ensure_binary

RESULT_DIR="${LOCALNET_SMOKE_DIR}/phase-13-smoke"
RESULT_PATH="${RESULT_DIR}/result.json"
SMOKE_RUN_ID="$(date -u '+%Y%m%dT%H%M%SZ')"
RUN_STARTED_EPOCH="$(date +%s)"
rm -rf "${RESULT_DIR}"
mkdir -p "${RESULT_DIR}"

"${ROOT_DIR}/deploy/localnet/scripts/wait-localnet.sh" >/dev/null

height_before="$(curl -sf "${LOCALNET_RPC_URL}/status" | jq -r '.result.sync_info.latest_block_height // "0"')"
height_after="${height_before}"
block_wait_deadline=$(( $(date +%s) + 30 ))

[[ "${height_before}" =~ ^[0-9]+$ ]] || die "localnet-smoke: invalid initial height"

while (( $(date +%s) < block_wait_deadline )); do
  current_height="$(curl -sf "${LOCALNET_RPC_URL}/status" | jq -r '.result.sync_info.latest_block_height // "0"')"
  [[ "${current_height}" =~ ^[0-9]+$ ]] || die "localnet-smoke: invalid follow-up height"
  height_after="${current_height}"
  if (( height_after > height_before )); then
    break
  fi
  sleep 1
done

(( height_after > height_before )) || die "localnet-smoke: block height did not increase"
height_delta=$(( height_after - height_before ))

curl -sf "${LOCALNET_REST_URL}/cosmos/base/tendermint/v1beta1/node_info" >/dev/null

grpc_result="PASS"
if command -v grpcurl >/dev/null 2>&1; then
  grpcurl -plaintext "${LOCALNET_GRPC_URL}" list >/dev/null
else
  require_command nc
  nc -z "${LOCALNET_GRPC_URL%%:*}" "${LOCALNET_GRPC_URL##*:}" >/dev/null
fi

env \
  KUDORA_USE_EXISTING_NODE=1 \
  KUDORA_HOME="${LOCALNET_HOME}" \
  KUDORA_RPC_URL="${LOCALNET_RPC_URL}" \
  KUDORA_REST_URL="${LOCALNET_REST_URL}" \
  KUDORA_GRPC_URL="${LOCALNET_GRPC_URL}" \
  KUDORA_EVM_RPC_URL="${LOCALNET_EVM_RPC_URL}" \
  KUDORA_EVM_WS_URL="${LOCALNET_WS_URL}" \
  KUDORA_CHAIN_ID="${LOCALNET_CHAIN_ID}" \
  KUDORA_EVM_CHAIN_ID="${LOCALNET_EVM_CHAIN_ID}" \
  KUDORA_ETH_CHAIN_ID="${LOCALNET_ETH_CHAIN_ID}" \
  KUDORA_EVM_SENDER_KEY_FILE="${LOCALNET_EVM_SENDER_KEY_FILE}" \
  KUDORA_EVM_SENDER_INFO_FILE="${LOCALNET_EVM_SENDER_INFO_FILE}" \
  KUDORA_EVM_SMOKE_INFO_FILE="${LOCALNET_EVM_SENDER_INFO_FILE}" \
  KUDORA_WASM_UPLOADER_KEY_NAME="${LOCALNET_WASM_UPLOADER_NAME}" \
  KUDORA_RESULT_DIR="${RESULT_DIR}" \
  "${ROOT_DIR}/scripts/evm-smoke-test.sh"

env \
  KUDORA_USE_EXISTING_NODE=1 \
  KUDORA_HOME="${LOCALNET_HOME}" \
  KUDORA_RPC_URL="${LOCALNET_RPC_URL}" \
  KUDORA_REST_URL="${LOCALNET_REST_URL}" \
  KUDORA_GRPC_URL="${LOCALNET_GRPC_URL}" \
  KUDORA_EVM_RPC_URL="${LOCALNET_EVM_RPC_URL}" \
  KUDORA_EVM_WS_URL="${LOCALNET_WS_URL}" \
  KUDORA_CHAIN_ID="${LOCALNET_CHAIN_ID}" \
  KUDORA_EVM_CHAIN_ID="${LOCALNET_EVM_CHAIN_ID}" \
  KUDORA_ETH_CHAIN_ID="${LOCALNET_ETH_CHAIN_ID}" \
  KUDORA_EVM_SENDER_KEY_FILE="${LOCALNET_EVM_SENDER_KEY_FILE}" \
  KUDORA_EVM_SENDER_INFO_FILE="${LOCALNET_EVM_SENDER_INFO_FILE}" \
  KUDORA_RESULT_DIR="${RESULT_DIR}" \
  "${ROOT_DIR}/scripts/evm-transaction-smoke-test.sh"

env \
  KUDORA_USE_EXISTING_NODE=1 \
  KUDORA_HOME="${LOCALNET_HOME}" \
  KUDORA_RPC_URL="${LOCALNET_RPC_URL}" \
  KUDORA_REST_URL="${LOCALNET_REST_URL}" \
  KUDORA_GRPC_URL="${LOCALNET_GRPC_URL}" \
  KUDORA_EVM_RPC_URL="${LOCALNET_EVM_RPC_URL}" \
  KUDORA_EVM_WS_URL="${LOCALNET_WS_URL}" \
  KUDORA_CHAIN_ID="${LOCALNET_CHAIN_ID}" \
  KUDORA_EVM_CHAIN_ID="${LOCALNET_EVM_CHAIN_ID}" \
  KUDORA_ETH_CHAIN_ID="${LOCALNET_ETH_CHAIN_ID}" \
  KUDORA_EVM_SENDER_KEY_FILE="${LOCALNET_EVM_SENDER_KEY_FILE}" \
  KUDORA_EVM_SENDER_INFO_FILE="${LOCALNET_EVM_SENDER_INFO_FILE}" \
  KUDORA_RESULT_DIR="${RESULT_DIR}" \
  "${ROOT_DIR}/scripts/evm-contract-smoke-test.sh"

env \
  KUDORA_USE_EXISTING_NODE=1 \
  KUDORA_HOME="${LOCALNET_HOME}" \
  KUDORA_RPC_URL="${LOCALNET_RPC_URL}" \
  KUDORA_REST_URL="${LOCALNET_REST_URL}" \
  KUDORA_GRPC_URL="${LOCALNET_GRPC_URL}" \
  KUDORA_EVM_RPC_URL="${LOCALNET_EVM_RPC_URL}" \
  KUDORA_EVM_WS_URL="${LOCALNET_WS_URL}" \
  KUDORA_CHAIN_ID="${LOCALNET_CHAIN_ID}" \
  KUDORA_EVM_CHAIN_ID="${LOCALNET_EVM_CHAIN_ID}" \
  KUDORA_ETH_CHAIN_ID="${LOCALNET_ETH_CHAIN_ID}" \
  KUDORA_WASM_UPLOADER_KEY_NAME="${LOCALNET_WASM_UPLOADER_NAME}" \
  KUDORA_RESULT_DIR="${RESULT_DIR}" \
  "${ROOT_DIR}/scripts/wasm-smoke-test.sh"

RUN_FINISHED_EPOCH="$(date +%s)"

jq -n \
  --arg rpc "PASS" \
  --arg rest "PASS" \
  --arg grpc "${grpc_result}" \
  --arg evm_smoke "PASS" \
  --arg evm_transaction "PASS" \
  --arg evm_contract "PASS" \
  --arg wasm_smoke "PASS" \
  --arg run_id "${SMOKE_RUN_ID}" \
  --arg generated_at_utc "$(date -u '+%Y-%m-%d %H:%M:%S UTC')" \
  --arg run_started_epoch "${RUN_STARTED_EPOCH}" \
  --arg run_finished_epoch "${RUN_FINISHED_EPOCH}" \
  --arg height_before "${height_before}" \
  --arg height_after "${height_after}" \
  --arg height_delta "${height_delta}" \
  --arg eth_chain_id "${LOCALNET_ETH_CHAIN_ID}" \
  --arg rpc_url "${LOCALNET_RPC_URL}" \
  --arg rest_url "${LOCALNET_REST_URL}" \
  --arg grpc_url "${LOCALNET_GRPC_URL}" \
  --arg evm_rpc_url "${LOCALNET_EVM_RPC_URL}" \
  '{
    run_id: $run_id,
    generated_at_utc: $generated_at_utc,
    run_started_epoch: ($run_started_epoch | tonumber),
    run_finished_epoch: ($run_finished_epoch | tonumber),
    rpc_status: $rpc,
    rest_status: $rest,
    grpc_status: $grpc,
    evm_smoke_status: $evm_smoke,
    evm_transaction_status: $evm_transaction,
    evm_contract_status: $evm_contract,
    wasm_smoke_status: $wasm_smoke,
    height_before: ($height_before | tonumber),
    height_after: ($height_after | tonumber),
    height_delta: ($height_delta | tonumber),
    eth_chain_id: $eth_chain_id,
    rpc_url: $rpc_url,
    rest_url: $rest_url,
    grpc_url: $grpc_url,
    evm_rpc_url: $evm_rpc_url
  }' >"${RESULT_PATH}"

echo "localnet-smoke: PASS (rpc=${LOCALNET_RPC_URL} evm=${LOCALNET_EVM_RPC_URL} height=${height_before}->${height_after})"
