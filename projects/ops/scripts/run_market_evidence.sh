#!/usr/bin/env bash
# Run the market-evidence workflow from systemd.
set -euo pipefail

if [[ "$#" -gt 0 ]]; then
  echo "RESULT: FAILED - run_market_evidence.sh does not accept CLI args; set MARKET_EVIDENCE_MODE or run scripts/collect_market_evidence.sh directly" >&2
  exit 2
fi

ROOT="${STEVETRADING_BASILISP_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
MODE="${MARKET_EVIDENCE_MODE:-collect}"
TARGET_DATE="${MARKET_EVIDENCE_TARGET_DATE:-${MARKET_EVIDENCE_DATE:-$(TZ=America/New_York date +%F)}}"
TIMEOUT_SECONDS="${MARKET_EVIDENCE_TIMEOUT_SECONDS:-1800}"
LOG_DIR="${MARKET_EVIDENCE_LOG_DIR:-/var/log/stevetrading}"
LOG_FILE="${MARKET_EVIDENCE_LOG_FILE:-$LOG_DIR/market-evidence.log}"
SKIP_NON_TRADING_DAYS="${MARKET_EVIDENCE_SKIP_NON_TRADING_DAYS:-1}"
REQUIRE_PREFLIGHT="${MARKET_EVIDENCE_REQUIRE_PREFLIGHT:-1}"
PREFLIGHT_WAIT_SECONDS="${MARKET_EVIDENCE_PREFLIGHT_WAIT_SECONDS:-600}"
PREFLIGHT_POLL_SECONDS="${MARKET_EVIDENCE_PREFLIGHT_POLL_SECONDS:-5}"
REQUIRE_THETADATA_HEALTH="${MARKET_EVIDENCE_REQUIRE_THETADATA_HEALTH:-1}"
THETADATA_HEALTH_URL="${MARKET_EVIDENCE_THETADATA_HEALTH_URL:-${THETADATA_BASE_URL:-http://127.0.0.1:25503}/v3/option/list/expirations?symbol=SPY&format=json}"
THETADATA_HEALTH_TIMEOUT_SECONDS="${MARKET_EVIDENCE_THETADATA_HEALTH_TIMEOUT_SECONDS:-300}"
THETADATA_HEALTH_POLL_SECONDS="${MARKET_EVIDENCE_THETADATA_HEALTH_POLL_SECONDS:-5}"
COLLECT_SCRIPT="${MARKET_EVIDENCE_COLLECT_SCRIPT:-scripts/collect_market_evidence.sh}"
if [[ -d /opt/stevetrading/shared ]]; then
  DEFAULT_RUNTIME_ROOT=/opt/stevetrading/shared
else
  DEFAULT_RUNTIME_ROOT="$ROOT"
fi
STEVE_REF_ROOT="${STEVE_REF_ROOT:-$DEFAULT_RUNTIME_ROOT/Data-Preprocessor}"
ANALYSIS_DIR="${ANALYSIS_DIR:-$DEFAULT_RUNTIME_ROOT/live_runtime/analysis}"
CAPTURE_DIR="${CAPTURE_DIR:-$DEFAULT_RUNTIME_ROOT/live_runtime/feature-capture}"
PAYLOAD_DIR="${PAYLOAD_DIR:-$DEFAULT_RUNTIME_ROOT/payload_examples}"
PREFLIGHT_STATUS_FILE="${MARKET_EVIDENCE_PREFLIGHT_STATUS_FILE:-$ANALYSIS_DIR/market_evidence_preflight_${TARGET_DATE//-/}.json}"
CAPTURE_SMOKE_MIN_ROWS="${MARKET_EVIDENCE_CAPTURE_SMOKE_MIN_ROWS:-5}"
CAPTURE_SMOKE_JSON="${MARKET_EVIDENCE_CAPTURE_SMOKE_JSON:-$ANALYSIS_DIR/capture_v2_sidecar_smoke_${TARGET_DATE//-/}.json}"
ALLOW_MISSING_OPTION_SURFACES="${MARKET_EVIDENCE_ALLOW_MISSING_OPTION_SURFACES:-1}"

resolve_runner() {
  local env_value="$1"
  local repo_candidate="$2"
  local shared_candidate="$3"
  local path_name="$4"
  if [[ -n "$env_value" ]]; then
    printf '%s\n' "$env_value"
  elif [[ -x "$repo_candidate" ]]; then
    printf '%s\n' "$repo_candidate"
  elif [[ -x "$shared_candidate" ]]; then
    printf '%s\n' "$shared_candidate"
  elif command -v "$path_name" >/dev/null 2>&1; then
    command -v "$path_name"
  else
    printf '%s\n' "$repo_candidate"
  fi
}

mkdir -p "$LOG_DIR"

json_escape() {
  local value="${1:-}"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\n'/\\n}"
  printf '%s' "$value"
}

write_preflight_status() {
  local status="$1"
  local rc="$2"
  local detail="$3"
  mkdir -p "$(dirname "$PREFLIGHT_STATUS_FILE")"
  {
    printf '{\n'
    printf '  "generated_at": "%s",\n' "$(date -u +%FT%TZ)"
    printf '  "target_date": "%s",\n' "$(json_escape "$TARGET_DATE")"
    printf '  "target_stamp": "%s",\n' "$(json_escape "${TARGET_DATE//-/}")"
    printf '  "mode": "preflight",\n'
    printf '  "status": "%s",\n' "$(json_escape "$status")"
    printf '  "returncode": %s,\n' "$rc"
    printf '  "detail": "%s"\n' "$(json_escape "$detail")"
    printf '}\n'
  } > "$PREFLIGHT_STATUS_FILE"
}

require_preflight_status_ok() {
  if [[ "$REQUIRE_PREFLIGHT" != "1" ]]; then
    echo "WARN: MARKET_EVIDENCE_REQUIRE_PREFLIGHT=$REQUIRE_PREFLIGHT; skipping preflight status gate" >&2
    return 0
  fi
  local deadline=$((SECONDS + PREFLIGHT_WAIT_SECONDS))
  local tmp rc output
  while true; do
    if [[ ! -s "$PREFLIGHT_STATUS_FILE" ]]; then
      if (( SECONDS >= deadline )); then
        echo "RESULT: FAILED - missing same-day preflight status: $PREFLIGHT_STATUS_FILE" >&2
        return 2
      fi
      echo "WAIT: missing same-day preflight status; waiting for recovered preflight: $PREFLIGHT_STATUS_FILE" >&2
      sleep "$PREFLIGHT_POLL_SECONDS"
      continue
    fi
    tmp="$(mktemp)"
    set +e
    "$BASILISP_BIN" run scripts/check_market_evidence_preflight.lpy -- \
      --status-file "$PREFLIGHT_STATUS_FILE" \
      --target-date "$TARGET_DATE" >"$tmp" 2>&1
    rc=$?
    set -e
    output="$(cat "$tmp")"
    rm -f "$tmp"
    if [[ "$rc" == "0" ]]; then
      printf '%s\n' "$output"
      return 0
    fi
    if [[ "$output" == *"predates scheduled preflight"* && "$SECONDS" -lt "$deadline" ]]; then
      printf '%s\n' "WAIT: $output; waiting for recovered preflight" >&2
      sleep "$PREFLIGHT_POLL_SECONDS"
      continue
    fi
    printf '%s\n' "$output" >&2
    return "$rc"
  done
}

wait_for_thetadata_health() {
  if [[ "$REQUIRE_THETADATA_HEALTH" != "1" ]]; then
    echo "WARN: MARKET_EVIDENCE_REQUIRE_THETADATA_HEALTH=$REQUIRE_THETADATA_HEALTH; skipping ThetaData health gate" >&2
    return 0
  fi
  "$BASILISP_BIN" run scripts/wait_thetadata_health.lpy -- \
    --url "$THETADATA_HEALTH_URL" \
    --timeout-seconds "$THETADATA_HEALTH_TIMEOUT_SECONDS" \
    --poll-seconds "$THETADATA_HEALTH_POLL_SECONDS"
}

{
  echo
  echo "================================================================"
  echo "  Market evidence run - $(date)"
  echo "================================================================"
  echo "mode=$MODE target_date=$TARGET_DATE root=$ROOT"

  cd "$ROOT"
  export STEVE_REPO_ROOT="$ROOT"
  export STEVE_REF_ROOT
  export BASILISP_BIN
  BASILISP_BIN="$(resolve_runner "${BASILISP_BIN:-}" "$ROOT/.venv/bin/basilisp" "$STEVE_REF_ROOT/.venv/bin/basilisp" basilisp)"
  export ANALYSIS_DIR
  export CAPTURE_DIR
  export PAYLOAD_DIR

  if [[ ! -x "$BASILISP_BIN" ]]; then
    echo "RESULT: FAILED - Basilisp runner not executable: $BASILISP_BIN" >&2
    if [[ "$MODE" == "preflight" ]]; then
      write_preflight_status "error" 2 "Basilisp runner not executable: $BASILISP_BIN"
    fi
    exit 2
  fi

  if [[ "$SKIP_NON_TRADING_DAYS" == "1" ]]; then
    if "$BASILISP_BIN" run scripts/is_trading_day.lpy -- "$TARGET_DATE"; then
      :
    else
      rc=$?
      if [[ "$rc" == "1" ]]; then
        echo "RESULT: SKIPPED - non-trading day $TARGET_DATE"
        exit 0
      fi
      echo "RESULT: FAILED - trading-day calendar check failed exit=$rc" >&2
      exit "$rc"
    fi
  fi

  case "$MODE" in
    preflight)
      set +e
      timeout "$TIMEOUT_SECONDS" "$COLLECT_SCRIPT" \
        --preflight \
        --target-date "$TARGET_DATE"
      rc=$?
      set -e
      if [[ "$rc" == "0" ]]; then
        write_preflight_status "ok" 0 "preflight passed"
        echo "RESULT: SUCCESS - preflight $(date)"
      else
        write_preflight_status "error" "$rc" "preflight failed"
        echo "RESULT: FAILED - preflight exit=$rc" >&2
      fi
      exit "$rc"
      ;;
    collect)
      require_preflight_status_ok
      wait_for_thetadata_health
      timeout "$TIMEOUT_SECONDS" "$COLLECT_SCRIPT" \
        --target-date "$TARGET_DATE"
      ;;
    capture-smoke)
      require_preflight_status_ok
      wait_for_thetadata_health
      capture_smoke_cmd=("$BASILISP_BIN" run scripts/capture_v2_sidecar_check.lpy --
        --capture "$CAPTURE_DIR/live_features_${TARGET_DATE//-/}.npz" \
        --target-date "$TARGET_DATE" \
        --min-rows "$CAPTURE_SMOKE_MIN_ROWS" \
        --sidecar-row-limit "$CAPTURE_SMOKE_MIN_ROWS" \
        --fast-json \
        --out-json "$CAPTURE_SMOKE_JSON")
      if [[ "$ALLOW_MISSING_OPTION_SURFACES" == "1" ]]; then
        capture_smoke_cmd+=(--allow-missing-option-surfaces)
      fi
      timeout "$TIMEOUT_SECONDS" "${capture_smoke_cmd[@]}"
      ;;
    dry-run)
      timeout "$TIMEOUT_SECONDS" "$COLLECT_SCRIPT" \
        --dry-run \
        --target-date "$TARGET_DATE"
      ;;
    *)
      echo "RESULT: FAILED - unknown MARKET_EVIDENCE_MODE=$MODE" >&2
      exit 2
      ;;
  esac

  echo "RESULT: SUCCESS - $(date)"
} >> "$LOG_FILE" 2>&1
