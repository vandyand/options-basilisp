#!/usr/bin/env bash
# Daily trading orchestrator. Runs TWO fully-isolated sessions that share
# only the read-only ThetaData terminal:
#
#   1. SIX-BOT PAPER (primary): CHESTNUT/LYNX/MOOSE/PARROT/OAK/DOLPHIN on
#      their six Alpaca paper accounts (:broker/alpaca-paper). Real money
#      path (paper). Drives orchestrator exit.
#   2. VOL/TERM SIM (secondary, additive): condor-rv + calendar-slope +
#      HAWK_TERM_SPY_V2 on ONE local sim account (:broker/sim). ZERO
#      Alpaca trading — fills price at observed marks. Resilient: a sim
#      launch failure NEVER aborts the six bots.
#
# Both launchers own their own session clock (15:30 ET entry cutoff,
# 15:45 ET forced flatten) and run under the REF venv (torch/xgboost +
# the V2 term predictor). Alpaca creds come from REF/.env (six bots) /
# the chestnut data key (sim, market data only). The terminal is a
# shared single session handed back to Steve on stop.
#
# Broker target override: set BROKER_TARGET=sim to run the six accounts
# against the durable local sim broker only, or BROKER_TARGET=both to keep
# Alpaca paper canonical while mirroring intents into sim
# (<session>/sim-broker.db). Default is BROKER_TARGET=alpaca.
#
# Cron (09:20 ET gives the bridges ~10 min to load bundles + prime):
#   20 9 * * 1-5 /home/kingjames/contracting/upwork/steven-tran/stevetrading-basilisp/scripts/steve_six_session.sh >> /home/kingjames/contracting/upwork/steven-tran/stevetrading-basilisp/live_runtime/steve_six.cron.log 2>&1
set -uo pipefail

REPO="${STEVE_REPO_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
DEFAULT_REF="$HOME/contracting/upwork/steven-tran/SteveTrading/ref/Data-Preprocessor"
if [ -z "${STEVE_REF_ROOT:-}" ] && [ -d /opt/stevetrading/shared/Data-Preprocessor ]; then
  DEFAULT_REF="/opt/stevetrading/shared/Data-Preprocessor"
fi
REF="${STEVE_REF_ROOT:-$DEFAULT_REF}"
LIFECYCLE="${STEVE_THETADATA_LIFECYCLE:-$REF/thetadata_lifecycle.sh}"
BASILISP="${BASILISP_BIN:-$REF/.venv/bin/basilisp}"
cd "$REPO"
export STEVE_REPO_ROOT="$REPO"

# Keep the launcher environment aligned with the workspace. A stale
# .nrepl-pythonpath can make market-open startup fail after adding a component.
ls -d components/*/src bases/*/src | paste -sd: - > .nrepl-pythonpath
PYPATH="$(cat .nrepl-pythonpath)"

log() { echo "$(date -u '+%FT%TZ') [orchestrator] $*"; }
et_now() {
  if [ -n "${STEVE_SIX_NOW_ET:-}" ]; then
    TZ=America/New_York date -d "$STEVE_SIX_NOW_ET" "$@"
  else
    TZ=America/New_York date "$@"
  fi
}

ET_TODAY="$(et_now +%F)"
ET_HHMM="$(et_now +%H%M)"

# weekend guard (cron 1-5 already filters; belt for manual runs)
case "$(et_now +%u)" in 6|7) log "weekend — skipping"; exit 0 ;; esac

# Recovery guard for a persistent timer after host reboots. A reboot after the
# 09:20 ET timer should recover the live capture, but an after-hours boot must
# not grab the shared ThetaData terminal or launch a dead session.
if [ "${STEVE_SIX_SKIP_SESSION_WINDOW:-0}" != "1" ]; then
  if [ "$ET_HHMM" -lt 900 ] || [ "$ET_HHMM" -gt 1555 ]; then
    log "outside recoverable market session window ($ET_TODAY $ET_HHMM ET) — skipping"
    exit 0
  fi
fi

# NYSE full-day holiday guard. The market is closed these dates, so don't
# grab the shared ThetaData terminal or launch bots into a dead session.
# (Remaining 2026 NYSE closures; half-days Nov 27 / Dec 24 stay open.)
NYSE_HOLIDAYS="2026-06-19 2026-07-03 2026-09-07 2026-11-26 2026-12-25"
case " $NYSE_HOLIDAYS " in
  *" $ET_TODAY "*) log "NYSE holiday ($ET_TODAY) — skipping"; exit 0 ;;
esac

log "running live import preflight"
if ! PYTHONPATH="$PYPATH" "$BASILISP" run "$REPO/scripts/preflight_live_imports.lpy"; then
  log "live import preflight failed — aborting before terminal start"
  exit 1
fi

CAPTURE_DIR="${CAPTURE_DIR:-$REPO/live_runtime/feature-capture}"
ANALYSIS_DIR="${ANALYSIS_DIR:-$REPO/live_runtime/analysis}"
mkdir -p "$CAPTURE_DIR" "$ANALYSIS_DIR"
log "preparing capture-v2 session file"
if ! PYTHONPATH="$PYPATH" "$BASILISP" run "$REPO/scripts/prepare_capture_v2_session.lpy" -- \
    --capture-dir "$CAPTURE_DIR" \
    --target-date "$ET_TODAY" \
    --out-json "$ANALYSIS_DIR/prepare_capture_v2_session_${ET_TODAY//-/}.json"; then
  log "capture-v2 session preparation failed — aborting before terminal start"
  exit 1
fi

SIM_PID=""
cleanup() {
  # stop the sim session first if it is somehow still alive (it ends at
  # 15:45 ET on its own; this is a belt for early orchestrator exit)
  if [ -n "$SIM_PID" ] && kill -0 "$SIM_PID" 2>/dev/null; then
    log "stopping vol/term sim (pid $SIM_PID)"
    kill "$SIM_PID" 2>/dev/null || true
  fi
  log "stopping theta terminal (handing session back)"
  "$LIFECYCLE" stop || true
}
# Arm cleanup BEFORE the terminal start so a failed/partial start can never
# strand an orphan (the 06-18 failure mode: abort happened before the trap was
# set, leaving a thrashed terminal running unmanaged for 2+ days).
trap cleanup EXIT

# Terminal start with retry. The 06-17/06-18 outage was a transient morning
# DNS blip (could not resolve nexus-api.thetadata.us) that had recovered within
# the hour — but the old `start || exit 1` killed the whole trading day on the
# first failure. Retry across ~45 min so a recoverable network hiccup at the
# open does not cost us the session. The lifecycle itself now waits for DNS and
# starts patiently, so each attempt is already robust; this is the outer belt.
start_terminal() {
  local try
  for try in 1 2 3 4 5; do
    if "$LIFECYCLE" start; then return 0; fi
    log "terminal start attempt $try/5 failed (transient DNS/network?) — retry in 10 min"
    sleep 600
  done
  return 1
}
log "starting theta terminal (with retry)"
if ! start_terminal; then
  log "terminal could not start after 5 attempts over ~45 min — aborting day"
  exit 1
fi

# secondary: vol/term sim trio, backgrounded, resilient (own log)
log "launching vol/term sim trio (REF venv, sim broker)"
PYTHONPATH="$PYPATH" "$BASILISP" run "$REPO/scripts/launch_vol_term_sim.lpy" \
  >> "$REPO/live_runtime/sim_vol_term.cron.log" 2>&1 &
SIM_PID=$!
log "vol/term sim pid $SIM_PID"

# primary: six-bot paper session (foreground — its exit drives the run)
log "launching six-bot session (REF venv)"
PYTHONPATH="$PYPATH" "$BASILISP" run "$REPO/scripts/launch_steve_six.lpy"
rc=$?
log "six-bot session exited rc=$rc"
exit $rc
