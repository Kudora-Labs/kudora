#!/usr/bin/env bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../common.sh"

ping_dashboard_compose down --remove-orphans >/dev/null

echo "ping-dashboard-stop: PASS"
