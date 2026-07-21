#!/usr/bin/env bash
# ThetaData terminal lifecycle.
#
# The ThetaData account allows ONE terminal at a time. Steve runs his on his PC
# off-hours (data downloads); we need ours up only during market hours. This
# script starts the terminal before the open and stops it after the close so
# the single account session is handed back to Steve cleanly.
#
# The terminal runs as the systemd service `theta-terminal.service`
# (Restart=always). This script CONTROLS THE SERVICE rather than killing the
# process — a bare `kill` is undone by systemd in 10s, and systemd owns the
# whole cgroup so there are no orphan/duplicate terminals (the failure mode we
# hit on 2026-05-21). `systemctl stop` is an explicit stop and is NOT overridden
# by Restart=always, so a stop sticks until the next `start`.
#
# 2026-06-20 hardening (the 06-17/06-18 two-day outage):
#   ROOT CAUSE was DNS — the terminal could not resolve nexus-api.thetadata.us
#   to reach the ThetaData auth server ("Temporary failure in name resolution"),
#   almost certainly a WSL2 sleep/resume network blip. It was NOT Steve and NOT
#   an orphan. Two things made it worse: (1) the old start() did `systemctl
#   restart` every 25s on failure, which thrashed a terminal that just needed
#   ~60-90s to connect — and stranded an orphan when systemd's cgroup kill
#   failed on WSL ("Failed to kill control group"); (2) the health-fail message
#   blamed Steve by default, misdirecting diagnosis. This version:
#     - net_ready(): a DNS/reachability PRECHECK before declaring failure, with
#       a bounded wait for the network to recover (sleep/resume blips).
#     - patient single-start: poll health over ~2 min WITHOUT restart-thrash;
#       at most ONE restart mid-window for a genuinely wedged start.
#     - honest classification: dns-down / invalid-session (Steve) / warming —
#       log the real reason instead of always blaming Steve.
#     - reap_orphans(): belt for the WSL cgroup-kill quirk so stop/restart
#       never strands a terminal.
#
# ONE-TIME SETUP (needs root once — cron runs as an unprivileged user):
#   echo 'kingjames ALL=(root) NOPASSWD: /bin/systemctl start theta-terminal.service, /bin/systemctl stop theta-terminal.service, /bin/systemctl restart theta-terminal.service, /bin/systemctl restart systemd-resolved' \
#     | sudo tee /etc/sudoers.d/theta-terminal-lifecycle >/dev/null \
#     && sudo chmod 440 /etc/sudoers.d/theta-terminal-lifecycle && sudo visudo -c
#   sudo systemctl disable theta-terminal.service   # cron becomes the sole controller; no boot-time grab of Steve's session
#
# Usage: thetadata_lifecycle.sh {start|stop|status|net}
#
# VPS CUTOVER NOTE (2026-06-25):
#   Hetzner now owns the live ThetaData terminal while strategies are running.
#   Local development should normally read ThetaData through an SSH tunnel:
#     ssh -N -L 127.0.0.1:25503:127.0.0.1:25503 bot@167.233.141.61
#   To prevent accidentally stealing the single ThetaData session from the
#   VPS, local `start` is refused unless STEVE_ALLOW_LOCAL_THETADATA=1.

set -uo pipefail

SYSTEMCTL=/bin/systemctl
SERVICE=theta-terminal.service
AUTH_HOST="nexus-api.thetadata.us"          # ThetaData auth/version server (DNS canary)
HEALTH_URL="http://127.0.0.1:25503/v3/option/list/expirations?symbol=SPY"
TERM_PROC_RE="ThetaTerminalv3\.jar|/lib/[0-9]+\.jar"
REF_ROOT="${STEVE_REF_ROOT:-/home/kingjames/contracting/upwork/steven-tran/SteveTrading/ref/Data-Preprocessor}"
LOG="$REF_ROOT/pipeline_data/paper_trading_logs/thetadata_lifecycle.log"

# US market holidays (NYSE) — the terminal is not started on these days, so the
# account stays free for Steve. Extend this list each year.
HOLIDAYS="2026-01-01 2026-01-19 2026-02-16 2026-04-03 2026-05-25 2026-06-19 \
2026-07-03 2026-09-07 2026-11-26 2026-12-25 2027-01-01"

log() {
    mkdir -p "$(dirname "$LOG")"
    echo "$(TZ=America/New_York date '+%F %T %Z') [theta-lifecycle] $*" | tee -a "$LOG"
}

is_vps_runtime() {
    [[ -d /opt/stevetrading/shared/Data-Preprocessor ]]
}

guard_local_start() {
    if is_vps_runtime || [[ "${STEVE_ALLOW_LOCAL_THETADATA:-}" == "1" ]]; then
        return 0
    fi
    log "ERROR: refusing local ThetaData start; Hetzner owns the live ThetaData session. Use SSH tunnel, or set STEVE_ALLOW_LOCAL_THETADATA=1 for an explicit emergency override."
    exit 5
}

is_trading_day() {
    local dow today
    dow=$(TZ=America/New_York date '+%u')      # 1=Mon .. 7=Sun
    today=$(TZ=America/New_York date '+%F')
    [[ "$dow" -ge 6 ]] && return 1             # weekend
    [[ " $HOLIDAYS " == *" $today "* ]] && return 1
    return 0
}

# --- network -------------------------------------------------------------
# The terminal cannot authenticate if it cannot resolve the ThetaData auth
# host. This is the 06-17/06-18 failure. DNS resolution is the canary.
net_ready() {
    getent hosts "$AUTH_HOST" >/dev/null 2>&1
}

# Wait up to ~3 min for DNS/network to recover (covers a sleep/resume blip).
# Nudge systemd-resolved periodically, since that is the usual WSL culprit.
wait_for_net() {
    local i
    for i in $(seq 1 12); do
        if net_ready; then return 0; fi
        log "network: cannot resolve $AUTH_HOST (try $i/12) — waiting for recovery"
        if [[ $((i % 4)) -eq 0 ]]; then
            sudo "$SYSTEMCTL" restart systemd-resolved 2>/dev/null || true
        fi
        sleep 15
    done
    net_ready
}

# Classify the live health endpoint: ok | invalid-session | no-response | unexpected
health_reason() {
    local r
    r=$(curl -s -m 15 "$HEALTH_URL" 2>/dev/null)
    if [[ -z "$r" ]]; then
        echo "no-response"                       # port not up yet (warming) or hung
    elif [[ "$r" == *"Invalid session"* ]]; then
        echo "invalid-session"                   # another terminal (Steve) holds the account
    elif [[ "$r" == *expiration* ]]; then
        echo "ok"
    else
        echo "unexpected"
    fi
}

health_ok() {
    [[ "$(health_reason)" == "ok" ]]
}

# Kill stray terminal java procs that systemd failed to reap (the WSL
# "Failed to kill control group: Invalid argument" quirk). Every ThetaTerminal
# process on THIS host is ours — Steve runs his on his own PC — so reaping
# local strays is always safe.
reap_orphans() {
    local pids
    pids=$(pgrep -f "$TERM_PROC_RE" 2>/dev/null | tr '\n' ' ')
    if [[ -n "${pids// }" ]]; then
        log "reaping stray terminal proc(s): $pids"
        kill $pids 2>/dev/null || true
        sleep 2
        pids=$(pgrep -f "$TERM_PROC_RE" 2>/dev/null | tr '\n' ' ')
        [[ -n "${pids// }" ]] && { log "force-killing: $pids"; kill -9 $pids 2>/dev/null || true; }
    fi
}

start() {
    guard_local_start

    if ! is_trading_day; then
        log "not a trading day — terminal left off, account free for Steve"
        exit 0
    fi

    # 0. NETWORK PRECHECK — the 06-17/06-18 outage was DNS, not Steve.
    if ! net_ready; then
        log "network: $AUTH_HOST unresolvable at start — waiting for DNS/network"
        if ! wait_for_net; then
            log "ERROR: network/DNS down — cannot reach $AUTH_HOST (NOT Steve, NOT the terminal)"
            exit 3
        fi
    fi
    log "network OK ($AUTH_HOST resolvable) — starting $SERVICE"
    sudo "$SYSTEMCTL" start "$SERVICE"

    # 1. PATIENT single-start poll. A cold terminal needs ~30-90s to connect to
    #    the upstream feed; do NOT restart every cycle (that thrash stranded the
    #    06-18 orphan). At most one restart mid-window for a wedged start.
    local restarted=0 i reason
    for i in $(seq 1 14); do                    # up to ~140s
        sleep 10
        reason=$(health_reason)
        case "$reason" in
            ok) log "healthy after ~$((i*10))s — live data flowing"; exit 0 ;;
            invalid-session)
                log "Invalid session (~$((i*10))s): another terminal holds the account — Steve still connected?" ;;
            *) : ;;                              # no-response/unexpected: still warming
        esac
        # if the network dropped mid-start, wait rather than thrash
        if ! net_ready; then
            log "network dropped mid-start (~$((i*10))s) — waiting"
            wait_for_net || { log "ERROR: network/DNS down mid-start"; exit 3; }
        fi
        if [[ "$i" -eq 8 && "$restarted" -eq 0 && "$reason" != "invalid-session" ]]; then
            log "still not serving after ~80s — single restart"
            reap_orphans
            sudo "$SYSTEMCTL" restart "$SERVICE"
            restarted=1
        fi
    done

    reason=$(health_reason)
    log "ERROR: terminal not healthy after ~140s (last reason: $reason)"
    case "$reason" in
        invalid-session) log "  -> Steve's terminal is likely still connected; account not free" ;;
        no-response)     log "  -> terminal never served data (warmup/auth?); check journalctl -u $SERVICE" ;;
    esac
    net_ready || log "  -> and DNS for $AUTH_HOST is currently failing"
    exit 1
}

stop() {
    log "stopping $SERVICE"
    sudo "$SYSTEMCTL" stop "$SERVICE"
    sleep 3
    reap_orphans                                # belt for the WSL cgroup-kill quirk
    if "$SYSTEMCTL" is-active --quiet "$SERVICE"; then
        log "ERROR: $SERVICE still active after stop"
        exit 1
    fi
    log "stopped — account session handed back to Steve"
}

status() {
    echo "service : $("$SYSTEMCTL" is-active "$SERVICE" 2>/dev/null)"
    echo "network : $(net_ready && echo "OK ($AUTH_HOST resolvable)" || echo "DNS FAIL — cannot resolve $AUTH_HOST")"
    echo "health  : $(health_reason)"
    echo "procs   :"
    ps -eo pid,etime,cmd | grep -E "$TERM_PROC_RE" | grep -v grep \
        | sed 's/^/  /' || echo "  (none)"
}

case "${1:-}" in
    start)  start ;;
    stop)   stop ;;
    status) status ;;
    net)    net_ready && { echo "net: OK"; exit 0; } || { echo "net: FAIL"; exit 1; } ;;
    *) echo "usage: $0 {start|stop|status|net}"; exit 2 ;;
esac
