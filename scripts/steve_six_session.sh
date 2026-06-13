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
# Cron (09:20 ET gives the bridges ~10 min to load bundles + prime):
#   20 9 * * 1-5 /home/kingjames/contracting/upwork/steven-tran/stevetrading-basilisp/scripts/steve_six_session.sh >> /home/kingjames/contracting/upwork/steven-tran/stevetrading-basilisp/live_runtime/steve_six.cron.log 2>&1
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
REF="$HOME/contracting/upwork/steven-tran/SteveTrading/ref/Data-Preprocessor"
LIFECYCLE="$REF/thetadata_lifecycle.sh"
PYPATH="$(cat "$REPO/.nrepl-pythonpath")"
BASILISP="$REF/.venv/bin/basilisp"
cd "$REPO"

log() { echo "$(date -u '+%FT%TZ') [orchestrator] $*"; }

# weekend guard (cron 1-5 already filters; belt for manual runs)
case "$(date +%u)" in 6|7) log "weekend — skipping"; exit 0 ;; esac

log "starting theta terminal"
"$LIFECYCLE" start || { log "terminal start failed — aborting"; exit 1; }

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
trap cleanup EXIT

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
