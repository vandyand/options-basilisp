#!/usr/bin/env bash
# Resumable local pull from Hetzner's immutable raw-data landing area to D:.
set -euo pipefail

REMOTE="${THETADATA_PARITY_REMOTE:-bot@167.233.141.61}"
REMOTE_ROOT="${THETADATA_PARITY_REMOTE_ROOT:-/opt/stevetrading/shared/thetadata-parity-v1}"
LOCAL_ROOT="${THETADATA_PARITY_LOCAL_ROOT:-/mnt/d/stevetrading/thetadata-parity-v1}"
ROOT="${STEVETRADING_BASILISP_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
BASILISP_BIN="${BASILISP_BIN:-$ROOT/.venv/bin/basilisp}"
DATE="${THETADATA_PARITY_TARGET_DATE:-$(TZ=America/New_York date +%F)}"
ATTEMPTS="${THETADATA_PARITY_PULL_ATTEMPTS:-15}"
RETRY_SECONDS="${THETADATA_PARITY_PULL_RETRY_SECONDS:-60}"
VERIFY_OUT="$LOCAL_ROOT/verification/$DATE/raw-history-evidence.json"

mkdir -p "$LOCAL_ROOT"
# D: is a Windows-mounted filesystem under WSL, so POSIX owner/group metadata
# cannot be preserved. Content and mtimes are the immutable evidence contract.
for attempt in $(seq 1 "$ATTEMPTS"); do
  rsync -rtvz --omit-dir-times --no-perms --no-owner --no-group --partial --append-verify \
    "$REMOTE:$REMOTE_ROOT/" "$LOCAL_ROOT/"
  if "$BASILISP_BIN" run "$ROOT/scripts/verify_raw_parity_evidence.lpy" -- \
      --landing-root "$LOCAL_ROOT" --target-date "$DATE" --out "$VERIFY_OUT"; then
    echo "raw parity evidence ready for $DATE after pull attempt $attempt/$ATTEMPTS"
    exit 0
  fi
  if [[ "$attempt" -lt "$ATTEMPTS" ]]; then
    echo "raw parity evidence pending for $DATE; retrying in ${RETRY_SECONDS}s ($attempt/$ATTEMPTS)" >&2
    sleep "$RETRY_SECONDS"
  fi
done

echo "raw parity evidence incomplete after $ATTEMPTS pull attempts: $VERIFY_OUT" >&2
exit 1
