#!/usr/bin/env bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

release_prepare_dirs
release_require_command jq
release_require_docker

primary_tag="$(release_docker_image_tag)"
alias_tag="$(release_docker_image_latest_rc_tag)"
result_path="${RELEASE_OUT_DIR}/docker-verify.json"

docker image inspect "${primary_tag}" >/dev/null 2>&1 || release_die "phase-17: candidate release image missing: ${primary_tag}"
docker image inspect "${alias_tag}" >/dev/null 2>&1 || release_die "phase-17: candidate release alias image missing: ${alias_tag}"

primary_id="$(docker image inspect "${primary_tag}" --format '{{.Id}}')"
alias_id="$(docker image inspect "${alias_tag}" --format '{{.Id}}')"
[[ "${primary_id}" == "${alias_id}" ]] || release_die "phase-17: candidate Docker tags do not point to the same image"

config_user="$(docker image inspect "${primary_tag}" --format '{{.Config.User}}')"
[[ -n "${config_user}" && "${config_user}" != "0" && "${config_user}" != "root" ]] \
  || release_die "phase-17: candidate release image must run as a non-root user"

docker image inspect "${primary_tag}" --format '{{json .Config.Labels}}' >"${RELEASE_DOCKER_TMP_DIR}/docker-labels.json"
jq -e \
  --arg version "$(release_version_tag)" \
  --arg revision "$(release_git_commit)" \
  --arg track "${RELEASE_TRACK}" \
  '
    ."org.opencontainers.image.version" == $version and
    ."org.opencontainers.image.revision" == $revision and
    ."io.kudora.release_track" == $track and
    ."io.kudora.mainnet_launch_ready" == "false"
  ' "${RELEASE_DOCKER_TMP_DIR}/docker-labels.json" >/dev/null \
  || release_die "phase-17: candidate release image labels are incomplete"

docker run --rm "${primary_tag}" version >/dev/null 2>&1 \
  || release_die "phase-17: candidate release image failed 'kudorad version'"
docker run --rm "${primary_tag}" start --help >/dev/null 2>&1 \
  || release_die "phase-17: candidate release image failed 'kudorad start --help'"

ports="$(docker image inspect "${primary_tag}" --format '{{json .Config.ExposedPorts}}')"
for required_port in 26656 26657 1317 9090 8545 8546; do
  printf '%s\n' "${ports}" | rg -n "\"${required_port}/tcp\"" >/dev/null \
    || release_die "phase-17: candidate release image is missing exposed port ${required_port}/tcp"
done

container_id="$(docker create "${primary_tag}")"
cleanup() {
  docker rm -f "${container_id}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

docker export "${container_id}" | tar -tf - | rg -n '(^|/)\.kudora/|(^|/)\.env(\..*)?$|(^|/)priv_validator_key\.json$|(^|/)node_key\.json$|(^|/)key_seed\.json$|\.pem$|\.key$|\.seed$|\.mnemonic$' >/dev/null \
  && release_die "phase-17: forbidden local state or secret-bearing files found in candidate release image" || true

jq -n \
  --arg verified_at_utc "$(release_now_utc)" \
  --arg primary_tag "${primary_tag}" \
  --arg alias_tag "${alias_tag}" \
  --arg image_id "${primary_id}" \
  --arg image_size_bytes "$(docker image inspect "${primary_tag}" --format '{{.Size}}')" \
  --arg user "${config_user}" \
  '{
    verified_at_utc: $verified_at_utc,
    primary_tag: $primary_tag,
    alias_tag: $alias_tag,
    image_id: $image_id,
    image_size_bytes: ($image_size_bytes | tonumber),
    user: $user,
    non_root: true
  }' >"${result_path}"

echo "release-docker-verify: PASS (${primary_tag})"
