#!/usr/bin/env bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

require_command jq
ensure_localnet_init_mode
prepare_localnet_dirs

HELPER_BIN="${LOCALNET_SMOKE_DIR}/evm-smoke-helper"
CONTAINER_EVM_SENDER_KEY_FILE="${LOCALNET_CONTAINER_HOME}/smoke/evm-sender.key"
CONTAINER_EVM_SENDER_INFO_FILE="${LOCALNET_CONTAINER_HOME}/smoke/evm-sender.json"
VALIDATOR_GENESIS_FUNDS="100000000000000000000${LOCALNET_DENOM}"
WASM_UPLOADER_FUNDS="100000000000000000000${LOCALNET_DENOM}"
INTEGRITY_PENDING_OWNER_FUNDS="20000000000000000000${LOCALNET_DENOM}"
EVM_SENDER_FUNDS="500000000000000000000${LOCALNET_DENOM}"
VALIDATOR_SELF_DELEGATION="1000000000000000000${LOCALNET_DENOM}"

rm -rf "${LOCALNET_HOME}"
mkdir -p "${LOCALNET_HOME}"
LOG_DIR="${LOCALNET_DIR}/init-logs"
rm -rf "${LOG_DIR}"
mkdir -p "${LOG_DIR}"

if [[ "${LOCALNET_INIT_MODE}" == "docker" ]]; then
  require_docker_access

  docker_init_ok=0
  for attempt in 1 2 3 4 5; do
    if docker_run_localnet_image init localnet-validator-0 \
      --chain-id "${LOCALNET_CHAIN_ID}" \
      --default-denom "${LOCALNET_DENOM}" \
      --home "${LOCALNET_CONTAINER_HOME}" \
      >"${LOG_DIR}/init.stdout" 2>"${LOG_DIR}/init.stderr"; then
      docker_init_ok=1
      break
    fi
    sleep 1
  done
  [[ "${docker_init_ok}" -eq 1 ]] || die "localnet-init: docker init failed after retries"

  validator_json="$(
    docker_run_localnet_image keys add validator \
      --keyring-backend test \
      --home "${LOCALNET_CONTAINER_HOME}" \
      --output json \
      2>"${LOG_DIR}/validator-key.stderr"
  )"
  wasm_uploader_json="$(
    docker_run_localnet_image keys add "${LOCALNET_WASM_UPLOADER_NAME}" \
      --keyring-backend test \
      --home "${LOCALNET_CONTAINER_HOME}" \
      --output json \
      2>"${LOG_DIR}/wasm-uploader-key.stderr"
  )"
  integrity_pending_owner_json="$(
    docker_run_localnet_image keys add "${LOCALNET_INTEGRITY_PENDING_OWNER_NAME}" \
      --keyring-backend test \
      --home "${LOCALNET_CONTAINER_HOME}" \
      --output json \
      2>"${LOG_DIR}/integrity-pending-owner-key.stderr"
  )"
else
  ensure_binary
  go build -o "${HELPER_BIN}" ./testutil/evm-smoke

  "${KUDORA_BINARY}" init localnet-validator-0 \
    --chain-id "${LOCALNET_CHAIN_ID}" \
    --default-denom "${LOCALNET_DENOM}" \
    --home "${LOCALNET_HOME}" \
    >"${LOG_DIR}/init.stdout" 2>"${LOG_DIR}/init.stderr"

  validator_json="$("${KUDORA_BINARY}" keys add validator --keyring-backend test --home "${LOCALNET_HOME}" --output json 2>"${LOG_DIR}/validator-key.stderr")"
  wasm_uploader_json="$("${KUDORA_BINARY}" keys add "${LOCALNET_WASM_UPLOADER_NAME}" --keyring-backend test --home "${LOCALNET_HOME}" --output json 2>"${LOG_DIR}/wasm-uploader-key.stderr")"
  integrity_pending_owner_json="$("${KUDORA_BINARY}" keys add "${LOCALNET_INTEGRITY_PENDING_OWNER_NAME}" --keyring-backend test --home "${LOCALNET_HOME}" --output json 2>"${LOG_DIR}/integrity-pending-owner-key.stderr")"
fi

mkdir -p "${LOCALNET_HOME}/smoke"

validator_address="$(printf '%s\n' "${validator_json}" | jq -r '.address // empty')"
wasm_uploader_address="$(printf '%s\n' "${wasm_uploader_json}" | jq -r '.address // empty')"
integrity_pending_owner_address="$(printf '%s\n' "${integrity_pending_owner_json}" | jq -r '.address // empty')"

[[ -n "${validator_address}" ]] || die "localnet-init: failed to derive validator address"
[[ -n "${wasm_uploader_address}" ]] || die "localnet-init: failed to derive wasm uploader address"
[[ -n "${integrity_pending_owner_address}" ]] || die "localnet-init: failed to derive integrity pending owner address"

if [[ "${LOCALNET_INIT_MODE}" == "docker" ]]; then
  docker_run_localnet_helper create-account \
    --key-file "${CONTAINER_EVM_SENDER_KEY_FILE}" \
    --info-file "${CONTAINER_EVM_SENDER_INFO_FILE}" \
    >"${LOG_DIR}/evm-sender.stdout" 2>"${LOG_DIR}/evm-sender.stderr"
else
  "${HELPER_BIN}" create-account \
    --key-file "${LOCALNET_EVM_SENDER_KEY_FILE}" \
    --info-file "${LOCALNET_EVM_SENDER_INFO_FILE}" \
    >"${LOG_DIR}/evm-sender.stdout" 2>"${LOG_DIR}/evm-sender.stderr"
fi

evm_sender_cosmos_address="$(jq -r '.cosmos_address // empty' "${LOCALNET_EVM_SENDER_INFO_FILE}")"
[[ -n "${evm_sender_cosmos_address}" ]] || die "localnet-init: failed to derive EVM sender cosmos address"

if [[ "${LOCALNET_INIT_MODE}" == "docker" ]]; then
  docker_run_localnet_image genesis add-genesis-account \
    "${validator_address}" \
    "${VALIDATOR_GENESIS_FUNDS}" \
    --home "${LOCALNET_CONTAINER_HOME}" \
    --keyring-backend test \
    >"${LOG_DIR}/validator-account.stdout" 2>"${LOG_DIR}/validator-account.stderr"

  docker_run_localnet_image genesis add-genesis-account \
    "${wasm_uploader_address}" \
    "${WASM_UPLOADER_FUNDS}" \
    --home "${LOCALNET_CONTAINER_HOME}" \
    --keyring-backend test \
    >"${LOG_DIR}/wasm-uploader-account.stdout" 2>"${LOG_DIR}/wasm-uploader-account.stderr"

  docker_run_localnet_image genesis add-genesis-account \
    "${integrity_pending_owner_address}" \
    "${INTEGRITY_PENDING_OWNER_FUNDS}" \
    --home "${LOCALNET_CONTAINER_HOME}" \
    --keyring-backend test \
    >"${LOG_DIR}/integrity-pending-owner-account.stdout" 2>"${LOG_DIR}/integrity-pending-owner-account.stderr"

  docker_run_localnet_image genesis add-genesis-account \
    "${evm_sender_cosmos_address}" \
    "${EVM_SENDER_FUNDS}" \
    --home "${LOCALNET_CONTAINER_HOME}" \
    >"${LOG_DIR}/evm-sender-account.stdout" 2>"${LOG_DIR}/evm-sender-account.stderr"

  docker_run_localnet_image genesis gentx \
    validator \
    "${VALIDATOR_SELF_DELEGATION}" \
    --chain-id "${LOCALNET_CHAIN_ID}" \
    --home "${LOCALNET_CONTAINER_HOME}" \
    --keyring-backend test \
    >"${LOG_DIR}/gentx.stdout" 2>"${LOG_DIR}/gentx.stderr"

  docker_run_localnet_image genesis collect-gentxs \
    --home "${LOCALNET_CONTAINER_HOME}" \
    >"${LOG_DIR}/collect-gentxs.stdout" 2>"${LOG_DIR}/collect-gentxs.stderr"
else
  "${KUDORA_BINARY}" genesis add-genesis-account \
    "${validator_address}" \
    "${VALIDATOR_GENESIS_FUNDS}" \
    --home "${LOCALNET_HOME}" \
    --keyring-backend test \
    >"${LOG_DIR}/validator-account.stdout" 2>"${LOG_DIR}/validator-account.stderr"

  "${KUDORA_BINARY}" genesis add-genesis-account \
    "${wasm_uploader_address}" \
    "${WASM_UPLOADER_FUNDS}" \
    --home "${LOCALNET_HOME}" \
    --keyring-backend test \
    >"${LOG_DIR}/wasm-uploader-account.stdout" 2>"${LOG_DIR}/wasm-uploader-account.stderr"

  "${KUDORA_BINARY}" genesis add-genesis-account \
    "${integrity_pending_owner_address}" \
    "${INTEGRITY_PENDING_OWNER_FUNDS}" \
    --home "${LOCALNET_HOME}" \
    --keyring-backend test \
    >"${LOG_DIR}/integrity-pending-owner-account.stdout" 2>"${LOG_DIR}/integrity-pending-owner-account.stderr"

  "${KUDORA_BINARY}" genesis add-genesis-account \
    "${evm_sender_cosmos_address}" \
    "${EVM_SENDER_FUNDS}" \
    --home "${LOCALNET_HOME}" \
    >"${LOG_DIR}/evm-sender-account.stdout" 2>"${LOG_DIR}/evm-sender-account.stderr"

  "${KUDORA_BINARY}" genesis gentx \
    validator \
    "${VALIDATOR_SELF_DELEGATION}" \
    --chain-id "${LOCALNET_CHAIN_ID}" \
    --home "${LOCALNET_HOME}" \
    --keyring-backend test \
    >"${LOG_DIR}/gentx.stdout" 2>"${LOG_DIR}/gentx.stderr"

  "${KUDORA_BINARY}" genesis collect-gentxs \
    --home "${LOCALNET_HOME}" \
    >"${LOG_DIR}/collect-gentxs.stdout" 2>"${LOG_DIR}/collect-gentxs.stderr"
fi

jq \
  --arg addr "${wasm_uploader_address}" \
  '.app_state.wasm.params.code_upload_access = {permission:"AnyOfAddresses", addresses:[$addr]}
   | .app_state.wasm.params.instantiate_default_permission = "AnyOfAddresses"' \
  "${LOCALNET_HOME}/config/genesis.json" >"${LOCALNET_HOME}/config/genesis.json.tmp"
mv "${LOCALNET_HOME}/config/genesis.json.tmp" "${LOCALNET_HOME}/config/genesis.json"

python_replacement_msg="localnet-init: expected generated config files are missing"
[[ -f "${LOCALNET_HOME}/config/config.toml" ]] || die "${python_replacement_msg}"
[[ -f "${LOCALNET_HOME}/config/app.toml" ]] || die "${python_replacement_msg}"
[[ -f "${LOCALNET_HOME}/config/client.toml" ]] || die "${python_replacement_msg}"

perl -0pi -e 's#laddr = "tcp://127\.0\.0\.1:26657"#laddr = "tcp://0.0.0.0:26657"#g' "${LOCALNET_HOME}/config/config.toml"
perl -0pi -e 's#cors_allowed_origins = \[\]#cors_allowed_origins = ["*"]#g' "${LOCALNET_HOME}/config/config.toml"
perl -0pi -e 's#addr_book_strict = true#addr_book_strict = false#g' "${LOCALNET_HOME}/config/config.toml"
perl -0pi -e 's#(?ms)(\[instrumentation\].*?prometheus = )false#${1}true#' "${LOCALNET_HOME}/config/config.toml"
perl -0pi -e 's#prometheus_listen_addr = \".*?\"#prometheus_listen_addr = \":26660\"#g' "${LOCALNET_HOME}/config/config.toml"
perl -0pi -e 's#node = "tcp://localhost:26657"#node = "tcp://localhost:26657"#g' "${LOCALNET_HOME}/config/client.toml"
perl -0pi -e 's#keyring-backend = "os"#keyring-backend = "test"#g' "${LOCALNET_HOME}/config/client.toml"
perl -0pi -e 's#chain-id = ".*?"#chain-id = "'"${LOCALNET_CHAIN_ID}"'"#g' "${LOCALNET_HOME}/config/client.toml"
perl -0pi -e 's#(?ms)(\[api\].*?enable = )false#${1}true#' "${LOCALNET_HOME}/config/app.toml"
perl -0pi -e 's#address = "tcp://localhost:1317"#address = "tcp://0.0.0.0:1317"#g' "${LOCALNET_HOME}/config/app.toml"
perl -0pi -e 's#enabled-unsafe-cors = false#enabled-unsafe-cors = true#g' "${LOCALNET_HOME}/config/app.toml"
perl -0pi -e 's#address = "localhost:9090"#address = "0.0.0.0:9090"#g' "${LOCALNET_HOME}/config/app.toml"
perl -0pi -e 's#(?ms)(\[json-rpc\].*?enable = )false#${1}true#' "${LOCALNET_HOME}/config/app.toml"
perl -0pi -e 's#address = "127\.0\.0\.1:8545"#address = "0.0.0.0:8545"#g' "${LOCALNET_HOME}/config/app.toml"
perl -0pi -e 's#ws-address = "127\.0\.0\.1:8546"#ws-address = "0.0.0.0:8546"#g' "${LOCALNET_HOME}/config/app.toml"
perl -0pi -e 's#evm-chain-id = [0-9]+#evm-chain-id = '"${LOCALNET_EVM_CHAIN_ID}"'#g' "${LOCALNET_HOME}/config/app.toml"

if [[ "${LOCALNET_INIT_MODE}" == "docker" ]]; then
  validated=0
  for attempt in 1 2 3 4 5; do
    if docker_run_localnet_image genesis validate --home "${LOCALNET_CONTAINER_HOME}" >"${LOG_DIR}/validate.stdout" 2>"${LOG_DIR}/validate.stderr"; then
      validated=1
      break
    fi
    sleep 1
  done
  [[ "${validated}" -eq 1 ]] || die "localnet-init: docker genesis validation failed after retries"
else
  "${KUDORA_BINARY}" genesis validate --home "${LOCALNET_HOME}" >"${LOG_DIR}/validate.stdout" 2>"${LOG_DIR}/validate.stderr"
fi

# The localnet container runs with the image's default non-root user, so the
# generated runtime config/state must remain readable and writable inside the
# bind mount. This applies only to ignored localnet state under .localnet/.
find "${LOCALNET_HOME}/config" -type d -exec chmod 755 {} +
find "${LOCALNET_HOME}/config" -type f -exec chmod 644 {} +
find "${LOCALNET_HOME}/data" -type d -exec chmod 755 {} +
find "${LOCALNET_HOME}/data" -type f -exec chmod 664 {} +

write_localnet_metadata "${validator_address}" "${wasm_uploader_address}" "${integrity_pending_owner_address}" "${LOCALNET_INIT_MODE}"

echo "localnet-init: PASS (${LOCALNET_HOME}; mode=${LOCALNET_INIT_MODE})"
