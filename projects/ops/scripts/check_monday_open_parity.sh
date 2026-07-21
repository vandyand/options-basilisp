#!/usr/bin/env bash
# Persist a concise, machine-readable Monday-open checkpoint without starting
# another capture or competing with the scheduled parity pipeline.
set -euo pipefail

ROOT="${STEVETRADING_BASILISP_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
REMOTE="${THETADATA_PARITY_REMOTE:-bot@167.233.141.61}"
REMOTE_ROOT="${THETADATA_PARITY_REMOTE_ROOT:-/opt/stevetrading/shared/thetadata-parity-v1}"
LOCAL_ROOT="${THETADATA_PARITY_LOCAL_ROOT:-/mnt/d/stevetrading/thetadata-parity-v1}"
BASILISP_BIN="${BASILISP_BIN:-$ROOT/.venv/bin/basilisp}"
SSH_BIN="${CHECKPOINT_SSH_BIN:-ssh}"
PHASE=""
DATE="$(TZ=America/New_York date +%F)"
OUT_DIR="$ROOT/live_runtime/monday-open-checks"

usage() {
  cat <<'USAGE'
Usage: check_monday_open_parity.sh --phase liveness|evidence [--date YYYY-MM-DD] [--out-dir PATH]
USAGE
}

while (($#)); do
  case "$1" in
    --phase) PHASE="${2:-}"; shift 2 ;;
    --date) DATE="${2:-}"; shift 2 ;;
    --out-dir) OUT_DIR="${2:-}"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

case "$PHASE" in
  liveness|evidence) ;;
  *) echo "--phase must be liveness or evidence" >&2; usage >&2; exit 2 ;;
esac

if [[ ! "$DATE" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
  echo "--date must be YYYY-MM-DD" >&2
  exit 2
fi

mkdir -p "$OUT_DIR"
STAMP="$(TZ=America/New_York date +%Y%m%dT%H%M%S%z)"
OUT="$OUT_DIR/${DATE}-${PHASE}-${STAMP}.json"

set +e
REMOTE_JSON="$("$SSH_BIN" -o BatchMode=yes -o ConnectTimeout=12 "$REMOTE" "TARGET_DATE='$DATE' REMOTE_ROOT='$REMOTE_ROOT' bash -s" <<'REMOTE'
set -u
unit_state() { systemctl is-active "$1" 2>/dev/null || true; }
health_file="$(mktemp)"
health_meta="$(curl -sS --max-time 8 -o "$health_file" -w '%{http_code} %{size_download}' \
  'http://127.0.0.1:25503/v3/option/list/expirations?symbol=SPY&format=json' 2>/dev/null || true)"
rm -f "$health_file"

receipt_dir="$REMOTE_ROOT/receipts/$TARGET_DATE/stream-events"
receipt="$(find "$receipt_dir" -maxdepth 1 -type f -name '*.json' 2>/dev/null | sort | tail -n 1)"
receipt_status=""
market_events="0"
if [[ -n "$receipt" ]] && command -v jq >/dev/null 2>&1; then
  receipt_status="$(jq -r '.status // empty' "$receipt" 2>/dev/null || true)"
  market_events="$(jq -r '.summary.market_event_count // 0' "$receipt" 2>/dev/null || printf '0')"
fi

jq -n \
  --arg host "$(hostname)" \
  --arg six "$(unit_state stevetrading-six.service)" \
  --arg terminal "$(unit_state theta-terminal.service)" \
  --arg snapshot "$(unit_state stevetrading-raw-thetadata-parity.service)" \
  --arg capture "$(unit_state stevetrading-thetadata-stream-capture.service)" \
  --arg history "$(unit_state stevetrading-raw-history-parity.service)" \
  --arg health_meta "$health_meta" \
  --arg receipt "$receipt" \
  --arg receipt_status "$receipt_status" \
  --argjson market_events "$market_events" \
  '{host: $host,
    units: {stevetrading_six: $six, theta_terminal: $terminal,
            raw_snapshot: $snapshot, stream_capture: $capture, raw_history: $history},
    terminal_health: {curl: $health_meta},
    latest_stream_receipt: {path: $receipt, status: $receipt_status,
                            market_event_count: $market_events}}'
REMOTE
)"
REMOTE_EXIT=$?
set -e

if [[ "$REMOTE_EXIT" -ne 0 ]] || ! jq -e . >/dev/null 2>&1 <<<"$REMOTE_JSON"; then
  REMOTE_JSON="$(jq -n --arg error "remote checkpoint failed (exit $REMOTE_EXIT)" '{error: $error}')"
  REMOTE_STATUS="UNREACHABLE"
else
  REMOTE_STATUS="OBSERVED"
fi

VERIFIER_STATUS="NOT_RUN"
VERIFIER_EXIT=""
VERIFIER_OUTPUT=""
VERIFIER_ARTIFACT=""
if [[ "$PHASE" == "evidence" ]]; then
  VERIFIER_ARTIFACT="$LOCAL_ROOT/verification/$DATE/raw-history-evidence.json"
  set +e
  VERIFIER_OUTPUT="$("$BASILISP_BIN" run "$ROOT/scripts/verify_raw_parity_evidence.lpy" -- \
    --landing-root "$LOCAL_ROOT" --target-date "$DATE" --out "$VERIFIER_ARTIFACT" 2>&1)"
  VERIFIER_EXIT=$?
  set -e
  if [[ -f "$VERIFIER_ARTIFACT" ]] && jq -e . >/dev/null 2>&1 <"$VERIFIER_ARTIFACT"; then
    VERIFIER_STATUS="$(jq -r '.status // "UNKNOWN"' "$VERIFIER_ARTIFACT")"
  else
    VERIFIER_STATUS="ERROR"
  fi
fi

CHECK_STATUS="$REMOTE_STATUS"
if [[ "$PHASE" == "evidence" && "$REMOTE_STATUS" == "OBSERVED" ]]; then
  CHECK_STATUS="$VERIFIER_STATUS"
fi

jq -n \
  --arg schema_version "1" \
  --arg created_at "$(TZ=America/New_York date --iso-8601=seconds)" \
  --arg phase "$PHASE" \
  --arg target_date "$DATE" \
  --arg status "$CHECK_STATUS" \
  --arg remote "$REMOTE" \
  --arg remote_status "$REMOTE_STATUS" \
  --arg verifier_status "$VERIFIER_STATUS" \
  --arg verifier_artifact "$VERIFIER_ARTIFACT" \
  --arg verifier_output "$VERIFIER_OUTPUT" \
  --argjson verifier_exit "${VERIFIER_EXIT:-null}" \
  --argjson remote_checkpoint "$REMOTE_JSON" \
  '{schema_version: ($schema_version | tonumber), created_at: $created_at,
    phase: $phase, target_date: $target_date, status: $status, remote: $remote,
    remote_status: $remote_status, remote_checkpoint: $remote_checkpoint,
    local_evidence: {verifier_status: $verifier_status, verifier_exit: $verifier_exit,
                     verifier_artifact: $verifier_artifact, verifier_output: $verifier_output}}' \
  | tee "$OUT"

echo "monday-open checkpoint written: $OUT" >&2

if [[ "$REMOTE_STATUS" == "UNREACHABLE" ]]; then
  exit 1
fi
if [[ "$PHASE" == "evidence" && "$VERIFIER_STATUS" == "ERROR" ]]; then
  exit 2
fi
