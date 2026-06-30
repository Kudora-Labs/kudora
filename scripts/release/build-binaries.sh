#!/usr/bin/env bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

release_prepare_dirs
release_require_command jq
release_require_command file
release_require_docker
release_require_candidate_genesis

platform="$(release_linux_amd64_platform)"
platform_dir="$(release_binary_dir "${platform}")"
binary_path="$(release_binary_path "${platform}")"
lib_name="$(release_required_wasmvm_library "${platform}")"
lib_path="$(release_wasmvm_lib_path "${platform}" "${lib_name}")"
metadata_path="$(release_build_metadata_path)"
platforms_file="$(release_supported_platforms_file)"
git_commit="$(release_git_commit)"
build_created="$(release_now_utc)"
host_cache_dir="$(mktemp -d "${TMPDIR:-/tmp}/kudora-phase17-release-cache.XXXXXX")"

cleanup() {
  rm -rf "${host_cache_dir}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

rm -rf "${platform_dir}"
mkdir -p "${platform_dir}" "$(release_wasmvm_lib_dir "${platform}")" "$(dirname "${metadata_path}")"

docker run --rm \
  -v "${ROOT_DIR}:/workspace:ro" \
  -v "${platform_dir}:/out" \
  -v "${host_cache_dir}:/cache" \
  -w /workspace \
  "golang:1.26.4-bookworm" \
  bash -c '
    set -euo pipefail

    native_arch="$(dpkg --print-architecture)"
    cc_bin="cc"

    if [[ "${native_arch}" != "amd64" ]]; then
      apt-get update >/dev/null
      DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends gcc-x86-64-linux-gnu libc6-dev-amd64-cross >/dev/null
      rm -rf /var/lib/apt/lists/*
      cc_bin="x86_64-linux-gnu-gcc"
    fi

    export GOFLAGS=-buildvcs=false
    export GOCACHE=/cache/gocache
    export GOMODCACHE=/cache/gomod
    export GOTMPDIR=/cache/gotmp
    export TMPDIR=/cache/tmp
    export GOOS=linux
    export GOARCH=amd64
    export GOAMD64=v1
    export CGO_ENABLED=1
    export CC="${cc_bin}"

    mkdir -p "${GOCACHE}" "${GOMODCACHE}" "${GOTMPDIR}" "${TMPDIR}" /out/lib

    go build -trimpath \
      -ldflags="-s -w \
        -X github.com/cosmos/cosmos-sdk/version.Name=kudora \
        -X github.com/cosmos/cosmos-sdk/version.AppName=kudorad \
        -X github.com/cosmos/cosmos-sdk/version.Version='"$(release_version_tag)"' \
        -X github.com/cosmos/cosmos-sdk/version.Commit='"${git_commit}"' \
        -X github.com/cosmos/cosmos-sdk/version.BuildTags=release,candidate,linux,amd64" \
      -o /out/'"${RELEASE_BINARY_NAME}"' ./cmd/'"${RELEASE_BINARY_NAME}"'

    mod_cache="$(go env GOMODCACHE)"
    wasmvm_lib="$(find "${mod_cache}" -path '"'"'*/github.com/!cosm!wasm/wasmvm/v3@*/internal/api/libwasmvm.x86_64.so'"'"' | head -n 1)"
    test -n "${wasmvm_lib}"
    cp "${wasmvm_lib}" /out/lib/'"${lib_name}"'
  '

chmod 0755 "${binary_path}"
chmod 0644 "${lib_path}"

printf '%s\n' "${platform}" >"${platforms_file}"

jq -n \
  --arg generated_at_utc "${build_created}" \
  --arg release_version "$(release_version_tag)" \
  --arg git_commit "${git_commit}" \
  --arg platform "${platform}" \
  --arg binary_path "$(release_repo_relpath "${binary_path}")" \
  --arg binary_sha256 "$(release_sha256_file "${binary_path}")" \
  --arg binary_file_type "$(file "${binary_path}")" \
  --arg wasmvm_library_path "$(release_repo_relpath "${lib_path}")" \
  --arg wasmvm_library_sha256 "$(release_sha256_file "${lib_path}")" \
  --arg wasmvm_library_name "${lib_name}" \
  '{
    generated_at_utc: $generated_at_utc,
    release_version: $release_version,
    git_commit: $git_commit,
    supported_platforms: [$platform],
    artifacts: [
      {
        platform: $platform,
        binary_path: $binary_path,
        binary_sha256: $binary_sha256,
        binary_file_type: $binary_file_type,
        wasmvm_library_path: $wasmvm_library_path,
        wasmvm_library_sha256: $wasmvm_library_sha256,
        wasmvm_library_name: $wasmvm_library_name
      }
    ]
  }' >"${metadata_path}"

echo "release-build-binaries: PASS (${binary_path})"
