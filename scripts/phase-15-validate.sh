#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

source "${ROOT_DIR}/deploy/localnet/scripts/common.sh"
source "${ROOT_DIR}/scripts/localnet-validation-common.sh"
source "${ROOT_DIR}/deploy/explorers/common.sh"
source "${ROOT_DIR}/deploy/monitoring/common.sh"

OUT_DIR="out"
REPORT_PATH="${OUT_DIR}/phase-15-validation.md"
BLOCKER_PATH="${OUT_DIR}/phase-15-blocker.md"
EXPECTED_BRANCH="Upgrade"
INTEGRITY_RESULT_PATH="${LOCALNET_SMOKE_DIR}/integrity-smoke/result.json"

mkdir -p "${OUT_DIR}"
rm -f "${BLOCKER_PATH}" "${REPORT_PATH}"
rm -rf "${MONITORING_RESULT_DIR}" "${LOCALNET_SMOKE_DIR}/integrity-smoke" "${BLOCKSCOUT_RESULT_DIR}" "${PING_DASHBOARD_RESULT_DIR}"

branch_name="$(git branch --show-current)"
if [[ "${branch_name}" != "${EXPECTED_BRANCH}" ]]; then
  echo "phase-15-validate: expected branch ${EXPECTED_BRANCH}, found ${branch_name}" >&2
  exit 1
fi

starting_commit="$(git rev-parse HEAD)"
head_before_report="$(git rev-parse HEAD)"
working_tree_status_before="$(git status --short)"
generated_at="$(date -u '+%Y-%m-%d %H:%M:%S UTC')"
validation_start_epoch="$(date +%s)"
LOCALNET_VALIDATION_SMOKE_START_EPOCH="${validation_start_epoch}"
export LOCALNET_VALIDATION_SMOKE_START_EPOCH
go_version="$(go version)"
docker_version="$(docker version 2>&1 || true)"
docker_compose_version="$(compose_version_string)"

results=()
last_failure_label=""
last_failure_status=0
last_failure_output=""

cleanup() {
  make monitoring-down >/dev/null 2>&1 || true
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

check_phase15_artifacts() {
  local required_files=(
    "deploy/monitoring/README.md"
    "deploy/monitoring/common.sh"
    "deploy/monitoring/docker-compose.yml"
    "deploy/monitoring/prometheus/prometheus.yml"
    "deploy/monitoring/prometheus/alert-rules.yml"
    "deploy/monitoring/blackbox/blackbox.yml"
    "deploy/monitoring/grafana/provisioning/datasources/prometheus.yml"
    "deploy/monitoring/grafana/provisioning/dashboards/dashboards.yml"
    "deploy/monitoring/grafana/dashboards/kudora-localnet-overview.json"
    "deploy/monitoring/grafana/dashboards/kudora-evm.json"
    "deploy/monitoring/grafana/dashboards/kudora-cosmwasm-integrity.json"
    "deploy/monitoring/scripts/start-monitoring.sh"
    "deploy/monitoring/scripts/stop-monitoring.sh"
    "deploy/monitoring/scripts/reset-monitoring.sh"
    "deploy/monitoring/scripts/smoke-monitoring.sh"
    "docs/docker/phase-15-monitoring.md"
    "scripts/phase-15-validate.sh"
  )
  local path

  for path in "${required_files[@]}"; do
    [[ -f "${path}" ]] || {
      echo "phase-15-validate: required artifact missing: ${path}" >&2
      return 1
    }
  done
}

check_generated_state_not_tracked() {
  local tracked
  tracked="$(git ls-files | rg '(^\.localnet/|^tmp/localnet/|^tmp/phase-15-monitoring/|^deploy/monitoring/.*/\.env$|^deploy/monitoring/.*/(data|prometheus-data|grafana-data)/)' || true)"

  if [[ -n "${tracked}" ]]; then
    echo "phase-15-validate: generated localnet or monitoring state must not be tracked" >&2
    printf '%s\n' "${tracked}" >&2
    return 1
  fi
}

check_monitoring_result_current_run() {
  [[ -f "${MONITORING_RESULT_PATH}" ]] || {
    echo "phase-15-validate: monitoring result missing at ${MONITORING_RESULT_PATH}" >&2
    return 1
  }

  local mtime
  mtime="$(monitoring_file_mtime "${MONITORING_RESULT_PATH}")"
  (( mtime >= validation_start_epoch )) || {
    echo "phase-15-validate: monitoring result is stale" >&2
    return 1
  }

  jq -e --argjson start "${validation_start_epoch}" '
    (.run_id // "" | length > 0) and
    .run_started_epoch >= $start and
    .run_finished_epoch >= .run_started_epoch and
    .prometheus_status == "PASS" and
    .grafana_status == "PASS" and
    .scrape_targets_status == "PASS" and
    .cometbft_metrics_status == "PASS" and
    .rpc_probe_status == "PASS" and
    .rest_probe_status == "PASS" and
    .evm_probe_status == "PASS" and
    .grafana_probe_status == "PASS" and
    .dashboard_provisioning_status == "PASS" and
    (.latest_block_height // 0) > 0
  ' "${MONITORING_RESULT_PATH}" >/dev/null || {
    echo "phase-15-validate: monitoring result is incomplete or failed" >&2
    return 1
  }
}

check_integrity_smoke_current_run() {
  [[ -f "${INTEGRITY_RESULT_PATH}" ]] || {
    echo "phase-15-validate: integrity smoke result missing at ${INTEGRITY_RESULT_PATH}" >&2
    return 1
  }

  local mtime
  mtime="$(localnet_validation_file_mtime "${INTEGRITY_RESULT_PATH}")"
  (( mtime >= validation_start_epoch )) || {
    echo "phase-15-validate: integrity smoke result is stale" >&2
    return 1
  }

  jq -e --argjson start "${validation_start_epoch}" '
    (.run_id // "" | length > 0) and
    .run_started_epoch >= $start and
    .run_finished_epoch >= .run_started_epoch and
    .tenant_registration_status == "PASS" and
    .ownership_transfer_status == "PASS" and
    .ownership_acceptance_status == "PASS" and
    .new_owner_postaccept_commit_status == "PASS" and
    .root_match_status == "PASS" and
    .records_sorted_status == "PASS" and
    .record_query_status == "PASS" and
    .plaintext_leak_status == "PASS"
  ' "${INTEGRITY_RESULT_PATH}" >/dev/null || {
    echo "phase-15-validate: integrity smoke result is incomplete or failed" >&2
    return 1
  }
}

write_blocker() {
  {
    echo "# Phase 15 Blocker"
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
  local phase121_status="not run"
  local localnet_status="not run"
  local integrity_status="not run"
  local monitoring_up_status="not run"
  local monitoring_smoke_status="not run"
  local explorers_status="not run"
  local no_forks_status="not run"
  local no_secrets_status="not run"
  local dependency_audit_status="not run"
  local vulncheck_status="not run"
  local archive_status="not run"
  local docker_build_status="not run"
  local docker_smoke_status="not run"
  local generated_state_status="not run"
  local monitoring_current_run_status="not run"

  for result in "${results[@]}"; do
    case "${result}" in
      PASS\|make\ phase-12.1-lite-validate) phase121_status="PASS" ;;
      FAIL\|make\ phase-12.1-lite-validate) phase121_status="FAIL" ;;
      PASS\|make\ localnet-smoke-test) localnet_status="PASS" ;;
      FAIL\|make\ localnet-smoke-test) localnet_status="FAIL" ;;
      PASS\|make\ integrity-smoke-test) integrity_status="PASS" ;;
      FAIL\|make\ integrity-smoke-test) integrity_status="FAIL" ;;
      PASS\|make\ monitoring-up) monitoring_up_status="PASS" ;;
      FAIL\|make\ monitoring-up) monitoring_up_status="FAIL" ;;
      PASS\|make\ monitoring-smoke-test) monitoring_smoke_status="PASS" ;;
      FAIL\|make\ monitoring-smoke-test) monitoring_smoke_status="FAIL" ;;
      PASS\|make\ explorers-smoke-test) explorers_status="PASS" ;;
      FAIL\|make\ explorers-smoke-test) explorers_status="FAIL" ;;
      PASS\|make\ verify-no-forks) no_forks_status="PASS" ;;
      FAIL\|make\ verify-no-forks) no_forks_status="FAIL" ;;
      PASS\|make\ verify-no-secrets) no_secrets_status="PASS" ;;
      FAIL\|make\ verify-no-secrets) no_secrets_status="FAIL" ;;
      PASS\|make\ dependency-audit) dependency_audit_status="PASS" ;;
      FAIL\|make\ dependency-audit) dependency_audit_status="FAIL" ;;
      PASS\|make\ vulncheck) vulncheck_status="PASS" ;;
      FAIL\|make\ vulncheck) vulncheck_status="FAIL" ;;
      PASS\|make\ docker-build) docker_build_status="PASS" ;;
      FAIL\|make\ docker-build) docker_build_status="FAIL" ;;
      PASS\|make\ docker-smoke-test) docker_smoke_status="PASS" ;;
      FAIL\|make\ docker-smoke-test) docker_smoke_status="FAIL" ;;
      PASS\|Phase\ 15\ generated-state\ tracking\ guard) generated_state_status="PASS" ;;
      FAIL\|Phase\ 15\ generated-state\ tracking\ guard) generated_state_status="FAIL" ;;
      PASS\|Phase\ 15\ monitoring\ current-run\ verification) monitoring_current_run_status="PASS" ;;
      FAIL\|Phase\ 15\ monitoring\ current-run\ verification) monitoring_current_run_status="FAIL" ;;
      PASS\|make\ zip) archive_status="PASS" ;;
      FAIL\|make\ zip) archive_status="FAIL" ;;
    esac
  done

  local prometheus_status="not run"
  local grafana_status="not run"
  local scrape_targets_status="not run"
  local cometbft_metrics_status="not run"
  local rest_probe_status="not run"
  local evm_probe_status="not run"
  local dashboard_provisioning_status="not run"
  local latest_block_height="not run"

  if [[ -f "${MONITORING_RESULT_PATH}" ]]; then
    prometheus_status="$(jq -r '.prometheus_status // "not run"' "${MONITORING_RESULT_PATH}")"
    grafana_status="$(jq -r '.grafana_status // "not run"' "${MONITORING_RESULT_PATH}")"
    scrape_targets_status="$(jq -r '.scrape_targets_status // "not run"' "${MONITORING_RESULT_PATH}")"
    cometbft_metrics_status="$(jq -r '.cometbft_metrics_status // "not run"' "${MONITORING_RESULT_PATH}")"
    rest_probe_status="$(jq -r '.rest_probe_status // "not run"' "${MONITORING_RESULT_PATH}")"
    evm_probe_status="$(jq -r '.evm_probe_status // "not run"' "${MONITORING_RESULT_PATH}")"
    dashboard_provisioning_status="$(jq -r '.dashboard_provisioning_status // "not run"' "${MONITORING_RESULT_PATH}")"
    latest_block_height="$(jq -r '.latest_block_height // "not run"' "${MONITORING_RESULT_PATH}")"
  fi

  {
    echo "# Phase 15 Validation Report"
    echo
    echo "- Validation generated at: ${generated_at}"
    echo "- Branch: ${branch_name}"
    echo "- Starting commit: ${starting_commit}"
    echo "- Current HEAD before report generation: ${head_before_report}"
    echo "- Go version: \`${go_version}\`"
    echo "- Docker version:"
    echo '```text'
    printf '%s\n' "${docker_version}"
    echo '```'
    echo "- Docker Compose version:"
    echo '```text'
    printf '%s\n' "${docker_compose_version}"
    echo '```'
    echo "- Prometheus image/version: \`${PROMETHEUS_IMAGE}\`"
    echo "- Grafana image/version: \`${GRAFANA_IMAGE}\`"
    echo "- Optional exporter image versions: \`${BLACKBOX_EXPORTER_IMAGE}\`"
    echo
    echo "## Working Tree Status Before Validation"
    echo
    echo '```text'
    echo "${working_tree_status_before:-clean}"
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
    echo "## Monitoring Summary"
    echo
    echo "- Phase 12.1-lite validation result: ${phase121_status}"
    echo "- Localnet validation result: ${localnet_status}"
    echo "- Monitoring startup result: ${monitoring_up_status}"
    echo "- Monitoring smoke result: ${monitoring_smoke_status}"
    echo "- Prometheus API result: ${prometheus_status}"
    echo "- Grafana API/UI result: ${grafana_status}"
    echo "- Scrape target summary: ${scrape_targets_status}"
    echo "- CometBFT metrics target result: ${cometbft_metrics_status}"
    echo "- REST probe result: ${rest_probe_status}"
    echo "- EVM JSON-RPC probe result: ${evm_probe_status}"
    echo "- Expected eth_chainId: \`${LOCALNET_ETH_CHAIN_ID}\`"
    echo "- Dashboard provisioning result: ${dashboard_provisioning_status}"
    echo "- Latest block height observed by monitoring: ${latest_block_height}"
    echo
    echo "## Runtime Preservation Summary"
    echo
    echo "- Integrity smoke result: ${integrity_status}"
    echo "- Explorers smoke result: ${explorers_status}"
    echo "- Docker build result: ${docker_build_status}"
    echo "- Docker smoke result: ${docker_smoke_status}"
    echo
    echo "## Dependency And Security Summary"
    echo
    echo "- Dependency audit result: ${dependency_audit_status}"
    echo "- Vulnerability scan result: ${vulncheck_status}"
    echo "- No-forks result: ${no_forks_status}"
    echo "- No-secrets result: ${no_secrets_status}"
    echo "- Generated-state tracking guard result: ${generated_state_status}"
    echo
    echo "## Archive"
    echo
    echo "- Phase 15 archive: \`out/kudora-phase-15-monitoring.zip\`"
    echo "- Latest inspection archive: \`out/kudora-latest-inspection.zip\`"
    echo "- Archive generation result: ${archive_status}"
    echo
    echo "## Confirmations"
    echo
    echo "- No generated monitoring state is tracked."
    echo "- No generated localnet state is tracked."
    echo "- No secrets were committed."
    echo "- No business modules other than \`x/integrity\` are present."
    echo "- No IBC product, tokenfactory, packet-forward, rate-limit, ICA, or 08-wasm work was added."
    echo "- No Docker registry push was performed."
    echo
    echo "> Note: the final pushed commit may differ if this report itself is committed afterward."
  } >"${REPORT_PATH}"
}

run_check "Phase 15 required artifacts" check_phase15_artifacts || { write_blocker; write_report; echo "phase-15-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "Phase 15 generated-state tracking guard" check_generated_state_not_tracked || { write_blocker; write_report; echo "phase-15-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make phase-12.1-lite-validate" make phase-12.1-lite-validate || { write_blocker; write_report; echo "phase-15-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make tidy" make tidy || { write_blocker; write_report; echo "phase-15-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "go mod verify" go mod verify || { write_blocker; write_report; echo "phase-15-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make build" make build || { write_blocker; write_report; echo "phase-15-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make test" make test || { write_blocker; write_report; echo "phase-15-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make lint" make lint || { write_blocker; write_report; echo "phase-15-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make verify-no-forks" make verify-no-forks || { write_blocker; write_report; echo "phase-15-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make verify-clean-reset" make verify-clean-reset || { write_blocker; write_report; echo "phase-15-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make verify-no-secrets" make verify-no-secrets || { write_blocker; write_report; echo "phase-15-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make verify-integrity-generic" make verify-integrity-generic || { write_blocker; write_report; echo "phase-15-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make dependency-audit" make dependency-audit || { write_blocker; write_report; echo "phase-15-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make vulncheck" make vulncheck || { write_blocker; write_report; echo "phase-15-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make docker-build" make docker-build || { write_blocker; write_report; echo "phase-15-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make docker-smoke-test" make docker-smoke-test || { write_blocker; write_report; echo "phase-15-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make localnet-reset" make localnet-reset || { write_blocker; write_report; echo "phase-15-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make localnet-init" make localnet-init || { write_blocker; write_report; echo "phase-15-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make localnet-up" make localnet-up || { write_blocker; write_report; echo "phase-15-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make localnet-smoke-test" make localnet-smoke-test || { write_blocker; write_report; echo "phase-15-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "Phase 15 localnet smoke current-run verification" localnet_validation_check_smoke_current_run || { write_blocker; write_report; echo "phase-15-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make integrity-smoke-test" env KUDORA_USE_EXISTING_NODE=1 KUDORA_HOME="${LOCALNET_HOME}" KUDORA_RPC_URL="${LOCALNET_RPC_URL}" KUDORA_EVM_RPC_URL="${LOCALNET_EVM_RPC_URL}" KUDORA_CHAIN_ID="${LOCALNET_CHAIN_ID}" KUDORA_EVM_CHAIN_ID="${LOCALNET_EVM_CHAIN_ID}" KUDORA_ETH_CHAIN_ID="${LOCALNET_ETH_CHAIN_ID}" KUDORA_RESULT_DIR="${LOCALNET_SMOKE_DIR}" make integrity-smoke-test || { write_blocker; write_report; echo "phase-15-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "Phase 15 integrity smoke current-run verification" check_integrity_smoke_current_run || { write_blocker; write_report; echo "phase-15-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make monitoring-reset" make monitoring-reset || { write_blocker; write_report; echo "phase-15-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make monitoring-up" make monitoring-up || { write_blocker; write_report; echo "phase-15-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make monitoring-smoke-test" make monitoring-smoke-test || { write_blocker; write_report; echo "phase-15-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "Phase 15 monitoring current-run verification" check_monitoring_result_current_run || { write_blocker; write_report; echo "phase-15-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make explorers-reset" make explorers-reset || { write_blocker; write_report; echo "phase-15-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make explorers-up" make explorers-up || { write_blocker; write_report; echo "phase-15-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make explorers-smoke-test" make explorers-smoke-test || { write_blocker; write_report; echo "phase-15-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make explorers-down" make explorers-down || { write_blocker; write_report; echo "phase-15-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make monitoring-down" make monitoring-down || { write_blocker; write_report; echo "phase-15-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make localnet-down" make localnet-down || { write_blocker; write_report; echo "phase-15-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }
run_check "make zip" make zip || { write_blocker; write_report; echo "phase-15-validate: FAIL (${REPORT_PATH}); see ${BLOCKER_PATH}" >&2; exit 1; }

write_report
rm -f "${BLOCKER_PATH}"
echo "phase-15-validate: PASS (${REPORT_PATH})"
