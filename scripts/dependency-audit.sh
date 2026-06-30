#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

command -v jq >/dev/null 2>&1 || {
  echo "dependency-audit: jq is required" >&2
  exit 1
}

OUT_DIR="out"
REPORT_PATH="${OUT_DIR}/phase-3.2-dependency-audit.md"

mkdir -p "$OUT_DIR"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

generated_at="$(date -u '+%Y-%m-%d %H:%M:%S UTC')"
go_version="$(go version)"
go_env_goversion="$(go env GOVERSION)"
go_mod_go="$(awk '/^go / { print $2; exit }' go.mod)"
docker_go_version="$(awk -F= '/^ARG GO_VERSION=/ {gsub(/[[:space:]]/, "", $2); print $2; exit}' Dockerfile)"
cosmos_sdk_version="$(go list -m -f '{{.Version}}' github.com/cosmos/cosmos-sdk)"
cometbft_version="$(go list -m -f '{{.Version}}' github.com/cometbft/cometbft)"
cosmos_evm_version="$(go list -m -f '{{.Version}}' github.com/cosmos/evm)"
wasmd_version="$(go list -m -f '{{.Version}}' github.com/CosmWasm/wasmd 2>/dev/null || printf 'not present')"
wasmvm_version="$(go list -m -f '{{.Version}}' github.com/CosmWasm/wasmvm/v3 2>/dev/null || printf 'not present')"
msgpack_v2_version="$(go list -m -f '{{.Version}}' github.com/shamaton/msgpack/v2 2>/dev/null || printf 'not present')"
go_ethereum_version="$(go list -m -f '{{.Version}}' github.com/ethereum/go-ethereum)"
cosmos_geth_replacement="$(go list -m -f '{{if .Replace}}{{.Replace.Path}} {{.Replace.Version}}{{end}}' github.com/ethereum/go-ethereum)"
wasmd_replacement="$(go list -m -f '{{if .Replace}}{{.Replace.Path}} {{.Replace.Version}}{{end}}' github.com/CosmWasm/wasmd 2>/dev/null || true)"
wasmvm_replacement="$(go list -m -f '{{if .Replace}}{{.Replace.Path}} {{.Replace.Version}}{{end}}' github.com/CosmWasm/wasmvm/v3 2>/dev/null || true)"

go_mod_edit_json="$tmp_dir/go-mod-edit.json"
go mod edit -json >"$go_mod_edit_json"

direct_dependencies="$(
  jq -r '
    .Require
    | map(select((.Indirect // false) | not))
    | sort_by(.Path)
    | .[]
    | "- `\(.Path)` `\(.Version)`"
  ' "$go_mod_edit_json"
)"

replace_directives="$(
  jq -r '
    (.Replace // [])
    | map(
        "- `\(.Old.Path)` => `\(.New.Path)\(if .New.Version then " " + .New.Version else "" end)`"
      )
    | .[]
  ' "$go_mod_edit_json"
)"

why_cosmos_evm="$tmp_dir/why-cosmos-evm.txt"
why_wasmd="$tmp_dir/why-wasmd.txt"
why_wasmvm="$tmp_dir/why-wasmvm.txt"
why_msgpack_v2="$tmp_dir/why-msgpack-v2.txt"
why_geth="$tmp_dir/why-geth.txt"
why_cosmos_geth="$tmp_dir/why-cosmos-geth.txt"

go mod why -m github.com/cosmos/evm >"$why_cosmos_evm" 2>&1 || true
go mod why -m github.com/CosmWasm/wasmd >"$why_wasmd" 2>&1 || true
go mod why -m github.com/CosmWasm/wasmvm/v3 >"$why_wasmvm" 2>&1 || true
go mod why -m github.com/shamaton/msgpack/v2 >"$why_msgpack_v2" 2>&1 || true
go mod why -m github.com/ethereum/go-ethereum >"$why_geth" 2>&1 || true
go mod why -m github.com/cosmos/go-ethereum >"$why_cosmos_geth" 2>&1 || true

module_updates_json="$tmp_dir/module-updates.json"
module_updates_err="$tmp_dir/module-updates.err"
set +e
go list -m -u -json all >"$module_updates_json" 2>"$module_updates_err"
module_updates_status=$?
set -e

if [[ $module_updates_status -eq 0 ]]; then
  modules_with_updates="$(
    jq -s '[.[] | select(.Update != null)] | length' "$module_updates_json"
  )"
  core_update_summary="$(
    jq -s -r '
      [
        .[]
        | select(
            .Path == "github.com/cosmos/cosmos-sdk"
            or .Path == "github.com/cometbft/cometbft"
            or .Path == "github.com/cosmos/evm"
            or .Path == "github.com/CosmWasm/wasmd"
            or .Path == "github.com/CosmWasm/wasmvm/v3"
            or .Path == "github.com/shamaton/msgpack/v2"
            or .Path == "github.com/cosmos/ibc-go/v11"
            or .Path == "github.com/ethereum/go-ethereum"
          )
      ]
      | .[]
      | "- `\(.Path)` current `\(.Version)`"
        + (if .Update then " -> `\(.Update.Version)`" else " (no newer version reported)" end)
    ' "$module_updates_json"
  )"
  if [[ -z "$core_update_summary" ]]; then
    core_update_summary="- No core module update summary was produced."
  fi
  module_updates_note="\`go list -m -u -json all\` succeeded. Modules with updates reported: ${modules_with_updates}."
else
  core_update_summary="- Update query did not complete."
  module_updates_note="\`go list -m -u -json all\` failed; see the captured stderr below."
fi

{
  echo "# Active Dependency Audit"
  echo
  echo "- Generated at: ${generated_at}"
  echo "- Go version: \`${go_version}\`"
  echo "- \`go env GOVERSION\`: \`${go_env_goversion}\`"
  echo "- \`go.mod\` Go directive: \`${go_mod_go}\`"
  echo "- Docker \`GO_VERSION\`: \`${docker_go_version}\`"
  echo "- Cosmos SDK version: \`${cosmos_sdk_version}\`"
  echo "- CometBFT version: \`${cometbft_version}\`"
  echo "- Cosmos EVM version: \`${cosmos_evm_version}\`"
  echo "- Wasmd version: \`${wasmd_version}\`"
  echo "- wasmvm version: \`${wasmvm_version}\`"
  echo "- msgpack v2 version: \`${msgpack_v2_version}\`"
  echo "- \`go-ethereum\` required version: \`${go_ethereum_version}\`"
  echo "- \`cosmos/go-ethereum\` replacement: \`${cosmos_geth_replacement:-none}\`"
  echo "- \`wasmd\` replacement: \`${wasmd_replacement:-none}\`"
  echo "- \`wasmvm\` replacement: \`${wasmvm_replacement:-none}\`"
  echo
  echo "## Direct Dependencies"
  echo
  printf '%s\n' "${direct_dependencies:-"- none"}"
  echo
  echo "## Replace Directives"
  echo
  printf '%s\n' "${replace_directives:-"- none"}"
  echo
  echo "## Module Reachability"
  echo
  echo "### \`go mod why -m github.com/cosmos/evm\`"
  echo
  echo '```text'
  cat "$why_cosmos_evm"
  echo '```'
  echo
  echo "### \`go mod why -m github.com/CosmWasm/wasmd\`"
  echo
  echo '```text'
  cat "$why_wasmd"
  echo '```'
  echo
  echo "### \`go mod why -m github.com/CosmWasm/wasmvm/v3\`"
  echo
  echo '```text'
  cat "$why_wasmvm"
  echo '```'
  echo
  echo "### \`go mod why -m github.com/shamaton/msgpack/v2\`"
  echo
  echo '```text'
  cat "$why_msgpack_v2"
  echo '```'
  echo
  echo "### \`go mod why -m github.com/ethereum/go-ethereum\`"
  echo
  echo '```text'
  cat "$why_geth"
  echo '```'
  echo
  echo "### \`go mod why -m github.com/cosmos/go-ethereum\`"
  echo
  echo '```text'
  cat "$why_cosmos_geth"
  echo '```'
  echo
  echo "## Update Query"
  echo
  echo "- ${module_updates_note}"
  echo
  printf '%s\n' "$core_update_summary"
  echo
  echo "### \`go list -m -u -json all\` stderr"
  echo
  echo '```text'
  if [[ -s "$module_updates_err" ]]; then
    cat "$module_updates_err"
  else
    echo "none"
  fi
  echo '```'
} >"$REPORT_PATH"

echo "dependency-audit: PASS (${REPORT_PATH})"
