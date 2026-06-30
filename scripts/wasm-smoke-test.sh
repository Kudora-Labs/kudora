#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

BINARY="${ROOT_DIR}/build/kudorad"
USE_EXISTING_NODE="${KUDORA_USE_EXISTING_NODE:-0}"
WASM_FILE="${ROOT_DIR}/testutil/wasm/reflect_1_5.wasm"
WASM_SHA256="45de7a3ac8a72368a71c813d6b0cf7024f8b3581ffa1fc8d2c5fd4060f950c01"
CHAIN_ID="${KUDORA_CHAIN_ID:-kudora_12000-1}"
EVM_CHAIN_ID="${KUDORA_EVM_CHAIN_ID:-120001}"
EXPECTED_ETH_CHAIN_ID="${KUDORA_ETH_CHAIN_ID:-0x1d4c1}"
UPLOADER_GENESIS_FUNDS="100000000000000000000akud"
VALIDATOR_GENESIS_FUNDS="100000000000000000000akud"
VALIDATOR_SELF_DELEGATION="1000000000000000000akud"
TX_FEES="1000000000000000akud"
TX_GAS="5000000"

if [[ "${USE_EXISTING_NODE}" == "1" ]]; then
  NODE_HOME="${KUDORA_HOME:-}"
  WORK_ROOT="${KUDORA_RESULT_DIR:-${ROOT_DIR}/tmp/localnet}"
  WORK_DIR="${WORK_ROOT}/wasm-smoke"
  COMET_RPC_URL="${KUDORA_RPC_URL:-http://127.0.0.1:26657}"
  JSONRPC_URL="${KUDORA_EVM_RPC_URL:-http://127.0.0.1:8545}"
else
  NODE_HOME="${ROOT_DIR}/tmp/phase-5-wasm-smoke"
  WORK_DIR="${NODE_HOME}"
  COMET_RPC_PORT="${KUDORA_WASM_SMOKE_COMET_RPC_PORT:-28657}"
  JSONRPC_PORT="${KUDORA_WASM_SMOKE_JSONRPC_PORT:-8745}"
  JSONRPC_WS_PORT="${KUDORA_WASM_SMOKE_JSONRPC_WS_PORT:-8746}"
  COMET_RPC_URL="http://127.0.0.1:${COMET_RPC_PORT}"
  JSONRPC_URL="http://127.0.0.1:${JSONRPC_PORT}"
fi

LOG_DIR="${WORK_DIR}/logs"
RESULT_FILE="${WORK_DIR}/result.json"
NODE_RPC_ENDPOINT="tcp://${COMET_RPC_URL#http://}"

command -v jq >/dev/null 2>&1 || {
  echo "wasm-smoke-test: jq is required" >&2
  exit 1
}

command -v curl >/dev/null 2>&1 || {
  echo "wasm-smoke-test: curl is required" >&2
  exit 1
}

command -v shasum >/dev/null 2>&1 || {
  echo "wasm-smoke-test: shasum is required" >&2
  exit 1
}

if [[ ! -x "${BINARY}" ]]; then
  echo "wasm-smoke-test: expected built binary at ${BINARY}. Run make build first." >&2
  exit 1
fi

if [[ ! -f "${WASM_FILE}" ]]; then
  echo "wasm-smoke-test: expected test contract at ${WASM_FILE}" >&2
  exit 1
fi

if [[ "$(shasum -a 256 "${WASM_FILE}" | awk '{print $1}')" != "${WASM_SHA256}" ]]; then
  echo "wasm-smoke-test: test contract hash drifted from the documented upstream reflect_1_5.wasm artifact" >&2
  exit 1
fi

rm -rf "${WORK_DIR}"
mkdir -p "${LOG_DIR}"

cleanup() {
  if [[ -n "${node_pid:-}" ]]; then
    kill "${node_pid}" >/dev/null 2>&1 || true
    wait "${node_pid}" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

wait_for_chain_ready() {
  local status_file="$1"
  local height="0"

  for _ in $(seq 1 180); do
    if curl -sf "${COMET_RPC_URL}/status" >"${status_file}" 2>/dev/null; then
      height="$(jq -r '.result.sync_info.latest_block_height // "0"' "${status_file}")"
      if [[ -n "${height}" && "${height}" != "0" && "${height}" -ge 3 ]]; then
        sleep 2
        return 0
      fi
    fi
    sleep 1
  done

  echo "wasm-smoke-test: chain never reached a usable block height" >&2
  return 1
}

wait_for_tx() {
  local tx_hash="$1"
  local output_file="$2"
  local error_file="$3"

  for _ in $(seq 1 60); do
    if "${BINARY}" query tx "${tx_hash}" --node "${NODE_RPC_ENDPOINT}" --output json >"${output_file}" 2>"${error_file}"; then
      return 0
    fi
    sleep 1
  done

  echo "wasm-smoke-test: transaction ${tx_hash} was not queryable in time" >&2
  return 1
}

jsonrpc_request() {
  local payload="$1"
  curl -sS -H 'Content-Type: application/json' --data "${payload}" "${JSONRPC_URL}"
}

if [[ "${USE_EXISTING_NODE}" == "1" ]]; then
  [[ -d "${NODE_HOME}" ]] || {
    echo "wasm-smoke-test: existing-node mode requires KUDORA_HOME" >&2
    exit 1
  }

  uploader_name="${KUDORA_WASM_UPLOADER_KEY_NAME:-wasm-uploader}"
  validator_name="${KUDORA_WASM_VALIDATOR_KEY_NAME:-validator}"
  uploader_address="$("${BINARY}" keys show "${uploader_name}" --address --keyring-backend test --home "${NODE_HOME}")"
  validator_address="$("${BINARY}" keys show "${validator_name}" --address --keyring-backend test --home "${NODE_HOME}")"
else
  rm -rf "${NODE_HOME}"
  mkdir -p "${LOG_DIR}"

  "${BINARY}" init phase5-wasm \
    --chain-id "${CHAIN_ID}" \
    --default-denom akud \
    --home "${NODE_HOME}" \
    >"${LOG_DIR}/init.stdout" 2>"${LOG_DIR}/init.stderr"

  uploader_json="$("${BINARY}" keys add uploader --keyring-backend test --home "${NODE_HOME}" --output json 2>"${LOG_DIR}/uploader-key.stderr")"
  validator_json="$("${BINARY}" keys add validator --keyring-backend test --home "${NODE_HOME}" --output json 2>"${LOG_DIR}/validator-key.stderr")"

  uploader_address="$(printf '%s\n' "${uploader_json}" | jq -r '.address // empty')"
  validator_address="$(printf '%s\n' "${validator_json}" | jq -r '.address // empty')"
  if [[ -z "${uploader_address}" || -z "${validator_address}" ]]; then
    echo "wasm-smoke-test: could not derive test addresses" >&2
    exit 1
  fi

  "${BINARY}" genesis add-genesis-account \
    "${validator_address}" \
    "${VALIDATOR_GENESIS_FUNDS}" \
    --home "${NODE_HOME}" \
    --keyring-backend test \
    >"${LOG_DIR}/add-validator.stdout" 2>"${LOG_DIR}/add-validator.stderr"

  "${BINARY}" genesis add-genesis-account \
    "${uploader_address}" \
    "${UPLOADER_GENESIS_FUNDS}" \
    --home "${NODE_HOME}" \
    >"${LOG_DIR}/add-uploader.stdout" 2>"${LOG_DIR}/add-uploader.stderr"

  "${BINARY}" genesis gentx \
    validator \
    "${VALIDATOR_SELF_DELEGATION}" \
    --chain-id "${CHAIN_ID}" \
    --home "${NODE_HOME}" \
    --keyring-backend test \
    >"${LOG_DIR}/gentx.stdout" 2>"${LOG_DIR}/gentx.stderr"

  "${BINARY}" genesis collect-gentxs \
    --home "${NODE_HOME}" \
    >"${LOG_DIR}/collect-gentxs.stdout" 2>"${LOG_DIR}/collect-gentxs.stderr"

  jq \
    --arg addr "${uploader_address}" \
    '.app_state.wasm.params.code_upload_access = {permission:"AnyOfAddresses", addresses:[$addr]}
     | .app_state.wasm.params.instantiate_default_permission = "AnyOfAddresses"' \
    "${NODE_HOME}/config/genesis.json" \
    >"${NODE_HOME}/config/genesis.json.tmp"
  mv "${NODE_HOME}/config/genesis.json.tmp" "${NODE_HOME}/config/genesis.json"

  jq -e --arg addr "${uploader_address}" '
    .app_state.wasm.params.code_upload_access.permission == "AnyOfAddresses" and
    .app_state.wasm.params.code_upload_access.addresses == [$addr] and
    .app_state.wasm.params.instantiate_default_permission == "AnyOfAddresses"
  ' "${NODE_HOME}/config/genesis.json" >/dev/null || {
    echo "wasm-smoke-test: temporary wasm genesis policy patch did not apply cleanly" >&2
    exit 1
  }

  "${BINARY}" start \
    --home "${NODE_HOME}" \
    --minimum-gas-prices 0akud \
    --grpc.enable=false \
    --grpc-web.enable=false \
    --api.enable=false \
    --json-rpc.enable \
    --json-rpc.address "127.0.0.1:${JSONRPC_PORT}" \
    --json-rpc.ws-address "127.0.0.1:${JSONRPC_WS_PORT}" \
    --rpc.laddr "tcp://127.0.0.1:${COMET_RPC_PORT}" \
    --evm.evm-chain-id "${EVM_CHAIN_ID}" \
    >"${LOG_DIR}/start.stdout" 2>"${LOG_DIR}/start.stderr" &
  node_pid=$!
fi

wait_for_chain_ready "${LOG_DIR}/status.json"

eth_chain_id_response="$(jsonrpc_request '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}')"
if ! printf '%s\n' "${eth_chain_id_response}" | jq -e --arg expected "${EXPECTED_ETH_CHAIN_ID}" '.error == null and .result == $expected' >/dev/null; then
  echo "wasm-smoke-test: eth_chainId drifted after wasm integration" >&2
  printf 'response: %s\n' "${eth_chain_id_response}" >&2
  exit 1
fi

uploader_key_name="${KUDORA_WASM_UPLOADER_KEY_NAME:-uploader}"
if [[ "${USE_EXISTING_NODE}" != "1" ]]; then
  uploader_key_name="uploader"
fi

store_sync_json="$("${BINARY}" tx wasm store "${WASM_FILE}" \
  --from "${uploader_key_name}" \
  --keyring-backend test \
  --home "${NODE_HOME}" \
  --chain-id "${CHAIN_ID}" \
  --node "${NODE_RPC_ENDPOINT}" \
  -b sync \
  --yes \
  --gas "${TX_GAS}" \
  --fees "${TX_FEES}" \
  --output json \
  2>"${LOG_DIR}/store.stderr")"
printf '%s\n' "${store_sync_json}" >"${LOG_DIR}/store-sync.json"
store_txhash="$(printf '%s\n' "${store_sync_json}" | jq -r '.txhash // empty')"
if [[ -z "${store_txhash}" ]]; then
  echo "wasm-smoke-test: missing store tx hash" >&2
  exit 1
fi

wait_for_tx "${store_txhash}" "${LOG_DIR}/store-tx.json" "${LOG_DIR}/store-query.stderr"
jq -e '.code == 0' "${LOG_DIR}/store-tx.json" >/dev/null || {
  echo "wasm-smoke-test: store transaction failed" >&2
  jq -r '.raw_log' "${LOG_DIR}/store-tx.json" >&2
  exit 1
}

code_id="$(jq -r '.events[] | select(.type=="store_code") | .attributes[] | select(.key=="code_id") | .value' "${LOG_DIR}/store-tx.json" | tail -n1)"
if [[ -z "${code_id}" ]]; then
  echo "wasm-smoke-test: could not extract code id from store transaction" >&2
  exit 1
fi

instantiate_sync_json="$("${BINARY}" tx wasm instantiate "${code_id}" '{}' \
  --label reflect-smoke \
  --no-admin \
  --from "${uploader_key_name}" \
  --keyring-backend test \
  --home "${NODE_HOME}" \
  --chain-id "${CHAIN_ID}" \
  --node "${NODE_RPC_ENDPOINT}" \
  -b sync \
  --yes \
  --gas "${TX_GAS}" \
  --fees "${TX_FEES}" \
  --output json \
  2>"${LOG_DIR}/instantiate.stderr")"
printf '%s\n' "${instantiate_sync_json}" >"${LOG_DIR}/instantiate-sync.json"
instantiate_txhash="$(printf '%s\n' "${instantiate_sync_json}" | jq -r '.txhash // empty')"
if [[ -z "${instantiate_txhash}" ]]; then
  echo "wasm-smoke-test: missing instantiate tx hash" >&2
  exit 1
fi

wait_for_tx "${instantiate_txhash}" "${LOG_DIR}/instantiate-tx.json" "${LOG_DIR}/instantiate-query.stderr"
jq -e '.code == 0' "${LOG_DIR}/instantiate-tx.json" >/dev/null || {
  echo "wasm-smoke-test: instantiate transaction failed" >&2
  jq -r '.raw_log' "${LOG_DIR}/instantiate-tx.json" >&2
  exit 1
}

contract_address="$(jq -r '.events[] | select(.type=="instantiate") | .attributes[] | select(.key=="_contract_address") | .value' "${LOG_DIR}/instantiate-tx.json" | tail -n1)"
if [[ -z "${contract_address}" ]]; then
  echo "wasm-smoke-test: could not extract contract address from instantiate transaction" >&2
  exit 1
fi

"${BINARY}" query wasm contract-state smart "${contract_address}" '{"owner":{}}' \
  --node "${NODE_RPC_ENDPOINT}" \
  --output json \
  >"${LOG_DIR}/owner-before.json" 2>"${LOG_DIR}/owner-before.stderr"
owner_before="$(jq -r '.data.owner // empty' "${LOG_DIR}/owner-before.json")"
if [[ "${owner_before}" != "${uploader_address}" ]]; then
  echo "wasm-smoke-test: unexpected initial owner ${owner_before}" >&2
  exit 1
fi

execute_sync_json="$("${BINARY}" tx wasm execute "${contract_address}" "{\"change_owner\":{\"owner\":\"${validator_address}\"}}" \
  --from "${uploader_key_name}" \
  --keyring-backend test \
  --home "${NODE_HOME}" \
  --chain-id "${CHAIN_ID}" \
  --node "${NODE_RPC_ENDPOINT}" \
  -b sync \
  --yes \
  --gas "${TX_GAS}" \
  --fees "${TX_FEES}" \
  --output json \
  2>"${LOG_DIR}/execute.stderr")"
printf '%s\n' "${execute_sync_json}" >"${LOG_DIR}/execute-sync.json"
execute_txhash="$(printf '%s\n' "${execute_sync_json}" | jq -r '.txhash // empty')"
if [[ -z "${execute_txhash}" ]]; then
  echo "wasm-smoke-test: missing execute tx hash" >&2
  exit 1
fi

wait_for_tx "${execute_txhash}" "${LOG_DIR}/execute-tx.json" "${LOG_DIR}/execute-query.stderr"
jq -e '.code == 0' "${LOG_DIR}/execute-tx.json" >/dev/null || {
  echo "wasm-smoke-test: execute transaction failed" >&2
  jq -r '.raw_log' "${LOG_DIR}/execute-tx.json" >&2
  exit 1
}

"${BINARY}" query wasm contract-state smart "${contract_address}" '{"owner":{}}' \
  --node "${NODE_RPC_ENDPOINT}" \
  --output json \
  >"${LOG_DIR}/owner-after.json" 2>"${LOG_DIR}/owner-after.stderr"
owner_after="$(jq -r '.data.owner // empty' "${LOG_DIR}/owner-after.json")"
if [[ "${owner_after}" != "${validator_address}" ]]; then
  echo "wasm-smoke-test: owner update did not persist" >&2
  exit 1
fi

if git ls-files "${WORK_DIR}" | rg -q .; then
  echo "wasm-smoke-test: temporary wasm smoke result directory must not be tracked" >&2
  exit 1
fi

jq -n \
  --arg chain_id "${CHAIN_ID}" \
  --arg evm_chain_id "${EVM_CHAIN_ID}" \
  --arg eth_chain_id "${EXPECTED_ETH_CHAIN_ID}" \
  --arg uploader "${uploader_address}" \
  --arg validator "${validator_address}" \
  --arg code_id "${code_id}" \
  --arg contract "${contract_address}" \
  --arg store_txhash "${store_txhash}" \
  --arg instantiate_txhash "${instantiate_txhash}" \
  --arg execute_txhash "${execute_txhash}" \
  --arg owner_before "${owner_before}" \
  --arg owner_after "${owner_after}" \
  --arg wasm_file "${WASM_FILE}" \
  --arg wasm_sha256 "${WASM_SHA256}" \
  '{
    chain_id: $chain_id,
    evm_chain_id: ($evm_chain_id | tonumber),
    eth_chain_id: $eth_chain_id,
    uploader_address: $uploader,
    validator_address: $validator,
    code_id: ($code_id | tonumber),
    contract_address: $contract,
    store_txhash: $store_txhash,
    instantiate_txhash: $instantiate_txhash,
    execute_txhash: $execute_txhash,
    owner_before: $owner_before,
    owner_after: $owner_after,
    wasm_file: $wasm_file,
    wasm_sha256: $wasm_sha256
  }' >"${RESULT_FILE}"

echo "wasm-smoke-test: PASS (code_id=${code_id} contract=${contract_address})"
