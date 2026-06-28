#!/usr/bin/env bash
# steve_watchdog.sh — auth-free self-healing watchdog for the six-bot session.
#
# WHY (2026-06-20, hardened 2026-06-22): our monitoring used to lean on a live
# Claude session that died when the Anthropic login dropped; trading days were
# then lost silently. This watchdog is the auth-free safety net: PURE bash, no
# Claude, no Anthropic, no permission classifier — a system cron that just runs
# and FIXES things, with no human in the loop.
#
# 2026-06-22 incident that drove the upgrade: the ThetaData terminal lost its
# session mid-day; the engine's decision/execution loop WEDGED (no signals, no
# orders, and critically the 15:45 flatten never fired — 0DTE positions decayed
# to full loss) while equity-bar ingestion kept running. The process stayed
# ALIVE, so the old `pgrep` liveness check passed and nothing recovered. The fix
# below detects a STALL (data flowing but the decision side frozen), not just a
# dead process, and recovers by tearing down + relaunching the whole session.
#
# Checks each run (inside the session window):
#   1. launcher process alive?              no  -> recover (relaunch)
#   2. decision pipeline progressing?        no  -> recover (kill stalled + relaunch)
#   3. theta terminal serving data?          no  -> reclaim terminal (pre-empt a stall)
# Recovery is bounded (lock + N/day cap) so a persistent fault (e.g. Steve
# holding the shared ThetaData account) escalates to an alert instead of looping
# forever. Every action is pushed to ntfy so you find out without watching.
#
# Cron (every ~5 min, 09:34-15:51 ET, weekdays — tighter than before so a stall
# is caught fast and a late stall can still be rescued before the 15:45 flatten):
#   */5 9-15 * * 1-5 .../scripts/steve_watchdog.sh >> .../live_runtime/watchdog.cron.log 2>&1
#
# Optional phone push: export STEVE_NTFY_TOPIC=<topic> in the cron environment.
set -uo pipefail

REPO="${STEVE_REPO_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
DEFAULT_REF="$HOME/contracting/upwork/steven-tran/SteveTrading/ref/Data-Preprocessor"
if [ -z "${STEVE_REF_ROOT:-}" ] && [ -d /opt/stevetrading/shared/Data-Preprocessor ]; then
  DEFAULT_REF="/opt/stevetrading/shared/Data-Preprocessor"
fi
REF="${STEVE_REF_ROOT:-$DEFAULT_REF}"
LIFECYCLE="${STEVE_THETADATA_LIFECYCLE:-$REF/thetadata_lifecycle.sh}"
ORCH="$REPO/scripts/steve_six_session.sh"
ORCH_LOG="$REPO/live_runtime/steve_six.cron.log"
PRECHECK_LOG="$REPO/live_runtime/watchdog.preflight.log"
ALERTS="$REPO/live_runtime/watchdog.alerts.log"
LOCK="$REPO/live_runtime/watchdog.relaunch.lock"
HEAL_COUNT="$REPO/live_runtime/watchdog.heals.$(TZ=America/New_York date +%F)"
MAX_HEALS_PER_DAY=4
STALL_SECONDS=900          # decisions silent > 15 min while bars flow = stalled
BAR_FRESH_SECONDS=420      # bars within 7 min = the engine is alive/ingesting
NTFY_TOPIC="${STEVE_NTFY_TOPIC:-}"
SYSTEMD_SIX_UNIT="${STEVE_SIX_SYSTEMD_UNIT:-stevetrading-six.service}"
POST_RELAUNCH_VERIFY_SECONDS="${STEVE_POST_RELAUNCH_VERIFY_SECONDS:-20}"

NYSE_HOLIDAYS="2026-06-19 2026-07-03 2026-09-07 2026-11-26 2026-12-25"

log()  { echo "$(TZ=America/New_York date '+%F %T %Z') [watchdog] $*"; }

alert() {
    local msg="$1"
    log "ALERT: $msg"
    echo "$(TZ=America/New_York date '+%F %T %Z')  $msg" >> "$ALERTS"
    if [[ -n "$NTFY_TOPIC" ]]; then
        curl -s -m 10 -H "Title: SteveTrading watchdog" -d "$msg" \
            "https://ntfy.sh/$NTFY_TOPIC" >/dev/null 2>&1 || true
    fi
}

is_session_window() {
    # trading day AND 09:34-15:51 ET. Window now extends past the 15:45 flatten
    # so a stall arising right before close can still be rescued (a fresh launch
    # force-flattens immediately once its clock sees now > 15:45).
    local dow today hm
    dow=$(TZ=America/New_York date '+%u'); today=$(TZ=America/New_York date '+%F')
    hm=$(TZ=America/New_York date '+%H%M')
    [[ "$dow" -ge 6 ]] && return 1
    [[ " $NYSE_HOLIDAYS " == *" $today "* ]] && return 1
    [[ "$hm" > "0933" && "$hm" < "1552" ]]
}

launcher_alive() { pgrep -f "launch_steve_six\.lpy" >/dev/null 2>&1; }

terminal_healthy() {
    [[ "$("$LIFECYCLE" status 2>/dev/null | awk -F': ' '/^health/{print $2}')" == "ok" ]]
}

sim_broker_status() {
    local db updated bytes
    db=$(ls -t "$REPO"/live_runtime/steve-session-*/sim-broker.db 2>/dev/null | head -1)
    [[ -f "$db" ]] || { echo "sim:no-store"; return 0; }
    updated=$(sqlite3 "$db" "select updated_at from sim_journal where id='main';" 2>/dev/null || true)
    bytes=$(sqlite3 "$db" "select length(record) from sim_journal where id='main';" 2>/dev/null || true)
    if [[ -n "$updated" ]]; then
        echo "sim:journal updated=$updated bytes=${bytes:-0}"
    else
        echo "sim:journal empty"
    fi
}

# Decision-pipeline liveness via the append-only ledger: a healthy RTH session
# writes a decision-side fact (signal / risk / order-intent) every cycle, even
# when flat. If equity bars are FRESH (engine ingesting) but the newest decision
# fact is older than STALL_SECONDS, the decision/execution loop is wedged — the
# 06-22 failure. Returns 0 (stalled) / 1 (fine or can't tell — fail safe).
decisions_stalled() {
    local db last_bar last_dec now bar_epoch dec_epoch
    db=$(ls -t "$REPO"/live_runtime/steve-session-*/facts.db 2>/dev/null | head -1)
    [[ -f "$db" ]] || return 1
    last_bar=$(sqlite3 "$db" \
      "select max(occurred_at) from facts where fact_type=':fact/market-bar-observed';" 2>/dev/null)
    last_dec=$(sqlite3 "$db" \
      "select max(occurred_at) from facts where fact_type in \
       (':fact/signal-decision-produced',':fact/risk-decision-recorded',':fact/order-intent-created');" 2>/dev/null)
    [[ -n "$last_bar" ]] || return 1
    now=$(date -u +%s)
    bar_epoch=$(date -u -d "$last_bar" +%s 2>/dev/null) || return 1
    dec_epoch=$(date -u -d "${last_dec:-1970-01-01T00:00:00Z}" +%s 2>/dev/null || echo 0)
    # stalled iff bars are fresh AND decisions are stale
    (( now - bar_epoch < BAR_FRESH_SECONDS )) && (( now - dec_epoch > STALL_SECONDS ))
}

heals_today() { [[ -f "$HEAL_COUNT" ]] && cat "$HEAL_COUNT" || echo 0; }

preflight_ok() {
    (
        cd "$REPO" || exit 1
        ls -d components/*/src bases/*/src | paste -sd: - > .nrepl-pythonpath
        PYTHONPATH="$(cat .nrepl-pythonpath)" \
          "${BASILISP_BIN:-$REF/.venv/bin/basilisp}" run "$REPO/scripts/preflight_live_imports.lpy"
    ) > "$PRECHECK_LOG" 2>&1
}

start_orchestrator() {
    if command -v systemctl >/dev/null 2>&1 \
       && systemctl list-unit-files "$SYSTEMD_SIX_UNIT" >/dev/null 2>&1; then
        sudo -n systemctl restart "$SYSTEMD_SIX_UNIT"
        return $?
    fi

    setsid nohup "$ORCH" >> "$ORCH_LOG" 2>&1 < /dev/null &
    log "relaunched orchestrator fallback (pid $!) — engine reconciles with the broker on start"
}

reclaim_terminal() {
    # our systemctl only controls OUR terminal process, never Steve's PC — safe.
    log "reclaiming theta terminal (stop+start)"
    "$LIFECYCLE" stop  >/dev/null 2>&1 || true
    "$LIFECYCLE" start >/dev/null 2>&1 || true
}

recover() {
    # Full session recovery: tear down a down/stalled session and relaunch the
    # orchestrator fresh (it reclaims the terminal + the engine snapshot-replays
    # and broker-reconciles on start). Bounded by lock + daily cap so a
    # persistent fault escalates to a human instead of looping.
    local reason="$1"
    if ! ( set -o noclobber; echo $$ > "$LOCK" ) 2>/dev/null; then
        log "recover skipped — another watchdog holds the lock"; return 0
    fi
    trap 'rm -f "$LOCK"' RETURN
    if ! preflight_ok; then
        alert "session fault ($reason) but live import preflight FAILED — not relaunching. See $PRECHECK_LOG"
        return 0
    fi
    local n; n=$(heals_today)
    if (( n >= MAX_HEALS_PER_DAY )); then
        alert "session fault ($reason) but heal cap reached ($n/$MAX_HEALS_PER_DAY) — NOT relaunching; NEEDS A HUMAN. Check orchestrator log: $ORCH_LOG"
        return 0
    fi
    echo $((n + 1)) > "$HEAL_COUNT"
    alert "RECOVERING ($reason) — heal $((n+1))/$MAX_HEALS_PER_DAY: tearing down + relaunching"
    # tear down any running/stalled launcher + sim; the orchestrator's own
    # cleanup then stops the terminal as its foreground launcher exits.
    pkill -f "launch_steve_six\.lpy"    2>/dev/null || true
    pkill -f "launch_vol_term_sim\.lpy" 2>/dev/null || true
    sleep 8
    if launcher_alive; then
        log "launcher still alive after TERM — SIGKILL"
        pkill -9 -f "launch_steve_six\.lpy" 2>/dev/null || true
        pkill -9 -f "launch_vol_term_sim\.lpy" 2>/dev/null || true
        sleep 3
    fi
    # Relaunch fresh via the long-running systemd unit when available. A
    # watchdog Type=oneshot must not own the background child process directly.
    if start_orchestrator; then
        log "requested orchestrator relaunch via ${SYSTEMD_SIX_UNIT}"
    else
        alert "session fault ($reason) but relaunch command FAILED. Check sudo/systemd and $ORCH_LOG"
        return 0
    fi

    sleep "$POST_RELAUNCH_VERIFY_SECONDS"
    if launcher_alive; then
        log "orchestrator relaunch verified alive after ${POST_RELAUNCH_VERIFY_SECONDS}s"
    else
        alert "session fault ($reason): relaunch did not stay alive after ${POST_RELAUNCH_VERIFY_SECONDS}s. Last orchestrator lines: $(tail -20 "$ORCH_LOG" 2>/dev/null | tr '\n' ' ' | tail -c 1000)"
    fi
}

main() {
    if ! is_session_window; then
        log "outside session window — nothing to check"; exit 0
    fi

    if ! launcher_alive; then
        recover "launcher process DOWN"
    elif decisions_stalled; then
        recover "decision pipeline STALLED (equity bars flowing but no signal/order facts > ${STALL_SECONDS}s)"
    elif ! terminal_healthy; then
        # bots alive + still deciding, but the terminal is flaky/invalid-session.
        # reclaim it now to pre-empt the stall; alert if it does not recover.
        reclaim_terminal
        if terminal_healthy; then
            alert "theta terminal was down — reclaimed, serving data again"
        else
            alert "theta terminal DOWN and reclaim failed ($("$LIFECYCLE" status 2>/dev/null | awk -F': ' '/^network/{print $2}')) — Steve may hold the account"
        fi
    else
        log "OK — launcher alive, decisions progressing, terminal serving data, $(sim_broker_status)"
    fi
}

main "$@"
