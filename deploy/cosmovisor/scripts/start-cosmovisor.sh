#!/usr/bin/env bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../common.sh"

cosmovisor_prepare_dirs
release_require_docker

if [[ ! -d "${COSMOVISOR_HOME_DIR}/config" ]]; then
  "${ROOT_DIR}/deploy/cosmovisor/scripts/init-cosmovisor-home.sh" >/dev/null
fi

cosmovisor_compose up -d

if [[ "${1:-}" == "--logs" ]]; then
  cosmovisor_compose logs -f
fi

echo "start-cosmovisor: PASS (${COSMOVISOR_CONTAINER_NAME})"
