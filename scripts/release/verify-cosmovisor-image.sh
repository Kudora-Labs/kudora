#!/usr/bin/env bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

release_prepare_dirs
release_require_command jq
release_require_docker

cosmovisor_image_tag="$(release_cosmovisor_image_tag)"
result_path="${RELEASE_OUT_DIR}/cosmovisor-image-verify.json"

docker image inspect "${cosmovisor_image_tag}" >/dev/null 2>&1 \
  || release_die "phase-17: cosmovisor image missing; run make cosmovisor-image-build first"

config_user="$(docker image inspect "${cosmovisor_image_tag}" --format '{{.Config.User}}')"
[[ -n "${config_user}" && "${config_user}" != "0" && "${config_user}" != "root" ]] \
  || release_die "phase-17: cosmovisor image must run as a non-root user"

env_json="$(docker image inspect "${cosmovisor_image_tag}" --format '{{json .Config.Env}}')"
printf '%s\n' "${env_json}" | jq -e '
  index("DAEMON_NAME=kudorad") and
  index("DAEMON_HOME=/home/nonroot/.kudora") and
  index("DAEMON_RESTART_AFTER_UPGRADE=true") and
  index("DAEMON_ALLOW_DOWNLOAD_BINARIES=false") and
  index("UNSAFE_SKIP_BACKUP=false")
' >/dev/null || release_die "phase-17: cosmovisor image default environment is incomplete"

docker run --rm --entrypoint /usr/local/bin/cosmovisor "${cosmovisor_image_tag}" --help >/dev/null 2>&1 \
  || release_die "phase-17: cosmovisor image failed 'cosmovisor --help'"
docker run --rm --entrypoint /usr/local/bin/kudorad "${cosmovisor_image_tag}" version >/dev/null 2>&1 \
  || release_die "phase-17: cosmovisor image failed 'kudorad version'"

container_id="$(docker create "${cosmovisor_image_tag}")"
cleanup() {
  docker rm -f "${container_id}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

docker export "${container_id}" | tar -tf - | rg -n '(^|/)usr/local/bin/cosmovisor$' >/dev/null \
  || release_die "phase-17: cosmovisor binary missing from image filesystem"
docker export "${container_id}" | tar -tf - | rg -n '(^|/)usr/local/bin/kudorad$' >/dev/null \
  || release_die "phase-17: kudorad binary missing from cosmovisor image filesystem"
docker export "${container_id}" | tar -tf - | rg -n '(^|/)usr/lib/libwasmvm\.(x86_64|aarch64)\.so$' >/dev/null \
  || release_die "phase-17: wasmvm runtime libraries missing from cosmovisor image"

jq -n \
  --arg verified_at_utc "$(release_now_utc)" \
  --arg image_tag "${cosmovisor_image_tag}" \
  --arg user "${config_user}" \
  --arg cosmovisor_help_output "$(docker run --rm --entrypoint /usr/local/bin/cosmovisor "${cosmovisor_image_tag}" --help 2>&1)" \
  '{
    verified_at_utc: $verified_at_utc,
    image_tag: $image_tag,
    user: $user,
    cosmovisor_help_output: $cosmovisor_help_output,
    non_root: true
  }' >"${result_path}"

echo "verify-cosmovisor-image: PASS (${cosmovisor_image_tag})"
