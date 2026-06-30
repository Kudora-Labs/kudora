#!/usr/bin/env bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../common.sh"

rm -rf "${BLOCKSCOUT_RESULT_DIR}"
blockscout_compose down -v --remove-orphans >/dev/null 2>&1 || true

echo "blockscout-reset: PASS"
