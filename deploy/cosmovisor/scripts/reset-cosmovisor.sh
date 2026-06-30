#!/usr/bin/env bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../common.sh"

cosmovisor_prepare_dirs
release_require_docker

cosmovisor_compose down --remove-orphans -v >/dev/null 2>&1 || true
rm -rf "${COSMOVISOR_HOME_DIR}" "${COSMOVISOR_RESULT_PATH}" "${COSMOVISOR_LAYOUT_RESULT_PATH}" "${COSMOVISOR_LOG_DIR}"

echo "reset-cosmovisor: PASS"
