#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${ROOT_DIR}/deploy/localnet/scripts/common.sh"

MONITORING_DIR="${ROOT_DIR}/deploy/monitoring"
MONITORING_COMPOSE_FILE="${MONITORING_DIR}/docker-compose.yml"
PROMETHEUS_CONFIG_FILE="${MONITORING_DIR}/prometheus/prometheus.yml"
PROMETHEUS_RULES_FILE="${MONITORING_DIR}/prometheus/alert-rules.yml"
BLACKBOX_CONFIG_FILE="${MONITORING_DIR}/blackbox/blackbox.yml"
GRAFANA_PROVISIONING_DIR="${MONITORING_DIR}/grafana/provisioning"
GRAFANA_DASHBOARDS_DIR="${MONITORING_DIR}/grafana/dashboards"

PROMETHEUS_IMAGE="${PROMETHEUS_IMAGE:-prom/prometheus:v3.12.0}"
BLACKBOX_EXPORTER_IMAGE="${BLACKBOX_EXPORTER_IMAGE:-quay.io/prometheus/blackbox-exporter:v0.28.0}"
GRAFANA_IMAGE="${GRAFANA_IMAGE:-grafana/grafana:13.0.2}"

PROMETHEUS_CONTAINER="${PROMETHEUS_CONTAINER:-kudora-prometheus}"
BLACKBOX_EXPORTER_CONTAINER="${BLACKBOX_EXPORTER_CONTAINER:-kudora-blackbox-exporter}"
GRAFANA_CONTAINER="${GRAFANA_CONTAINER:-kudora-grafana}"

MONITORING_PROJECT_NAME="${MONITORING_PROJECT_NAME:-kudora-monitoring}"
PROMETHEUS_UI_URL="${PROMETHEUS_UI_URL:-http://127.0.0.1:19090}"
PROMETHEUS_API_URL="${PROMETHEUS_API_URL:-${PROMETHEUS_UI_URL}/api/v1}"
GRAFANA_UI_URL="${GRAFANA_UI_URL:-http://127.0.0.1:3000}"
GRAFANA_API_URL="${GRAFANA_API_URL:-${GRAFANA_UI_URL}/api}"
GRAFANA_ADMIN_USER="${GRAFANA_ADMIN_USER:-admin}"
GRAFANA_ADMIN_PASSWORD="${GRAFANA_ADMIN_PASSWORD:-admin}"

MONITORING_RESULT_DIR="${ROOT_DIR}/tmp/phase-15-monitoring"
MONITORING_RESULT_PATH="${MONITORING_RESULT_DIR}/result.json"

monitoring_compose() {
  require_compose
  COMPOSE_PROJECT_NAME="${MONITORING_PROJECT_NAME}" \
  LOCALNET_DOCKER_NETWORK="${LOCALNET_DOCKER_NETWORK}" \
  PROMETHEUS_IMAGE="${PROMETHEUS_IMAGE}" \
  BLACKBOX_EXPORTER_IMAGE="${BLACKBOX_EXPORTER_IMAGE}" \
  GRAFANA_IMAGE="${GRAFANA_IMAGE}" \
  GRAFANA_ADMIN_USER="${GRAFANA_ADMIN_USER}" \
  GRAFANA_ADMIN_PASSWORD="${GRAFANA_ADMIN_PASSWORD}" \
  "${COMPOSE_CMD[@]}" -f "${MONITORING_COMPOSE_FILE}" "$@"
}

require_monitoring_artifacts() {
  local required_files=(
    "${MONITORING_COMPOSE_FILE}"
    "${PROMETHEUS_CONFIG_FILE}"
    "${PROMETHEUS_RULES_FILE}"
    "${BLACKBOX_CONFIG_FILE}"
    "${GRAFANA_PROVISIONING_DIR}/datasources/prometheus.yml"
    "${GRAFANA_PROVISIONING_DIR}/dashboards/dashboards.yml"
    "${GRAFANA_DASHBOARDS_DIR}/kudora-localnet-overview.json"
    "${GRAFANA_DASHBOARDS_DIR}/kudora-evm.json"
    "${GRAFANA_DASHBOARDS_DIR}/kudora-cosmwasm-integrity.json"
  )
  local path

  for path in "${required_files[@]}"; do
    [[ -f "${path}" ]] || die "monitoring: required file missing: ${path}"
  done
}

require_localnet_running() {
  require_docker_access

  if ! docker inspect "${LOCALNET_STATEFUL_SERVICE}" >/dev/null 2>&1; then
    die "monitoring: localnet service ${LOCALNET_STATEFUL_SERVICE} is not running; start it with make localnet-up"
  fi
}

wait_for_http() {
  local url="$1"
  local timeout="${2:-120}"
  local started_at
  started_at="$(date +%s)"

  while (( $(date +%s) - started_at < timeout )); do
    if curl -fsS "${url}" >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done

  return 1
}

grafana_api_get() {
  local path="$1"
  curl -fsS -u "${GRAFANA_ADMIN_USER}:${GRAFANA_ADMIN_PASSWORD}" "${GRAFANA_API_URL}${path}"
}

prometheus_api_get() {
  local path="$1"
  curl -fsS "${PROMETHEUS_API_URL}${path}"
}

monitoring_file_mtime() {
  local path="$1"

  if stat -f '%m' "${path}" >/dev/null 2>&1; then
    stat -f '%m' "${path}"
  else
    stat -c '%Y' "${path}"
  fi
}
