#!/usr/bin/env bash
# Daily six-bot paper session orchestrator (CHESTNUT/LYNX/MOOSE/PARROT/
# OAK/DOLPHIN on their six Alpaca paper accounts).
#
# Starts the ThetaData terminal (shared single-session account — the
# lifecycle script hands it back to Steve on stop), runs the six-bot
# launcher under the REF venv (torch/xgboost), and stops the terminal
# afterward NO MATTER how the session ends.
#
# The launcher owns the session clock: 15:30 ET entry cutoff, 15:45 ET
# forced flatten, sources until 15:55 ET. Alpaca creds come from
# REF/.env (read by the launcher itself).
#
# Cron (09:20 ET gives the bridge ~10 min to load bundles + prime):
#   20 9 * * 1-5 /home/kingjames/contracting/upwork/steven-tran/stevetrading-basilisp/scripts/steve_six_session.sh >> /home/kingjames/contracting/upwork/steven-tran/stevetrading-basilisp/live_runtime/steve_six.cron.log 2>&1
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
REF="$HOME/contracting/upwork/steven-tran/SteveTrading/ref/Data-Preprocessor"
LIFECYCLE="$REF/thetadata_lifecycle.sh"
cd "$REPO"

log() { echo "$(date -u '+%FT%TZ') [steve-six] $*"; }

# weekend guard (cron 1-5 already filters; belt for manual runs)
case "$(date +%u)" in 6|7) log "weekend — skipping"; exit 0 ;; esac

log "starting theta terminal"
"$LIFECYCLE" start || { log "terminal start failed — aborting"; exit 1; }

cleanup() {
  log "stopping theta terminal (handing session back)"
  "$LIFECYCLE" stop || true
}
trap cleanup EXIT

log "launching six-bot session (REF venv)"
PYTHONPATH="$(cat "$REPO/.nrepl-pythonpath")" \
  "$REF/.venv/bin/basilisp" run "$REPO/scripts/launch_steve_six.lpy"
rc=$?
log "session exited rc=$rc"
exit $rc
