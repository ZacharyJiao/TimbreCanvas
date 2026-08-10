#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-}"
if [[ -n "$MODE" && "$MODE" != "--history" ]]; then
  echo "usage: $0 [--history]" >&2
  exit 2
fi

PATTERN='(/Users/[^/[:space:]]+/|[[:alnum:]_.%+-]+@[[:alnum:].-]+[.]local([^[:alnum:]_-]|$)|BEGIN (RSA |OPENSSH |EC |DSA )?PRIVATE KEY)'
FAILED=0

scan_tree() {
  local tree="$1"
  local matches
  if matches="$(git grep -I -l -E "$PATTERN" "$tree" -- 2>/dev/null)" && [[ -n "$matches" ]]; then
    echo "Private path, local identity, or private-key material found at:"
    echo "$matches"
    FAILED=1
  fi
}

scan_tree HEAD
if [[ "$MODE" == "--history" ]]; then
  while IFS= read -r commit; do
    scan_tree "$commit"
  done < <(git rev-list --all)
fi

while IFS= read -r path; do
  lowercase_path="$(printf '%s' "$path" | tr '[:upper:]' '[:lower:]')"
  case "$lowercase_path" in
    *.safetensors|*.pth|*.pt|*.bin|*.npz|*.wav|*.mp3|*.m4a|*.pem|*.key|*.p12|*.mobileprovision)
      echo "Blocked model, audio, credential, or signing file is tracked: $path"
      FAILED=1
      ;;
  esac
done < <(git ls-files)

while IFS=$'\t' read -r metadata path; do
  size="${metadata##* }"
  if ((size > 10 * 1024 * 1024)); then
    echo "Tracked file exceeds 10 MiB: $path"
    FAILED=1
  fi
done < <(git ls-tree -r -l HEAD)

if ((FAILED)); then
  exit 1
fi
echo "Public-tree privacy and binary policy passed."
