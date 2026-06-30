#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

OUT_DIR="out"
REPORT_PATH="${OUT_DIR}/phase-2.1-validation.md"
EXPECTED_BRANCH="Upgrade"
COSMOS_EVM_TAG="v0.7.0"
COSMOS_EVM_COMMIT="f4ab9a3e3fbe353468327d5cacda94b33b41ed11"
IGNITE_APPS_COMMIT="56b3cdb880535b697a8d368789b83241501dfd40"
APPROVED_POLICY_DECISION="Narrow Cosmos EVM go-ethereum exception approved"
APPROVED_EXCEPTION_VERSION="github.com/ethereum/go-ethereum => github.com/cosmos/go-ethereum v1.17.2-cosmos-0"
PHASE3_STATUS="Phase 3 is unblocked only under the approved narrow exception for cosmos/go-ethereum; EVM runtime remains inactive."

mkdir -p "$OUT_DIR"

branch_name="$(git branch --show-current)"
if [[ "$branch_name" != "$EXPECTED_BRANCH" ]]; then
  echo "phase-2.1-validate: expected branch ${EXPECTED_BRANCH}, found ${branch_name}" >&2
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
  "make phase-2-validate"
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

check_phase21_docs() {
  local required_files=(
    "docs/evm/phase-2.1-evm-dependency-policy.md"
    "docs/evm/phase-2-official-evm-path.md"
    "docs/evm/phase-2-evm-compatibility-matrix.md"
    "docs/evm/phase-2-evm-integration-design.md"
  )
  local path

  for path in "${required_files[@]}"; do
    if [[ ! -f "$path" ]]; then
      echo "phase-2.1-validate: required document missing: $path" >&2
      return 1
    fi
  done
}

check_policy_decision() {
  if ! rg -n --fixed-strings "Decision: ${APPROVED_POLICY_DECISION}." docs/evm/phase-2.1-evm-dependency-policy.md >/dev/null; then
    echo "phase-2.1-validate: policy decision is missing or ambiguous" >&2
    return 1
  fi

  if ! rg -n --fixed-strings "$APPROVED_EXCEPTION_VERSION" docs/evm/phase-2.1-evm-dependency-policy.md >/dev/null; then
    echo "phase-2.1-validate: approved exception version is missing from the policy document" >&2
    return 1
  fi
}

check_tmp_repos_not_tracked() {
  local tracked_tmp

  tracked_tmp="$(git ls-files tmp/cosmos-evm tmp/ignite-apps)"
  if [[ -n "$tracked_tmp" ]]; then
    echo "phase-2.1-validate: temporary upstream repositories must not be tracked" >&2
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
      echo "phase-2.1-validate: forbidden EVM wiring path present: $path" >&2
      return 1
    fi
  done

  if rg -n 'github.com/(cosmos/evm|ethereum/go-ethereum|cosmos/go-ethereum)' app cmd proto testutil >/dev/null; then
    echo "phase-2.1-validate: EVM runtime imports were added to Kudora source" >&2
    rg -n 'github.com/(cosmos/evm|ethereum/go-ethereum|cosmos/go-ethereum)' app cmd proto testutil >&2
    return 1
  fi
}

check_no_evm_ports() {
  if rg -n '\b8545\b|\b8546\b' Dockerfile docs/docker scripts Makefile >/dev/null; then
    echo "phase-2.1-validate: EVM JSON-RPC ports must not be exposed in Phase 2.1" >&2
    return 1
  fi
}

check_current_go_mod_has_no_evm_deps() {
  if rg -n '^\s*github\.com/cosmos/evm\s+v' go.mod >/dev/null; then
    echo "phase-2.1-validate: github.com/cosmos/evm must not be added to Kudora go.mod in Phase 2.1" >&2
    return 1
  fi

  if rg -n 'github\.com/cosmos/go-ethereum|github\.com/ethereum/go-ethereum[[:space:]]*=>' go.mod >/dev/null; then
    echo "phase-2.1-validate: github.com/cosmos/go-ethereum must not be added to Kudora go.mod in Phase 2.1" >&2
    return 1
  fi
}

check_verify_no_forks_policy() {
  if ! rg -n --fixed-strings 'ALLOWED_COSMOS_EVM_VERSION="v0.7.0"' scripts/verify-no-forks.sh >/dev/null; then
    echo "phase-2.1-validate: verify-no-forks.sh does not pin the approved Cosmos EVM version" >&2
    return 1
  fi

  if ! rg -n --fixed-strings 'ALLOWED_GETH_REPLACEMENT="github.com/ethereum/go-ethereum => github.com/cosmos/go-ethereum v1.17.2-cosmos-0"' scripts/verify-no-forks.sh >/dev/null; then
    echo "phase-2.1-validate: verify-no-forks.sh does not pin the approved go-ethereum exception" >&2
    return 1
  fi
}

check_verify_no_forks_behavior() {
  local test_dir
  test_dir="$(mktemp -d)"

  cat >"${test_dir}/repo-current.go.mod" <<'EOF'
module example.com/current

go 1.25.10
EOF
  KUDORA_GO_MOD_PATH="${test_dir}/repo-current.go.mod" ./scripts/verify-no-forks.sh >/dev/null

  cat >"${test_dir}/no-cosmos-evm-with-replace.go.mod" <<'EOF'
module example.com/forbidden

go 1.25.10

replace github.com/ethereum/go-ethereum => github.com/cosmos/go-ethereum v1.17.2-cosmos-0
EOF
  if KUDORA_GO_MOD_PATH="${test_dir}/no-cosmos-evm-with-replace.go.mod" ./scripts/verify-no-forks.sh >/dev/null 2>&1; then
    echo "phase-2.1-validate: verify-no-forks.sh accepted a go-ethereum replacement without github.com/cosmos/evm" >&2
    rm -rf "$test_dir"
    return 1
  fi

  cat >"${test_dir}/allowed-exception.go.mod" <<'EOF'
module example.com/allowed

go 1.25.10

require github.com/cosmos/evm v0.7.0

replace github.com/ethereum/go-ethereum => github.com/cosmos/go-ethereum v1.17.2-cosmos-0
EOF
  KUDORA_GO_MOD_PATH="${test_dir}/allowed-exception.go.mod" ./scripts/verify-no-forks.sh >/dev/null

  cat >"${test_dir}/wrong-version.go.mod" <<'EOF'
module example.com/wrong

go 1.25.10

require github.com/cosmos/evm v0.7.0

replace github.com/ethereum/go-ethereum => github.com/cosmos/go-ethereum v1.17.1-cosmos-0
EOF
  if KUDORA_GO_MOD_PATH="${test_dir}/wrong-version.go.mod" ./scripts/verify-no-forks.sh >/dev/null 2>&1; then
    echo "phase-2.1-validate: verify-no-forks.sh accepted the wrong cosmos/go-ethereum version" >&2
    rm -rf "$test_dir"
    return 1
  fi

  cat >"${test_dir}/wrong-cosmos-evm-version.go.mod" <<'EOF'
module example.com/wrong-evm

go 1.25.10

require github.com/cosmos/evm v0.6.0

replace github.com/ethereum/go-ethereum => github.com/cosmos/go-ethereum v1.17.2-cosmos-0
EOF
  if KUDORA_GO_MOD_PATH="${test_dir}/wrong-cosmos-evm-version.go.mod" ./scripts/verify-no-forks.sh >/dev/null 2>&1; then
    echo "phase-2.1-validate: verify-no-forks.sh accepted the exception with the wrong cosmos/evm version" >&2
    rm -rf "$test_dir"
    return 1
  fi

  cat >"${test_dir}/arbitrary-target.go.mod" <<'EOF'
module example.com/arbitrary

go 1.25.10

require github.com/cosmos/evm v0.7.0

replace github.com/ethereum/go-ethereum => example.com/custom/geth v1.17.2
EOF
  if KUDORA_GO_MOD_PATH="${test_dir}/arbitrary-target.go.mod" ./scripts/verify-no-forks.sh >/dev/null 2>&1; then
    echo "phase-2.1-validate: verify-no-forks.sh accepted an arbitrary go-ethereum replacement target" >&2
    rm -rf "$test_dir"
    return 1
  fi

  cat >"${test_dir}/replace-block-forbidden.go.mod" <<'EOF'
module example.com/forbidden-block

go 1.25.10

replace (
  github.com/cosmos/cosmos-sdk => example.com/custom/sdk v0.0.0
)
EOF
  if KUDORA_GO_MOD_PATH="${test_dir}/replace-block-forbidden.go.mod" ./scripts/verify-no-forks.sh >/dev/null 2>&1; then
    echo "phase-2.1-validate: verify-no-forks.sh accepted a forbidden replace block entry" >&2
    rm -rf "$test_dir"
    return 1
  fi

  rm -rf "$test_dir"
}

run_check "make phase-2-validate" make phase-2-validate
run_check "make tidy" make tidy
run_check "make build" make build
run_check "make test" make test
run_check "make lint" make lint
run_check "make verify-no-forks" make verify-no-forks
run_check "make verify-clean-reset" make verify-clean-reset
run_check "make verify-no-secrets" make verify-no-secrets
run_check "Phase 2.1 docs exist" check_phase21_docs
run_check "policy decision is exact" check_policy_decision
run_check "temporary upstream repos are not tracked" check_tmp_repos_not_tracked
run_check "no EVM runtime wiring present" check_no_evm_wiring
run_check "no EVM Docker ports exposed" check_no_evm_ports
run_check "Kudora go.mod has no EVM deps yet" check_current_go_mod_has_no_evm_deps
run_check "verify-no-forks documents the approved exception" check_verify_no_forks_policy
run_check "verify-no-forks enforces the approved exception" check_verify_no_forks_behavior
run_check "make docker-build" make docker-build
run_check "make docker-smoke-test" make docker-smoke-test
run_check "make zip" make zip

{
  echo "# Phase 2.1 Validation Report"
  echo
  echo "- Validation generated at: ${generated_at}"
  echo "- Branch: ${branch_name}"
  echo "- Starting commit: ${starting_commit}"
  echo "- Current HEAD before report generation: ${head_before_report}"
  echo "- Cosmos EVM tag inspected: \`${COSMOS_EVM_TAG}\`"
  echo "- Cosmos EVM commit inspected: \`${COSMOS_EVM_COMMIT}\`"
  echo "- Ignite EVM app commit inspected: \`${IGNITE_APPS_COMMIT}\`"
  echo "- Approved policy decision: \`${APPROVED_POLICY_DECISION}\`"
  echo "- Approved exception version: \`${APPROVED_EXCEPTION_VERSION}\`"
  echo "- Phase 3 status: ${PHASE3_STATUS}"
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
  echo "${go_version}"
  echo
  echo "${ignite_version}"
  echo
  echo "${docker_version}"
  echo '```'
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
  echo "- No EVM runtime code was added in Phase 2.1."
  echo "- No EVM Docker ports were exposed."
  echo "- No Docker registry push occurred."
  echo "- Kudora still does not depend on \`github.com/cosmos/evm\` or \`github.com/cosmos/go-ethereum\`."
} >"$REPORT_PATH"

echo "phase-2.1-validate: PASS (${REPORT_PATH})"
