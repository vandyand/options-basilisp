#!/usr/bin/env bash
# Daily local sim orchestrator. This intentionally does NOT launch Alpaca broker
# strategies and does NOT start/stop ThetaData. It assumes local ThetaData access
# comes through the Hetzner SSH tunnel on 127.0.0.1:25503.

set -uo pipefail

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  cat <<'EOF'
Usage: scripts/local_sim_session.sh

Launches local sim-only strategies:
  - scripts/launch_local_sim_fleet.lpy
  - scripts/launch_vol_term_sim.lpy after the ThetaData SSH tunnel is healthy

Does not launch Alpaca broker strategies and does not start/stop ThetaData.
EOF
  exit 0
fi

REPO="${STEVE_REPO_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
DEFAULT_REF="$HOME/contracting/upwork/steven-tran/SteveTrading/ref/Data-Preprocessor"
REF="${STEVE_REF_ROOT:-$DEFAULT_REF}"
BASILISP="${BASILISP_BIN:-$REPO/.venv/bin/basilisp}"
REF_BASILISP="${REF_BASILISP_BIN:-$REF/.venv/bin/basilisp}"
THETA_HEALTH_URL="${THETA_HEALTH_URL:-http://127.0.0.1:25503/v3/option/list/expirations?symbol=SPY}"
THETA_WAIT_TRIES="${THETA_WAIT_TRIES:-45}"
THETA_WAIT_SECONDS="${THETA_WAIT_SECONDS:-60}"
THETA_HEALTH_TIMEOUT_SECONDS="${THETA_HEALTH_TIMEOUT_SECONDS:-15}"
LOCK="$REPO/live_runtime/local_sim_session.lock"

cd "$REPO"
export STEVE_REPO_ROOT="$REPO"

log() { echo "$(date -u '+%FT%TZ') [local-sim] $*"; }

acquire_lock() {
  mkdir -p "$(dirname "$LOCK")"
  exec 8>"$LOCK"
  if ! flock -n 8; then
    log "another local sim session owns $LOCK; skipping"
    exit 0
  fi
}

acquire_lock

case "$(TZ=America/New_York date +%u)" in
  6|7) log "weekend - skipping"; exit 0 ;;
esac

NYSE_HOLIDAYS="2026-06-19 2026-07-03 2026-09-07 2026-11-26 2026-12-25"
case " $NYSE_HOLIDAYS " in
  *" $(TZ=America/New_York date +%F) "*) log "NYSE holiday - skipping"; exit 0 ;;
esac

if [ ! -x "$BASILISP" ]; then
  log "FATAL: Basilisp runner not executable: $BASILISP"
  exit 1
fi
if [ ! -x "$REF_BASILISP" ]; then
  log "FATAL: REF Basilisp runner not executable: $REF_BASILISP"
  exit 1
fi
if [ ! -f "$REF/.env" ]; then
  log "FATAL: REF .env missing: $REF/.env"
  exit 1
fi

ls -d components/*/src bases/*/src | paste -sd: - > .nrepl-pythonpath
PYPATH="$(while IFS= read -r p; do printf '%s:%s\n' "$REPO/$p" ""; done < <(tr ':' '\n' < .nrepl-pythonpath) | paste -sd '' - | sed 's/:$//')"

log "running import preflight"
if ! PYTHONPATH="$PYPATH" "$BASILISP" run "$REPO/scripts/preflight_live_imports.lpy"; then
  log "FATAL: import preflight failed"
  exit 1
fi

LOCAL_FLEET_PID=""
VOL_TERM_PID=""

terminate_child() {
  local pid="$1" label="$2" i
  if [ -z "$pid" ] || ! kill -0 "$pid" 2>/dev/null; then
    return 0
  fi
  log "stopping $label pid $pid"
  kill -TERM -- "-$pid" 2>/dev/null || kill -TERM "$pid" 2>/dev/null || true
  for i in $(seq 1 10); do
    if ! kill -0 "$pid" 2>/dev/null; then
      wait "$pid" 2>/dev/null || true
      return 0
    fi
    sleep 1
  done
  log "forcing $label pid $pid"
  kill -KILL -- "-$pid" 2>/dev/null || kill -KILL "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
}

cleanup() {
  trap - EXIT INT TERM
  terminate_child "$LOCAL_FLEET_PID" "local fleet"
  terminate_child "$VOL_TERM_PID" "vol/term"
}

signal_exit() {
  cleanup
  exit 130
}

trap cleanup EXIT
trap signal_exit INT TERM

log "launching local equity sim fleet"
PYTHONPATH="$PYPATH" setsid "$BASILISP" run "$REPO/scripts/launch_local_sim_fleet.lpy" \
  >> "$REPO/live_runtime/local_sim_fleet.cron.log" 2>&1 &
LOCAL_FLEET_PID=$!
log "local fleet pid $LOCAL_FLEET_PID"

theta_healthy() {
  "$BASILISP" run "$REPO/scripts/wait_thetadata_health.lpy" -- \
    --url "$THETA_HEALTH_URL" \
    --timeout-seconds "$THETA_HEALTH_TIMEOUT_SECONDS" \
    --poll-seconds "1" >/dev/null 2>&1
}

log "waiting for ThetaData tunnel health at $THETA_HEALTH_URL"
for i in $(seq 1 "$THETA_WAIT_TRIES"); do
  if theta_healthy; then
    log "ThetaData tunnel healthy"
    break
  fi
  if [ "$i" = "$THETA_WAIT_TRIES" ]; then
    log "FATAL: ThetaData tunnel did not become healthy after $THETA_WAIT_TRIES tries"
    exit 2
  fi
  log "ThetaData tunnel not healthy yet ($i/$THETA_WAIT_TRIES); retrying in ${THETA_WAIT_SECONDS}s"
  sleep "$THETA_WAIT_SECONDS"
done

log "launching vol/term sim stack"
PYTHONPATH="$PYPATH" SIM_ENABLE_V2_VOL="${SIM_ENABLE_V2_VOL:-0}" \
  setsid "$REF_BASILISP" run "$REPO/scripts/launch_vol_term_sim.lpy" \
  >> "$REPO/live_runtime/sim_vol_term.cron.log" 2>&1 &
VOL_TERM_PID=$!
log "vol/term pid $VOL_TERM_PID"

rc=0
wait "$LOCAL_FLEET_PID" || rc=$?
wait "$VOL_TERM_PID" || rc=$?
log "local sim session exited rc=$rc"
exit "$rc"
