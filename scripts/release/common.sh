#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT_DIR}"

source "${ROOT_DIR}/scripts/mainnet/common.sh"

RELEASE_VERSION_FILE="${ROOT_DIR}/VERSION"
RELEASE_MANIFEST_PATH="${ROOT_DIR}/release/manifest.json"
RELEASE_CHECKSUMS_PATH="${ROOT_DIR}/release/checksums.sha256"
RELEASE_OUT_DIR="${ROOT_DIR}/out/release"
RELEASE_TMP_DIR="${ROOT_DIR}/tmp/phase-17-release"
RELEASE_DOCKER_TMP_DIR="${ROOT_DIR}/tmp/phase-17-docker"
RELEASE_COSMOVISOR_TMP_DIR="${ROOT_DIR}/tmp/phase-17-cosmovisor"
RELEASE_TEMP_WORK_DIR="${ROOT_DIR}/release/temp"

RELEASE_TRACK="candidate"
RELEASE_TYPE="devnet_candidate"
RELEASE_BINARY_NAME="kudorad"
RELEASE_APP_NAME="kudora"
RELEASE_DOCKER_IMAGE_REPOSITORY="kudora/kudorad"
RELEASE_DOCKER_IMAGE_LATEST_RC_TAG="latest-rc"
COSMOVISOR_IMAGE_REPOSITORY="kudora/kudorad-cosmovisor"
COSMOVISOR_VERSION="${KUDORA_COSMOVISOR_VERSION:-v1.6.0}"

release_die() {
  echo "$*" >&2
  exit 1
}

release_require_command() {
  command -v "$1" >/dev/null 2>&1 || release_die "phase-17: required command not found: $1"
}

release_require_docker() {
  docker version >/dev/null 2>&1 || release_die "phase-17: docker daemon is not accessible from this shell session"
}

release_version_raw() {
  [[ -f "${RELEASE_VERSION_FILE}" ]] || release_die "phase-17: VERSION file missing at ${RELEASE_VERSION_FILE}"
  local version
  version="$(tr -d '[:space:]' <"${RELEASE_VERSION_FILE}")"
  [[ -n "${version}" ]] || release_die "phase-17: VERSION file is empty"
  printf '%s\n' "${version}"
}

release_version_tag() {
  printf 'v%s\n' "$(release_version_raw)"
}

release_git_commit() {
  git rev-parse HEAD
}

release_git_branch() {
  git branch --show-current
}

release_now_utc() {
  date -u '+%Y-%m-%dT%H:%M:%SZ'
}

release_prepare_dirs() {
  mkdir -p \
    "${RELEASE_OUT_DIR}" \
    "${RELEASE_TMP_DIR}" \
    "${RELEASE_DOCKER_TMP_DIR}" \
    "${RELEASE_COSMOVISOR_TMP_DIR}" \
    "${RELEASE_TEMP_WORK_DIR}"
}

release_force_remove_path() {
  local path="$1"
  [[ -e "${path}" ]] || return 0

  if rm -rf "${path}" 2>/dev/null; then
    return 0
  fi

  if command -v docker >/dev/null 2>&1; then
    local parent_dir base_name
    parent_dir="$(dirname "${path}")"
    base_name="$(basename "${path}")"
    docker run --rm -v "${parent_dir}:/cleanup" busybox sh -c "rm -rf \"/cleanup/${base_name}\"" >/dev/null 2>&1 || true
  fi

  rm -rf "${path}" 2>/dev/null || true
}

release_version_out_dir() {
  printf '%s/%s\n' "${RELEASE_OUT_DIR}" "$(release_version_tag)"
}

release_supported_platforms_file() {
  printf '%s/supported-platforms.txt\n' "$(release_version_out_dir)"
}

release_build_metadata_path() {
  printf '%s/build-metadata.json\n' "$(release_version_out_dir)"
}

release_binary_dir() {
  local platform="$1"
  printf '%s/%s\n' "$(release_version_out_dir)" "${platform}"
}

release_binary_path() {
  local platform="$1"
  printf '%s/%s\n' "$(release_binary_dir "${platform}")" "${RELEASE_BINARY_NAME}"
}

release_wasmvm_lib_dir() {
  local platform="$1"
  printf '%s/lib\n' "$(release_binary_dir "${platform}")"
}

release_wasmvm_lib_path() {
  local platform="$1"
  local arch_lib="$2"
  printf '%s/%s\n' "$(release_wasmvm_lib_dir "${platform}")" "${arch_lib}"
}

release_linux_amd64_platform() {
  printf 'linux-amd64\n'
}

release_linux_amd64_archive_path() {
  printf '%s/kudora-%s-linux-amd64.tar.gz\n' "${RELEASE_OUT_DIR}" "$(release_version_tag)"
}

release_source_context_archive_path() {
  printf '%s/kudora-%s-source-context.zip\n' "${RELEASE_OUT_DIR}" "$(release_version_tag)"
}

release_docker_image_tag() {
  printf '%s:%s\n' "${RELEASE_DOCKER_IMAGE_REPOSITORY}" "$(release_version_tag)"
}

release_docker_image_latest_rc_tag() {
  printf '%s:%s\n' "${RELEASE_DOCKER_IMAGE_REPOSITORY}" "${RELEASE_DOCKER_IMAGE_LATEST_RC_TAG}"
}

release_cosmovisor_image_tag() {
  printf '%s:%s\n' "${COSMOVISOR_IMAGE_REPOSITORY}" "$(release_version_tag)"
}

release_repo_relpath() {
  local path="$1"
  case "${path}" in
    "${ROOT_DIR}/"*) printf '%s\n' "${path#${ROOT_DIR}/}" ;;
    *) printf '%s\n' "${path}" ;;
  esac
}

release_sha256_file() {
  local path="$1"
  [[ -f "${path}" ]] || release_die "phase-17: file missing for sha256: ${path}"

  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "${path}" | awk '{print $1}'
    return 0
  fi

  shasum -a 256 "${path}" | awk '{print $1}'
}

release_require_candidate_genesis() {
  [[ -f "${MAINNET_GENESIS_OUTPUT_PATH}" ]] || release_die "phase-17: candidate genesis missing at ${MAINNET_GENESIS_OUTPUT_PATH}; run make phase-16.1-validate first"
  [[ -f "${MAINNET_METADATA_OUTPUT_PATH}" ]] || release_die "phase-17: candidate genesis metadata missing at ${MAINNET_METADATA_OUTPUT_PATH}; run make phase-16.1-validate first"

  jq -e '.genesis_template_valid == true' "${MAINNET_METADATA_OUTPUT_PATH}" >/dev/null \
    || release_die "phase-17: Phase 16.1 candidate genesis metadata is invalid; genesis_template_valid must be true"
  jq -e '.mainnet_launch_ready == false' "${MAINNET_METADATA_OUTPUT_PATH}" >/dev/null \
    || release_die "phase-17: candidate release requires mainnet_launch_ready=false"
}

release_mainnet_launch_ready_reason() {
  release_require_candidate_genesis
  jq -r '.mainnet_launch_ready_reason // ""' "${MAINNET_METADATA_OUTPUT_PATH}"
}

release_candidate_genesis_sha256() {
  release_require_candidate_genesis
  release_sha256_file "${MAINNET_GENESIS_OUTPUT_PATH}"
}

release_allocations_sha256() {
  release_sha256_file "$(mainnet_allocations_file)"
}

release_required_wasmvm_library() {
  local platform="$1"
  case "${platform}" in
    linux-amd64) printf 'libwasmvm.x86_64.so\n' ;;
    linux-arm64) printf 'libwasmvm.aarch64.so\n' ;;
    *) release_die "phase-17: unsupported wasmvm library lookup for platform ${platform}" ;;
  esac
}

release_manifest_supported_platforms_json() {
  local platforms=()
  if [[ -f "$(release_supported_platforms_file)" ]]; then
    while IFS= read -r platform; do
      [[ -n "${platform}" ]] || continue
      platforms+=("${platform}")
    done <"$(release_supported_platforms_file)"
  fi

  if (( ${#platforms[@]} == 0 )); then
    platforms=("$(release_linux_amd64_platform)")
  fi

  printf '%s\n' "${platforms[@]}" | jq -R . | jq -s .
}

release_require_supported_platform() {
  local platform="$1"
  [[ -f "$(release_binary_path "${platform}")" ]] || release_die "phase-17: release binary missing for ${platform}; run make release-build-binaries first"
  [[ -d "$(release_wasmvm_lib_dir "${platform}")" ]] || release_die "phase-17: wasmvm library directory missing for ${platform}; run make release-build-binaries first"
}
