#!/usr/bin/env bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

release_prepare_dirs
release_require_command jq
release_require_command zip
release_require_command tar
release_require_candidate_genesis

platform="$(release_linux_amd64_platform)"
release_require_supported_platform "${platform}"

binary_path="$(release_binary_path "${platform}")"
lib_name="$(release_required_wasmvm_library "${platform}")"
lib_path="$(release_wasmvm_lib_path "${platform}" "${lib_name}")"
linux_archive_path="$(release_linux_amd64_archive_path)"
source_archive_path="$(release_source_context_archive_path)"
manifest_path="${RELEASE_MANIFEST_PATH}"
checksums_path="${RELEASE_CHECKSUMS_PATH}"
manifest_tmp="${RELEASE_TEMP_WORK_DIR}/manifest.json.tmp"
checksums_tmp="${RELEASE_TEMP_WORK_DIR}/checksums.sha256.tmp"
package_root="${RELEASE_TEMP_WORK_DIR}/linux-amd64"
source_root="${RELEASE_TEMP_WORK_DIR}/source-context"
metadata_path="${MAINNET_METADATA_OUTPUT_PATH}"
git_commit="$(release_git_commit)"
git_branch="$(release_git_branch)"
build_timestamp_utc="$(release_now_utc)"
launch_ready_reason="$(release_mainnet_launch_ready_reason)"

rm -rf "${package_root}" "${source_root}"
mkdir -p \
  "${package_root}/bin" \
  "${package_root}/lib" \
  "${package_root}/genesis" \
  "${package_root}/config" \
  "${source_root}"

jq -n \
  --arg release_version "$(release_version_tag)" \
  --arg release_track "${RELEASE_TRACK}" \
  --arg release_type "${RELEASE_TYPE}" \
  --arg mainnet_launch_ready "false" \
  --arg mainnet_launch_ready_reason "${launch_ready_reason}" \
  --arg git_commit "${git_commit}" \
  --arg git_branch "${git_branch}" \
  --arg build_timestamp_utc "${build_timestamp_utc}" \
  --arg go_version "$(go version)" \
  --arg binary_name "${RELEASE_BINARY_NAME}" \
  --arg app_name "${RELEASE_APP_NAME}" \
  --arg chain_id "${MAINNET_CHAIN_ID}" \
  --arg evm_chain_id "${MAINNET_EVM_CHAIN_ID}" \
  --arg eth_chain_id "${MAINNET_ETH_CHAIN_ID}" \
  --arg denom "${MAINNET_BASE_DENOM}" \
  --arg display_denom "${MAINNET_DISPLAY_DENOM}" \
  --arg decimals "${MAINNET_DECIMALS}" \
  --arg cosmos_sdk_version "$(go list -m -f '{{.Version}}' github.com/cosmos/cosmos-sdk)" \
  --arg cometbft_version "$(go list -m -f '{{.Version}}' github.com/cometbft/cometbft)" \
  --arg cosmos_evm_version "$(go list -m -f '{{.Version}}' github.com/cosmos/evm)" \
  --arg wasmd_version "$(go list -m -f '{{.Version}}' github.com/CosmWasm/wasmd)" \
  --arg wasmvm_version "$(go list -m -f '{{.Version}}' github.com/CosmWasm/wasmvm/v3)" \
  --arg candidate_genesis_sha256 "$(release_candidate_genesis_sha256)" \
  --arg allocations_sha256 "$(release_allocations_sha256)" \
  --arg docker_image_tag "$(release_docker_image_tag)" \
  --arg docker_image_latest_rc_tag "$(release_docker_image_latest_rc_tag)" \
  --argjson release_artifacts "$(jq -n \
    --arg linux_archive "$(release_repo_relpath "${linux_archive_path}")" \
    --arg source_archive "$(release_repo_relpath "${source_archive_path}")" \
    '[
      {path: $linux_archive, kind: "binary_tarball", platform: "linux/amd64"},
      {path: $source_archive, kind: "source_context"}
    ]')" \
  '{
    release_version: $release_version,
    release_track: $release_track,
    release_type: $release_type,
    mainnet_launch_ready: ($mainnet_launch_ready == "true"),
    mainnet_launch_ready_reason: $mainnet_launch_ready_reason,
    git_commit: $git_commit,
    git_branch: $git_branch,
    build_timestamp_utc: $build_timestamp_utc,
    go_version: $go_version,
    binary_name: $binary_name,
    app_name: $app_name,
    chain_id: $chain_id,
    evm_chain_id: ($evm_chain_id | tonumber),
    eth_chainId: $eth_chain_id,
    denom: $denom,
    display_denom: $display_denom,
    decimals: ($decimals | tonumber),
    cosmos_sdk_version: $cosmos_sdk_version,
    cometbft_version: $cometbft_version,
    cosmos_evm_version: $cosmos_evm_version,
    wasmd_version: $wasmd_version,
    wasmvm_version: $wasmvm_version,
    candidate_genesis_sha256: $candidate_genesis_sha256,
    allocations_sha256: $allocations_sha256,
    release_artifacts: $release_artifacts,
    docker_image_tags: [$docker_image_tag, $docker_image_latest_rc_tag],
    cosmovisor_supported: true,
    cosmovisor_auto_download_default: false,
    no_registry_push: true,
    no_github_release: true,
    no_git_tag: true
  }' >"${manifest_tmp}"
mv "${manifest_tmp}" "${manifest_path}"

checksum_paths=(
  "VERSION"
  "release/README.md"
  "release/docker/README.md"
  "release/cosmovisor/README.md"
  "release/manifest.json"
  "config/mainnet/allocations.json"
  "config/mainnet/genesis-policy.md"
  "docs/mainnet/phase-16-genesis.md"
  "docs/release/phase-17-candidate-release-cosmovisor.md"
  "$(release_repo_relpath "${MAINNET_GENESIS_OUTPUT_PATH}")"
  "$(release_repo_relpath "${MAINNET_METADATA_OUTPUT_PATH}")"
  "$(release_repo_relpath "${binary_path}")"
  "$(release_repo_relpath "${lib_path}")"
)

: >"${checksums_tmp}"
for rel_path in "${checksum_paths[@]}"; do
  printf '%s  %s\n' "$(release_sha256_file "${ROOT_DIR}/${rel_path}")" "${rel_path}" >>"${checksums_tmp}"
done
LC_ALL=C sort -o "${checksums_tmp}" "${checksums_tmp}"
mv "${checksums_tmp}" "${checksums_path}"

cp "${binary_path}" "${package_root}/bin/${RELEASE_BINARY_NAME}"
cp "${lib_path}" "${package_root}/lib/${lib_name}"
cp "${MAINNET_GENESIS_OUTPUT_PATH}" "${package_root}/genesis/genesis.json"
cp "$(mainnet_allocations_file)" "${package_root}/config/allocations.json"
cp "${manifest_path}" "${package_root}/manifest.json"
cp "${checksums_path}" "${package_root}/checksums.sha256"

cat >"${package_root}/README.md" <<EOF
Kudora $(release_version_tag) Candidate Release

THIS IS A CANDIDATE/DEVNET RELEASE.
NOT FINAL MAINNET LAUNCH-READY.

Release track: ${RELEASE_TRACK}
Release type: ${RELEASE_TYPE}
Mainnet launch-ready: false
Reason: ${launch_ready_reason}
EOF

chmod 0755 "${package_root}/bin/${RELEASE_BINARY_NAME}"

rm -f "${linux_archive_path}"
tar -C "${package_root}" -czf "${linux_archive_path}" .

rm -rf "${source_root}"
mkdir -p "${source_root}"
cp VERSION "${source_root}/VERSION"
cp README.md "${source_root}/README.md"
mkdir -p "${source_root}/release" "${source_root}/scripts" "${source_root}/deploy" "${source_root}/docs" "${source_root}/config"
cp release/README.md "${source_root}/release/README.md"
cp release/manifest.json "${source_root}/release/manifest.json"
cp release/checksums.sha256 "${source_root}/release/checksums.sha256"
mkdir -p "${source_root}/release/docker" "${source_root}/release/cosmovisor"
cp release/docker/README.md "${source_root}/release/docker/README.md"
cp release/cosmovisor/README.md "${source_root}/release/cosmovisor/README.md"
cp -R scripts/release "${source_root}/scripts/"
cp -R deploy/cosmovisor "${source_root}/deploy/"
cp -R config/mainnet "${source_root}/config/"
mkdir -p "${source_root}/docs/release" "${source_root}/docs/mainnet"
cp docs/release/phase-17-candidate-release-cosmovisor.md "${source_root}/docs/release/"
cp docs/mainnet/phase-16-genesis.md "${source_root}/docs/mainnet/"
cp scripts/phase-17-validate.sh "${source_root}/scripts/"

rm -f "${source_archive_path}"
(
  cd "${source_root}"
  zip -qr "${source_archive_path}" .
)

jq -n \
  --arg generated_at_utc "${build_timestamp_utc}" \
  --arg manifest_path "$(release_repo_relpath "${manifest_path}")" \
  --arg checksums_path "$(release_repo_relpath "${checksums_path}")" \
  --arg linux_archive_path "$(release_repo_relpath "${linux_archive_path}")" \
  --arg source_archive_path "$(release_repo_relpath "${source_archive_path}")" \
  --arg metadata_path "$(release_repo_relpath "${metadata_path}")" \
  '{
    generated_at_utc: $generated_at_utc,
    manifest_path: $manifest_path,
    checksums_path: $checksums_path,
    linux_archive_path: $linux_archive_path,
    source_archive_path: $source_archive_path,
    metadata_path: $metadata_path
  }' >"${RELEASE_OUT_DIR}/package-metadata.json"

echo "release-package: PASS (${linux_archive_path}; ${source_archive_path})"
