#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

BINARY="${ROOT_DIR}/build/kudorad"
USE_EXISTING_NODE="${KUDORA_USE_EXISTING_NODE:-0}"
CHAIN_ID="${KUDORA_CHAIN_ID:-kudora_12000-1}"
EVM_CHAIN_ID="${KUDORA_EVM_CHAIN_ID:-120001}"
EXPECTED_ETH_CHAIN_ID="${KUDORA_ETH_CHAIN_ID:-0x1d4c1}"
SENDER_GENESIS_FUNDS="500000000000000000000akud"
VALIDATOR_GENESIS_FUNDS="100000000000000000000akud"
VALIDATOR_SELF_DELEGATION="1000000000000000000akud"

if [[ "${USE_EXISTING_NODE}" == "1" ]]; then
  WORK_ROOT="${KUDORA_RESULT_DIR:-${ROOT_DIR}/tmp/localnet}"
  WORK_DIR="${WORK_ROOT}/evm-transaction-smoke"
  HOME_DIR="${KUDORA_HOME:-}"
  COMET_RPC_URL="${KUDORA_RPC_URL:-http://127.0.0.1:26657}"
  JSONRPC_URL="${KUDORA_EVM_RPC_URL:-http://127.0.0.1:8545}"
else
  HOME_DIR="${ROOT_DIR}/tmp/phase-4-evm-tx-smoke"
  WORK_DIR="${HOME_DIR}"
  COMET_RPC_PORT="${KUDORA_EVM_TX_SMOKE_COMET_RPC_PORT:-26667}"
  JSONRPC_PORT="${KUDORA_EVM_TX_SMOKE_JSONRPC_PORT:-8547}"
  JSONRPC_WS_PORT="${KUDORA_EVM_TX_SMOKE_JSONRPC_WS_PORT:-8548}"
  COMET_RPC_URL="http://127.0.0.1:${COMET_RPC_PORT}"
  JSONRPC_URL="http://127.0.0.1:${JSONRPC_PORT}"
fi

LOG_DIR="${WORK_DIR}/logs"
HELPER_BIN="${WORK_DIR}/evm-smoke-helper"
SENDER_KEY_FILE="${WORK_DIR}/sender.key"
SENDER_INFO_FILE="${WORK_DIR}/sender.json"
RECIPIENT_KEY_FILE="${WORK_DIR}/recipient.key"
RECIPIENT_INFO_FILE="${WORK_DIR}/recipient.json"
RESULT_FILE="${WORK_DIR}/result.json"

command -v jq >/dev/null 2>&1 || {
  echo "evm-transaction-smoke-test: jq is required" >&2
  exit 1
}

command -v curl >/dev/null 2>&1 || {
  echo "evm-transaction-smoke-test: curl is required" >&2
  exit 1
}

if [[ "${USE_EXISTING_NODE}" != "1" && ! -x "${BINARY}" ]]; then
  echo "evm-transaction-smoke-test: expected built binary at ${BINARY}. Run make build first." >&2
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

go build -o "${HELPER_BIN}" ./testutil/evm-smoke

if [[ "${USE_EXISTING_NODE}" == "1" ]]; then
  SENDER_KEY_FILE="${KUDORA_EVM_SENDER_KEY_FILE:-}"
  SENDER_INFO_FILE="${KUDORA_EVM_SENDER_INFO_FILE:-}"
  [[ -f "${SENDER_KEY_FILE}" ]] || {
    echo "evm-transaction-smoke-test: existing-node mode requires KUDORA_EVM_SENDER_KEY_FILE" >&2
    exit 1
  }
  [[ -f "${SENDER_INFO_FILE}" ]] || {
    echo "evm-transaction-smoke-test: existing-node mode requires KUDORA_EVM_SENDER_INFO_FILE" >&2
    exit 1
  }
else
  "${HELPER_BIN}" create-account \
    --key-file "${SENDER_KEY_FILE}" \
    --info-file "${SENDER_INFO_FILE}" \
    >"${LOG_DIR}/create-sender.stdout" 2>"${LOG_DIR}/create-sender.stderr"
fi

"${HELPER_BIN}" create-account \
  --key-file "${RECIPIENT_KEY_FILE}" \
  --info-file "${RECIPIENT_INFO_FILE}" \
  >"${LOG_DIR}/create-recipient.stdout" 2>"${LOG_DIR}/create-recipient.stderr"

sender_eth_address="$(jq -r '.eth_address' "${SENDER_INFO_FILE}")"
recipient_eth_address="$(jq -r '.eth_address' "${RECIPIENT_INFO_FILE}")"

if [[ "${USE_EXISTING_NODE}" != "1" ]]; then
  sender_cosmos_address="$(jq -r '.cosmos_address' "${SENDER_INFO_FILE}")"

  "${BINARY}" init phase4-tx \
    --chain-id "${CHAIN_ID}" \
    --default-denom akud \
    --home "${HOME_DIR}" \
    >"${LOG_DIR}/init.stdout" 2>"${LOG_DIR}/init.stderr"

  validator_json="$("${BINARY}" keys add validator --keyring-backend test --home "${HOME_DIR}" --output json 2>"${LOG_DIR}/validator-key.stderr")"
  validator_address="$(printf '%s\n' "${validator_json}" | jq -r '.address // empty')"
  if [[ -z "${validator_address}" ]]; then
    echo "evm-transaction-smoke-test: could not derive validator address" >&2
    exit 1
  fi
  unset validator_json

  "${BINARY}" genesis add-genesis-account \
    "${validator_address}" \
    "${VALIDATOR_GENESIS_FUNDS}" \
    --home "${HOME_DIR}" \
    --keyring-backend test \
    >"${LOG_DIR}/add-validator.stdout" 2>"${LOG_DIR}/add-validator.stderr"

  "${BINARY}" genesis add-genesis-account \
    "${sender_cosmos_address}" \
    "${SENDER_GENESIS_FUNDS}" \
    --home "${HOME_DIR}" \
    >"${LOG_DIR}/add-sender.stdout" 2>"${LOG_DIR}/add-sender.stderr"

  "${BINARY}" genesis gentx \
    validator \
    "${VALIDATOR_SELF_DELEGATION}" \
    --chain-id "${CHAIN_ID}" \
    --home "${HOME_DIR}" \
    --keyring-backend test \
    >"${LOG_DIR}/gentx.stdout" 2>"${LOG_DIR}/gentx.stderr"

  "${BINARY}" genesis collect-gentxs \
    --home "${HOME_DIR}" \
    >"${LOG_DIR}/collect-gentxs.stdout" 2>"${LOG_DIR}/collect-gentxs.stderr"

  rg -n '"chain_id": "kudora_12000-1"' "${HOME_DIR}/config/genesis.json" >/dev/null
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

for _ in $(seq 1 90); do
  if curl -sf "${COMET_RPC_URL}/health" >/dev/null; then
    break
  fi
  sleep 1
done

if ! curl -sf "${COMET_RPC_URL}/health" >/dev/null; then
  echo "evm-transaction-smoke-test: CometBFT RPC never became healthy" >&2
  [[ -f "${LOG_DIR}/start.stderr" ]] && tail -n 80 "${LOG_DIR}/start.stderr" >&2 || true
  exit 1
fi

chain_id_response=""
for _ in $(seq 1 60); do
  chain_id_response="$(
    curl -sS \
      -H 'Content-Type: application/json' \
      --data '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' \
      "${JSONRPC_URL}" || true
  )"
  if printf '%s\n' "${chain_id_response}" | jq -e --arg expected "${EXPECTED_ETH_CHAIN_ID}" '.error == null and .result == $expected' >/dev/null; then
    break
  fi
  sleep 1
done

if ! printf '%s\n' "${chain_id_response}" | jq -e --arg expected "${EXPECTED_ETH_CHAIN_ID}" '.error == null and .result == $expected' >/dev/null; then
  echo "evm-transaction-smoke-test: eth_chainId did not return ${EXPECTED_ETH_CHAIN_ID}" >&2
  printf 'last response: %s\n' "${chain_id_response:-<empty>}" >&2
  [[ -f "${LOG_DIR}/start.stderr" ]] && tail -n 80 "${LOG_DIR}/start.stderr" >&2 || true
  exit 1
fi

block_number_response=""
for _ in $(seq 1 60); do
  block_number_response="$(
    curl -sS \
      -H 'Content-Type: application/json' \
      --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":2}' \
      "${JSONRPC_URL}" || true
  )"
  if printf '%s\n' "${block_number_response}" | jq -e '.error == null and (.result // "" | test("^0x[0-9a-f]+$")) and .result != "0x0"' >/dev/null; then
    break
  fi
  sleep 1
done

if ! printf '%s\n' "${block_number_response}" | jq -e '.error == null and (.result // "" | test("^0x[0-9a-f]+$")) and .result != "0x0"' >/dev/null; then
  echo "evm-transaction-smoke-test: eth_blockNumber never reached a non-zero height" >&2
  printf 'last response: %s\n' "${block_number_response:-<empty>}" >&2
  [[ -f "${LOG_DIR}/start.stderr" ]] && tail -n 80 "${LOG_DIR}/start.stderr" >&2 || true
  exit 1
fi

"${HELPER_BIN}" transfer-smoke \
  --rpc-url "${JSONRPC_URL}" \
  --chain-id "${EVM_CHAIN_ID}" \
  --sender-key-file "${SENDER_KEY_FILE}" \
  --recipient-info-file "${RECIPIENT_INFO_FILE}" \
  --result-file "${RESULT_FILE}" \
  >"${LOG_DIR}/transfer.stdout" 2>"${LOG_DIR}/transfer.stderr"

jq -e '
  .receipt_status == "0x1" and
  .gas_used > 0 and
  .nonce_after == (.nonce_before + 1)
' "${RESULT_FILE}" >/dev/null

echo "evm-transaction-smoke-test: PASS (sender=${sender_eth_address} recipient=${recipient_eth_address} tx=$(jq -r '.transaction_hash' "${RESULT_FILE}"))"
