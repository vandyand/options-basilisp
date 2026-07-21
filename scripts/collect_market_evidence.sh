#!/usr/bin/env bash
# One-shot market-open evidence workflow.
#
# This intentionally threads one target session through every artifact. The
# failure mode this prevents is a green readiness report assembled from mixed
# days: fresh analysis JSON over stale feature captures, or payload validation
# against historical ThetaData examples.

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/collect_market_evidence.sh [--target-date YYYY-MM-DD] [--dry-run] [--preflight]

Runs, in order:
  1. capture_v2_sidecar_check.lpy explicit raw-replay capture gate
  2. thetadata_capability_probe.lpy --save-payloads
  3. verify_thetadata_payload_examples.lpy against payload_examples/YYYYMMDD
  4. collect_option_surface_sidecar.lpy non-SPY option-surface evidence
  5. option_surface_sidecar_check.lpy dedicated sidecar evidence gate
  6. live_feature_parity_baseline.lpy for the compact target date when capture is usable
  7. live_feature_prediction_delta.lpy diagnostic sensitivity audit when possible
  8. live_feature_parity_gate.lpy diagnostic parity gate
  9. live_feature_model_usage_audit.lpy against that baseline CSV
  10. neutralization_audit.lpy against the target baseline and model-usage CSV
  11. neutralized_feature_unlock_plan.lpy read-only unlock requirements plan
  12. blocked_feature_provenance_audit.lpy read-only audit for formula-blocked features
  13. legacy_greek_formula_search.lpy read-only search for formula provenance
  14. greek_feature_reconstruction_audit.lpy conservative audit for formula-blocked Greek features
  15. raw_feature_unlock_audit.lpy primary diagnostic unmask-candidate audit when possible
  16. supplemental raw_feature_unlock_audit.lpy probes for bounded source-family coverage
  17. v3_grid_unlock_audit.lpy diagnostic V3-grid unmask audit when possible
  18. greek_reconstruction_promotion_gate.lpy strict promotion gate for guarded Greek formulas
  19. build_thetadata_historical_feature_cohort.lpy recent-date historical tensor
      (or prepare_historical_feature_cohort.lpy when HISTORICAL_FEATURE_MODE=archive)
  20. matched_feature_parity_report.lpy Steve-requested live-vs-historical table
  21. summarize_matched_feature_parity.lpy concentrated blocker summary
  22. market_evidence_readiness.lpy with explicit target artifact paths
  23. neutralized_feature_evidence_report.lpy per-feature current blocker roll-up
  24. apply_neutralization_candidates.lpy dry-run unmask plan when possible
  25. market_evidence_manifest.lpy checksum manifest for the run bundle
  26. market_evidence_manifest.lpy --verify against the generated manifest
  27. market_evidence_status.lpy concise operator summary
  28. apply_verified_neutralization_unmask.lpy non-applying verified-apply validation
  29. market_evidence_status.lpy final summary including verified-apply validation

Environment overrides:
  STEVE_REPO_ROOT, BASILISP_BIN, ANALYSIS_DIR, CAPTURE_DIR,
  PAYLOAD_DIR, THETADATA_BASE_URL, THETADATA_TIMEOUT_S,
  THETADATA_OPTION_SYMBOLS, THETADATA_INDEX_SYMBOLS, THETADATA_STOCK_SYMBOLS,
  THETADATA_EXPIRATION, MIN_CAPTURE_ROWS, HISTORICAL_FEATURE_NPZ,
  OPTION_SURFACE_SIDECAR_SYMBOLS, OPTION_SURFACE_SIDECAR_MAX_CONTRACTS,
  OPTION_SURFACE_SIDECAR_MAX_ROWS, OPTION_SURFACE_SIDECAR_MAX_AUDIT_CONTRACTS,
  MARKET_EVIDENCE_ALLOW_MISSING_OPTION_SURFACES,
  RAW_FEATURE_UNLOCK_MAX_ROWS, RAW_FEATURE_UNLOCK_SUPPLEMENTAL_PRESETS,
  V3_GRID_UNLOCK_MAX_PREDICTION_ROWS,
  HISTORICAL_FEATURE_MODE, HISTORICAL_FEATURE_START_TIME,
  HISTORICAL_FEATURE_STOCK_START_TIME,
  HISTORICAL_FEATURE_END_TIME, HISTORICAL_FEATURE_CHAIN_HORIZON_DAYS,
  HISTORICAL_FEATURE_SURFACE_HORIZON_DAYS, HISTORICAL_FEATURE_SURFACE_SYMBOLS,
  HISTORICAL_FEATURE_STRIKE_RANGE, HISTORICAL_FEATURE_SPY_STRIKE_RANGE, HISTORICAL_FEATURE_JOBS,
  HISTORICAL_FEATURE_IMPLEMENTATION,
  HISTORICAL_FEATURE_COHORT_WINDOW_MINUTES,
  HISTORICAL_FEATURE_GRID_CONTRACTS_ONLY,
  HISTORICAL_FEATURE_REQUEST_TIMEOUT, HISTORICAL_FEATURE_ALLOW_MISSING_SURFACES,
  HISTORICAL_FEATURE_THETADATA_CACHE_DIR,
  HISTORICAL_FEATURE_SOURCE_NPZ, HISTORICAL_FEATURE_DATE_MAP,
  ALLOW_NON_TODAY_TARGET=1, MARKET_EVIDENCE_NOW_ET

Modes:
  --dry-run    Print the exact command plan without local checks or writes.
  --preflight  Non-destructively check local runners/paths and print the plan.
EOF
}

REPO="${STEVE_REPO_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
DEFAULT_REF="$HOME/contracting/upwork/steven-tran/SteveTrading/ref/Data-Preprocessor"
if [[ -z "${STEVE_REF_ROOT:-}" && -d /opt/stevetrading/shared/Data-Preprocessor ]]; then
  DEFAULT_REF="/opt/stevetrading/shared/Data-Preprocessor"
fi
REF="${STEVE_REF_ROOT:-$DEFAULT_REF}"
resolve_runner() {
  local env_value="$1"
  local repo_candidate="$2"
  local ref_candidate="$3"
  local path_name="$4"
  if [[ -n "$env_value" ]]; then
    printf '%s\n' "$env_value"
  elif [[ -x "$repo_candidate" ]]; then
    printf '%s\n' "$repo_candidate"
  elif [[ -x "$ref_candidate" ]]; then
    printf '%s\n' "$ref_candidate"
  elif command -v "$path_name" >/dev/null 2>&1; then
    command -v "$path_name"
  else
    printf '%s\n' "$repo_candidate"
  fi
}
BASILISP="$(resolve_runner "${BASILISP_BIN:-}" "$REPO/.venv/bin/basilisp" "$REF/.venv/bin/basilisp" basilisp)"
if [[ -d /opt/stevetrading/shared ]]; then
  DEFAULT_RUNTIME_ROOT="/opt/stevetrading/shared"
  DEFAULT_PAYLOAD_DIR="$DEFAULT_RUNTIME_ROOT/payload_examples"
else
  DEFAULT_RUNTIME_ROOT="$REPO"
  DEFAULT_PAYLOAD_DIR="$REPO/resources/thetadata/payload_examples"
fi
ANALYSIS_DIR="${ANALYSIS_DIR:-$DEFAULT_RUNTIME_ROOT/live_runtime/analysis}"
CAPTURE_DIR="${CAPTURE_DIR:-$DEFAULT_RUNTIME_ROOT/live_runtime/feature-capture}"
PAYLOAD_DIR="${PAYLOAD_DIR:-$DEFAULT_PAYLOAD_DIR}"
THETADATA_BASE_URL="${THETADATA_BASE_URL:-http://127.0.0.1:25503}"
THETADATA_TIMEOUT_S="${THETADATA_TIMEOUT_S:-5.0}"
MIN_CAPTURE_ROWS="${MIN_CAPTURE_ROWS:-60}"
CAPTURE_SIDECAR_ROW_LIMIT="${MARKET_EVIDENCE_CAPTURE_SIDECAR_ROW_LIMIT:-$((MIN_CAPTURE_ROWS * 2))}"
ALLOW_MISSING_OPTION_SURFACES="${MARKET_EVIDENCE_ALLOW_MISSING_OPTION_SURFACES:-1}"
RAW_FEATURE_UNLOCK_MAX_ROWS="${RAW_FEATURE_UNLOCK_MAX_ROWS:-40}"
RAW_FEATURE_UNLOCK_MAX_OPTION_CONTRACTS="${RAW_FEATURE_UNLOCK_MAX_OPTION_CONTRACTS:-40}"
RAW_FEATURE_UNLOCK_MAX_SURFACE_CONTRACTS="${RAW_FEATURE_UNLOCK_MAX_SURFACE_CONTRACTS:-40}"
RAW_FEATURE_UNLOCK_SUPPLEMENTAL_PRESETS="${RAW_FEATURE_UNLOCK_SUPPLEMENTAL_PRESETS:-base-bars30,option-chain,spy-grid60,surface-greek-grid60-full}"
V3_GRID_UNLOCK_MAX_PREDICTION_ROWS="${V3_GRID_UNLOCK_MAX_PREDICTION_ROWS:-0}"
REPLAY_CAPTURED_FEATURE_MAX_ROWS="${REPLAY_CAPTURED_FEATURE_MAX_ROWS:-30}"
ET_TODAY="$(TZ=America/New_York date +%F)"
TARGET_DATE="$ET_TODAY"
DRY_RUN=0
PREFLIGHT=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target-date)
      if [[ $# -lt 2 || "$2" == --* ]]; then
        echo "missing value for --target-date" >&2
        usage >&2
        exit 2
      fi
      TARGET_DATE="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --preflight)
      PREFLIGHT=1
      shift
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

if [[ "$PREFLIGHT" == "1" ]]; then
  DRY_RUN=1
fi

if [[ ! "$TARGET_DATE" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
  echo "target date must be YYYY-MM-DD: $TARGET_DATE" >&2
  exit 2
fi
if ! NORMALIZED_TARGET_DATE="$(date -d "$TARGET_DATE" +%F 2>/dev/null)" || [[ "$NORMALIZED_TARGET_DATE" != "$TARGET_DATE" ]]; then
  echo "target date is not a valid calendar date: $TARGET_DATE" >&2
  exit 2
fi

if [[ "$DRY_RUN" != "1" && "$TARGET_DATE" != "$ET_TODAY" && "${ALLOW_NON_TODAY_TARGET:-}" != "1" ]]; then
  echo "refusing non-dry-run target date $TARGET_DATE; live artifacts are timestamped today ($ET_TODAY). Set ALLOW_NON_TODAY_TARGET=1 only for controlled debugging." >&2
  exit 2
fi

STAMP="${TARGET_DATE//-/}"
default_historical_feature_end_time() {
  local now_et="${MARKET_EVIDENCE_NOW_ET:-$(TZ=America/New_York date '+%F %T')}"
  now_et="${now_et/T/ }"
  now_et="${now_et%%.*}"
  local now_date="${now_et%% *}"
  local open_epoch end_epoch close_epoch

  if [[ "$now_date" != "$TARGET_DATE" ]]; then
    printf '%s\n' "15:59:00"
    return 0
  fi

  open_epoch="$(TZ=America/New_York date -d "$TARGET_DATE 09:30:00" +%s)"
  close_epoch="$(TZ=America/New_York date -d "$TARGET_DATE 15:59:00" +%s)"
  end_epoch="$(TZ=America/New_York date -d "$now_et" +%s)"
  end_epoch=$((end_epoch - 300))

  if (( end_epoch < open_epoch )); then
    printf '%s\n' "09:30:00"
  elif (( end_epoch > close_epoch )); then
    printf '%s\n' "15:59:00"
  else
    TZ=America/New_York date -d "@$end_epoch" '+%H:%M:00'
  fi
}

CAPTURE_NPZ="$CAPTURE_DIR/live_features_$STAMP.npz"
TARGET_PAYLOAD_DIR="$PAYLOAD_DIR/$STAMP"
BASELINE_CSV="$ANALYSIS_DIR/live_feature_parity_baseline_$STAMP.csv"
BASELINE_JSON="$ANALYSIS_DIR/live_feature_parity_baseline_$STAMP.json"
PREDICTION_DELTA_CSV="$ANALYSIS_DIR/live_feature_prediction_delta_aggregate_$STAMP.csv"
PARITY_GATE_JSON="$ANALYSIS_DIR/live_feature_parity_gate_$STAMP.json"
MODEL_USAGE_CSV="$ANALYSIS_DIR/live_feature_model_usage_$STAMP.csv"
MODEL_USAGE_JSON="$ANALYSIS_DIR/live_feature_model_usage_$STAMP.json"
PROBE_JSON="$ANALYSIS_DIR/thetadata_capability_probe_$STAMP.json"
PAYLOAD_VERIFICATION_JSON="$ANALYSIS_DIR/thetadata_payload_verification_$STAMP.json"
NEUTRALIZATION_JSON="$ANALYSIS_DIR/neutralization_audit_$STAMP.json"
UNLOCK_PLAN_JSON="$ANALYSIS_DIR/neutralized_feature_unlock_plan_$STAMP.json"
BLOCKED_PROVENANCE_JSON="$ANALYSIS_DIR/blocked_feature_provenance_audit_$STAMP.json"
LEGACY_GREEK_SEARCH_JSON="$ANALYSIS_DIR/legacy_greek_formula_search_$STAMP.json"
GREEK_RECONSTRUCTION_JSON="$ANALYSIS_DIR/greek_feature_reconstruction_audit_$STAMP.json"
RAW_UNLOCK_JSON="$ANALYSIS_DIR/raw_feature_unlock_audit_$STAMP.json"
RAW_UNLOCK_CANDIDATES_JSON="$ANALYSIS_DIR/raw_feature_unlock_candidates_$STAMP.json"
OPTION_SURFACE_SIDECAR_SYMBOLS="${OPTION_SURFACE_SIDECAR_SYMBOLS:-SPXW,VIXW,SPX,VIX}"
OPTION_SURFACE_SIDECAR_MAX_CONTRACTS="${OPTION_SURFACE_SIDECAR_MAX_CONTRACTS:-300}"
OPTION_SURFACE_SIDECAR_MAX_ROWS="${OPTION_SURFACE_SIDECAR_MAX_ROWS:-}"
OPTION_SURFACE_SIDECAR_MAX_AUDIT_CONTRACTS="${OPTION_SURFACE_SIDECAR_MAX_AUDIT_CONTRACTS:-80}"
OPTION_SURFACE_SIDECAR_NPZ="$ANALYSIS_DIR/option_surface_sidecar_$STAMP.npz"
OPTION_SURFACE_SIDECAR_JSON="$ANALYSIS_DIR/option_surface_sidecar_$STAMP.json"
OPTION_SURFACE_SIDECAR_CHECK_JSON="$ANALYSIS_DIR/option_surface_sidecar_check_$STAMP.json"
V3_UNLOCK_JSON="$ANALYSIS_DIR/v3_grid_unlock_audit_$STAMP.json"
GREEK_PROMOTION_JSON="$ANALYSIS_DIR/greek_reconstruction_promotion_gate_$STAMP.json"
HISTORICAL_FEATURE_NPZ="${HISTORICAL_FEATURE_NPZ:-$ANALYSIS_DIR/historical_features_$STAMP.npz}"
HISTORICAL_FEATURE_MODE="${HISTORICAL_FEATURE_MODE:-thetadata}"
HISTORICAL_FEATURE_START_TIME="${HISTORICAL_FEATURE_START_TIME:-09:30:00}"
HISTORICAL_FEATURE_STOCK_START_TIME="${HISTORICAL_FEATURE_STOCK_START_TIME:-04:00:00}"
HISTORICAL_FEATURE_END_TIME="${HISTORICAL_FEATURE_END_TIME:-$(default_historical_feature_end_time)}"
# Match launch_steve_six.lpy's default STEVE_CHAIN_HORIZON_DAYS=1
# (today + tomorrow). Broad live snapshots are then narrowed by the bridge's
# +/-12% moneyness filter, so historical fetches need a wide SPY strike range.
HISTORICAL_FEATURE_CHAIN_HORIZON_DAYS="${HISTORICAL_FEATURE_CHAIN_HORIZON_DAYS:-1}"
HISTORICAL_FEATURE_SURFACE_HORIZON_DAYS="${HISTORICAL_FEATURE_SURFACE_HORIZON_DAYS:-45}"
HISTORICAL_FEATURE_SURFACE_SYMBOLS="${HISTORICAL_FEATURE_SURFACE_SYMBOLS:-}"
HISTORICAL_FEATURE_STRIKE_RANGE="${HISTORICAL_FEATURE_STRIKE_RANGE:-1}"
HISTORICAL_FEATURE_SPY_STRIKE_RANGE="${HISTORICAL_FEATURE_SPY_STRIKE_RANGE:-100}"
HISTORICAL_FEATURE_JOBS="${HISTORICAL_FEATURE_JOBS:-8}"
HISTORICAL_FEATURE_IMPLEMENTATION="${HISTORICAL_FEATURE_IMPLEMENTATION:-native}"
HISTORICAL_FEATURE_STOCK_VENUE="${HISTORICAL_FEATURE_STOCK_VENUE:-${THETADATA_STOCK_VENUE:-nqb}}"
HISTORICAL_FEATURE_OPTION_RECONSTRUCTION="${HISTORICAL_FEATURE_OPTION_RECONSTRUCTION:-at-time-quote}"
HISTORICAL_FEATURE_SKIP_OPTION_ENRICHMENT="${HISTORICAL_FEATURE_SKIP_OPTION_ENRICHMENT:-1}"
HISTORICAL_FEATURE_COHORT_WINDOW_MINUTES="${HISTORICAL_FEATURE_COHORT_WINDOW_MINUTES:-75}"
HISTORICAL_FEATURE_GRID_CONTRACTS_ONLY="${HISTORICAL_FEATURE_GRID_CONTRACTS_ONLY:-1}"
HISTORICAL_FEATURE_REQUEST_TIMEOUT="${HISTORICAL_FEATURE_REQUEST_TIMEOUT:-15}"
HISTORICAL_FEATURE_ALLOW_MISSING_SURFACES="${HISTORICAL_FEATURE_ALLOW_MISSING_SURFACES:-0}"
HISTORICAL_FEATURE_THETADATA_CACHE_DIR="${HISTORICAL_FEATURE_THETADATA_CACHE_DIR:-$ANALYSIS_DIR/thetadata-cache}"
HISTORICAL_FEATURE_SOURCE_NPZ="${HISTORICAL_FEATURE_SOURCE_NPZ:-$REF/cache/full_features_5yr_v3.npz}"
HISTORICAL_FEATURE_DATE_MAP="${HISTORICAL_FEATURE_DATE_MAP:-$REF/cache/date_map_5yr_v3.json}"
HISTORICAL_COHORT_JSON="$ANALYSIS_DIR/historical_feature_cohort_$STAMP.json"
SOURCE_PARITY_JSON="$ANALYSIS_DIR/captured_source_parity_$STAMP.json"
VERIFIED_CORPUS_NPZ="$ANALYSIS_DIR/verified_feature_corpus_$STAMP.npz"
VERIFIED_CORPUS_JSON="$ANALYSIS_DIR/verified_feature_corpus_$STAMP.json"
SOURCE_PARITY_BAR_TOLERANCE="${SOURCE_PARITY_BAR_TOLERANCE:-0}"
SOURCE_PARITY_QUOTE_TOLERANCE="${SOURCE_PARITY_QUOTE_TOLERANCE:-0}"
GRID_INPUT_PARITY_JSON="$ANALYSIS_DIR/grid_feature_input_parity_$STAMP.json"
GRID_INPUT_PARITY_MD="$ANALYSIS_DIR/grid_feature_input_parity_$STAMP.md"
MATCHED_PARITY_JSON="$ANALYSIS_DIR/matched_feature_parity_$STAMP.json"
NEUTRALIZED_EVIDENCE_JSON="$ANALYSIS_DIR/neutralized_feature_evidence_report_$STAMP.json"
UNMASK_DRY_RUN_JSON="$ANALYSIS_DIR/neutralization_unmask_dry_run_$STAMP.json"
CAPTURE_CHECK_JSON="$ANALYSIS_DIR/capture_v2_sidecar_check_$STAMP.json"
REPLAYED_FEATURE_NPZ="$ANALYSIS_DIR/replayed_feature_cohort_$STAMP.npz"
REPLAYED_COHORT_JSON="$ANALYSIS_DIR/replayed_feature_cohort_$STAMP.json"
READINESS_JSON="$ANALYSIS_DIR/market_evidence_readiness_$STAMP.json"
MANIFEST_JSON="$ANALYSIS_DIR/market_evidence_manifest_$STAMP.json"
STATUS_JSON="$ANALYSIS_DIR/market_evidence_status_$STAMP.json"
STATUS_MD="$ANALYSIS_DIR/market_evidence_status_$STAMP.md"
VERIFIED_APPLY_VALIDATION_JSON="$ANALYSIS_DIR/neutralization_verified_apply_validation_$STAMP.json"
REQUIRED_WORKFLOW_SCRIPTS=(
  "scripts/thetadata_capability_probe.lpy"
  "scripts/verify_thetadata_payload_examples.lpy"
  "scripts/live_feature_parity_baseline.lpy"
  "scripts/live_feature_prediction_delta.lpy"
  "scripts/live_feature_parity_gate.lpy"
  "scripts/live_feature_model_usage_audit.lpy"
  "scripts/neutralization_audit.lpy"
  "scripts/neutralized_feature_unlock_plan.lpy"
  "scripts/blocked_feature_provenance_audit.lpy"
  "scripts/legacy_greek_formula_search.lpy"
  "scripts/greek_feature_reconstruction_audit.lpy"
  "scripts/collect_option_surface_sidecar.lpy"
  "scripts/option_surface_sidecar_check.lpy"
  "scripts/raw_feature_unlock_audit.lpy"
  "scripts/v3_grid_unlock_audit.lpy"
  "scripts/apply_neutralization_candidates.lpy"
  "scripts/apply_verified_neutralization_unmask.lpy"
  "scripts/verify_neutralization_unmask_apply.lpy"
  "scripts/capture_v2_runtime_preflight.lpy"
  "scripts/capture_v2_sidecar_check.lpy"
  "scripts/replay_captured_feature_cohort.lpy"
  "scripts/prepare_historical_feature_cohort.lpy"
  "scripts/build_thetadata_historical_feature_cohort.lpy"
  "scripts/grid_feature_input_parity.lpy"
  "scripts/greek_reconstruction_promotion_gate.lpy"
  "scripts/matched_feature_parity_report.lpy"
  "scripts/summarize_matched_feature_parity.lpy"
  "scripts/market_evidence_readiness.lpy"
  "scripts/market_evidence_manifest.lpy"
  "scripts/market_evidence_status.lpy"
  "scripts/assert_market_evidence_status.lpy"
)

cd "$REPO"
export STEVE_REPO_ROOT="$REPO"

PREFLIGHT_RC=0

preflight_ok() {
  echo "OK: $*"
}

preflight_warn() {
  echo "WARN: $*" >&2
}

preflight_fail() {
  echo "FAIL: $*" >&2
  PREFLIGHT_RC=1
}

preflight_check_corrected_bundles() {
  local first_account="chestnut"
  local first_bundle="$REF/pipeline_data/live_model_${first_account}_multihead_corrected"
  local first_features="$first_bundle/feature_names.json"
  local first_neutralized="$first_bundle/neutralize_features.json"
  [[ -d "$REF" ]] && preflight_ok "ref root exists: $REF" || preflight_fail "ref root missing: $REF"
  [[ -f "$first_features" ]] && preflight_ok "corrected feature names exist: $first_features" || preflight_fail "corrected feature names missing: $first_features"
  [[ -f "$first_neutralized" ]] && preflight_ok "corrected neutralization exists: $first_neutralized" || preflight_fail "corrected neutralization missing: $first_neutralized"
  for account in lynx moose; do
    local bundle="$REF/pipeline_data/live_model_${account}_multihead_corrected"
    local features="$bundle/feature_names.json"
    local neutralized="$bundle/neutralize_features.json"
    [[ -f "$features" ]] && preflight_ok "corrected feature names exist: $features" || preflight_fail "corrected feature names missing: $features"
    [[ -f "$neutralized" ]] && preflight_ok "corrected neutralization exists: $neutralized" || preflight_fail "corrected neutralization missing: $neutralized"
    if [[ -f "$first_features" && -f "$features" ]]; then
      cmp -s "$first_features" "$features" && preflight_ok "feature names aligned: $first_account/$account" || preflight_fail "feature names drift: $first_features != $features"
    fi
    if [[ -f "$first_neutralized" && -f "$neutralized" ]]; then
      cmp -s "$first_neutralized" "$neutralized" && preflight_ok "neutralization aligned: $first_account/$account" || preflight_fail "neutralization drift: $first_neutralized != $neutralized"
    fi
  done
}

run() {
  printf '+'
  printf ' %q' "$@"
  printf '\n'
  if [[ "$DRY_RUN" != "1" ]]; then
    "$@"
  fi
}

run_allow_fail() {
  set +e
  run "$@"
  local rc=$?
  set -e
  if [[ "$rc" != "0" ]]; then
    echo "WARN: command exited $rc but workflow will continue to final readiness: $*" >&2
  fi
  return "$rc"
}

run_raw_unlock_probe() {
  local label="$1"
  shift
  run_allow_fail "$BASILISP" run scripts/raw_feature_unlock_audit.lpy -- \
    --target-date "$TARGET_DATE" \
    --ref-root "$REF" \
    --capture "$CAPTURE_NPZ" \
    --baseline-json "$BASELINE_JSON" \
    --usage-json "$MODEL_USAGE_JSON" \
    --out-dir "$ANALYSIS_DIR" \
    --label "$label" \
    "$@" || true
}

run_supplemental_raw_unlock_preset() {
  local preset="$1"
  case "$preset" in
    ""|none|off|disabled)
      ;;
    base-bars30)
      run_raw_unlock_probe "$preset" \
        --include-sources base \
        --skip-option-formulas \
        --skip-greek-reconstruction \
        --max-rows 30
      ;;
    option-chain)
      run_raw_unlock_probe "$preset" \
        --include-sources option-chain \
        --skip-greek-reconstruction \
        --max-option-contracts 30 \
        --max-rows 30
      ;;
    spy-grid60)
      run_raw_unlock_probe "$preset" \
        --include-sources spy-grid \
        --skip-option-formulas \
        --skip-greek-reconstruction \
        --max-rows 60
      ;;
    surface-greek-grid60-full)
      run_raw_unlock_probe "$preset" \
        --include-sources option-surface,greek-grid \
        --option-surface-prefixes SPY,SPX,SPXW,VIX,VIXW \
        --max-option-contracts 30 \
        --max-surface-contracts 30 \
        --max-rows 60
      ;;
    *)
      echo "WARN: unknown RAW_FEATURE_UNLOCK_SUPPLEMENTAL_PRESETS entry ignored: $preset" >&2
      ;;
  esac
}

run_supplemental_raw_unlock_probes() {
  local preset
  local old_ifs="$IFS"
  IFS=','
  for preset in $RAW_FEATURE_UNLOCK_SUPPLEMENTAL_PRESETS; do
    IFS="$old_ifs"
    preset="${preset#"${preset%%[![:space:]]*}"}"
    preset="${preset%"${preset##*[![:space:]]}"}"
    run_supplemental_raw_unlock_preset "$preset"
    IFS=','
  done
  IFS="$old_ifs"
}

assert_status_json_ok() {
  if [[ ! -s "$STATUS_JSON" ]]; then
    echo "ERROR: status command exited successfully but did not write status JSON: $STATUS_JSON" >&2
    return 1
  fi
  "$BASILISP" run scripts/assert_market_evidence_status.lpy -- \
    --status-json "$STATUS_JSON"
}

assert_status_json_unmask_apply_ready() {
  assert_status_json_ok || return $?
  "$BASILISP" run scripts/assert_market_evidence_status.lpy -- \
    --status-json "$STATUS_JSON" \
    --require-unmask-apply
}

if [[ "$PREFLIGHT" == "1" ]]; then
  echo "Market evidence preflight"
  echo "target_date=$TARGET_DATE"
  echo "target_stamp=$STAMP"
  echo "repo=$REPO"
  echo "ref=$REF"
  echo "analysis_dir=$ANALYSIS_DIR"
  echo "capture_dir=$CAPTURE_DIR"
  echo "payload_dir=$PAYLOAD_DIR"
  echo "target_payload_dir=$TARGET_PAYLOAD_DIR"

  [[ -x "$BASILISP" ]] && preflight_ok "Basilisp runner executable: $BASILISP" || preflight_fail "Basilisp runner not executable: $BASILISP"
  [[ -d "$CAPTURE_DIR" ]] && preflight_ok "capture dir exists: $CAPTURE_DIR" || preflight_fail "capture dir does not exist: $CAPTURE_DIR"
  preflight_check_corrected_bundles
  if [[ -L "$ANALYSIS_DIR" ]]; then
    preflight_fail "analysis dir must be a real directory, not a symlink: $ANALYSIS_DIR"
  elif [[ -d "$ANALYSIS_DIR" ]]; then
    preflight_ok "analysis dir exists: $ANALYSIS_DIR"
  else
    preflight_warn "analysis dir does not exist yet: $ANALYSIS_DIR"
  fi
  [[ -d "$PAYLOAD_DIR" ]] && preflight_ok "payload root exists: $PAYLOAD_DIR" || preflight_warn "payload root does not exist yet: $PAYLOAD_DIR"
  for script in "${REQUIRED_WORKFLOW_SCRIPTS[@]}"; do
    [[ -f "$REPO/$script" ]] && preflight_ok "workflow script exists: $script" || preflight_fail "workflow script missing: $REPO/$script"
  done
  if "$BASILISP" run scripts/capture_v2_runtime_preflight.lpy -- \
      --repo-root "$REPO" \
      --target-date "$TARGET_DATE" \
      --capture-dir "$CAPTURE_DIR" \
      --out-json "$ANALYSIS_DIR/capture_v2_runtime_preflight_$STAMP.json"; then
    preflight_ok "capture-v2 runtime writer preflight passed"
  else
    preflight_fail "capture-v2 runtime writer preflight failed"
  fi
  echo "Command plan:"
fi

if [[ "$DRY_RUN" != "1" ]]; then
	  [[ -x "$BASILISP" ]] || { echo "Basilisp runner not executable: $BASILISP" >&2; exit 1; }
	  mkdir -p "$ANALYSIS_DIR" "$PAYLOAD_DIR"
  if [[ -L "$ANALYSIS_DIR" ]]; then
    echo "refusing symlinked analysis dir: $ANALYSIS_DIR" >&2
    exit 2
  fi
	  PAYLOAD_DIR_REAL="$(cd "$PAYLOAD_DIR" && pwd -P)"
  TARGET_PAYLOAD_PARENT_REAL="$(cd "$(dirname "$TARGET_PAYLOAD_DIR")" && pwd -P)"
  if [[ -z "$STAMP" || "$(basename "$TARGET_PAYLOAD_DIR")" != "$STAMP" || "$TARGET_PAYLOAD_PARENT_REAL" != "$PAYLOAD_DIR_REAL" ]]; then
    echo "refusing unsafe target payload dir cleanup: $TARGET_PAYLOAD_DIR (payload root: $PAYLOAD_DIR)" >&2
    exit 2
  fi
  RETAINED_DIR="$ANALYSIS_DIR/market_evidence_retained/$STAMP/$(date -u +%Y%m%dT%H%M%SZ)-$$"
  RETAINED_COUNT=0
  retain_artifact_if_exists() {
    local path="$1"
    if [[ -f "$path" ]]; then
      mkdir -p "$RETAINED_DIR"
      cp -p "$path" "$RETAINED_DIR/"
      RETAINED_COUNT=$((RETAINED_COUNT + 1))
    fi
  }
  retain_artifact_if_exists "$HISTORICAL_FEATURE_NPZ"
  retain_artifact_if_exists "$HISTORICAL_COHORT_JSON"
  retain_artifact_if_exists "$REPLAYED_FEATURE_NPZ"
  retain_artifact_if_exists "$REPLAYED_COHORT_JSON"
  retain_artifact_if_exists "$GRID_INPUT_PARITY_JSON"
  retain_artifact_if_exists "$GRID_INPUT_PARITY_MD"
  retain_artifact_if_exists "$MATCHED_PARITY_JSON"
  retain_artifact_if_exists "$ANALYSIS_DIR/matched_feature_parity_$STAMP.csv"
  retain_artifact_if_exists "$ANALYSIS_DIR/matched_feature_parity_$STAMP.md"
  retain_artifact_if_exists "$ANALYSIS_DIR/matched_feature_parity_summary_$STAMP.json"
  retain_artifact_if_exists "$ANALYSIS_DIR/matched_feature_parity_summary_$STAMP.md"
  if (( RETAINED_COUNT > 0 )); then
    echo "retained $RETAINED_COUNT previous market-evidence artifact(s) before cleanup: $RETAINED_DIR" >&2
  fi
  rm -f \
    "$ANALYSIS_DIR/thetadata_capability_probe_$STAMP.json" \
    "$ANALYSIS_DIR/thetadata_capability_probe_$STAMP.md" \
    "$PAYLOAD_VERIFICATION_JSON" \
    "$BASELINE_JSON" \
    "$BASELINE_CSV" \
    "$ANALYSIS_DIR/live_feature_parity_baseline_$STAMP.md" \
    "$PREDICTION_DELTA_CSV" \
    "$ANALYSIS_DIR/live_feature_prediction_delta_aggregate_$STAMP.json" \
    "$ANALYSIS_DIR/live_feature_prediction_delta_aggregate_$STAMP.md" \
    "$PARITY_GATE_JSON" \
    "$ANALYSIS_DIR/live_feature_parity_gate_$STAMP.md" \
    "$MODEL_USAGE_CSV" \
    "$ANALYSIS_DIR/live_feature_model_usage_$STAMP.json" \
    "$ANALYSIS_DIR/live_feature_model_usage_$STAMP.md" \
    "$NEUTRALIZATION_JSON" \
    "$ANALYSIS_DIR/neutralization_audit_$STAMP.csv" \
    "$ANALYSIS_DIR/neutralization_audit_$STAMP.md" \
    "$UNLOCK_PLAN_JSON" \
    "$ANALYSIS_DIR/neutralized_feature_unlock_plan_$STAMP.csv" \
    "$ANALYSIS_DIR/neutralized_feature_unlock_plan_$STAMP.md" \
    "$BLOCKED_PROVENANCE_JSON" \
    "$ANALYSIS_DIR/blocked_feature_provenance_audit_$STAMP.csv" \
    "$ANALYSIS_DIR/blocked_feature_provenance_audit_$STAMP.md" \
    "$ANALYSIS_DIR/legacy_greek_formula_search_$STAMP.json" \
    "$ANALYSIS_DIR/legacy_greek_formula_search_$STAMP.csv" \
    "$ANALYSIS_DIR/legacy_greek_formula_search_$STAMP.md" \
    "$GREEK_RECONSTRUCTION_JSON" \
    "$ANALYSIS_DIR/greek_feature_reconstruction_audit_$STAMP.csv" \
    "$ANALYSIS_DIR/greek_feature_reconstruction_audit_$STAMP.md" \
    "$OPTION_SURFACE_SIDECAR_NPZ" \
    "$OPTION_SURFACE_SIDECAR_JSON" \
    "$OPTION_SURFACE_SIDECAR_CHECK_JSON" \
    "$RAW_UNLOCK_JSON" \
    "$ANALYSIS_DIR/raw_feature_unlock_audit_$STAMP.csv" \
    "$ANALYSIS_DIR/raw_feature_unlock_audit_$STAMP.md" \
    "$RAW_UNLOCK_CANDIDATES_JSON" \
    "$V3_UNLOCK_JSON" \
    "$ANALYSIS_DIR/v3_grid_unlock_audit_$STAMP.csv" \
    "$ANALYSIS_DIR/v3_grid_unlock_audit_$STAMP.md" \
    "$GREEK_PROMOTION_JSON" \
    "$ANALYSIS_DIR/greek_reconstruction_promotion_gate_$STAMP.csv" \
    "$ANALYSIS_DIR/greek_reconstruction_promotion_gate_$STAMP.md" \
    "$HISTORICAL_FEATURE_NPZ" \
    "$HISTORICAL_COHORT_JSON" \
    "$REPLAYED_FEATURE_NPZ" \
    "$REPLAYED_COHORT_JSON" \
    "$MATCHED_PARITY_JSON" \
    "$ANALYSIS_DIR/matched_feature_parity_$STAMP.csv" \
    "$ANALYSIS_DIR/matched_feature_parity_$STAMP.md" \
    "$ANALYSIS_DIR/matched_feature_parity_summary_$STAMP.json" \
    "$ANALYSIS_DIR/matched_feature_parity_summary_$STAMP.md" \
    "$NEUTRALIZED_EVIDENCE_JSON" \
    "$ANALYSIS_DIR/neutralized_feature_evidence_report_$STAMP.csv" \
    "$ANALYSIS_DIR/neutralized_feature_evidence_report_$STAMP.md" \
    "$UNMASK_DRY_RUN_JSON" \
    "$CAPTURE_CHECK_JSON" \
    "$READINESS_JSON" \
    "$ANALYSIS_DIR/market_evidence_readiness_$STAMP.md" \
    "$MANIFEST_JSON" \
    "$STATUS_JSON" \
    "$STATUS_MD" \
    "$VERIFIED_APPLY_VALIDATION_JSON"
  rm -f \
    "$ANALYSIS_DIR"/raw_feature_unlock_audit_"$STAMP"_*.json \
    "$ANALYSIS_DIR"/raw_feature_unlock_audit_"$STAMP"_*.csv \
    "$ANALYSIS_DIR"/raw_feature_unlock_audit_"$STAMP"_*.md \
    "$ANALYSIS_DIR"/raw_feature_unlock_candidates_"$STAMP"_*.json
  rm -rf "$TARGET_PAYLOAD_DIR"
  mkdir -p "$TARGET_PAYLOAD_DIR"
fi

CAPTURE_CHECK_RC=0
if [[ "$DRY_RUN" == "1" || -f "$CAPTURE_NPZ" ]]; then
  capture_check_cmd=("$BASILISP" run scripts/capture_v2_sidecar_check.lpy --
    --capture "$CAPTURE_NPZ"
    --target-date "$TARGET_DATE"
    --min-rows "$MIN_CAPTURE_ROWS"
    --sidecar-row-limit "$CAPTURE_SIDECAR_ROW_LIMIT"
    --fast-json
    --out-json "$CAPTURE_CHECK_JSON")
  if [[ "$ALLOW_MISSING_OPTION_SURFACES" == "1" ]]; then
    capture_check_cmd+=(--allow-missing-option-surfaces)
  fi
  run_allow_fail "${capture_check_cmd[@]}" || CAPTURE_CHECK_RC=$?
else
  echo "WARN: skipping capture-v2 sidecar check because target capture NPZ is missing: $CAPTURE_NPZ" >&2
  CAPTURE_CHECK_RC=1
fi

CAPTURE_V2_READY=0
if [[ "$DRY_RUN" == "1" || ( "$CAPTURE_CHECK_RC" == "0" && -f "$CAPTURE_CHECK_JSON" ) ]]; then
  CAPTURE_V2_READY=1
fi

probe_cmd=("$BASILISP" run scripts/thetadata_capability_probe.lpy --
  --base-url "$THETADATA_BASE_URL"
  --out-dir "$ANALYSIS_DIR"
  --timeout-s "$THETADATA_TIMEOUT_S"
  --save-payloads
  --payload-dir "$PAYLOAD_DIR"
  --target-date "$TARGET_DATE")

if [[ -n "${THETADATA_OPTION_SYMBOLS:-}" ]]; then
  probe_cmd+=(--option-symbols "$THETADATA_OPTION_SYMBOLS")
fi
if [[ -n "${THETADATA_INDEX_SYMBOLS:-}" ]]; then
  probe_cmd+=(--index-symbols "$THETADATA_INDEX_SYMBOLS")
fi
if [[ -n "${THETADATA_STOCK_SYMBOLS:-}" ]]; then
  probe_cmd+=(--stock-symbols "$THETADATA_STOCK_SYMBOLS")
fi
if [[ -n "${THETADATA_EXPIRATION:-}" ]]; then
  probe_cmd+=(--expiration "$THETADATA_EXPIRATION")
fi
run_allow_fail "${probe_cmd[@]}" || true

run_allow_fail "$BASILISP" run scripts/verify_thetadata_payload_examples.lpy -- \
  --payload-dir "$TARGET_PAYLOAD_DIR" \
  --target-date "$TARGET_DATE" \
  --out "$PAYLOAD_VERIFICATION_JSON" || true

option_surface_sidecar_cmd=("$BASILISP" run scripts/collect_option_surface_sidecar.lpy --
  --base-url "$THETADATA_BASE_URL"
  --symbols "$OPTION_SURFACE_SIDECAR_SYMBOLS"
  --target-date "$TARGET_DATE"
  --capture "$CAPTURE_NPZ"
  --out-npz "$OPTION_SURFACE_SIDECAR_NPZ"
  --out-json "$OPTION_SURFACE_SIDECAR_JSON"
  --timeout-s "$THETADATA_TIMEOUT_S"
  --max-contracts "$OPTION_SURFACE_SIDECAR_MAX_CONTRACTS")
if [[ -n "${THETADATA_EXPIRATION:-}" ]]; then
  option_surface_sidecar_cmd+=(--expiration "$THETADATA_EXPIRATION")
fi
run_allow_fail "${option_surface_sidecar_cmd[@]}" || true
if [[ "$DRY_RUN" == "1" || -f "$OPTION_SURFACE_SIDECAR_NPZ" ]]; then
  run_allow_fail "$BASILISP" run scripts/option_surface_sidecar_check.lpy -- \
    --sidecar "$OPTION_SURFACE_SIDECAR_NPZ" \
    --target-date "$TARGET_DATE" \
    --min-rows 1 \
    --required-prefixes "$OPTION_SURFACE_SIDECAR_SYMBOLS" \
    --min-contracts-per-prefix 1 \
    --out-json "$OPTION_SURFACE_SIDECAR_CHECK_JSON" || true
else
  echo "WARN: skipping option-surface sidecar check because sidecar NPZ is missing: $OPTION_SURFACE_SIDECAR_NPZ" >&2
fi

if [[ "$CAPTURE_V2_READY" == "1" ]]; then
  run_allow_fail "$BASILISP" run scripts/live_feature_parity_baseline.lpy -- \
    --capture-dir "$CAPTURE_DIR" \
    --out-dir "$ANALYSIS_DIR" \
    --target-date "$TARGET_DATE" \
    --dates "$STAMP" || true
else
  echo "WARN: skipping live feature parity baseline because capture-v2 sidecar check failed or is missing: $CAPTURE_CHECK_JSON" >&2
  run_allow_fail "$BASILISP" run scripts/live_feature_parity_baseline.lpy -- \
    --capture-dir "$CAPTURE_DIR" \
    --out-dir "$ANALYSIS_DIR" \
    --target-date "$TARGET_DATE" \
    --dates "$STAMP" \
    --write-unavailable \
    --unavailable-reason "capture-v2 sidecar check failed or is missing: $CAPTURE_CHECK_JSON" || true
fi

BASELINE_READY=0
if [[ "$DRY_RUN" == "1" || ( "$CAPTURE_V2_READY" == "1" && -f "$BASELINE_CSV" ) ]]; then
  BASELINE_READY=1
fi

if [[ "$BASELINE_READY" == "1" ]]; then
  run_allow_fail "$BASILISP" run scripts/live_feature_prediction_delta.lpy -- \
    --capture-dir "$CAPTURE_DIR" \
    --out-dir "$ANALYSIS_DIR" \
    --candidate-mode aggregate \
    --baseline-csv "$BASELINE_CSV" \
    --dates "$STAMP" || true
else
  echo "WARN: skipping prediction delta because baseline is unavailable or missing: $BASELINE_CSV" >&2
  run_allow_fail "$BASILISP" run scripts/live_feature_prediction_delta.lpy -- \
    --capture-dir "$CAPTURE_DIR" \
    --out-dir "$ANALYSIS_DIR" \
    --candidate-mode aggregate \
    --baseline-csv "$BASELINE_CSV" \
    --dates "$STAMP" \
    --write-unavailable \
    --unavailable-reason "baseline is unavailable or missing: $BASELINE_CSV" || true
fi

if [[ "$BASELINE_READY" == "1" ]]; then
  parity_gate_cmd=("$BASILISP" run scripts/live_feature_parity_gate.lpy --
    --baseline-csv "$BASELINE_CSV"
    --out-dir "$ANALYSIS_DIR"
    --target-date "$TARGET_DATE")
  if [[ "$DRY_RUN" == "1" || -f "$PREDICTION_DELTA_CSV" ]]; then
    parity_gate_cmd+=(--prediction-delta-csv "$PREDICTION_DELTA_CSV")
  fi
  run_allow_fail "${parity_gate_cmd[@]}" || true
else
  echo "WARN: skipping parity gate because baseline is unavailable or missing: $BASELINE_CSV" >&2
  run_allow_fail "$BASILISP" run scripts/live_feature_parity_gate.lpy -- \
    --baseline-csv "$BASELINE_CSV" \
    --out-dir "$ANALYSIS_DIR" \
    --target-date "$TARGET_DATE" \
    --write-unavailable \
    --unavailable-reason "baseline is unavailable or missing: $BASELINE_CSV" || true
fi

if [[ "$BASELINE_READY" == "1" ]]; then
  run_allow_fail "$BASILISP" run scripts/live_feature_model_usage_audit.lpy -- \
    --baseline-csv "$BASELINE_CSV" \
    --ref-root "$REF" \
    --out-dir "$ANALYSIS_DIR" \
    --target-date "$TARGET_DATE" || true
else
  echo "WARN: skipping model usage audit because baseline is unavailable or missing: $BASELINE_CSV" >&2
  run_allow_fail "$BASILISP" run scripts/live_feature_model_usage_audit.lpy -- \
    --baseline-csv "$BASELINE_CSV" \
    --ref-root "$REF" \
    --out-dir "$ANALYSIS_DIR" \
    --target-date "$TARGET_DATE" \
    --write-unavailable \
    --unavailable-reason "baseline is unavailable or missing: $BASELINE_CSV" || true
fi

if [[ "$BASELINE_READY" == "1" && ( "$DRY_RUN" == "1" || -f "$MODEL_USAGE_CSV" ) ]]; then
  run_allow_fail "$BASILISP" run scripts/neutralization_audit.lpy -- \
    --baseline-csv "$BASELINE_CSV" \
    --usage-csv "$MODEL_USAGE_CSV" \
    --capture-dir "$CAPTURE_DIR" \
    --out-dir "$ANALYSIS_DIR" \
    --target-date "$TARGET_DATE" || true
else
  echo "WARN: skipping neutralization audit because baseline/model-usage CSV is missing" >&2
  run_allow_fail "$BASILISP" run scripts/neutralization_audit.lpy -- \
    --baseline-csv "$BASELINE_CSV" \
    --usage-csv "$MODEL_USAGE_CSV" \
    --capture-dir "$CAPTURE_DIR" \
    --out-dir "$ANALYSIS_DIR" \
    --target-date "$TARGET_DATE" \
    --write-unavailable \
    --unavailable-reason "baseline/model-usage CSV is missing: $BASELINE_CSV / $MODEL_USAGE_CSV" || true
fi

unlock_plan_cmd=("$BASILISP" run scripts/neutralized_feature_unlock_plan.lpy --
  --ref-root "$REF" \
  --out-dir "$ANALYSIS_DIR" \
  --label "$STAMP" \
  --target-date "$TARGET_DATE")
if [[ "$DRY_RUN" == "1" || -f "$MODEL_USAGE_JSON" ]]; then
  unlock_plan_cmd+=(--usage-json "$MODEL_USAGE_JSON")
fi
run_allow_fail "${unlock_plan_cmd[@]}" || true

if [[ "$DRY_RUN" == "1" || -f "$UNLOCK_PLAN_JSON" ]]; then
  run_allow_fail "$BASILISP" run scripts/blocked_feature_provenance_audit.lpy -- \
    --ref-root "$REF" \
    --plan-json "$UNLOCK_PLAN_JSON" \
    --out-dir "$ANALYSIS_DIR" \
    --label "$STAMP" \
    --target-date "$TARGET_DATE" || true
else
  echo "WARN: skipping blocked feature provenance audit because unlock plan is missing: $UNLOCK_PLAN_JSON" >&2
fi

if [[ "$DRY_RUN" == "1" || -f "$BLOCKED_PROVENANCE_JSON" ]]; then
  run_allow_fail "$BASILISP" run scripts/legacy_greek_formula_search.lpy -- \
    --blocked-json "$BLOCKED_PROVENANCE_JSON" \
    --root "$REPO" \
    --root "$REF" \
    --out-dir "$ANALYSIS_DIR" \
    --label "$STAMP" \
    --target-date "$TARGET_DATE" || true
else
  echo "WARN: skipping legacy greek formula search because blocked provenance audit is missing: $BLOCKED_PROVENANCE_JSON" >&2
fi

if [[ "$DRY_RUN" == "1" || -f "$BLOCKED_PROVENANCE_JSON" ]]; then
  greek_reconstruction_cmd=("$BASILISP" run scripts/greek_feature_reconstruction_audit.lpy --
    --blocked-json "$BLOCKED_PROVENANCE_JSON" \
    --out-dir "$ANALYSIS_DIR" \
    --label "$STAMP" \
    --target-date "$TARGET_DATE")
  if [[ "$CAPTURE_V2_READY" == "1" ]]; then
    greek_reconstruction_cmd+=(--capture "$CAPTURE_NPZ")
  fi
  run_allow_fail "${greek_reconstruction_cmd[@]}" || true
else
  echo "WARN: skipping Greek feature reconstruction audit because blocked provenance audit is missing: $BLOCKED_PROVENANCE_JSON" >&2
  run_allow_fail "$BASILISP" run scripts/greek_feature_reconstruction_audit.lpy -- \
    --out-dir "$ANALYSIS_DIR" \
    --label "$STAMP" \
    --target-date "$TARGET_DATE" \
    --write-unavailable \
    --unavailable-reason "blocked provenance audit is missing: $BLOCKED_PROVENANCE_JSON" || true
fi

if [[ "$CAPTURE_V2_READY" == "1" && ( "$DRY_RUN" == "1" || ( -f "$BASELINE_JSON" && -f "$MODEL_USAGE_JSON" ) ) ]]; then
  raw_unlock_cmd=("$BASILISP" run scripts/raw_feature_unlock_audit.lpy --
    --target-date "$TARGET_DATE" \
    --ref-root "$REF" \
    --capture "$CAPTURE_NPZ" \
    --baseline-json "$BASELINE_JSON" \
    --usage-json "$MODEL_USAGE_JSON" \
    --out-dir "$ANALYSIS_DIR" \
    --include-sources base,v2 \
    --skip-option-formulas \
    --skip-greek-reconstruction)
  if [[ -n "$RAW_FEATURE_UNLOCK_MAX_ROWS" && "$RAW_FEATURE_UNLOCK_MAX_ROWS" != "all" && "$RAW_FEATURE_UNLOCK_MAX_ROWS" != "full" && "$RAW_FEATURE_UNLOCK_MAX_ROWS" != "0" ]]; then
    raw_unlock_cmd+=(--max-rows "$RAW_FEATURE_UNLOCK_MAX_ROWS")
  fi
  if [[ -n "$RAW_FEATURE_UNLOCK_MAX_OPTION_CONTRACTS" && "$RAW_FEATURE_UNLOCK_MAX_OPTION_CONTRACTS" != "all" && "$RAW_FEATURE_UNLOCK_MAX_OPTION_CONTRACTS" != "full" && "$RAW_FEATURE_UNLOCK_MAX_OPTION_CONTRACTS" != "0" ]]; then
    raw_unlock_cmd+=(--max-option-contracts "$RAW_FEATURE_UNLOCK_MAX_OPTION_CONTRACTS")
  fi
  if [[ -n "$RAW_FEATURE_UNLOCK_MAX_SURFACE_CONTRACTS" && "$RAW_FEATURE_UNLOCK_MAX_SURFACE_CONTRACTS" != "all" && "$RAW_FEATURE_UNLOCK_MAX_SURFACE_CONTRACTS" != "full" && "$RAW_FEATURE_UNLOCK_MAX_SURFACE_CONTRACTS" != "0" ]]; then
    raw_unlock_cmd+=(--max-surface-contracts "$RAW_FEATURE_UNLOCK_MAX_SURFACE_CONTRACTS")
  fi
  run_allow_fail "${raw_unlock_cmd[@]}" || true
  run_supplemental_raw_unlock_probes
  if [[ "$DRY_RUN" == "1" || -f "$OPTION_SURFACE_SIDECAR_NPZ" ]]; then
    option_surface_audit_cmd=("$BASILISP" run scripts/raw_feature_unlock_audit.lpy --
      --target-date "$TARGET_DATE"
      --ref-root "$REF"
      --capture "$OPTION_SURFACE_SIDECAR_NPZ"
      --baseline-json "$BASELINE_JSON"
      --usage-json "$MODEL_USAGE_JSON"
      --out-dir "$ANALYSIS_DIR"
      --label "option_surface_sidecar"
      --include-sources option-surface,greek,greek-grid,greek-reconstruction
      --option-surface-prefixes "$OPTION_SURFACE_SIDECAR_SYMBOLS"
      --max-option-contracts "$OPTION_SURFACE_SIDECAR_MAX_AUDIT_CONTRACTS"
      --max-surface-contracts "$OPTION_SURFACE_SIDECAR_MAX_AUDIT_CONTRACTS")
    if [[ -n "$OPTION_SURFACE_SIDECAR_MAX_ROWS" ]]; then
      option_surface_audit_cmd+=(--max-rows "$OPTION_SURFACE_SIDECAR_MAX_ROWS")
    fi
    run_allow_fail "${option_surface_audit_cmd[@]}" || true
  else
    echo "WARN: skipping option-surface sidecar unlock audit because sidecar NPZ is missing: $OPTION_SURFACE_SIDECAR_NPZ" >&2
  fi
else
  echo "WARN: skipping raw feature unlock audit because capture-v2 sidecar check failed or baseline/model-usage JSON is missing" >&2
  run_allow_fail "$BASILISP" run scripts/raw_feature_unlock_audit.lpy -- \
    --target-date "$TARGET_DATE" \
    --ref-root "$REF" \
    --capture "$CAPTURE_NPZ" \
    --baseline-json "$BASELINE_JSON" \
    --usage-json "$MODEL_USAGE_JSON" \
    --out-dir "$ANALYSIS_DIR" \
    --write-unavailable \
    --unavailable-reason "capture-v2 sidecar check failed or baseline/model-usage JSON is missing: $CAPTURE_CHECK_JSON / $BASELINE_JSON / $MODEL_USAGE_JSON" || true
fi

if [[ "$CAPTURE_V2_READY" == "1" && ( "$DRY_RUN" == "1" || ( -f "$BASELINE_JSON" && -f "$MODEL_USAGE_JSON" ) ) ]]; then
  if [[ "$V3_GRID_UNLOCK_MAX_PREDICTION_ROWS" == "0" || "$V3_GRID_UNLOCK_MAX_PREDICTION_ROWS" == "skip" || "$V3_GRID_UNLOCK_MAX_PREDICTION_ROWS" == "off" ]]; then
    run_allow_fail "$BASILISP" run scripts/v3_grid_unlock_audit.lpy -- \
      --target-date "$TARGET_DATE" \
      --out-dir "$ANALYSIS_DIR" \
      --write-unavailable \
      --unavailable-reason "V3 audit skipped by V3_GRID_UNLOCK_MAX_PREDICTION_ROWS=$V3_GRID_UNLOCK_MAX_PREDICTION_ROWS; candidates fail-closed" || true
  else
    run_allow_fail "$BASILISP" run scripts/v3_grid_unlock_audit.lpy -- \
      --target-date "$TARGET_DATE" \
      --ref-root "$REF" \
      --capture "$CAPTURE_NPZ" \
      --baseline-json "$BASELINE_JSON" \
      --usage-json "$MODEL_USAGE_JSON" \
      --out-dir "$ANALYSIS_DIR" \
      --max-prediction-rows "$V3_GRID_UNLOCK_MAX_PREDICTION_ROWS" || true
  fi
else
  echo "WARN: skipping V3 grid unlock audit because capture-v2 sidecar check failed or baseline/model-usage JSON is missing" >&2
  run_allow_fail "$BASILISP" run scripts/v3_grid_unlock_audit.lpy -- \
    --target-date "$TARGET_DATE" \
    --ref-root "$REF" \
    --capture "$CAPTURE_NPZ" \
    --baseline-json "$BASELINE_JSON" \
    --usage-json "$MODEL_USAGE_JSON" \
    --out-dir "$ANALYSIS_DIR" \
    --write-unavailable \
    --unavailable-reason "capture-v2 sidecar check failed or baseline/model-usage JSON is missing: $CAPTURE_CHECK_JSON / $BASELINE_JSON / $MODEL_USAGE_JSON" || true
fi

if [[ "$CAPTURE_V2_READY" == "1" ]]; then
  run_allow_fail "$BASILISP" run scripts/replay_captured_feature_cohort.lpy -- \
    --capture "$CAPTURE_NPZ" \
    --ref-root "$REF" \
    --bundle "$REF/pipeline_data/live_model_chestnut_multihead_corrected" \
    --out-npz "$REPLAYED_FEATURE_NPZ" \
    --out-json "$REPLAYED_COHORT_JSON" \
    --live-array chestnut \
    --min-rows 1 \
    --max-rows "$REPLAY_CAPTURED_FEATURE_MAX_ROWS" \
    --skip-option-overlays || true
else
  echo "WARN: skipping captured feature replay because capture-v2 sidecar check failed or is missing: $CAPTURE_CHECK_JSON" >&2
  run_allow_fail "$BASILISP" run scripts/replay_captured_feature_cohort.lpy -- \
    --capture "$CAPTURE_NPZ" \
    --ref-root "$REF" \
    --bundle "$REF/pipeline_data/live_model_chestnut_multihead_corrected" \
    --out-npz "$REPLAYED_FEATURE_NPZ" \
    --out-json "$REPLAYED_COHORT_JSON" \
    --live-array chestnut \
    --target-date "$TARGET_DATE" \
    --write-unavailable \
    --unavailable-reason "capture-v2 sidecar check failed or is missing: $CAPTURE_CHECK_JSON" || true
fi

if [[ "$CAPTURE_V2_READY" == "1" && ( "$DRY_RUN" == "1" || -f "$RAW_UNLOCK_JSON" ) ]]; then
  greek_promotion_cmd=("$BASILISP" run scripts/greek_reconstruction_promotion_gate.lpy --
    --target-date "$TARGET_DATE" \
    --raw-audit-json "$RAW_UNLOCK_JSON" \
    --capture-check-json "$CAPTURE_CHECK_JSON" \
    --out-dir "$ANALYSIS_DIR" \
    --label "$STAMP")
  while IFS= read -r supplemental_raw_audit; do
    greek_promotion_cmd+=(--extra-raw-audit-json "$supplemental_raw_audit")
  done < <(
    find "$ANALYSIS_DIR" -maxdepth 1 -type f \
      -name "raw_feature_unlock_audit_${STAMP}_*.json" \
      ! -name "raw_feature_unlock_candidates_${STAMP}*.json" \
      | sort
  )
  run_allow_fail "${greek_promotion_cmd[@]}" || true
else
  echo "WARN: skipping Greek reconstruction promotion gate because raw unlock audit is missing or capture-v2 sidecar check failed" >&2
  run_allow_fail "$BASILISP" run scripts/greek_reconstruction_promotion_gate.lpy -- \
    --target-date "$TARGET_DATE" \
    --raw-audit-json "$RAW_UNLOCK_JSON" \
    --capture-check-json "$CAPTURE_CHECK_JSON" \
    --out-dir "$ANALYSIS_DIR" \
    --label "$STAMP" \
    --write-unavailable \
    --unavailable-reason "raw unlock audit is missing or capture-v2 sidecar check failed: $RAW_UNLOCK_JSON / $CAPTURE_CHECK_JSON" || true
fi

if [[ "$CAPTURE_V2_READY" == "1" ]]; then
  case "$HISTORICAL_FEATURE_MODE" in
    thetadata)
      historical_cmd=("$BASILISP" run scripts/build_thetadata_historical_feature_cohort.lpy --
        --target-date "$TARGET_DATE"
        --ref-root "$REF"
        --bundle "$REF/pipeline_data/live_model_chestnut_multihead_corrected"
        --base-url "$THETADATA_BASE_URL"
        --stock-venue "$HISTORICAL_FEATURE_STOCK_VENUE"
        --start-time "$HISTORICAL_FEATURE_START_TIME"
        --stock-start-time "$HISTORICAL_FEATURE_STOCK_START_TIME"
        --end-time "$HISTORICAL_FEATURE_END_TIME"
        --chain-horizon-days "$HISTORICAL_FEATURE_CHAIN_HORIZON_DAYS"
        --surface-horizon-days "$HISTORICAL_FEATURE_SURFACE_HORIZON_DAYS"
        --surface-symbols "$HISTORICAL_FEATURE_SURFACE_SYMBOLS"
        --implementation "$HISTORICAL_FEATURE_IMPLEMENTATION"
        --option-reconstruction "$HISTORICAL_FEATURE_OPTION_RECONSTRUCTION"
        --cohort-window-minutes "$HISTORICAL_FEATURE_COHORT_WINDOW_MINUTES"
        --jobs "$HISTORICAL_FEATURE_JOBS"
        --request-timeout "$HISTORICAL_FEATURE_REQUEST_TIMEOUT"
        --thetadata-cache-dir "$HISTORICAL_FEATURE_THETADATA_CACHE_DIR"
        --min-rows "$MIN_CAPTURE_ROWS"
        --out-npz "$HISTORICAL_FEATURE_NPZ"
        --out-json "$HISTORICAL_COHORT_JSON")
      if [[ -n "$HISTORICAL_FEATURE_STRIKE_RANGE" ]]; then
        historical_cmd+=(--strike-range "$HISTORICAL_FEATURE_STRIKE_RANGE")
      fi
      if [[ -n "$HISTORICAL_FEATURE_SPY_STRIKE_RANGE" ]]; then
        historical_cmd+=(--spy-strike-range "$HISTORICAL_FEATURE_SPY_STRIKE_RANGE")
      fi
      if [[ "$HISTORICAL_FEATURE_ALLOW_MISSING_SURFACES" == "1" ]]; then
        historical_cmd+=(--allow-missing-surfaces)
      fi
      if [[ "$HISTORICAL_FEATURE_GRID_CONTRACTS_ONLY" == "1" ]]; then
        historical_cmd+=(--grid-contracts-only)
      fi
      if [[ "$HISTORICAL_FEATURE_SKIP_OPTION_ENRICHMENT" == "1" ]]; then
        historical_cmd+=(--skip-option-enrichment)
      fi
      run_allow_fail "${historical_cmd[@]}" || true
      ;;
    archive)
      run_allow_fail "$BASILISP" run scripts/prepare_historical_feature_cohort.lpy -- \
        --live-capture "$CAPTURE_NPZ" \
        --historical-source "$HISTORICAL_FEATURE_SOURCE_NPZ" \
        --date-map "$HISTORICAL_FEATURE_DATE_MAP" \
        --feature-names "$REF/pipeline_data/live_model_chestnut_multihead_corrected/feature_names.json" \
        --out-npz "$HISTORICAL_FEATURE_NPZ" \
        --out-json "$HISTORICAL_COHORT_JSON" \
        --target-date "$TARGET_DATE" \
        --min-rows "$MIN_CAPTURE_ROWS" || true
      ;;
    *)
      echo "WARN: unknown HISTORICAL_FEATURE_MODE=$HISTORICAL_FEATURE_MODE; expected thetadata or archive" >&2
      ;;
  esac
else
  echo "WARN: skipping historical feature cohort preparation because capture-v2 sidecar check failed or is missing: $CAPTURE_CHECK_JSON" >&2
fi

# This is the admission gate for a future training corpus. Tensor comparisons
# below remain diagnostic until raw source inputs and provenance are certified.
if [[ "$CAPTURE_V2_READY" == "1" && -f "$HISTORICAL_FEATURE_NPZ" ]]; then
  run_allow_fail "$BASILISP" run scripts/audit_captured_source_parity.lpy -- \
    --live-capture "$CAPTURE_NPZ" \
    --historical-inputs "$HISTORICAL_FEATURE_NPZ" \
    --out-json "$SOURCE_PARITY_JSON" \
    --min-rows "$MIN_CAPTURE_ROWS" \
    --bar-tolerance "$SOURCE_PARITY_BAR_TOLERANCE" \
    --quote-tolerance "$SOURCE_PARITY_QUOTE_TOLERANCE" || true
  if [[ -f "$SOURCE_PARITY_JSON" ]]; then
    run_allow_fail "$BASILISP" run scripts/build_verified_feature_corpus.lpy -- \
      --source-audit "$SOURCE_PARITY_JSON" \
      --historical-inputs "$HISTORICAL_FEATURE_NPZ" \
      --out-npz "$VERIFIED_CORPUS_NPZ" \
      --out-json "$VERIFIED_CORPUS_JSON" || true
  fi
else
  echo "WARN: skipping certified source audit because capture-v2 sidecars or historical inputs are missing: $CAPTURE_CHECK_JSON / $HISTORICAL_FEATURE_NPZ" >&2
fi

if [[ "$CAPTURE_V2_READY" == "1" && ( "$DRY_RUN" == "1" || -f "$HISTORICAL_FEATURE_NPZ" ) ]]; then
  run_allow_fail "$BASILISP" run scripts/grid_feature_input_parity.lpy -- \
    --live-capture "$CAPTURE_NPZ" \
    --historical-npz "$HISTORICAL_FEATURE_NPZ" \
    --historical-cohort-json "$HISTORICAL_COHORT_JSON" \
    --out-json "$GRID_INPUT_PARITY_JSON" \
    --md-out "$GRID_INPUT_PARITY_MD" \
    --target-date "$TARGET_DATE" \
    --min-rows "$MIN_CAPTURE_ROWS" || true
else
  echo "WARN: skipping grid feature input parity because capture-v2 sidecar check failed or historical tensor is missing: $CAPTURE_CHECK_JSON / $HISTORICAL_FEATURE_NPZ" >&2
  run_allow_fail "$BASILISP" run scripts/grid_feature_input_parity.lpy -- \
    --live-capture "$CAPTURE_NPZ" \
    --historical-npz "$HISTORICAL_FEATURE_NPZ" \
    --historical-cohort-json "$HISTORICAL_COHORT_JSON" \
    --out-json "$GRID_INPUT_PARITY_JSON" \
    --md-out "$GRID_INPUT_PARITY_MD" \
    --target-date "$TARGET_DATE" \
    --min-rows "$MIN_CAPTURE_ROWS" \
    --write-unavailable \
    --unavailable-reason "capture-v2 sidecar check failed or historical tensor is missing: $CAPTURE_CHECK_JSON / $HISTORICAL_FEATURE_NPZ" || true
fi

if [[ "$CAPTURE_V2_READY" == "1" && ( "$DRY_RUN" == "1" || -f "$HISTORICAL_FEATURE_NPZ" ) ]]; then
  run_allow_fail "$BASILISP" run scripts/matched_feature_parity_report.lpy -- \
    --live-capture "$CAPTURE_NPZ" \
    --historical-npz "$HISTORICAL_FEATURE_NPZ" \
    --feature-names "$REF/pipeline_data/live_model_chestnut_multihead_corrected/feature_names.json" \
    --out-dir "$ANALYSIS_DIR" \
    --target-date "$TARGET_DATE" \
    --min-rows "$MIN_CAPTURE_ROWS" \
    --write-unavailable-on-error || true
	  if [[ -f "$ANALYSIS_DIR/matched_feature_parity_$STAMP.csv" ]]; then
	    run_allow_fail "$BASILISP" run scripts/summarize_matched_feature_parity.lpy -- \
	      --matched-csv "$ANALYSIS_DIR/matched_feature_parity_$STAMP.csv" \
	      --usage-csv "$MODEL_USAGE_CSV" \
	      --grid-input-parity-json "$GRID_INPUT_PARITY_JSON" \
	      --target-date "$TARGET_DATE" \
	      --out-json "$ANALYSIS_DIR/matched_feature_parity_summary_$STAMP.json" \
	      --md-out "$ANALYSIS_DIR/matched_feature_parity_summary_$STAMP.md" \
	      --top-n 25 || true
  else
    echo "WARN: skipping matched feature parity summary because CSV is missing: $ANALYSIS_DIR/matched_feature_parity_$STAMP.csv" >&2
  fi
else
  echo "WARN: skipping matched feature parity report because capture-v2 sidecar check failed or historical tensor is missing: $CAPTURE_CHECK_JSON / $HISTORICAL_FEATURE_NPZ" >&2
  matched_unavailable_reason="capture-v2 sidecar check failed or historical tensor is missing: $CAPTURE_CHECK_JSON / $HISTORICAL_FEATURE_NPZ"
  run_allow_fail "$BASILISP" run scripts/matched_feature_parity_report.lpy -- \
    --live-capture "$CAPTURE_NPZ" \
    --historical-npz "$HISTORICAL_FEATURE_NPZ" \
    --feature-names "$REF/pipeline_data/live_model_chestnut_multihead_corrected/feature_names.json" \
    --out-dir "$ANALYSIS_DIR" \
    --target-date "$TARGET_DATE" \
    --min-rows "$MIN_CAPTURE_ROWS" \
    --write-unavailable \
    --unavailable-reason "$matched_unavailable_reason" || true
fi

READINESS_RC=0
run_allow_fail "$BASILISP" run scripts/market_evidence_readiness.lpy -- \
  --analysis-dir "$ANALYSIS_DIR" \
  --out-dir "$ANALYSIS_DIR" \
  --target-date "$TARGET_DATE" \
  --baseline-json "$BASELINE_JSON" \
  --probe-json "$PROBE_JSON" \
  --payload-verification-json "$PAYLOAD_VERIFICATION_JSON" \
  --neutralization-json "$NEUTRALIZATION_JSON" \
  --capture-check-json "$CAPTURE_CHECK_JSON" \
  --option-surface-sidecar-check-json "$OPTION_SURFACE_SIDECAR_CHECK_JSON" \
  --legacy-greek-search-json "$LEGACY_GREEK_SEARCH_JSON" \
  --greek-promotion-json "$GREEK_PROMOTION_JSON" \
  --historical-cohort-json "$HISTORICAL_COHORT_JSON" \
  --raw-unlock-json "$RAW_UNLOCK_JSON" \
  --v3-unlock-json "$V3_UNLOCK_JSON" \
  --matched-parity-json "$MATCHED_PARITY_JSON" \
  --min-capture-rows "$MIN_CAPTURE_ROWS" || READINESS_RC=$?

if [[ "$DRY_RUN" == "1" || -f "$UNLOCK_PLAN_JSON" ]]; then
  raw_unlock_evidence_args=()
  while IFS= read -r raw_unlock_path; do
    raw_unlock_evidence_args+=(--raw-unlock-json "$raw_unlock_path")
  done < <(
    find "$ANALYSIS_DIR" -maxdepth 1 -type f \
      -name "raw_feature_unlock_audit_${STAMP}*.json" \
      ! -name "raw_feature_unlock_candidates_${STAMP}*.json" \
      | sort
  )
  if [[ "${#raw_unlock_evidence_args[@]}" -eq 0 ]]; then
    raw_unlock_evidence_args=(--raw-unlock-json "$RAW_UNLOCK_JSON")
  fi
  run_allow_fail "$BASILISP" run scripts/neutralized_feature_evidence_report.lpy -- \
    --plan-json "$UNLOCK_PLAN_JSON" \
    "${raw_unlock_evidence_args[@]}" \
    --v3-unlock-json "$V3_UNLOCK_JSON" \
    --grid-input-parity-json "$GRID_INPUT_PARITY_JSON" \
    --readiness-json "$READINESS_JSON" \
    --capture-check-json "$CAPTURE_CHECK_JSON" \
    --out-dir "$ANALYSIS_DIR" \
    --target-date "$TARGET_DATE" || true
else
  echo "WARN: skipping neutralized feature evidence report because unlock plan is missing: $UNLOCK_PLAN_JSON" >&2
fi

if [[ "$DRY_RUN" == "1" || ( ( -f "$RAW_UNLOCK_CANDIDATES_JSON" && -f "$RAW_UNLOCK_JSON" ) || -f "$V3_UNLOCK_JSON" || -f "$GREEK_PROMOTION_JSON" ) ]]; then
  unmask_dry_run_cmd=("$BASILISP" run scripts/apply_neutralization_candidates.lpy --
    --ref-root "$REF" \
    --target-date "$TARGET_DATE" \
    --readiness-json "$READINESS_JSON" \
    --backup-label "before_unmask_$STAMP" \
    --out-json "$UNMASK_DRY_RUN_JSON")
  if [[ "$DRY_RUN" == "1" || ( -f "$RAW_UNLOCK_CANDIDATES_JSON" && -f "$RAW_UNLOCK_JSON" ) ]]; then
    unmask_dry_run_cmd+=(--candidates "$RAW_UNLOCK_CANDIDATES_JSON" --audit-json "$RAW_UNLOCK_JSON")
  fi
  while IFS= read -r supplemental_raw_audit; do
    unmask_dry_run_cmd+=(--extra-audit-json "$supplemental_raw_audit")
  done < <(
    find "$ANALYSIS_DIR" -maxdepth 1 -type f \
      -name "raw_feature_unlock_audit_${STAMP}_*.json" \
      ! -name "raw_feature_unlock_candidates_${STAMP}*.json" \
      | sort
  )
  if [[ "$DRY_RUN" == "1" || -f "$V3_UNLOCK_JSON" ]]; then
    unmask_dry_run_cmd+=(--extra-audit-json "$V3_UNLOCK_JSON")
  fi
  if [[ "$DRY_RUN" == "1" ]]; then
    unmask_dry_run_cmd+=(--extra-audit-json "$GREEK_PROMOTION_JSON")
  elif [[ -f "$GREEK_PROMOTION_JSON" ]] &&
       grep -Eq '"capture_ok"[[:space:]]*:[[:space:]]*true' "$GREEK_PROMOTION_JSON" &&
       grep -Eq '"coverage_ok"[[:space:]]*:[[:space:]]*true' "$GREEK_PROMOTION_JSON"; then
    unmask_dry_run_cmd+=(--extra-audit-json "$GREEK_PROMOTION_JSON")
  elif [[ -f "$GREEK_PROMOTION_JSON" ]]; then
    echo "WARN: skipping Greek promotion audit in unmask dry-run because capture_ok/coverage_ok is not true: $GREEK_PROMOTION_JSON" >&2
  fi
  run_allow_fail "${unmask_dry_run_cmd[@]}" || true
else
  echo "WARN: skipping neutralization unmask dry-run because raw unlock candidates/audit, V3 unlock audit, and Greek promotion gate are missing" >&2
fi

MANIFEST_RC=0
run_allow_fail "$BASILISP" run scripts/market_evidence_manifest.lpy -- \
  --target-date "$TARGET_DATE" \
  --analysis-dir "$ANALYSIS_DIR" \
  --payload-dir "$PAYLOAD_DIR" \
  --out "$MANIFEST_JSON" || MANIFEST_RC=$?

MANIFEST_VERIFY_RC=0
if [[ "$DRY_RUN" == "1" || -f "$MANIFEST_JSON" ]]; then
  run_allow_fail "$BASILISP" run scripts/market_evidence_manifest.lpy -- \
    --target-date "$TARGET_DATE" \
    --verify "$MANIFEST_JSON" \
    --analysis-dir "$ANALYSIS_DIR" \
    --payload-dir "$PAYLOAD_DIR" || MANIFEST_VERIFY_RC=$?
else
  echo "WARN: skipping manifest verification because manifest is missing: $MANIFEST_JSON" >&2
  MANIFEST_VERIFY_RC=1
fi

STATUS_RC=0
if [[ "$DRY_RUN" == "1" || -f "$MANIFEST_JSON" ]]; then
  run_allow_fail "$BASILISP" run scripts/market_evidence_status.lpy -- \
    --target-date "$TARGET_DATE" \
    --analysis-dir "$ANALYSIS_DIR" \
    --payload-dir "$PAYLOAD_DIR" \
    --manifest "$MANIFEST_JSON" \
    --out "$STATUS_JSON" \
    --md-out "$STATUS_MD" || STATUS_RC=$?
else
  echo "WARN: skipping market evidence status because manifest is missing: $MANIFEST_JSON" >&2
  STATUS_RC=1
fi

if [[ "$DRY_RUN" != "1" && "$STATUS_RC" == "0" ]]; then
  assert_status_json_ok || STATUS_RC=$?
fi

VERIFIED_APPLY_RC=0
if [[ "$DRY_RUN" == "1" || ( "$STATUS_RC" == "0" && -f "$MANIFEST_JSON" && -f "$STATUS_JSON" ) ]]; then
  run_allow_fail "$BASILISP" run scripts/apply_verified_neutralization_unmask.lpy -- \
    --target-date "$TARGET_DATE" \
    --analysis-dir "$ANALYSIS_DIR" \
    --manifest-json "$MANIFEST_JSON" \
    --status-json "$STATUS_JSON" \
    --ref-root "$REF" \
    --validation-json "$VERIFIED_APPLY_VALIDATION_JSON" \
    --allow-empty || VERIFIED_APPLY_RC=$?
else
  echo "WARN: skipping verified apply validation because status/manifest is not green" >&2
fi

if [[ "$DRY_RUN" == "1" || ( "$VERIFIED_APPLY_RC" == "0" && -f "$VERIFIED_APPLY_VALIDATION_JSON" ) ]]; then
  run_allow_fail "$BASILISP" run scripts/market_evidence_status.lpy -- \
    --target-date "$TARGET_DATE" \
    --analysis-dir "$ANALYSIS_DIR" \
    --payload-dir "$PAYLOAD_DIR" \
    --manifest "$MANIFEST_JSON" \
    --out "$STATUS_JSON" \
    --md-out "$STATUS_MD" || STATUS_RC=$?
  if [[ "$DRY_RUN" != "1" && "$STATUS_RC" == "0" ]]; then
    assert_status_json_unmask_apply_ready || STATUS_RC=$?
  fi
fi

if [[ "$PREFLIGHT" == "1" ]]; then
  exit "$PREFLIGHT_RC"
fi
if [[ "$CAPTURE_CHECK_RC" != "0" ]]; then
  exit "$CAPTURE_CHECK_RC"
fi
if [[ "$READINESS_RC" != "0" ]]; then
  exit "$READINESS_RC"
fi
if [[ "$MANIFEST_RC" != "0" ]]; then
  exit "$MANIFEST_RC"
fi
if [[ "$MANIFEST_VERIFY_RC" != "0" ]]; then
  exit "$MANIFEST_VERIFY_RC"
fi
if [[ "$VERIFIED_APPLY_RC" != "0" ]]; then
  exit "$VERIFIED_APPLY_RC"
fi
exit "$STATUS_RC"
