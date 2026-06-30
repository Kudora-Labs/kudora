#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

command -v jq >/dev/null 2>&1 || {
  echo "assert-evm-precompile-policy: jq is required" >&2
  exit 1
}

BINARY="${ROOT_DIR}/build/kudorad"
TMP_HOME="${ROOT_DIR}/tmp/phase-3.2-precompile-policy"
GENESIS_PATH="${TMP_HOME}/config/genesis.json"

if [[ ! -x "$BINARY" ]]; then
  echo "assert-evm-precompile-policy: expected built binary at ${BINARY}. Run make build first." >&2
  exit 1
fi

rm -rf "$TMP_HOME"
trap 'rm -rf "$TMP_HOME"' EXIT

"$BINARY" init phase-3.2-precompile-policy \
  --chain-id kudora_12000-1 \
  --default-denom akud \
  --home "$TMP_HOME" \
  >/dev/null 2>&1

expected_active='[
  "0x0000000000000000000000000000000000000100",
  "0x0000000000000000000000000000000000000400"
]'

jq -e --argjson expected "$expected_active" '
  (.app_state.evm.params.active_static_precompiles // []) == $expected
' "$GENESIS_PATH" >/dev/null || {
  echo "assert-evm-precompile-policy: active static precompile list drifted from the approved p256/bech32-only set" >&2
  exit 1
}

jq -e '
  (.app_state.erc20.token_pairs | length) == 0 and
  (.app_state.erc20.native_precompiles | length) == 0 and
  (.app_state.erc20.dynamic_precompiles | length) == 0
' "$GENESIS_PATH" >/dev/null || {
  echo "assert-evm-precompile-policy: ERC20 precompile surface is not empty by default" >&2
  exit 1
}

jq -e '
  [
    "0x0000000000000000000000000000000000000800",
    "0x0000000000000000000000000000000000000801",
    "0x0000000000000000000000000000000000000802",
    "0x0000000000000000000000000000000000000804",
    "0x0000000000000000000000000000000000000805",
    "0x0000000000000000000000000000000000000806",
    "0x0000000000000000000000000000000000000807"
  ] as $forbidden
  | [(.app_state.evm.params.active_static_precompiles // [])[] | select(. as $addr | $forbidden | index($addr))] | length == 0
' "$GENESIS_PATH" >/dev/null || {
  echo "assert-evm-precompile-policy: a forbidden stateful Cosmos precompile is active by default" >&2
  exit 1
}

echo "assert-evm-precompile-policy: PASS"
