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

SUPERVISOR_CONF="$BENCH_DIR/config/supervisor.conf"
NGINX_CONF="$BENCH_DIR/config/nginx.conf"

info() { printf '[INFO] %s\n' "$*"; }
ok() { printf '[OK] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*" >&2; }
die() { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
  SUDO=()
else
  command -v sudo >/dev/null 2>&1 || die 'sudo is required'
  sudo -n true >/dev/null 2>&1 || die 'passwordless sudo is required'
  SUDO=(sudo -n)
fi

export PATH="$HOME/.local/bin:$PATH"
export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
NODE_MAJOR="${NODE_MAJOR:-22}"
if [[ -s "$NVM_DIR/nvm.sh" ]]; then
  # shellcheck disable=SC1090
  . "$NVM_DIR/nvm.sh"
  nvm use "$NODE_MAJOR" >/dev/null 2>&1 || true
fi

NODE_BIN="$(command -v node 2>/dev/null || true)"
BENCH_BIN="$(command -v bench 2>/dev/null || true)"
[[ -x "$NODE_BIN" ]] || die 'node executable not found; load/install Node before production services'
[[ -x "$BENCH_BIN" ]] || die 'bench executable not found in PATH'
NODE_DIR="$(dirname "$NODE_BIN")"

[[ -d "$BENCH_DIR/apps/frappe" && -d "$BENCH_DIR/sites" ]] || die "invalid bench: $BENCH_DIR"

# `bench setup supervisor/nginx` prompts before overwriting an existing file.
# These are generated artifacts, so keep one recovery copy and remove the live
# generated file before regeneration to keep production deployment unattended.
for generated in "$SUPERVISOR_CONF" "$NGINX_CONF"; do
  if [[ -f "$generated" ]]; then
    cp -f "$generated" "$generated.previous"
    rm -f "$generated"
  fi
done

info 'generating fresh Bench Supervisor configuration'
(cd "$BENCH_DIR" && "$BENCH_BIN" setup supervisor)
info 'generating fresh Bench Nginx configuration'
(cd "$BENCH_DIR" && "$BENCH_BIN" setup nginx)

[[ -f "$SUPERVISOR_CONF" ]] || die "missing Supervisor config: $SUPERVISOR_CONF"
[[ -f "$NGINX_CONF" ]] || die "missing Nginx config: $NGINX_CONF"

info "patching Socket.IO Supervisor PATH with $NODE_DIR"
python3 - "$SUPERVISOR_CONF" "$NODE_DIR" "$HOME" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
node_dir = sys.argv[2]
home = sys.argv[3]
lines = path.read_text().splitlines()

section_start = None
section_end = None
for i, line in enumerate(lines):
    if line.startswith("[program:") and line.endswith("-node-socketio]"):
        section_start = i
        for j in range(i + 1, len(lines)):
            if lines[j].startswith("["):
                section_end = j
                break
        if section_end is None:
            section_end = len(lines)
        break

if section_start is None:
    raise SystemExit("node-socketio Supervisor program not found")

body = [
    line for line in lines[section_start + 1:section_end]
    if not line.startswith("environment=")
]
env = (
    f'environment=PATH="{node_dir}:{home}/.local/bin:'
    '/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",'
    f'HOME="{home}",NVM_DIR="{home}/.nvm"'
)

insert_at = 0
for i, line in enumerate(body):
    if line.startswith("command="):
        insert_at = i + 1
        break
body.insert(insert_at, env)

new_lines = lines[:section_start + 1] + body + lines[section_end:]
path.write_text("\n".join(new_lines) + "\n")
PY

info 'normalizing generated Nginx access log format for Ubuntu Nginx'
python3 - "$NGINX_CONF" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
text = path.read_text()
text = re.sub(
    r'(?m)^(\s*access_log\s+[^;\s]+)\s+main;(\s*)$',
    r'\1 combined;\2',
    text,
)
path.write_text(text)
PY

info 'installing generated production configs'
"${SUDO[@]}" ln -sfn "$SUPERVISOR_CONF" /etc/supervisor/conf.d/frappe-bench.conf
"${SUDO[@]}" ln -sfn "$NGINX_CONF" /etc/nginx/conf.d/frappe-bench.conf

# Ubuntu loads every path under sites-enabled/*, regardless of file suffix.
# Renaming `default` inside that directory therefore does NOT disable it.
# Move all current/stale default variants completely outside active include
# directories while keeping them available for recovery.
info 'disabling Ubuntu default Nginx site'
DISABLED_NGINX_DIR="/etc/nginx/ledgix-disabled"
"${SUDO[@]}" mkdir -p "$DISABLED_NGINX_DIR"
shopt -s nullglob
for path in /etc/nginx/sites-enabled/default*; do
  [[ -e "$path" || -L "$path" ]] || continue
  info "moving inactive default config out of sites-enabled: $path"
  "${SUDO[@]}" mv -f "$path" "$DISABLED_NGINX_DIR/$(basename "$path")"
done
for path in /etc/nginx/conf.d/default.conf; do
  [[ -e "$path" || -L "$path" ]] || continue
  info "moving inactive default config out of conf.d: $path"
  "${SUDO[@]}" mv -f "$path" "$DISABLED_NGINX_DIR/$(basename "$path")"
done
shopt -u nullglob

info 'enabling production services for EC2 reboot/start'
for svc in mariadb nginx supervisor; do
  "${SUDO[@]}" systemctl enable "$svc" >/dev/null
  "${SUDO[@]}" systemctl start "$svc"
done

info 'reloading Supervisor configuration'
"${SUDO[@]}" supervisorctl reread
"${SUDO[@]}" supervisorctl update

mapfile -t groups < <("${SUDO[@]}" supervisorctl status 2>/dev/null \
  | awk '/^frappe-bench-/{split($1,a,":"); print a[1]}' | sort -u)
[[ "${#groups[@]}" -gt 0 ]] || die 'no frappe-bench Supervisor groups found'
for group in "${groups[@]}"; do
  info "restarting Supervisor group $group"
  "${SUDO[@]}" supervisorctl restart "$group:"
done

info 'validating Nginx configuration'
"${SUDO[@]}" nginx -t
"${SUDO[@]}" systemctl reload nginx

sleep 2
status="$("${SUDO[@]}" supervisorctl status 2>&1 || true)"
printf '%s\n' "$status"

if printf '%s\n' "$status" | grep -E '^frappe-bench-.*(FATAL|BACKOFF|EXITED|STOPPED|UNKNOWN)' >/dev/null; then
  die 'one or more Frappe Supervisor processes are not running'
fi
if ! printf '%s\n' "$status" | grep -E '^frappe-bench-.*node-socketio.*RUNNING' >/dev/null; then
  die 'Socket.IO is not RUNNING under Supervisor'
fi

for svc in mariadb nginx supervisor; do
  "${SUDO[@]}" systemctl is-enabled "$svc" >/dev/null || die "$svc is not enabled at boot"
  "${SUDO[@]}" systemctl is-active "$svc" >/dev/null || die "$svc is not active"
done

ok 'production services are healthy and enabled for automatic boot startup'
