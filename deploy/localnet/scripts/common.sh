#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
LOCALNET_DIR="${ROOT_DIR}/.localnet"
LOCALNET_HOME="${LOCALNET_DIR}/validator0"
LOCALNET_SMOKE_DIR="${ROOT_DIR}/tmp/localnet"
COMPOSE_FILE="${ROOT_DIR}/deploy/localnet/docker-compose.yml"
CONFIG_TEMPLATE_DIR="${ROOT_DIR}/deploy/localnet/config"
METADATA_PATH="${LOCALNET_HOME}/smoke/metadata.json"
KUDORA_BINARY="${ROOT_DIR}/build/kudorad"
LOCALNET_CHAIN_ID="${KUDORA_CHAIN_ID:-kudora_12000-1}"
LOCALNET_EVM_CHAIN_ID="${KUDORA_EVM_CHAIN_ID:-120001}"
LOCALNET_ETH_CHAIN_ID="${KUDORA_ETH_CHAIN_ID:-0x1d4c1}"
LOCALNET_DENOM="${KUDORA_DENOM:-akud}"
LOCALNET_DISPLAY_DENOM="${KUDORA_DISPLAY_DENOM:-KUD}"
LOCALNET_DOCKER_IMAGE="${KUDORA_DOCKER_IMAGE:-$(awk -F':= ' '/^DOCKER_IMAGE :=/ {print $2; exit}' "${ROOT_DIR}/Makefile")}"
LOCALNET_PROJECT_NAME="${LOCALNET_PROJECT_NAME:-kudora-localnet}"
LOCALNET_DOCKER_NETWORK="${LOCALNET_DOCKER_NETWORK:-kudora-localnet}"
LOCALNET_INIT_MODE="${KUDORA_LOCALNET_INIT_MODE:-docker}"
LOCALNET_UID="${LOCAL_UID:-$(id -u)}"
LOCALNET_GID="${LOCAL_GID:-$(id -g)}"
LOCALNET_RUNTIME_UID="${LOCALNET_RUNTIME_UID:-65532}"
LOCALNET_RUNTIME_GID="${LOCALNET_RUNTIME_GID:-65532}"
LOCALNET_CONTAINER_USER="${LOCALNET_RUNTIME_UID}:${LOCALNET_RUNTIME_GID}"
LOCALNET_CONTAINER_HOME="/home/nonroot/.kudora"
LOCALNET_CONTAINER_WORKDIR="/home/nonroot"
LOCALNET_RPC_URL="${KUDORA_RPC_URL:-http://127.0.0.1:26657}"
LOCALNET_REST_URL="${KUDORA_REST_URL:-http://127.0.0.1:1317}"
LOCALNET_GRPC_URL="${KUDORA_GRPC_URL:-127.0.0.1:9090}"
LOCALNET_EVM_RPC_URL="${KUDORA_EVM_RPC_URL:-http://127.0.0.1:8545}"
LOCALNET_WS_URL="${KUDORA_EVM_WS_URL:-ws://127.0.0.1:8546}"
LOCALNET_METRICS_URL="${KUDORA_METRICS_URL:-http://127.0.0.1:26660/metrics}"
LOCALNET_WAIT_TIMEOUT="${KUDORA_LOCALNET_WAIT_TIMEOUT:-180}"
LOCALNET_STATEFUL_SERVICE="kudora-validator-0"
LOCALNET_EVM_SENDER_KEY_FILE="${LOCALNET_HOME}/smoke/evm-sender.key"
LOCALNET_EVM_SENDER_INFO_FILE="${LOCALNET_HOME}/smoke/evm-sender.json"
LOCALNET_WASM_UPLOADER_NAME="${KUDORA_WASM_UPLOADER_KEY_NAME:-wasm-uploader}"
LOCALNET_INTEGRITY_PENDING_OWNER_NAME="${KUDORA_INTEGRITY_NEW_OWNER_KEY_NAME:-integrity-owner-b}"

die() {
  echo "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "localnet: required command not found: $1"
}

ensure_localnet_init_mode() {
  case "${LOCALNET_INIT_MODE}" in
    docker|host)
      ;;
    *)
      die "localnet: unsupported init mode '${LOCALNET_INIT_MODE}'; expected 'docker' or 'host'"
      ;;
  esac
}

ensure_binary() {
  if [[ ! -x "${KUDORA_BINARY}" ]]; then
    (cd "${ROOT_DIR}" && make build >/dev/null)
  fi

  [[ -x "${KUDORA_BINARY}" ]] || die "localnet: expected built binary at ${KUDORA_BINARY}"
}

ensure_localnet_image() {
  require_docker_access

  if ! docker image inspect "${LOCALNET_DOCKER_IMAGE}" >/dev/null 2>&1; then
    (cd "${ROOT_DIR}" && make docker-build >/dev/null)
  fi
}

detect_compose() {
  if docker compose version >/dev/null 2>&1; then
    COMPOSE_CMD=(docker compose)
    return 0
  fi

  if command -v docker-compose >/dev/null 2>&1; then
    COMPOSE_CMD=(docker-compose)
    return 0
  fi

  return 1
}

require_docker_access() {
  if ! docker version >/dev/null 2>&1; then
    die "localnet: docker daemon is not accessible from this shell session"
  fi
}

require_compose() {
  detect_compose || die "localnet: neither 'docker compose' nor 'docker-compose' is available"
}

compose() {
  require_compose
  COMPOSE_PROJECT_NAME="${LOCALNET_PROJECT_NAME}" \
  LOCALNET_RUNTIME_UID="${LOCALNET_RUNTIME_UID}" \
  LOCALNET_RUNTIME_GID="${LOCALNET_RUNTIME_GID}" \
  LOCALNET_DOCKER_NETWORK="${LOCALNET_DOCKER_NETWORK}" \
  KUDORA_DOCKER_IMAGE="${LOCALNET_DOCKER_IMAGE}" \
  "${COMPOSE_CMD[@]}" -f "${COMPOSE_FILE}" "$@"
}

docker_run_localnet_image() {
  ensure_localnet_image

  docker run --rm \
    --workdir "${LOCALNET_CONTAINER_WORKDIR}" \
    -e HOME="${LOCALNET_CONTAINER_WORKDIR}" \
    -v "${LOCALNET_HOME}:${LOCALNET_CONTAINER_HOME}" \
    "${LOCALNET_DOCKER_IMAGE}" "$@"
}

docker_run_localnet_helper() {
  ensure_localnet_image

  docker run --rm \
    --workdir "${LOCALNET_CONTAINER_WORKDIR}" \
    -e HOME="${LOCALNET_CONTAINER_WORKDIR}" \
    -v "${LOCALNET_HOME}:${LOCALNET_CONTAINER_HOME}" \
    --entrypoint /usr/local/bin/kudora-evm-smoke-helper \
    "${LOCALNET_DOCKER_IMAGE}" "$@"
}

docker_cleanup_localnet_home() {
  ensure_localnet_image

  mkdir -p "${LOCALNET_HOME}"

  docker run --rm \
    --workdir "${LOCALNET_CONTAINER_WORKDIR}" \
    -e HOME="${LOCALNET_CONTAINER_WORKDIR}" \
    -v "${LOCALNET_HOME}:${LOCALNET_CONTAINER_HOME}" \
    --entrypoint /usr/local/bin/kudora-evm-smoke-helper \
    "${LOCALNET_DOCKER_IMAGE}" cleanup-home --home-dir "${LOCALNET_CONTAINER_HOME}"
}

prepare_localnet_dirs() {
  mkdir -p "${LOCALNET_DIR}" "${LOCALNET_HOME}" "${LOCALNET_SMOKE_DIR}"
}

metadata_value() {
  local key="$1"
  [[ -f "${METADATA_PATH}" ]] || die "localnet: metadata file missing at ${METADATA_PATH}; run make localnet-init"
  jq -r "${key}" "${METADATA_PATH}"
}

write_localnet_metadata() {
  local validator_address="$1"
  local wasm_uploader_address="$2"
  local integrity_pending_owner_address="$3"
  local init_mode="$4"
  local host_binary_required="false"
  local host_go_required="false"

  if [[ "${init_mode}" == "host" ]]; then
    host_binary_required="true"
    host_go_required="true"
  fi

  jq -n \
    --slurpfile evm_sender "${LOCALNET_EVM_SENDER_INFO_FILE}" \
    --arg chain_id "${LOCALNET_CHAIN_ID}" \
    --arg evm_chain_id "${LOCALNET_EVM_CHAIN_ID}" \
    --arg eth_chain_id "${LOCALNET_ETH_CHAIN_ID}" \
    --arg denom "${LOCALNET_DENOM}" \
    --arg display_denom "${LOCALNET_DISPLAY_DENOM}" \
    --arg validator_name "validator" \
    --arg validator_address "${validator_address}" \
    --arg wasm_uploader_name "${LOCALNET_WASM_UPLOADER_NAME}" \
    --arg wasm_uploader_address "${wasm_uploader_address}" \
    --arg integrity_pending_owner_name "${LOCALNET_INTEGRITY_PENDING_OWNER_NAME}" \
    --arg integrity_pending_owner_address "${integrity_pending_owner_address}" \
    --arg evm_sender_key_file "${LOCALNET_EVM_SENDER_KEY_FILE}" \
    --arg evm_sender_info_file "${LOCALNET_EVM_SENDER_INFO_FILE}" \
    --arg init_mode "${init_mode}" \
    --arg docker_image "${LOCALNET_DOCKER_IMAGE}" \
    --arg container_user "${LOCALNET_CONTAINER_USER}" \
    --arg docker_network "${LOCALNET_DOCKER_NETWORK}" \
    --arg metrics_url "${LOCALNET_METRICS_URL}" \
    --argjson host_binary_required "${host_binary_required}" \
    --argjson host_go_required "${host_go_required}" \
    '{
      chain_id: $chain_id,
      evm_chain_id: ($evm_chain_id | tonumber),
      eth_chain_id: $eth_chain_id,
      base_denom: $denom,
      display_denom: $display_denom,
      init_mode: $init_mode,
      docker_image: $docker_image,
      container_user: $container_user,
      docker_network: $docker_network,
      metrics_url: $metrics_url,
      host_binary_required: $host_binary_required,
      host_go_required: $host_go_required,
      validator: {
        name: $validator_name,
        address: $validator_address
      },
      wasm_uploader: {
        name: $wasm_uploader_name,
        address: $wasm_uploader_address
      },
      integrity_pending_owner: {
        name: $integrity_pending_owner_name,
        address: $integrity_pending_owner_address
      },
      evm_sender: $evm_sender[0]
    }' >"${METADATA_PATH}"
}

compose_version_string() {
  if docker compose version >/dev/null 2>&1; then
    docker compose version 2>&1
    return 0
  fi

  if command -v docker-compose >/dev/null 2>&1; then
    docker-compose version 2>&1
    return 0
  fi

  echo "docker compose unavailable"
}
