#!/usr/bin/env bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

mode="${1:-up}"

case "${mode}" in
  --logs|logs)
    require_docker_access
    compose logs -f "${LOCALNET_STATEFUL_SERVICE}"
    exit 0
    ;;
  up|--up)
    ;;
  *)
    die "localnet-start: unsupported mode '${mode}'"
    ;;
esac

require_docker_access
prepare_localnet_dirs

if [[ ! -f "${LOCALNET_HOME}/config/genesis.json" ]]; then
  "${ROOT_DIR}/deploy/localnet/scripts/init-localnet.sh"
fi

if ! docker image inspect "${LOCALNET_DOCKER_IMAGE}" >/dev/null 2>&1; then
  (cd "${ROOT_DIR}" && make docker-build >/dev/null)
fi

compose up -d "${LOCALNET_STATEFUL_SERVICE}"
"${ROOT_DIR}/deploy/localnet/scripts/wait-localnet.sh"

echo "localnet-start: PASS (${LOCALNET_STATEFUL_SERVICE})"
