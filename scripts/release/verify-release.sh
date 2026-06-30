#!/usr/bin/env bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

release_prepare_dirs
release_require_command jq
release_require_command tar
release_require_command unzip
release_require_command rg
release_require_command file
release_require_docker
release_require_candidate_genesis

manifest_path="${RELEASE_MANIFEST_PATH}"
checksums_path="${RELEASE_CHECKSUMS_PATH}"
linux_archive_path="$(release_linux_amd64_archive_path)"
source_archive_path="$(release_source_context_archive_path)"
platform="$(release_linux_amd64_platform)"
binary_dir="$(release_binary_dir "${platform}")"
binary_path="$(release_binary_path "${platform}")"
verify_output_path="${RELEASE_OUT_DIR}/verify-release.json"
tmp_extract_dir="${RELEASE_TMP_DIR}/verify"

[[ -f "${manifest_path}" ]] || release_die "phase-17: release manifest missing; run make release-package first"
[[ -f "${checksums_path}" ]] || release_die "phase-17: release checksums missing; run make release-package first"
[[ -f "${linux_archive_path}" ]] || release_die "phase-17: linux release archive missing; run make release-package first"
[[ -f "${source_archive_path}" ]] || release_die "phase-17: source context archive missing; run make release-package first"
release_require_supported_platform "${platform}"

jq -e . "${manifest_path}" >/dev/null || release_die "phase-17: release manifest is not valid JSON"
jq -e \
  --arg version "$(release_version_tag)" \
  --arg track "${RELEASE_TRACK}" \
  --arg release_type "${RELEASE_TYPE}" \
  --arg chain_id "${MAINNET_CHAIN_ID}" \
  --arg denom "${MAINNET_BASE_DENOM}" \
  --arg display_denom "${MAINNET_DISPLAY_DENOM}" \
  --arg decimals "${MAINNET_DECIMALS}" \
  --arg evm_chain_id "${MAINNET_EVM_CHAIN_ID}" \
  --arg eth_chain_id "${MAINNET_ETH_CHAIN_ID}" \
  '
    .release_version == $version and
    .release_track == $track and
    .release_type == $release_type and
    .mainnet_launch_ready == false and
    .chain_id == $chain_id and
    .denom == $denom and
    .display_denom == $display_denom and
    (.decimals | tostring) == $decimals and
    (.evm_chain_id | tostring) == $evm_chain_id and
    .eth_chainId == $eth_chain_id and
    .binary_name == "kudorad" and
    .app_name == "kudora" and
    .cosmovisor_supported == true and
    .cosmovisor_auto_download_default == false and
    .no_registry_push == true and
    .no_github_release == true and
    .no_git_tag == true and
    (.mainnet_launch_ready_reason // "" | length > 0)
  ' "${manifest_path}" >/dev/null || release_die "phase-17: manifest values do not match the required candidate release baseline"

while IFS= read -r artifact_path; do
  [[ -f "${ROOT_DIR}/${artifact_path}" ]] || release_die "phase-17: manifest artifact is missing: ${artifact_path}"
done < <(jq -r '.release_artifacts[].path' "${manifest_path}")

while read -r expected_hash rel_path; do
  [[ -n "${expected_hash}" && -n "${rel_path}" ]] || continue
  actual_hash="$(release_sha256_file "${ROOT_DIR}/${rel_path}")"
  [[ "${actual_hash}" == "${expected_hash}" ]] || release_die "phase-17: checksum mismatch for ${rel_path}"
done <"${checksums_path}"

[[ "$(jq -r '.candidate_genesis_sha256' "${manifest_path}")" == "$(release_candidate_genesis_sha256)" ]] \
  || release_die "phase-17: candidate genesis hash mismatch in manifest"
[[ "$(jq -r '.allocations_sha256' "${manifest_path}")" == "$(release_allocations_sha256)" ]] \
  || release_die "phase-17: allocations hash mismatch in manifest"

rm -rf "${tmp_extract_dir}"
mkdir -p "${tmp_extract_dir}"
tar -C "${tmp_extract_dir}" -xzf "${linux_archive_path}"

for required_path in \
  "bin/${RELEASE_BINARY_NAME}" \
  "genesis/genesis.json" \
  "manifest.json" \
  "checksums.sha256" \
  "README.md"
do
  [[ -e "${tmp_extract_dir}/${required_path}" ]] || release_die "phase-17: release archive is missing ${required_path}"
done

tar -xOf "${linux_archive_path}" README.md | rg -n 'CANDIDATE/DEVNET RELEASE|NOT FINAL MAINNET LAUNCH-READY' >/dev/null \
  || release_die "phase-17: release README is missing the candidate/devnet warning"

tar -tzf "${linux_archive_path}" | rg -n '(^|/)(\.env(\..*)?|priv_validator_key\.json|node_key\.json|key_seed\.json|.*\.pem|.*\.key|.*\.seed|.*\.mnemonic)$' >/dev/null \
  && release_die "phase-17: forbidden secret-bearing files found in release tarball" || true

unzip -Z1 "${source_archive_path}" | rg -n '^scripts/release/build-binaries\.sh$' >/dev/null \
  || release_die "phase-17: source context archive is missing release scripts"
unzip -Z1 "${source_archive_path}" | rg -n '^deploy/cosmovisor/Dockerfile$' >/dev/null \
  || release_die "phase-17: source context archive is missing cosmovisor assets"

file "${binary_path}" | rg -n 'ELF 64-bit.*x86-64' >/dev/null \
  || release_die "phase-17: linux/amd64 release binary is not an x86-64 ELF binary"

version_output="$(
  docker run --rm \
    --platform linux/amd64 \
    -e LD_LIBRARY_PATH=/release/lib \
    -v "${binary_dir}:/release:ro" \
    debian:bookworm-slim \
    /release/${RELEASE_BINARY_NAME} version 2>&1
)"
printf '%s\n' "${version_output}" | rg -n "$(release_version_tag)" >/dev/null \
  || release_die "phase-17: linux/amd64 release binary version output did not include $(release_version_tag)"

help_output="$(
  docker run --rm \
    --platform linux/amd64 \
    -e LD_LIBRARY_PATH=/release/lib \
    -v "${binary_dir}:/release:ro" \
    debian:bookworm-slim \
    /release/${RELEASE_BINARY_NAME} start --help 2>&1
)"
printf '%s\n' "${help_output}" | rg -n 'start a full node|start.*node|Usage:' >/dev/null \
  || release_die "phase-17: linux/amd64 release binary did not return the expected start help output"

jq -n \
  --arg verified_at_utc "$(release_now_utc)" \
  --arg manifest_path "$(release_repo_relpath "${manifest_path}")" \
  --arg manifest_sha256 "$(release_sha256_file "${manifest_path}")" \
  --arg checksums_path "$(release_repo_relpath "${checksums_path}")" \
  --arg candidate_genesis_sha256 "$(release_candidate_genesis_sha256)" \
  --arg allocations_sha256 "$(release_allocations_sha256)" \
  --arg linux_archive_path "$(release_repo_relpath "${linux_archive_path}")" \
  --arg source_archive_path "$(release_repo_relpath "${source_archive_path}")" \
  --arg version_output "${version_output}" \
  '{
    verified_at_utc: $verified_at_utc,
    manifest_path: $manifest_path,
    manifest_sha256: $manifest_sha256,
    checksums_path: $checksums_path,
    candidate_genesis_sha256: $candidate_genesis_sha256,
    allocations_sha256: $allocations_sha256,
    linux_archive_path: $linux_archive_path,
    source_archive_path: $source_archive_path,
    version_output: $version_output
  }' >"${verify_output_path}"

echo "release-verify: PASS (${linux_archive_path})"
