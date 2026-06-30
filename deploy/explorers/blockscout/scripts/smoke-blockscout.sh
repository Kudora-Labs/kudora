#!/usr/bin/env bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../common.sh"

require_command curl
require_command jq
require_localnet_running

rm -rf "${BLOCKSCOUT_RESULT_DIR}"
mkdir -p "${BLOCKSCOUT_RESULT_DIR}"

run_started_epoch="$(date +%s)"
run_id="$(date -u '+%Y%m%dT%H%M%SZ')"

wait_for_http "${BLOCKSCOUT_UI_URL}/" 180 || die "blockscout-smoke: UI did not become reachable at ${BLOCKSCOUT_UI_URL}"
wait_for_http "${BLOCKSCOUT_API_URL}/stats" 180 || die "blockscout-smoke: API did not become reachable at ${BLOCKSCOUT_API_URL}"

frontend_status="PASS"
api_status="PASS"
indexing_status="FAIL"
tx_status="NOT_OBSERVED"
latest_block="0"
indexed_tx_hash=""

deadline=$(( $(date +%s) + 180 ))
while (( $(date +%s) < deadline )); do
  blocks_json="$(curl -fsS "${BLOCKSCOUT_API_URL}/blocks" || true)"
  tx_json="$(curl -fsS "${BLOCKSCOUT_API_URL}/transactions" || true)"

  if [[ -n "${blocks_json}" ]]; then
    latest_block="$(printf '%s' "${blocks_json}" | jq -r '.items[0].height // .items[0].block_number // "0"' 2>/dev/null || echo "0")"
    if [[ "${latest_block}" =~ ^[0-9]+$ ]] && (( latest_block > 0 )); then
      indexing_status="PASS"
    fi
  fi

  if [[ -n "${tx_json}" ]]; then
    indexed_tx_hash="$(printf '%s' "${tx_json}" | jq -r '.items[0].hash // empty' 2>/dev/null || true)"
    if [[ -n "${indexed_tx_hash}" ]]; then
      tx_status="PASS"
    fi
  fi

  if [[ "${indexing_status}" == "PASS" ]]; then
    break
  fi

  sleep 3
done

[[ "${indexing_status}" == "PASS" ]] || die "blockscout-smoke: Blockscout did not index any Kudora localnet blocks"

run_finished_epoch="$(date +%s)"

jq -n \
  --arg run_id "${run_id}" \
  --arg generated_at_utc "$(date -u '+%Y-%m-%d %H:%M:%S UTC')" \
  --argjson run_started_epoch "${run_started_epoch}" \
  --argjson run_finished_epoch "${run_finished_epoch}" \
  --arg frontend_status "${frontend_status}" \
  --arg api_status "${api_status}" \
  --arg indexing_status "${indexing_status}" \
  --arg tx_status "${tx_status}" \
  --arg latest_block "${latest_block}" \
  --arg indexed_tx_hash "${indexed_tx_hash}" \
  --arg ui_url "${BLOCKSCOUT_UI_URL}" \
  --arg api_url "${BLOCKSCOUT_API_URL}" \
  --arg upstream_commit "${BLOCKSCOUT_UPSTREAM_COMMIT}" \
  '{
    run_id: $run_id,
    generated_at_utc: $generated_at_utc,
    run_started_epoch: $run_started_epoch,
    run_finished_epoch: $run_finished_epoch,
    frontend_status: $frontend_status,
    api_status: $api_status,
    indexing_status: $indexing_status,
    transaction_visibility_status: $tx_status,
    latest_indexed_block: ($latest_block | tonumber),
    indexed_tx_hash: $indexed_tx_hash,
    ui_url: $ui_url,
    api_url: $api_url,
    upstream_commit: $upstream_commit
  }' >"${BLOCKSCOUT_RESULT_PATH}"

echo "blockscout-smoke: PASS (ui=${BLOCKSCOUT_UI_URL} api=${BLOCKSCOUT_API_URL} block=${latest_block})"
