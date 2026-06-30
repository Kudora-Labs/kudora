#!/usr/bin/env bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../common.sh"

mode="${1:-up}"

case "${mode}" in
  --logs|logs)
    require_localnet_running
    blockscout_compose logs -f
    exit 0
    ;;
  up|--up)
    ;;
  *)
    die "blockscout-start: unsupported mode '${mode}'"
    ;;
esac

require_localnet_running
blockscout_compose up -d

echo "blockscout-start: PASS (${BLOCKSCOUT_UI_URL})"
