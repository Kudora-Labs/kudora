#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

BINARY="${ROOT_DIR}/build/kudorad"
USE_EXISTING_NODE="${KUDORA_USE_EXISTING_NODE:-0}"
CHAIN_ID="${KUDORA_CHAIN_ID:-kudora_12000-1}"
EVM_CHAIN_ID="${KUDORA_EVM_CHAIN_ID:-120001}"
EXPECTED_ETH_CHAIN_ID="${KUDORA_ETH_CHAIN_ID:-0x1d4c1}"

if [[ "${USE_EXISTING_NODE}" == "1" ]]; then
  WORK_ROOT="${KUDORA_RESULT_DIR:-${ROOT_DIR}/tmp/localnet}"
  WORK_DIR="${WORK_ROOT}/evm-smoke"
  HOME_DIR=""
  COMET_RPC_URL="${KUDORA_RPC_URL:-http://127.0.0.1:26657}"
  JSONRPC_URL="${KUDORA_EVM_RPC_URL:-http://127.0.0.1:8545}"
else
  HOME_DIR="${ROOT_DIR}/tmp/phase-3-evm-smoke"
  WORK_DIR="${HOME_DIR}"
  COMET_RPC_PORT="${KUDORA_EVM_SMOKE_COMET_RPC_PORT:-26657}"
  JSONRPC_PORT="${KUDORA_EVM_SMOKE_JSONRPC_PORT:-8545}"
  JSONRPC_WS_PORT="${KUDORA_EVM_SMOKE_JSONRPC_WS_PORT:-8546}"
  COMET_RPC_URL="http://127.0.0.1:${COMET_RPC_PORT}"
  JSONRPC_URL="http://127.0.0.1:${JSONRPC_PORT}"
fi

LOG_DIR="${WORK_DIR}/logs"
HELPER_BIN="${WORK_DIR}/evm-smoke-helper"
QUERY_KEY_FILE="${WORK_DIR}/query.key"
QUERY_INFO_FILE="${WORK_DIR}/query.json"
RESULT_FILE="${WORK_DIR}/result.json"

command -v jq >/dev/null 2>&1 || {
  echo "evm-smoke-test: jq is required" >&2
  exit 1
}

command -v curl >/dev/null 2>&1 || {
  echo "evm-smoke-test: curl is required" >&2
  exit 1
}

jsonrpc_request() {
  local payload="$1"
  curl -sS -H 'Content-Type: application/json' --data "$payload" "${JSONRPC_URL}"
}

jsonrpc_has_no_error() {
  local response="$1"
  printf '%s\n' "$response" | jq -e 'has("error") | not' >/dev/null
}

wait_for_rpc_health() {
  local url="$1"

  for _ in $(seq 1 90); do
    if curl -sf "${url}/health" >/dev/null; then
      return 0
    fi
    sleep 1
  done

  return 1
}

wait_for_eth_chain_id() {
  local response=""

  for _ in $(seq 1 60); do
    response="$(jsonrpc_request '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' || true)"
    if jsonrpc_has_no_error "${response}" && [[ "$(printf '%s\n' "${response}" | jq -r '.result // empty')" == "${EXPECTED_ETH_CHAIN_ID}" ]]; then
      printf '%s\n' "${response}"
      return 0
    fi
    sleep 1
  done

  printf '%s\n' "${response}"
  return 1
}

wait_for_eth_block_number() {
  local response=""

  for _ in $(seq 1 60); do
    response="$(jsonrpc_request '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":2}' || true)"
    if jsonrpc_has_no_error "${response}" && printf '%s\n' "${response}" | jq -r '.result // empty' | rg -q '^0x[0-9a-f]+$' && [[ "$(printf '%s\n' "${response}" | jq -r '.result // empty')" != "0x0" ]]; then
      printf '%s\n' "${response}"
      return 0
    fi
    sleep 1
  done

  printf '%s\n' "${response}"
  return 1
}

wait_for_nonzero_balance() {
  local address="$1"
  local response=""
  local balance=""

  for _ in $(seq 1 60); do
    response="$(jsonrpc_request "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getBalance\",\"params\":[\"${address}\",\"latest\"],\"id\":3}" || true)"
    balance="$(printf '%s\n' "${response}" | jq -r '.result // empty' 2>/dev/null || true)"
    if jsonrpc_has_no_error "${response}" && printf '%s\n' "${balance}" | rg -q '^0x[1-9a-f][0-9a-f]*$'; then
      printf '%s\n' "${response}"
      return 0
    fi
    sleep 1
  done

  printf '%s\n' "${response}"
  return 1
}

rm -rf "${WORK_DIR}"
mkdir -p "${LOG_DIR}"

cleanup() {
  if [[ -n "${node_pid:-}" ]]; then
    kill "${node_pid}" >/dev/null 2>&1 || true
    wait "${node_pid}" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

if [[ "${USE_EXISTING_NODE}" != "1" ]]; then
  go build -o "${HELPER_BIN}" ./testutil/evm-smoke
fi

if [[ "${USE_EXISTING_NODE}" == "1" ]]; then
  info_file="${KUDORA_EVM_SMOKE_INFO_FILE:-${KUDORA_EVM_SENDER_INFO_FILE:-}}"
  if [[ -n "${info_file}" && -f "${info_file}" ]]; then
    query_eth_address="$(jq -r '.eth_address // empty' "${info_file}")"
  else
    query_eth_address="${KUDORA_EVM_SMOKE_ETH_ADDRESS:-}"
  fi

  [[ -n "${query_eth_address}" ]] || {
    echo "evm-smoke-test: existing-node mode requires KUDORA_EVM_SMOKE_INFO_FILE or KUDORA_EVM_SMOKE_ETH_ADDRESS" >&2
    exit 1
  }
else
  [[ -x "${BINARY}" ]] || {
    echo "evm-smoke-test: expected built binary at ${BINARY}. Run make build first." >&2
    exit 1
  }

  "${HELPER_BIN}" create-account \
    --key-file "${QUERY_KEY_FILE}" \
    --info-file "${QUERY_INFO_FILE}" \
    >"${LOG_DIR}/create-query.stdout" 2>"${LOG_DIR}/create-query.stderr"

  "${BINARY}" init smoke \
    --chain-id "${CHAIN_ID}" \
    --default-denom akud \
    --home "${HOME_DIR}" \
    >"${LOG_DIR}/init.stdout" 2>"${LOG_DIR}/init.stderr"

  validator_json="$("${BINARY}" keys add validator --keyring-backend test --home "${HOME_DIR}" --output json 2>"${LOG_DIR}/keys.stderr")"
  validator_address="$(printf '%s\n' "${validator_json}" | jq -r '.address // empty')"
  if [[ -z "${validator_address}" ]]; then
    echo "evm-smoke-test: could not derive validator address from key output" >&2
    exit 1
  fi
  unset validator_json

  query_cosmos_address="$(jq -r '.cosmos_address // empty' "${QUERY_INFO_FILE}")"
  query_eth_address="$(jq -r '.eth_address // empty' "${QUERY_INFO_FILE}")"
  if [[ -z "${query_cosmos_address}" || -z "${query_eth_address}" ]]; then
    echo "evm-smoke-test: could not derive funded EVM query account" >&2
    exit 1
  fi

  "${BINARY}" genesis add-genesis-account \
    "${validator_address}" \
    100000000000000000000akud \
    --home "${HOME_DIR}" \
    --keyring-backend test \
    >"${LOG_DIR}/add-genesis-account.stdout" 2>"${LOG_DIR}/add-genesis-account.stderr"

  "${BINARY}" genesis add-genesis-account \
    "${query_cosmos_address}" \
    500000000000000000000akud \
    --home "${HOME_DIR}" \
    >"${LOG_DIR}/add-query-account.stdout" 2>"${LOG_DIR}/add-query-account.stderr"

  "${BINARY}" genesis gentx \
    validator \
    1000000000000000000akud \
    --chain-id "${CHAIN_ID}" \
    --home "${HOME_DIR}" \
    --keyring-backend test \
    >"${LOG_DIR}/gentx.stdout" 2>"${LOG_DIR}/gentx.stderr"

  "${BINARY}" genesis collect-gentxs \
    --home "${HOME_DIR}" \
    >"${LOG_DIR}/collect-gentxs.stdout" 2>"${LOG_DIR}/collect-gentxs.stderr"

  rg -n '"chain_id": "kudora_12000-1"' "${HOME_DIR}/config/genesis.json" >/dev/null
  rg -n '"denom_metadata": \[' "${HOME_DIR}/config/genesis.json" >/dev/null
  rg -n '"evm_denom": "akud"' "${HOME_DIR}/config/genesis.json" >/dev/null
  rg -n '"no_base_fee": true' "${HOME_DIR}/config/genesis.json" >/dev/null
  rg -n 'type = "app"' "${HOME_DIR}/config/config.toml" >/dev/null
  rg -n 'evm-chain-id = 120001' "${HOME_DIR}/config/app.toml" >/dev/null

  "${BINARY}" start \
    --home "${HOME_DIR}" \
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

if ! wait_for_rpc_health "${COMET_RPC_URL}"; then
  echo "evm-smoke-test: CometBFT RPC never became healthy" >&2
  [[ -f "${LOG_DIR}/start.stderr" ]] && tail -n 80 "${LOG_DIR}/start.stderr" >&2 || true
  exit 1
fi

chain_id_response="$(wait_for_eth_chain_id || true)"
if ! jsonrpc_has_no_error "${chain_id_response}" || [[ "$(printf '%s\n' "${chain_id_response}" | jq -r '.result // empty')" != "${EXPECTED_ETH_CHAIN_ID}" ]]; then
  echo "evm-smoke-test: eth_chainId did not return ${EXPECTED_ETH_CHAIN_ID}" >&2
  printf 'last response: %s\n' "${chain_id_response:-<empty>}" >&2
  [[ -f "${LOG_DIR}/start.stderr" ]] && tail -n 80 "${LOG_DIR}/start.stderr" >&2 || true
  exit 1
fi

block_number_response="$(wait_for_eth_block_number || true)"
if ! jsonrpc_has_no_error "${block_number_response}" || ! printf '%s\n' "${block_number_response}" | jq -r '.result // empty' | rg -q '^0x[0-9a-f]+$' || [[ "$(printf '%s\n' "${block_number_response}" | jq -r '.result // empty')" == "0x0" ]]; then
  echo "evm-smoke-test: eth_blockNumber never reached a non-zero height" >&2
  printf 'last response: %s\n' "${block_number_response:-<empty>}" >&2
  [[ -f "${LOG_DIR}/start.stderr" ]] && tail -n 80 "${LOG_DIR}/start.stderr" >&2 || true
  exit 1
fi

balance_response="$(wait_for_nonzero_balance "${query_eth_address}" || true)"
if ! jsonrpc_has_no_error "${balance_response}" || ! printf '%s\n' "${balance_response}" | jq -r '.result // empty' | rg -q '^0x[1-9a-f][0-9a-f]*$'; then
  echo "evm-smoke-test: eth_getBalance did not return a non-zero balance for ${query_eth_address}" >&2
  printf 'response: %s\n' "${balance_response:-<empty>}" >&2
  [[ -f "${LOG_DIR}/start.stderr" ]] && tail -n 80 "${LOG_DIR}/start.stderr" >&2 || true
  exit 1
fi

net_response="$(jsonrpc_request '{"jsonrpc":"2.0","method":"net_version","params":[],"id":4}' || true)"
client_response=""
if ! jsonrpc_has_no_error "${net_response}" || [[ -z "$(printf '%s\n' "${net_response}" | jq -r '.result // empty')" ]]; then
  client_response="$(jsonrpc_request '{"jsonrpc":"2.0","method":"web3_clientVersion","params":[],"id":5}' || true)"
  if ! jsonrpc_has_no_error "${client_response}" || [[ -z "$(printf '%s\n' "${client_response}" | jq -r '.result // empty')" ]]; then
    echo "evm-smoke-test: neither net_version nor web3_clientVersion returned a valid response" >&2
    printf 'net_version response: %s\n' "${net_response:-<empty>}" >&2
    printf 'web3_clientVersion response: %s\n' "${client_response:-<empty>}" >&2
    [[ -f "${LOG_DIR}/start.stderr" ]] && tail -n 80 "${LOG_DIR}/start.stderr" >&2 || true
    exit 1
  fi
fi

jq -n \
  --arg chain_id "${CHAIN_ID}" \
  --arg evm_chain_id "${EVM_CHAIN_ID}" \
  --arg eth_chain_id "${EXPECTED_ETH_CHAIN_ID}" \
  --arg query_eth_address "${query_eth_address}" \
  --arg block_number "$(printf '%s\n' "${block_number_response}" | jq -r '.result')" \
  --arg balance "$(printf '%s\n' "${balance_response}" | jq -r '.result')" \
  --arg net_version "$(printf '%s\n' "${net_response}" | jq -r '.result // empty')" \
  --arg client_version "$(printf '%s\n' "${client_response}" | jq -r '.result // empty')" \
  '{
    chain_id: $chain_id,
    evm_chain_id: ($evm_chain_id | tonumber),
    eth_chain_id: $eth_chain_id,
    query_eth_address: $query_eth_address,
    block_number: $block_number,
    balance: $balance,
    net_version: $net_version,
    client_version: $client_version
  }' >"${RESULT_FILE}"

echo "evm-smoke-test: PASS (eth_chainId=${EXPECTED_ETH_CHAIN_ID}, eth_blockNumber=$(printf '%s\n' "${block_number_response}" | jq -r '.result'), eth_getBalance=$(printf '%s\n' "${balance_response}" | jq -r '.result'))"
