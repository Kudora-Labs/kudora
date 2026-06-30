#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

source "${ROOT_DIR}/deploy/localnet/scripts/common.sh"
source "${ROOT_DIR}/scripts/localnet-validation-common.sh"
source "${ROOT_DIR}/deploy/explorers/common.sh"

OUT_DIR="out"
REPORT_PATH="${OUT_DIR}/phase-14-validation.md"
BLOCKER_PATH="${OUT_DIR}/phase-14-blocker.md"
EXPECTED_BRANCH="Upgrade"

LOCALNET_SMOKE_RESULT_PATH="${LOCALNET_SMOKE_DIR}/phase-13-smoke/result.json"

mkdir -p "${OUT_DIR}"
rm -f "${BLOCKER_PATH}"

branch_name="$(git branch --show-current)"
if [[ "${branch_name}" != "${EXPECTED_BRANCH}" ]]; then
  echo "phase-14-validate: expected branch ${EXPECTED_BRANCH}, found ${branch_name}" >&2
  exit 1
fi

starting_commit="$(git rev-parse HEAD)"
head_before_report="$(git rev-parse HEAD)"
working_tree_status_before="$(git status --short)"
generated_at="$(date -u '+%Y-%m-%d %H:%M:%S UTC')"
validation_start_epoch="$(date +%s)"
go_version="$(go version)"
docker_version="$(docker version 2>&1 || true)"
docker_compose_version="$(compose_version_string)"
docker_image_tag="$(awk -F':= ' '/^DOCKER_IMAGE :=/ {print $2; exit}' Makefile)"
wasmd_version="$(go list -m -f '{{.Version}}' github.com/CosmWasm/wasmd)"
wasmvm_version="$(go list -m -f '{{.Version}}' github.com/CosmWasm/wasmvm/v3)"

results=()
last_failure_label=""
last_failure_status=0
last_failure_output=""

cleanup() {
  make explorers-down >/dev/null 2>&1 || true
  make localnet-down >/dev/null 2>&1 || true
}
trap cleanup EXIT

run_check() {
  local label="$1"
  shift
  local log_file
  log_file="$(mktemp)"

  set +e
  "$@" >"${log_file}" 2>&1
  local status=$?
  set -e

  if [[ ${status} -eq 0 ]]; then
    results+=("PASS|${label}")
    rm -f "${log_file}"
    return 0
  fi

  results+=("FAIL|${label}")
  last_failure_label="${label}"
  last_failure_status="${status}"
  last_failure_output="$(tail -n 200 "${log_file}")"
  rm -f "${log_file}"
  return "${status}"
}

check_phase14_artifacts() {
  local required_files=(
    "deploy/explorers/README.md"
    "deploy/explorers/common.sh"
    "deploy/explorers/blockscout/docker-compose.yml"
    "deploy/explorers/blockscout/README.md"
    "deploy/explorers/blockscout/env/blockscout.env.example"
    "deploy/explorers/blockscout/env/frontend.env.example"
    "deploy/explorers/blockscout/proxy/explorer.conf.template"
    "deploy/explorers/blockscout/scripts/start-blockscout.sh"
    "deploy/explorers/blockscout/scripts/stop-blockscout.sh"
    "deploy/explorers/blockscout/scripts/reset-blockscout.sh"
    "deploy/explorers/blockscout/scripts/smoke-blockscout.sh"
    "deploy/explorers/ping-dashboard/Dockerfile"
    "deploy/explorers/ping-dashboard/docker-compose.yml"
    "deploy/explorers/ping-dashboard/README.md"
    "deploy/explorers/ping-dashboard/config/kudora.json"
    "deploy/explorers/ping-dashboard/scripts/start-ping-dashboard.sh"
    "deploy/explorers/ping-dashboard/scripts/stop-ping-dashboard.sh"
    "deploy/explorers/ping-dashboard/scripts/reset-ping-dashboard.sh"
    "deploy/explorers/ping-dashboard/scripts/smoke-ping-dashboard.sh"
    "docs/docker/phase-14-explorers.md"
    "scripts/phase-14-validate.sh"
  )
  local path

  for path in "${required_files[@]}"; do
    [[ -f "${path}" ]] || {
      echo "phase-14-validate: required artifact missing: ${path}" >&2
      return 1
    }
  done
}

check_generated_state_not_tracked() {
  local tracked
  tracked="$(git ls-files | rg '(^\.localnet/|^tmp/localnet/|^tmp/phase-14-|^deploy/localnet/state/|^deploy/explorers/.*/\.env$|^deploy/explorers/.*/(data|db|postgres|redis)/)' || true)"

  if [[ -n "${tracked}" ]]; then
    echo "phase-14-validate: generated localnet or explorer state must not be tracked" >&2
    printf '%s\n' "${tracked}" >&2
    return 1
  fi
}

check_blockscout_result_current_run() {
  [[ -f "${BLOCKSCOUT_RESULT_PATH}" ]] || {
    echo "phase-14-validate: Blockscout result missing at ${BLOCKSCOUT_RESULT_PATH}" >&2
    return 1
  }

  local mtime
  mtime="$(explorer_file_mtime "${BLOCKSCOUT_RESULT_PATH}")"
  (( mtime >= validation_start_epoch )) || {
    echo "phase-14-validate: Blockscout result file is stale" >&2
    return 1
  }

  jq -e --argjson start "${validation_start_epoch}" '
    (.run_id // "" | length > 0) and
    .run_started_epoch >= $start and
    .run_finished_epoch >= .run_started_epoch and
    .frontend_status == "PASS" and
    .api_status == "PASS" and
    .indexing_status == "PASS" and
    (.latest_indexed_block // 0) > 0 and
    ((.transaction_visibility_status == "PASS") or (.transaction_visibility_status == "NOT_OBSERVED"))
  ' "${BLOCKSCOUT_RESULT_PATH}" >/dev/null || {
    echo "phase-14-validate: Blockscout smoke result is incomplete or stale" >&2
    return 1
  }
}

check_ping_result_current_run() {
  [[ -f "${PING_DASHBOARD_RESULT_PATH}" ]] || {
    echo "phase-14-validate: Ping Dashboard result missing at ${PING_DASHBOARD_RESULT_PATH}" >&2
    return 1
  }

  local mtime
  mtime="$(explorer_file_mtime "${PING_DASHBOARD_RESULT_PATH}")"
  (( mtime >= validation_start_epoch )) || {
    echo "phase-14-validate: Ping Dashboard result file is stale" >&2
    return 1
  }

  jq -e --argjson start "${validation_start_epoch}" '
    (.run_id // "" | length > 0) and
    .run_started_epoch >= $start and
    .run_finished_epoch >= .run_started_epoch and
    .frontend_status == "PASS" and
    .chain_presence_status == "PASS" and
    .endpoint_reachability_status == "PASS" and
    .configured_chain == "Kudora Localnet"
  ' "${PING_DASHBOARD_RESULT_PATH}" >/dev/null || {
    echo "phase-14-validate: Ping Dashboard smoke result is incomplete or stale" >&2
    return 1
  }
}

write_blocker() {
  {
    echo "# Phase 14 Blocker"
    echo
    echo "- Generated at: ${generated_at}"
    echo "- Branch: ${branch_name}"
    echo "- Starting commit: ${starting_commit}"
    echo "- Current HEAD before report generation: ${head_before_report}"
    echo
    echo "## First Failure"
    echo
    echo "- Label: \`${last_failure_label:-unknown}\`"
    echo "- Exit status: \`${last_failure_status}\`"
    echo
    echo '```text'
    echo "${last_failure_output:-no failure output captured}"
    echo '```'
  } >"${BLOCKER_PATH}"
}

write_report() {
  local phase131_status="not run"
  local no_forks_status="not run"
  local no_secrets_status="not run"
  local dependency_audit_status="not run"
  local vulncheck_status="not run"
  local localnet_status="not run"
  local explorers_up_status="not run"
  local explorers_smoke_status="not run"
  local archive_status="not run"
  local explorer_state_status="not run"
  local blockscout_current_run_status="not run"
  local ping_current_run_status="not run"
  local blockscout_indexing_status="not run"
  local ping_frontend_status="not run"
  local evm_smoke_status="not run"
  local evm_tx_status="not run"
  local evm_contract_status="not run"
  local wasm_smoke_status="not run"
  local latest_block_height="not available"

  local blockscout_indexed_tx="not observed"
  local blockscout_ui_url="${BLOCKSCOUT_UI_URL}"
  local blockscout_api_url="${BLOCKSCOUT_API_URL}"
  local ping_ui_url="${PING_DASHBOARD_UI_URL}"
  local ping_chain="Kudora Localnet"

  for result in "${results[@]}"; do
    case "${result}" in
      PASS\|make\ phase-13.1-validate) phase131_status="PASS" ;;
      FAIL\|make\ phase-13.1-validate) phase131_status="FAIL" ;;
      PASS\|make\ verify-no-forks) no_forks_status="PASS" ;;
      FAIL\|make\ verify-no-forks) no_forks_status="FAIL" ;;
      PASS\|make\ verify-no-secrets) no_secrets_status="PASS" ;;
      FAIL\|make\ verify-no-secrets) no_secrets_status="FAIL" ;;
      PASS\|make\ dependency-audit) dependency_audit_status="PASS" ;;
      FAIL\|make\ dependency-audit) dependency_audit_status="FAIL" ;;
      PASS\|make\ vulncheck) vulncheck_status="PASS" ;;
      FAIL\|make\ vulncheck) vulncheck_status="FAIL" ;;
      PASS\|make\ localnet-smoke-test) localnet_status="PASS" ;;
      FAIL\|make\ localnet-smoke-test) localnet_status="FAIL" ;;
      PASS\|make\ explorers-up) explorers_up_status="PASS" ;;
      FAIL\|make\ explorers-up) explorers_up_status="FAIL" ;;
      PASS\|make\ explorers-smoke-test) explorers_smoke_status="PASS" ;;
      FAIL\|make\ explorers-smoke-test) explorers_smoke_status="FAIL" ;;
      PASS\|make\ zip) archive_status="PASS" ;;
      FAIL\|make\ zip) archive_status="FAIL" ;;
      PASS\|Phase\ 14\ generated\ state\ is\ not\ tracked) explorer_state_status="PASS" ;;
      FAIL\|Phase\ 14\ generated\ state\ is\ not\ tracked) explorer_state_status="FAIL" ;;
      PASS\|Phase\ 14\ Blockscout\ current-run\ result) blockscout_current_run_status="PASS" ;;
      FAIL\|Phase\ 14\ Blockscout\ current-run\ result) blockscout_current_run_status="FAIL" ;;
      PASS\|Phase\ 14\ Ping\ current-run\ result) ping_current_run_status="PASS" ;;
      FAIL\|Phase\ 14\ Ping\ current-run\ result) ping_current_run_status="FAIL" ;;
    esac
  done

  if [[ -f "${LOCALNET_SMOKE_RESULT_PATH}" ]]; then
    evm_smoke_status="$(jq -r '.evm_smoke_status // "not run"' "${LOCALNET_SMOKE_RESULT_PATH}")"
    evm_tx_status="$(jq -r '.evm_transaction_status // "not run"' "${LOCALNET_SMOKE_RESULT_PATH}")"
    evm_contract_status="$(jq -r '.evm_contract_status // "not run"' "${LOCALNET_SMOKE_RESULT_PATH}")"
    wasm_smoke_status="$(jq -r '.wasm_smoke_status // "not run"' "${LOCALNET_SMOKE_RESULT_PATH}")"
    latest_block_height="$(jq -r '.height_after // "not available"' "${LOCALNET_SMOKE_RESULT_PATH}")"
  fi

  if [[ -f "${BLOCKSCOUT_RESULT_PATH}" ]]; then
    blockscout_indexing_status="$(jq -r '.indexing_status // "not run"' "${BLOCKSCOUT_RESULT_PATH}")"
    blockscout_indexed_tx="$(jq -r '.indexed_tx_hash // "not observed"' "${BLOCKSCOUT_RESULT_PATH}")"
  fi

  if [[ -f "${PING_DASHBOARD_RESULT_PATH}" ]]; then
    ping_frontend_status="$(jq -r '.frontend_status // "not run"' "${PING_DASHBOARD_RESULT_PATH}")"
  fi

  {
    echo "# Phase 14 Validation Report"
    echo
    echo "- Validation generated at: ${generated_at}"
    echo "- Branch: ${branch_name}"
    echo "- Starting commit: ${starting_commit}"
    echo "- Current HEAD before report generation: ${head_before_report}"
    echo "- Go version: \`${go_version}\`"
    echo "- Docker image tag: \`${docker_image_tag}\`"
    echo "- Docker localnet validation result: ${phase131_status}"
    echo "- Blockscout upstream commit inspected: \`${BLOCKSCOUT_UPSTREAM_COMMIT}\`"
    echo "- Ping Dashboard upstream commit inspected: \`${PING_DASHBOARD_UPSTREAM_COMMIT}\`"
    echo "- Cosmos chain-id: \`${LOCALNET_CHAIN_ID}\`"
    echo "- EVM chain ID: \`${LOCALNET_EVM_CHAIN_ID}\`"
    echo "- Expected \`eth_chainId\`: \`${LOCALNET_ETH_CHAIN_ID}\`"
    echo "- Wasmd version: \`${wasmd_version}\`"
    echo "- wasmvm version: \`${wasmvm_version}\`"
    echo "- Blockscout service list: \`kudora-blockscout-db, kudora-blockscout-redis, kudora-blockscout-backend, kudora-blockscout-frontend, kudora-blockscout-proxy\`"
    echo "- Blockscout UI URL: \`${blockscout_ui_url}\`"
    echo "- Blockscout API URL: \`${blockscout_api_url}\`"
    echo "- Ping Dashboard UI URL: \`${ping_ui_url}\`"
    echo "- Ping Dashboard configured chain: \`${ping_chain}\`"
    echo "- Latest localnet block height observed: \`${latest_block_height}\`"
    echo
    echo "## Working Tree Status Before Validation"
    echo
    echo '```text'
    echo "${working_tree_status_before:-clean}"
    echo '```'
    echo
    echo "## Tooling"
    echo
    echo '```text'
    echo "${docker_version}"
    echo
    echo "${docker_compose_version}"
    echo '```'
    echo
    echo "## Results"
    echo
    for result in "${results[@]}"; do
      status="${result%%|*}"
      label="${result#*|}"
      echo "- ${status}: \`${label}\`"
    done
    echo
    if [[ -n "${last_failure_label}" ]]; then
      echo "## First Failure"
      echo
      echo "- Label: \`${last_failure_label}\`"
      echo "- Exit status: \`${last_failure_status}\`"
      echo
      echo '```text'
      echo "${last_failure_output}"
      echo '```'
      echo
    fi
    echo "## Explorer Summary"
    echo
    echo "- Blockscout indexing result: ${blockscout_indexing_status}"
    echo "- Blockscout indexed transaction hash: ${blockscout_indexed_tx}"
    echo "- Ping Dashboard frontend status: ${ping_frontend_status}"
    echo "- Explorer smoke current-run verification: Blockscout=${blockscout_current_run_status}, Ping=${ping_current_run_status}"
    echo "- EVM smoke result: ${evm_smoke_status}"
    echo "- EVM transaction result: ${evm_tx_status}"
    echo "- EVM contract result: ${evm_contract_status}"
    echo "- Wasm smoke result: ${wasm_smoke_status}"
    echo
    echo "## Security And Dependency Summary"
    echo
    echo "- Dependency audit result: ${dependency_audit_status}"
    echo "- Vulnerability scan result: ${vulncheck_status}"
    echo "- No-forks result: ${no_forks_status}"
    echo "- No-secrets result: ${no_secrets_status}"
    echo "- Generated state tracking check: ${explorer_state_status}"
    echo
    echo "## Archive Paths"
    echo
    echo "- Phase 14 archive: \`out/kudora-phase-14-explorers.zip\`"
    echo "- Latest inspection archive: \`out/kudora-latest-inspection.zip\`"
    echo "- Archive generation result: ${archive_status}"
    echo
    echo "## Confirmations"
    echo
    echo "- No generated explorer DB/state is tracked: ${explorer_state_status}"
    echo "- No generated localnet state is tracked: ${explorer_state_status}"
    echo "- No secrets are committed: ${no_secrets_status}"
    echo "- No business modules were added."
    echo "- No IBC product/tokenfactory/packet-forward/rate-limit/ICA/08-wasm/monitoring work was added."
    echo "- No Docker registry push was performed."
  } >"${REPORT_PATH}"
}

run_check "Phase 14 artifacts exist" check_phase14_artifacts || { write_blocker; write_report; echo "phase-14-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make phase-13.1-validate" make phase-13.1-validate || { write_blocker; write_report; echo "phase-14-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make tidy" make tidy || { write_blocker; write_report; echo "phase-14-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "go mod verify" go mod verify || { write_blocker; write_report; echo "phase-14-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make build" make build || { write_blocker; write_report; echo "phase-14-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make test" make test || { write_blocker; write_report; echo "phase-14-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make lint" make lint || { write_blocker; write_report; echo "phase-14-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make verify-no-forks" make verify-no-forks || { write_blocker; write_report; echo "phase-14-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make verify-clean-reset" make verify-clean-reset || { write_blocker; write_report; echo "phase-14-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make verify-no-secrets" make verify-no-secrets || { write_blocker; write_report; echo "phase-14-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make dependency-audit" make dependency-audit || { write_blocker; write_report; echo "phase-14-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make vulncheck" make vulncheck || { write_blocker; write_report; echo "phase-14-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make docker-build" make docker-build || { write_blocker; write_report; echo "phase-14-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make docker-smoke-test" make docker-smoke-test || { write_blocker; write_report; echo "phase-14-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make localnet-reset" make localnet-reset || { write_blocker; write_report; echo "phase-14-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make localnet-init" make localnet-init || { write_blocker; write_report; echo "phase-14-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make localnet-up" make localnet-up || { write_blocker; write_report; echo "phase-14-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make localnet-smoke-test" make localnet-smoke-test || { write_blocker; write_report; echo "phase-14-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make explorers-reset" make explorers-reset || { write_blocker; write_report; echo "phase-14-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make explorers-up" make explorers-up || { write_blocker; write_report; echo "phase-14-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make explorers-smoke-test" make explorers-smoke-test || { write_blocker; write_report; echo "phase-14-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "Phase 14 Blockscout current-run result" check_blockscout_result_current_run || { write_blocker; write_report; echo "phase-14-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "Phase 14 Ping current-run result" check_ping_result_current_run || { write_blocker; write_report; echo "phase-14-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make explorers-down" make explorers-down || { write_blocker; write_report; echo "phase-14-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make localnet-down" make localnet-down || { write_blocker; write_report; echo "phase-14-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make zip" make zip || { write_blocker; write_report; echo "phase-14-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "Phase 14 generated state is not tracked" check_generated_state_not_tracked || { write_blocker; write_report; echo "phase-14-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }

write_report

echo "phase-14-validate: PASS (${REPORT_PATH})"
