#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${ROOT_DIR}/deploy/localnet/scripts/common.sh"

EXPLORERS_DIR="${ROOT_DIR}/deploy/explorers"

BLOCKSCOUT_COMPOSE_FILE="${EXPLORERS_DIR}/blockscout/docker-compose.yml"
PING_DASHBOARD_COMPOSE_FILE="${EXPLORERS_DIR}/ping-dashboard/docker-compose.yml"

BLOCKSCOUT_PROXY_TEMPLATE="${EXPLORERS_DIR}/blockscout/proxy/explorer.conf.template"
PING_DASHBOARD_DOCKERFILE="${EXPLORERS_DIR}/ping-dashboard/Dockerfile"
PING_DASHBOARD_CONFIG_FILE="${EXPLORERS_DIR}/ping-dashboard/config/kudora.json"

BLOCKSCOUT_UI_URL="${BLOCKSCOUT_UI_URL:-http://127.0.0.1:4000}"
BLOCKSCOUT_API_URL="${BLOCKSCOUT_API_URL:-http://127.0.0.1:4000/api/v2}"
PING_DASHBOARD_UI_URL="${PING_DASHBOARD_UI_URL:-http://127.0.0.1:18088}"

BLOCKSCOUT_RESULT_DIR="${ROOT_DIR}/tmp/phase-14-blockscout"
BLOCKSCOUT_RESULT_PATH="${BLOCKSCOUT_RESULT_DIR}/result.json"
PING_DASHBOARD_RESULT_DIR="${ROOT_DIR}/tmp/phase-14-ping-dashboard"
PING_DASHBOARD_RESULT_PATH="${PING_DASHBOARD_RESULT_DIR}/result.json"

BLOCKSCOUT_UPSTREAM_COMMIT="${BLOCKSCOUT_UPSTREAM_COMMIT:-f7039b5e41da2b01dc2b2d33bbbca0ab0be29aff}"
PING_DASHBOARD_UPSTREAM_COMMIT="${PING_DASHBOARD_UPSTREAM_COMMIT:-f001c4f40256d883c67cfdefdbd5c70414de17c9}"

BLOCKSCOUT_BACKEND_IMAGE="${BLOCKSCOUT_BACKEND_IMAGE:-ghcr.io/blockscout/blockscout@sha256:7659f168e4e2f6b73dd559ae5278fe96ba67bc2905ea01b57a814c68adf5a9dc}"
BLOCKSCOUT_FRONTEND_IMAGE="${BLOCKSCOUT_FRONTEND_IMAGE:-ghcr.io/blockscout/frontend@sha256:4b69f44148414b55c6b8550bc3270c63c9f99e923d54ef0b307e762af6bac90a}"
PING_DASHBOARD_IMAGE="${PING_DASHBOARD_IMAGE:-kudora/ping-dashboard:localnet}"

BLOCKSCOUT_PROJECT_NAME="${BLOCKSCOUT_PROJECT_NAME:-kudora-blockscout}"
PING_DASHBOARD_PROJECT_NAME="${PING_DASHBOARD_PROJECT_NAME:-kudora-ping-dashboard}"

BLOCKSCOUT_BACKEND_CONTAINER="${BLOCKSCOUT_BACKEND_CONTAINER:-kudora-blockscout-backend}"
BLOCKSCOUT_FRONTEND_CONTAINER="${BLOCKSCOUT_FRONTEND_CONTAINER:-kudora-blockscout-frontend}"
BLOCKSCOUT_PROXY_CONTAINER="${BLOCKSCOUT_PROXY_CONTAINER:-kudora-blockscout-proxy}"
PING_DASHBOARD_CONTAINER="${PING_DASHBOARD_CONTAINER:-kudora-ping-dashboard}"

blockscout_compose() {
  require_compose
  COMPOSE_PROJECT_NAME="${BLOCKSCOUT_PROJECT_NAME}" \
  LOCALNET_DOCKER_NETWORK="${LOCALNET_DOCKER_NETWORK}" \
  BLOCKSCOUT_BACKEND_IMAGE="${BLOCKSCOUT_BACKEND_IMAGE}" \
  BLOCKSCOUT_FRONTEND_IMAGE="${BLOCKSCOUT_FRONTEND_IMAGE}" \
  "${COMPOSE_CMD[@]}" -f "${BLOCKSCOUT_COMPOSE_FILE}" "$@"
}

ping_dashboard_compose() {
  require_compose
  COMPOSE_PROJECT_NAME="${PING_DASHBOARD_PROJECT_NAME}" \
  LOCALNET_DOCKER_NETWORK="${LOCALNET_DOCKER_NETWORK}" \
  PING_DASHBOARD_IMAGE="${PING_DASHBOARD_IMAGE}" \
  PING_DASHBOARD_UPSTREAM_COMMIT="${PING_DASHBOARD_UPSTREAM_COMMIT}" \
  "${COMPOSE_CMD[@]}" -f "${PING_DASHBOARD_COMPOSE_FILE}" "$@"
}

require_localnet_running() {
  require_docker_access

  if ! docker inspect "${LOCALNET_STATEFUL_SERVICE}" >/dev/null 2>&1; then
    die "explorers: localnet service ${LOCALNET_STATEFUL_SERVICE} is not running; start it with make localnet-up"
  fi
}

wait_for_http() {
  local url="$1"
  local timeout="${2:-120}"
  local started
  started="$(date +%s)"

  while (( $(date +%s) - started < timeout )); do
    if curl -fsS "${url}" >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done

  return 1
}

explorer_file_mtime() {
  local path="$1"

  if stat -f '%m' "$path" >/dev/null 2>&1; then
    stat -f '%m' "$path"
  else
    stat -c '%Y' "$path"
  fi
}
