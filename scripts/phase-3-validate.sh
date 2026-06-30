#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

OUT_DIR="out"
REPORT_PATH="${OUT_DIR}/phase-3-validation.md"
EXPECTED_BRANCH="Upgrade"
OFFICIAL_CHAIN_ID="kudora_12000-1"
SUPERSEDED_CHAIN_ID="kudora_12000-2"
COSMOS_EVM_TAG="v0.7.0"
COSMOS_EVM_COMMIT="f4ab9a3e3fbe353468327d5cacda94b33b41ed11"
EVM_CHAIN_ID="120001"
EXPECTED_ETH_CHAIN_ID="0x1d4c1"
DOCKER_IMAGE="kudora/kudorad:phase3-local"
LATEST_ARCHIVE_PATH="out/kudora-phase-3-evm-runtime.zip"
INSPECTION_ARCHIVE_PATH="out/kudora-latest-inspection.zip"
COMPATIBILITY_ARCHIVE_PATH="out/kudora-phase-0-reset.zip"

mkdir -p "$OUT_DIR"

branch_name="$(git branch --show-current)"
if [[ "$branch_name" != "$EXPECTED_BRANCH" ]]; then
  echo "phase-3-validate: expected branch ${EXPECTED_BRANCH}, found ${branch_name}" >&2
  exit 1
fi

starting_commit="$(git rev-parse HEAD)"
head_before_report="$(git rev-parse HEAD)"
working_tree_status_before="$(git status --short)"
generated_at="$(date -u '+%Y-%m-%d %H:%M:%S UTC')"
go_version="$(go version)"
ignite_version="$(ignite version 2>&1 | tr -d '\r')"
docker_version="$(docker version 2>&1)"
cosmos_sdk_version="$(go list -m -f '{{.Version}}' github.com/cosmos/cosmos-sdk)"
cometbft_version="$(go list -m -f '{{.Version}}' github.com/cometbft/cometbft)"
geth_replacement_line="$(awk '/github\.com\/ethereum\/go-ethereum[[:space:]]*=>/ {gsub(/^[[:space:]]+/, "", $0); print; exit}' go.mod)"
files_changed="$(
  {
    git diff --name-only HEAD
    git ls-files --others --exclude-standard
  } | sort -u
)"

commands=(
  "make tidy"
  "go mod verify"
  "make build"
  "make test"
  "make lint"
  "make verify-no-forks"
  "make verify-clean-reset"
  "make verify-no-secrets"
  "ignite chain build --check-dependencies"
  "make docker-build"
  "make docker-smoke-test"
  "make evm-smoke-test"
  "make zip"
)

results=()

run_check() {
  local label="$1"
  shift
  "$@"
  results+=("PASS|${label}")
}

check_phase3_docs() {
  local required_files=(
    "docs/evm/phase-3-evm-runtime.md"
    "docs/evm/phase-2-official-evm-path.md"
    "docs/evm/phase-2-evm-compatibility-matrix.md"
    "docs/evm/phase-2-evm-integration-design.md"
    "docs/evm/phase-2.1-evm-dependency-policy.md"
    "docs/release/dependency-baseline.md"
  )
  local path

  for path in "${required_files[@]}"; do
    if [[ ! -f "$path" ]]; then
      echo "phase-3-validate: required Phase 3 document missing: $path" >&2
      return 1
    fi
  done
}

check_no_tracked_tmp_repos() {
  local tracked_tmp
  tracked_tmp="$(git ls-files tmp/cosmos-evm tmp/ignite-apps)"
  if [[ -n "$tracked_tmp" ]]; then
    echo "phase-3-validate: temporary upstream repositories must not be tracked" >&2
    printf '%s\n' "$tracked_tmp" >&2
    return 1
  fi
}

check_phase3_go_mod_policy() {
  rg -n '^\s*github\.com/cosmos/evm v0\.7\.0' go.mod >/dev/null || {
    echo "phase-3-validate: github.com/cosmos/evm v0.7.0 is missing from go.mod" >&2
    return 1
  }

  rg -n '^replace github\.com/ethereum/go-ethereum => github\.com/cosmos/go-ethereum v1\.17\.2-cosmos-0$' go.mod >/dev/null || {
    echo "phase-3-validate: approved cosmos/go-ethereum replacement is missing or mismatched" >&2
    return 1
  }
}

check_phase3_runtime_scope() {
  local tracked_x
  tracked_x="$(git ls-files 'x/*')"
  if [[ -n "$tracked_x" ]]; then
    echo "phase-3-validate: local x/ business modules must not be committed in Phase 3" >&2
    printf '%s\n' "$tracked_x" >&2
    return 1
  fi

  for forbidden_path in proto/kudora proto/cosmwasm proto/tokenfactory app/wasm.go; do
    if git ls-files "$forbidden_path" | rg -q .; then
      echo "phase-3-validate: forbidden Phase 3 path present: $forbidden_path" >&2
      return 1
    fi
  done
}

check_chain_id_docs() {
  local active_matches

  active_matches="$(
    {
      rg -n 'kudora_12000-2|120002|0x1d4c2' \
        README.md \
        docs/phase-0-reset.md \
        docs/evm/phase-2-official-evm-path.md \
        docs/evm/phase-2-evm-compatibility-matrix.md \
        docs/evm/phase-2-evm-integration-design.md \
        docs/evm/phase-2.1-evm-dependency-policy.md \
        docs/evm/phase-3-evm-runtime.md \
        docs/release/dependency-baseline.md \
        scripts/phase-0-validate.sh \
        scripts/phase-0.1-validate.sh \
        scripts/evm-smoke-test.sh \
        app \
        cmd \
        Dockerfile \
        Makefile \
        .github/workflows \
        2>/dev/null || true
    } | rg -vi 'superseded|earlier planning' || true
  )"

  if [[ -n "$active_matches" ]]; then
    echo "phase-3-validate: active docs or scripts still use superseded chain-id assumptions" >&2
    printf '%s\n' "$active_matches" >&2
    return 1
  fi
}

check_phase3_ports() {
  rg -n '^EXPOSE .*26656 .*26657 .*1317 .*9090 .*8545 .*8546$' Dockerfile >/dev/null || {
    echo "phase-3-validate: Dockerfile does not expose the expected Cosmos and EVM ports" >&2
    return 1
  }
}

check_no_premature_ibc_product_activation() {
  local active_matches

  active_matches="$(
    rg -n \
      -e 'packetforward' \
      -e 'packet-forward' \
      -e 'ratelimit' \
      -e 'rate-limit' \
      -e 'interchainaccounts' \
      -e 'interchain accounts' \
      -e '08-wasm' \
      -e 'modules/apps/transfer' \
      -e 'transferkeeper' \
      -e 'relayer' \
      app cmd Dockerfile Makefile .github/workflows 2>/dev/null || true
  )"

  if [[ -n "$active_matches" ]]; then
    echo "phase-3-validate: premature IBC product activation detected" >&2
    printf '%s\n' "$active_matches" >&2
    return 1
  fi
}

check_phase3_archive() {
  if [[ ! -f "$LATEST_ARCHIVE_PATH" ]]; then
    echo "phase-3-validate: expected latest archive at $LATEST_ARCHIVE_PATH" >&2
    return 1
  fi

  if [[ ! -f "$INSPECTION_ARCHIVE_PATH" ]]; then
    echo "phase-3-validate: latest inspection archive missing at $INSPECTION_ARCHIVE_PATH" >&2
    return 1
  fi

  if [[ ! -f "$COMPATIBILITY_ARCHIVE_PATH" ]]; then
    echo "phase-3-validate: compatibility archive copy missing at $COMPATIBILITY_ARCHIVE_PATH" >&2
    return 1
  fi

  local listing_path
  listing_path="$(mktemp)"
  unzip -Z1 "$LATEST_ARCHIVE_PATH" >"$listing_path"

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
    "$listing_path" >/dev/null; then
    echo "phase-3-validate: forbidden content found in ${LATEST_ARCHIVE_PATH}" >&2
    rm -f "$listing_path"
    return 1
  fi

  rm -f "$listing_path"
}

run_check "Phase 3 docs exist" check_phase3_docs
run_check "temporary upstream repos are not tracked" check_no_tracked_tmp_repos
run_check "Phase 3 go.mod policy" check_phase3_go_mod_policy
run_check "Phase 3 scope check" check_phase3_runtime_scope
run_check "active chain-id messaging" check_chain_id_docs
run_check "Dockerfile EVM ports" check_phase3_ports
run_check "no premature IBC product activation" check_no_premature_ibc_product_activation
run_check "make tidy" make tidy
run_check "go mod verify" go mod verify
run_check "make build" make build
run_check "make test" make test
run_check "make lint" make lint
run_check "make verify-no-forks" make verify-no-forks
run_check "make verify-clean-reset" make verify-clean-reset
run_check "make verify-no-secrets" make verify-no-secrets
run_check "ignite chain build --check-dependencies" ./scripts/ignite-check-dependencies.sh
run_check "make docker-build" make docker-build
run_check "make docker-smoke-test" make docker-smoke-test
run_check "make evm-smoke-test" make evm-smoke-test
run_check "make zip" make zip
run_check "archive safety verification" check_phase3_archive

docker_ports_summary="$(rg -n '^EXPOSE ' Dockerfile | sed 's/^[0-9]*://')"

{
  echo "# Phase 3 Validation Report"
  echo
  echo "- Validation generated at: ${generated_at}"
  echo "- Branch: ${branch_name}"
  echo "- Starting commit: ${starting_commit}"
  echo "- Current HEAD before report generation: ${head_before_report}"
  echo "- Official Cosmos chain-id: \`${OFFICIAL_CHAIN_ID}\`"
  echo "- Superseded planning chain-id: \`${SUPERSEDED_CHAIN_ID}\`"
  echo "- Cosmos EVM version/tag/commit: \`${COSMOS_EVM_TAG}\` / \`${COSMOS_EVM_COMMIT}\`"
  echo "- Cosmos SDK version after alignment: \`${cosmos_sdk_version}\`"
  echo "- CometBFT version after alignment: \`${cometbft_version}\`"
  echo "- Approved go-ethereum exception status: \`${geth_replacement_line}\`"
  echo "- EVM chain ID: \`${EVM_CHAIN_ID}\`"
  echo "- Expected \`eth_chainId\`: \`${EXPECTED_ETH_CHAIN_ID}\`"
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
  echo "## Modules Wired"
  echo
  echo "- \`x/vm\` via upstream \`github.com/cosmos/evm\`"
  echo "- \`x/feemarket\` via upstream \`github.com/cosmos/evm\`"
  echo "- \`x/erc20\` via upstream \`github.com/cosmos/evm\`"
  echo "- Cosmos EVM ante handling"
  echo "- Cosmos EVM mempool"
  echo "- JSON-RPC server wiring"
  echo
  echo "## Files Changed In This Phase"
  echo
  echo '```text'
  echo "${files_changed:-none}"
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
  echo "## Docker Ports Exposed"
  echo
  echo '```text'
  echo "${docker_ports_summary}"
  echo '```'
  echo
  echo "## Confirmations"
  echo
  echo "- No secrets were detected in the working tree."
  echo "- No forbidden runtime forks were found."
  echo "- No local business modules were added."
  echo "- No premature IBC product activation was detected."
  echo "- No Docker registry push was performed."
  echo "- Latest archive path: \`${LATEST_ARCHIVE_PATH}\`"
  echo "- Latest inspection archive path: \`${INSPECTION_ARCHIVE_PATH}\`"
  echo "- Compatibility archive path: \`${COMPATIBILITY_ARCHIVE_PATH}\`"
  echo "- Note: the final pushed commit may differ if this report is committed afterward."
} >"$REPORT_PATH"

echo "phase-3-validate: PASS (${REPORT_PATH})"
