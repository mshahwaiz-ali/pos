#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BENCH_DIR="${BENCH_DIR:-$REPO_ROOT/frappe-bench}"
SITE="${PRODUCTION_SITE:-ledgix.local}"

export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"

[[ "$SITE" =~ ^[a-z0-9][a-z0-9.-]*$ ]] || { echo "[ERROR] invalid site name: $SITE" >&2; exit 1; }
[[ -f "$BENCH_DIR/sites/$SITE/site_config.json" ]] || { echo "[ERROR] site not found: $SITE" >&2; exit 1; }
command -v bench >/dev/null 2>&1 || { echo '[ERROR] bench is not available in PATH' >&2; exit 1; }

printf '\n===== BACKUP %s =====\n' "$SITE"
(
  cd "$BENCH_DIR"
  bench --site "$SITE" backup --with-files
)

printf '\n===== LATEST BACKUP FILES =====\n'
find "$BENCH_DIR/sites/$SITE/private/backups" -maxdepth 1 -type f -printf '%TY-%Tm-%Td %TH:%TM  %10s  %f\n' \
  | sort \
  | tail -n 8

printf '[OK] backup complete: %s\n' "$SITE"
