#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

mkdir -p out

primary_archive_name="kudora-phase-17-candidate-release-cosmovisor.zip"
primary_archive_path="out/${primary_archive_name}"
latest_archive_name="kudora-latest-inspection.zip"
latest_archive_path="out/${latest_archive_name}"
compatibility_archives=(
  "kudora-phase-17-release-cosmovisor.zip"
  "kudora-phase-16.1-mainnet-genesis-finalization.zip"
  "kudora-phase-16-mainnet-genesis.zip"
  "kudora-phase-15-monitoring.zip"
  "kudora-phase-12-integrity-module.zip"
  "kudora-phase-13-localnet-docker.zip"
  "kudora-phase-14-explorers.zip"
  "kudora-phase-5-cosmwasm-runtime.zip"
  "kudora-phase-0-reset.zip"
)
tmp_dir="$(mktemp -d "/tmp/${primary_archive_name%.zip}.XXXXXX")"
tmp_archive="${tmp_dir}/${primary_archive_name}"
trap 'rm -rf "$tmp_dir"' EXIT

rm -f "$primary_archive_path"
rm -f "$latest_archive_path"
for archive_name in "${compatibility_archives[@]}"; do
  rm -f "out/${archive_name}"
done

zip -qr "$tmp_archive" . \
  -x '.git/*' \
  -x '.kudora/*' \
  -x '.testnets/*' \
  -x '.localnet/*' \
  -x 'build/*' \
  -x 'dist/*' \
  -x 'tmp/*' \
  -x 'release/temp/*' \
  -x 'deploy/localnet/state/*' \
  -x 'deploy/explorers/**/.env' \
  -x 'deploy/explorers/**/data/*' \
  -x 'deploy/explorers/**/db/*' \
  -x 'deploy/explorers/**/postgres/*' \
  -x 'deploy/explorers/**/redis/*' \
  -x 'deploy/monitoring/**/.env' \
  -x 'deploy/monitoring/**/data/*' \
  -x 'deploy/monitoring/**/prometheus-data/*' \
  -x 'deploy/monitoring/**/grafana-data/*' \
  -x 'deploy/cosmovisor/**/.env' \
  -x 'out/release/*.tar.gz' \
  -x 'out/release/*.zip' \
  -x 'out/release/*/linux-amd64/kudorad' \
  -x 'out/release/*/linux-amd64/lib/*' \
  -x '*.log' \
  -x '.DS_Store' \
  -x '*/.DS_Store' \
  -x '__MACOSX/*' \
  -x '.env' \
  -x '.env.*' \
  -x 'priv_validator_key.json' \
  -x 'node_key.json' \
  -x 'key_seed.json' \
  -x '*.pem' \
  -x '*.key' \
  -x '*.seed' \
  -x '*.mnemonic' \
  -x '*.zip' \
  -x 'out/*.zip'

zip_listing="$(unzip -Z1 "$tmp_archive")"
for forbidden_pattern in \
  '^\.git/' \
  '^\.kudora/' \
  '^\.testnets/' \
  '^\.localnet/' \
  '^build/' \
  '^dist/' \
  '^tmp/' \
  '^release/temp/' \
  '^deploy/localnet/state/' \
  '^deploy/explorers/.*/\.env$' \
  '^deploy/explorers/.*/data/' \
  '^deploy/explorers/.*/db/' \
  '^deploy/explorers/.*/postgres/' \
  '^deploy/explorers/.*/redis/' \
  '^deploy/monitoring/.*/\.env$' \
  '^deploy/monitoring/.*/data/' \
  '^deploy/monitoring/.*/prometheus-data/' \
  '^deploy/monitoring/.*/grafana-data/' \
  '^deploy/cosmovisor/.*/\.env$' \
  '^out/release/.*\.tar\.gz$' \
  '^out/release/.*\.zip$' \
  '^out/release/.*/linux-amd64/kudorad$' \
  '^out/release/.*/linux-amd64/lib/' \
  '(^|/)\.env(\..*)?$' \
  '(^|/)priv_validator_key\.json$' \
  '(^|/)node_key\.json$' \
  '(^|/)key_seed\.json$' \
  '\.pem$' \
  '\.key$' \
  '\.seed$' \
  '\.mnemonic$' \
  '\.zip$' \
  '(^|/)__MACOSX/' \
  '(^|/)\.DS_Store$'
do
  if printf '%s\n' "$zip_listing" | rg -n "$forbidden_pattern" >/dev/null; then
    echo "make-zip: forbidden content found in archive for pattern $forbidden_pattern" >&2
    exit 1
  fi
done

mv "$tmp_archive" "$primary_archive_path"
cp "$primary_archive_path" "$latest_archive_path"
for archive_name in "${compatibility_archives[@]}"; do
  cp "$primary_archive_path" "out/${archive_name}"
done

echo "make-zip: PASS (${primary_archive_path}; latest inspection copy at ${latest_archive_path})"
