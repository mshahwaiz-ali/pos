#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BENCH_DIR="${BENCH_DIR:-$REPO_ROOT/frappe-bench}"
RUNNER_DIR="$BENCH_DIR/.runner"
MODE="${1:-status}"

info() { printf '[INFO] %s\n' "$*"; }
ok() { printf '[OK] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*" >&2; }

[[ -d "$BENCH_DIR/config" ]] || exit 0
mkdir -p "$RUNNER_DIR"

port_from_conf() {
  awk '$1 == "port" {print $2; exit}' "$1" 2>/dev/null
}

port_open() {
  local port="$1"
  [[ -n "$port" ]] || return 1
  timeout 1 bash -c ":</dev/tcp/127.0.0.1/$port" >/dev/null 2>&1
}

start_one() {
  local name conf pidfile port pid
  name="$1"
  conf="$2"
  pidfile="$RUNNER_DIR/temp_${name}.pid"

  [[ -f "$conf" ]] || { warn "missing Redis config: $conf"; return 1; }
  port="$(port_from_conf "$conf")"
  [[ -n "$port" ]] || { warn "could not read Redis port from $conf"; return 1; }

  if port_open "$port"; then
    info "$name already reachable on 127.0.0.1:$port"
    return 0
  fi

  info "starting temporary $name on 127.0.0.1:$port"
  redis-server "$conf" --daemonize yes --pidfile "$pidfile"

  for _ in {1..20}; do
    if port_open "$port"; then
      ok "$name is ready on port $port"
      return 0
    fi
    sleep 0.25
  done

  if [[ -f "$pidfile" ]]; then
    pid="$(cat "$pidfile" 2>/dev/null || true)"
    [[ "$pid" =~ ^[0-9]+$ ]] && kill "$pid" 2>/dev/null || true
    rm -f "$pidfile"
  fi
  warn "$name failed to start on port $port"
  return 1
}

stop_one() {
  local name pidfile pid
  name="$1"
  pidfile="$RUNNER_DIR/temp_${name}.pid"

  [[ -f "$pidfile" ]] || return 0
  pid="$(cat "$pidfile" 2>/dev/null || true)"
  if [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null; then
    info "stopping temporary $name PID $pid"
    kill "$pid" 2>/dev/null || true
    for _ in {1..20}; do
      kill -0 "$pid" 2>/dev/null || break
      sleep 0.25
    done
  fi
  rm -f "$pidfile"
}

status_one() {
  local name conf port
  name="$1"
  conf="$2"

  [[ -f "$conf" ]] || { printf '%s: config missing\n' "$name"; return 0; }
  port="$(port_from_conf "$conf")"
  if port_open "$port"; then
    printf '%s: reachable on %s\n' "$name" "$port"
  else
    printf '%s: stopped on %s\n' "$name" "$port"
  fi
}

CACHE_CONF="$BENCH_DIR/config/redis_cache.conf"
QUEUE_CONF="$BENCH_DIR/config/redis_queue.conf"

case "$MODE" in
  start)
    command -v redis-server >/dev/null 2>&1 || { warn 'redis-server command missing'; exit 1; }
    start_one redis_cache "$CACHE_CONF"
    start_one redis_queue "$QUEUE_CONF"
    ;;
  stop)
    stop_one redis_cache
    stop_one redis_queue
    ;;
  status)
    status_one redis_cache "$CACHE_CONF"
    status_one redis_queue "$QUEUE_CONF"
    ;;
  *)
    printf 'Usage: %s {start|stop|status}\n' "$0" >&2
    exit 2
    ;;
esac
