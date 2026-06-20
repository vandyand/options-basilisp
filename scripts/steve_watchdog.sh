#!/usr/bin/env bash
# steve_watchdog.sh — auth-free liveness watchdog for the six-bot paper session.
#
# WHY THIS EXISTS (2026-06-20): the week of 06-15 exposed that our monitoring
# leaned on a live Claude session, which died when the Anthropic login dropped
# (a machine sleep/resume). And the 06-17/06-18 trading days were lost because a
# transient morning DNS blip made the orchestrator abort with no retry, and
# nothing noticed for days. The trading itself runs from system cron (good), but
# nothing was watching it that did not itself depend on an auth token.
#
# This watchdog is that missing piece: PURE bash, no Claude, no Anthropic, no
# network auth. Run it from system cron every ~15 min during market hours. It:
#   1. checks it is a trading day + inside the active session window,
#   2. checks the six-bot launcher process is alive and the theta terminal is
#      serving data,
#   3. SELF-HEALS — if the launcher is down inside the window, it relaunches the
#      orchestrator (guarded against double-launch: never relaunch while a
#      launcher already runs; lock file; capped attempts/day),
#   4. ALERTS — every problem is appended to the alerts log and (if configured)
#      pushed to your phone via ntfy.sh, so you find out without a live session.
#
# Cron (every 15 min, 09:35-15:35 ET, weekdays):
#   */15 9-15 * * 1-5 /home/kingjames/contracting/upwork/steven-tran/stevetrading-basilisp/scripts/steve_watchdog.sh >> /home/kingjames/contracting/upwork/steven-tran/stevetrading-basilisp/live_runtime/watchdog.cron.log 2>&1
#
# Optional phone push: export STEVE_NTFY_TOPIC=some-unguessable-topic in the
# cron environment (or ~/.bashrc) and subscribe to ntfy.sh/<topic> on your phone.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
REF="$HOME/contracting/upwork/steven-tran/SteveTrading/ref/Data-Preprocessor"
LIFECYCLE="$REF/thetadata_lifecycle.sh"
ORCH="$REPO/scripts/steve_six_session.sh"
ORCH_LOG="$REPO/live_runtime/steve_six.cron.log"
ALERTS="$REPO/live_runtime/watchdog.alerts.log"
LOCK="$REPO/live_runtime/watchdog.relaunch.lock"
HEAL_COUNT="$REPO/live_runtime/watchdog.heals.$(TZ=America/New_York date +%F)"
MAX_HEALS_PER_DAY=3
NTFY_TOPIC="${STEVE_NTFY_TOPIC:-}"

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
    # trading day (weekday, not a holiday) AND 09:35-15:35 ET — inside the live
    # session but clear of the 09:20 launch ramp and the 15:45 close-out.
    local dow today hm
    dow=$(TZ=America/New_York date '+%u'); today=$(TZ=America/New_York date '+%F')
    hm=$(TZ=America/New_York date '+%H%M')
    [[ "$dow" -ge 6 ]] && return 1
    [[ " $NYSE_HOLIDAYS " == *" $today "* ]] && return 1
    [[ "$hm" > "0934" && "$hm" < "1536" ]]
}

launcher_alive() { pgrep -f "launch_steve_six\.lpy" >/dev/null 2>&1; }

terminal_healthy() {
    # reuse the lifecycle's own health classification (auth-free, local curl)
    [[ "$("$LIFECYCLE" status 2>/dev/null | awk -F': ' '/^health/{print $2}')" == "ok" ]]
}

heals_today() { [[ -f "$HEAL_COUNT" ]] && cat "$HEAL_COUNT" || echo 0; }

relaunch() {
    # double-launch guard: NEVER relaunch while a launcher already runs (two
    # sessions would double-trade the six real accounts). Lock + daily cap.
    if launcher_alive; then
        log "relaunch skipped — a launcher is already running"; return 0
    fi
    if ! ( set -o noclobber; echo $$ > "$LOCK" ) 2>/dev/null; then
        log "relaunch skipped — another watchdog holds the lock"; return 0
    fi
    trap 'rm -f "$LOCK"' RETURN
    local n; n=$(heals_today)
    if (( n >= MAX_HEALS_PER_DAY )); then
        alert "launcher DOWN but heal cap reached ($n/$MAX_HEALS_PER_DAY today) — NOT relaunching; needs a human"
        return 0
    fi
    echo $((n + 1)) > "$HEAL_COUNT"
    alert "launcher DOWN in session window — self-healing: relaunching orchestrator (heal $((n+1))/$MAX_HEALS_PER_DAY)"
    setsid nohup "$ORCH" >> "$ORCH_LOG" 2>&1 < /dev/null &
    log "relaunched orchestrator (pid $!) — engine will snapshot-replay + broker-reconcile on start"
}

main() {
    if ! is_session_window; then
        log "outside session window — nothing to check"; exit 0
    fi

    local problems=0
    if ! terminal_healthy; then
        problems=1
        alert "theta terminal not serving data ($("$LIFECYCLE" status 2>/dev/null | awk -F': ' '/^network/{print $2}'))"
    fi
    if ! launcher_alive; then
        problems=1
        relaunch              # the important self-heal: bots are not running
    fi

    if (( problems == 0 )); then
        log "OK — launcher alive, terminal serving data"
    fi
}

main "$@"
