#!/usr/bin/env bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../common.sh"

rm -rf "${PING_DASHBOARD_RESULT_DIR}"
ping_dashboard_compose down --remove-orphans >/dev/null 2>&1 || true

echo "ping-dashboard-reset: PASS"
