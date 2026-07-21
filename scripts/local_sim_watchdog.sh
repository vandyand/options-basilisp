#!/usr/bin/env bash
# Local sim watchdog. Safe to run repeatedly from cron.
#
# Responsibilities:
#   - keep the Hetzner ThetaData SSH tunnel available locally
#   - keep the base local sim session running
#   - keep the V2 VOL sidecar running under its own sim account/process
#
# This is intentionally local-only. It never starts/stops Hetzner live Alpaca
# services and never controls the remote Theta terminal lifecycle.

set -uo pipefail

REPO="${STEVE_REPO_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
DEFAULT_REF="$HOME/contracting/upwork/steven-tran/SteveTrading/ref/Data-Preprocessor"
REF="${STEVE_REF_ROOT:-$DEFAULT_REF}"
BASILISP="${BASILISP_BIN:-$REPO/.venv/bin/basilisp}"
REF_BASILISP="${REF_BASILISP_BIN:-$REF/.venv/bin/basilisp}"
THETA_HOST="${THETA_HOST:-bot@167.233.141.61}"
THETA_HEALTH_URL="${THETA_HEALTH_URL:-http://127.0.0.1:25503/v3/option/list/expirations?symbol=SPY}"
THETA_HEALTH_TIMEOUT_SECONDS="${THETA_HEALTH_TIMEOUT_SECONDS:-10}"
LOG="$REPO/live_runtime/local_sim_watchdog.log"
LOCK="$REPO/live_runtime/local_sim_watchdog.lock"

cd "$REPO"
export STEVE_REPO_ROOT="$REPO"

log() {
  mkdir -p "$(dirname "$LOG")"
  echo "$(date -u '+%FT%TZ') [local-sim-watchdog] $*" | tee -a "$LOG"
}

acquire_lock() {
  mkdir -p "$(dirname "$LOCK")"
  exec 9>"$LOCK"
  if ! flock -n 9; then
    log "another local sim watchdog owns $LOCK; skipping"
    exit 0
  fi
}

acquire_lock

case "$(TZ=America/New_York date +%u)" in
  6|7) exit 0 ;;
esac

NYSE_HOLIDAYS="2026-06-19 2026-07-03 2026-09-07 2026-11-26 2026-12-25"
case " $NYSE_HOLIDAYS " in
  *" $(TZ=America/New_York date +%F) "*) exit 0 ;;
esac

hhmm="$(TZ=America/New_York date +%H%M)"
if [[ "$hhmm" < "0915" || "$hhmm" > "1605" ]]; then
  exit 0
fi

theta_healthy() {
  "$BASILISP" run "$REPO/scripts/wait_thetadata_health.lpy" -- \
    --url "$THETA_HEALTH_URL" \
    --timeout-seconds "$THETA_HEALTH_TIMEOUT_SECONDS" \
    --poll-seconds "1" >/dev/null 2>&1
}

ensure_tunnel() {
  if theta_healthy; then
    return 0
  fi
  if pgrep -f 'ssh .*127\.0\.0\.1:25503:127\.0\.0\.1:25503' >/dev/null 2>&1; then
    pkill -f 'ssh .*127\.0\.0\.1:25503:127\.0\.0\.1:25503' 2>/dev/null || true
    sleep 1
  fi
  log "starting ThetaData SSH tunnel"
  ssh -f -N -L 127.0.0.1:25503:127.0.0.1:25503 \
    -o ExitOnForwardFailure=yes -o BatchMode=yes -o ConnectTimeout=10 \
    "$THETA_HOST" || return 1
  sleep 3
  theta_healthy
}

workspace_pythonpath() {
  ls -d components/*/src bases/*/src | paste -sd: - > .nrepl-pythonpath
  while IFS= read -r p; do
    printf '%s:' "$REPO/$p"
  done < <(tr ':' '\n' < .nrepl-pythonpath) | sed 's/:$//'
}

env_pid() {
  local key="$1" value="$2" pid
  for pid in $(pgrep -f 'launch_vol_term_sim\.lpy' 2>/dev/null || true); do
    if tr '\0' '\n' <"/proc/$pid/environ" 2>/dev/null | grep -qx "$key=$value"; then
      echo "$pid"
      return 0
    fi
  done
  return 1
}

v2_vol_running() {
  env_pid SIM_PROCESS_ID engine-sim-v2-vol >/dev/null 2>&1
}

base_volterm_running() {
  for pid in $(pgrep -f 'launch_vol_term_sim\.lpy' 2>/dev/null || true); do
    if tr '\0' '\n' <"/proc/$pid/environ" 2>/dev/null | grep -qx 'SIM_ENABLE_V2_VOL=0'; then
      return 0
    fi
  done
  return 1
}

local_fleet_running() {
  pgrep -f 'launch_local_sim_fleet\.lpy' >/dev/null 2>&1
}

start_base() {
  if [[ ! -x "$BASILISP" || ! -x "$REF_BASILISP" ]]; then
    log "missing Basilisp runner(s): BASILISP=$BASILISP REF_BASILISP=$REF_BASILISP"
    return 1
  fi
  log "starting base local sim session"
  nohup "$REPO/scripts/local_sim_session.sh" 9>&- \
    >> "$REPO/live_runtime/local_sim_session.watchdog.log" 2>&1 &
}

start_base_volterm() {
  if [[ ! -x "$REF_BASILISP" ]]; then
    log "missing REF Basilisp runner: $REF_BASILISP"
    return 1
  fi
  local pypath
  pypath="$(workspace_pythonpath)"
  log "starting base vol/term sim stack"
  nohup setsid env PYTHONPATH="$pypath" SIM_ENABLE_V2_VOL=0 \
    "$REF_BASILISP" run "$REPO/scripts/launch_vol_term_sim.lpy" \
    9>&- \
    >> "$REPO/live_runtime/sim_vol_term.watchdog.log" 2>&1 &
}

start_v2_vol() {
  if [[ ! -x "$REF_BASILISP" ]]; then
    log "missing REF Basilisp runner: $REF_BASILISP"
    return 1
  fi
  local pypath
  pypath="$(workspace_pythonpath)"
  log "starting V2 VOL sidecar"
  nohup setsid env PYTHONPATH="$pypath" \
    SIM_ENABLE_CORE=0 \
    SIM_ENABLE_VARIANTS=0 \
    SIM_ENABLE_SMA=0 \
    SIM_ENABLE_V2_TERM=0 \
    SIM_ENABLE_V2_TERM_SPXW=0 \
    SIM_ENABLE_V2_VOL=1 \
    SIM_ACCOUNT_ID=account/sim/v2-vol \
    SIM_PROCESS_ID=engine-sim-v2-vol \
    SIM_CP_ROOT=live_runtime/cp-sim-v2-vol \
    SIM_OUT_SUFFIX=-v2vol \
    "$REF_BASILISP" run "$REPO/scripts/launch_vol_term_sim.lpy" \
    9>&- \
    >> "$REPO/live_runtime/sim_v2_vol.watchdog.log" 2>&1 &
}

terminate_pid() {
  local pid="$1" label="$2" i
  if [ -z "$pid" ] || ! kill -0 "$pid" 2>/dev/null; then
    return 0
  fi
  log "stopping $label pid $pid"
  kill -TERM -- "-$pid" 2>/dev/null || kill -TERM "$pid" 2>/dev/null || true
  for i in $(seq 1 5); do
    if ! kill -0 "$pid" 2>/dev/null; then
      return 0
    fi
    sleep 1
  done
  log "forcing $label pid $pid"
  kill -KILL -- "-$pid" 2>/dev/null || kill -KILL "$pid" 2>/dev/null || true
}

stop_sim_processes() {
  local pid
  for pid in $(pgrep -f 'launch_local_sim_fleet\.lpy' 2>/dev/null || true); do
    terminate_pid "$pid" "local fleet"
  done
  for pid in $(pgrep -f 'launch_vol_term_sim\.lpy' 2>/dev/null || true); do
    terminate_pid "$pid" "vol/term"
  done
}

if ! ensure_tunnel; then
  log "ThetaData tunnel unhealthy; stopping sim processes"
  stop_sim_processes
  exit 2
fi

if ! local_fleet_running && ! base_volterm_running; then
  start_base
elif local_fleet_running && ! base_volterm_running; then
  start_base_volterm
elif ! local_fleet_running && base_volterm_running; then
  stop_sim_processes
  start_base
fi

if [[ "${SIM_WATCHDOG_ENABLE_V2_VOL:-1}" != "0" ]] && ! v2_vol_running; then
  start_v2_vol
fi
