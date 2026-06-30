#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

command -v jq >/dev/null 2>&1 || {
  echo "vulncheck: jq is required" >&2
  exit 1
}

OUT_DIR="out"
REPORT_PATH="${OUT_DIR}/phase-3.2-govulncheck.md"
BLOCKER_PATH="${OUT_DIR}/phase-3.2-vulncheck-blocker.md"
TOOL_PACKAGE="golang.org/x/vuln/cmd/govulncheck@latest"
BINARY_PATH="./build/kudorad"
WAIVER_PHRASE="unreachable by active Kudora Phase 3 runtime configuration"
ALLOWED_GETH_REPLACEMENT="replace github.com/ethereum/go-ethereum => github.com/cosmos/go-ethereum v1.17.2-cosmos-0"
MSGPACK_POLICY_DOC="docs/security/phase-5-cosmwasm-vulnerability-audit.md"
MSGPACK_POLICY_PHRASE="resolved by github.com/shamaton/msgpack/v2 v2.4.1 with upstream vulnerability-database lag acknowledged"
MSGPACK_FIXED_V2="v2.4.1"
MSGPACK_FIXED_V3="v3.1.1"

mkdir -p "$OUT_DIR"
rm -f "$BLOCKER_PATH"

if [[ ! -x "$BINARY_PATH" ]]; then
  echo "vulncheck: expected built binary at ${BINARY_PATH}. Run make build first." >&2
  exit 1
fi

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
tool_bin_dir="${tmp_dir}/bin"
mkdir -p "$tool_bin_dir"

generated_at="$(date -u '+%Y-%m-%d %H:%M:%S UTC')"
go_version="$(go version)"
(cd "$tmp_dir" && GOWORK=off GOBIN="$tool_bin_dir" go install "${TOOL_PACKAGE}")
govulncheck_bin="${tool_bin_dir}/govulncheck"
govulncheck_version="$("${govulncheck_bin}" -version 2>&1)"

source_json="$tmp_dir/source.json"
source_err="$tmp_dir/source.err"
set +e
"${govulncheck_bin}" -json ./... >"$source_json" 2>"$source_err"
source_status=$?
set -e

if [[ $source_status -eq 0 ]]; then
  source_mode_note="source-mode scan on ./... succeeded"
else
  if rg -q 'ForEachElement called on type containing \*types\.TypeParam|panic:' "$source_err"; then
    source_mode_note="source-mode scan on ./... failed because govulncheck/x/tools panicked under the current Go 1.26 toolchain; binary-mode fallback was used"
  else
    source_mode_note="source-mode scan on ./... failed; binary-mode fallback was used"
  fi
fi

binary_json="$tmp_dir/binary.json"
binary_err="$tmp_dir/binary.err"
set +e
"${govulncheck_bin}" -mode=binary -json "$BINARY_PATH" >"$binary_json" 2>"$binary_err"
binary_status=$?
set -e

if [[ ! -s "$binary_json" ]]; then
  {
    echo "# Phase 3.2 Vulncheck Blocker"
    echo
    echo "- Generated at: ${generated_at}"
    echo "- Go version: \`${go_version}\`"
    echo "- Govulncheck version:"
    echo
    echo '```text'
    echo "${govulncheck_version}"
    echo '```'
    echo
    echo "## Failure"
    echo
    echo "Govulncheck did not produce a usable fallback binary scan result."
    echo
    echo "### Source-mode stderr"
    echo
    echo '```text'
    cat "$source_err"
    echo '```'
    echo
    echo "### Binary-mode stderr"
    echo
    echo '```text'
    cat "$binary_err"
    echo '```'
  } >"$BLOCKER_PATH"
  echo "vulncheck: unable to obtain a usable govulncheck result; see ${BLOCKER_PATH}" >&2
  exit 1
fi

severity_for() {
  case "$1" in
    GO-2025-3684) echo "High" ;;
    GO-2026-4677) echo "Critical" ;;
    GO-2026-4513) echo "High" ;;
    GO-2026-4740) echo "High" ;;
    GO-2026-4479) echo "Moderate" ;;
    GO-2025-3442) echo "Low" ;;
    GO-2024-2584) echo "Low" ;;
    GO-2023-1821) echo "Low" ;;
    GO-2023-1881) echo "Low" ;;
    *) echo "Unknown" ;;
  esac
}

scope_for() {
  case "$1" in
    GO-2025-3684) echo "runtime (stateful Cosmos EVM precompile path)" ;;
    GO-2026-4677) echo "runtime (Cosmos EVM module)" ;;
    GO-2026-4513) echo "runtime-transitive (CosmWasm wasmvm msgpack decoder)" ;;
    GO-2026-4740) echo "runtime-transitive (CosmWasm wasmvm msgpack decoder; duplicate advisory source)" ;;
    GO-2026-4479) echo "runtime-transitive (DTLS via networking stack)" ;;
    GO-2025-3442) echo "runtime (CometBFT blocksync surface)" ;;
    GO-2024-2584) echo "runtime (staking / slashing surface)" ;;
    GO-2023-1821) echo "module-level only; inactive x/crisis product surface in Kudora" ;;
    GO-2023-1881) echo "module-level only; inactive x/crisis product surface in Kudora" ;;
    *) echo "unknown" ;;
  esac
}

summary_for() {
  local osv_id="$1"
  jq -rs --arg id "$osv_id" '
    [ .[] | select(.osv != null and .osv.id == $id) | .osv.summary ][0] // "summary unavailable"
  ' "$binary_json"
}

fixed_version_for() {
  local osv_id="$1"
  jq -rs --arg id "$osv_id" '
    [ .[] | select(.finding != null and .finding.osv == $id and (.finding.fixed_version // "") != "") | .finding.fixed_version ][0] // "none reported"
  ' "$binary_json"
}

waiver_status="not applicable"
waiver_reason="GO-2025-3684 not present in current findings"
msgpack_policy_status="not applicable"
msgpack_policy_reason="msgpack advisories not present in current findings"

evaluate_go20253684_waiver() {
  waiver_status="rejected"
  waiver_reason=""

  rg -n '^\s*github\.com/cosmos/evm v0\.7\.0' go.mod >/dev/null || {
    waiver_reason="github.com/cosmos/evm is not exactly v0.7.0"
    return
  }

  rg -n '^replace github\.com/ethereum/go-ethereum => github\.com/cosmos/go-ethereum v1\.17\.2-cosmos-0$' go.mod >/dev/null || {
    waiver_reason="approved cosmos/go-ethereum replacement is missing or mismatched"
    return
  }

  if [[ ! -f docs/security/phase-3.2-precompile-reachability-audit.md ]]; then
    waiver_reason="phase-3.2 reachability audit document is missing"
    return
  fi

  rg -n --fixed-strings "$WAIVER_PHRASE" docs/security/phase-3.2-precompile-reachability-audit.md >/dev/null || {
    waiver_reason="phase-3.2 reachability audit does not contain the required waiver conclusion"
    return
  }

  if ! ./scripts/audit-evm-precompile-surface.sh >"$tmp_dir/waiver-audit.stdout" 2>"$tmp_dir/waiver-audit.stderr"; then
    waiver_reason="audit-evm-precompile-surface failed"
    return
  fi

  if ! ./scripts/assert-evm-precompile-policy.sh >"$tmp_dir/waiver-assert.stdout" 2>"$tmp_dir/waiver-assert.stderr"; then
    waiver_reason="assert-evm-precompile-policy failed"
    return
  fi

  waiver_status="applied"
  waiver_reason="$WAIVER_PHRASE"
}

evaluate_msgpack_policy() {
  msgpack_policy_status="rejected"
  msgpack_policy_reason=""

  if [[ ! -f "$MSGPACK_POLICY_DOC" ]]; then
    msgpack_policy_reason="Phase 5 msgpack vulnerability audit document is missing"
    return
  fi

  rg -n --fixed-strings "$MSGPACK_POLICY_PHRASE" "$MSGPACK_POLICY_DOC" >/dev/null || {
    msgpack_policy_reason="Phase 5 msgpack vulnerability audit does not contain the required policy conclusion"
    return
  }

  local msgpack_v2_version
  msgpack_v2_version="$(go list -m -f '{{.Version}}' github.com/shamaton/msgpack/v2 2>/dev/null || printf 'absent')"
  if [[ "$msgpack_v2_version" != "$MSGPACK_FIXED_V2" ]]; then
    msgpack_policy_reason="github.com/shamaton/msgpack/v2 is not pinned to ${MSGPACK_FIXED_V2}"
    return
  fi

  local msgpack_v3_version="absent"
  if msgpack_v3_version="$(go list -m -f '{{.Version}}' github.com/shamaton/msgpack/v3 2>/dev/null)"; then
    if [[ "$msgpack_v3_version" != "$MSGPACK_FIXED_V3" ]]; then
      msgpack_policy_reason="github.com/shamaton/msgpack/v3 is present but not pinned to ${MSGPACK_FIXED_V3}"
      return
    fi
  fi

  if ! go mod why -m github.com/shamaton/msgpack/v2 2>/dev/null | rg -q 'github\.com/CosmWasm/wasmvm/v3/types'; then
    msgpack_policy_reason="github.com/shamaton/msgpack/v2 is no longer only the known wasmvm transitive dependency"
    return
  fi

  msgpack_policy_status="applied"
  msgpack_policy_reason="$MSGPACK_POLICY_PHRASE"
}

mapfile -t finding_ids < <(jq -r 'select(.finding != null) | .finding.osv' "$binary_json" | sort -u)

if printf '%s\n' "${finding_ids[@]:-}" | rg -qx 'GO-2025-3684'; then
  evaluate_go20253684_waiver
fi

if printf '%s\n' "${finding_ids[@]:-}" | rg -qx 'GO-2026-4513|GO-2026-4740'; then
  evaluate_msgpack_policy
fi

high_or_critical_detected="no"
unknown_severity_detected="no"
findings_table="$tmp_dir/findings-table.txt"

if (( ${#finding_ids[@]} == 0 )); then
  printf '| none | none | none | none | none | none |\n' >"$findings_table"
else
  : >"$findings_table"
  for osv_id in "${finding_ids[@]}"; do
    severity="$(severity_for "$osv_id")"
    scope="$(scope_for "$osv_id")"
    summary="$(summary_for "$osv_id" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g')"
    fixed_version="$(fixed_version_for "$osv_id")"
    disposition="reported"

    if [[ "$osv_id" == "GO-2025-3684" && "$waiver_status" == "applied" ]]; then
      disposition="waived (${WAIVER_PHRASE})"
    fi

    if [[ ( "$osv_id" == "GO-2026-4513" || "$osv_id" == "GO-2026-4740" ) && "$msgpack_policy_status" == "applied" ]]; then
      disposition="suppressed (${MSGPACK_POLICY_PHRASE})"
    fi

    printf '| `%s` | %s | %s | `%s` | %s | %s |\n' \
      "$osv_id" \
      "$severity" \
      "$scope" \
      "$fixed_version" \
      "$disposition" \
      "$summary" \
      >>"$findings_table"

    if [[ "$severity" == "Unknown" ]]; then
      unknown_severity_detected="yes"
    fi

    if [[ "$osv_id" == "GO-2025-3684" && "$waiver_status" == "applied" ]]; then
      continue
    fi

    if [[ ( "$osv_id" == "GO-2026-4513" || "$osv_id" == "GO-2026-4740" ) && "$msgpack_policy_status" == "applied" ]]; then
      continue
    fi

    if [[ "$severity" == "High" || "$severity" == "Critical" ]]; then
      high_or_critical_detected="yes"
    fi
  done
fi

{
  echo "# Phase 3.2 Govulncheck Report"
  echo
  echo "- Generated at: ${generated_at}"
  echo "- Go version: \`${go_version}\`"
  echo "- Source mode status: ${source_mode_note}"
  echo "- Binary mode exit status: \`${binary_status}\`"
  echo "- GO-2025-3684 waiver status: ${waiver_status}"
  echo "- GO-2025-3684 waiver rationale: ${waiver_reason}"
  echo "- Msgpack advisory policy status: ${msgpack_policy_status}"
  echo "- Msgpack advisory rationale: ${msgpack_policy_reason}"
  echo "- High or critical runtime findings detected after waiver policy: ${high_or_critical_detected}"
  echo "- Unknown severity findings detected: ${unknown_severity_detected}"
  echo
  echo "## Govulncheck Version"
  echo
  echo '```text'
  echo "${govulncheck_version}"
  echo '```'
  echo
  echo "## Findings"
  echo
  echo '| OSV | Severity | Scope | Fixed Version | Disposition | Summary |'
  echo '| --- | --- | --- | --- | --- | --- |'
  cat "$findings_table"
  echo
  echo "## GO-2025-3684 Waiver Requirements"
  echo
  echo "The Phase 3.2 waiver is only valid when all of the following remain true:"
  echo
  echo "1. \`github.com/cosmos/evm\` is exactly \`v0.7.0\`."
  echo "2. The approved replacement remains exactly \`${ALLOWED_GETH_REPLACEMENT}\`."
  echo "3. \`./scripts/audit-evm-precompile-surface.sh\` passes."
  echo "4. \`./scripts/assert-evm-precompile-policy.sh\` passes."
  echo "5. \`docs/security/phase-3.2-precompile-reachability-audit.md\` exists."
  echo "6. That document states \`${WAIVER_PHRASE}\`."
  echo
  echo "## Msgpack Advisory Policy Requirements"
  echo
  echo "The Phase 5 msgpack policy is only valid when all of the following remain true:"
  echo
  echo "1. \`${MSGPACK_POLICY_DOC}\` exists."
  echo "2. That document states \`${MSGPACK_POLICY_PHRASE}\`."
  echo "3. \`github.com/shamaton/msgpack/v2\` is exactly \`${MSGPACK_FIXED_V2}\`."
  echo "4. \`github.com/shamaton/msgpack/v3\` is absent or fixed at \`${MSGPACK_FIXED_V3}\`."
  echo "5. The msgpack dependency remains the known \`wasmvm\` transitive path, not a new direct product surface."
  echo
  echo "## Source-mode stderr"
  echo
  echo '```text'
  if [[ -s "$source_err" ]]; then
    cat "$source_err"
  else
    echo "none"
  fi
  echo '```'
  echo
  echo "## Binary-mode stderr"
  echo
  echo '```text'
  if [[ -s "$binary_err" ]]; then
    cat "$binary_err"
  else
    echo "none"
  fi
  echo '```'
} >"$REPORT_PATH"

if [[ "$unknown_severity_detected" == "yes" ]]; then
  echo "vulncheck: unknown-severity findings require manual review; see ${REPORT_PATH}" >&2
  exit 1
fi

if [[ "$high_or_critical_detected" == "yes" ]]; then
  echo "vulncheck: high or critical audited findings detected after waiver policy; see ${REPORT_PATH}" >&2
  exit 1
fi

echo "vulncheck: PASS (${REPORT_PATH})"
