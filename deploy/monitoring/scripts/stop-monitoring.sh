#!/usr/bin/env bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../common.sh"

require_docker_access
require_monitoring_artifacts

monitoring_compose down --remove-orphans

echo "monitoring-down: PASS"
