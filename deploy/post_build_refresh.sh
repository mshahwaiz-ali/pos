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

export PATH="$HOME/.local/bin:$PATH"

[[ -d "$BENCH_DIR/sites" ]] || exit 0
BENCH_BIN="$(command -v bench 2>/dev/null || true)"
[[ -x "$BENCH_BIN" ]] || exit 0

printf '[INFO] refreshing site caches after asset build\n'
while IFS= read -r site; do
  [[ -n "$site" ]] || continue
  (cd "$BENCH_DIR" && "$BENCH_BIN" --site "$site" clear-cache) || true
  (cd "$BENCH_DIR" && "$BENCH_BIN" --site "$site" clear-website-cache) || true
done < <(
  find "$BENCH_DIR/sites" -mindepth 1 -maxdepth 1 -type d \
    ! -name assets ! -name archived \
    -exec test -f "{}/site_config.json" \; -printf '%f\n' 2>/dev/null | sort
)

# A running Gunicorn process can retain Frappe's previous assets manifest in
# memory after `bench build`, causing rendered HTML to reference deleted hash
# filenames. Restart production web/workers when Supervisor already owns them.
if command -v supervisorctl >/dev/null 2>&1 && sudo -n true >/dev/null 2>&1; then
  status="$(sudo -n supervisorctl status 2>/dev/null || true)"
  if printf '%s\n' "$status" | grep -q '^frappe-bench-web:'; then
    printf '[INFO] restarting Frappe web processes to load fresh asset manifest\n'
    sudo -n supervisorctl restart frappe-bench-web:
  fi
  if printf '%s\n' "$status" | grep -q '^frappe-bench-workers:'; then
    printf '[INFO] restarting Frappe workers after app build\n'
    sudo -n supervisorctl restart frappe-bench-workers:
  fi
fi

printf '[OK] post-build refresh complete\n'
