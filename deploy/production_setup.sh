#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
LOG_DIR="$REPO_ROOT/logs/deploy"
LOG_FILE="$LOG_DIR/production-setup-$TIMESTAMP.log"
SECRETS_FILE="$SCRIPT_DIR/production.secrets.md"
BACKUPS_INDEX="$SCRIPT_DIR/backups-index.md"
APPS_SRC="${APPS_SRC:-$REPO_ROOT/apps}"

DEFAULT_REPO_URL="${DEFAULT_REPO_URL:-https://github.com/mshahwaiz-ali/pos.git}"
FRAPPE_BRANCH="${FRAPPE_BRANCH:-version-15}"
NODE_MAJOR="${NODE_MAJOR:-22}"
NVM_INSTALL_VERSION="${NVM_INSTALL_VERSION:-v0.40.3}"
BENCH_DIR_INPUT="${BENCH_DIR:-./frappe-bench}"
case "$BENCH_DIR_INPUT" in
  /*) BENCH_DIR="$BENCH_DIR_INPUT" ;;
  ./*) BENCH_DIR="$REPO_ROOT/${BENCH_DIR_INPUT#./}" ;;
  *) BENCH_DIR="$REPO_ROOT/$BENCH_DIR_INPUT" ;;
esac

DRY_RUN=0
ASSUME_YES=0
ACTION=""
SUDO=()

export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
export PIPX_BIN_DIR="$HOME/.local/bin"
export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"

mkdir -p "$LOG_DIR"
exec > >(tee -a "$LOG_FILE") 2>&1

info() { printf '[INFO] %s\n' "$*"; }
ok() { printf '[OK] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*" >&2; }
err() { printf '[ERROR] %s\n' "$*" >&2; }
die() { err "$*"; err "Log file: $LOG_FILE"; exit 1; }

trap 'rc=$?; err "Failed at line $LINENO: $BASH_COMMAND"; err "Log file: $LOG_FILE"; exit "$rc"' ERR

section() {
  printf '\n'
  printf '==================================================\n'
  printf ' %s\n' "$*"
  printf '==================================================\n'
}

usage() {
  cat <<EOF
Usage: deploy/production_setup.sh [options]

Production EC2/server deployment helper for this Frappe repo.

Options:
  --dry-run           Print intended changes without running mutating commands
  --yes              Accept safe default confirmations where possible
  --action ACTION    Run one action without the menu
                     Actions: full, preflight, packages, bench, apps, site,
                              services, ssl, backup, deploy-update, status
  --help, -h         Show this help

Environment defaults:
  DEFAULT_REPO_URL   Default: $DEFAULT_REPO_URL
  FRAPPE_BRANCH      Default: $FRAPPE_BRANCH
  NODE_MAJOR         Default: $NODE_MAJOR
  BENCH_DIR          Default: ./frappe-bench
  PRODUCTION_DOMAIN  Required for non-interactive site/SSL setup
  PRODUCTION_SITE    Defaults to lowercased production domain
  LETSENCRYPT_EMAIL  Required for non-interactive SSL setup
  APP_NAME           App to install when multiple importable apps exist
EOF
}

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

resolve_cmd() {
  local cmd="$1"
  command -v "$cmd" 2>/dev/null || true
}

refresh_path() {
  export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
  export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
  if [[ -s "$NVM_DIR/nvm.sh" ]]; then
    # shellcheck disable=SC1090
    . "$NVM_DIR/nvm.sh"
    nvm use "$NODE_MAJOR" >/dev/null 2>&1 || true
  fi
}

run_cmd() {
  info "[RUN] $*"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    return 0
  fi
  "$@"
}

run_cmd_label() {
  local label="$1"
  shift
  info "[RUN] $label"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    return 0
  fi
  "$@"
}

bench_cmd() {
  local b
  b="$(resolve_cmd bench)"
  if [[ -z "$b" ]]; then
    die "bench command not found in current user PATH. Run installer first."
  fi
  printf '%s\n' "$b"
}

run_bench() {
  local b
  b="$(bench_cmd)"
  info "[RUN] bench $*"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    return 0
  fi
  (cd "$BENCH_DIR" && "$b" "$@")
}

run_bench_label() {
  local label="$1"
  local b
  shift
  b="$(bench_cmd)"
  info "[RUN] $label"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    return 0
  fi
  (cd "$BENCH_DIR" && "$b" "$@")
}

status_ok() { printf '[OK] %s\n' "$*"; }
status_warn() { printf '[WARN] %s\n' "$*"; }
status_error() { printf '[ERROR] %s\n' "$*"; }

need_sudo() {
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    SUDO=()
    return 0
  fi
  have_cmd sudo || die "sudo is required for production setup"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    SUDO=(sudo)
    return 0
  fi
  sudo -v || die "sudo permission is required"
  SUDO=(sudo)
}

sudo_available_noninteractive() {
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    return 0
  fi
  have_cmd sudo || return 1
  sudo -n true >/dev/null 2>&1
}

sudo_env_cmd() {
  local sudo_user
  need_sudo || die "sudo required"
  sudo_user="${USER:-$(id -un)}"
  info "[RUN] sudo env PATH=$PATH HOME=$HOME USER=$sudo_user $*"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    return 0
  fi
  "${SUDO[@]}" env \
    "PATH=$PATH" \
    "HOME=$HOME" \
    "USER=$sudo_user" \
    "$@"
}

sudo_bench() {
  local b
  b="$(bench_cmd)"
  sudo_env_cmd "$b" "$@"
}

validate_sudo_bench_for_production() {
  local b
  b="$(bench_cmd)"
  info "Detected bench path: $b"
  if ! run_bench --version; then
    die "bench --version failed for detected bench path: $b"
  fi
  if ! sudo_bench --version; then
    err "sudo cannot execute bench with the current PATH. Check bench installation or sudo secure_path."
    err "Detected bench path: $b"
    die "sudo bench validation failed"
  fi
}

run_sudo_status() {
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    "$@"
  elif sudo_available_noninteractive; then
    sudo "$@"
  else
    "$@"
  fi
}

confirm() {
  local prompt="$1"
  local default="${2:-N}"
  local answer suffix
  if [[ "$ASSUME_YES" -eq 1 ]]; then
    info "Assuming yes: $prompt"
    return 0
  fi
  if [[ "$default" =~ ^[Yy]$ ]]; then
    suffix='Y/n'
  else
    suffix='y/N'
  fi
  read -r -p "$prompt [$suffix]: " answer
  answer="${answer:-$default}"
  case "$answer" in
    y|Y|yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

exact_confirm() {
  local phrase="$1"
  local prompt="$2"
  local answer
  if [[ "$DRY_RUN" -eq 1 ]]; then
    warn "$prompt"
    warn "Dry run: continuing without exact confirmation because no changes will be made."
    return 0
  fi
  printf '%s\n' "$prompt"
  read -r -p "Type '$phrase' to continue: " answer
  [[ "$answer" == "$phrase" ]]
}

prompt_value() {
  local -n _out="$1"
  local prompt="$2"
  local default="${3:-}"
  local required="${4:-0}"
  local answer
  if [[ "$ASSUME_YES" -eq 1 ]]; then
    if [[ -n "$default" ]]; then
      _out="$default"
      info "$prompt: $default"
      return 0
    fi
    [[ "$required" -eq 0 ]] || die "$prompt is required for --yes mode"
  fi
  if [[ -n "$default" ]]; then
    read -r -p "$prompt [$default]: " answer
    _out="${answer:-$default}"
  else
    while true; do
      read -r -p "$prompt: " answer
      if [[ -n "$answer" || "$required" -eq 0 ]]; then
        _out="$answer"
        break
      fi
      warn "value is required"
    done
  fi
}

prompt_secret() {
  local -n _out="$1"
  local prompt="$2"
  local required="${3:-1}"
  local answer
  if [[ "$ASSUME_YES" -eq 1 ]]; then
    die "$prompt is required for --yes mode"
  fi
  while true; do
    read -r -s -p "$prompt: " answer
    printf '\n'
    if [[ -n "$answer" || "$required" -eq 0 ]]; then
      _out="$answer"
      break
    fi
    warn "value is required"
  done
}

now_iso() {
  date '+%Y-%m-%d %H:%M:%S %z'
}

lowercase() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

random_hex() {
  local bytes="$1"
  if have_cmd openssl; then
    openssl rand -hex "$bytes"
  else
    warn "openssl is missing; using a weaker random fallback"
    date +%s%N | sha256sum | cut -c "1-$((bytes * 2))"
  fi
}

strong_password() {
  if have_cmd openssl; then
    openssl rand -base64 42 | tr -d '\n' | cut -c 1-40
  else
    warn "openssl is missing; using a weaker random fallback"
    printf '%s%s' "$(date +%s%N)" "$RANDOM" | sha256sum | cut -c 1-40
  fi
}

safe_db_name() {
  [[ -n "$1" && "$1" =~ ^[A-Za-z0-9_]+$ ]]
}

sql_quote() {
  printf "%s" "$1" | sed "s/'/''/g"
}

sql_identifier() {
  printf "%s" "$1" | sed 's/`/``/g'
}

make_db_name() {
  printf 'site_%s' "$(random_hex 8)"
}

make_db_password() {
  strong_password
}

detect_public_ip() {
  have_cmd curl || return 1
  curl -fsS --max-time 4 https://ifconfig.me 2>/dev/null ||
    curl -fsS --max-time 4 https://api.ipify.org 2>/dev/null
}

detect_private_ips() {
  hostname -I 2>/dev/null | awk '{$1=$1; print}' || true
}

detect_ec2_instance_id() {
  have_cmd curl || return 1
  curl -fsS --max-time 1 http://169.254.169.254/latest/meta-data/instance-id 2>/dev/null
}

git_is_repo() {
  git -C "$REPO_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1
}

git_branch() {
  if git_is_repo; then
    git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || printf 'main'
  else
    printf 'main'
  fi
}

git_remote_url() {
  if git_is_repo && git -C "$REPO_ROOT" remote get-url origin >/dev/null 2>&1; then
    git -C "$REPO_ROOT" remote get-url origin
  else
    printf '%s' "$DEFAULT_REPO_URL"
  fi
}

git_dirty_status() {
  git_is_repo || return 0
  git -C "$REPO_ROOT" status --short
}

valid_bench() {
  [[ -d "$BENCH_DIR/apps" ]] || return 1
  [[ -d "$BENCH_DIR/apps/frappe" ]] || return 1
  [[ -d "$BENCH_DIR/sites" ]] || return 1
  [[ -x "$BENCH_DIR/env/bin/python" ]] || return 1
  [[ -f "$BENCH_DIR/Procfile" ]] || return 1
  [[ -f "$BENCH_DIR/sites/common_site_config.json" ]] || return 1
}

require_valid_bench() {
  valid_bench || die "valid Frappe bench not found at $BENCH_DIR. Run setup/validate bench first."
}

site_names() {
  [[ -d "$BENCH_DIR/sites" ]] || return 0
  find "$BENCH_DIR/sites" -mindepth 1 -maxdepth 1 -type d \
    ! -name assets ! -name archived \
    -exec test -f "{}/site_config.json" \; -printf "%f\n" 2>/dev/null | sort
}

app_name_from_dir() {
  basename "$1"
}

is_system_app() {
  case "$1" in
    frappe|erpnext|payments|hrms|print_designer) return 0 ;;
    *) return 1 ;;
  esac
}

valid_custom_app_dir() {
  local dir="$1"
  local hook
  [[ -d "$dir" ]] || return 1
  if [[ -f "$dir/hooks.py" && -f "$dir/__init__.py" ]]; then
    return 0
  fi
  for hook in "$dir"/*/hooks.py; do
    [[ -f "$hook" ]] || continue
    if [[ -f "$(dirname "$hook")/__init__.py" ]]; then
      return 0
    fi
  done
  return 1
}

has_package_metadata() {
  local dir="$1"
  [[ -f "$dir/pyproject.toml" || -f "$dir/setup.py" || -f "$dir/setup.cfg" ]]
}

discover_source_apps() {
  [[ -d "$APPS_SRC" ]] || return 0
  local dir name
  for dir in "$APPS_SRC"/*; do
    [[ -d "$dir" ]] || continue
    name="$(app_name_from_dir "$dir")"
    is_system_app "$name" && continue
    if valid_custom_app_dir "$dir"; then
      printf '%s\n' "$name"
    else
      warn "invalid custom app folder, skipping: $name"
    fi
  done | sort
}

discover_bench_custom_apps() {
  [[ -d "$BENCH_DIR/apps" ]] || return 0
  local dir name
  for dir in "$BENCH_DIR/apps"/*; do
    [[ -d "$dir" ]] || continue
    name="$(app_name_from_dir "$dir")"
    is_system_app "$name" && continue
    valid_custom_app_dir "$dir" || continue
    printf '%s\n' "$name"
  done | sort
}

ensure_app_importable() {
  local app="$1"
  local app_dir="$BENCH_DIR/apps/$app"
  [[ -d "$app_dir" ]] || return 1
  [[ "$app" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || {
    warn "app name is not a valid Python import name: $app"
    return 1
  }
  if has_package_metadata "$app_dir"; then
    run_cmd_label "./env/bin/python -m pip install -e apps/$app" \
      "$BENCH_DIR/env/bin/python" -m pip install -e "$app_dir" >/dev/null
  else
    warn "No package metadata found for app: $app"
  fi
  PYTHONDONTWRITEBYTECODE=1 "$BENCH_DIR/env/bin/python" -c "import importlib; importlib.import_module('$app')" >/dev/null 2>&1
}

importable_bench_apps() {
  local app
  while IFS= read -r app; do
    [[ -n "$app" ]] || continue
    if ensure_app_importable "$app"; then
      printf '%s\n' "$app"
    else
      warn "import test failed; app will not be selectable: $app"
    fi
  done < <(discover_bench_custom_apps)
}

detect_importable_bench_apps_no_install() {
  [[ -x "$BENCH_DIR/env/bin/python" ]] || return 0
  local app
  while IFS= read -r app; do
    [[ -n "$app" ]] || continue
    if PYTHONDONTWRITEBYTECODE=1 "$BENCH_DIR/env/bin/python" -c "import importlib; importlib.import_module('$app')" >/dev/null 2>&1; then
      printf '%s\n' "$app"
    fi
  done < <(discover_bench_custom_apps)
}

ensure_app_in_apps_txt() {
  local app="$1"
  local apps_txt="$BENCH_DIR/sites/apps.txt"
  [[ -f "$apps_txt" ]] || run_cmd_label "create $apps_txt" touch "$apps_txt"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    grep -Fxq "$app" "$apps_txt" 2>/dev/null || info "[DRY-RUN] would add $app to sites/apps.txt"
    return 0
  fi
  grep -Fxq "$app" "$apps_txt" 2>/dev/null && return 0
  if [[ -s "$apps_txt" && "$(tail -c 1 "$apps_txt" 2>/dev/null || true)" != "" ]]; then
    printf '\n' >>"$apps_txt"
  fi
  printf '%s\n' "$app" >>"$apps_txt"
  ok "registered app in sites/apps.txt: $app"
}

ensure_custom_app_assets() {
  require_valid_bench
  run_cmd mkdir -p "$BENCH_DIR/sites/assets"
  local app public_dir asset_link target
  while IFS= read -r app; do
    [[ -n "$app" ]] || continue
    public_dir="$BENCH_DIR/apps/$app/public"
    asset_link="$BENCH_DIR/sites/assets/$app"
    [[ -d "$public_dir" ]] || continue
    if [[ -L "$asset_link" ]]; then
      target="$(readlink "$asset_link" 2>/dev/null || true)"
      if [[ "$target" == "$public_dir" ]]; then
        info "asset link ok: $app"
      else
        run_cmd ln -sfn "$public_dir" "$asset_link"
      fi
    elif [[ -e "$asset_link" ]]; then
      warn "asset path exists and is not a symlink, leaving untouched: $asset_link"
    else
      run_cmd ln -s "$public_dir" "$asset_link"
    fi
  done < <(discover_bench_custom_apps)
}

add_gitignore_entry() {
  local entry="$1"
  local gitignore="$REPO_ROOT/.gitignore"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    grep -Fxq "$entry" "$gitignore" 2>/dev/null || info "[DRY-RUN] would add to .gitignore: $entry"
    return 0
  fi
  [[ -f "$gitignore" ]] || touch "$gitignore"
  grep -Fxq "$entry" "$gitignore" 2>/dev/null && return 0
  printf '%s\n' "$entry" >>"$gitignore"
  ok "added to .gitignore: $entry"
}

ensure_gitignore_entries() {
  add_gitignore_entry "deploy/production.secrets.md"
  add_gitignore_entry "logs/deploy/"
  add_gitignore_entry "deploy/backups-index.md"
  add_gitignore_entry "backups/"
  add_gitignore_entry "*.sql.gz"
  add_gitignore_entry "*.tar"
  add_gitignore_entry "*.tgz"
  add_gitignore_entry "*.env.local"
}

check_gitignore_entry() {
  local entry="$1"
  local gitignore="$REPO_ROOT/.gitignore"
  if [[ -f "$gitignore" ]] && grep -Fxq "$entry" "$gitignore"; then
    status_ok ".gitignore covers $entry"
  else
    status_warn ".gitignore missing $entry"
  fi
}

ensure_secrets_file() {
  ensure_gitignore_entries
  if [[ "$DRY_RUN" -eq 1 ]]; then
    info "[DRY-RUN] would ensure secrets file: $SECRETS_FILE"
    return 0
  fi
  if [[ ! -f "$SECRETS_FILE" ]]; then
    umask 077
    {
      printf '# Frappe Production Secrets\n\n'
      printf 'Generated by deploy/production_setup.sh. Do not commit this file.\n\n'
    } >"$SECRETS_FILE"
  fi
  chmod 600 "$SECRETS_FILE"
}

append_production_secret() {
  local domain="$1"
  local site="$2"
  local admin_password="$3"
  local admin_password_source="$4"
  local db_name="$5"
  local db_password="$6"
  local db_password_source="$7"
  local app="$8"
  ensure_secrets_file
  if [[ "$DRY_RUN" -eq 1 ]]; then
    info "[DRY-RUN] would save site credentials to $SECRETS_FILE"
    return 0
  fi
  {
    printf '\n## Site: %s\n' "$site"
    printf -- '- Site URL: https://%s\n' "$domain"
    printf -- '- Domain: %s\n' "$domain"
    printf -- '- Site name: %s\n' "$site"
    printf -- '- Admin user: Administrator\n'
    printf -- '- Admin password: %s\n' "$admin_password"
    printf -- '- Admin password source: %s\n' "$admin_password_source"
    printf -- '- DB name: %s\n' "$db_name"
    printf -- '- DB user: %s\n' "$db_name"
    printf -- '- DB password: %s\n' "$db_password"
    printf -- '- DB password source: %s\n' "$db_password_source"
    printf -- '- App: %s\n' "$app"
    printf -- '- Timestamp: %s\n' "$(now_iso)"
  } >>"$SECRETS_FILE"
  chmod 600 "$SECRETS_FILE"
  ok "Credentials saved to deploy/production.secrets.md"
}

port_listeners() {
  local port="$1"
  if have_cmd ss; then
    ss -ltnp 2>/dev/null | awk -v port="$port" '$4 ~ ":" port "$" {print}' || true
  elif have_cmd lsof; then
    lsof -nP -iTCP:"$port" -sTCP:LISTEN 2>/dev/null || true
  fi
}

print_port_status_line() {
  local port="$1"
  local listeners
  listeners="$(port_listeners "$port")"
  if [[ -z "$listeners" ]]; then
    printf '  %s: free\n' "$port"
  else
    printf '  %s: listening\n' "$port"
    printf '%s\n' "$listeners" | sed 's/^/    /'
  fi
}

port_owned_by_nginx() {
  local port="$1"
  port_listeners "$port" | grep -qi nginx
}

mariadb_socket_auth_available_noninteractive() {
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    mariadb -e "SELECT 1;" >/dev/null 2>&1
  elif sudo_available_noninteractive; then
    sudo mariadb -e "SELECT 1;" >/dev/null 2>&1
  else
    return 1
  fi
}

system_service_active() {
  local svc="$1"
  if have_cmd systemctl && systemctl list-unit-files "$svc.service" >/dev/null 2>&1; then
    systemctl is-active "$svc" >/dev/null 2>&1
  elif have_cmd service; then
    service "$svc" status >/dev/null 2>&1
  else
    return 1
  fi
}

sudo_bench_available_noninteractive() {
  local b="$1"
  local sudo_user
  [[ -n "$b" ]] || return 1
  sudo_user="${USER:-$(id -un)}"
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    env "PATH=$PATH" "HOME=$HOME" "USER=$sudo_user" "$b" --version >/dev/null 2>&1
  elif sudo_available_noninteractive; then
    sudo env "PATH=$PATH" "HOME=$HOME" "USER=$sudo_user" "$b" --version >/dev/null 2>&1
  else
    return 1
  fi
}

preflight_check() {
  section "Preflight Check"
  printf 'Repo root: %s\n' "$REPO_ROOT"
  printf 'Bench path: %s\n' "$BENCH_DIR"
  printf 'Log file: %s\n' "$LOG_FILE"

  local os_name arch cpu ram disk current_user public_ip private_ips ec2_id
  os_name="unknown"
  if [[ -r /etc/os-release ]]; then
    os_name="$(. /etc/os-release && printf '%s' "${PRETTY_NAME:-$NAME}")"
  fi
  arch="$(uname -m 2>/dev/null || true)"
  cpu="$(nproc 2>/dev/null || printf '?')"
  ram="$(free -h 2>/dev/null | awk '/^Mem:/ {print $2}' || true)"
  disk="$(df -h "$REPO_ROOT" 2>/dev/null | awk 'NR==2 {print $4 " free on " $6}' || true)"
  current_user="$(whoami)"

  status_ok "OS: $os_name"
  status_ok "Architecture: ${arch:-unknown}"
  status_ok "CPU cores: $cpu"
  status_ok "RAM: ${ram:-unknown}"
  status_ok "Disk: ${disk:-unknown}"
  status_ok "Current user: $current_user"

  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    status_ok "sudo: running as root"
  elif sudo_available_noninteractive; then
    status_ok "sudo: available"
  elif have_cmd sudo; then
    status_warn "sudo: installed but may prompt or be unavailable"
  else
    status_error "sudo: missing"
  fi

  public_ip="$(detect_public_ip || true)"
  if [[ -n "$public_ip" ]]; then
    status_ok "Public IP: $public_ip"
  else
    status_warn "Public IP: could not detect"
  fi
  private_ips="$(detect_private_ips)"
  status_ok "Private IP(s): ${private_ips:-unknown}"
  ec2_id="$(detect_ec2_instance_id || true)"
  if [[ -n "$ec2_id" ]]; then
    status_ok "EC2 metadata: reachable ($ec2_id)"
  else
    status_warn "EC2 metadata: unavailable or blocked"
  fi

  if git_is_repo; then
    status_ok "Git repository detected"
    status_ok "Git branch: $(git_branch)"
    status_ok "Git remote: $(git_remote_url)"
    if [[ -n "$(git_dirty_status)" ]]; then
      status_warn "Git working tree has local changes"
      git_dirty_status | sed 's/^/  /'
    else
      status_ok "Git working tree clean"
    fi
  else
    status_warn "Not inside a Git repository"
    status_ok "Default repo URL: $DEFAULT_REPO_URL"
  fi

  local cmd
  for cmd in git curl python3 pipx mariadb redis-server node npm yarn bench nginx supervisorctl certbot; do
    if have_cmd "$cmd"; then
      status_ok "command: $cmd"
    else
      status_warn "command missing: $cmd"
    fi
  done

  printf 'Current PATH: %s\n' "$PATH"
  local normal_bench_path
  normal_bench_path="$(resolve_cmd bench)"
  if [[ -n "$normal_bench_path" ]]; then
    status_ok "normal bench path: $normal_bench_path"
  else
    status_warn "normal bench path: not found"
  fi
  if sudo_bench_available_noninteractive "$normal_bench_path"; then
    status_ok "sudo bench validation: OK"
  else
    status_warn "sudo bench validation: WARN"
  fi

  if mariadb_socket_auth_available_noninteractive; then
    status_ok "MariaDB sudo socket auth: available"
  else
    status_warn "MariaDB sudo socket auth: unavailable or requires interactive sudo"
  fi
  if system_service_active nginx; then
    status_ok "nginx service: running"
  else
    status_warn "nginx service: not running or not detected"
  fi
  if system_service_active supervisor; then
    status_ok "supervisor service: running"
  else
    status_warn "supervisor service: not running or not detected"
  fi

  printf 'Ports:\n'
  local port
  for port in 80 443 8000 9000 11000 12000 13000; do
    print_port_status_line "$port"
  done
  for port in 80 443; do
    if [[ -z "$(port_listeners "$port")" ]]; then
      status_ok "port $port is free"
    elif port_owned_by_nginx "$port"; then
      status_ok "port $port is owned by nginx"
    else
      status_warn "port $port is occupied by a non-nginx listener"
    fi
  done

  if valid_bench; then
    status_ok "Bench is valid: $BENCH_DIR"
  elif [[ -e "$BENCH_DIR" ]]; then
    status_error "Bench path exists but is invalid: $BENCH_DIR"
  else
    status_warn "Bench is not initialized yet: $BENCH_DIR"
  fi

  printf 'Existing sites:\n'
  if [[ -d "$BENCH_DIR/sites" ]]; then
    local sites
    sites="$(site_names || true)"
    if [[ -n "$sites" ]]; then
      printf '%s\n' "$sites" | sed 's/^/  /'
    else
      printf '  none\n'
    fi
  else
    printf '  none\n'
  fi

  printf 'Available apps:\n'
  local source_apps
  source_apps="$(discover_source_apps || true)"
  if [[ -n "$source_apps" ]]; then
    printf '%s\n' "$source_apps" | sed 's/^/  /'
  else
    printf '  none\n'
  fi

  printf 'Bench custom apps:\n'
  local bench_apps
  bench_apps="$(discover_bench_custom_apps || true)"
  if [[ -n "$bench_apps" ]]; then
    printf '%s\n' "$bench_apps" | sed 's/^/  /'
  else
    printf '  none\n'
  fi

  printf 'Importable bench apps:\n'
  local importable_apps
  importable_apps="$(detect_importable_bench_apps_no_install || true)"
  if [[ -n "$importable_apps" ]]; then
    printf '%s\n' "$importable_apps" | sed 's/^/  /'
  else
    printf '  none detected without modifying the bench env\n'
  fi

  if [[ -f "$SECRETS_FILE" ]]; then
    status_warn "existing production secrets file: $SECRETS_FILE"
  else
    status_ok "production secrets file does not exist yet"
  fi

  check_gitignore_entry "frappe-bench/"
  check_gitignore_entry "logs/"
  check_gitignore_entry "logs/install/"
  check_gitignore_entry "secrets.md"
  check_gitignore_entry "deploy/production.secrets.md"
  check_gitignore_entry "logs/deploy/"
  check_gitignore_entry "deploy/backups-index.md"
  check_gitignore_entry "backups/"
}

apt_has_candidate() {
  local pkg="$1"
  apt-cache policy "$pkg" 2>/dev/null | awk '/Candidate:/ {print $2}' | grep -qxv '(none)'
}

install_apt_if_missing() {
  local pkg="$1"
  if dpkg -s "$pkg" >/dev/null 2>&1; then
    info "skip installed package: $pkg"
    return 0
  fi
  if ! apt_has_candidate "$pkg"; then
    warn "package has no apt candidate, skipping: $pkg"
    return 0
  fi
  run_cmd "${SUDO[@]}" apt-get install -y "$pkg"
}

install_optional_apt_if_available() {
  local pkg="$1"
  if apt_has_candidate "$pkg"; then
    install_apt_if_missing "$pkg"
  else
    warn "optional package unavailable from apt: $pkg"
  fi
}

install_tiff_dependency() {
  if dpkg -s libtiff-dev >/dev/null 2>&1 || dpkg -s libtiff5-dev >/dev/null 2>&1; then
    info "skip installed package: libtiff-dev/libtiff5-dev"
  elif apt_has_candidate libtiff-dev; then
    install_apt_if_missing libtiff-dev
  elif apt_has_candidate libtiff5-dev; then
    install_apt_if_missing libtiff5-dev
  else
    warn "no libtiff development package candidate found"
  fi
}

ensure_service_started() {
  local svc="$1"
  local unit="$svc.service"
  if have_cmd systemctl && systemctl list-unit-files "$unit" >/dev/null 2>&1; then
    if ! systemctl is-enabled "$unit" >/dev/null 2>&1; then
      run_cmd "${SUDO[@]}" systemctl enable "$unit" || warn "could not enable $svc"
    fi
    if systemctl is-active "$unit" >/dev/null 2>&1; then
      info "service already running: $svc"
    else
      run_cmd "${SUDO[@]}" systemctl start "$unit" || warn "could not start $svc"
    fi
  elif have_cmd service; then
    run_cmd "${SUDO[@]}" service "$svc" start || warn "could not start $svc with service"
  else
    warn "could not manage service automatically: $svc"
  fi
}

ensure_nvm() {
  export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
  if [[ -s "$NVM_DIR/nvm.sh" ]]; then
    # shellcheck disable=SC1090
    . "$NVM_DIR/nvm.sh"
    return 0
  fi
  have_cmd curl || die "curl is required to install nvm"
  run_cmd_label "install nvm $NVM_INSTALL_VERSION" \
    bash -c "curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_INSTALL_VERSION}/install.sh | bash"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    return 0
  fi
  [[ -s "$NVM_DIR/nvm.sh" ]] || die "nvm install completed but $NVM_DIR/nvm.sh was not found"
  # shellcheck disable=SC1090
  . "$NVM_DIR/nvm.sh"
}

ensure_node() {
  section "Node"
  refresh_path
  ensure_nvm
  if [[ "$DRY_RUN" -eq 0 ]]; then
    # shellcheck disable=SC1090
    [[ -s "$NVM_DIR/nvm.sh" ]] && . "$NVM_DIR/nvm.sh"
  fi
  run_cmd nvm install "$NODE_MAJOR"
  run_cmd nvm alias default "$NODE_MAJOR"
  run_cmd nvm use "$NODE_MAJOR"
  hash -r
  refresh_path
  if [[ "$DRY_RUN" -eq 0 ]]; then
    have_cmd node || die "node is unavailable after nvm setup"
    have_cmd npm || die "npm is unavailable after nvm setup"
    local current_major
    current_major="$(node -v | sed -E 's/^v([0-9]+).*/\1/')"
    [[ "$current_major" == "$NODE_MAJOR" ]] || die "active node is $(node -v), expected Node $NODE_MAJOR"
    ok "node $(node -v)"
    ok "npm $(npm -v)"
  fi
}

ensure_yarn() {
  section "Yarn"
  refresh_path
  have_cmd npm || {
    [[ "$DRY_RUN" -eq 1 ]] && info "[DRY-RUN] npm not available yet" && return 0
    die "npm is required before installing yarn"
  }
  if ! have_cmd yarn; then
    run_cmd npm install -g yarn
    refresh_path
  fi
  [[ "$DRY_RUN" -eq 1 ]] || ok "yarn $(yarn --version)"
}

ensure_pipx() {
  refresh_path
  if have_cmd pipx; then
    run_cmd pipx ensurepath || true
    refresh_path
    return 0
  fi
  need_sudo
  install_apt_if_missing pipx
  refresh_path
  have_cmd pipx || [[ "$DRY_RUN" -eq 1 ]]
}

pip_user_install() {
  local package="$1"
  run_cmd python3 -m pip install --user "$package" ||
    run_cmd python3 -m pip install --user --break-system-packages "$package"
  refresh_path
}

ensure_uv() {
  section "uv"
  refresh_path
  if have_cmd uv; then
    ok "$(uv --version 2>/dev/null || true)"
    return 0
  fi
  if ensure_pipx; then
    run_cmd pipx install uv || run_cmd pipx upgrade uv || warn "pipx could not install/upgrade uv"
    refresh_path
  fi
  if ! have_cmd uv && [[ "$DRY_RUN" -eq 0 ]]; then
    warn "falling back to user-level pip install for uv"
    pip_user_install uv
  fi
  [[ "$DRY_RUN" -eq 1 ]] || have_cmd uv || die "uv command is unavailable after install"
}

ensure_bench_cli() {
  section "Bench CLI"
  refresh_path
  if have_cmd bench; then
    ok "$(bench --version 2>/dev/null || true)"
    return 0
  fi
  if ensure_pipx; then
    run_cmd pipx install frappe-bench || run_cmd pipx upgrade frappe-bench || warn "pipx could not install/upgrade frappe-bench"
    refresh_path
  fi
  if ! have_cmd bench && [[ "$DRY_RUN" -eq 0 ]]; then
    warn "falling back to user-level pip install for frappe-bench"
    pip_user_install frappe-bench
  fi
  [[ "$DRY_RUN" -eq 1 ]] || have_cmd bench || die "bench command is unavailable after install"
}

prepare_server_packages() {
  section "Prepare Server Packages"
  have_cmd apt-get || die "apt-get is required for this production package setup"
  need_sudo
  run_cmd "${SUDO[@]}" apt-get update
  run_cmd "${SUDO[@]}" apt-get --fix-broken install -y

  local packages=(
    git curl ca-certificates gnupg
    build-essential pkg-config
    python3 python3-dev python3-pip python3-venv python3-setuptools pipx
    redis-server mariadb-server mariadb-client
    nginx supervisor certbot cron
    libffi-dev libssl-dev libmysqlclient-dev
    libjpeg-dev zlib1g-dev liblcms2-dev libwebp-dev
    libxrender1 libxext6 fontconfig xfonts-75dpi xfonts-base
  )
  local pkg
  for pkg in "${packages[@]}"; do
    install_apt_if_missing "$pkg"
  done
  install_optional_apt_if_available python3-certbot-nginx
  install_optional_apt_if_available ufw
  install_tiff_dependency
  install_optional_apt_if_available wkhtmltopdf

  ensure_service_started mariadb
  ensure_service_started redis-server
  ensure_service_started nginx
  ensure_service_started supervisor

  ensure_node
  ensure_yarn
  ensure_pipx
  ensure_uv
  ensure_bench_cli
  ok "server package preparation complete"
}

setup_validate_bench() {
  section "Setup / Validate Bench"
  refresh_path
  ensure_bench_cli
  ensure_uv
  ensure_node
  ensure_yarn
  refresh_path

  if valid_bench; then
    ok "valid bench found: $BENCH_DIR"
  elif [[ -e "$BENCH_DIR" ]]; then
    die "Existing bench path is incomplete or invalid. Move/fix it manually before continuing: $BENCH_DIR"
  else
    info "initializing Frappe bench: $BENCH_DIR"
    if ! run_bench init --frappe-branch "$FRAPPE_BRANCH" "$BENCH_DIR"; then
      local failed_dir="$REPO_ROOT/frappe-bench.failed-$TIMESTAMP"
      if [[ -e "$BENCH_DIR" ]]; then
        warn "bench init failed; moving partial folder to $failed_dir"
        run_cmd mv "$BENCH_DIR" "$failed_dir"
      fi
      die "bench init failed"
    fi
    valid_bench || die "bench init finished but validation failed"
    ok "bench initialized: $BENCH_DIR"
  fi

  run_bench set-config -g dns_multitenant on
  run_bench set-config -g developer_mode 0
  ok "bench production config validated"
}

copy_or_update_app() {
  local app="$1"
  local overwrite_mode="${2:-ask}"
  local src="$APPS_SRC/$app"
  local dest="$BENCH_DIR/apps/$app"
  [[ -d "$src" ]] || return 0

  if [[ ! -e "$dest" ]]; then
    run_cmd cp -a "$src" "$dest"
    ok "copied app into bench: $app"
    return 0
  fi

  if [[ "$overwrite_mode" == "yes" ]]; then
    run_cmd cp -a "$src/." "$dest/"
    ok "updated existing app from apps: $app"
    return 0
  fi

  warn "App already exists in bench: $app"
  if confirm "Overwrite/update $app from apps now?" "N"; then
    run_cmd cp -a "$src/." "$dest/"
    ok "updated existing app from apps: $app"
  else
    info "left existing bench app untouched: $app"
  fi
}

sync_validate_apps() {
  local overwrite_mode="${1:-ask}"
  section "Sync and Validate Apps"
  require_valid_bench
  [[ -d "$APPS_SRC" ]] || {
    warn "apps source folder missing: $APPS_SRC"
    return 0
  }

  local app
  while IFS= read -r app; do
    [[ -n "$app" ]] || continue
    copy_or_update_app "$app" "$overwrite_mode"
  done < <(discover_source_apps)

  local ready=()
  while IFS= read -r app; do
    [[ -n "$app" ]] || continue
    if ensure_app_importable "$app"; then
      ensure_app_in_apps_txt "$app"
      ready+=("$app")
    else
      warn "app is not production-ready/importable yet: $app"
    fi
  done < <(discover_bench_custom_apps)

  ensure_custom_app_assets

  printf '\nProduction-ready apps:\n'
  if [[ "${#ready[@]}" -eq 0 ]]; then
    printf '  none\n'
  else
    printf '  %s\n' "${ready[@]}"
  fi
}

select_site() {
  local -n _site="$1"
  local sites=()
  local choice idx
  mapfile -t sites < <(site_names)
  if [[ "${#sites[@]}" -eq 0 ]]; then
    die "no Frappe sites found in $BENCH_DIR/sites"
  fi
  if [[ -n "${PRODUCTION_SITE:-}" ]]; then
    local env_site
    env_site="$(lowercase "$PRODUCTION_SITE")"
    local site
    for site in "${sites[@]}"; do
      if [[ "$site" == "$env_site" ]]; then
        _site="$site"
        info "Using site from PRODUCTION_SITE: $site"
        return 0
      fi
    done
  fi
  if [[ "${#sites[@]}" -eq 1 ]]; then
    _site="${sites[0]}"
    info "Using only detected site: $_site"
    return 0
  fi
  if [[ "$ASSUME_YES" -eq 1 ]]; then
    die "multiple sites detected; set PRODUCTION_SITE for --yes mode"
  fi
  printf '\nSelect site:\n'
  local i
  for i in "${!sites[@]}"; do
    printf '  %d) %s\n' "$((i + 1))" "${sites[$i]}"
  done
  while true; do
    read -r -p "Choose site number: " choice
    choice="${choice//[[:space:]]/}"
    if [[ "$choice" =~ ^[0-9]+$ ]]; then
      idx=$((choice - 1))
      if (( idx >= 0 && idx < ${#sites[@]} )); then
        _site="${sites[$idx]}"
        return 0
      fi
    fi
    warn "invalid site selection"
  done
}

select_importable_app() {
  local -n _app="$1"
  local apps=()
  local choice idx app
  mapfile -t apps < <(importable_bench_apps)
  if [[ "${#apps[@]}" -eq 0 ]]; then
    die "no importable custom apps found. Run Sync and Validate Apps first."
  fi
  if [[ -n "${APP_NAME:-}" ]]; then
    for app in "${apps[@]}"; do
      if [[ "$app" == "$APP_NAME" ]]; then
        _app="$app"
        info "Using APP_NAME: $app"
        return 0
      fi
    done
    warn "APP_NAME is not importable in this bench: $APP_NAME"
  fi
  if [[ "${#apps[@]}" -eq 1 ]]; then
    _app="${apps[0]}"
    info "Using only importable app: $_app"
    return 0
  fi
  if [[ "$ASSUME_YES" -eq 1 ]]; then
    die "multiple importable apps detected; set APP_NAME for --yes mode"
  fi
  printf '\nSelect app for this production site:\n'
  local i
  for i in "${!apps[@]}"; do
    printf '  %d) %s\n' "$((i + 1))" "${apps[$i]}"
  done
  while true; do
    read -r -p "Choose app number: " choice
    choice="${choice//[[:space:]]/}"
    if [[ "$choice" =~ ^[0-9]+$ ]]; then
      idx=$((choice - 1))
      if (( idx >= 0 && idx < ${#apps[@]} )); then
        _app="${apps[$idx]}"
        return 0
      fi
    fi
    warn "invalid app selection"
  done
}

read_domain_and_site() {
  local -n _domain="$1"
  local -n _site="$2"
  local default_domain="${PRODUCTION_DOMAIN:-}"
  local default_site
  prompt_value _domain "Production domain, example site.local" "$default_domain" 1
  _domain="$(lowercase "$_domain")"
  _domain="${_domain#http://}"
  _domain="${_domain#https://}"
  _domain="${_domain%%/*}"
  [[ -n "$_domain" ]] || die "production domain is required"
  [[ "$_domain" != *" "* ]] || die "production domain must not contain spaces"
  default_site="${PRODUCTION_SITE:-$_domain}"
  default_site="$(lowercase "$default_site")"
  prompt_value _site "Site name" "$default_site" 1
  _site="$(lowercase "$_site")"
  [[ "$_site" != *" "* ]] || die "site name must not contain spaces"
}

dns_ips_for_domain() {
  local domain="$1"
  if have_cmd dig; then
    dig +short A "$domain" 2>/dev/null | awk 'NF'
  elif have_cmd nslookup; then
    nslookup "$domain" 2>/dev/null | awk '/^Address: / {print $2}' | grep -E '^[0-9.]+$' || true
  elif have_cmd getent; then
    getent ahostsv4 "$domain" 2>/dev/null | awk '{print $1}' | sort -u || true
  fi
}

dns_points_to_public_ip() {
  local domain="$1"
  local public_ip="$2"
  local ip
  [[ -n "$public_ip" ]] || return 1
  while IFS= read -r ip; do
    [[ "$ip" == "$public_ip" ]] && return 0
  done < <(dns_ips_for_domain "$domain")
  return 1
}

validate_dns_or_confirm() {
  local domain="$1"
  local phrase="$2"
  local public_ip dns_ips
  public_ip="$(detect_public_ip || true)"
  dns_ips="$(dns_ips_for_domain "$domain" || true)"
  if [[ -z "$public_ip" ]]; then
    warn "Could not detect this server public IP; DNS validation is limited."
    return 0
  fi
  if [[ -z "$dns_ips" ]]; then
    warn "Could not resolve an A record for $domain"
    exact_confirm "$phrase" "DNS is not verified. SSL may fail and traffic may not reach this server." ||
      die "DNS confirmation not provided"
    return 0
  fi
  if dns_points_to_public_ip "$domain" "$public_ip"; then
    ok "DNS A record for $domain points to this public IP: $public_ip"
    return 0
  fi
  warn "DNS mismatch for $domain"
  warn "  Server public IP: $public_ip"
  warn "  DNS A record(s):"
  printf '%s\n' "$dns_ips" | sed 's/^/    /' >&2
  exact_confirm "$phrase" "Continue only if this mismatch is expected." ||
    die "DNS confirmation not provided"
}

create_database_sql() {
  local db_name="$1"
  local db_password="$2"
  local quoted_pass quoted_user ident
  quoted_pass="$(sql_quote "$db_password")"
  quoted_user="$(sql_quote "$db_name")"
  ident="$(sql_identifier "$db_name")"
  cat <<SQL
CREATE DATABASE IF NOT EXISTS \`$ident\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '$quoted_user'@'localhost' IDENTIFIED BY '$quoted_pass';
ALTER USER '$quoted_user'@'localhost' IDENTIFIED BY '$quoted_pass';
GRANT ALL PRIVILEGES ON \`$ident\`.* TO '$quoted_user'@'localhost';
FLUSH PRIVILEGES;
SQL
}

mariadb_socket_auth_available() {
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    SUDO=()
  elif have_cmd sudo; then
    if [[ "$ASSUME_YES" -eq 1 ]]; then
      sudo -n true >/dev/null 2>&1 || return 1
    else
      sudo -v || return 1
    fi
    SUDO=(sudo)
  else
    return 1
  fi
  [[ "$DRY_RUN" -eq 1 ]] && return 0
  "${SUDO[@]}" mariadb -e "SELECT 1;" >/dev/null 2>&1
}

create_database_with_sudo() {
  local db_name="$1"
  local db_password="$2"
  mariadb_socket_auth_available || return 1
  info "creating MariaDB database/user via sudo socket auth"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    info "[DRY-RUN] would create MariaDB database/user: $db_name"
    return 0
  fi
  create_database_sql "$db_name" "$db_password" | "${SUDO[@]}" mariadb
}

create_database_with_credentials() {
  local db_name="$1"
  local db_password="$2"
  local db_admin_user db_admin_password
  warn "sudo MariaDB socket auth failed or is unavailable."
  prompt_value db_admin_user "MariaDB admin user" "root" 1
  prompt_secret db_admin_password "MariaDB password for $db_admin_user" 0
  if [[ "$DRY_RUN" -eq 1 ]]; then
    info "[DRY-RUN] would create MariaDB database/user using provided admin credentials: $db_name"
    return 0
  fi
  if [[ -n "$db_admin_password" ]]; then
    create_database_sql "$db_name" "$db_password" | MYSQL_PWD="$db_admin_password" mariadb -u "$db_admin_user"
  else
    create_database_sql "$db_name" "$db_password" | mariadb -u "$db_admin_user"
  fi
}

create_database_and_user() {
  local db_name="$1"
  local db_password="$2"
  have_cmd mariadb || die "mariadb client command not found"
  safe_db_name "$db_name" || die "generated DB name is invalid: $db_name"
  if create_database_with_sudo "$db_name" "$db_password"; then
    ok "database prepared: $db_name"
  else
    create_database_with_credentials "$db_name" "$db_password"
    ok "database prepared: $db_name"
  fi
}

select_admin_password() {
  local -n _password="$1"
  local -n _source="$2"
  local manual
  if [[ -n "${FRAPPE_ADMIN_PASSWORD:-}" ]]; then
    _password="$FRAPPE_ADMIN_PASSWORD"
    _source="FRAPPE_ADMIN_PASSWORD environment variable"
    info "Using FRAPPE_ADMIN_PASSWORD from environment"
    if [[ "$_password" == "admin" ]]; then
      warn "FRAPPE_ADMIN_PASSWORD is set to 'admin'; consider using a stronger password."
    fi
    return 0
  fi
  if [[ "$ASSUME_YES" -eq 1 ]]; then
    _password="$(strong_password)"
    _source="auto-generated"
    info "Generated strong Administrator password"
    return 0
  fi
  prompt_optional_secret_with_confirm manual \
    "Administrator password (press Enter to auto-generate)" \
    "Confirm Administrator password"
  if [[ -z "$manual" ]]; then
    _password="$(strong_password)"
    _source="auto-generated"
    info "Generated strong Administrator password"
  else
    _password="$manual"
    _source="entered manually"
  fi
}

prompt_optional_secret_with_confirm() {
  local -n _out="$1"
  local prompt="$2"
  local confirm_prompt="$3"
  local first second

  if [[ "$ASSUME_YES" -eq 1 ]]; then
    _out=""
    return 0
  fi

  while true; do
    read -r -s -p "$prompt: " first
    printf '\n'
    if [[ -z "$first" ]]; then
      _out=""
      return 0
    fi

    read -r -s -p "$confirm_prompt: " second
    printf '\n'
    if [[ "$first" == "$second" ]]; then
      _out="$first"
      return 0
    fi
    warn "passwords did not match; try again or press Enter to auto-generate"
  done
}

select_site_db_password() {
  local -n _password="$1"
  local -n _source="$2"
  local manual

  if [[ "$ASSUME_YES" -eq 1 ]]; then
    _password="$(make_db_password)"
    _source="auto-generated"
    info "Generated strong site DB password"
    return 0
  fi

  prompt_optional_secret_with_confirm manual \
    "Site DB password (press Enter to auto-generate)" \
    "Confirm Site DB password"
  if [[ -z "$manual" ]]; then
    _password="$(make_db_password)"
    _source="auto-generated"
    info "Generated strong site DB password"
  else
    _password="$manual"
    _source="entered manually"
  fi
}

site_has_app() {
  local site="$1"
  local app="$2"
  [[ "$DRY_RUN" -eq 1 ]] && return 1
  (cd "$BENCH_DIR" && bench --site "$site" list-apps 2>/dev/null | awk '{print $1}' | grep -Fxq "$app")
}

production_site_config_value() {
  local site="$1"
  local key="$2"
  local site_config="$BENCH_DIR/sites/$site/site_config.json"
  [[ -f "$site_config" ]] || return 1
  "$BENCH_DIR/env/bin/python" -c 'import json, sys
with open(sys.argv[1], encoding="utf-8") as f:
    data = json.load(f)
value = data.get(sys.argv[2], "")
print("" if value is None else value)
' "$site_config" "$key"
}

select_mariadb_root_password() {
  local -n _password="$1"
  local -n _source="$2"
  local manual

  if [[ -n "${MARIADB_ROOT_PASSWORD:-}" ]]; then
    _password="$MARIADB_ROOT_PASSWORD"
    _source="MARIADB_ROOT_PASSWORD environment variable"
    info "Using MariaDB root/admin password from environment"
    return 0
  fi

  if [[ "$ASSUME_YES" -eq 1 ]]; then
    _password="admin"
    _source="default admin password"
    warn "Using default MariaDB root/admin password for --yes mode: admin"
    return 0
  fi

  read -r -s -p "MariaDB root/admin password for bench new-site [admin]: " manual
  printf '\n'
  _password="${manual:-admin}"
  if [[ -z "$manual" ]]; then
    _source="default admin password"
  else
    _source="entered manually"
  fi
}

restart_frappe_supervisor() {
  section "Restart Frappe Supervisor"
  need_sudo

  local bench_name groups group
  bench_name="$(basename "$BENCH_DIR")"
  groups="$("${SUDO[@]}" supervisorctl status 2>/dev/null | awk -v prefix="$bench_name-" '
    $1 ~ "^" prefix {
      split($1, parts, ":")
      print parts[1]
    }
  ' | sort -u || true)"

  if [[ -n "$groups" ]]; then
    while IFS= read -r group; do
      [[ -n "$group" ]] || continue
      sudo_env_cmd supervisorctl restart "$group:" || warn "supervisor restart returned non-zero for group: $group"
    done <<<"$groups"
    return 0
  fi

  warn "Could not detect Frappe supervisor groups for bench: $bench_name"
  warn "Keeping restart scoped to common Frappe group names instead of restarting all supervisor programs."
  sudo_env_cmd supervisorctl restart frappe-bench-web: || true
  sudo_env_cmd supervisorctl restart frappe-bench-workers: || true
}

create_production_site() {
  section "Create Production Site"
  require_valid_bench
  local domain site app admin_password admin_password_source scheduler_answer
  local db_name db_password db_password_source mariadb_root_password mariadb_root_password_source
  read_domain_and_site domain site
  select_importable_app app

  scheduler_answer=1
  if ! confirm "Enable scheduler after setup?" "Y"; then
    scheduler_answer=0
  fi

  validate_dns_or_confirm "$domain" "CONTINUE WITHOUT DNS"

  if [[ -d "$BENCH_DIR/sites/$site" ]]; then
    warn "site already exists: $site"
    if confirm "Install/migrate selected app and refresh this existing site?" "Y"; then
      if site_has_app "$site" "$app"; then
        info "app already installed on site: $app"
      else
        run_bench --site "$site" install-app "$app"
      fi
      run_bench --site "$site" migrate
      [[ "$scheduler_answer" -eq 1 ]] && run_bench --site "$site" enable-scheduler || true
      run_bench --site "$site" clear-cache
      run_bench --site "$site" clear-website-cache
    fi
    return 0
  fi

  select_admin_password admin_password admin_password_source
  select_mariadb_root_password mariadb_root_password mariadb_root_password_source

  run_bench_label "bench new-site $site --admin-password [redacted] --mariadb-root-password [redacted]" \
    new-site "$site" --admin-password "$admin_password" --mariadb-root-password "$mariadb_root_password"

  run_bench --site "$site" install-app "$app"
  run_bench --site "$site" migrate
  [[ "$scheduler_answer" -eq 1 ]] && run_bench --site "$site" enable-scheduler || true
  run_bench --site "$site" clear-cache
  run_bench --site "$site" clear-website-cache

  db_name="$(production_site_config_value "$site" db_name 2>/dev/null || true)"
  db_password="$(production_site_config_value "$site" db_password 2>/dev/null || true)"
  db_password_source="created by bench new-site; saved in site_config.json"

  append_production_secret "$domain" "$site" "$admin_password" "$admin_password_source" "${db_name:-created-by-bench}" "${db_password:-stored-in-site-config}" "$db_password_source" "$app"
}

disable_nginx_default_if_needed() {
  local path backup
  for path in /etc/nginx/sites-enabled/default /etc/nginx/conf.d/default.conf; do
    [[ -e "$path" ]] || continue
    backup="$path.disabled-$TIMESTAMP"
    run_cmd "${SUDO[@]}" mv "$path" "$backup"
    warn "disabled default nginx config: $path -> $backup"
  done
}

setup_supervisor_nginx() {
  section "Setup Supervisor + Nginx"
  require_valid_bench
  need_sudo
  validate_sudo_bench_for_production
  local use_standard=1
  if ! confirm "Use Frappe standard production setup?" "Y"; then
    use_standard=0
  fi

  if [[ "$use_standard" -eq 1 ]]; then
    (cd "$BENCH_DIR" && sudo_bench setup production "$(whoami)")
  else
    run_bench setup supervisor
    run_bench setup nginx
    run_cmd "${SUDO[@]}" ln -sfn "$BENCH_DIR/config/supervisor.conf" /etc/supervisor/conf.d/frappe-bench.conf
    run_cmd "${SUDO[@]}" ln -sfn "$BENCH_DIR/config/nginx.conf" /etc/nginx/conf.d/frappe-bench.conf
    disable_nginx_default_if_needed
    sudo_env_cmd supervisorctl reread
    sudo_env_cmd supervisorctl update
    restart_frappe_supervisor
  fi

  if ! run_cmd "${SUDO[@]}" nginx -t; then
    die "nginx validation failed. Check $BENCH_DIR/config/nginx.conf before reloading."
  fi
  run_cmd "${SUDO[@]}" systemctl reload nginx || run_cmd "${SUDO[@]}" service nginx reload

  sudo_env_cmd supervisorctl status || warn "supervisor status returned non-zero"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    info "[DRY-RUN] skipping HTTP validation"
    return 0
  fi

  local site
  if site="$(site_names | sed -n '1p')"; [[ -n "$site" ]]; then
    if have_cmd curl; then
      curl -fsSI --max-time 8 "http://$site" || curl -fsSI --max-time 8 -H "Host: $site" http://127.0.0.1 || warn "HTTP validation did not succeed for $site"
    fi
  fi
}

setup_ssl() {
  section "Setup SSL"
  if ! confirm "Install SSL now?" "N"; then
    info "SSL setup skipped"
    return 0
  fi
  need_sudo
  have_cmd certbot || die "certbot is not installed. Run Prepare Server Packages first."
  local domain site email staging=0 redirect=1 public_ip
  read_domain_and_site domain site
  prompt_value email "SSL email" "${LETSENCRYPT_EMAIL:-}" 1
  if confirm "Use Let's Encrypt staging mode?" "N"; then
    staging=1
  fi
  if ! confirm "Redirect HTTP to HTTPS?" "Y"; then
    redirect=0
  fi

  validate_dns_or_confirm "$domain" "RUN SSL ANYWAY"
  run_cmd "${SUDO[@]}" nginx -t
  if have_cmd curl; then
    curl -fsSI --max-time 5 -H "Host: $domain" http://127.0.0.1 >/dev/null ||
      warn "local HTTP check did not return success for Host: $domain"
  fi
  public_ip="$(detect_public_ip || true)"
  [[ -n "$public_ip" ]] && info "Public IP for SSL context: $public_ip"

  local certbot_cmd=("${SUDO[@]}" certbot --nginx -d "$domain" --email "$email" --agree-tos --non-interactive)
  if [[ "$redirect" -eq 1 ]]; then
    certbot_cmd+=(--redirect)
  else
    certbot_cmd+=(--no-redirect)
  fi
  [[ "$staging" -eq 1 ]] && certbot_cmd+=(--staging)
  run_cmd "${certbot_cmd[@]}"
  run_cmd "${SUDO[@]}" certbot certificates
  if have_cmd curl; then
    curl -fsSI --max-time 10 "https://$domain" || warn "HTTPS validation did not succeed for $domain"
  fi
}

update_backup_index() {
  local site="$1"
  local backup_dir="$BENCH_DIR/sites/$site/private/backups"
  ensure_gitignore_entries
  if [[ "$DRY_RUN" -eq 1 ]]; then
    info "[DRY-RUN] would update $BACKUPS_INDEX"
    return 0
  fi
  {
    printf '\n## Backup: %s\n' "$(now_iso)"
    printf -- '- Site: %s\n' "$site"
    printf -- '- Backup directory: %s\n' "$backup_dir"
    if [[ -d "$backup_dir" ]]; then
      find "$backup_dir" -maxdepth 1 -type f -printf '- %TY-%Tm-%Td %TH:%TM %p\n' 2>/dev/null | sort | tail -n 12
    fi
  } >>"$BACKUPS_INDEX"
}

backup_site() {
  section "Backup Site"
  require_valid_bench
  local site
  select_site site
  if [[ "$DRY_RUN" -eq 1 ]]; then
    run_bench --site "$site" backup --with-files
    update_backup_index "$site"
    return 0
  fi
  local backup_log="$LOG_DIR/backup-$site-$TIMESTAMP.out"
  info "[RUN] bench --site $site backup --with-files"
  (cd "$BENCH_DIR" && bench --site "$site" backup --with-files) | tee "$backup_log"
  update_backup_index "$site"
  ok "backup complete. Output captured in $backup_log"
}

ensure_git_remote_origin() {
  if ! git_is_repo; then
    die "deploy update must run inside a Git repository: $REPO_ROOT"
  fi
  if git -C "$REPO_ROOT" remote get-url origin >/dev/null 2>&1; then
    info "Git origin: $(git -C "$REPO_ROOT" remote get-url origin)"
  else
    run_cmd git -C "$REPO_ROOT" remote add origin "$DEFAULT_REPO_URL"
    ok "configured Git origin: $DEFAULT_REPO_URL"
  fi
}

deploy_update() {
  section "Deploy Update"
  require_valid_bench

  local dirty
  if git_is_repo; then
    dirty="$(git_dirty_status || true)"
    if [[ -n "$dirty" ]]; then
      warn "Git working tree has local changes. Deploy update will use these local files unless you explicitly pull."
      printf '%s\n' "$dirty" | sed 's/^/  /'
    fi
  else
    warn "Deploy update is not running inside a Git repository; continuing with local files only."
  fi

  local site branch overwrite_mode="ask"
  select_site site

  if git_is_repo && confirm "Fetch/pull from Git remote before deploying? Local files are used by default." "N"; then
    ensure_git_remote_origin
    dirty="$(git_dirty_status || true)"
    if [[ -n "$dirty" ]]; then
      exact_confirm "CONTINUE WITH DIRTY TREE" "Git pull with local changes can fail or mix unreviewed work." ||
        die "dirty tree confirmation not provided"
    fi
    prompt_value branch "Git branch to deploy" "$(git_branch)" 1
    run_cmd git -C "$REPO_ROOT" fetch origin
    run_cmd git -C "$REPO_ROOT" pull --ff-only origin "$branch"
  else
    info "Skipping Git fetch/pull; deploying current local source tree."
  fi

  if confirm "Update existing bench app copies from apps?" "Y"; then
    overwrite_mode="yes"
  fi
  sync_validate_apps "$overwrite_mode"
  run_bench build
  run_bench --site "$site" migrate
  run_bench --site "$site" clear-cache
  run_bench --site "$site" clear-website-cache
  restart_frappe_supervisor
  run_cmd "${SUDO[@]}" systemctl reload nginx || run_cmd "${SUDO[@]}" service nginx reload
  status_report
}

service_status_line() {
  local svc="$1"
  if have_cmd systemctl && systemctl list-unit-files "$svc.service" >/dev/null 2>&1; then
    printf '%s: %s\n' "$svc" "$(systemctl is-active "$svc" 2>/dev/null || true)"
  elif have_cmd service; then
    printf '%s: service command available\n' "$svc"
  else
    printf '%s: unknown\n' "$svc"
  fi
}

site_apps_line() {
  local site="$1"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf '  %s: dry-run\n' "$site"
    return 0
  fi
  if (cd "$BENCH_DIR" && bench --site "$site" list-apps >/tmp/production-setup-apps.$$ 2>/dev/null); then
    printf '  %s:\n' "$site"
    sed 's/^/    /' /tmp/production-setup-apps.$$
    rm -f /tmp/production-setup-apps.$$
  else
    rm -f /tmp/production-setup-apps.$$
    printf '  %s: could not read app list\n' "$site"
  fi
}

latest_backup_location() {
  if [[ -d "$BENCH_DIR/sites" ]]; then
    find "$BENCH_DIR/sites" -path '*/private/backups/*' -type f -printf '%T@ %p\n' 2>/dev/null | sort -nr | awk 'NR==1 {$1=""; sub(/^ /, ""); print}'
  fi
}

status_report() {
  section "Status"
  printf 'Repo path: %s\n' "$REPO_ROOT"
  printf 'Git branch: %s\n' "$(git_branch)"
  printf 'Git remote: %s\n' "$(git_remote_url)"
  printf 'Bench path: %s\n' "$BENCH_DIR"
  if valid_bench; then
    printf 'Bench: valid\n'
  else
    printf 'Bench: missing or invalid\n'
  fi

  printf '\nSites:\n'
  local sites site
  sites="$(site_names || true)"
  if [[ -n "$sites" ]]; then
    printf '%s\n' "$sites" | sed 's/^/  /'
  else
    printf '  none\n'
  fi

  printf '\nApps per site:\n'
  if [[ -n "$sites" ]]; then
    while IFS= read -r site; do
      [[ -n "$site" ]] || continue
      site_apps_line "$site"
    done <<<"$sites"
  else
    printf '  none\n'
  fi

  printf '\nSupervisor status:\n'
  if have_cmd supervisorctl; then
    run_sudo_status supervisorctl status 2>/dev/null || printf '  supervisorctl unavailable or returned non-zero\n'
  else
    printf '  supervisorctl missing\n'
  fi

  printf '\nNginx status:\n'
  service_status_line nginx | sed 's/^/  /'
  if have_cmd nginx; then
    run_sudo_status nginx -t 2>&1 | sed 's/^/  /' || true
  else
    printf '  nginx missing\n'
  fi

  printf '\nPorts:\n'
  local port
  for port in 80 443 8000 9000 11000 12000 13000; do
    print_port_status_line "$port"
  done

  printf '\nHTTP checks:\n'
  if have_cmd curl && [[ -n "$sites" ]]; then
    while IFS= read -r site; do
      [[ -n "$site" ]] || continue
      local code
      code="$(curl -sS -o /dev/null -w "%{http_code}" --max-time 5 -H "Host: $site" http://127.0.0.1 2>/dev/null || true)"
      printf '  %s: %s\n' "$site" "${code:-unreachable}"
    done <<<"$sites"
  else
    printf '  skipped\n'
  fi

  printf '\nDisk:\n'
  df -h "$REPO_ROOT" | sed 's/^/  /'

  printf '\nServices:\n'
  service_status_line mariadb | sed 's/^/  /'
  service_status_line redis-server | sed 's/^/  /'

  printf '\nLatest backup:\n'
  local latest
  latest="$(latest_backup_location || true)"
  printf '  %s\n' "${latest:-none found}"
}

full_production_setup() {
  section "Full Production Setup"
  warn "Production mode is for real EC2/server deployment and uses nginx/supervisor."
  preflight_check
  confirm "Continue to Prepare Server Packages?" "Y" || return 0
  prepare_server_packages
  confirm "Continue to Setup / Validate Bench?" "Y" || return 0
  setup_validate_bench
  confirm "Continue to Sync and Validate Apps?" "Y" || return 0
  sync_validate_apps
  confirm "Continue to Create Production Site?" "Y" || return 0
  create_production_site
  confirm "Continue to Setup Supervisor + Nginx?" "Y" || return 0
  setup_supervisor_nginx
  setup_ssl
  status_report
}

production_menu() {
  while true; do
    printf '\n'
    printf '=============================================\n'
    printf ' Frappe Production / EC2 Deployment\n'
    printf '=============================================\n'
    printf 'Repo:  %s\n' "$REPO_ROOT"
    printf 'Bench: %s\n' "$BENCH_DIR"
    printf 'Log:   %s\n\n' "$LOG_FILE"
    printf '1) Full Production Setup\n'
    printf '2) Preflight Check\n'
    printf '3) Prepare Server Packages\n'
    printf '4) Setup / Validate Bench\n'
    printf '5) Sync and Validate Apps\n'
    printf '6) Create Production Site\n'
    printf '7) Setup Supervisor + Nginx\n'
    printf '8) Setup SSL\n'
    printf '9) Backup Site\n'
    printf '10) Deploy Update\n'
    printf '11) Status\n'
    printf '12) Exit\n'
    read -r -p "Choose: " choice
    case "${choice:-}" in
      1) full_production_setup ;;
      2) preflight_check ;;
      3) prepare_server_packages ;;
      4) setup_validate_bench ;;
      5) sync_validate_apps ;;
      6) create_production_site ;;
      7) setup_supervisor_nginx ;;
      8) setup_ssl ;;
      9) backup_site ;;
      10) deploy_update ;;
      11) status_report ;;
      12) info "bye"; exit 0 ;;
      *) warn "invalid option" ;;
    esac
  done
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run) DRY_RUN=1; shift ;;
      --yes|-y) ASSUME_YES=1; shift ;;
      --action)
        [[ $# -ge 2 ]] || die "--action requires a value"
        ACTION="$2"
        shift 2
        ;;
      --help|-h) usage; exit 0 ;;
      *) die "Unknown option: $1" ;;
    esac
  done
}

run_action() {
  case "$1" in
    full) full_production_setup ;;
    preflight) preflight_check ;;
    packages) prepare_server_packages ;;
    bench) setup_validate_bench ;;
    apps) sync_validate_apps ;;
    site) create_production_site ;;
    services) setup_supervisor_nginx ;;
    ssl) setup_ssl ;;
    backup) backup_site ;;
    deploy-update) deploy_update ;;
    status) status_report ;;
    *) die "Unknown action: $1" ;;
  esac
}

main() {
  parse_args "$@"
  section "Production Setup Launcher"
  printf 'Default repo URL: %s\n' "$DEFAULT_REPO_URL"
  printf 'Dry run: %s\n' "$DRY_RUN"
  printf 'Assume yes: %s\n' "$ASSUME_YES"
  printf 'Log file: %s\n' "$LOG_FILE"
  if [[ -n "$ACTION" ]]; then
    run_action "$ACTION"
  else
    production_menu
  fi
}

main "$@"
