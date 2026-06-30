#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

command -v jq >/dev/null 2>&1 || {
  echo "audit-evm-precompile-surface: jq is required" >&2
  exit 1
}

BINARY="${ROOT_DIR}/build/kudorad"
OUT_DIR="out"
REPORT_PATH="${OUT_DIR}/phase-3.2-precompile-surface.md"
TMP_HOME="${ROOT_DIR}/tmp/phase-3.2-precompile-surface-home"
GENESIS_PATH="${TMP_HOME}/config/genesis.json"

if [[ ! -x "$BINARY" ]]; then
  echo "audit-evm-precompile-surface: expected built binary at ${BINARY}. Run make build first." >&2
  exit 1
fi

mkdir -p "$OUT_DIR"
rm -rf "$TMP_HOME"
trap 'rm -rf "$TMP_HOME"' EXIT

"$BINARY" init phase-3.2-precompile-audit \
  --chain-id kudora_12000-1 \
  --default-denom akud \
  --home "$TMP_HOME" \
  >"${TMP_HOME}.stdout" 2>"${TMP_HOME}.stderr"

safe_precompiles=(
  "0x0000000000000000000000000000000000000100:p256"
  "0x0000000000000000000000000000000000000400:bech32"
)

stateful_precompiles=(
  "0x0000000000000000000000000000000000000800:staking"
  "0x0000000000000000000000000000000000000801:distribution"
  "0x0000000000000000000000000000000000000802:ics20"
  "0x0000000000000000000000000000000000000804:bank"
  "0x0000000000000000000000000000000000000805:gov"
  "0x0000000000000000000000000000000000000806:slashing"
  "0x0000000000000000000000000000000000000807:ics02"
)

label_for() {
  local needle="$1"
  shift
  local item
  for item in "$@"; do
    local address="${item%%:*}"
    local label="${item#*:}"
    if [[ "$address" == "$needle" ]]; then
      printf '%s' "$label"
      return 0
    fi
  done
  printf 'unknown'
}

mapfile -t active_static < <(jq -r '.app_state.evm.params.active_static_precompiles[]?' "$GENESIS_PATH")
token_pair_count="$(jq '.app_state.erc20.token_pairs | length' "$GENESIS_PATH")"
native_precompile_count="$(jq '.app_state.erc20.native_precompiles | length' "$GENESIS_PATH")"
dynamic_precompile_count="$(jq '.app_state.erc20.dynamic_precompiles | length' "$GENESIS_PATH")"

active_stateful=()
unexpected_active=()
active_labels=()

for address in "${active_static[@]}"; do
  if label="$(label_for "$address" "${safe_precompiles[@]}")" && [[ "$label" != "unknown" ]]; then
    active_labels+=("${address} (${label})")
    continue
  fi

  if label="$(label_for "$address" "${stateful_precompiles[@]}")" && [[ "$label" != "unknown" ]]; then
    active_stateful+=("${address} (${label})")
    active_labels+=("${address} (${label})")
    continue
  fi

  unexpected_active+=("$address")
  active_labels+=("${address} (unexpected)")
done

distribution_active="no"
bank_active="no"
staking_active="no"
gov_active="no"
ics20_active="no"
ics02_active="no"
custom_stateful_active="no"

for entry in "${active_stateful[@]}"; do
  case "$entry" in
    *"(distribution)") distribution_active="yes" ;;
    *"(bank)") bank_active="yes" ;;
    *"(staking)") staking_active="yes" ;;
    *"(gov)") gov_active="yes" ;;
    *"(ics20)") ics20_active="yes" ;;
    *"(ics02)") ics02_active="yes" ;;
  esac
done

if (( ${#unexpected_active[@]} > 0 )); then
  custom_stateful_active="yes"
fi

source_wiring="$(
  {
    echo "app/genesis.go"
    sed -n '96,120p' app/genesis.go
    echo
    echo "app/app.go"
    sed -n '400,416p' app/app.go
  }
)"

failure_reasons=()
if (( ${#active_stateful[@]} > 0 )); then
  failure_reasons+=("stateful Cosmos static precompiles are active by default: ${active_stateful[*]}")
fi
if (( ${#unexpected_active[@]} > 0 )); then
  failure_reasons+=("unexpected active static precompiles were found: ${unexpected_active[*]}")
fi
if [[ "$token_pair_count" != "0" ]]; then
  failure_reasons+=("ERC20 token pairs are configured by default")
fi
if [[ "$native_precompile_count" != "0" ]]; then
  failure_reasons+=("ERC20 native precompiles are configured by default")
fi
if [[ "$dynamic_precompile_count" != "0" ]]; then
  failure_reasons+=("ERC20 dynamic precompiles are configured by default")
fi

{
  echo "# Phase 3.2 Precompile Surface Audit"
  echo
  echo "- Generated at: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
  echo "- Source inspection scope: \`app/genesis.go\`, \`app/app.go\`"
  echo "- Runtime inspection source: fresh \`kudorad init\` genesis under ignored \`tmp/\`"
  echo
  echo "## Source Wiring Evidence"
  echo
  echo '```go'
  printf '%s\n' "$source_wiring"
  echo '```'
  echo
  echo "## Active Surface"
  echo
  echo "- Static precompiles activated by default:"
  echo "  - Prague EVM precompiles are active implicitly through the EVM core."
  if (( ${#active_labels[@]} > 0 )); then
    local_item=""
    for local_item in "${active_labels[@]}"; do
      echo "  - ${local_item}"
    done
  else
    echo "  - none"
  fi
  echo "- Stateful Cosmos precompiles activated by default: ${active_stateful[*]:-none}"
  echo "- x/erc20 token pairs default state: ${token_pair_count}"
  echo "- x/erc20 native precompiles default state: ${native_precompile_count}"
  echo "- x/erc20 dynamic precompiles default state: ${dynamic_precompile_count}"
  echo "- distribution precompile active: ${distribution_active}"
  echo "- bank precompile active: ${bank_active}"
  echo "- staking precompile active: ${staking_active}"
  echo "- gov precompile active: ${gov_active}"
  echo "- ICS-20 precompile active: ${ics20_active}"
  echo "- ICS-02 precompile active: ${ics02_active}"
  echo "- custom stateful precompile active: ${custom_stateful_active}"
  echo
  echo "## Result"
  echo
  if (( ${#failure_reasons[@]} == 0 )); then
    echo "- PASS: Kudora's active Phase 3 runtime enables only Prague, p256, and bech32, with no default ERC20 precompile surface."
  else
    echo "- FAIL:"
    local_reason=""
    for local_reason in "${failure_reasons[@]}"; do
      echo "  - ${local_reason}"
    done
  fi
} >"$REPORT_PATH"

if (( ${#failure_reasons[@]} > 0 )); then
  echo "audit-evm-precompile-surface: FAIL (${REPORT_PATH})" >&2
  exit 1
fi

echo "audit-evm-precompile-surface: PASS (${REPORT_PATH})"
