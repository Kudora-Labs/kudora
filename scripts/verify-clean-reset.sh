#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
tracked_files="$tmp_dir/tracked-files.txt"
matches_file="$tmp_dir/matches.txt"

git ls-files --cached --others --exclude-standard >"$tracked_files"
declare -a tracked_paths=()
declare -a content_targets=()

while IFS= read -r path; do
  [[ -e "$path" ]] || continue
  tracked_paths+=("$path")
done <"$tracked_files"

legacy_paths=(
  ".localnet"
  "tmp/mainnet-genesis"
  "tmp/phase-17-cosmovisor"
  "tmp/phase-17-release"
  "chain_metadata.json"
  "chain_registry.json"
  "chain_registry_assets.json"
  "chains"
  "chains.yaml"
  "contrib"
  "interchaintest"
  "kudora"
  "make"
  "scripts/protocgen.sh"
  "scripts/test_node.sh"
  "x/escrow"
  "x/project"
  "x/reputation"
  "x/task"
  "app/modules"
  "app/wasm.go"
  "deploy/localnet/state"
  "release/temp"
)

for legacy_path in "${legacy_paths[@]}"; do
  for path in "${tracked_paths[@]}"; do
    case "$path" in
      "$legacy_path"|"$legacy_path"/*)
        echo "verify-clean-reset: legacy artifact still present at $legacy_path" >&2
        exit 1
        ;;
    esac
  done
done

for path in "${tracked_paths[@]}"; do
  case "$path" in
    proto/kudora/integrity|proto/kudora/integrity/*|x/integrity|x/integrity/*)
      ;;
    proto/kudora|proto/kudora/*)
      echo "verify-clean-reset: unsupported custom proto namespace present at ${path}; only proto/kudora/integrity is allowed in Phase 12" >&2
      exit 1
      ;;
  esac
done

for path in "${tracked_paths[@]}"; do
  case "$path" in
    README.md|docs/*.md|out/*.md|scripts/verify-clean-reset.sh|scripts/verify-no-forks.sh|scripts/verify-no-secrets.sh|scripts/verify-integrity-generic.sh|scripts/phase-*.sh|scripts/evm-smoke-test.sh|scripts/integrity-smoke-test.sh|scripts/make-zip.sh)
      ;;
    *)
      content_targets+=("$path")
      ;;
  esac
done

patterns=(
  'kudora_12000-2'
  'strangelove-ventures'
  'rollchains'
  'evmos/go-ethereum'
  'evmos/cosmos-sdk'
  'github.com/evmos'
  'kud-network-mainnet pinned setup'
  'old mainnet genesis'
  'legacy seeds/peers lists'
  'legacy network repository'
)

touch "$matches_file"
for pattern in "${patterns[@]}"; do
  if (( ${#content_targets[@]} > 0 )) && rg -n --fixed-strings "$pattern" "${content_targets[@]}" >>"$matches_file"; then
    :
  fi
done

if [[ -s "$matches_file" ]]; then
  echo "verify-clean-reset: forbidden legacy patterns found in the working tree" >&2
  sort -u "$matches_file" >&2
  exit 1
fi

echo "verify-clean-reset: PASS"
