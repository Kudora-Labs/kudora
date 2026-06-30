#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT_DIR}/deploy/localnet/scripts/common.sh"

LOCALNET_VALIDATION_SMOKE_RESULT_PATH="${LOCALNET_SMOKE_DIR}/phase-13-smoke/result.json"
LOCALNET_VALIDATION_SMOKE_START_EPOCH=0

localnet_validation_file_mtime() {
  local path="$1"

  if stat -f '%m' "$path" >/dev/null 2>&1; then
    stat -f '%m' "$path"
  else
    stat -c '%Y' "$path"
  fi
}

localnet_validation_make_go_free_path() {
  local tmpbin
  tmpbin="$(mktemp -d)"
  local cmd
  local cmd_path
  local required_commands=(
    awk
    bash
    chmod
    curl
    date
    dirname
    docker
    env
    find
    chown
    id
    jq
    ln
    make
    mkdir
    mv
    perl
    pwd
    rg
    rm
    sh
    sleep
    stat
  )

  for cmd in "${required_commands[@]}"; do
    cmd_path="$(command -v "${cmd}" 2>/dev/null || true)"
    [[ -n "${cmd_path}" ]] || continue
    ln -sf "${cmd_path}" "${tmpbin}/${cmd}"
  done

  printf '%s\n' "${tmpbin}"
}

localnet_validation_run_default_docker_init() {
  local backup_binary=""
  local tmpbin=""
  local status=0

  if [[ -f "${KUDORA_BINARY}" ]]; then
    backup_binary="${KUDORA_BINARY}.phase13.bak"
    mv "${KUDORA_BINARY}" "${backup_binary}"
  fi

  tmpbin="$(localnet_validation_make_go_free_path)"

  (
    export PATH="${tmpbin}"
    unset KUDORA_LOCALNET_INIT_MODE
    make localnet-init
  ) || status=$?

  rm -rf "${tmpbin}"

  if [[ -n "${backup_binary}" && -f "${backup_binary}" ]]; then
    mv "${backup_binary}" "${KUDORA_BINARY}"
  fi

  return "${status}"
}

localnet_validation_check_compose_user_strategy() {
  if ! rg -n 'user:\s*"\$\{LOCALNET_RUNTIME_UID:-65532\}:\$\{LOCALNET_RUNTIME_GID:-65532\}"' "${COMPOSE_FILE}" >/dev/null \
    && ! rg -n 'user:\s*"\$\{LOCAL_UID:-1000\}:\$\{LOCAL_GID:-1000\}"' "${COMPOSE_FILE}" >/dev/null; then
    echo "localnet-validation: docker-compose.yml is missing a documented non-root runtime user strategy" >&2
    return 1
  fi

  rg -n 'name:\s*\$\{LOCALNET_DOCKER_NETWORK:-kudora-localnet\}' "${COMPOSE_FILE}" >/dev/null || {
    echo "localnet-validation: docker-compose.yml is missing the stable localnet network name" >&2
    return 1
  }
}

localnet_validation_check_init_metadata() {
  [[ -f "${METADATA_PATH}" ]] || {
    echo "localnet-validation: metadata file missing at ${METADATA_PATH}" >&2
    return 1
  }

  jq -e '
    .init_mode == "docker" and
    .host_binary_required == false and
    .host_go_required == false and
    (.docker_image // "" | length > 0) and
    (.container_user // "" | length > 0) and
    (.docker_network // "" | length > 0)
  ' "${METADATA_PATH}" >/dev/null || {
    echo "localnet-validation: metadata does not prove docker-first init mode" >&2
    return 1
  }
}

localnet_validation_check_container_user() {
  local container_user

  container_user="$(docker inspect "${LOCALNET_STATEFUL_SERVICE}" --format '{{.Config.User}}' 2>/dev/null || true)"
  [[ -n "${container_user}" ]] || {
    echo "localnet-validation: container user is empty for ${LOCALNET_STATEFUL_SERVICE}" >&2
    return 1
  }

  case "${container_user}" in
    0|0:0|root|root:root)
      echo "localnet-validation: container must not run as root" >&2
      return 1
      ;;
  esac
}

localnet_validation_run_smoke() {
  LOCALNET_VALIDATION_SMOKE_START_EPOCH="$(date +%s)"
  export LOCALNET_VALIDATION_SMOKE_START_EPOCH
  make localnet-smoke-test
}

localnet_validation_check_smoke_current_run() {
  [[ -f "${LOCALNET_VALIDATION_SMOKE_RESULT_PATH}" ]] || {
    echo "localnet-validation: smoke result missing at ${LOCALNET_VALIDATION_SMOKE_RESULT_PATH}" >&2
    return 1
  }

  jq -e --argjson run_start "${LOCALNET_VALIDATION_SMOKE_START_EPOCH}" '
    (.run_id // "" | length > 0) and
    .run_started_epoch >= $run_start and
    .run_finished_epoch >= .run_started_epoch and
    .height_before >= 0 and
    .height_after > .height_before and
    .height_delta == (.height_after - .height_before) and
    .height_delta > 0 and
    .rpc_status == "PASS" and
    .rest_status == "PASS" and
    .grpc_status == "PASS" and
    .evm_smoke_status == "PASS" and
    .evm_transaction_status == "PASS" and
    .evm_contract_status == "PASS" and
    .wasm_smoke_status == "PASS"
  ' "${LOCALNET_VALIDATION_SMOKE_RESULT_PATH}" >/dev/null || {
    echo "localnet-validation: localnet smoke result is stale or incomplete" >&2
    return 1
  }
}
