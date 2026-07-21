#!/usr/bin/env bash
# Capture the first same-session raw ThetaData source-pair diagnostics.
set -euo pipefail

if [[ "$#" -gt 0 ]]; then
  echo "run_raw_thetadata_parity.sh accepts no CLI arguments; use environment overrides" >&2
  exit 2
fi

ROOT="${STEVETRADING_BASILISP_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
TARGET_DATE="${RAW_THETADATA_PARITY_TARGET_DATE:-$(TZ=America/New_York date +%F)}"
LANDING_ROOT="${RAW_THETADATA_PARITY_LANDING_ROOT:-/opt/stevetrading/shared/thetadata-parity-v1}"
BASE_URL="${THETADATA_BASE_URL:-http://127.0.0.1:25503}"
TIMEOUT_S="${RAW_THETADATA_PARITY_TIMEOUT_S:-30}"
OPTION_SYMBOLS="${RAW_THETADATA_PARITY_OPTION_SYMBOLS:-SPY,SPX,SPXW,VIX,VIXW}"
OPEN_INTEREST_SYMBOLS="${RAW_THETADATA_PARITY_OPEN_INTEREST_SYMBOLS:-SPY,SPX,SPXW,VIX,VIXW}"
INDEX_SYMBOLS="${RAW_THETADATA_PARITY_INDEX_SYMBOLS:-SPX,VIX}"
BASILISP_BIN="${BASILISP_BIN:-$ROOT/.venv/bin/basilisp}"

if [[ ! -x "$BASILISP_BIN" ]]; then
  echo "Basilisp runner not executable: $BASILISP_BIN" >&2
  exit 2
fi

cd "$ROOT"
export STEVE_REPO_ROOT="$ROOT"

if ! "$BASILISP_BIN" run scripts/is_trading_day.lpy -- "$TARGET_DATE"; then
  rc=$?
  if [[ "$rc" == "1" ]]; then
    echo "RESULT: SKIPPED - non-trading day $TARGET_DATE"
    exit 0
  fi
  exit "$rc"
fi

"$BASILISP_BIN" run scripts/wait_thetadata_health.lpy -- \
  --url "$BASE_URL/v3/option/list/expirations?symbol=SPY&format=json" \
  --timeout-seconds "${RAW_THETADATA_PARITY_HEALTH_TIMEOUT_S:-180}" \
  --poll-seconds 5

status=0
IFS=',' read -r -a option_symbols <<< "$OPTION_SYMBOLS"
for symbol in "${option_symbols[@]}"; do
  symbol="${symbol//[[:space:]]/}"
  [[ -z "$symbol" ]] && continue
  if ! timeout 180 "$BASILISP_BIN" run scripts/raw_thetadata_parity.lpy -- \
    --class option-nbbo-quote --symbol "$symbol" --base-url "$BASE_URL" \
    --landing-root "$LANDING_ROOT" --timeout-s "$TIMEOUT_S"; then
    status=1
  fi
done

IFS=',' read -r -a open_interest_symbols <<< "$OPEN_INTEREST_SYMBOLS"
for symbol in "${open_interest_symbols[@]}"; do
  symbol="${symbol//[[:space:]]/}"
  [[ -z "$symbol" ]] && continue
  if ! timeout 180 "$BASILISP_BIN" run scripts/raw_thetadata_parity.lpy -- \
    --class option-open-interest --symbol "$symbol" --base-url "$BASE_URL" \
    --landing-root "$LANDING_ROOT" --timeout-s "$TIMEOUT_S"; then
    status=1
  fi
done

IFS=',' read -r -a index_symbols <<< "$INDEX_SYMBOLS"
for symbol in "${index_symbols[@]}"; do
  symbol="${symbol//[[:space:]]/}"
  [[ -z "$symbol" ]] && continue
  if ! timeout 90 "$BASILISP_BIN" run scripts/raw_thetadata_parity.lpy -- \
    --class index-price --symbol "$symbol" --base-url "$BASE_URL" \
    --landing-root "$LANDING_ROOT" --timeout-s "$TIMEOUT_S"; then
    status=1
  fi
done

exit "$status"
