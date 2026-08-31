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

find_action() {
  local args=("$@") i
  for ((i = 0; i < ${#args[@]}; i++)); do
    if [[ "${args[$i]}" == "--action" && $((i + 1)) -lt ${#args[@]} ]]; then
      printf '%s\n' "${args[$((i + 1))]}"
      return 0
    fi
  done
  printf '\n'
}

run_ec2() {
  bash "$SCRIPT_DIR/ec2_setup.sh" "$@"
}

start_temp_redis() {
  [[ -f "$SCRIPT_DIR/bench_redis.sh" ]] || return 0
  bash "$SCRIPT_DIR/bench_redis.sh" start
}

stop_temp_redis() {
  [[ -f "$SCRIPT_DIR/bench_redis.sh" ]] || return 0
  bash "$SCRIPT_DIR/bench_redis.sh" stop || true
}

run_services() {
  [[ -f "$SCRIPT_DIR/production_services_fix.sh" ]] || {
    printf '[ERROR] missing production services helper: %s\n' "$SCRIPT_DIR/production_services_fix.sh" >&2
    return 1
  }
  bash "$SCRIPT_DIR/production_services_fix.sh"
}

post_build_refresh() {
  [[ -f "$SCRIPT_DIR/post_build_refresh.sh" ]] || return 0
  bash "$SCRIPT_DIR/post_build_refresh.sh"
}

run_safe_backup() {
  [[ -f "$SCRIPT_DIR/backup_safe.sh" ]] || {
    printf '[ERROR] missing backup helper: %s\n' "$SCRIPT_DIR/backup_safe.sh" >&2
    return 1
  }
  bash "$SCRIPT_DIR/backup_safe.sh"
}

run_safe_deploy_update() {
  [[ -f "$SCRIPT_DIR/deploy_update_safe.sh" ]] || {
    printf '[ERROR] missing deploy update helper: %s\n' "$SCRIPT_DIR/deploy_update_safe.sh" >&2
    return 1
  }
  bash "$SCRIPT_DIR/deploy_update_safe.sh"
}

ACTION="$(find_action "$@")"

# Ledgix demo/server convention: keep the Administrator password simple unless
# the caller explicitly supplies FRAPPE_ADMIN_PASSWORD. This can be overridden
# at any time for a hardened client deployment.
if [[ "$ACTION" == "site" || "$ACTION" == "full" ]]; then
  export FRAPPE_ADMIN_PASSWORD="${FRAPPE_ADMIN_PASSWORD:-admin}"
fi

# Route site backup directly by explicit site name. This avoids Bash nameref
# edge cases with dotted Frappe site names such as ledgix.local.
if [[ "$ACTION" == "backup" ]]; then
  run_safe_backup
  exit $?
fi

# Production updates need an exact app mirror because V2 intentionally deletes
# legacy pages/assets. A plain cp-over-existing-tree would leave removed files
# behind, so deploy-update uses the dedicated exact-sync helper.
if [[ "$ACTION" == "deploy-update" ]]; then
  run_safe_deploy_update
  exit $?
fi

# Site creation/install/migrate can need the bench Redis cache/queue even
# before Supervisor has been configured. Start only the missing bench Redis
# instances temporarily and stop only the processes that this helper started.
if [[ "$ACTION" == "site" ]]; then
  trap stop_temp_redis EXIT
  start_temp_redis
  run_ec2 "$@"
  exit $?
fi

# App builds can produce new hashed Frappe assets. If production processes are
# already running, refresh caches and restart web/workers so rendered HTML does
# not keep referencing stale asset hashes.
if [[ "$ACTION" == "apps" ]]; then
  run_ec2 "$@"
  post_build_refresh
  exit $?
fi

# Production services are generated, patched, installed and validated in one
# pass. This adds the nvm Node PATH for Socket.IO, normalizes the Ubuntu Nginx
# access-log format, and verifies automatic boot startup.
if [[ "$ACTION" == "services" ]]; then
  run_services
  exit $?
fi

# Keep the one-command full flow safe as well: run the phases in order, with
# temporary bench Redis only around site creation. This avoids a later port
# conflict when Supervisor takes ownership of the Redis processes.
if [[ "$ACTION" == "full" ]]; then
  original=("$@")
  base=()
  for ((i = 0; i < ${#original[@]}; i++)); do
    if [[ "${original[$i]}" == "--action" && $((i + 1)) -lt ${#original[@]} && "${original[$((i + 1))]}" == "full" ]]; then
      i=$((i + 1))
      continue
    fi
    base+=("${original[$i]}")
  done

  run_ec2 "${base[@]}" --action preflight
  run_ec2 "${base[@]}" --action packages
  run_ec2 "${base[@]}" --action bench
  run_ec2 "${base[@]}" --action apps
  post_build_refresh

  trap stop_temp_redis EXIT
  start_temp_redis
  run_ec2 "${base[@]}" --action site
  stop_temp_redis
  trap - EXIT

  run_services
  if [[ -n "${PRODUCTION_DOMAIN:-}" && -n "${LETSENCRYPT_EMAIL:-}" ]]; then
    run_ec2 "${base[@]}" --action ssl
  fi
  run_ec2 "${base[@]}" --action status
  exit 0
fi

# Invoke through bash so the helper itself does not need a tracked executable
# bit. This keeps EC2 clones clean even when files were created via GitHub API.
exec bash "$SCRIPT_DIR/ec2_setup.sh" "$@"
