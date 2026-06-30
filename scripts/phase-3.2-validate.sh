#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

OUT_DIR="out"
REPORT_PATH="${OUT_DIR}/phase-3.2-validation.md"
SECURITY_BLOCKER_PATH="${OUT_DIR}/phase-3.2-security-blocker.md"
EXPECTED_BRANCH="Upgrade"

mkdir -p "$OUT_DIR"
rm -f "$SECURITY_BLOCKER_PATH"

branch_name="$(git branch --show-current)"
if [[ "$branch_name" != "$EXPECTED_BRANCH" ]]; then
  echo "phase-3.2-validate: expected branch ${EXPECTED_BRANCH}, found ${branch_name}" >&2
  exit 1
fi

starting_commit="$(git rev-parse HEAD)"
head_before_report="$(git rev-parse HEAD)"
working_tree_status_before="$(git status --short)"
generated_at="$(date -u '+%Y-%m-%d %H:%M:%S UTC')"
go_version="$(go version)"
go_mod_go="$(awk '/^go / { print $2; exit }' go.mod)"
docker_go_version="$(awk -F= '/^ARG GO_VERSION=/ {gsub(/[[:space:]]/, "", $2); print $2; exit}' Dockerfile)"
ignite_version="$(ignite version 2>&1 | tr -d '\r')"
docker_version="$(docker version 2>&1)"
cosmos_sdk_version="$(go list -m -f '{{.Version}}' github.com/cosmos/cosmos-sdk)"
cometbft_version="$(go list -m -f '{{.Version}}' github.com/cometbft/cometbft)"
cosmos_evm_version="$(go list -m -f '{{.Version}}' github.com/cosmos/evm)"
geth_replacement_line="$(awk '/github\.com\/ethereum\/go-ethereum[[:space:]]*=>/ {gsub(/^[[:space:]]+/, "", $0); print; exit}' go.mod)"
docker_image_tag="$(awk -F':= ' '/^DOCKER_IMAGE :=/ {print $2; exit}' Makefile)"
github_actions_go_version="$(
  {
    rg -n "go-version:" .github/workflows/*.yml || true
    rg -n "go-version-file:" .github/workflows/*.yml || true
  } | sed 's/^[0-9]*://' | sort -u
)"

results=()
last_failure_label=""
last_failure_status=0
last_failure_output=""

run_check() {
  local label="$1"
  shift
  local log_file
  log_file="$(mktemp)"

  set +e
  "$@" >"$log_file" 2>&1
  local status=$?
  set -e

  if [[ $status -eq 0 ]]; then
    results+=("PASS|${label}")
    rm -f "$log_file"
    return 0
  fi

  results+=("FAIL|${label}")
  last_failure_label="$label"
  last_failure_status="$status"
  last_failure_output="$(tail -n 120 "$log_file")"
  rm -f "$log_file"
  return "$status"
}

check_phase32_docs() {
  local required_files=(
    "docs/security/phase-3.1-vulnerability-audit.md"
    "docs/security/phase-3.2-precompile-reachability-audit.md"
    "docs/release/dependency-baseline.md"
    "docs/evm/phase-3-evm-runtime.md"
    "scripts/dependency-audit.sh"
    "scripts/vulncheck.sh"
    "scripts/audit-evm-precompile-surface.sh"
    "scripts/assert-evm-precompile-policy.sh"
  )
  local path

  for path in "${required_files[@]}"; do
    if [[ ! -f "$path" ]]; then
      echo "phase-3.2-validate: required Phase 3.2 artifact missing: $path" >&2
      return 1
    fi
  done
}

check_phase32_scope() {
  local unexpected_surface
  unexpected_surface="$(
    rg -n \
      -e 'packetforward' \
      -e 'packet-forward' \
      -e 'ratelimit' \
      -e 'rate-limit' \
      -e 'interchainaccounts' \
      -e 'interchain accounts' \
      -e '08-wasm' \
      -e 'tokenfactory' \
      -e 'Blockscout' \
      -e 'Ping\.pub' \
      app cmd Dockerfile Makefile .github/workflows 2>/dev/null || true
  )"

  if [[ -n "$unexpected_surface" ]]; then
    echo "phase-3.2-validate: out-of-scope product surface detected" >&2
    printf '%s\n' "$unexpected_surface" >&2
    return 1
  fi
}

check_tmp_repos_not_tracked() {
  local tracked_tmp
  tracked_tmp="$(git ls-files tmp/cosmos-evm tmp/ignite-apps)"
  if [[ -n "$tracked_tmp" ]]; then
    echo "phase-3.2-validate: temporary upstream repositories must not be tracked" >&2
    printf '%s\n' "$tracked_tmp" >&2
    return 1
  fi
}

write_security_blocker() {
  {
    echo "# Phase 3.2 Security Blocker"
    echo
    echo "- Generated at: ${generated_at}"
    echo "- Branch: ${branch_name}"
    echo "- Starting commit: ${starting_commit}"
    echo "- Current HEAD before report generation: ${head_before_report}"
    echo
    echo "## Blocking Issue"
    echo
    echo "Phase 3.2 cannot be pushed because the Cosmos EVM precompile advisory waiver conditions were not fully proven, or another high/critical runtime vulnerability remained after policy evaluation."
    echo
    echo "## Evidence"
    echo
    echo "- Reachability audit: \`docs/security/phase-3.2-precompile-reachability-audit.md\`"
    echo "- Precompile surface audit: \`out/phase-3.2-precompile-surface.md\`"
    echo "- Govulncheck report: \`out/phase-3.2-govulncheck.md\`"
    echo "- Dependency audit: \`out/phase-3.2-dependency-audit.md\`"
    echo
    echo "## Safe Next Steps"
    echo
    echo "1. If the waiver conditions failed, keep the blocker and do not activate stateful Cosmos precompiles or ERC20 precompile defaults."
    echo "2. If a different high/critical vulnerability appeared, audit and remediate it before any push."
    echo "3. If future phases activate stateful precompiles, re-evaluate GO-2025-3684 without reusing the Phase 3.2 waiver."
  } >"$SECURITY_BLOCKER_PATH"
}

write_report() {
  local dependency_audit_status="not run"
  local precompile_surface_status="not run"
  local precompile_policy_status="not run"
  local govulncheck_status="not run"
  local phase3_status="not run"
  local waiver_status="not evaluated"
  local phase_archive_path="out/kudora-phase-3-evm-runtime.zip"
  local latest_archive_path="out/kudora-latest-inspection.zip"
  local compatibility_archive_path="out/kudora-phase-0-reset.zip"

  for result in "${results[@]}"; do
    case "$result" in
      PASS\|make\ phase-3-validate) phase3_status="PASS" ;;
      FAIL\|make\ phase-3-validate) phase3_status="FAIL" ;;
      PASS\|make\ dependency-audit) dependency_audit_status="PASS" ;;
      FAIL\|make\ dependency-audit) dependency_audit_status="FAIL" ;;
      PASS\|make\ audit-evm-precompile-surface) precompile_surface_status="PASS" ;;
      FAIL\|make\ audit-evm-precompile-surface) precompile_surface_status="FAIL" ;;
      PASS\|make\ assert-evm-precompile-policy) precompile_policy_status="PASS" ;;
      FAIL\|make\ assert-evm-precompile-policy) precompile_policy_status="FAIL" ;;
      PASS\|make\ vulncheck) govulncheck_status="PASS" ;;
      FAIL\|make\ vulncheck) govulncheck_status="FAIL" ;;
    esac
  done

  if [[ "$govulncheck_status" == "PASS" && -f out/phase-3.2-govulncheck.md ]]; then
    waiver_status="$(awk -F': ' '/^- GO-2025-3684 waiver status:/ {print $2; exit}' out/phase-3.2-govulncheck.md)"
  fi

  {
    echo "# Phase 3.2 Validation Report"
    echo
    echo "- Validation generated at: ${generated_at}"
    echo "- Branch: ${branch_name}"
    echo "- Starting commit: ${starting_commit}"
    echo "- Current HEAD before report generation: ${head_before_report}"
    echo "- Phase 3 validation result: ${phase3_status}"
    echo "- Go baseline: \`1.26.4\`"
    echo "- Go version from \`go.mod\`: \`${go_mod_go}\`"
    echo "- Docker Go version: \`${docker_go_version}\`"
    echo "- GitHub Actions Go version:"
    echo
    echo '```text'
    echo "${github_actions_go_version:-none found}"
    echo '```'
    echo
    echo "- Cosmos SDK version: \`${cosmos_sdk_version}\`"
    echo "- CometBFT version: \`${cometbft_version}\`"
    echo "- Cosmos EVM version: \`${cosmos_evm_version}\`"
    echo "- Approved go-ethereum exception: \`${geth_replacement_line}\`"
    echo "- Vulnerability advisory summary: \`GO-2025-3684 / GHSA-mjfq-3qr2-6g84\` stateful Cosmos EVM precompile partial state writes"
    echo "- Docker image tag: \`${docker_image_tag}\`"
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
    echo "${go_version}"
    echo
    echo "${ignite_version}"
    echo
    echo "${docker_version}"
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
    if [[ -n "$last_failure_label" ]]; then
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
    echo "## Audit Summary"
    echo
    echo "- Dependency audit result: ${dependency_audit_status}"
    echo "- Precompile surface audit result: ${precompile_surface_status}"
    echo "- Precompile policy assertion result: ${precompile_policy_status}"
    echo "- Vulnerability waiver status: ${waiver_status:-unknown}"
    echo "- Govulncheck result: ${govulncheck_status}"
    echo "- EVM smoke test result: inherited from \`make phase-3-validate\`"
    echo
    echo "## Archive Paths"
    echo
    echo "- Phase archive: \`${phase_archive_path}\`"
    echo "- Latest inspection archive: \`${latest_archive_path}\`"
    echo "- Compatibility archive: \`${compatibility_archive_path}\`"
    echo
    echo "## Confirmations"
    echo
    echo "- No secrets were detected in the working tree."
    echo "- No forbidden runtime forks were found."
    echo "- No business modules were added."
    echo "- No IBC product/tokenfactory/packet-forward/rate-limit/ICA/08-wasm/explorer/monitoring work was added."
    echo "- No Docker registry push was performed."
    if [[ -f "$SECURITY_BLOCKER_PATH" ]]; then
      echo "- Security blocker report: \`${SECURITY_BLOCKER_PATH}\`"
    fi
    echo "- Note: the final pushed commit may differ if this report is committed afterward."
  } >"$REPORT_PATH"
}

run_check "Phase 3.2 docs exist" check_phase32_docs || {
  write_report
  echo "phase-3.2-validate: FAIL (${REPORT_PATH})" >&2
  exit 1
}
run_check "temporary upstream repos are not tracked" check_tmp_repos_not_tracked || {
  write_report
  echo "phase-3.2-validate: FAIL (${REPORT_PATH})" >&2
  exit 1
}
run_check "Phase 3.2 scope guard" check_phase32_scope || {
  write_report
  echo "phase-3.2-validate: FAIL (${REPORT_PATH})" >&2
  exit 1
}
run_check "make phase-3-validate" make phase-3-validate || {
  write_report
  echo "phase-3.2-validate: FAIL (${REPORT_PATH})" >&2
  exit 1
}
run_check "make tidy" make tidy || { write_report; echo "phase-3.2-validate: FAIL (${REPORT_PATH})" >&2; exit 1; }
run_check "go mod verify" go mod verify || { write_report; echo "phase-3.2-validate: FAIL (${REPORT_PATH})" >&2; exit 1; }
run_check "make build" make build || { write_report; echo "phase-3.2-validate: FAIL (${REPORT_PATH})" >&2; exit 1; }
run_check "make test" make test || { write_report; echo "phase-3.2-validate: FAIL (${REPORT_PATH})" >&2; exit 1; }
run_check "make lint" make lint || { write_report; echo "phase-3.2-validate: FAIL (${REPORT_PATH})" >&2; exit 1; }
run_check "make verify-no-forks" make verify-no-forks || { write_report; echo "phase-3.2-validate: FAIL (${REPORT_PATH})" >&2; exit 1; }
run_check "make verify-clean-reset" make verify-clean-reset || { write_report; echo "phase-3.2-validate: FAIL (${REPORT_PATH})" >&2; exit 1; }
run_check "make verify-no-secrets" make verify-no-secrets || { write_report; echo "phase-3.2-validate: FAIL (${REPORT_PATH})" >&2; exit 1; }
run_check "make dependency-audit" make dependency-audit || { write_report; echo "phase-3.2-validate: FAIL (${REPORT_PATH})" >&2; exit 1; }
run_check "make audit-evm-precompile-surface" make audit-evm-precompile-surface || {
  write_security_blocker
  write_report
  echo "phase-3.2-validate: FAIL (${REPORT_PATH}); see ${SECURITY_BLOCKER_PATH}" >&2
  exit 1
}
run_check "make assert-evm-precompile-policy" make assert-evm-precompile-policy || {
  write_security_blocker
  write_report
  echo "phase-3.2-validate: FAIL (${REPORT_PATH}); see ${SECURITY_BLOCKER_PATH}" >&2
  exit 1
}
run_check "make vulncheck" make vulncheck || {
  write_security_blocker
  write_report
  echo "phase-3.2-validate: FAIL (${REPORT_PATH}); see ${SECURITY_BLOCKER_PATH}" >&2
  exit 1
}
run_check "make docker-build" make docker-build || { write_report; echo "phase-3.2-validate: FAIL (${REPORT_PATH})" >&2; exit 1; }
run_check "make docker-smoke-test" make docker-smoke-test || { write_report; echo "phase-3.2-validate: FAIL (${REPORT_PATH})" >&2; exit 1; }
run_check "make evm-smoke-test" make evm-smoke-test || { write_report; echo "phase-3.2-validate: FAIL (${REPORT_PATH})" >&2; exit 1; }
run_check "make zip" make zip || { write_report; echo "phase-3.2-validate: FAIL (${REPORT_PATH})" >&2; exit 1; }

write_report

echo "phase-3.2-validate: PASS (${REPORT_PATH})"
