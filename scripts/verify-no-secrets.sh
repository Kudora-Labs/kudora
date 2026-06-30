#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

tracked_files="$tmp_dir/tracked-files.txt"
path_matches="$tmp_dir/path-matches.txt"
content_matches="$tmp_dir/content-matches.txt"

git ls-files --cached --others --exclude-standard -z >"$tracked_files"
declare -a scan_targets=()

if command -v gitleaks >/dev/null 2>&1; then
  if gitleaks dir --help >/dev/null 2>&1; then
    if ! gitleaks dir . --no-banner --redact --report-format json --report-path "$tmp_dir/gitleaks.json" >/dev/null 2>&1; then
      echo "verify-no-secrets: gitleaks detected potential secrets" >&2
      exit 1
    fi
  else
    if ! gitleaks detect --no-banner --redact --source . --report-format json --report-path "$tmp_dir/gitleaks.json" >/dev/null 2>&1; then
      echo "verify-no-secrets: gitleaks detected potential secrets" >&2
      exit 1
    fi
  fi

  echo "verify-no-secrets: PASS (gitleaks)"
  exit 0
fi

while IFS= read -r -d '' path; do
  [[ -e "$path" ]] || continue
  case "$path" in
    .env.example|*/.env.example|*.env.example|*/*.env.example)
      ;;
    .localnet|.localnet/*|tmp/mainnet-genesis|tmp/mainnet-genesis/*|tmp/phase-17-*|tmp/phase-17-*/*|release/temp|release/temp/*)
      printf '%s\n' "$path" >>"$path_matches"
      ;;
    .env|*/.env|.env.*|*/.env.*|deploy/cosmovisor/.env|deploy/cosmovisor/*/.env|*/cosmovisor/.env)
      printf '%s\n' "$path" >>"$path_matches"
      ;;
    priv_validator_key.json|*/priv_validator_key.json|node_key.json|*/node_key.json|key_seed.json|*/key_seed.json|*.pem|*.key|*.seed|*.mnemonic|.docker/config.json|*/.docker/config.json|docker-config.json|registry-auth.json|cosign.key|*.cosign.key|signing.key|*.sigstore.key)
      printf '%s\n' "$path" >>"$path_matches"
      ;;
    scripts/verify-no-secrets.sh|scripts/mainnet/inspect-genesis-policy.sh|release/manifest.json|release/checksums.sha256|release/README.md|release/docker/README.md|release/cosmovisor/README.md|docs/release/phase-17-candidate-release-cosmovisor.md|deploy/cosmovisor/env/cosmovisor.env.example|out/phase-0-validation.md|out/phase-0.1-validation.md)
      ;;
    *)
      scan_targets+=("$path")
      ;;
  esac
done <"$tracked_files"

if [[ -s "$path_matches" ]]; then
  echo "verify-no-secrets: suspicious secret-bearing files found in the working tree" >&2
  sort -u "$path_matches" >&2
  exit 1
fi

if (( ${#scan_targets[@]} > 0 )); then
  set +e
  rg --pcre2 --files-with-matches --no-messages \
    -e '-----BEGIN (?:OPENSSH|RSA|EC|DSA|PGP|[A-Z ]*PRIVATE KEY)-----' \
    -e 'PRIVATE KEY-----' \
    -e 'github_pat_[A-Za-z0-9_]{40,}' \
    -e 'gh[pousr]_[A-Za-z0-9_]{36,255}' \
    -e 'AKIA[0-9A-Z]{16}' \
    -e 'ASIA[0-9A-Z]{16}' \
    -e '"auths"\s*:\s*\{' \
    -e '(?i)docker[_ -]?registry[_ -]?(password|token)' \
    -e '(?i)cosign[_ -]?(private|password|key)' \
    -e '(?i)\b(?:mnemonic|seed(?:[_ -]?phrase)?)\b\s*[:=]\s*["'"'"'`][a-z]+(?: [a-z]+){11,23}["'"'"'`]' \
    "${scan_targets[@]}" >"$content_matches"
  rg_exit=$?
  set -e

  if (( rg_exit > 1 )); then
    echo "verify-no-secrets: content scan failed" >&2
    exit "$rg_exit"
  fi

  if [[ -s "$content_matches" ]]; then
    echo "verify-no-secrets: potential secret content found in tracked or unignored files" >&2
    sort -u "$content_matches" >&2
    exit 1
  fi
fi

echo "verify-no-secrets: PASS (regex fallback; gitleaks unavailable)"
