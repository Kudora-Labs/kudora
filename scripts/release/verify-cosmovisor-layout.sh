#!/usr/bin/env bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"
source "${ROOT_DIR}/deploy/cosmovisor/common.sh"

release_prepare_dirs
cosmovisor_prepare_dirs

"${ROOT_DIR}/scripts/release/verify-cosmovisor-image.sh" >/dev/null
"${ROOT_DIR}/deploy/cosmovisor/scripts/init-cosmovisor-home.sh" >/dev/null

genesis_binary_path="${COSMOVISOR_HOME_DIR}/cosmovisor/genesis/bin/${RELEASE_BINARY_NAME}"
current_link_path="${COSMOVISOR_HOME_DIR}/cosmovisor/current"

[[ -f "${genesis_binary_path}" ]] || release_die "phase-17: cosmovisor genesis binary is missing at ${genesis_binary_path}"
[[ -L "${current_link_path}" ]] || release_die "phase-17: cosmovisor current symlink is missing"
expected_current_target="${COSMOVISOR_RUNTIME_HOME}/cosmovisor/genesis"
[[ "$(readlink "${current_link_path}")" == "${expected_current_target}" ]] \
  || release_die "phase-17: cosmovisor current symlink must point to ${expected_current_target}"

jq -n \
  --arg verified_at_utc "$(release_now_utc)" \
  --arg daemon_name "kudorad" \
  --arg daemon_home "${COSMOVISOR_RUNTIME_HOME}" \
  --arg home_host "$(release_repo_relpath "${COSMOVISOR_HOME_DIR}")" \
  --arg genesis_binary_path "$(release_repo_relpath "${genesis_binary_path}")" \
  --arg current_link_target "$(readlink "${current_link_path}")" \
  '{
    verified_at_utc: $verified_at_utc,
    daemon_name: $daemon_name,
    daemon_home: $daemon_home,
    home_host: $home_host,
    genesis_binary_path: $genesis_binary_path,
    current_link_target: $current_link_target
  }' >"${COSMOVISOR_LAYOUT_RESULT_PATH}"

echo "cosmovisor-layout-verify: PASS (${genesis_binary_path})"
