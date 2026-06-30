#!/usr/bin/env bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../common.sh"

cosmovisor_prepare_dirs
release_require_command jq
release_require_command perl
mainnet_require_binary
release_require_docker
release_require_candidate_genesis

docker image inspect "${COSMOVISOR_RELEASE_IMAGE_TAG}" >/dev/null 2>&1 \
  || cosmovisor_die "phase-17: release Docker image missing: ${COSMOVISOR_RELEASE_IMAGE_TAG}; run make release-docker-build first"

rm -rf "${COSMOVISOR_HOME_DIR}"
mkdir -p "${COSMOVISOR_HOME_DIR}/cosmovisor/genesis/bin" "${COSMOVISOR_HOME_DIR}/cosmovisor/upgrades" "${COSMOVISOR_LOG_DIR}"

"${KUDORA_BINARY}" init phase17-cosmovisor \
  --chain-id "${MAINNET_CHAIN_ID}" \
  --default-denom "${MAINNET_BASE_DENOM}" \
  --home "${COSMOVISOR_HOME_DIR}" \
  >/dev/null 2>&1

cp "${MAINNET_GENESIS_OUTPUT_PATH}" "${COSMOVISOR_HOME_DIR}/config/genesis.json"

runtime_genesis_time="$(perl -MPOSIX=strftime -e 'print strftime("%Y-%m-%dT%H:%M:%SZ", gmtime(time() - 60))')"
jq --arg runtime_genesis_time "${runtime_genesis_time}" '.genesis_time = $runtime_genesis_time' \
  "${COSMOVISOR_HOME_DIR}/config/genesis.json" >"${COSMOVISOR_HOME_DIR}/config/genesis.json.tmp"
mv "${COSMOVISOR_HOME_DIR}/config/genesis.json.tmp" "${COSMOVISOR_HOME_DIR}/config/genesis.json"

"${KUDORA_BINARY}" keys add "${COSMOVISOR_VALIDATOR_KEY_NAME}" \
  --keyring-backend test \
  --home "${COSMOVISOR_HOME_DIR}" \
  --output json >/dev/null 2>&1

validator_address="$("${KUDORA_BINARY}" keys show "${COSMOVISOR_VALIDATOR_KEY_NAME}" --address --keyring-backend test --home "${COSMOVISOR_HOME_DIR}")"

"${KUDORA_BINARY}" genesis add-genesis-account \
  "${validator_address}" \
  "1000000000000000000${MAINNET_BASE_DENOM}" \
  --home "${COSMOVISOR_HOME_DIR}" \
  >/dev/null 2>&1

"${KUDORA_BINARY}" genesis gentx \
  "${COSMOVISOR_VALIDATOR_KEY_NAME}" \
  "1000000000000000000${MAINNET_BASE_DENOM}" \
  --chain-id "${MAINNET_CHAIN_ID}" \
  --home "${COSMOVISOR_HOME_DIR}" \
  --keyring-backend test \
  >/dev/null 2>&1

"${KUDORA_BINARY}" genesis collect-gentxs --home "${COSMOVISOR_HOME_DIR}" >/dev/null 2>&1
"${KUDORA_BINARY}" genesis validate --home "${COSMOVISOR_HOME_DIR}" >/dev/null 2>&1

release_container_id="$(docker create "${COSMOVISOR_RELEASE_IMAGE_TAG}")"
cleanup_release_container() {
  docker rm -f "${release_container_id}" >/dev/null 2>&1 || true
}
trap cleanup_release_container EXIT

docker cp "${release_container_id}:/usr/local/bin/${RELEASE_BINARY_NAME}" "${COSMOVISOR_HOME_DIR}/cosmovisor/genesis/bin/${RELEASE_BINARY_NAME}"
chmod 0755 "${COSMOVISOR_HOME_DIR}/cosmovisor/genesis/bin/${RELEASE_BINARY_NAME}"
ln -sfn "${COSMOVISOR_RUNTIME_HOME}/cosmovisor/genesis" "${COSMOVISOR_HOME_DIR}/cosmovisor/current"

cleanup_release_container
trap - EXIT

jq -n \
  --arg generated_at_utc "$(release_now_utc)" \
  --arg daemon_name "kudorad" \
  --arg daemon_home "${COSMOVISOR_RUNTIME_HOME}" \
  --arg runtime_genesis_time "${runtime_genesis_time}" \
  --arg chain_id "${MAINNET_CHAIN_ID}" \
  --arg evm_chain_id "${MAINNET_EVM_CHAIN_ID}" \
  --arg eth_chain_id "${MAINNET_ETH_CHAIN_ID}" \
  --arg validator_address "${validator_address}" \
  --arg release_image_tag "${COSMOVISOR_RELEASE_IMAGE_TAG}" \
  '{
    generated_at_utc: $generated_at_utc,
    daemon_name: $daemon_name,
    daemon_home: $daemon_home,
    runtime_genesis_time: $runtime_genesis_time,
    chain_id: $chain_id,
    evm_chain_id: ($evm_chain_id | tonumber),
    eth_chain_id: $eth_chain_id,
    validator_address: $validator_address,
    release_image_tag: $release_image_tag
  }' >"${COSMOVISOR_HOME_DIR}/cosmovisor-home.json"

echo "init-cosmovisor-home: PASS (${COSMOVISOR_HOME_DIR})"
