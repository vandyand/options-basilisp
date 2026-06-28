#!/usr/bin/env bash
# Build Tran reports from the Data-Preprocessor reference tree.
#
# This is intentionally separate from the live trading systemd units. It reads
# Alpaca/report state and writes report-viewer/public, but it does not start,
# stop, or signal the trading runner.
set -uo pipefail

REF_ROOT="${STEVE_REF_ROOT:-/opt/stevetrading/shared/Data-Preprocessor}"
MODE="${REPORTS_MODE:-skip-deploy}"
TIMEOUT_SECONDS="${REPORTS_TIMEOUT_SECONDS:-900}"
LOG_DIR="${REPORTS_LOG_DIR:-/var/log/stevetrading}"
LOG_FILE="${REPORTS_LOG_FILE:-$LOG_DIR/reports.log}"

mkdir -p "$LOG_DIR"

{
    echo
    echo "================================================================"
    echo "  Reports build run - $(date)"
    echo "================================================================"

    cd "$REF_ROOT" || exit 2

    if [[ -x "$REF_ROOT/.venv/bin/python" ]]; then
        export PATH="$REF_ROOT/.venv/bin:$PATH"
    fi

    if timeout "$TIMEOUT_SECONDS" bash deploy_reports.sh "$MODE"; then
        echo "  RESULT: SUCCESS - $(date)"
        exit 0
    else
        rc=$?
        echo "  RESULT: FAILED exit=$rc - $(date)"
        exit "$rc"
    fi
} >> "$LOG_FILE" 2>&1
