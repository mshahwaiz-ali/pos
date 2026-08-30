#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BENCH_DIR_INPUT="${BENCH_DIR:-./frappe-bench}"
case "$BENCH_DIR_INPUT" in
  /*) BENCH_DIR="$BENCH_DIR_INPUT" ;;
  ./*) BENCH_DIR="$REPO_ROOT/${BENCH_DIR_INPUT#./}" ;;
  *) BENCH_DIR="$REPO_ROOT/$BENCH_DIR_INPUT" ;;
esac

APPS_TXT="$BENCH_DIR/sites/apps.txt"
APPS_DIR="$BENCH_DIR/apps"

[[ -d "$APPS_DIR" ]] || exit 0
[[ -d "$BENCH_DIR/sites" ]] || exit 0

# Rebuild apps.txt from actual bench app directories instead of appending to a
# potentially non-newline-terminated file. This prevents values such as
# "frappeledgix_saas" from being created after a fresh bench init.
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

if [[ -d "$APPS_DIR/frappe" ]]; then
  printf 'frappe\n' >>"$tmp"
fi

find "$APPS_DIR" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null \
  | grep -v '^frappe$' \
  | sort -u >>"$tmp" || true

# Keep only plausible Frappe app package names and de-duplicate while
# preserving frappe first.
awk '/^[A-Za-z_][A-Za-z0-9_]*$/ && !seen[$0]++' "$tmp" >"$tmp.clean"
mv "$tmp.clean" "$tmp"

if [[ -s "$tmp" ]]; then
  if [[ ! -f "$APPS_TXT" ]] || ! cmp -s "$tmp" "$APPS_TXT"; then
    cp "$tmp" "$APPS_TXT"
    printf '[OK] repaired %s\n' "$APPS_TXT"
  fi
fi
