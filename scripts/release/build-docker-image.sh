#!/usr/bin/env bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

release_prepare_dirs
release_require_command jq
release_require_docker
release_require_candidate_genesis

git_commit="$(release_git_commit)"
image_created="$(release_now_utc)"
primary_tag="$(release_docker_image_tag)"
alias_tag="$(release_docker_image_latest_rc_tag)"
result_path="${RELEASE_OUT_DIR}/docker-image.json"

docker buildx build \
  --load \
  --tag "${primary_tag}" \
  --tag "${alias_tag}" \
  --build-arg APP_VERSION="$(release_version_tag)" \
  --build-arg GIT_COMMIT="${git_commit}" \
  --build-arg BUILD_TAGS="release,candidate,docker" \
  --build-arg IMAGE_CREATED="${image_created}" \
  --build-arg RELEASE_TRACK="${RELEASE_TRACK}" \
  --build-arg MAINNET_LAUNCH_READY="false" \
  --file "${ROOT_DIR}/Dockerfile" \
  "${ROOT_DIR}" >/dev/null

jq -n \
  --arg built_at_utc "${image_created}" \
  --arg primary_tag "${primary_tag}" \
  --arg alias_tag "${alias_tag}" \
  --arg image_id "$(docker image inspect "${primary_tag}" --format '{{.Id}}')" \
  --arg image_size_bytes "$(docker image inspect "${primary_tag}" --format '{{.Size}}')" \
  '{
    built_at_utc: $built_at_utc,
    primary_tag: $primary_tag,
    alias_tag: $alias_tag,
    image_id: $image_id,
    image_size_bytes: ($image_size_bytes | tonumber)
  }' >"${result_path}"

echo "release-docker-build: PASS (${primary_tag})"
