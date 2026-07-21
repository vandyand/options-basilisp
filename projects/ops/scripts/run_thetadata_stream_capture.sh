#!/usr/bin/env bash
# Build a frozen contract plan, then retain raw ThetaData stream messages.
set -euo pipefail

ROOT="${STEVETRADING_BASILISP_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
BASILISP_BIN="${BASILISP_BIN:-$ROOT/.venv/bin/basilisp}"
LANDING_ROOT="${THETADATA_STREAM_LANDING_ROOT:-/opt/stevetrading/shared/thetadata-parity-v1}"
BASE_URL="${THETADATA_BASE_URL:-http://127.0.0.1:25503}"
TARGET_DATE="${THETADATA_STREAM_TARGET_DATE:-$(TZ=America/New_York date +%F)}"

cd "$ROOT"
export STEVE_REPO_ROOT="$ROOT"
"$BASILISP_BIN" run scripts/is_trading_day.lpy -- "$TARGET_DATE"
"$BASILISP_BIN" run scripts/wait_thetadata_health.lpy -- \
  --url "$BASE_URL/v3/option/list/expirations?symbol=SPY&format=json" \
  --timeout-seconds "${THETADATA_STREAM_HEALTH_TIMEOUT_S:-180}" --poll-seconds 5
"$BASILISP_BIN" run scripts/build_thetadata_stream_plan.lpy -- \
  --base-url "$BASE_URL" --landing-root "$LANDING_ROOT" --target-date "$TARGET_DATE" \
  --strike-range "${THETADATA_STREAM_STRIKE_RANGE:-50}"
"$BASILISP_BIN" run scripts/record_thetadata_stream.lpy -- \
  --plan-file "$LANDING_ROOT/plans/$TARGET_DATE/thetadata-stream-plan.json" \
  --landing-root "$LANDING_ROOT" --duration-s "${THETADATA_STREAM_DURATION_S:-900}" \
  --receive-timeout-s "${THETADATA_STREAM_RECEIVE_TIMEOUT_S:-10}" \
  --max-reconnects "${THETADATA_STREAM_MAX_RECONNECTS:-5}"
