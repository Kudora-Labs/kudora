#!/usr/bin/env bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../common.sh"

mode="${1:-up}"

case "${mode}" in
  --logs|logs)
    require_localnet_running
    ping_dashboard_compose logs -f
    exit 0
    ;;
  up|--up)
    ;;
  *)
    die "ping-dashboard-start: unsupported mode '${mode}'"
    ;;
esac

require_localnet_running
ping_dashboard_compose up -d --build

echo "ping-dashboard-start: PASS (${PING_DASHBOARD_UI_URL})"
