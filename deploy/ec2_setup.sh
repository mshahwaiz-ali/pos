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
  printf '\n==================================================\n %s\n==================================================\n' "$*"
}

usage() {
  cat <<EOF2
Usage: deploy/production_setup.sh [options]

Production EC2/server deployment helper for Ledgix POS / Frappe v15.
This script never asks for a Linux sudo password. The server user must have
passwordless sudo (standard on Ubuntu EC2 images).

Options:
  --dry-run           Print intended changes without mutating the server
  --yes, -y           Use safe/default answers and avoid interactive prompts
  --action ACTION     Run one action and exit
                      Actions: full, preflight, packages, bench, apps, site,
                               services, ssl, backup, deploy-update, status
  --help, -h          Show this help

Useful environment variables:
  FRAPPE_BRANCH           Default: $FRAPPE_BRANCH
  NODE_MAJOR              Default: $NODE_MAJOR
  BENCH_DIR               Default: ./frappe-bench
  APP_NAME                Default: auto-detect (normally ledgix_saas)
  PRODUCTION_SITE         Default for --yes: ledgix.local
  PRODUCTION_DOMAIN       Optional; required only for SSL
  LETSENCRYPT_EMAIL       Required only for SSL
  FRAPPE_ADMIN_PASSWORD   Optional; auto-generated when omitted
EOF2
}

have_cmd() { command -v "$1" >/dev/null 2>&1; }
resolve_cmd() { command -v "$1" 2>/dev/null || true; }

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
  [[ "$DRY_RUN" -eq 1 ]] && return 0
  "$@"
}

run_cmd_label() {
  local label="$1"
  shift
  info "[RUN] $label"
  [[ "$DRY_RUN" -eq 1 ]] && return 0
  "$@"
}

need_sudo() {
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    SUDO=()
    return 0
  fi
  have_cmd sudo || die "sudo is required for production setup"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    SUDO=(sudo -n)
    return 0
  fi
  sudo -n true >/dev/null 2>&1 || die "passwordless sudo is required; this script will not prompt for a Linux password"
  SUDO=(sudo -n)
}

sudo_available_noninteractive() {
  [[ "${EUID:-$(id -u)}" -eq 0 ]] && return 0
  have_cmd sudo || return 1
  sudo -n true >/dev/null 2>&1
}

sudo_env_cmd() {
  local sudo_user
  need_sudo
  sudo_user="${USER:-$(id -un)}"
  run_cmd "${SUDO[@]}" env "PATH=$PATH" "HOME=$HOME" "USER=$sudo_user" "$@"
}

run_sudo_status() {
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    "$@"
  elif sudo_available_noninteractive; then
    sudo -n "$@"
  else
    "$@"
  fi
}

bench_cmd() {
  local b
  b="$(resolve_cmd bench)"
  [[ -n "$b" ]] || die "bench command not found in PATH. Run --action packages first."
  printf '%s\n' "$b"
}

run_bench() {
  local b
  b="$(bench_cmd)"
  info "[RUN] bench $*"
  [[ "$DRY_RUN" -eq 1 ]] && return 0
  (cd "$BENCH_DIR" && "$b" "$@")
}

run_bench_label() {
  local label="$1" b
  shift
  b="$(bench_cmd)"
  info "[RUN] $label"
  [[ "$DRY_RUN" -eq 1 ]] && return 0
  (cd "$BENCH_DIR" && "$b" "$@")
}

confirm() {
  local prompt="$1" default="${2:-N}" answer suffix
  if [[ "$ASSUME_YES" -eq 1 ]]; then
    if [[ "$default" =~ ^[Yy]$ ]]; then
      info "Using default yes: $prompt"
      return 0
    fi
    info "Using default no: $prompt"
    return 1
  fi
  if [[ "$default" =~ ^[Yy]$ ]]; then suffix='Y/n'; else suffix='y/N'; fi
  read -r -p "$prompt [$suffix]: " answer
  answer="${answer:-$default}"
  [[ "$answer" =~ ^([Yy]|[Yy][Ee][Ss])$ ]]
}

prompt_value() {
  local -n _out="$1"
  local prompt="$2" default="${3:-}" required="${4:-0}" answer
  if [[ "$ASSUME_YES" -eq 1 ]]; then
    if [[ -n "$default" ]]; then
      _out="$default"
      info "$prompt: $default"
      return 0
    fi
    [[ "$required" -eq 0 ]] || die "$prompt is required in --yes mode"
    _out=""
    return 0
  fi
  if [[ -n "$default" ]]; then
    read -r -p "$prompt [$default]: " answer
    _out="${answer:-$default}"
  else
    while true; do
      read -r -p "$prompt: " answer
      if [[ -n "$answer" || "$required" -eq 0 ]]; then _out="$answer"; return 0; fi
      warn "value is required"
    done
  fi
}

now_iso() { date '+%Y-%m-%d %H:%M:%S %z'; }
lowercase() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

strong_password() {
  if have_cmd openssl; then
    openssl rand -base64 42 | tr -d '\n' | cut -c 1-40
  else
    printf '%s%s' "$(date +%s%N)" "$RANDOM" | sha256sum | cut -c 1-40
  fi
}

random_hex() {
  if have_cmd openssl; then openssl rand -hex "$1"; else date +%s%N | sha256sum | cut -c "1-$(( $1 * 2 ))"; fi
}

make_db_name() { printf 'site_%s' "$(random_hex 8)"; }
make_db_password() { strong_password; }
safe_db_name() { [[ -n "$1" && "$1" =~ ^[A-Za-z0-9_]+$ ]]; }
sql_quote() { printf '%s' "$1" | sed "s/'/''/g"; }
sql_identifier() { printf '%s' "$1" | sed 's/`/``/g'; }

valid_bench() {
  [[ -d "$BENCH_DIR/apps/frappe" ]] || return 1
  [[ -d "$BENCH_DIR/sites" ]] || return 1
  [[ -x "$BENCH_DIR/env/bin/python" ]] || return 1
  [[ -f "$BENCH_DIR/Procfile" ]] || return 1
  [[ -f "$BENCH_DIR/sites/common_site_config.json" ]] || return 1
}

require_valid_bench() { valid_bench || die "valid Frappe bench not found at $BENCH_DIR"; }

site_names() {
  [[ -d "$BENCH_DIR/sites" ]] || return 0
  find "$BENCH_DIR/sites" -mindepth 1 -maxdepth 1 -type d \
    ! -name assets ! -name archived \
    -exec test -f "{}/site_config.json" \; -printf '%f\n' 2>/dev/null | sort
}

is_system_app() {
  case "$1" in frappe|erpnext|payments|hrms|print_designer) return 0 ;; *) return 1 ;; esac
}

valid_custom_app_dir() {
  local dir="$1" hook
  [[ -d "$dir" ]] || return 1
  [[ -f "$dir/hooks.py" && -f "$dir/__init__.py" ]] && return 0
  for hook in "$dir"/*/hooks.py; do
    [[ -f "$hook" && -f "$(dirname "$hook")/__init__.py" ]] && return 0
  done
  return 1
}

discover_source_apps() {
  [[ -d "$APPS_SRC" ]] || return 0
  local dir name
  for dir in "$APPS_SRC"/*; do
    [[ -d "$dir" ]] || continue
    name="$(basename "$dir")"
    is_system_app "$name" && continue
    valid_custom_app_dir "$dir" && printf '%s\n' "$name"
  done | sort
}

discover_bench_custom_apps() {
  [[ -d "$BENCH_DIR/apps" ]] || return 0
  local dir name
  for dir in "$BENCH_DIR/apps"/*; do
    [[ -d "$dir" ]] || continue
    name="$(basename "$dir")"
    is_system_app "$name" && continue
    valid_custom_app_dir "$dir" && printf '%s\n' "$name"
  done | sort
}

ensure_app_in_apps_txt() {
  local app="$1" apps_txt="$BENCH_DIR/sites/apps.txt"
  [[ "$DRY_RUN" -eq 1 ]] && return 0
  touch "$apps_txt"
  grep -Fxq "$app" "$apps_txt" 2>/dev/null || printf '%s\n' "$app" >>"$apps_txt"
}

site_has_app() {
  local site="$1" app="$2"
  [[ "$DRY_RUN" -eq 1 ]] && return 1
  (cd "$BENCH_DIR" && bench --site "$site" list-apps 2>/dev/null | awk '{print $1}' | grep -Fxq "$app")
}

select_site() {
  local -n _site="$1"
  local sites=() choice idx candidate
  mapfile -t sites < <(site_names)
  [[ "${#sites[@]}" -gt 0 ]] || die "no Frappe sites found"
  if [[ -n "${PRODUCTION_SITE:-}" ]]; then
    candidate="$(lowercase "$PRODUCTION_SITE")"
    for _site in "${sites[@]}"; do [[ "$_site" == "$candidate" ]] && return 0; done
  fi
  if [[ "${#sites[@]}" -eq 1 ]]; then _site="${sites[0]}"; return 0; fi
  [[ "$ASSUME_YES" -eq 0 ]] || die "multiple sites found; set PRODUCTION_SITE"
  printf 'Available sites:\n'
  local i
  for i in "${!sites[@]}"; do printf '  %d) %s\n' "$((i+1))" "${sites[$i]}"; done
  while true; do
    read -r -p 'Choose site: ' choice
    [[ "$choice" =~ ^[0-9]+$ ]] || { warn 'invalid site selection'; continue; }
    idx=$((choice-1))
    if (( idx >= 0 && idx < ${#sites[@]} )); then _site="${sites[$idx]}"; return 0; fi
  done
}

select_app() {
  local -n _app="$1"
  local apps=() candidate
  mapfile -t apps < <(discover_bench_custom_apps)
  [[ "${#apps[@]}" -gt 0 ]] || die "no custom app found in bench; run --action apps first"
  candidate="${APP_NAME:-}"
  if [[ -n "$candidate" ]]; then
    for _app in "${apps[@]}"; do [[ "$_app" == "$candidate" ]] && return 0; done
    die "APP_NAME is not available in bench: $candidate"
  fi
  if [[ "${#apps[@]}" -eq 1 ]]; then _app="${apps[0]}"; return 0; fi
  [[ "$ASSUME_YES" -eq 0 ]] || die "multiple custom apps found; set APP_NAME"
  local i choice idx
  for i in "${!apps[@]}"; do printf '  %d) %s\n' "$((i+1))" "${apps[$i]}"; done
  while true; do
    read -r -p 'Choose app: ' choice
    [[ "$choice" =~ ^[0-9]+$ ]] || continue
    idx=$((choice-1))
    if (( idx >= 0 && idx < ${#apps[@]} )); then _app="${apps[$idx]}"; return 0; fi
  done
}

ensure_secrets_file() {
  [[ "$DRY_RUN" -eq 1 ]] && return 0
  umask 077
  if [[ ! -f "$SECRETS_FILE" ]]; then
    printf '# Frappe Production Secrets\n\nGenerated by deploy/production_setup.sh. Do not commit this file.\n' >"$SECRETS_FILE"
  fi
  chmod 600 "$SECRETS_FILE"
}

append_site_secret() {
  local site="$1" admin_password="$2" db_name="$3" db_password="$4" app="$5"
  ensure_secrets_file
  [[ "$DRY_RUN" -eq 1 ]] && return 0
  {
    printf '\n## Site: %s\n' "$site"
    printf -- '- Site name: %s\n' "$site"
    printf -- '- Admin user: Administrator\n'
    printf -- '- Admin password: %s\n' "$admin_password"
    printf -- '- DB name/user: %s\n' "$db_name"
    printf -- '- DB password: %s\n' "$db_password"
    printf -- '- App: %s\n' "$app"
    printf -- '- Timestamp: %s\n' "$(now_iso)"
  } >>"$SECRETS_FILE"
  ok "credentials saved to $SECRETS_FILE"
}

detect_public_ip() {
  have_cmd curl || return 1
  curl -fsS --max-time 4 https://api.ipify.org 2>/dev/null || curl -fsS --max-time 4 https://ifconfig.me 2>/dev/null
}

port_listeners() {
  local port="$1"
  if have_cmd ss; then
    ss -ltnp 2>/dev/null | awk -v port="$port" '$4 ~ ":" port "$" {print}' || true
  elif have_cmd lsof; then
    lsof -nP -iTCP:"$port" -sTCP:LISTEN 2>/dev/null || true
  fi
}

preflight_check() {
  section 'Preflight Check'
  local os_name='unknown' cmd public_ip
  [[ -r /etc/os-release ]] && os_name="$(. /etc/os-release && printf '%s' "${PRETTY_NAME:-$NAME}")"
  printf 'Repo root: %s\nBench path: %s\nOS: %s\nArchitecture: %s\nCPU: %s\nMemory: %s\nSwap: %s\nDisk: %s\n' \
    "$REPO_ROOT" "$BENCH_DIR" "$os_name" "$(uname -m)" "$(nproc)" \
    "$(free -h | awk '/^Mem:/ {print $2}')" "$(free -h | awk '/^Swap:/ {print $2}')" \
    "$(df -h "$REPO_ROOT" | awk 'NR==2 {print $4 " free"}')"

  if [[ "${EUID:-$(id -u)}" -eq 0 ]] || sudo_available_noninteractive; then
    ok 'passwordless sudo available'
  else
    err 'passwordless sudo unavailable'
  fi

  if git -C "$REPO_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    ok "git branch: $(git -C "$REPO_ROOT" branch --show-current)"
    ok "git commit: $(git -C "$REPO_ROOT" rev-parse --short HEAD)"
    if [[ -n "$(git -C "$REPO_ROOT" status --short)" ]]; then warn 'git working tree has local changes'; else ok 'git working tree clean'; fi
  fi

  for cmd in git curl python3 pipx mariadb redis-server node npm yarn bench nginx supervisorctl certbot; do
    if have_cmd "$cmd"; then ok "command: $cmd"; else warn "command missing: $cmd"; fi
  done

  public_ip="$(detect_public_ip || true)"
  [[ -n "$public_ip" ]] && ok "public IP: $public_ip" || warn 'public IP could not be detected'

  if valid_bench; then ok "bench valid: $BENCH_DIR"; else warn "bench not initialized: $BENCH_DIR"; fi
  printf 'Source apps:\n'
  discover_source_apps | sed 's/^/  /' || true
  printf 'Sites:\n'
  site_names | sed 's/^/  /' || true
  printf 'Ports:\n'
  local port listeners
  for port in 80 443 8000 9000 11000 12000 13000; do
    listeners="$(port_listeners "$port")"
    [[ -n "$listeners" ]] && printf '  %s: listening\n' "$port" || printf '  %s: free\n' "$port"
  done
}

apt_has_candidate() {
  apt-cache policy "$1" 2>/dev/null | awk '/Candidate:/ {print $2}' | grep -qxv '(none)'
}

install_packages_batch() {
  local kind="$1"
  shift
  local requested=("$@") missing=() pkg
  for pkg in "${requested[@]}"; do
    if dpkg -s "$pkg" >/dev/null 2>&1; then
      info "skip installed package: $pkg"
    elif apt_has_candidate "$pkg"; then
      missing+=("$pkg")
    elif [[ "$kind" == 'required' ]]; then
      die "required package has no apt candidate: $pkg"
    else
      warn "optional package unavailable: $pkg"
    fi
  done
  [[ "${#missing[@]}" -gt 0 ]] || return 0
  run_cmd "${SUDO[@]}" env DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a apt-get install -y "${missing[@]}"
}

ensure_service_started() {
  local svc="$1"
  if have_cmd systemctl && systemctl list-unit-files "$svc.service" >/dev/null 2>&1; then
    run_cmd "${SUDO[@]}" systemctl enable --now "$svc"
  elif have_cmd service; then
    run_cmd "${SUDO[@]}" service "$svc" start
  fi
}

ensure_nvm() {
  export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
  if [[ ! -s "$NVM_DIR/nvm.sh" ]]; then
    have_cmd curl || die 'curl is required to install nvm'
    run_cmd_label "install nvm $NVM_INSTALL_VERSION" bash -c "curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_INSTALL_VERSION}/install.sh | bash"
  fi
  [[ "$DRY_RUN" -eq 1 ]] && return 0
  [[ -s "$NVM_DIR/nvm.sh" ]] || die "nvm installation failed: $NVM_DIR/nvm.sh missing"
  # shellcheck disable=SC1090
  . "$NVM_DIR/nvm.sh"
}

ensure_node() {
  section 'Node + Yarn'
  refresh_path
  ensure_nvm
  if [[ "$DRY_RUN" -eq 0 ]]; then . "$NVM_DIR/nvm.sh"; fi
  run_cmd nvm install "$NODE_MAJOR"
  run_cmd nvm alias default "$NODE_MAJOR"
  run_cmd nvm use "$NODE_MAJOR"
  refresh_path
  if [[ "$DRY_RUN" -eq 0 ]]; then
    [[ "$(node -v | sed -E 's/^v([0-9]+).*/\1/')" == "$NODE_MAJOR" ]] || die "expected Node $NODE_MAJOR, got $(node -v)"
  fi
  if [[ "$DRY_RUN" -eq 1 ]] || ! have_cmd yarn; then
    run_cmd npm install -g yarn@1.22.22
  fi
}

ensure_pipx_tools() {
  section 'Python CLI tools'
  refresh_path
  have_cmd pipx || die 'pipx missing after package installation'
  run_cmd pipx ensurepath || true
  refresh_path
  if ! have_cmd uv; then run_cmd pipx install uv; fi
  if ! have_cmd bench; then run_cmd pipx install frappe-bench; fi
  refresh_path
  [[ "$DRY_RUN" -eq 1 ]] || have_cmd bench || die 'bench command unavailable after install'
}

prepare_server_packages() {
  section 'Prepare Server Packages'
  have_cmd apt-get || die 'apt-get is required'
  need_sudo
  run_cmd "${SUDO[@]}" env DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a apt-get update
  run_cmd "${SUDO[@]}" env DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a apt-get --fix-broken install -y

  local required=(
    git curl ca-certificates gnupg build-essential pkg-config
    python3 python3-dev python3-pip python3-venv python3-setuptools pipx
    redis-server mariadb-server mariadb-client nginx supervisor certbot cron
    libffi-dev libssl-dev libmysqlclient-dev libjpeg-dev zlib1g-dev
    liblcms2-dev libwebp-dev libxrender1 libxext6 fontconfig xfonts-75dpi xfonts-base
  )
  local optional=(python3-certbot-nginx ufw wkhtmltopdf)
  install_packages_batch required "${required[@]}"
  install_packages_batch optional "${optional[@]}"
  if apt_has_candidate libtiff-dev; then install_packages_batch required libtiff-dev; elif apt_has_candidate libtiff5-dev; then install_packages_batch required libtiff5-dev; fi

  ensure_service_started mariadb
  ensure_service_started redis-server
  ensure_service_started nginx
  ensure_service_started supervisor
  ensure_node
  ensure_pipx_tools
  ok 'server package preparation complete'
}

setup_validate_bench() {
  section 'Setup / Validate Bench'
  refresh_path
  have_cmd bench || ensure_pipx_tools
  if valid_bench; then
    ok "reusing valid bench: $BENCH_DIR"
  elif [[ -e "$BENCH_DIR" ]]; then
    die "bench path exists but is incomplete: $BENCH_DIR"
  else
    info "initializing Frappe $FRAPPE_BRANCH bench"
    run_cmd bench init --frappe-branch "$FRAPPE_BRANCH" "$BENCH_DIR"
    valid_bench || die 'bench init completed but validation failed'
  fi
  run_bench set-config -g developer_mode 0
  run_bench set-config -g serve_default_site true
  ok 'bench configuration validated'
}

sync_validate_apps() {
  section 'Sync and Validate Apps'
  require_valid_bench
  local app src dest ready=()
  while IFS= read -r app; do
    [[ -n "$app" ]] || continue
    src="$APPS_SRC/$app"
    dest="$BENCH_DIR/apps/$app"
    if [[ -d "$dest" ]]; then
      run_cmd cp -a "$src/." "$dest/"
      info "updated bench app from repo: $app"
    else
      run_cmd cp -a "$src" "$dest"
      info "copied app into bench: $app"
    fi
    if [[ "$DRY_RUN" -eq 0 ]]; then
      "$BENCH_DIR/env/bin/python" -m pip install -e "$dest"
      "$BENCH_DIR/env/bin/python" -c "import importlib; importlib.import_module('$app')" >/dev/null
      ensure_app_in_apps_txt "$app"
    fi
    ready+=("$app")
  done < <(discover_source_apps)
  [[ "${#ready[@]}" -gt 0 ]] || die "no valid custom apps found under $APPS_SRC"
  run_bench build
  printf 'Production-ready apps:\n  %s\n' "${ready[*]}"
}

create_database_sql() {
  local db_name="$1" db_password="$2" user_q pass_q ident
  user_q="$(sql_quote "$db_name")"
  pass_q="$(sql_quote "$db_password")"
  ident="$(sql_identifier "$db_name")"
  cat <<SQL
CREATE DATABASE IF NOT EXISTS \`$ident\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '$user_q'@'localhost' IDENTIFIED BY '$pass_q';
ALTER USER '$user_q'@'localhost' IDENTIFIED BY '$pass_q';
GRANT ALL PRIVILEGES ON \`$ident\`.* TO '$user_q'@'localhost';
FLUSH PRIVILEGES;
SQL
}

drop_database_sql() {
  local db_name="$1" user_q ident
  user_q="$(sql_quote "$db_name")"
  ident="$(sql_identifier "$db_name")"
  cat <<SQL
DROP DATABASE IF EXISTS \`$ident\`;
DROP USER IF EXISTS '$user_q'@'localhost';
FLUSH PRIVILEGES;
SQL
}

mariadb_socket_auth_available() {
  need_sudo
  [[ "$DRY_RUN" -eq 1 ]] && return 0
  "${SUDO[@]}" mariadb -e 'SELECT 1;' >/dev/null 2>&1
}

create_database_and_user() {
  local db_name="$1" db_password="$2"
  safe_db_name "$db_name" || die "unsafe DB name: $db_name"
  mariadb_socket_auth_available || die 'MariaDB root socket auth is unavailable; production setup will not ask for a database root password'
  info "creating MariaDB database/user via passwordless sudo socket auth"
  [[ "$DRY_RUN" -eq 1 ]] && return 0
  create_database_sql "$db_name" "$db_password" | "${SUDO[@]}" mariadb
}

drop_database_and_user() {
  local db_name="$1"
  safe_db_name "$db_name" || return 1
  mariadb_socket_auth_available || return 1
  [[ "$DRY_RUN" -eq 1 ]] && return 0
  drop_database_sql "$db_name" | "${SUDO[@]}" mariadb
}

read_admin_password() {
  local -n _password="$1"
  if [[ -n "${FRAPPE_ADMIN_PASSWORD:-}" ]]; then
    _password="$FRAPPE_ADMIN_PASSWORD"
    return 0
  fi
  if [[ "$ASSUME_YES" -eq 1 ]]; then
    _password="$(strong_password)"
    return 0
  fi
  local first second
  read -r -s -p 'Administrator password (Enter = auto-generate): ' first; printf '\n'
  if [[ -z "$first" ]]; then _password="$(strong_password)"; return 0; fi
  read -r -s -p 'Confirm Administrator password: ' second; printf '\n'
  [[ "$first" == "$second" ]] || die 'Administrator passwords did not match'
  _password="$first"
}

create_production_site() {
  section 'Create Production Site'
  require_valid_bench
  local site app admin_password db_name db_password default_site
  default_site="${PRODUCTION_SITE:-ledgix.local}"
  prompt_value site 'Site name' "$default_site" 1
  site="$(lowercase "$site")"
  [[ "$site" =~ ^[a-z0-9][a-z0-9.-]*$ ]] || die "invalid site name: $site"
  select_app app

  if [[ -d "$BENCH_DIR/sites/$site" ]]; then
    warn "site already exists: $site"
    if ! site_has_app "$site" "$app"; then run_bench --site "$site" install-app "$app"; fi
    run_bench --site "$site" migrate
    run_bench --site "$site" enable-scheduler || true
    run_bench use "$site"
    run_bench set-config -g serve_default_site true
    run_bench --site "$site" clear-cache
    return 0
  fi

  read_admin_password admin_password
  db_name="$(make_db_name)"
  db_password="$(make_db_password)"
  create_database_and_user "$db_name" "$db_password"

  if ! run_bench_label "bench new-site $site --admin-password [redacted] --db-name $db_name --db-password [redacted] --no-setup-db" \
      new-site "$site" --admin-password "$admin_password" --db-name "$db_name" --db-password "$db_password" --no-setup-db; then
    warn 'site creation failed; cleaning the newly-created database/user'
    drop_database_and_user "$db_name" || true
    return 1
  fi

  run_bench --site "$site" install-app "$app"
  run_bench --site "$site" migrate
  run_bench --site "$site" enable-scheduler || true
  run_bench use "$site"
  run_bench set-config -g serve_default_site true
  run_bench --site "$site" clear-cache
  run_bench --site "$site" clear-website-cache
  append_site_secret "$site" "$admin_password" "$db_name" "$db_password" "$app"
  ok "site ready: $site"
}

disable_nginx_default() {
  local path
  for path in /etc/nginx/sites-enabled/default /etc/nginx/conf.d/default.conf; do
    [[ -e "$path" ]] || continue
    run_cmd "${SUDO[@]}" mv "$path" "$path.disabled-$TIMESTAMP"
  done
}

restart_frappe_supervisor() {
  need_sudo
  local bench_name group groups
  bench_name="$(basename "$BENCH_DIR")"
  groups="$("${SUDO[@]}" supervisorctl status 2>/dev/null | awk -v prefix="$bench_name-" '$1 ~ "^" prefix {split($1,a,":"); print a[1]}' | sort -u || true)"
  if [[ -n "$groups" ]]; then
    while IFS= read -r group; do [[ -n "$group" ]] && run_cmd "${SUDO[@]}" supervisorctl restart "$group:" || true; done <<<"$groups"
  else
    run_cmd "${SUDO[@]}" supervisorctl restart frappe-bench-web: || true
    run_cmd "${SUDO[@]}" supervisorctl restart frappe-bench-workers: || true
  fi
}

setup_supervisor_nginx() {
  section 'Setup Supervisor + Nginx'
  require_valid_bench
  need_sudo
  run_bench setup supervisor
  run_bench setup nginx
  run_cmd "${SUDO[@]}" ln -sfn "$BENCH_DIR/config/supervisor.conf" /etc/supervisor/conf.d/frappe-bench.conf
  run_cmd "${SUDO[@]}" ln -sfn "$BENCH_DIR/config/nginx.conf" /etc/nginx/conf.d/frappe-bench.conf
  disable_nginx_default
  run_cmd "${SUDO[@]}" supervisorctl reread
  run_cmd "${SUDO[@]}" supervisorctl update
  restart_frappe_supervisor
  run_cmd "${SUDO[@]}" nginx -t
  run_cmd "${SUDO[@]}" systemctl reload nginx
  ok 'Supervisor + Nginx configured'
}

setup_ssl() {
  section 'Setup SSL'
  local domain="${PRODUCTION_DOMAIN:-}" email="${LETSENCRYPT_EMAIL:-}" site
  if [[ -z "$domain" || -z "$email" ]]; then
    if [[ "$ASSUME_YES" -eq 1 ]]; then
      warn 'PRODUCTION_DOMAIN / LETSENCRYPT_EMAIL not set; SSL skipped'
      return 0
    fi
    prompt_value domain 'Production domain' "$domain" 1
    prompt_value email 'LetsEncrypt email' "$email" 1
  fi
  need_sudo
  have_cmd certbot || die 'certbot missing; run --action packages first'
  select_site site
  run_bench --site "$site" set-config host_name "https://$domain"
  run_cmd "${SUDO[@]}" nginx -t
  run_cmd "${SUDO[@]}" certbot --nginx -d "$domain" --email "$email" --agree-tos --non-interactive --redirect
  ok "SSL configured: https://$domain"
}

backup_site() {
  section 'Backup Site'
  require_valid_bench
  local site
  select_site site
  run_bench --site "$site" backup --with-files
  [[ "$DRY_RUN" -eq 1 ]] && return 0
  {
    printf '\n## Backup %s\n- Site: %s\n- Directory: %s\n' "$(now_iso)" "$site" "$BENCH_DIR/sites/$site/private/backups"
  } >>"$BACKUPS_INDEX"
  ok "backup complete: $site"
}

git_dirty() { [[ -n "$(git -C "$REPO_ROOT" status --short 2>/dev/null || true)" ]]; }

deploy_update() {
  section 'Deploy Update'
  require_valid_bench
  local site branch
  select_site site
  if git -C "$REPO_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    if git_dirty; then
      die 'repository has local changes; commit/stash them before deploy-update'
    fi
    branch="${DEPLOY_BRANCH:-$(git -C "$REPO_ROOT" branch --show-current)}"
    run_cmd git -C "$REPO_ROOT" fetch origin "$branch"
    run_cmd git -C "$REPO_ROOT" pull --ff-only origin "$branch"
  fi
  sync_validate_apps
  run_bench --site "$site" migrate
  run_bench --site "$site" clear-cache
  run_bench --site "$site" clear-website-cache
  restart_frappe_supervisor
  need_sudo
  run_cmd "${SUDO[@]}" nginx -t
  run_cmd "${SUDO[@]}" systemctl reload nginx
  status_report
}

service_status() {
  local svc="$1"
  if have_cmd systemctl && systemctl list-unit-files "$svc.service" >/dev/null 2>&1; then
    systemctl is-active "$svc" 2>/dev/null || true
  else
    printf 'unknown'
  fi
}

status_report() {
  section 'Status'
  printf 'Repo: %s\nBench: %s\n' "$REPO_ROOT" "$BENCH_DIR"
  if git -C "$REPO_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    printf 'Git: %s @ %s\n' "$(git -C "$REPO_ROOT" branch --show-current)" "$(git -C "$REPO_ROOT" rev-parse --short HEAD)"
  fi
  printf 'Bench status: '; valid_bench && printf 'valid\n' || printf 'missing/invalid\n'
  printf 'Sites:\n'
  local site sites
  sites="$(site_names || true)"
  if [[ -n "$sites" ]]; then
    while IFS= read -r site; do
      printf '  %s\n' "$site"
      if valid_bench; then (cd "$BENCH_DIR" && bench --site "$site" list-apps 2>/dev/null | sed 's/^/    /') || true; fi
    done <<<"$sites"
  else
    printf '  none\n'
  fi
  printf 'Services:\n  mariadb: %s\n  redis-server: %s\n  nginx: %s\n  supervisor: %s\n' \
    "$(service_status mariadb)" "$(service_status redis-server)" "$(service_status nginx)" "$(service_status supervisor)"
  if have_cmd supervisorctl; then run_sudo_status supervisorctl status 2>/dev/null || true; fi
  if have_cmd nginx; then run_sudo_status nginx -t 2>&1 || true; fi
  printf 'Disk:\n'; df -h "$REPO_ROOT" | sed 's/^/  /'
}

full_production_setup() {
  section 'Full Production Setup'
  preflight_check
  prepare_server_packages
  setup_validate_bench
  sync_validate_apps
  create_production_site
  setup_supervisor_nginx
  if [[ -n "${PRODUCTION_DOMAIN:-}" && -n "${LETSENCRYPT_EMAIL:-}" ]]; then setup_ssl; else info 'SSL skipped (no production domain/email yet)'; fi
  status_report
}

production_menu() {
  while true; do
    printf '\n=============================================\n Frappe Production / EC2 Deployment\n=============================================\n'
    printf '1) Full Production Setup\n2) Preflight Check\n3) Prepare Server Packages\n4) Setup / Validate Bench\n5) Sync and Validate Apps\n6) Create Production Site\n7) Setup Supervisor + Nginx\n8) Setup SSL\n9) Backup Site\n10) Deploy Update\n11) Status\n12) Exit\n'
    read -r -p 'Choose: ' choice
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
      12) exit 0 ;;
      *) warn 'invalid option' ;;
    esac
  done
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run) DRY_RUN=1; shift ;;
      --yes|-y) ASSUME_YES=1; shift ;;
      --action) [[ $# -ge 2 ]] || die '--action requires a value'; ACTION="$2"; shift 2 ;;
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
  section 'Production Setup Launcher'
  printf 'Repo: %s\nBench: %s\nFrappe: %s\nNode: %s\nDry run: %s\nAssume defaults: %s\nLog: %s\n' \
    "$REPO_ROOT" "$BENCH_DIR" "$FRAPPE_BRANCH" "$NODE_MAJOR" "$DRY_RUN" "$ASSUME_YES" "$LOG_FILE"
  if [[ -n "$ACTION" ]]; then run_action "$ACTION"; else production_menu; fi
}

main "$@"
