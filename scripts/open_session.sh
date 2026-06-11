#!/usr/bin/env bash
# Market-open paper session orchestrator (venturevd account).
#
# Starts the ThetaData terminal (shared single-session account — the
# lifecycle script hands it back to Steve on stop), waits for health,
# runs the open launcher (strikes resolved from live price at launch),
# and stops the terminal afterward NO MATTER how the session ends.
#
# Run manually at/after 09:28 ET, or via cron:
#   28 9 * * 1-5 /home/kingjames/contracting/upwork/steven-tran/stevetrading-basilisp/scripts/open_session.sh >> /home/kingjames/contracting/upwork/steven-tran/stevetrading-basilisp/live_runtime/open_session.cron.log 2>&1
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
LIFECYCLE="$HOME/contracting/upwork/steven-tran/SteveTrading/ref/Data-Preprocessor/thetadata_lifecycle.sh"
cd "$REPO"

# ~/.bashrc's interactivity guard (line 6: `case $- in *i*) ;; *) return`)
# returns before the export lines under cron — caused the 2026-06-11
# 09:28 startup failure. Read the creds directly instead of sourcing.
eval "$(grep '^export ALPACA_VENTUREVD_' "$HOME/.bashrc")"
if [ -z "${ALPACA_VENTUREVD_API_KEY:-}" ] || [ -z "${ALPACA_VENTUREVD_API_SECRET:-}" ]; then
  echo "$(date -u '+%FT%TZ') [open-session] FATAL: could not load ALPACA_VENTUREVD creds from ~/.bashrc" >&2
  exit 1
fi

log() { echo "$(date -u '+%FT%TZ') [open-session] $*"; }

log "starting theta terminal"
"$LIFECYCLE" start || { log "terminal start failed — aborting"; exit 1; }

cleanup() {
  log "stopping theta terminal (handing session back)"
  "$LIFECYCLE" stop || true
}
trap cleanup EXIT

log "launching session"
PYTHONPATH="$(cat "$REPO/.nrepl-pythonpath")" \
  "$REPO/.venv/bin/basilisp" run "$REPO/scripts/launch_open_venturevd.lpy"
rc=$?
log "session exited rc=$rc"
exit $rc
