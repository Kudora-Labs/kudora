#!/usr/bin/env bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

keep_state=0
if [[ "${1:-}" == "--keep-state" ]]; then
  keep_state=1
fi

wait_for_localnet_container_absent() {
  local timeout="${1:-30}"
  local deadline=$((SECONDS + timeout))

  while docker inspect "${LOCALNET_STATEFUL_SERVICE}" >/dev/null 2>&1; do
    if (( SECONDS >= deadline )); then
      die "localnet-reset: timed out waiting for ${LOCALNET_STATEFUL_SERVICE} to stop"
    fi
    sleep 1
  done
}

if detect_compose; then
  COMPOSE_PROJECT_NAME="${LOCALNET_PROJECT_NAME}" \
  LOCALNET_RUNTIME_UID="${LOCALNET_RUNTIME_UID}" \
  LOCALNET_RUNTIME_GID="${LOCALNET_RUNTIME_GID}" \
  KUDORA_DOCKER_IMAGE="${LOCALNET_DOCKER_IMAGE}" \
  "${COMPOSE_CMD[@]}" -f "${COMPOSE_FILE}" down --remove-orphans >/dev/null 2>&1 || true
fi

if docker version >/dev/null 2>&1; then
  wait_for_localnet_container_absent
fi

if (( keep_state == 0 )); then
  rm -rf "${LOCALNET_SMOKE_DIR}"
  if [[ -d "${LOCALNET_HOME}" ]]; then
    docker_cleanup_localnet_home >/dev/null 2>&1 || true
  fi
  rm -rf "${LOCALNET_DIR}"

  [[ ! -e "${LOCALNET_DIR}" ]] || die "localnet-reset: localnet state directory still exists at ${LOCALNET_DIR}"
  [[ ! -e "${LOCALNET_SMOKE_DIR}" ]] || die "localnet-reset: localnet smoke directory still exists at ${LOCALNET_SMOKE_DIR}"
fi

if (( keep_state == 0 )); then
  echo "localnet-reset: PASS (state removed)"
else
  echo "localnet-reset: PASS (containers stopped; state kept)"
fi
