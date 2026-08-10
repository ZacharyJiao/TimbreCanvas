#!/usr/bin/env bash

set -euo pipefail

check_required_job() {
  local workflow=$1
  local job=$2

  if ! grep -Eq "^  ${job}:$" "$workflow"; then
    echo "Required check job '${job}' is missing from ${workflow}." >&2
    return 1
  fi

  if awk '
    /^on:[[:space:]]*$/ { in_on = 1; next }
    in_on && /^[^[:space:]]/ { in_on = 0 }
    in_on && /^[[:space:]]+(paths|paths-ignore):/ { filtered = 1 }
    END { exit filtered ? 0 : 1 }
  ' "$workflow"; then
    echo "${workflow} filters the whole workflow by path, so required check '${job}' may never be created." >&2
    return 1
  fi
}

check_required_job .github/workflows/ci.yml test
check_required_job .github/workflows/ci.yml dependency-review
check_required_job .github/workflows/security.yml repository-scan

echo "Required CI check trigger contract passed."
