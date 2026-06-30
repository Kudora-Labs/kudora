#!/usr/bin/env bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../common.sh"

cosmovisor_prepare_dirs
release_require_docker

cosmovisor_compose down --remove-orphans >/dev/null

echo "stop-cosmovisor: PASS"
