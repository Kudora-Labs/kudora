#!/usr/bin/env bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../common.sh"

require_docker_access
require_monitoring_artifacts
require_localnet_running
mkdir -p "${MONITORING_RESULT_DIR}"

monitoring_compose up -d

echo "monitoring-up: PASS (${PROMETHEUS_UI_URL}, ${GRAFANA_UI_URL})"
