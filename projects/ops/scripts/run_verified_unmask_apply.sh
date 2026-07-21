#!/usr/bin/env bash
# Execute the final verified neutralization unmask apply step.
#
# This intentionally does not collect evidence. It only applies candidates from
# an already verified market-evidence bundle after the non-applying validation
# artifact exists and the status JSON marks the bundle apply-safe.
set -euo pipefail

ROOT="${STEVETRADING_BASILISP_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
if [[ -d /opt/stevetrading/shared ]]; then
  DEFAULT_RUNTIME_ROOT=/opt/stevetrading/shared
else
  DEFAULT_RUNTIME_ROOT="$ROOT"
fi

TARGET_DATE="${MARKET_EVIDENCE_DATE:-$(TZ=America/New_York date +%F)}"
ANALYSIS_DIR="${ANALYSIS_DIR:-$DEFAULT_RUNTIME_ROOT/live_runtime/analysis}"
REF_ROOT="${STEVE_REF_ROOT:-$DEFAULT_RUNTIME_ROOT/Data-Preprocessor}"
BASILISP_BIN="${BASILISP_BIN:-$REF_ROOT/.venv/bin/basilisp}"
STAMP="${TARGET_DATE//-/}"
MANIFEST_JSON="${MARKET_EVIDENCE_MANIFEST_JSON:-$ANALYSIS_DIR/market_evidence_manifest_$STAMP.json}"
STATUS_JSON="${MARKET_EVIDENCE_STATUS_JSON:-$ANALYSIS_DIR/market_evidence_status_$STAMP.json}"
VALIDATION_JSON="${MARKET_EVIDENCE_VALIDATION_JSON:-$ANALYSIS_DIR/neutralization_verified_apply_validation_$STAMP.json}"
APPLY_JSON="${MARKET_EVIDENCE_APPLY_JSON:-$ANALYSIS_DIR/neutralization_unmask_apply_$STAMP.json}"
APPLY_VERIFY_JSON="${MARKET_EVIDENCE_APPLY_VERIFY_JSON:-$ANALYSIS_DIR/neutralization_unmask_apply_verification_$STAMP.json}"
LOG_DIR="${MARKET_EVIDENCE_LOG_DIR:-/var/log/stevetrading}"
LOG_FILE="${MARKET_EVIDENCE_APPLY_LOG_FILE:-$LOG_DIR/market-evidence-apply.log}"

usage() {
  cat <<'EOF'
Usage: projects/ops/scripts/run_verified_unmask_apply.sh [--target-date YYYY-MM-DD]

Applies only after these same-day artifacts are present and internally green:
  - market_evidence_manifest_YYYYMMDD.json
  - market_evidence_status_YYYYMMDD.json
  - neutralization_verified_apply_validation_YYYYMMDD.json

Environment overrides:
  STEVETRADING_BASILISP_ROOT, STEVE_REF_ROOT, BASILISP_BIN, ANALYSIS_DIR,
  MARKET_EVIDENCE_DATE, MARKET_EVIDENCE_MANIFEST_JSON,
  MARKET_EVIDENCE_STATUS_JSON, MARKET_EVIDENCE_VALIDATION_JSON,
  MARKET_EVIDENCE_APPLY_JSON, MARKET_EVIDENCE_APPLY_VERIFY_JSON,
  MARKET_EVIDENCE_LOG_DIR, MARKET_EVIDENCE_APPLY_LOG_FILE
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target-date)
      if [[ $# -lt 2 || "$2" == --* ]]; then
        echo "missing value for --target-date" >&2
        usage >&2
        exit 2
      fi
      TARGET_DATE="$2"
      STAMP="${TARGET_DATE//-/}"
      MANIFEST_JSON="${MARKET_EVIDENCE_MANIFEST_JSON:-$ANALYSIS_DIR/market_evidence_manifest_$STAMP.json}"
      STATUS_JSON="${MARKET_EVIDENCE_STATUS_JSON:-$ANALYSIS_DIR/market_evidence_status_$STAMP.json}"
      VALIDATION_JSON="${MARKET_EVIDENCE_VALIDATION_JSON:-$ANALYSIS_DIR/neutralization_verified_apply_validation_$STAMP.json}"
      APPLY_JSON="${MARKET_EVIDENCE_APPLY_JSON:-$ANALYSIS_DIR/neutralization_unmask_apply_$STAMP.json}"
      APPLY_VERIFY_JSON="${MARKET_EVIDENCE_APPLY_VERIFY_JSON:-$ANALYSIS_DIR/neutralization_unmask_apply_verification_$STAMP.json}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ ! "$TARGET_DATE" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
  echo "target date must be YYYY-MM-DD: $TARGET_DATE" >&2
  exit 2
fi
if ! NORMALIZED_TARGET_DATE="$(date -d "$TARGET_DATE" +%F 2>/dev/null)" || [[ "$NORMALIZED_TARGET_DATE" != "$TARGET_DATE" ]]; then
  echo "target date is not a valid calendar date: $TARGET_DATE" >&2
  exit 2
fi
if [[ ! -x "$BASILISP_BIN" ]]; then
  echo "RESULT: FAILED - Basilisp runner not executable: $BASILISP_BIN" >&2
  exit 2
fi

mkdir -p "$LOG_DIR"
{
  echo
  echo "================================================================"
  echo "  Verified unmask apply - $(date)"
  echo "================================================================"
  echo "target_date=$TARGET_DATE root=$ROOT analysis_dir=$ANALYSIS_DIR"

  cd "$ROOT"
  export STEVE_REPO_ROOT="$ROOT"
  "$BASILISP_BIN" run scripts/apply_verified_neutralization_unmask.lpy -- \
    --target-date "$TARGET_DATE" \
    --analysis-dir "$ANALYSIS_DIR" \
    --manifest-json "$MANIFEST_JSON" \
    --status-json "$STATUS_JSON" \
    --ref-root "$REF_ROOT" \
    --require-validation-json "$VALIDATION_JSON" \
    --apply
  "$BASILISP_BIN" run scripts/verify_neutralization_unmask_apply.lpy -- \
    --apply-json "$APPLY_JSON" \
    --out-json "$APPLY_VERIFY_JSON"
  echo "RESULT: SUCCESS - $(date)"
} >> "$LOG_FILE" 2>&1
