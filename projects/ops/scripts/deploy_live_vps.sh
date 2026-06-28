#!/usr/bin/env bash
# Deploy the current working tree to a SteveTrading VPS release directory.
#
# This script intentionally deploys a release directory and then flips the
# /opt/stevetrading/current symlink only after remote preflight passes. That
# avoids editing production in place.
set -euo pipefail

HOST="${1:?usage: deploy_live_vps.sh bot@host [ref-root]}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOCAL_REPO="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || cd "$SCRIPT_DIR/../../.." && pwd)"
LOCAL_REF="${2:-$HOME/contracting/upwork/steven-tran/SteveTrading/ref/Data-Preprocessor}"
REMOTE_ROOT="${REMOTE_ROOT:-/opt/stevetrading}"
RELEASE_ID="${RELEASE_ID:-$(date -u +%Y%m%dT%H%M%SZ)-$(git -C "$LOCAL_REPO" rev-parse --short HEAD 2>/dev/null || echo worktree)}"
REMOTE_RELEASE="$REMOTE_ROOT/releases/$RELEASE_ID"
REMOTE_REF="$REMOTE_ROOT/shared/Data-Preprocessor"

log() { echo "$(date -u '+%FT%TZ') [deploy] $*"; }

log "creating release $REMOTE_RELEASE"
ssh "$HOST" "mkdir -p '$REMOTE_RELEASE' '$REMOTE_ROOT/shared' '$REMOTE_ROOT/releases'"

log "syncing Basilisp repo"
rsync -az --delete \
  --exclude '.git/' \
  --exclude '.venv/' \
  --exclude '.pytest_cache/' \
  --exclude '__pycache__/' \
  --exclude 'live_runtime/' \
  "$LOCAL_REPO"/ "$HOST:$REMOTE_RELEASE"/

log "syncing Data-Preprocessor reference tree"
rsync -az --delete --delete-excluded \
  --exclude '.git/' \
  --exclude '.planning/' \
  --exclude '__pycache__/' \
  --exclude '.pytest_cache/' \
  --exclude 'cache/' \
  --exclude 'logs/' \
  --exclude 'research-papers/' \
  --exclude 'report-viewer/node_modules/' \
  --exclude 'tests/' \
  --exclude 'pipeline_data/paper_trading_logs/' \
  "$LOCAL_REF"/ "$HOST:$REMOTE_REF"/

log "installing compatibility symlink for copied Python venv shebangs"
ssh "$HOST" "sudo mkdir -p /home/kingjames/contracting/upwork/steven-tran/SteveTrading/ref && \
  sudo ln -sfn '$REMOTE_REF' /home/kingjames/contracting/upwork/steven-tran/SteveTrading/ref/Data-Preprocessor"

log "installing repo-owned ThetaData lifecycle wrapper into reference tree"
rsync -az "$LOCAL_REPO/projects/ops/scripts/thetadata_lifecycle.sh" "$HOST:$REMOTE_REF/thetadata_lifecycle.sh"

log "installing runtime env file if absent"
ssh "$HOST" "sudo mkdir -p /etc/stevetrading && if [ ! -f /etc/stevetrading/env ]; then sudo tee /etc/stevetrading/env >/dev/null <<'EOF'
STEVE_REPO_ROOT=$REMOTE_ROOT/current
STEVE_REF_ROOT=$REMOTE_REF
BASILISP_BIN=$REMOTE_REF/.venv/bin/basilisp
STEVE_THETADATA_LIFECYCLE=$REMOTE_REF/thetadata_lifecycle.sh
BROKER_TARGET=alpaca
STEVE_BUNDLES=corrected
EOF
fi"

log "installing systemd units"
ssh "$HOST" "sudo cp '$REMOTE_RELEASE/projects/ops/scripts/systemd/theta-terminal.service' /etc/systemd/system/theta-terminal.service && \
  sudo cp '$REMOTE_RELEASE/projects/ops/scripts/systemd/stevetrading-six.service' /etc/systemd/system/stevetrading-six.service && \
  sudo cp '$REMOTE_RELEASE/projects/ops/scripts/systemd/stevetrading-six.timer' /etc/systemd/system/stevetrading-six.timer && \
  sudo cp '$REMOTE_RELEASE/projects/ops/scripts/systemd/stevetrading-watchdog.service' /etc/systemd/system/stevetrading-watchdog.service && \
  sudo cp '$REMOTE_RELEASE/projects/ops/scripts/systemd/stevetrading-watchdog.timer' /etc/systemd/system/stevetrading-watchdog.timer && \
  sudo cp '$REMOTE_RELEASE/projects/ops/scripts/systemd/stevetrading-reports-build.service' /etc/systemd/system/stevetrading-reports-build.service && \
  sudo cp '$REMOTE_RELEASE/projects/ops/scripts/systemd/stevetrading-reports-build.timer' /etc/systemd/system/stevetrading-reports-build.timer && \
  sudo cp '$REMOTE_RELEASE/projects/ops/scripts/systemd/stevetrading-reports-web.service' /etc/systemd/system/stevetrading-reports-web.service && \
  sudo systemctl daemon-reload; sudo systemctl disable theta-terminal.service >/dev/null 2>&1 || true"

log "regenerating pythonpath and running import preflight"
ssh "$HOST" "cd '$REMOTE_RELEASE' && \
  ls -d components/*/src bases/*/src | paste -sd: - > .nrepl-pythonpath && \
  set -a && . /etc/stevetrading/env && set +a && \
  PYTHONPATH=\"\$(cat .nrepl-pythonpath)\" \"\$BASILISP_BIN\" run scripts/preflight_live_imports.lpy"

log "promoting current symlink"
ssh "$HOST" "ln -sfn '$REMOTE_RELEASE' '$REMOTE_ROOT/current'"

log "linking shared runtime into promoted release"
ssh "$HOST" "mkdir -p '$REMOTE_ROOT/shared/live_runtime' && \
  rm -rf '$REMOTE_ROOT/current/live_runtime' && \
  ln -sfn '$REMOTE_ROOT/shared/live_runtime' '$REMOTE_ROOT/current/live_runtime'"

if [[ "${DISABLE_LIVE_AFTER_DEPLOY:-0}" == "1" ]]; then
  log "DISABLE_LIVE_AFTER_DEPLOY=1: disabling live timers/services"
  ssh "$HOST" "sudo systemctl disable --now stevetrading-six.service >/dev/null 2>&1 || true; \
    sudo systemctl disable --now stevetrading-six.timer >/dev/null 2>&1 || true; \
    sudo systemctl disable --now stevetrading-watchdog.timer >/dev/null 2>&1 || true"
else
  log "leaving live timer/service enablement unchanged"
fi

log "deployed $RELEASE_ID"
log "cutover when ready: ssh $HOST 'sudo systemctl enable --now stevetrading-six.timer stevetrading-watchdog.timer'"
log "manual market-hours incident start: ssh $HOST 'sudo systemctl start stevetrading-six.service'"
