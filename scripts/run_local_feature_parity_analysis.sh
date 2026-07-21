#!/usr/bin/env bash
# Run expensive Steve V2 parity reconstruction on the workstation while the
# VPS remains the sole owner of live trading and ThetaData Terminal.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/run_local_feature_parity_analysis.sh --target-date YYYY-MM-DD [options]

Synchronizes immutable VPS capture/cache inputs, opens a temporary SSH tunnel
to the VPS-local ThetaData Terminal, and runs canonical replay, historical
reconstruction, matched parity, and drift-ledger generation on this machine.

Options:
  --remote USER@HOST       SSH target (default: FEATURE_PARITY_REMOTE or bot@167.233.141.61)
  --remote-root PATH       VPS shared root (default: /opt/stevetrading/shared)
  --end-time HH:MM:SS      Historical reconstruction end (default: 15:59:00)
  --jobs N                 Local historical fetch workers (default: 16)
  --port N                 Temporary local ThetaData tunnel port (default: 25513)
  --replay-rows N          Recent rows for exact replay smoke (default: 1; 0 means full session)
  --cohort-window-minutes N  Trailing historical option window, excluding grid warmup (default: 75; 0 means full session)
  --include-option-overlays Include expensive SPY option aggregates in replay (off by default)
  --skip-historical        Run only exact captured-live replay plus ledger.
EOF
}

ROOT="${STEVE_REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
REF="${STEVE_REF_ROOT:-$HOME/contracting/upwork/steven-tran/SteveTrading/ref/Data-Preprocessor}"
REMOTE="${FEATURE_PARITY_REMOTE:-bot@167.233.141.61}"
REMOTE_ROOT="${FEATURE_PARITY_REMOTE_ROOT:-/opt/stevetrading/shared}"
TARGET_DATE=""
END_TIME="15:59:00"
JOBS="${FEATURE_PARITY_LOCAL_JOBS:-16}"
PORT="${FEATURE_PARITY_TUNNEL_PORT:-25513}"
REPLAY_ROWS="${FEATURE_PARITY_REPLAY_ROWS:-1}"
COHORT_WINDOW_MINUTES="${FEATURE_PARITY_COHORT_WINDOW_MINUTES:-75}"
INCLUDE_OPTION_OVERLAYS=0
SKIP_HISTORICAL=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target-date) TARGET_DATE="$2"; shift 2 ;;
    --remote) REMOTE="$2"; shift 2 ;;
    --remote-root) REMOTE_ROOT="$2"; shift 2 ;;
    --end-time) END_TIME="$2"; shift 2 ;;
    --jobs) JOBS="$2"; shift 2 ;;
    --port) PORT="$2"; shift 2 ;;
    --replay-rows) REPLAY_ROWS="$2"; shift 2 ;;
    --cohort-window-minutes) COHORT_WINDOW_MINUTES="$2"; shift 2 ;;
    --include-option-overlays) INCLUDE_OPTION_OVERLAYS=1; shift ;;
    --skip-historical) SKIP_HISTORICAL=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ "$TARGET_DATE" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || { echo "--target-date must be YYYY-MM-DD" >&2; exit 2; }
[[ -d "$REF" ]] || { echo "missing Steve reference root: $REF" >&2; exit 2; }
if [[ -n "${BASILISP_BIN:-}" ]]; then
  BASILISP="$BASILISP_BIN"
elif [[ -x "$REF/.venv/bin/basilisp" ]]; then
  BASILISP="$REF/.venv/bin/basilisp"
else
  BASILISP="$ROOT/.venv/bin/basilisp"
fi
[[ -x "$BASILISP" ]] || { echo "missing Basilisp runner: $BASILISP" >&2; exit 2; }

STAMP="${TARGET_DATE//-/}"
RUNTIME="$ROOT/live_runtime"
SYNC_ROOT="$RUNTIME/feature-parity-sync/$STAMP"
CAPTURE="$SYNC_ROOT/live_features_$STAMP.npz"
CACHE_DIR="$SYNC_ROOT/thetadata-cache"
OUT_DIR="$RUNTIME/analysis/local-parity/$STAMP"
BUNDLE="$REF/pipeline_data/live_model_chestnut_multihead_corrected"

mkdir -p "$SYNC_ROOT" "$CACHE_DIR" "$OUT_DIR"
cd "$ROOT"

# Capture is atomically rewritten during market hours. Snapshot it on the VPS
# before transfer so analysis cannot compare tensors from a moving file.
REMOTE_CAPTURE="$REMOTE_ROOT/live_runtime/feature-capture/live_features_$STAMP.npz"
REMOTE_SNAPSHOT_DIR="$REMOTE_ROOT/live_runtime/feature-parity-snapshots/$STAMP"
REMOTE_SNAPSHOT="$REMOTE_SNAPSHOT_DIR/live_features_${STAMP}_$(date -u +%Y%m%dT%H%M%SZ)_$$.npz"
REMOTE_CAPTURE_SHA256="$(ssh "$REMOTE" "mkdir -p '$REMOTE_SNAPSHOT_DIR' && cp --reflink=auto -- '$REMOTE_CAPTURE' '$REMOTE_SNAPSHOT' && sha256sum '$REMOTE_SNAPSHOT'" | awk '{print $1}')"

# Copy only immutable analysis inputs. Local work never writes the VPS capture.
rsync -a --partial --checksum "$REMOTE:$REMOTE_SNAPSHOT" "$CAPTURE"
rsync -a --partial --checksum "$REMOTE:$REMOTE_ROOT/live_runtime/analysis/thetadata-cache/" "$CACHE_DIR/"

CODE_VERSION="$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || printf 'unknown')"
CAPTURE_SHA256="$(sha256sum "$CAPTURE" | awk '{print $1}')"
[[ "$CAPTURE_SHA256" == "$REMOTE_CAPTURE_SHA256" ]] || { echo "capture checksum changed during transfer" >&2; exit 1; }
REPLAY_NPZ="$OUT_DIR/replayed_feature_cohort_$STAMP.npz"
REPLAY_JSON="$OUT_DIR/replayed_feature_cohort_$STAMP.json"
HIST_NPZ="$OUT_DIR/historical_features_$STAMP.npz"
HIST_JSON="$OUT_DIR/historical_feature_cohort_$STAMP.json"
MATCHED_CSV="$OUT_DIR/matched_feature_parity_$STAMP.csv"

replay_cmd=("$BASILISP" run scripts/replay_captured_feature_cohort.lpy --
  --capture "$CAPTURE" --ref-root "$REF" --bundle "$BUNDLE"
  --out-npz "$REPLAY_NPZ" --out-json "$REPLAY_JSON" --target-date "$TARGET_DATE" --min-rows 1
  --tail-rows "$REPLAY_ROWS" --implementation legacy-python)
if [[ "$INCLUDE_OPTION_OVERLAYS" != "1" ]]; then
  # Option features are neutralized today. Verify their raw-chain formulas in
  # focused audits; do not make the core tensor invariant pay chain cost per row.
  replay_cmd+=(--skip-option-overlays)
fi
set +e
"${replay_cmd[@]}"
REPLAY_RC=$?
set -e
if [[ ! -f "$REPLAY_JSON" ]]; then
  echo "replay did not write evidence JSON: $REPLAY_JSON" >&2
  exit "$REPLAY_RC"
fi
if [[ "$REPLAY_RC" != "0" ]]; then
  "$BASILISP" run scripts/feature_drift_ledger.lpy -- \
    --target-date "$TARGET_DATE" --replay-json "$REPLAY_JSON" --out-dir "$OUT_DIR" \
    --code-version "$CODE_VERSION" --capture-sha256 "$CAPTURE_SHA256"
  exit "$REPLAY_RC"
fi

TUNNEL_PID=""
cleanup() {
  if [[ -n "$TUNNEL_PID" ]]; then
    kill "$TUNNEL_PID" 2>/dev/null || true
    wait "$TUNNEL_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

if [[ "$SKIP_HISTORICAL" != "1" ]]; then
  ssh -N -L "$PORT:127.0.0.1:25503" -o ExitOnForwardFailure=yes "$REMOTE" &
  TUNNEL_PID=$!
  for _ in $(seq 1 30); do
    if curl -fsS --max-time 2 "http://127.0.0.1:$PORT/v3/option/list/expirations?symbol=SPY&format=json" >/dev/null; then
      break
    fi
    sleep 1
  done
  curl -fsS --max-time 2 "http://127.0.0.1:$PORT/v3/option/list/expirations?symbol=SPY&format=json" >/dev/null

  "$BASILISP" run scripts/build_thetadata_historical_feature_cohort.lpy -- \
    --target-date "$TARGET_DATE" --ref-root "$REF" --bundle "$BUNDLE" \
    --implementation legacy-python \
    --base-url "http://127.0.0.1:$PORT" --start-time 09:30:00 --stock-start-time 04:00:00 \
    --end-time "$END_TIME" --chain-horizon-days 1 --surface-horizon-days 45 \
    --jobs "$JOBS" --request-timeout 15 --thetadata-cache-dir "$CACHE_DIR" --min-rows 60 \
    --cohort-window-minutes "$COHORT_WINDOW_MINUTES" \
    --out-npz "$HIST_NPZ" --out-json "$HIST_JSON" --strike-range 1 --spy-strike-range 100

  "$BASILISP" run scripts/matched_feature_parity_report.lpy -- \
    --live-capture "$CAPTURE" --historical-npz "$HIST_NPZ" \
    --feature-names "$BUNDLE/feature_names.json" --out-dir "$OUT_DIR" \
    --target-date "$TARGET_DATE" --min-rows 60
fi

ledger_args=("$BASILISP" run scripts/feature_drift_ledger.lpy --
  --target-date "$TARGET_DATE" --replay-json "$REPLAY_JSON" --out-dir "$OUT_DIR"
  --code-version "$CODE_VERSION" --capture-sha256 "$CAPTURE_SHA256")
if [[ -f "$MATCHED_CSV" ]]; then
  ledger_args+=(--matched-csv "$MATCHED_CSV")
fi
"${ledger_args[@]}"

printf 'Local parity artifacts: %s\n' "$OUT_DIR"
printf 'Immutable VPS capture snapshot: %s\n' "$REMOTE_SNAPSHOT"
