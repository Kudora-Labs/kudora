#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT
matches_file="${tmp_dir}/matches.txt"

mapfile -t production_files < <(
  find x/integrity proto/kudora/integrity \
    -type f \
    \( -name '*.go' -o -name '*.proto' \) \
    ! -name '*_test.go' \
    | sort
)

if (( ${#production_files[@]} == 0 )); then
  echo "verify-integrity-generic: no integrity production files found" >&2
  exit 1
fi

patterns=(
  "legitimate"
  "legitimateId"
  "expert"
  "projectId"
  "sectionType"
  "scoreScaled"
  "scoring"
  "orbitrum"
)

touch "${matches_file}"
for pattern in "${patterns[@]}"; do
  if rg -n --ignore-case --fixed-strings "${pattern}" "${production_files[@]}" >>"${matches_file}"; then
    :
  fi
done

if [[ -s "${matches_file}" ]]; then
  echo "verify-integrity-generic: forbidden business-specific terms found in production integrity module code" >&2
  sort -u "${matches_file}" >&2
  exit 1
fi

echo "verify-integrity-generic: PASS"
