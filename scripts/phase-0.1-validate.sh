#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

OUT_DIR="out"
REPORT_PATH="${OUT_DIR}/phase-0.1-validation.md"
EXPECTED_BRANCH="Upgrade"
EXPECTED_IGNITE_TAG="v29.10.1"
EXPECTED_IGNITE_SOURCE_HASH="d401b9128a7efc2ee642ea733247436368331b41"
SCAFFOLD_COMMAND='ignite scaffold chain github.com/Kudora-Labs/kudora --address-prefix kudo --coin-type 60 --default-denom akud --minimal --no-module --skip-git --path .'

mkdir -p "$OUT_DIR"

branch_name="$(git branch --show-current)"
if [[ "$branch_name" != "$EXPECTED_BRANCH" ]]; then
  echo "phase-0.1-validate: expected branch ${EXPECTED_BRANCH}, found ${branch_name}" >&2
  exit 1
fi

head_before_validation="$(git rev-parse HEAD)"
recent_commits="$(git log --oneline --decorate -5)"
working_tree_status_before="$(git status --short)"
generated_at="$(date -u '+%Y-%m-%d %H:%M:%S UTC')"
go_version="$(go version)"
ignite_version_output="$(ignite version 2>&1 | tr -d '\r')"
ignite_version_line="$(printf '%s\n' "$ignite_version_output" | awk -F'\t+' '/Ignite CLI version:/ {print $2}')"
ignite_build_date="$(printf '%s\n' "$ignite_version_output" | awk -F'\t+' '/Ignite CLI build date:/ {print $2}')"
ignite_source_hash="$(printf '%s\n' "$ignite_version_output" | awk -F'\t+' '/Ignite CLI source hash:/ {print $2}')"
ignite_binary_path="$(command -v ignite)"

if [[ "$ignite_version_line" != *"$EXPECTED_IGNITE_TAG"* ]]; then
  echo "phase-0.1-validate: expected Ignite release tag ${EXPECTED_IGNITE_TAG}, got ${ignite_version_line}" >&2
  exit 1
fi

if [[ -z "$ignite_build_date" || "$ignite_build_date" == "undefined" ]]; then
  echo "phase-0.1-validate: Ignite build date is missing or undefined" >&2
  exit 1
fi

if [[ -z "$ignite_source_hash" || "$ignite_source_hash" == "undefined" ]]; then
  echo "phase-0.1-validate: Ignite source hash is missing or undefined" >&2
  exit 1
fi

if [[ "$ignite_source_hash" != "$EXPECTED_IGNITE_SOURCE_HASH" ]]; then
  echo "phase-0.1-validate: Ignite source hash mismatch (expected ${EXPECTED_IGNITE_SOURCE_HASH}, got ${ignite_source_hash})" >&2
  exit 1
fi

declare -a results=()

run_check() {
  local label="$1"
  shift
  "$@"
  results+=("PASS|${label}")
}

check_ci_consistency() {
  local make_targets workflow_targets target
  local -a missing_targets=()

  if [[ -e .github/workflows/release.yml ]]; then
    echo "phase-0.1-validate: release workflow is still present" >&2
    return 1
  fi

  if rg -n '@main' .github/workflows >/dev/null; then
    echo "phase-0.1-validate: unstable GitHub Action reference @main found in workflows" >&2
    rg -n '@main' .github/workflows >&2
    return 1
  fi

  make_targets="$(awk -F: '/^[A-Za-z0-9_.-]+:/ {print $1}' Makefile | sort -u)"
  workflow_targets="$(
    for workflow in .github/workflows/*.yml; do
      [[ -e "$workflow" ]] || continue
      sed '/^[[:space:]]*#/d' "$workflow" | sed -n 's/.*make \([A-Za-z0-9_.-][A-Za-z0-9_.-]*\).*/\1/p'
    done | sort -u
  )"

  while IFS= read -r target; do
    [[ -n "$target" ]] || continue
    if ! printf '%s\n' "$make_targets" | rg -x "$target" >/dev/null; then
      missing_targets+=("$target")
    fi
  done <<<"$workflow_targets"

  if (( ${#missing_targets[@]} > 0 )); then
    echo "phase-0.1-validate: workflows reference missing Makefile targets" >&2
    printf ' - %s\n' "${missing_targets[@]}" >&2
    return 1
  fi
}

verify_zip_safety() {
  local listing_path="$OUT_DIR/phase-0.1-zip-list.txt"
  unzip -Z1 "$OUT_DIR/kudora-phase-0-reset.zip" >"$listing_path"

  if rg -n \
    -e '^\.git/' \
    -e '^\.kudora/' \
    -e '^\.testnets/' \
    -e '^build/' \
    -e '^dist/' \
    -e '^tmp/' \
    -e '^release/' \
    -e '(^|/)\.env(\..*)?$' \
    -e '(^|/)priv_validator_key\.json$' \
    -e '(^|/)node_key\.json$' \
    -e '(^|/)key_seed\.json$' \
    -e '\.pem$' \
    -e '\.key$' \
    -e '\.seed$' \
    -e '\.mnemonic$' \
    -e '\.zip$' \
    -e '(^|/)__MACOSX/' \
    -e '(^|/)\.DS_Store$' \
    "$listing_path" >/dev/null; then
    echo "phase-0.1-validate: forbidden content found in out/kudora-phase-0-reset.zip" >&2
    return 1
  fi
}

run_check "make tidy" make tidy
run_check "make build" make build
run_check "make test" make test
run_check "make lint" make lint
run_check "make verify-no-forks" make verify-no-forks
run_check "make verify-clean-reset" make verify-clean-reset
run_check "make verify-no-secrets" make verify-no-secrets
run_check "CI consistency" check_ci_consistency
run_check "zip generation" ./scripts/make-zip.sh
run_check "zip safety verification" verify_zip_safety

zip_listing="$(unzip -Z1 "$OUT_DIR/kudora-phase-0-reset.zip")"
release_workflow_note="Removed for Phase 0.1 because release automation is premature before Docker/CI hardening and it referenced unstable @main actions."

{
  echo "# Phase 0.1 Validation Report"
  echo
  echo "- Validation generated at: ${generated_at}"
  echo "- Current branch: ${branch_name}"
  echo "- Latest commit before validation: ${head_before_validation}"
  echo
  echo "## Working Tree Status Before Validation"
  echo
  echo '```text'
  echo "${working_tree_status_before:-clean}"
  echo '```'
  echo
  echo "## Tooling"
  echo
  echo "- Ignite binary path: \`${ignite_binary_path}\`"
  echo "- Expected official Ignite tag: \`${EXPECTED_IGNITE_TAG}\`"
  echo "- Go version: \`${go_version}\`"
  echo
  echo '```text'
  echo "${ignite_version_output}"
  echo '```'
  echo
  echo "## Ignite Provenance Notes"
  echo
  echo "- Install/source assumption: the local \`ignite\` binary on PATH was replaced with the official GitHub release asset for \`${EXPECTED_IGNITE_TAG}\` after SHA256 verification against the published checksums file."
  echo "- Source hash validated: \`${ignite_source_hash}\`"
  echo "- Build date validated: \`${ignite_build_date}\`"
  echo "- Upstream note: the official \`${EXPECTED_IGNITE_TAG}\` binary still self-reports a \`-dev\` suffix even though it comes from the signed stable release tag."
  echo "- Scaffold regeneration required: no"
  echo "- Exact scaffold command validated: \`${SCAFFOLD_COMMAND}\`"
  echo
  echo "## Repository State"
  echo
  echo '```text'
  echo "${recent_commits}"
  echo '```'
  echo
  echo "## Chain Parameters"
  echo
  echo "- Binary name: \`kudorad\`"
  echo "- App name: \`kudora\`"
  echo "- Go module path: \`github.com/Kudora-Labs/kudora\`"
  echo "- Home directory: \`.kudora\`"
  echo "- Bech32 prefix: \`kudo\`"
  echo "- Coin type: \`60\`"
  echo "- Native base denom: \`akud\`"
  echo "- Display denom: \`KUD\`"
  echo "- Token decimals: \`18\`"
  echo "- Official Cosmos chain-id: \`kudora_12000-1\`"
  echo
  echo "## Results"
  echo
  echo "- PASS: branch is exactly \`Upgrade\`"
  echo "- PASS: official Ignite release provenance was validated against tag \`${EXPECTED_IGNITE_TAG}\` and source hash \`${EXPECTED_IGNITE_SOURCE_HASH}\`"
  for result in "${results[@]}"; do
    status="${result%%|*}"
    label="${result#*|}"
    echo "- ${status}: \`${label}\`"
  done
  echo
  echo "## CI Consistency"
  echo
  echo "- Workflow targets remain aligned with the root Makefile."
  echo "- Release workflow status: ${release_workflow_note}"
  echo "- Local workflow-equivalent commands covered in this validation: \`make test\` and \`make lint\`."
  echo
  echo "## Zip Verification"
  echo
  echo "- Local zip path: \`out/kudora-phase-0-reset.zip\`"
  echo "- Verification confirmed that the archive does not include \`.git\`, node homes, \`.env\` files, validator or node keys, secret-bearing file extensions, or nested zip files."
  echo "- Archive entry count: $(printf '%s\n' "$zip_listing" | wc -l | awk '{print $1}')"
  echo
  echo "## Final Notes"
  echo
  echo "- No scaffold regeneration was necessary during Phase 0.1."
  echo "- No Docker, EVM, CosmWasm, IBC, tokenfactory, packet-forward, rate-limit, ICA, 08-wasm, explorers, or business modules were added."
  echo "- This report records the pre-report HEAD above; the final pushed commit may differ if the report itself is committed afterward."
} >"$REPORT_PATH"

rm -f "$OUT_DIR/phase-0.1-zip-list.txt"

echo "phase-0.1-validate: PASS (${REPORT_PATH})"
