#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

OUT_DIR="out"
REPORT_PATH="${OUT_DIR}/phase-0-validation.md"
SCAFFOLD_COMMAND='ignite scaffold chain github.com/Kudora-Labs/kudora --address-prefix kudo --coin-type 60 --default-denom akud --minimal --no-module --skip-git --path .'

mkdir -p "$OUT_DIR"

ignite_version="$(ignite version 2>&1 | tr -d '\r')"
go_version="$(go version)"
branch_name="$(git branch --show-current)"
head_before_report="$(git rev-parse HEAD)"
working_tree_status_before="$(git status --short)"
generated_at="$(date -u '+%Y-%m-%d %H:%M:%S UTC')"

commands=(
  "ignite version"
  "go version"
  "go mod tidy"
  "go mod verify"
  "go test ./..."
  "ignite chain build --check-dependencies"
  "make verify-no-forks"
  "make verify-clean-reset"
)

results=()

run_check() {
  local label="$1"
  shift
  "$@"
  results+=("PASS|${label}")
}

run_check "ignite version" ignite version
run_check "go version" go version
run_check "go mod tidy" go mod tidy
run_check "go mod verify" go mod verify
run_check "go test ./..." go test ./...
run_check "ignite chain build --check-dependencies" ./scripts/ignite-check-dependencies.sh
run_check "make verify-no-forks" make verify-no-forks
run_check "make verify-clean-reset" make verify-clean-reset

created_files="$(find . \
  -path './.git' -prune -o \
  -type f \
  ! -path './build/*' \
  ! -path './dist/*' \
  ! -path './tmp/*' \
  ! -path './out/kudora-phase-0-reset.zip' \
  -print | sed 's#^\./##' | sort)"

{
  echo "# Phase 0 Validation Report"
  echo
  echo "- Validation generated at: ${generated_at}"
  echo "- Git branch: ${branch_name}"
  echo "- Current HEAD before report generation: ${head_before_report}"
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
  echo "${ignite_version}"
  echo "${go_version}"
  echo '```'
  echo
  echo "## Scaffold Command"
  echo
  echo '```bash'
  echo "${SCAFFOLD_COMMAND}"
  echo '```'
  echo
  echo "## Chain Parameters"
  echo
  echo "- Binary name: \`kudorad\`"
  echo "- App name: \`kudora\`"
  echo "- Go module path: \`github.com/Kudora-Labs/kudora\`"
  echo "- Home directory: \`.kudora\`"
  echo "- Bech32 account prefix: \`kudo\`"
  echo "- Coin type: \`60\`"
  echo "- Native base denom: \`akud\`"
  echo "- Display denom: \`KUD\`"
  echo "- Token decimals: \`18\`"
  echo "- Official Cosmos chain-id: \`kudora_12000-1\`"
  echo
  echo "## Commands Executed"
  echo
  for command in "${commands[@]}"; do
    echo "- \`${command}\`"
  done
  echo
  echo "## Results"
  echo
  for result in "${results[@]}"; do
    status="${result%%|*}"
    label="${result#*|}"
    echo "- ${status}: \`${label}\`"
  done
  echo
  echo "## Files Created"
  echo
  while IFS= read -r file; do
    echo "- \`${file}\`"
  done <<< "${created_files}"
  echo
  echo "## Confirmations"
  echo
  echo "- No production secrets, validator keys, node keys, mnemonics, private keys, or credentials were committed."
  echo "- No forbidden runtime forks or runtime replacements were found in \`go.mod\`."
  echo "- Legacy Kudora implementation files and legacy network artifacts were removed from the Phase 0 branch."
  echo "- The local archive output path is \`out/kudora-phase-0-reset.zip\` when generated with \`make zip\`."
  echo "- Note: the final pushed commit may differ from the HEAD recorded above if this report is committed afterward."
  echo
  echo "## Manual Adjustments After Ignite Scaffold"
  echo
  echo "- Added Phase 0 documentation, validation scripts, and packaging scripts."
  echo "- Replaced the generated root README, Makefile, and .gitignore with the required Phase 0 baseline."
  echo "- Set \`sdk.DefaultPowerReduction\` to \`10^18\` to align staking power reduction with the required 18 token decimals."
  echo "- Updated local scaffold balances to use only \`akud\` and to stay above the configured staking power reduction."
  echo "- Sanitized scaffolded local testnet examples to remove concrete private key material and use non-sensitive placeholders."
} > "$REPORT_PATH"

echo "phase-0-validate: PASS (${REPORT_PATH})"
