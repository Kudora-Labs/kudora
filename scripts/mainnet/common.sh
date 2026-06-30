#!/usr/bin/env bash

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT_DIR}"

MAINNET_CHAIN_ID="kudora_12000-1"
MAINNET_BASE_DENOM="akud"
MAINNET_DISPLAY_DENOM="KUD"
MAINNET_DECIMALS="18"
MAINNET_EVM_CHAIN_ID="120001"
MAINNET_ETH_CHAIN_ID="0x1d4c1"

MAINNET_TOTAL_SUPPLY_AKUD="65100000000000000000000000"
MAINNET_ALLOCATION_1_AKUD="1310000000000000000000000"
MAINNET_ALLOCATION_2_AKUD="5200000000000000000000000"
MAINNET_COMMUNITY_POOL_AKUD="58590000000000000000000000"

MAINNET_TOTAL_SUPPLY_KUD="65100000"
MAINNET_ALLOCATION_1_KUD="1310000"
MAINNET_ALLOCATION_2_KUD="5200000"
MAINNET_COMMUNITY_POOL_KUD="58590000"

MAINNET_GOVERNANCE_CAVEAT="Standard Cosmos SDK governance voting power is stake-based. Validators vote with their own bonded stake and delegated stake unless delegators vote directly. Delegators may override validator votes depending on standard governance behavior."
MAINNET_CANDIDATE_REASON_DEFAULT="generated temporary public allocation addresses for Phase 16.1 validation"

KUDORA_BINARY="${ROOT_DIR}/build/kudorad"
MAINNET_CONFIG_DIR="${ROOT_DIR}/config/mainnet"
MAINNET_GENTX_DIR="${MAINNET_CONFIG_DIR}/gentx"
MAINNET_ALLOCATIONS_FILE_DEFAULT="${MAINNET_CONFIG_DIR}/allocations.json"
MAINNET_ALLOCATIONS_EXAMPLE_FILE="${MAINNET_CONFIG_DIR}/allocations.example.json"
MAINNET_POLICY_DOC="${MAINNET_CONFIG_DIR}/genesis-policy.md"
MAINNET_TMP_DIR="${ROOT_DIR}/tmp/mainnet-genesis"
MAINNET_TEMPLATE_HOME="${MAINNET_TMP_DIR}/template"
MAINNET_RUNTIME_HOME="${MAINNET_TMP_DIR}/runtime"
MAINNET_OUTPUT_DIR="${ROOT_DIR}/out/mainnet"
MAINNET_GENESIS_OUTPUT_PATH="${MAINNET_OUTPUT_DIR}/genesis.json"
MAINNET_METADATA_OUTPUT_PATH="${MAINNET_OUTPUT_DIR}/metadata.json"
PHASE16_BLOCKER_PATH="${ROOT_DIR}/out/phase-16-blocker.md"
PHASE161_BLOCKER_PATH="${ROOT_DIR}/out/phase-16.1-blocker.md"

mainnet_die() {
  echo "$*" >&2
  exit 1
}

mainnet_require_command() {
  command -v "$1" >/dev/null 2>&1 || mainnet_die "phase-16: required command not found: $1"
}

mainnet_require_binary() {
  [[ -x "${KUDORA_BINARY}" ]] || mainnet_die "phase-16: expected built binary at ${KUDORA_BINARY}. Run make build first."
}

mainnet_prepare_dirs() {
  mkdir -p "${ROOT_DIR}/out" "${MAINNET_OUTPUT_DIR}" "${MAINNET_TMP_DIR}" "${MAINNET_GENTX_DIR}"
}

mainnet_allocations_file() {
  if [[ -n "${KUDORA_MAINNET_ALLOCATIONS_FILE:-}" ]]; then
    printf '%s\n' "${KUDORA_MAINNET_ALLOCATIONS_FILE}"
    return 0
  fi

  printf '%s\n' "${MAINNET_ALLOCATIONS_FILE_DEFAULT}"
}

mainnet_is_default_allocations_path() {
  [[ "$(mainnet_allocations_file)" == "${MAINNET_ALLOCATIONS_FILE_DEFAULT}" ]]
}

mainnet_allocations_genesis_time() {
  jq -r '.genesis_time // empty' "$1"
}

mainnet_allocations_candidate_only() {
  jq -r '.candidate_only // false' "$1"
}

mainnet_allocations_candidate_reason() {
  jq -r '.candidate_reason // empty' "$1"
}

mainnet_module_address() {
  local module_name="$1"
  local module_hex

  module_hex="$(printf '%s' "${module_name}" | shasum -a 256 | awk '{print substr($1,1,40)}')"
  "${KUDORA_BINARY}" debug addr "${module_hex}" 2>/dev/null | awk '/Bech32 Acc/{print $3}'
}

mainnet_integer_string_valid() {
  [[ "$1" =~ ^[0-9]+$ ]]
}

mainnet_hex_placeholder_present() {
  rg -n '<[A-Z0-9_]+>' "$1" >/dev/null 2>&1
}

mainnet_bc_add() {
  printf '%s + %s\n' "$1" "$2" | bc
}

mainnet_bc_sub() {
  printf '%s - %s\n' "$1" "$2" | bc
}

mainnet_akud_to_kud() {
  printf '%s / 1000000000000000000\n' "$1" | bc
}

mainnet_join_by() {
  local separator="$1"
  shift
  local output=""
  local item

  for item in "$@"; do
    if [[ -z "${output}" ]]; then
      output="${item}"
    else
      output="${output}${separator}${item}"
    fi
  done

  printf '%s\n' "${output}"
}

mainnet_write_blocker() {
  local reason="$1"
  local details="${2:-}"

  mkdir -p "${ROOT_DIR}/out"
  {
    echo "# Phase 16 Blocker"
    echo
    echo "- Generated at: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
    echo "- Branch: $(git branch --show-current)"
    echo "- Current HEAD: $(git rev-parse HEAD)"
    echo
    echo "## Reason"
    echo
    echo "${reason}"
    if [[ -n "${details}" ]]; then
      echo
      echo "## Details"
      echo
      echo '```text'
      printf '%s\n' "${details}"
      echo '```'
    fi
  } >"${PHASE16_BLOCKER_PATH}"
}

mainnet_require_allocations_file() {
  local allocations_file
  allocations_file="$(mainnet_allocations_file)"

  if [[ ! -f "${allocations_file}" ]]; then
    if mainnet_is_default_allocations_path && [[ -f "${MAINNET_ALLOCATIONS_EXAMPLE_FILE}" ]]; then
      mainnet_write_blocker \
        "The committed mainnet allocation file is missing. Only \`config/mainnet/allocations.example.json\` is present, so the Phase 16 pipeline cannot build or validate the candidate or final mainnet genesis." \
        "Create config/mainnet/allocations.json with two valid public \`kudo...\` allocation addresses, an explicit \`genesis_time\`, and the exact Phase 16 arithmetic, then rerun the validation."
    fi
    mainnet_die "phase-16: allocations file not found at ${allocations_file}"
  fi

  if mainnet_hex_placeholder_present "${allocations_file}"; then
    mainnet_write_blocker \
      "The mainnet allocations file still contains placeholder addresses, so the Phase 16 pipeline cannot produce a candidate or final genesis." \
      "Replace the placeholder values in ${allocations_file} with two valid public \`kudo...\` addresses and keep any temporary validation addresses explicitly marked as candidate-only."
    mainnet_die "phase-16: placeholder addresses remain in ${allocations_file}"
  fi
}

mainnet_require_real_allocations() {
  mainnet_require_allocations_file
}

mainnet_validate_bech32_address() {
  local address="$1"

  [[ "${address}" == kudo1* ]] || return 1
  "${KUDORA_BINARY}" debug addr "${address}" >/dev/null 2>&1
}

mainnet_validate_genesis_time() {
  local genesis_time="$1"

  [[ "${genesis_time}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] || return 1
  jq -n --arg genesis_time "${genesis_time}" '$genesis_time | fromdateiso8601' >/dev/null 2>&1
}

mainnet_validate_allocations_json() {
  local allocations_file="$1"

  mainnet_require_command jq
  mainnet_require_command bc
  mainnet_require_binary

  jq -e . "${allocations_file}" >/dev/null || mainnet_die "phase-16: invalid JSON in ${allocations_file}"

  local chain_id genesis_time candidate_only candidate_reason denom display_denom decimals total_supply community_pool_amount allocation_count
  local allocation_1_address allocation_2_address allocation_1_amount allocation_2_amount allocation_sum total_delta
  local duplicate_addresses

  chain_id="$(jq -r '.chain_id // empty' "${allocations_file}")"
  genesis_time="$(mainnet_allocations_genesis_time "${allocations_file}")"
  candidate_only="$(mainnet_allocations_candidate_only "${allocations_file}")"
  candidate_reason="$(mainnet_allocations_candidate_reason "${allocations_file}")"
  denom="$(jq -r '.denom // empty' "${allocations_file}")"
  display_denom="$(jq -r '.display_denom // empty' "${allocations_file}")"
  decimals="$(jq -r '.decimals // empty' "${allocations_file}")"
  total_supply="$(jq -r '.total_supply // empty' "${allocations_file}")"
  community_pool_amount="$(jq -r '.community_pool.amount // empty' "${allocations_file}")"
  allocation_count="$(jq -r '.allocations | length' "${allocations_file}")"

  [[ "${chain_id}" == "${MAINNET_CHAIN_ID}" ]] || mainnet_die "phase-16: allocations chain_id must be ${MAINNET_CHAIN_ID}"
  mainnet_validate_genesis_time "${genesis_time}" || mainnet_die "phase-16: allocations genesis_time must be a valid RFC3339 UTC timestamp with Z suffix"
  [[ "${candidate_only}" == "true" || "${candidate_only}" == "false" ]] || mainnet_die "phase-16: candidate_only must be a boolean when provided"
  [[ "${denom}" == "${MAINNET_BASE_DENOM}" ]] || mainnet_die "phase-16: allocations denom must be ${MAINNET_BASE_DENOM}"
  [[ "${display_denom}" == "${MAINNET_DISPLAY_DENOM}" ]] || mainnet_die "phase-16: allocations display_denom must be ${MAINNET_DISPLAY_DENOM}"
  [[ "${decimals}" == "${MAINNET_DECIMALS}" ]] || mainnet_die "phase-16: allocations decimals must be ${MAINNET_DECIMALS}"
  [[ "${allocation_count}" == "2" ]] || mainnet_die "phase-16: exactly two mainnet allocations are required"

  if [[ "${candidate_only}" == "true" && -z "${candidate_reason}" ]]; then
    mainnet_die "phase-16: candidate_only allocations must provide a non-empty candidate_reason"
  fi

  allocation_1_address="$(jq -r '.allocations[0].address // empty' "${allocations_file}")"
  allocation_2_address="$(jq -r '.allocations[1].address // empty' "${allocations_file}")"
  allocation_1_amount="$(jq -r '.allocations[0].amount // empty' "${allocations_file}")"
  allocation_2_amount="$(jq -r '.allocations[1].amount // empty' "${allocations_file}")"

  for value_name in total_supply community_pool_amount allocation_1_amount allocation_2_amount; do
    local value
    value="${!value_name}"
    mainnet_integer_string_valid "${value}" || mainnet_die "phase-16: ${value_name} must be a non-negative integer string"
  done

  mainnet_validate_bech32_address "${allocation_1_address}" || mainnet_die "phase-16: allocation address 1 is not a valid kudo bech32 address"
  mainnet_validate_bech32_address "${allocation_2_address}" || mainnet_die "phase-16: allocation address 2 is not a valid kudo bech32 address"

  duplicate_addresses="$(
    printf '%s\n%s\n' "${allocation_1_address}" "${allocation_2_address}" | sort | uniq -d
  )"
  [[ -z "${duplicate_addresses}" ]] || mainnet_die "phase-16: duplicate mainnet allocation addresses are not allowed"

  [[ "${total_supply}" == "${MAINNET_TOTAL_SUPPLY_AKUD}" ]] || mainnet_die "phase-16: total supply must be ${MAINNET_TOTAL_SUPPLY_AKUD}"
  [[ "${community_pool_amount}" == "${MAINNET_COMMUNITY_POOL_AKUD}" ]] || mainnet_die "phase-16: community pool amount must be ${MAINNET_COMMUNITY_POOL_AKUD}"
  [[ "${allocation_1_amount}" == "${MAINNET_ALLOCATION_1_AKUD}" ]] || mainnet_die "phase-16: allocation 1 amount must be ${MAINNET_ALLOCATION_1_AKUD}"
  [[ "${allocation_2_amount}" == "${MAINNET_ALLOCATION_2_AKUD}" ]] || mainnet_die "phase-16: allocation 2 amount must be ${MAINNET_ALLOCATION_2_AKUD}"

  allocation_sum="$(mainnet_bc_add "${allocation_1_amount}" "${allocation_2_amount}")"
  total_delta="$(mainnet_bc_sub "${total_supply}" "$(mainnet_bc_add "${allocation_sum}" "${community_pool_amount}")")"
  [[ "${total_delta}" == "0" ]] || mainnet_die "phase-16: allocation arithmetic mismatch; supply delta is ${total_delta}"
}
