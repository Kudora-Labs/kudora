#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

OUT_DIR="out"
REPORT_PATH="${OUT_DIR}/phase-1-validation.md"
DOCKER_IMAGE="kudora/kudorad:phase3-local"

mkdir -p "$OUT_DIR"

branch_name="$(git branch --show-current)"
starting_commit="$(git rev-parse HEAD)"
head_before_report="$(git rev-parse HEAD)"
working_tree_status_before="$(git status --short)"
generated_at="$(date -u '+%Y-%m-%d %H:%M:%S UTC')"
go_version="$(go version)"
ignite_version="$(ignite version 2>&1 | tr -d '\r')"
docker_version="$(docker version 2>&1)"
docker_buildx_version="$(docker buildx version 2>&1)"
docker_buildx_status="available"

commands=(
  "make phase0.1-validate"
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

check_phase1_scope() {
  local forbidden_paths=(
    "x"
    "app/ante"
    "app/precompiles.go"
    "app/token_pair.go"
    "app/wasm.go"
    "proto/kudora"
    "proto/ibc"
    "proto/cosmwasm"
    "proto/tokenfactory"
  )
  local path tracked

  tracked="$(git ls-files)"
  for path in "${forbidden_paths[@]}"; do
    if printf '%s\n' "$tracked" | rg -x "$path|$path/.+" >/dev/null; then
      echo "phase-1-validate: forbidden blockchain feature path present: $path" >&2
      return 1
    fi
  done
}

check_ci_summary() {
  local workflow
  if [[ -e .github/workflows/release.yml ]]; then
    echo "phase-1-validate: release workflow must not exist in Phase 1" >&2
    return 1
  fi

  if rg -n '@main' .github/workflows >/dev/null; then
    echo "phase-1-validate: unstable @main GitHub Actions reference found" >&2
    rg -n '@main' .github/workflows >&2
    return 1
  fi

  for workflow in .github/workflows/*.yml; do
    [[ -e "$workflow" ]] || continue
    sed '/^[[:space:]]*#/d' "$workflow" | sed -n 's/.*make \([A-Za-z0-9_.-][A-Za-z0-9_.-]*\).*/\1/p'
  done | sort -u | while IFS= read -r target; do
    [[ -n "$target" ]] || continue
    awk -F: '/^[A-Za-z0-9_.-]+:/ {print $1}' Makefile | rg -x "$target" >/dev/null || {
      echo "phase-1-validate: workflow target missing from Makefile: $target" >&2
      exit 1
    }
  done
}

run_check "make phase0.1-validate" make phase0.1-validate
run_check "make tidy" make tidy
run_check "make build" make build
run_check "make test" make test
run_check "make lint" make lint
run_check "make verify-no-forks" make verify-no-forks
run_check "make verify-clean-reset" make verify-clean-reset
run_check "make verify-no-secrets" make verify-no-secrets
run_check "CI workflow summary" check_ci_summary
run_check "Phase 1 scope check" check_phase1_scope
run_check "make docker-build" make docker-build
run_check "make docker-smoke-test" make docker-smoke-test
run_check "make zip" make zip

dockerfile_summary="$(
  cat <<'EOF'
- Multi-stage build
- Official Go builder image: golang:1.26.4-bookworm
- Minimal runtime image: gcr.io/distroless/base-debian12:nonroot
- Non-root execution
- Entry point: /usr/local/bin/kudorad
- Default command: version --long
- Exposed ports: 26656, 26657, 1317, 9090
EOF
)"

dockerignore_summary="$(
  cat <<'EOF'
- Excludes Git history, local homes, testnets, build artifacts, release artifacts, logs, out/, and common secret-bearing file patterns
- Prevents Docker build context from including .env files, node keys, validator keys, and zip archives
EOF
)"

ci_summary="$(
  cat <<'EOF'
- go-unit.yml runs make test
- lint.yml runs make lint
- lint-pr.yml only validates pull request title semantics
- docker.yml runs make docker-build and make docker-smoke-test
- No release publishing workflow is present
EOF
)"

dependency_summary="$(
  cat <<'EOF'
- Go baseline documented from go.mod and local validation environment
- Ignite provenance carried forward from Phase 0.1
- Cosmos SDK baseline: v0.53.6
- CometBFT baseline: v0.38.21
- Current replace directives documented and justified in docs/release/dependency-baseline.md
EOF
)"

{
  echo "# Phase 1 Validation Report"
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
  echo "- Docker image name/tag: \`${DOCKER_IMAGE}\`"
  echo "- Docker buildx/buildkit availability: ${docker_buildx_status}"
  echo
  echo '```text'
  echo "${go_version}"
  echo
  echo "${ignite_version}"
  echo
  echo "${docker_version}"
  echo
  echo "${docker_buildx_version}"
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
  echo "## Dockerfile Summary"
  echo
  printf '%s\n' "${dockerfile_summary}"
  echo
  echo "## .dockerignore Summary"
  echo
  printf '%s\n' "${dockerignore_summary}"
  echo
  echo "## CI Workflow Summary"
  echo
  printf '%s\n' "${ci_summary}"
  echo
  echo "## Dependency Baseline Summary"
  echo
  printf '%s\n' "${dependency_summary}"
  echo
  echo "## Confirmations"
  echo
  echo "- No secrets were detected in the working tree."
  echo "- No forbidden runtime forks were found."
  echo "- No blockchain feature modules were added in Phase 1."
  echo "- No Docker registry push was performed."
  echo "- Existing Phase 0 and Phase 0.1 validations still pass."
  echo "- Latest local archive path: \`out/kudora-phase-0-reset.zip\`"
  echo "- Note: the final pushed commit may differ if this report is committed afterward."
} >"$REPORT_PATH"

echo "phase-1-validate: PASS (${REPORT_PATH})"
