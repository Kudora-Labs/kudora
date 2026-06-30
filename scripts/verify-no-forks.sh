#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

GO_MOD_PATH="${KUDORA_GO_MOD_PATH:-go.mod}"
ALLOWED_COSMOS_EVM_VERSION="v0.7.0"
ALLOWED_GETH_REPLACEMENT="github.com/ethereum/go-ethereum => github.com/cosmos/go-ethereum v1.17.2-cosmos-0"

if [[ ! -f "$GO_MOD_PATH" ]]; then
  echo "verify-no-forks: go.mod not found at ${GO_MOD_PATH}" >&2
  exit 1
fi

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
matches_file="$tmp_dir/matches.txt"
errors_file="$tmp_dir/errors.txt"

fixed_patterns=(
  'strangelove-ventures'
  'github.com/evmos'
  'github.com/rollchains'
)

regex_patterns=(
  '^[[:space:]]*(replace[[:space:]]+)?github\.com/cosmos/cosmos-sdk[[:space:]]*=>'
  '^[[:space:]]*(replace[[:space:]]+)?github\.com/cosmos/evm[[:space:]]*=>'
  '^[[:space:]]*(replace[[:space:]]+)?github\.com/CosmWasm/wasmd[[:space:]]*=>'
  '^[[:space:]]*(replace[[:space:]]+)?github\.com/CosmWasm/wasmvm(?:/v[0-9]+)?[[:space:]]*=>'
)

touch "$matches_file"
for pattern in "${fixed_patterns[@]}"; do
  if rg -n --fixed-strings "$pattern" "$GO_MOD_PATH" >>"$matches_file"; then
    :
  fi
done

for pattern in "${regex_patterns[@]}"; do
  if rg -n "$pattern" "$GO_MOD_PATH" >>"$matches_file"; then
    :
  fi
done

if [[ -s "$matches_file" ]]; then
  echo "verify-no-forks: forbidden runtime forks or replacements found in go.mod" >&2
  sort -u "$matches_file" >&2
  echo "verify-no-forks: official github.com/CosmWasm/wasmd and github.com/CosmWasm/wasmvm dependencies are allowed only without replace directives" >&2
  echo "verify-no-forks: the only approved fork exception is github.com/ethereum/go-ethereum => github.com/cosmos/go-ethereum v1.17.2-cosmos-0 when github.com/cosmos/evm v0.7.0 is present" >&2
  exit 1
fi

cosmos_evm_version="$(
  awk '
    /^[[:space:]]*require[[:space:]]+github\.com\/cosmos\/evm[[:space:]]+v/ {
      print $3
      exit
    }
    /^[[:space:]]*github\.com\/cosmos\/evm[[:space:]]+v/ {
      print $2
      exit
    }
  ' "$GO_MOD_PATH"
)"

mapfile -t geth_replace_lines < <(
  awk '
    /github\.com\/ethereum\/go-ethereum[[:space:]]*=>/ {
      line = $0
      gsub(/^[[:space:]]*replace[[:space:]]+/, "", line)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
      gsub(/[[:space:]]+/, " ", line)
      print line
    }
  ' "$GO_MOD_PATH"
)

mapfile -t cosmos_geth_refs < <(
  awk '
    /github\.com\/cosmos\/go-ethereum/ {
      line = $0
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
      gsub(/[[:space:]]+/, " ", line)
      print line
    }
  ' "$GO_MOD_PATH"
)

if [[ -z "$cosmos_evm_version" ]]; then
  if (( ${#geth_replace_lines[@]} > 0 || ${#cosmos_geth_refs[@]} > 0 )); then
    {
      echo "verify-no-forks: github.com/cosmos/go-ethereum is forbidden unless github.com/cosmos/evm ${ALLOWED_COSMOS_EVM_VERSION} is present"
      printf 'cosmos/evm version detected: %s\n' "none"
      printf 'go-ethereum replacement lines:\n'
      printf ' - %s\n' "${geth_replace_lines[@]:-none}"
      printf 'cosmos/go-ethereum references:\n'
      printf ' - %s\n' "${cosmos_geth_refs[@]:-none}"
    } >"$errors_file"
    cat "$errors_file" >&2
    exit 1
  fi

  echo "verify-no-forks: PASS"
  exit 0
fi

if [[ "$cosmos_evm_version" != "$ALLOWED_COSMOS_EVM_VERSION" ]]; then
  if (( ${#geth_replace_lines[@]} > 0 || ${#cosmos_geth_refs[@]} > 0 )); then
    {
      echo "verify-no-forks: github.com/cosmos/go-ethereum is only approved with github.com/cosmos/evm ${ALLOWED_COSMOS_EVM_VERSION}"
      printf 'cosmos/evm version detected: %s\n' "$cosmos_evm_version"
      printf 'approved replacement: replace %s\n' "$ALLOWED_GETH_REPLACEMENT"
      printf 'go-ethereum replacement lines:\n'
      printf ' - %s\n' "${geth_replace_lines[@]:-none}"
      printf 'cosmos/go-ethereum references:\n'
      printf ' - %s\n' "${cosmos_geth_refs[@]:-none}"
    } >"$errors_file"
    cat "$errors_file" >&2
    exit 1
  fi

  echo "verify-no-forks: PASS"
  exit 0
fi

for line in "${geth_replace_lines[@]}"; do
  if [[ "$line" != "$ALLOWED_GETH_REPLACEMENT" ]]; then
    {
      echo "verify-no-forks: unsupported github.com/ethereum/go-ethereum replacement found"
      printf 'cosmos/evm version detected: %s\n' "$cosmos_evm_version"
      printf 'approved replacement: replace %s\n' "$ALLOWED_GETH_REPLACEMENT"
      printf 'found replacement: replace %s\n' "$line"
    } >"$errors_file"
    cat "$errors_file" >&2
    exit 1
  fi
done

for line in "${cosmos_geth_refs[@]}"; do
  if [[ "$line" != "$ALLOWED_GETH_REPLACEMENT" && "$line" != "replace $ALLOWED_GETH_REPLACEMENT" ]]; then
    {
      echo "verify-no-forks: unexpected github.com/cosmos/go-ethereum reference found"
      printf 'cosmos/evm version detected: %s\n' "$cosmos_evm_version"
      printf 'approved replacement: replace %s\n' "$ALLOWED_GETH_REPLACEMENT"
      printf 'found reference: %s\n' "$line"
    } >"$errors_file"
    cat "$errors_file" >&2
    exit 1
  fi
done

echo "verify-no-forks: PASS"
