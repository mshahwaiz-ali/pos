#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Fresh bench init can leave sites/apps.txt without a trailing newline.
# Normalize it before any production action so custom apps are never appended
# as a malformed value such as "frappeledgix_saas".
if [[ -f "$SCRIPT_DIR/repair_apps_txt.sh" ]]; then
  bash "$SCRIPT_DIR/repair_apps_txt.sh"
fi

# Invoke through bash so the helper itself does not need a tracked executable
# bit. This keeps EC2 clones clean even when files were created via GitHub API.
exec bash "$SCRIPT_DIR/ec2_setup.sh" "$@"
