#!/usr/bin/env bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../common.sh"

require_command curl
require_localnet_running

rm -rf "${PING_DASHBOARD_RESULT_DIR}"
mkdir -p "${PING_DASHBOARD_RESULT_DIR}"

run_started_epoch="$(date +%s)"
run_id="$(date -u '+%Y%m%dT%H%M%SZ')"

wait_for_http "${PING_DASHBOARD_UI_URL}/" 180 || die "ping-dashboard-smoke: UI did not become reachable at ${PING_DASHBOARD_UI_URL}"

docker exec "${PING_DASHBOARD_CONTAINER}" sh -lc \
  "wget -qO- http://kudora-validator-0:1317/cosmos/base/tendermint/v1beta1/node_info >/dev/null" \
  >/dev/null 2>&1 || die "ping-dashboard-smoke: explorer container cannot reach Kudora REST endpoint"

docker exec "${PING_DASHBOARD_CONTAINER}" sh -lc \
  "wget -qO- http://kudora-validator-0:26657/status >/dev/null" \
  >/dev/null 2>&1 || die "ping-dashboard-smoke: explorer container cannot reach Kudora RPC endpoint"

docker exec "${PING_DASHBOARD_CONTAINER}" sh -lc \
  "grep -R 'Kudora Localnet' /usr/share/nginx/html >/dev/null && grep -R 'kudora_12000-1' /usr/share/nginx/html >/dev/null && grep -R 'http://localhost:1317' /usr/share/nginx/html >/dev/null" \
  >/dev/null 2>&1 || die "ping-dashboard-smoke: built frontend does not contain the Kudora localnet chain configuration"

run_finished_epoch="$(date +%s)"

jq -n \
  --arg run_id "${run_id}" \
  --arg generated_at_utc "$(date -u '+%Y-%m-%d %H:%M:%S UTC')" \
  --argjson run_started_epoch "${run_started_epoch}" \
  --argjson run_finished_epoch "${run_finished_epoch}" \
  --arg frontend_status "PASS" \
  --arg chain_presence_status "PASS" \
  --arg endpoint_reachability_status "PASS" \
  --arg ui_url "${PING_DASHBOARD_UI_URL}" \
  --arg configured_chain "Kudora Localnet" \
  --arg upstream_commit "${PING_DASHBOARD_UPSTREAM_COMMIT}" \
  '{
    run_id: $run_id,
    generated_at_utc: $generated_at_utc,
    run_started_epoch: $run_started_epoch,
    run_finished_epoch: $run_finished_epoch,
    frontend_status: $frontend_status,
    chain_presence_status: $chain_presence_status,
    endpoint_reachability_status: $endpoint_reachability_status,
    ui_url: $ui_url,
    configured_chain: $configured_chain,
    upstream_commit: $upstream_commit
  }' >"${PING_DASHBOARD_RESULT_PATH}"

echo "ping-dashboard-smoke: PASS (ui=${PING_DASHBOARD_UI_URL})"
