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

log "provisioning systemd log directory"
ssh "$HOST" "sudo mkdir -p /var/log/stevetrading && sudo chown bot:bot /var/log/stevetrading"

log "syncing Basilisp repo"
rsync -az --delete --delete-excluded \
  --exclude '.git/' \
  --exclude '.venv/' \
  --exclude '.pytest_cache/' \
  --exclude '__pycache__/' \
  --exclude 'live_runtime/' \
  "$LOCAL_REPO"/ "$HOST:$REMOTE_RELEASE"/

log "removing stale Python entrypoints/caches from managed release paths"
ssh "$HOST" "cd '$REMOTE_RELEASE' && \
  find scripts projects/ops/scripts tests components bases \
    \( -name '*.py' -o -name '*.pyc' -o -name '__pycache__' \) \
    -print -exec rm -rf {} +"

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
STEVETRADING_BASILISP_ROOT=$REMOTE_ROOT/current
STEVE_REF_ROOT=$REMOTE_REF
BASILISP_BIN=$REMOTE_REF/.venv/bin/basilisp
STEVE_THETADATA_LIFECYCLE=$REMOTE_REF/thetadata_lifecycle.sh
ANALYSIS_DIR=$REMOTE_ROOT/shared/live_runtime/analysis
CAPTURE_DIR=$REMOTE_ROOT/shared/live_runtime/feature-capture
PAYLOAD_DIR=$REMOTE_ROOT/shared/payload_examples
STEVE_EXTRA_OPTION_SYMBOLS=disabled
STEVE_FETCH_OPTION_SIDECARS=1
STEVE_EXTRA_OPTION_HORIZON_DAYS=30
STEVE_CAPTURE_SIDECAR_EVERY=1
STEVE_STOCK_BAR_SOURCE=thetadata
THETADATA_STOCK_VENUE=nqb
STEVE_CHAIN_STRIKE_RANGE=100
STEVE_MAX_SIGNAL_LAG_SECONDS=180
BROKER_TARGET=alpaca
STEVE_BUNDLES=corrected
EOF
fi"

log "ensuring runtime env points runners at shared reference venv"
ssh "$HOST" "sudo bash -c '
set -euo pipefail
env_path=/etc/stevetrading/env
touch \"\$env_path\"
upsert() {
  key=\"\$1\"
  value=\"\$2\"
  if grep -q \"^\${key}=\" \"\$env_path\"; then
    escaped=\$(printf \"%s\" \"\$value\" | sed \"s/[&|]/\\\\&/g\")
    sed -i \"s|^\${key}=.*|\${key}=\${escaped}|\" \"\$env_path\"
  else
    printf \"%s=%s\\n\" \"\$key\" \"\$value\" >> \"\$env_path\"
  fi
}
upsert STEVE_REPO_ROOT \"$REMOTE_ROOT/current\"
upsert STEVETRADING_BASILISP_ROOT \"$REMOTE_ROOT/current\"
upsert STEVE_REF_ROOT \"$REMOTE_REF\"
upsert BASILISP_BIN \"$REMOTE_REF/.venv/bin/basilisp\"
upsert STEVE_THETADATA_LIFECYCLE \"$REMOTE_REF/thetadata_lifecycle.sh\"
upsert ANALYSIS_DIR \"$REMOTE_ROOT/shared/live_runtime/analysis\"
upsert CAPTURE_DIR \"$REMOTE_ROOT/shared/live_runtime/feature-capture\"
upsert PAYLOAD_DIR \"$REMOTE_ROOT/shared/payload_examples\"
upsert STEVE_EXTRA_OPTION_SYMBOLS \"disabled\"
upsert STEVE_FETCH_OPTION_SIDECARS \"1\"
upsert STEVE_EXTRA_OPTION_HORIZON_DAYS \"30\"
upsert STEVE_CAPTURE_SIDECAR_EVERY \"1\"
upsert STEVE_STOCK_BAR_SOURCE \"thetadata\"
upsert THETADATA_STOCK_VENUE \"nqb\"
upsert STEVE_CHAIN_STRIKE_RANGE \"100\"
upsert STEVE_MAX_SIGNAL_LAG_SECONDS \"180\"
sed -i \"/^PYTHON_BIN=/d\" \"\$env_path\"
'"

log "ensuring reports web auth env is present and fail-closed"
ssh "$HOST" "sudo bash -c '
set -euo pipefail
env_path=/etc/stevetrading/reports.env
if [ ! -f \"\$env_path\" ]; then
  cat > \"\$env_path\" <<EOF
REPORTS_ROOT=$REMOTE_REF/report-viewer/public
REPORTS_USER=stevetrading
REPORTS_PUBLIC_STATUS=0
REPORTS_ALLOW_NO_AUTH=0
EOF
fi
password_hash=\$(grep -E \"^REPORTS_PASSWORD_SHA256=\" \"\$env_path\" | tail -1 | cut -d= -f2- || true)
allow_no_auth=\$(grep -E \"^REPORTS_ALLOW_NO_AUTH=\" \"\$env_path\" | tail -1 | cut -d= -f2- || true)
if [ -z \"\$password_hash\" ]; then
  echo \"REPORTS_PASSWORD_SHA256 must be set in /etc/stevetrading/reports.env before deploying reports web\" >&2
  exit 1
fi
if [ \"\$allow_no_auth\" = \"1\" ]; then
  echo \"REPORTS_ALLOW_NO_AUTH=1 is not allowed in /etc/stevetrading/reports.env on the VPS\" >&2
  exit 1
fi
'"

log "installing systemd units"
ssh "$HOST" "sudo cp '$REMOTE_RELEASE/projects/ops/scripts/systemd/theta-terminal.service' /etc/systemd/system/theta-terminal.service && \
  sudo cp '$REMOTE_RELEASE/projects/ops/scripts/systemd/stevetrading-six.service' /etc/systemd/system/stevetrading-six.service && \
  sudo cp '$REMOTE_RELEASE/projects/ops/scripts/systemd/stevetrading-six.timer' /etc/systemd/system/stevetrading-six.timer && \
  sudo cp '$REMOTE_RELEASE/projects/ops/scripts/systemd/stevetrading-broker-flatten.service' /etc/systemd/system/stevetrading-broker-flatten.service && \
  sudo cp '$REMOTE_RELEASE/projects/ops/scripts/systemd/stevetrading-broker-flatten.timer' /etc/systemd/system/stevetrading-broker-flatten.timer && \
  sudo cp '$REMOTE_RELEASE/projects/ops/scripts/systemd/stevetrading-watchdog.service' /etc/systemd/system/stevetrading-watchdog.service && \
  sudo cp '$REMOTE_RELEASE/projects/ops/scripts/systemd/stevetrading-watchdog.timer' /etc/systemd/system/stevetrading-watchdog.timer && \
  sudo cp '$REMOTE_RELEASE/projects/ops/scripts/systemd/stevetrading-reports-build.service' /etc/systemd/system/stevetrading-reports-build.service && \
  sudo cp '$REMOTE_RELEASE/projects/ops/scripts/systemd/stevetrading-reports-build.timer' /etc/systemd/system/stevetrading-reports-build.timer && \
  sudo cp '$REMOTE_RELEASE/projects/ops/scripts/systemd/stevetrading-status-dashboard.service' /etc/systemd/system/stevetrading-status-dashboard.service && \
  sudo cp '$REMOTE_RELEASE/projects/ops/scripts/systemd/stevetrading-status-dashboard.timer' /etc/systemd/system/stevetrading-status-dashboard.timer && \
  sudo cp '$REMOTE_RELEASE/projects/ops/scripts/systemd/stevetrading-market-evidence-preflight.service' /etc/systemd/system/stevetrading-market-evidence-preflight.service && \
  sudo cp '$REMOTE_RELEASE/projects/ops/scripts/systemd/stevetrading-market-evidence-preflight.timer' /etc/systemd/system/stevetrading-market-evidence-preflight.timer && \
  sudo cp '$REMOTE_RELEASE/projects/ops/scripts/systemd/stevetrading-market-evidence-capture-smoke.service' /etc/systemd/system/stevetrading-market-evidence-capture-smoke.service && \
  sudo cp '$REMOTE_RELEASE/projects/ops/scripts/systemd/stevetrading-market-evidence-capture-smoke.timer' /etc/systemd/system/stevetrading-market-evidence-capture-smoke.timer && \
  sudo cp '$REMOTE_RELEASE/projects/ops/scripts/systemd/stevetrading-market-evidence-collect.service' /etc/systemd/system/stevetrading-market-evidence-collect.service && \
  sudo cp '$REMOTE_RELEASE/projects/ops/scripts/systemd/stevetrading-market-evidence-collect.timer' /etc/systemd/system/stevetrading-market-evidence-collect.timer && \
  sudo cp '$REMOTE_RELEASE/projects/ops/scripts/systemd/stevetrading-raw-thetadata-parity.service' /etc/systemd/system/stevetrading-raw-thetadata-parity.service && \
  sudo cp '$REMOTE_RELEASE/projects/ops/scripts/systemd/stevetrading-raw-thetadata-parity.timer' /etc/systemd/system/stevetrading-raw-thetadata-parity.timer && \
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
ssh "$HOST" "mkdir -p '$REMOTE_ROOT/shared/live_runtime/analysis' \
    '$REMOTE_ROOT/shared/live_runtime/feature-capture' \
    '$REMOTE_ROOT/shared/payload_examples' \
    '$REMOTE_ROOT/shared/thetadata-parity-v1' && \
  rm -rf '$REMOTE_ROOT/current/live_runtime' && \
  ln -sfn '$REMOTE_ROOT/shared/live_runtime' '$REMOTE_ROOT/current/live_runtime' && \
  mkdir -p '$REMOTE_ROOT/current/resources/thetadata' && \
  ln -sfn '$REMOTE_ROOT/shared/payload_examples' '$REMOTE_ROOT/current/resources/thetadata/payload_examples'"

log "running market evidence wrapper preflight after promotion"
ssh "$HOST" "cd '$REMOTE_ROOT/current' && \
  set -a && . /etc/stevetrading/env && set +a && \
  MARKET_EVIDENCE_MODE=preflight \
  MARKET_EVIDENCE_SKIP_NON_TRADING_DAYS=0 \
  MARKET_EVIDENCE_LOG_DIR='$REMOTE_ROOT/shared/live_runtime/logs' \
  ANALYSIS_DIR='$REMOTE_ROOT/shared/live_runtime/analysis' \
  CAPTURE_DIR='$REMOTE_ROOT/shared/live_runtime/feature-capture' \
  PAYLOAD_DIR='$REMOTE_ROOT/shared/payload_examples' \
  projects/ops/scripts/run_market_evidence.sh"

if [[ "${DISABLE_LIVE_AFTER_DEPLOY:-0}" == "1" ]]; then
  log "DISABLE_LIVE_AFTER_DEPLOY=1: disabling live timers/services"
  ssh "$HOST" "sudo systemctl disable --now stevetrading-six.service >/dev/null 2>&1 || true; \
    sudo systemctl disable --now stevetrading-six.timer >/dev/null 2>&1 || true; \
    sudo systemctl disable --now stevetrading-watchdog.timer >/dev/null 2>&1 || true; \
    sudo systemctl disable --now stevetrading-broker-flatten.timer >/dev/null 2>&1 || true; \
    sudo systemctl disable --now stevetrading-market-evidence-preflight.timer >/dev/null 2>&1 || true; \
    sudo systemctl disable --now stevetrading-market-evidence-capture-smoke.timer >/dev/null 2>&1 || true; \
    sudo systemctl disable --now stevetrading-market-evidence-collect.timer >/dev/null 2>&1 || true; \
    sudo systemctl disable --now stevetrading-raw-thetadata-parity.timer >/dev/null 2>&1 || true"
else
  log "leaving live timer/service enablement unchanged"
fi

log "deployed $RELEASE_ID"
log "cutover when ready: ssh $HOST 'sudo systemctl enable --now stevetrading-six.timer stevetrading-watchdog.timer stevetrading-broker-flatten.timer stevetrading-reports-build.timer stevetrading-status-dashboard.timer stevetrading-market-evidence-preflight.timer stevetrading-market-evidence-capture-smoke.timer stevetrading-market-evidence-collect.timer stevetrading-raw-thetadata-parity.timer'"
log "manual market-hours incident start: ssh $HOST 'sudo systemctl start stevetrading-six.service'"
