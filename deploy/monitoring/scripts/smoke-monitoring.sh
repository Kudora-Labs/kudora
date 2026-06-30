#!/usr/bin/env bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../common.sh"

require_command curl
require_command jq
require_docker_access
require_monitoring_artifacts
require_localnet_running

SMOKE_RUN_ID="$(date -u '+%Y%m%dT%H%M%SZ')"
RUN_STARTED_EPOCH="$(date +%s)"

rm -rf "${MONITORING_RESULT_DIR}"
mkdir -p "${MONITORING_RESULT_DIR}"

check_query_pass() {
  local query="$1"
  local output_file="$2"

  prometheus_api_get "/query?query=${query}" >"${output_file}"
  jq -e '
    .status == "success" and
    (.data.result | length) > 0 and
    ((.data.result[0].value[1] | tonumber) >= 1)
  ' "${output_file}" >/dev/null
}

wait_for_query_pass() {
  local query="$1"
  local output_file="$2"
  local description="$3"

  for _ in $(seq 1 60); do
    if check_query_pass "${query}" "${output_file}"; then
      return 0
    fi
    sleep 2
  done

  die "monitoring-smoke: ${description}"
}

wait_for_targets_ready() {
  for _ in $(seq 1 60); do
    prometheus_api_get "/targets" >"${MONITORING_RESULT_DIR}/targets.json" || true
    if jq -e '
      .status == "success" and
      (
        [
          .data.activeTargets[]
          | select(
              .labels.job == "kudora-cometbft" or
              .labels.job == "kudora-rpc-status" or
              .labels.job == "kudora-rest-node-info" or
              .labels.job == "kudora-evm-chainid" or
              .labels.job == "grafana-health"
            )
        ] | length == 5
      )
    ' "${MONITORING_RESULT_DIR}/targets.json" >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done

  die "monitoring-smoke: expected scrape targets are missing from Prometheus"
}

wait_for_dashboards() {
  for _ in $(seq 1 60); do
    grafana_api_get '/search?query=Kudora' >"${MONITORING_RESULT_DIR}/grafana-search.json" || true
    if jq -e '
      map(.title) as $titles |
      ($titles | index("Kudora Localnet Overview")) != null and
      ($titles | index("Kudora EVM")) != null and
      ($titles | index("Kudora CosmWasm + Integrity")) != null
    ' "${MONITORING_RESULT_DIR}/grafana-search.json" >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done

  die "monitoring-smoke: expected provisioned dashboards were not found in Grafana"
}

wait_for_grafana_health() {
  for _ in $(seq 1 60); do
    if grafana_api_get "/health" >"${MONITORING_RESULT_DIR}/grafana-health.json" 2>/dev/null; then
      return 0
    fi
    sleep 2
  done

  die "monitoring-smoke: Grafana health endpoint did not respond"
}

wait_for_http "${PROMETHEUS_UI_URL}/-/ready" 120 || die "monitoring-smoke: Prometheus did not become ready"
wait_for_grafana_health
prometheus_api_get "/targets" >"${MONITORING_RESULT_DIR}/targets.json" || die "monitoring-smoke: Prometheus targets API did not respond"

wait_for_query_pass 'up%7Bjob%3D%22kudora-cometbft%22%7D' "${MONITORING_RESULT_DIR}/query-cometbft.json" "kudora-cometbft scrape target is not UP"
wait_for_query_pass 'probe_success%7Bjob%3D%22kudora-rpc-status%22%7D' "${MONITORING_RESULT_DIR}/query-rpc.json" "RPC probe target is not UP"
wait_for_query_pass 'probe_success%7Bjob%3D%22kudora-rest-node-info%22%7D' "${MONITORING_RESULT_DIR}/query-rest.json" "REST probe target is not UP"
wait_for_query_pass 'probe_success%7Bjob%3D%22kudora-evm-chainid%22%7D' "${MONITORING_RESULT_DIR}/query-evm.json" "EVM chain-id probe target is not UP"
wait_for_query_pass 'probe_success%7Bjob%3D%22grafana-health%22%7D' "${MONITORING_RESULT_DIR}/query-grafana.json" "Grafana probe target is not UP"

prometheus_api_get '/query?query=max%28cometbft_consensus_height%29' >"${MONITORING_RESULT_DIR}/query-height.json"
latest_block_height="$(jq -r '.data.result[0].value[1] // "0"' "${MONITORING_RESULT_DIR}/query-height.json")"

wait_for_dashboards
wait_for_targets_ready

RUN_FINISHED_EPOCH="$(date +%s)"

jq -n \
  --arg run_id "${SMOKE_RUN_ID}" \
  --arg generated_at_utc "$(date -u '+%Y-%m-%d %H:%M:%S UTC')" \
  --arg run_started_epoch "${RUN_STARTED_EPOCH}" \
  --arg run_finished_epoch "${RUN_FINISHED_EPOCH}" \
  --arg prometheus_status "PASS" \
  --arg grafana_status "PASS" \
  --arg scrape_targets_status "PASS" \
  --arg cometbft_metrics_status "PASS" \
  --arg rpc_probe_status "PASS" \
  --arg rest_probe_status "PASS" \
  --arg evm_probe_status "PASS" \
  --arg grafana_probe_status "PASS" \
  --arg dashboard_provisioning_status "PASS" \
  --arg latest_block_height "${latest_block_height}" \
  --arg prometheus_url "${PROMETHEUS_UI_URL}" \
  --arg grafana_url "${GRAFANA_UI_URL}" \
  --arg metrics_url "${LOCALNET_METRICS_URL}" \
  '{
    run_id: $run_id,
    generated_at_utc: $generated_at_utc,
    run_started_epoch: ($run_started_epoch | tonumber),
    run_finished_epoch: ($run_finished_epoch | tonumber),
    prometheus_status: $prometheus_status,
    grafana_status: $grafana_status,
    scrape_targets_status: $scrape_targets_status,
    cometbft_metrics_status: $cometbft_metrics_status,
    rpc_probe_status: $rpc_probe_status,
    rest_probe_status: $rest_probe_status,
    evm_probe_status: $evm_probe_status,
    grafana_probe_status: $grafana_probe_status,
    dashboard_provisioning_status: $dashboard_provisioning_status,
    latest_block_height: ($latest_block_height | tonumber),
    prometheus_url: $prometheus_url,
    grafana_url: $grafana_url,
    metrics_url: $metrics_url
  }' >"${MONITORING_RESULT_PATH}"

echo "monitoring-smoke: PASS (prometheus=${PROMETHEUS_UI_URL} grafana=${GRAFANA_UI_URL} latest_height=${latest_block_height})"
