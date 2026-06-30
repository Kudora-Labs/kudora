#!/usr/bin/env bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

release_prepare_dirs
release_require_command jq
release_require_docker

release_image_tag="$(release_docker_image_tag)"
cosmovisor_image_tag="$(release_cosmovisor_image_tag)"

docker image inspect "${release_image_tag}" >/dev/null 2>&1 \
  || release_die "phase-17: candidate release image missing; run make release-docker-build first"

docker buildx build \
  --load \
  --tag "${cosmovisor_image_tag}" \
  --build-arg RELEASE_IMAGE="${release_image_tag}" \
  --build-arg COSMOVISOR_VERSION="${COSMOVISOR_VERSION}" \
  --build-arg RELEASE_VERSION="$(release_version_tag)" \
  --build-arg GIT_COMMIT="$(release_git_commit)" \
  --file "${ROOT_DIR}/deploy/cosmovisor/Dockerfile" \
  "${ROOT_DIR}" >/dev/null

jq -n \
  --arg built_at_utc "$(release_now_utc)" \
  --arg image_tag "${cosmovisor_image_tag}" \
  --arg image_id "$(docker image inspect "${cosmovisor_image_tag}" --format '{{.Id}}')" \
  --arg image_size_bytes "$(docker image inspect "${cosmovisor_image_tag}" --format '{{.Size}}')" \
  --arg cosmovisor_version "${COSMOVISOR_VERSION}" \
  '{
    built_at_utc: $built_at_utc,
    image_tag: $image_tag,
    image_id: $image_id,
    image_size_bytes: ($image_size_bytes | tonumber),
    cosmovisor_version: $cosmovisor_version
  }' >"${RELEASE_OUT_DIR}/cosmovisor-image.json"

echo "cosmovisor-image-build: PASS (${cosmovisor_image_tag})"
