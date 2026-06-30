#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

OUT_DIR="out"
REPORT_PATH="${OUT_DIR}/phase-2-validation.md"
EXPECTED_BRANCH="Upgrade"
COSMOS_EVM_TAG="v0.7.0"
COSMOS_EVM_COMMIT="f4ab9a3e3fbe353468327d5cacda94b33b41ed11"
CHOSEN_PATH="Use upstream cosmos/evm evmd as the future integration reference. Phase 2.1 approves a narrow exception for github.com/ethereum/go-ethereum => github.com/cosmos/go-ethereum v1.17.2-cosmos-0 only when required by official github.com/cosmos/evm v0.7.0. EVM runtime is still not wired."
COMPATIBILITY_SUMMARY="Phase 3 is unblocked only under the approved narrow cosmos/go-ethereum exception. Kudora still requires major Cosmos SDK and CometBFT alignment, and EVM runtime remains inactive."

mkdir -p "$OUT_DIR"

branch_name="$(git branch --show-current)"
if [[ "$branch_name" != "$EXPECTED_BRANCH" ]]; then
  echo "phase-2-validate: expected branch ${EXPECTED_BRANCH}, found ${branch_name}" >&2
  exit 1
fi

starting_commit="$(git rev-parse HEAD)"
head_before_report="$(git rev-parse HEAD)"
working_tree_status_before="$(git status --short)"
generated_at="$(date -u '+%Y-%m-%d %H:%M:%S UTC')"
go_version="$(go version)"
ignite_version="$(ignite version 2>&1 | tr -d '\r')"
docker_version="$(docker version 2>&1)"

commands=(
  "make phase-1-validate"
  "make tidy"
  "make build"
  "make test"
  "make lint"
  "make verify-no-forks"
  "make verify-clean-reset"
  "make verify-no-secrets"
  "make docker-build"
  "make docker-smoke-test"
  "make zip"
)

results=()

run_check() {
  local label="$1"
  shift
  "$@"
  results+=("PASS|${label}")
}

check_phase2_docs() {
  local required_files=(
    "docs/evm/phase-2-official-evm-path.md"
    "docs/evm/phase-2-evm-compatibility-matrix.md"
    "docs/evm/phase-2-evm-integration-design.md"
  )
  local path

  for path in "${required_files[@]}"; do
    if [[ ! -f "$path" ]]; then
      echo "phase-2-validate: required Phase 2 document missing: $path" >&2
      return 1
    fi
  done
}

check_tmp_repos_not_tracked() {
  local tracked_tmp

  tracked_tmp="$(git ls-files tmp/cosmos-evm tmp/ignite-apps)"
  if [[ -n "$tracked_tmp" ]]; then
    echo "phase-2-validate: temporary upstream repositories must not be tracked" >&2
    printf '%s\n' "$tracked_tmp" >&2
    return 1
  fi
}

check_no_evm_wiring() {
  local forbidden_paths=(
    "x/vm"
    "x/feemarket"
    "x/erc20"
    "proto/cosmos/evm"
    "proto/evm"
    "app/evm.go"
    "app/mempool.go"
    "app/precompiles.go"
    "app/token_pair.go"
  )
  local path tracked

  tracked="$(git ls-files)"
  for path in "${forbidden_paths[@]}"; do
    if printf '%s\n' "$tracked" | rg -x "$path|$path/.+" >/dev/null; then
      echo "phase-2-validate: forbidden EVM wiring path present: $path" >&2
      return 1
    fi
  done

  if rg -n 'github.com/(cosmos/evm|ethereum/go-ethereum)' app cmd proto testutil go.mod go.sum config.yml >/dev/null; then
    echo "phase-2-validate: EVM runtime imports or dependencies were added to Kudora" >&2
    rg -n 'github.com/(cosmos/evm|ethereum/go-ethereum)' app cmd proto testutil go.mod go.sum config.yml >&2
    return 1
  fi
}

check_no_evm_ports() {
  if rg -n '\b8545\b|\b8546\b' Dockerfile >/dev/null; then
    echo "phase-2-validate: Dockerfile must not expose EVM JSON-RPC ports before EVM integration" >&2
    return 1
  fi
}

run_check "make phase-1-validate" make phase-1-validate
run_check "make tidy" make tidy
run_check "make build" make build
run_check "make test" make test
run_check "make lint" make lint
run_check "make verify-no-forks" make verify-no-forks
run_check "make verify-clean-reset" make verify-clean-reset
run_check "make verify-no-secrets" make verify-no-secrets
run_check "Phase 2 docs exist" check_phase2_docs
run_check "temporary upstream repos are not tracked" check_tmp_repos_not_tracked
run_check "no EVM runtime wiring present" check_no_evm_wiring
run_check "no EVM Docker ports exposed" check_no_evm_ports
run_check "make docker-build" make docker-build
run_check "make docker-smoke-test" make docker-smoke-test
run_check "make zip" make zip

{
  echo "# Phase 2 Validation Report"
  echo
  echo "- Validation generated at: ${generated_at}"
  echo "- Branch: ${branch_name}"
  echo "- Starting commit: ${starting_commit}"
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
  echo "- Cosmos EVM upstream version/tag inspected: \`${COSMOS_EVM_TAG}\`"
  echo "- Cosmos EVM upstream commit inspected: \`${COSMOS_EVM_COMMIT}\`"
  echo
  echo '```text'
  echo "${go_version}"
  echo
  echo "${ignite_version}"
  echo
  echo "${docker_version}"
  echo '```'
  echo
  echo "## Chosen Path"
  echo
  echo "- ${CHOSEN_PATH}"
  echo "- Compatibility summary: ${COMPATIBILITY_SUMMARY}"
  echo
  echo "## Validation Commands"
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
  echo "## Confirmations"
  echo
  echo "- No secrets were detected in the working tree."
  echo "- No forbidden runtime forks were found in Kudora's \`go.mod\`."
  echo "- No EVM runtime modules or wiring were added to Kudora in Phase 2."
  echo "- No Docker registry push was performed."
  echo "- No committed \`tmp/cosmos-evm\` or \`tmp/ignite-apps\` directory exists."
  echo "- Latest local archive path remains \`out/kudora-phase-0-reset.zip\`."
  echo "- Note: the final pushed commit may differ if this report is committed afterward."
} >"$REPORT_PATH"

echo "phase-2-validate: PASS (${REPORT_PATH})"
