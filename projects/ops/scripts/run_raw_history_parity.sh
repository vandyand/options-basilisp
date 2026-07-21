#!/usr/bin/env bash
set -euo pipefail
ROOT="${STEVETRADING_BASILISP_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
BASILISP_BIN="${BASILISP_BIN:-$ROOT/.venv/bin/basilisp}"
LANDING_ROOT="${THETADATA_STREAM_LANDING_ROOT:-/opt/stevetrading/shared/thetadata-parity-v1}"
DATE="${RAW_HISTORY_PARITY_DATE:-$(TZ=America/New_York date +%F)}"
RECEIPT_DIR="$LANDING_ROOT/receipts/$DATE/stream-events"
RECEIPT="$(find "$RECEIPT_DIR" -maxdepth 1 -name '*.json' -type f | sort | tail -n 1)"
[[ -n "$RECEIPT" ]] || { echo "no stream receipt for $DATE" >&2; exit 1; }
jq -e '.status == "CAPTURED" and ((.summary.market_event_count // 0) > 0)' "$RECEIPT" >/dev/null \
  || { echo "stream receipt has no captured market events: $RECEIPT" >&2; exit 1; }
MANIFEST="$LANDING_ROOT/manifests/$DATE/raw-history-requests.json"
mkdir -p "$(dirname "$MANIFEST")"
cd "$ROOT"
"$BASILISP_BIN" run scripts/build_raw_history_request_manifest.lpy -- --stream-receipt "$RECEIPT" --out "$MANIFEST"
"$BASILISP_BIN" run scripts/execute_raw_history_parity.lpy -- --request-manifest "$MANIFEST" --base-url "${THETADATA_BASE_URL:-http://127.0.0.1:25503}" --landing-root "$LANDING_ROOT"
