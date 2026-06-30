#!/usr/bin/env bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../common.sh"

cosmovisor_prepare_dirs
release_require_command jq
release_require_command curl
release_require_docker

rm -f "${COSMOVISOR_RESULT_PATH}"
"${ROOT_DIR}/deploy/cosmovisor/scripts/reset-cosmovisor.sh" >/dev/null
"${ROOT_DIR}/deploy/cosmovisor/scripts/init-cosmovisor-home.sh" >/dev/null
"${ROOT_DIR}/scripts/release/verify-cosmovisor-image.sh" >/dev/null

trap '"${ROOT_DIR}/deploy/cosmovisor/scripts/stop-cosmovisor.sh" >/dev/null 2>&1 || true' EXIT

version_output="$(docker run --rm \
  -e HOME=/home/nonroot \
  -e DAEMON_NAME=kudorad \
  -e DAEMON_HOME=/home/nonroot/.kudora \
  -e DAEMON_ALLOW_DOWNLOAD_BINARIES=false \
  -e UNSAFE_SKIP_BACKUP=false \
  -v "${COSMOVISOR_HOME_DIR}:${COSMOVISOR_RUNTIME_HOME}" \
  --entrypoint /usr/local/bin/cosmovisor \
  "${COSMOVISOR_IMAGE_TAG}" version 2>&1)"
run_version_output="$(docker run --rm \
  -e HOME=/home/nonroot \
  -e DAEMON_NAME=kudorad \
  -e DAEMON_HOME=/home/nonroot/.kudora \
  -e DAEMON_ALLOW_DOWNLOAD_BINARIES=false \
  -e UNSAFE_SKIP_BACKUP=false \
  -v "${COSMOVISOR_HOME_DIR}:${COSMOVISOR_RUNTIME_HOME}" \
  --entrypoint /usr/local/bin/cosmovisor \
  "${COSMOVISOR_IMAGE_TAG}" run version 2>&1)"

"${ROOT_DIR}/deploy/cosmovisor/scripts/start-cosmovisor.sh" >/dev/null

rpc_ready=0
for _ in $(seq 1 90); do
  if curl -sf "${COSMOVISOR_RPC_URL}/status" >/dev/null 2>&1; then
    rpc_ready=1
    break
  fi
  sleep 1
done

[[ "${rpc_ready}" == "1" ]] || release_die "phase-17: cosmovisor RPC did not become healthy"

eth_chain_id_response="$(
  curl -sS \
    -H 'Content-Type: application/json' \
    --data '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' \
    "${COSMOVISOR_EVM_RPC_URL}"
)"
printf '%s\n' "${eth_chain_id_response}" | jq -e --arg expected "${MAINNET_ETH_CHAIN_ID}" '.error == null and .result == $expected' >/dev/null \
  || release_die "phase-17: cosmovisor EVM RPC did not return ${MAINNET_ETH_CHAIN_ID}"

container_user="$(docker inspect "${COSMOVISOR_CONTAINER_NAME}" --format '{{.Config.User}}')"
[[ -n "${container_user}" && "${container_user}" != "0" && "${container_user}" != "root" ]] \
  || release_die "phase-17: running cosmovisor container must not use root"

jq -n \
  --arg generated_at_utc "$(release_now_utc)" \
  --arg cosmovisor_version_output "${version_output}" \
  --arg run_version_output "${run_version_output}" \
  --arg daemon_name "kudorad" \
  --arg daemon_home "${COSMOVISOR_RUNTIME_HOME}" \
  --arg rpc_url "${COSMOVISOR_RPC_URL}" \
  --arg evm_rpc_url "${COSMOVISOR_EVM_RPC_URL}" \
  --arg eth_chain_id "${MAINNET_ETH_CHAIN_ID}" \
  --arg container_user "${container_user}" \
  '{
    generated_at_utc: $generated_at_utc,
    cosmovisor_version_output: $cosmovisor_version_output,
    run_version_output: $run_version_output,
    daemon_name: $daemon_name,
    daemon_home: $daemon_home,
    rpc_url: $rpc_url,
    evm_rpc_url: $evm_rpc_url,
    eth_chain_id: $eth_chain_id,
    container_user: $container_user,
    auto_download_enabled: false,
    unsafe_skip_backup: false
  }' >"${COSMOVISOR_RESULT_PATH}"

echo "cosmovisor-smoke-test: PASS (${COSMOVISOR_RPC_URL})"
