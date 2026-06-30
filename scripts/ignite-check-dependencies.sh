#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

temp_home="$(mktemp -d)"
trap 'rm -rf "$temp_home"' EXIT

original_gopath="$(go env GOPATH)"
original_gomodcache="$(go env GOMODCACHE)"
original_gocache="$(go env GOCACHE)"

HOME="$temp_home" \
GOPATH="$original_gopath" \
GOMODCACHE="$original_gomodcache" \
GOCACHE="$original_gocache" \
DO_NOT_TRACK=1 \
CI=true \
ignite chain build --check-dependencies
