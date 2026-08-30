#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Production actions run in fresh non-login shells on EC2. Node is installed
# with nvm, so explicitly load the selected Node version before invoking any
# bench command. Frappe's build subprocesses inherit this PATH.
export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
NODE_MAJOR="${NODE_MAJOR:-22}"
if [[ -s "$NVM_DIR/nvm.sh" ]]; then
  # shellcheck disable=SC1090
  . "$NVM_DIR/nvm.sh"
  nvm use "$NODE_MAJOR" >/dev/null 2>&1 || true
fi

# Fresh bench init can leave sites/apps.txt without a trailing newline.
# Normalize it before any production action so custom apps are never appended
# as a malformed value such as "frappeledgix_saas".
if [[ -f "$SCRIPT_DIR/repair_apps_txt.sh" ]]; then
  bash "$SCRIPT_DIR/repair_apps_txt.sh"
fi

# Invoke through bash so the helper itself does not need a tracked executable
# bit. This keeps EC2 clones clean even when files were created via GitHub API.
exec bash "$SCRIPT_DIR/ec2_setup.sh" "$@"
