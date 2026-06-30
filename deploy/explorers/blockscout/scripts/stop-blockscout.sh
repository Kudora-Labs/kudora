#!/usr/bin/env bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../common.sh"

blockscout_compose down --remove-orphans >/dev/null

echo "blockscout-stop: PASS"
