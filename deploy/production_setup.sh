#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Fresh bench init can leave sites/apps.txt without a trailing newline.
# Normalize it before any production action so custom apps are never appended
# as a malformed value such as "frappeledgix_saas".
if [[ -x "$SCRIPT_DIR/repair_apps_txt.sh" ]]; then
  "$SCRIPT_DIR/repair_apps_txt.sh"
elif [[ -f "$SCRIPT_DIR/repair_apps_txt.sh" ]]; then
  bash "$SCRIPT_DIR/repair_apps_txt.sh"
fi

exec "$SCRIPT_DIR/ec2_setup.sh" "$@"
