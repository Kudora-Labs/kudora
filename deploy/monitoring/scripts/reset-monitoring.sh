#!/usr/bin/env bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../common.sh"

require_docker_access
require_monitoring_artifacts

rm -rf "${MONITORING_RESULT_DIR}"
monitoring_compose down --volumes --remove-orphans

echo "monitoring-reset: PASS"
