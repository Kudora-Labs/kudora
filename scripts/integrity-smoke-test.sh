#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

BINARY="${ROOT_DIR}/build/kudorad"
USE_EXISTING_NODE="${KUDORA_USE_EXISTING_NODE:-0}"
CHAIN_ID="${KUDORA_CHAIN_ID:-kudora_12000-1}"
EVM_CHAIN_ID="${KUDORA_EVM_CHAIN_ID:-120001}"
EXPECTED_ETH_CHAIN_ID="${KUDORA_ETH_CHAIN_ID:-0x1d4c1}"
SMOKE_RUN_ID="$(date -u '+%Y%m%dT%H%M%SZ')"
TENANT="${KUDORA_INTEGRITY_TENANT:-orbitrum-smoke-$(date -u +%Y%m%d%H%M%S)}"
INTEGRITY_TYPE="${KUDORA_INTEGRITY_TYPE:-orbitrum.scoring.expert_daily_bundle.v1}"
SIGNER_KEY_NAME="${KUDORA_INTEGRITY_SIGNER_KEY_NAME:-validator}"
NEW_OWNER_KEY_NAME="${KUDORA_INTEGRITY_NEW_OWNER_KEY_NAME:-}"
NEW_OWNER_ADDRESS="${KUDORA_INTEGRITY_NEW_OWNER_ADDRESS:-}"
TX_FEES="${KUDORA_INTEGRITY_TX_FEES:-1000000000000000akud}"
TX_GAS="${KUDORA_INTEGRITY_TX_GAS:-700000}"
PERIOD_BASE="${KUDORA_INTEGRITY_PERIOD_BASE:-2026-06-25-smoke-$(date -u +%H%M%S)}"
RUN_STARTED_EPOCH="$(date +%s)"

INITIAL_PERIOD="${PERIOD_BASE}-a1"
PENDING_REJECT_PERIOD="${PERIOD_BASE}-b0"
PREACCEPT_PERIOD="${PERIOD_BASE}-a2"
POSTACCEPT_REJECT_PERIOD="${PERIOD_BASE}-a3"
POSTACCEPT_SUCCESS_PERIOD="${PERIOD_BASE}-b1"

if [[ "${USE_EXISTING_NODE}" == "1" ]]; then
  WORK_ROOT="${KUDORA_RESULT_DIR:-${ROOT_DIR}/tmp/localnet}"
  WORK_DIR="${WORK_ROOT}/integrity-smoke"
  HOME_DIR="${KUDORA_HOME:-}"
  COMET_RPC_URL="${KUDORA_RPC_URL:-http://127.0.0.1:26657}"
  EVM_RPC_URL="${KUDORA_EVM_RPC_URL:-http://127.0.0.1:8545}"
else
  source "${ROOT_DIR}/deploy/localnet/scripts/common.sh"
  WORK_DIR="${ROOT_DIR}/tmp/phase-12-integrity-smoke"
  HOME_DIR="${LOCALNET_HOME}"
  COMET_RPC_URL="${LOCALNET_RPC_URL}"
  EVM_RPC_URL="${LOCALNET_EVM_RPC_URL}"
fi

NODE_RPC_ENDPOINT="tcp://${COMET_RPC_URL#http://}"
RESULT_FILE="${WORK_DIR}/result.json"
LOG_DIR="${WORK_DIR}/logs"
QUERY_DIR="${WORK_DIR}/queries"
SET_DIR="${WORK_DIR}/sets"
METADATA_FILE="${HOME_DIR}/smoke/metadata.json"

command -v jq >/dev/null 2>&1 || {
  echo "integrity-smoke-test: jq is required" >&2
  exit 1
}

command -v curl >/dev/null 2>&1 || {
  echo "integrity-smoke-test: curl is required" >&2
  exit 1
}

command -v go >/dev/null 2>&1 || {
  echo "integrity-smoke-test: Go is required to build the integrity mock helper" >&2
  exit 1
}

if [[ ! -x "${BINARY}" ]]; then
  echo "integrity-smoke-test: expected built binary at ${BINARY}. Run make build first." >&2
  exit 1
fi

started_localnet="0"
cleanup() {
  if [[ "${started_localnet}" == "1" ]]; then
    "${ROOT_DIR}/deploy/localnet/scripts/reset-localnet.sh" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

run_tx_json() {
  local output_file="$1"
  local stderr_file="$2"
  shift 2

  local tx_json
  tx_json="$("$@" --output json 2>"${stderr_file}")"
  printf '%s\n' "${tx_json}" >"${output_file}"
  printf '%s\n' "${tx_json}"
}

wait_for_tx_success() {
  local tx_hash="$1"
  local output_file="$2"
  local stderr_file="$3"

  for _ in $(seq 1 60); do
    if "${BINARY}" query tx "${tx_hash}" --node "${NODE_RPC_ENDPOINT}" --output json >"${output_file}" 2>"${stderr_file}"; then
      jq -e '.code == 0' "${output_file}" >/dev/null && return 0
    fi
    sleep 1
  done

  return 1
}

wait_for_tx_query() {
  local tx_hash="$1"
  local output_file="$2"
  local stderr_file="$3"

  for _ in $(seq 1 60); do
    if "${BINARY}" query tx "${tx_hash}" --node "${NODE_RPC_ENDPOINT}" --output json >"${output_file}" 2>"${stderr_file}"; then
      return 0
    fi
    sleep 1
  done

  return 1
}

query_tenant_once() {
  local tenant="$1"
  local output_file="$2"
  local stderr_file="$3"

  "${BINARY}" query integrity tenant "${tenant}" \
    --node "${NODE_RPC_ENDPOINT}" \
    --output json \
    >"${output_file}" 2>"${stderr_file}"
}

wait_for_tenant_state() {
  local tenant="$1"
  local expected_owner="$2"
  local expected_pending_owner="$3"
  local output_file="$4"
  local stderr_file="$5"

  for _ in $(seq 1 30); do
    if query_tenant_once "${tenant}" "${output_file}" "${stderr_file}"; then
      if jq -e \
        --arg owner "${expected_owner}" \
        --arg pending_owner "${expected_pending_owner}" \
        '.tenant.owner == $owner and ((.tenant.pending_owner // "") == $pending_owner)' \
        "${output_file}" >/dev/null; then
        return 0
      fi
    fi
    sleep 1
  done

  return 1
}

query_set_once() {
  local tenant="$1"
  local integrity_type="$2"
  local period="$3"
  local output_file="$4"
  local stderr_file="$5"

  "${BINARY}" query integrity set "${tenant}" "${integrity_type}" "${period}" \
    --node "${NODE_RPC_ENDPOINT}" \
    --output json \
    >"${output_file}" 2>"${stderr_file}"
}

wait_for_set_query() {
  local tenant="$1"
  local integrity_type="$2"
  local period="$3"
  local output_file="$4"
  local stderr_file="$5"

  for _ in $(seq 1 30); do
    if query_set_once "${tenant}" "${integrity_type}" "${period}" "${output_file}" "${stderr_file}"; then
      return 0
    fi
    sleep 1
  done

  return 1
}

build_set() {
  local label="$1"
  local period="$2"

  local records_file="${SET_DIR}/${label}-records.json"
  local expected_file="${SET_DIR}/${label}-expected.json"

  go run ./testutil/integrity-smoke build-set \
    --tenant "${TENANT}" \
    --type "${INTEGRITY_TYPE}" \
    --period "${period}" \
    --record-count 2 \
    --records-file "${records_file}" \
    --expected-file "${expected_file}" \
    >"${LOG_DIR}/${label}-build.stdout" 2>"${LOG_DIR}/${label}-build.stderr"
}

rm -rf "${WORK_DIR}"
mkdir -p "${LOG_DIR}" "${QUERY_DIR}" "${SET_DIR}"

if [[ "${USE_EXISTING_NODE}" != "1" ]]; then
  "${ROOT_DIR}/deploy/localnet/scripts/reset-localnet.sh" >/dev/null
  "${ROOT_DIR}/deploy/localnet/scripts/init-localnet.sh" >/dev/null
  "${ROOT_DIR}/deploy/localnet/scripts/start-localnet.sh" >/dev/null
  started_localnet="1"
fi

[[ -d "${HOME_DIR}" ]] || {
  echo "integrity-smoke-test: expected node home at ${HOME_DIR}" >&2
  exit 1
}

for _ in $(seq 1 90); do
  if curl -sf "${COMET_RPC_URL}/health" >/dev/null; then
    break
  fi
  sleep 1
done

if ! curl -sf "${COMET_RPC_URL}/health" >/dev/null; then
  echo "integrity-smoke-test: CometBFT RPC never became healthy" >&2
  exit 1
fi

eth_chain_id_response=""
for _ in $(seq 1 60); do
  eth_chain_id_response="$(
    curl -sS \
      -H 'Content-Type: application/json' \
      --data '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' \
      "${EVM_RPC_URL}" || true
  )"
  if printf '%s\n' "${eth_chain_id_response}" | jq -e --arg expected "${EXPECTED_ETH_CHAIN_ID}" '.error == null and .result == $expected' >/dev/null; then
    break
  fi
  sleep 1
done

if ! printf '%s\n' "${eth_chain_id_response}" | jq -e --arg expected "${EXPECTED_ETH_CHAIN_ID}" '.error == null and .result == $expected' >/dev/null; then
  echo "integrity-smoke-test: eth_chainId did not return ${EXPECTED_ETH_CHAIN_ID}" >&2
  printf 'last response: %s\n' "${eth_chain_id_response:-<empty>}" >&2
  exit 1
fi

if [[ -z "${NEW_OWNER_KEY_NAME}" || -z "${NEW_OWNER_ADDRESS}" ]]; then
  [[ -f "${METADATA_FILE}" ]] || {
    echo "integrity-smoke-test: expected localnet metadata at ${METADATA_FILE}; re-run make localnet-init or set KUDORA_INTEGRITY_NEW_OWNER_KEY_NAME/KUDORA_INTEGRITY_NEW_OWNER_ADDRESS" >&2
    exit 1
  }

  if [[ -z "${NEW_OWNER_KEY_NAME}" ]]; then
    NEW_OWNER_KEY_NAME="$(jq -r '.integrity_pending_owner.name // empty' "${METADATA_FILE}")"
  fi
  if [[ -z "${NEW_OWNER_ADDRESS}" ]]; then
    NEW_OWNER_ADDRESS="$(jq -r '.integrity_pending_owner.address // empty' "${METADATA_FILE}")"
  fi
fi

[[ -n "${NEW_OWNER_KEY_NAME}" ]] || {
  echo "integrity-smoke-test: integrity pending owner key name is missing" >&2
  exit 1
}
[[ -n "${NEW_OWNER_ADDRESS}" ]] || {
  echo "integrity-smoke-test: integrity pending owner address is missing" >&2
  exit 1
}

new_owner_address="${NEW_OWNER_ADDRESS}"
actual_new_owner_address="$("${BINARY}" keys show "${NEW_OWNER_KEY_NAME}" --address --keyring-backend test --home "${HOME_DIR}" 2>"${LOG_DIR}/new-owner-key.stderr")"
[[ "${actual_new_owner_address}" == "${new_owner_address}" ]] || {
  echo "integrity-smoke-test: new owner key/address mismatch (${actual_new_owner_address} != ${new_owner_address})" >&2
  exit 1
}

build_set "initial" "${INITIAL_PERIOD}"
build_set "pending-reject" "${PENDING_REJECT_PERIOD}"
build_set "preaccept" "${PREACCEPT_PERIOD}"
build_set "postaccept-reject" "${POSTACCEPT_REJECT_PERIOD}"
build_set "postaccept-success" "${POSTACCEPT_SUCCESS_PERIOD}"

initial_root="$(jq -r '.root' "${SET_DIR}/initial-expected.json")"
pending_reject_root="$(jq -r '.root' "${SET_DIR}/pending-reject-expected.json")"
preaccept_root="$(jq -r '.root' "${SET_DIR}/preaccept-expected.json")"
postaccept_reject_root="$(jq -r '.root' "${SET_DIR}/postaccept-reject-expected.json")"
postaccept_success_root="$(jq -r '.root' "${SET_DIR}/postaccept-success-expected.json")"
expected_tags="$(jq -c '.sorted_tags' "${SET_DIR}/postaccept-success-expected.json")"
first_tag="$(jq -r '.sorted_tags[0]' "${SET_DIR}/postaccept-success-expected.json")"
expected_first_ciphertext="$(jq -r '.records[0].ciphertext' "${SET_DIR}/postaccept-success-expected.json")"

register_tx_json="$(run_tx_json "${LOG_DIR}/register-tenant.json" "${LOG_DIR}/register-tenant.stderr" \
  "${BINARY}" tx integrity register-tenant "${TENANT}" \
  --from "${SIGNER_KEY_NAME}" \
  --keyring-backend test \
  --home "${HOME_DIR}" \
  --chain-id "${CHAIN_ID}" \
  --node "${NODE_RPC_ENDPOINT}" \
  -y \
  -b sync \
  --gas 200000 \
  --fees "${TX_FEES}")"
register_tx_hash="$(printf '%s\n' "${register_tx_json}" | jq -r '.txhash // empty')"
[[ -n "${register_tx_hash}" ]] || {
  echo "integrity-smoke-test: tenant registration did not return a tx hash" >&2
  exit 1
}
wait_for_tx_success "${register_tx_hash}" "${LOG_DIR}/register-tenant-committed.json" "${LOG_DIR}/register-tenant-query.stderr" || {
  echo "integrity-smoke-test: tenant registration did not commit successfully" >&2
  exit 1
}
wait_for_tenant_state "${TENANT}" "$("${BINARY}" keys show "${SIGNER_KEY_NAME}" --address --keyring-backend test --home "${HOME_DIR}")" "" "${QUERY_DIR}/tenant-after-register.json" "${LOG_DIR}/tenant-after-register.stderr" || {
  echo "integrity-smoke-test: tenant did not become queryable after registration" >&2
  exit 1
}
tenant_registration_status="PASS"

initial_commit_json="$(run_tx_json "${LOG_DIR}/initial-commit.json" "${LOG_DIR}/initial-commit.stderr" \
  "${BINARY}" tx integrity commit-set "${TENANT}" "${INTEGRITY_TYPE}" "${INITIAL_PERIOD}" "${initial_root}" "${SET_DIR}/initial-records.json" \
  --from "${SIGNER_KEY_NAME}" \
  --keyring-backend test \
  --home "${HOME_DIR}" \
  --chain-id "${CHAIN_ID}" \
  --node "${NODE_RPC_ENDPOINT}" \
  -y \
  -b sync \
  --gas "${TX_GAS}" \
  --fees "${TX_FEES}")"
initial_commit_hash="$(printf '%s\n' "${initial_commit_json}" | jq -r '.txhash // empty')"
[[ -n "${initial_commit_hash}" ]] || {
  echo "integrity-smoke-test: initial commit transaction did not return a tx hash" >&2
  exit 1
}
wait_for_tx_success "${initial_commit_hash}" "${LOG_DIR}/initial-commit-committed.json" "${LOG_DIR}/initial-commit-query.stderr" || {
  echo "integrity-smoke-test: initial commit transaction did not commit successfully" >&2
  exit 1
}
wait_for_set_query "${TENANT}" "${INTEGRITY_TYPE}" "${INITIAL_PERIOD}" "${QUERY_DIR}/initial-set.json" "${LOG_DIR}/initial-set.stderr" || {
  echo "integrity-smoke-test: initial set did not become queryable" >&2
  exit 1
}

transfer_json="$(run_tx_json "${LOG_DIR}/transfer.json" "${LOG_DIR}/transfer.stderr" \
  "${BINARY}" tx integrity transfer-tenant-ownership "${TENANT}" "${new_owner_address}" \
  --from "${SIGNER_KEY_NAME}" \
  --keyring-backend test \
  --home "${HOME_DIR}" \
  --chain-id "${CHAIN_ID}" \
  --node "${NODE_RPC_ENDPOINT}" \
  -y \
  -b sync \
  --gas 200000 \
  --fees "${TX_FEES}")"
transfer_tx_hash="$(printf '%s\n' "${transfer_json}" | jq -r '.txhash // empty')"
[[ -n "${transfer_tx_hash}" ]] || {
  echo "integrity-smoke-test: ownership transfer transaction did not return a tx hash" >&2
  exit 1
}
wait_for_tx_success "${transfer_tx_hash}" "${LOG_DIR}/transfer-committed.json" "${LOG_DIR}/transfer-query.stderr" || {
  echo "integrity-smoke-test: ownership transfer transaction did not commit successfully" >&2
  exit 1
}
owner_a_address="$("${BINARY}" keys show "${SIGNER_KEY_NAME}" --address --keyring-backend test --home "${HOME_DIR}")"
wait_for_tenant_state "${TENANT}" "${owner_a_address}" "${new_owner_address}" "${QUERY_DIR}/tenant-after-transfer.json" "${LOG_DIR}/tenant-after-transfer.stderr" || {
  echo "integrity-smoke-test: tenant did not reflect a pending owner after transfer" >&2
  exit 1
}
ownership_transfer_status="PASS"
pending_owner_visibility_status="PASS"

set +e
pending_commit_json="$(run_tx_json "${LOG_DIR}/pending-owner-rejected.json" "${LOG_DIR}/pending-owner-rejected.stderr" \
  "${BINARY}" tx integrity commit-set "${TENANT}" "${INTEGRITY_TYPE}" "${PENDING_REJECT_PERIOD}" "${pending_reject_root}" "${SET_DIR}/pending-reject-records.json" \
  --from "${NEW_OWNER_KEY_NAME}" \
  --keyring-backend test \
  --home "${HOME_DIR}" \
  --chain-id "${CHAIN_ID}" \
  --node "${NODE_RPC_ENDPOINT}" \
  -y \
  -b sync \
  --gas "${TX_GAS}" \
  --fees "${TX_FEES}")"
pending_commit_status=$?
set -e

pending_owner_commit_rejected_status="FAIL"
if [[ ${pending_commit_status} -eq 0 ]]; then
  pending_commit_tx_hash="$(printf '%s\n' "${pending_commit_json}" | jq -r '.txhash // empty')"
  if [[ -n "${pending_commit_tx_hash}" ]] && wait_for_tx_query "${pending_commit_tx_hash}" "${LOG_DIR}/pending-owner-rejected-committed.json" "${LOG_DIR}/pending-owner-rejected-query.stderr" && jq -e '.code != 0' "${LOG_DIR}/pending-owner-rejected-committed.json" >/dev/null; then
    pending_owner_commit_rejected_status="PASS"
  fi
fi
[[ "${pending_owner_commit_rejected_status}" == "PASS" ]] || {
  echo "integrity-smoke-test: pending owner unexpectedly committed before accepting ownership" >&2
  printf '%s\n' "${pending_commit_json:-<empty>}" >&2
  exit 1
}

preaccept_commit_json="$(run_tx_json "${LOG_DIR}/preaccept-commit.json" "${LOG_DIR}/preaccept-commit.stderr" \
  "${BINARY}" tx integrity commit-set "${TENANT}" "${INTEGRITY_TYPE}" "${PREACCEPT_PERIOD}" "${preaccept_root}" "${SET_DIR}/preaccept-records.json" \
  --from "${SIGNER_KEY_NAME}" \
  --keyring-backend test \
  --home "${HOME_DIR}" \
  --chain-id "${CHAIN_ID}" \
  --node "${NODE_RPC_ENDPOINT}" \
  --yes \
  -b sync \
  --gas "${TX_GAS}" \
  --fees "${TX_FEES}")"
preaccept_commit_hash="$(printf '%s\n' "${preaccept_commit_json}" | jq -r '.txhash // empty')"
[[ -n "${preaccept_commit_hash}" ]] || {
  echo "integrity-smoke-test: pre-accept owner commit did not return a tx hash" >&2
  exit 1
}
wait_for_tx_success "${preaccept_commit_hash}" "${LOG_DIR}/preaccept-commit-committed.json" "${LOG_DIR}/preaccept-commit-query.stderr" || {
  echo "integrity-smoke-test: pre-accept owner commit did not commit successfully" >&2
  exit 1
}
old_owner_preaccept_commit_status="PASS"

accept_json="$(run_tx_json "${LOG_DIR}/accept.json" "${LOG_DIR}/accept.stderr" \
  "${BINARY}" tx integrity accept-tenant-ownership "${TENANT}" \
  --from "${NEW_OWNER_KEY_NAME}" \
  --keyring-backend test \
  --home "${HOME_DIR}" \
  --chain-id "${CHAIN_ID}" \
  --node "${NODE_RPC_ENDPOINT}" \
  -y \
  -b sync \
  --gas 200000 \
  --fees "${TX_FEES}")"
accept_tx_hash="$(printf '%s\n' "${accept_json}" | jq -r '.txhash // empty')"
[[ -n "${accept_tx_hash}" ]] || {
  echo "integrity-smoke-test: accept ownership transaction did not return a tx hash" >&2
  exit 1
}
wait_for_tx_success "${accept_tx_hash}" "${LOG_DIR}/accept-committed.json" "${LOG_DIR}/accept-query.stderr" || {
  echo "integrity-smoke-test: accept ownership transaction did not commit successfully" >&2
  exit 1
}
wait_for_tenant_state "${TENANT}" "${new_owner_address}" "" "${QUERY_DIR}/tenant-after-accept.json" "${LOG_DIR}/tenant-after-accept.stderr" || {
  echo "integrity-smoke-test: tenant owner did not switch to the pending owner" >&2
  exit 1
}
ownership_acceptance_status="PASS"

set +e
old_owner_rejected_json="$(run_tx_json "${LOG_DIR}/old-owner-rejected.json" "${LOG_DIR}/old-owner-rejected.stderr" \
  "${BINARY}" tx integrity commit-set "${TENANT}" "${INTEGRITY_TYPE}" "${POSTACCEPT_REJECT_PERIOD}" "${postaccept_reject_root}" "${SET_DIR}/postaccept-reject-records.json" \
  --from "${SIGNER_KEY_NAME}" \
  --keyring-backend test \
  --home "${HOME_DIR}" \
  --chain-id "${CHAIN_ID}" \
  --node "${NODE_RPC_ENDPOINT}" \
  -y \
  -b sync \
  --gas "${TX_GAS}" \
  --fees "${TX_FEES}")"
old_owner_rejected_status_code=$?
set -e

old_owner_postaccept_rejected_status="FAIL"
if [[ ${old_owner_rejected_status_code} -eq 0 ]]; then
  old_owner_rejected_tx_hash="$(printf '%s\n' "${old_owner_rejected_json}" | jq -r '.txhash // empty')"
  if [[ -n "${old_owner_rejected_tx_hash}" ]] && wait_for_tx_query "${old_owner_rejected_tx_hash}" "${LOG_DIR}/old-owner-rejected-committed.json" "${LOG_DIR}/old-owner-rejected-query.stderr" && jq -e '.code != 0' "${LOG_DIR}/old-owner-rejected-committed.json" >/dev/null; then
    old_owner_postaccept_rejected_status="PASS"
  fi
fi
[[ "${old_owner_postaccept_rejected_status}" == "PASS" ]] || {
  echo "integrity-smoke-test: old owner unexpectedly committed after ownership acceptance" >&2
  printf '%s\n' "${old_owner_rejected_json:-<empty>}" >&2
  exit 1
}

postaccept_commit_json="$(run_tx_json "${LOG_DIR}/postaccept-commit.json" "${LOG_DIR}/postaccept-commit.stderr" \
  "${BINARY}" tx integrity commit-set "${TENANT}" "${INTEGRITY_TYPE}" "${POSTACCEPT_SUCCESS_PERIOD}" "${postaccept_success_root}" "${SET_DIR}/postaccept-success-records.json" \
  --from "${NEW_OWNER_KEY_NAME}" \
  --keyring-backend test \
  --home "${HOME_DIR}" \
  --chain-id "${CHAIN_ID}" \
  --node "${NODE_RPC_ENDPOINT}" \
  -y \
  -b sync \
  --gas "${TX_GAS}" \
  --fees "${TX_FEES}")"
postaccept_commit_hash="$(printf '%s\n' "${postaccept_commit_json}" | jq -r '.txhash // empty')"
[[ -n "${postaccept_commit_hash}" ]] || {
  echo "integrity-smoke-test: new owner commit did not return a tx hash" >&2
  exit 1
}
wait_for_tx_success "${postaccept_commit_hash}" "${LOG_DIR}/postaccept-commit-committed.json" "${LOG_DIR}/postaccept-commit-query.stderr" || {
  echo "integrity-smoke-test: new owner commit did not commit successfully" >&2
  exit 1
}
wait_for_set_query "${TENANT}" "${INTEGRITY_TYPE}" "${POSTACCEPT_SUCCESS_PERIOD}" "${QUERY_DIR}/final-set.json" "${LOG_DIR}/final-set.stderr" || {
  echo "integrity-smoke-test: final set did not become queryable" >&2
  exit 1
}
"${BINARY}" query integrity record "${TENANT}" "${INTEGRITY_TYPE}" "${POSTACCEPT_SUCCESS_PERIOD}" "${first_tag}" \
  --node "${NODE_RPC_ENDPOINT}" \
  --output json \
  >"${QUERY_DIR}/final-record.json" 2>"${LOG_DIR}/final-record.stderr"
new_owner_postaccept_commit_status="PASS"

root_match_status="FAIL"
records_sorted_status="FAIL"
record_query_status="FAIL"
plaintext_leak_status="FAIL"
commit_status="FAIL"

actual_tags="$(jq -c '[.records[].tag]' "${QUERY_DIR}/final-set.json")"

if jq -e --arg root "${postaccept_success_root}" '.set.root == $root' "${QUERY_DIR}/final-set.json" >/dev/null; then
  root_match_status="PASS"
fi

if [[ "${actual_tags}" == "${expected_tags}" ]]; then
  records_sorted_status="PASS"
fi

if jq -e \
  --arg tag "${first_tag}" \
  --arg ciphertext "${expected_first_ciphertext}" \
  '.record.tag == $tag and .record.ciphertext == $ciphertext and .set.root != ""' \
  "${QUERY_DIR}/final-record.json" >/dev/null; then
  record_query_status="PASS"
fi

if ! rg -n 'legitimateId|projectId|sectionType|scoreScaled|business_value|team_integrity' "${QUERY_DIR}/final-set.json" "${QUERY_DIR}/final-record.json" >/dev/null; then
  plaintext_leak_status="PASS"
fi

[[ "${root_match_status}" == "PASS" ]] || { echo "integrity-smoke-test: root mismatch" >&2; exit 1; }
[[ "${records_sorted_status}" == "PASS" ]] || { echo "integrity-smoke-test: records were not returned sorted by tag" >&2; exit 1; }
[[ "${record_query_status}" == "PASS" ]] || { echo "integrity-smoke-test: record query did not return the expected encrypted payload" >&2; exit 1; }
[[ "${plaintext_leak_status}" == "PASS" ]] || { echo "integrity-smoke-test: plaintext Orbitrum-like fields leaked into chain query responses" >&2; exit 1; }

if [[ "${tenant_registration_status}" == "PASS" \
  && "${ownership_transfer_status}" == "PASS" \
  && "${pending_owner_commit_rejected_status}" == "PASS" \
  && "${old_owner_preaccept_commit_status}" == "PASS" \
  && "${ownership_acceptance_status}" == "PASS" \
  && "${old_owner_postaccept_rejected_status}" == "PASS" \
  && "${new_owner_postaccept_commit_status}" == "PASS" ]]; then
  commit_status="PASS"
fi

RUN_FINISHED_EPOCH="$(date +%s)"

jq -n \
  --arg run_id "${SMOKE_RUN_ID}" \
  --arg generated_at_utc "$(date -u '+%Y-%m-%d %H:%M:%S UTC')" \
  --arg run_started_epoch "${RUN_STARTED_EPOCH}" \
  --arg run_finished_epoch "${RUN_FINISHED_EPOCH}" \
  --arg mode "$(if [[ "${USE_EXISTING_NODE}" == "1" ]]; then printf '%s' "existing-node"; else printf '%s' "self-contained"; fi)" \
  --arg tenant "${TENANT}" \
  --arg type "${INTEGRITY_TYPE}" \
  --arg initial_period "${INITIAL_PERIOD}" \
  --arg final_period "${POSTACCEPT_SUCCESS_PERIOD}" \
  --arg root "${postaccept_success_root}" \
  --arg owner_a "${owner_a_address}" \
  --arg owner_b "${new_owner_address}" \
  --arg tenant_registration_status "${tenant_registration_status}" \
  --arg commit_status "${commit_status}" \
  --arg ownership_transfer_status "${ownership_transfer_status}" \
  --arg pending_owner_visibility_status "${pending_owner_visibility_status}" \
  --arg pending_owner_commit_rejected_status "${pending_owner_commit_rejected_status}" \
  --arg old_owner_preaccept_commit_status "${old_owner_preaccept_commit_status}" \
  --arg ownership_acceptance_status "${ownership_acceptance_status}" \
  --arg old_owner_postaccept_rejected_status "${old_owner_postaccept_rejected_status}" \
  --arg new_owner_postaccept_commit_status "${new_owner_postaccept_commit_status}" \
  --arg root_match_status "${root_match_status}" \
  --arg records_sorted_status "${records_sorted_status}" \
  --arg record_query_status "${record_query_status}" \
  --arg plaintext_leak_status "${plaintext_leak_status}" \
  --arg first_tag "${first_tag}" \
  '{
    run_id: $run_id,
    generated_at_utc: $generated_at_utc,
    run_started_epoch: ($run_started_epoch | tonumber),
    run_finished_epoch: ($run_finished_epoch | tonumber),
    mode: $mode,
    tenant: $tenant,
    type: $type,
    initial_period: $initial_period,
    final_period: $final_period,
    root: $root,
    owner_a: $owner_a,
    owner_b: $owner_b,
    tenant_registration_status: $tenant_registration_status,
    commit_status: $commit_status,
    ownership_transfer_status: $ownership_transfer_status,
    pending_owner_visibility_status: $pending_owner_visibility_status,
    pending_owner_commit_rejected_status: $pending_owner_commit_rejected_status,
    old_owner_preaccept_commit_status: $old_owner_preaccept_commit_status,
    ownership_acceptance_status: $ownership_acceptance_status,
    old_owner_postaccept_rejected_status: $old_owner_postaccept_rejected_status,
    new_owner_postaccept_commit_status: $new_owner_postaccept_commit_status,
    root_match_status: $root_match_status,
    records_sorted_status: $records_sorted_status,
    record_query_status: $record_query_status,
    plaintext_leak_status: $plaintext_leak_status,
    first_tag: $first_tag
  }' >"${RESULT_FILE}"

echo "integrity-smoke-test: PASS (tenant=${TENANT} owner-a=${owner_a_address} owner-b=${new_owner_address} final-period=${POSTACCEPT_SUCCESS_PERIOD} root=${postaccept_success_root})"
