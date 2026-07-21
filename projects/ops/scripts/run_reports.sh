#!/usr/bin/env bash
# Build Tran reports from the Data-Preprocessor reference tree.
#
# This is intentionally separate from the live trading systemd units. It reads
# Alpaca/report state and writes report-viewer/public, but it does not start,
# stop, or signal the trading runner.
set -uo pipefail

REF_ROOT="${STEVE_REF_ROOT:-/opt/stevetrading/shared/Data-Preprocessor}"
BASILISP_ROOT="${STEVETRADING_BASILISP_ROOT:-/opt/stevetrading/current}"
if [[ ! -f "$BASILISP_ROOT/scripts/validate_report_day.lpy" \
      && -f "/opt/stevetrading/shared/stevetrading-basilisp/scripts/validate_report_day.lpy" ]]; then
    BASILISP_ROOT="/opt/stevetrading/shared/stevetrading-basilisp"
fi
BASILISP="${BASILISP_BIN:-$BASILISP_ROOT/.venv/bin/basilisp}"
if [[ ! -x "$BASILISP" && -x "/opt/stevetrading/shared/Data-Preprocessor/.venv/bin/basilisp" ]]; then
    BASILISP="/opt/stevetrading/shared/Data-Preprocessor/.venv/bin/basilisp"
fi
VERCEL="${VERCEL_BIN:-vercel}"
MODE="${REPORTS_MODE:-skip-deploy}"
TIMEOUT_SECONDS="${REPORTS_TIMEOUT_SECONDS:-900}"
DEPLOY_ATTEMPTS="${REPORTS_DEPLOY_ATTEMPTS:-3}"
VERIFY_ATTEMPTS="${REPORTS_VERIFY_ATTEMPTS:-9}"
BUILD_ATTEMPTS="${REPORTS_BUILD_ATTEMPTS:-3}"
BUILD_RETRY_SECONDS="${REPORTS_BUILD_RETRY_SECONDS:-300}"
if [[ -n "${REPORTS_LOG_FILE:-}" && -z "${REPORTS_LOG_DIR:-}" ]]; then
    LOG_DIR="$(dirname "$REPORTS_LOG_FILE")"
else
    LOG_DIR="${REPORTS_LOG_DIR:-/var/log/stevetrading}"
fi
LOG_FILE="${REPORTS_LOG_FILE:-$LOG_DIR/reports.log}"
mkdir -p "$LOG_DIR"
if [[ -n "${REPORTS_TARGET_DATE:-}" ]]; then
    TODAY="$REPORTS_TARGET_DATE"
elif [[ -n "${REPORTS_DATE:-}" ]]; then
    TODAY="$REPORTS_DATE"
else
    if [[ -x "$BASILISP" && -f "$BASILISP_ROOT/scripts/report_target_date.lpy" ]]; then
        if TODAY="$(
            cd "$BASILISP_ROOT" &&
                "$BASILISP" run scripts/report_target_date.lpy --
        )"; then
            :
        else
            rc=$?
            {
                echo
                echo "================================================================"
                echo "  Reports build run - $(date)"
                echo "  RESULT: FAILED could not determine completed report target date exit=$rc - $(date)"
            } >> "$LOG_FILE" 2>&1
            exit "$rc"
        fi
    else
        TODAY="$(TZ=America/New_York date +%F)"
    fi
fi

ensure_accounts_nav_target() {
    local reports_dir="$REF_ROOT/report-viewer/public/reports"
    local singular="$reports_dir/account"
    local plural="$reports_dir/accounts"

    if [[ ! -d "$singular" ]]; then
        return 0
    fi
    if [[ -L "$plural" ]]; then
        rm "$plural"
    fi
    if [[ -d "$plural" ]]; then
        rm -rf "$plural"
    elif [[ -e "$plural" ]]; then
        rm -f "$plural"
    fi
    cp -a "$singular" "$plural"
}

normalize_report_nav() {
    local reports_dir="$REF_ROOT/report-viewer/public/reports"
    if [[ ! -d "$reports_dir" ]]; then
        return 0
    fi
    find "$reports_dir" -type f -name '*.html' -print0 | while IFS= read -r -d '' html; do
        perl -0pi \
            -e 's#/reports/account/index\.html#/reports/accounts/index.html#g;' \
            -e 's#<a href="/reports/status/index\.html">Status</a>#<a href="/reports/status/index.html">System</a>#g;' \
            -e 's#(<a href="/reports/accounts/index\.html">Accounts</a>)\s*(<a href="/index\.html" class="back">[^<]+</a>)\s*(<a href="/reports/status/index\.html">System</a>)#$1\n        $3\n        $2#g;' \
            "$html"
    done
}

build_daily_report_index() {
    local daily_dir="$REF_ROOT/report-viewer/public/reports/daily"
    local weekly_dir="$REF_ROOT/report-viewer/public/reports/weekly"
    local accounts_dir="$REF_ROOT/report-viewer/public/reports/accounts"
    if [[ ! -x "$BASILISP" || ! -f "$BASILISP_ROOT/scripts/build_daily_report_index.lpy" ]]; then
        echo "  RESULT: FAILED - missing Basilisp daily index builder at $BASILISP_ROOT or runner not executable: $BASILISP"
        return 2
    fi
    (
        cd "$BASILISP_ROOT" || exit 2
        "$BASILISP" run scripts/build_daily_report_index.lpy -- \
            --daily-dir "$daily_dir" \
            --weekly-dir "$weekly_dir" \
            --accounts-dir "$accounts_dir"
    )
}

build_reports_overview_index() {
    local reports_dir="$REF_ROOT/report-viewer/public/reports"
    if [[ ! -x "$BASILISP" || ! -f "$BASILISP_ROOT/scripts/build_reports_overview_index.lpy" ]]; then
        echo "  RESULT: FAILED - missing Basilisp reports overview builder at $BASILISP_ROOT or runner not executable: $BASILISP"
        return 2
    fi
    (
        cd "$BASILISP_ROOT" || exit 2
        "$BASILISP" run scripts/build_reports_overview_index.lpy -- \
            --reports-dir "$reports_dir"
    )
}

# The established, full report UI is the only public report surface.
render_classic_reports() {
    local python="$REF_ROOT/.venv/bin/python3"
    local iso_week
    if [[ ! -x "$python" ]]; then
        echo "  RESULT: FAILED - missing classic report renderer: $python"
        return 2
    fi
    iso_week="$(date -d "$TODAY" +%G-W%V)"
    (
        cd "$REF_ROOT" || exit 2
        "$python" scripts_5yr/live/reports/build_daily.py --date "$TODAY" &&
        "$python" scripts_5yr/live/reports/build_weekly.py --week "$iso_week" &&
        "$python" scripts_5yr/live/reports/build_account.py --all &&
        "$python" scripts_5yr/live/reports/build_index.py &&
        "$python" scripts_5yr/live/reports/build_dir_indexes.py
    )
}

render_daily_report() {
    local daily_dir="$REF_ROOT/report-viewer/public/reports/daily"
    if [[ ! -x "$BASILISP" || ! -f "$BASILISP_ROOT/scripts/render_daily_report.lpy" ]]; then
        echo "  RESULT: FAILED - missing Basilisp daily renderer at $BASILISP_ROOT or runner not executable: $BASILISP"
        return 2
    fi
    (
        cd "$BASILISP_ROOT" || exit 2
        "$BASILISP" run scripts/render_daily_report.lpy -- \
            --daily-dir "$daily_dir" \
            --date "$TODAY"
    )
}

generate_daily_validation() {
    local daily_dir="$REF_ROOT/report-viewer/public/reports/daily"
    local orders_cache_dir="${REPORTS_ORDERS_CACHE_DIR:-$REF_ROOT/pipeline_data/report_cache}"
    local state_fixture="${REPORTS_STATE_FIXTURE:-}"
    local args=(--daily-dir "$daily_dir" --date "$TODAY" --ref-root "$REF_ROOT")
    if [[ -d "$orders_cache_dir" ]]; then
        args+=(--orders-cache-dir "$orders_cache_dir" --allow-cache)
    fi
    if [[ -n "$state_fixture" ]]; then
        args+=(--state-fixture "$state_fixture")
    fi
    if [[ ! -x "$BASILISP" || ! -f "$BASILISP_ROOT/scripts/generate_daily_validation.lpy" ]]; then
        echo "  RESULT: FAILED - missing Basilisp daily validation generator at $BASILISP_ROOT or runner not executable: $BASILISP"
        return 2
    fi
    (
        cd "$BASILISP_ROOT" || exit 2
        "$BASILISP" run scripts/generate_daily_validation.lpy -- "${args[@]}"
    )
}

render_weekly_report() {
    local daily_dir="$REF_ROOT/report-viewer/public/reports/daily"
    local weekly_dir="$REF_ROOT/report-viewer/public/reports/weekly"
    local week_label
    if week_label="$(date -d "$TODAY" +%G-W%V)"; then
        :
    else
        echo "  RESULT: FAILED could not determine ISO week for $TODAY"
        return 2
    fi
    if [[ ! -x "$BASILISP" || ! -f "$BASILISP_ROOT/scripts/render_weekly_report.lpy" ]]; then
        echo "  RESULT: FAILED - missing Basilisp weekly renderer at $BASILISP_ROOT or runner not executable: $BASILISP"
        return 2
    fi
    (
        cd "$BASILISP_ROOT" || exit 2
        "$BASILISP" run scripts/render_weekly_report.lpy -- \
            --daily-dir "$daily_dir" \
            --weekly-dir "$weekly_dir" \
            --week "$week_label"
    )
}

render_account_reports() {
    local daily_dir="$REF_ROOT/report-viewer/public/reports/daily"
    local accounts_dir="$REF_ROOT/report-viewer/public/reports/accounts"
    if [[ ! -x "$BASILISP" || ! -f "$BASILISP_ROOT/scripts/render_account_reports.lpy" ]]; then
        echo "  RESULT: FAILED - missing Basilisp account renderer at $BASILISP_ROOT or runner not executable: $BASILISP"
        return 2
    fi
    (
        cd "$BASILISP_ROOT" || exit 2
        "$BASILISP" run scripts/render_account_reports.lpy -- \
            --daily-dir "$daily_dir" \
            --accounts-dir "$accounts_dir"
    )
}

repair_daily_report_index() {
    local daily_dir="$REF_ROOT/report-viewer/public/reports/daily"
    if [[ ! -x "$BASILISP" || ! -f "$BASILISP_ROOT/scripts/repair_daily_report_index.lpy" ]]; then
        echo "  RESULT: FAILED - missing Basilisp daily index repair at $BASILISP_ROOT or runner not executable: $BASILISP"
        return 2
    fi
    (
        cd "$BASILISP_ROOT" || exit 2
        "$BASILISP" run scripts/repair_daily_report_index.lpy -- \
            --daily-dir "$daily_dir" \
            --date "$TODAY"
    )
}

deploy_reports_site() {
    if [[ "$MODE" == "skip-deploy" ]]; then
        echo "=== skipping Vercel deploy ==="
        return 0
    fi
    (
        cd "$REF_ROOT/report-viewer" || exit 2
        deploy_out="$("$VERCEL" --prod --yes 2>&1 | tee /dev/stderr)"
        # Vercel also prints its persistent project alias (for example
        # report-viewer-omega.vercel.app).  That alias may still point at an
        # older deployment, so never use the last URL in the CLI output.
        # Match only the immutable deployment hostname that this command made.
        prod_url="$(printf '%s\n' "$deploy_out" | grep -oE 'https://report-viewer-[a-z0-9]+-andrew-van-dykes-projects\.vercel\.app' | head -1 || true)"
        if [[ -n "${prod_url:-}" ]]; then
            "$VERCEL" alias set "${prod_url#https://}" tran-trading-reports.vercel.app || \
                echo "  warning: alias to tran-trading-reports.vercel.app failed (non-fatal)"
        fi
    )
}

verify_public_daily_report() {
    if [[ "$MODE" == "skip-deploy" ]]; then
        return 0
    fi
    if [[ "$MODE" == "backfill" ]]; then
        echo "  Skipping single-date public propagation check in backfill mode"
        return 0
    fi
    if ! command -v curl >/dev/null 2>&1; then
        echo "  warning: curl unavailable; skipping public report propagation check"
        return 0
    fi
    local base_url="${REPORTS_PUBLIC_BASE_URL:-https://tran-trading-reports.vercel.app}"
    local compact_date="${TODAY//-/}"
    local daily_url="${base_url%/}/reports/daily/${compact_date}.html"
    local index_url="${base_url%/}/reports/daily/"
    local daily_body
    local attempt
    echo "  Verifying public daily report propagation: $daily_url"
    for attempt in $(seq 1 "$VERIFY_ATTEMPTS"); do
        daily_body="$(curl -fsS --max-redirs 0 "$daily_url" 2>/dev/null || true)"
        if [[ -n "$daily_body" ]] &&
           ! grep -qi '<title>Login' <<< "$daily_body" &&
           ! grep -qi 'name="password"' <<< "$daily_body" &&
           grep -Eq "(Daily Report|Per-Account Detail|${TODAY}|${compact_date})" <<< "$daily_body" &&
           curl -fsS "$index_url" 2>/dev/null | grep -q "${compact_date}.html"; then
            echo "  Public daily report verified on attempt $attempt"
            return 0
        fi
        sleep 10
    done
    echo "  Public report verification diagnostic:"
    curl -fsS -I "$daily_url" 2>/dev/null | sed 's/^/    daily: /' || true
    curl -fsS -I "$index_url" 2>/dev/null | sed 's/^/    index: /' || true
    echo "  RESULT: FAILED public report propagation check for $daily_url - $(date)"
    return 1
}

verify_public_classic_overview() {
    if [[ "$MODE" == "skip-deploy" ]]; then
        return 0
    fi
    if ! command -v curl >/dev/null 2>&1; then
        echo "  warning: curl unavailable; skipping public overview verification"
        return 0
    fi
    local base_url="${REPORTS_PUBLIC_BASE_URL:-https://tran-trading-reports.vercel.app}"
    local overview_url="${base_url%/}/reports/index.html?deployment_check=$(date +%s)"
    local overview_body
    overview_body="$(curl -fsS --max-redirs 0 "$overview_url" 2>/dev/null || true)"
    if grep -q 'Current Week' <<< "$overview_body" && ! grep -q 'Latest Daily' <<< "$overview_body"; then
        echo "  Public classic overview verified"
        return 0
    fi
    echo "  RESULT: FAILED public overview is not the classic report UI"
    return 1
}

verify_local_daily_report_index() {
    if [[ "$MODE" == "backfill" ]]; then
        return 0
    fi
    local daily_dir="$REF_ROOT/report-viewer/public/reports/daily"
    local compact_date="${TODAY//-/}"
    local daily_html="$daily_dir/${compact_date}.html"
    local index_html="$daily_dir/index.html"
    if [[ ! -f "$daily_html" ]]; then
        echo "  RESULT: FAILED missing local daily report HTML: $daily_html - $(date)"
        return 1
    fi
    if [[ ! -f "$index_html" ]]; then
        echo "  RESULT: FAILED missing local daily index: $index_html - $(date)"
        return 1
    fi
    if ! grep -q "${compact_date}.html" "$index_html"; then
        echo "  RESULT: FAILED local daily index does not link ${compact_date}.html - $(date)"
        return 1
    fi
}

publish_reports_site() {
    local attempt
    if [[ "$MODE" == "skip-deploy" ]]; then
        deploy_reports_site
        return $?
    fi
    for attempt in $(seq 1 "$DEPLOY_ATTEMPTS"); do
        echo "  Publication attempt $attempt/$DEPLOY_ATTEMPTS"
        if deploy_reports_site && verify_public_daily_report && verify_public_classic_overview; then
            return 0
        fi
        if [[ "$attempt" != "$DEPLOY_ATTEMPTS" ]]; then
            echo "  Publication attempt $attempt failed; retrying in 30s"
            sleep 30
        fi
    done
    echo "  RESULT: FAILED report publication after $DEPLOY_ATTEMPTS attempts - $(date)"
    return 1
}

export STEVE_REPO_ROOT="$BASILISP_ROOT"
export STEVETRADING_BASILISP_ROOT="$BASILISP_ROOT"
export BASILISP_BIN="$BASILISP"

{
    echo
    echo "================================================================"
    echo "  Reports build run - $(date)"
    echo "  Reports target date - $TODAY"
    echo "  Reports mode - $MODE"
    echo "  Reports build attempts - $BUILD_ATTEMPTS"
    echo "  Reports build retry seconds - $BUILD_RETRY_SECONDS"
    echo "  Ref root - $REF_ROOT"
    echo "  Basilisp root - $BASILISP_ROOT"
    echo "  Basilisp bin - $BASILISP"
    echo "  Vercel bin - $VERCEL"
    echo "================================================================"

    cd "$REF_ROOT" || exit 2

    build_mode="skip-deploy"
    if [[ "$MODE" == "backfill" ]]; then
        build_mode="backfill"
    fi

    build_ok=0
    build_rc=1
    for build_attempt in $(seq 1 "$BUILD_ATTEMPTS"); do
        echo "  Report artifact build attempt $build_attempt/$BUILD_ATTEMPTS - $(date)"
        if [[ "$build_mode" == "backfill" ]]; then
            build_ok=1
            build_rc=0
            break
        elif generate_daily_validation; then
            build_ok=1
            build_rc=0
            break
        else
            build_rc=$?
            echo "  Report artifact build attempt $build_attempt/$BUILD_ATTEMPTS failed exit=$build_rc - $(date)"
            if [[ "$build_attempt" != "$BUILD_ATTEMPTS" ]]; then
                echo "  Retrying report artifact build in ${BUILD_RETRY_SECONDS}s"
                sleep "$BUILD_RETRY_SECONDS"
            fi
        fi
    done

    if [[ "$build_ok" == "1" ]]; then
        ensure_accounts_nav_target
        normalize_report_nav
        if render_classic_reports; then
            :
        else
            rc=$?
            echo "  RESULT: FAILED classic report render exit=$rc - $(date)"
            exit "$rc"
        fi
        if repair_daily_report_index; then
            :
        else
            rc=$?
            echo "  RESULT: FAILED daily report index repair exit=$rc - $(date)"
            exit "$rc"
        fi
        if verify_local_daily_report_index; then
            :
        else
            rc=$?
            echo "  RESULT: FAILED local daily report index verification exit=$rc - $(date)"
            exit "$rc"
        fi
        daily_dir="$REF_ROOT/report-viewer/public/reports/daily"
        audit_args=(--daily-dir "$daily_dir" --write-manifests --require-manifests)
        if [[ "$MODE" == "backfill" ]]; then
            audit_args+=(--all)
        else
            audit_args+=(--date "$TODAY")
        fi
        if [[ -x "$BASILISP" && -f "$BASILISP_ROOT/scripts/audit_daily_report_validations.lpy" ]]; then
            echo "  Auditing daily report validation artifacts"
            if (
                cd "$BASILISP_ROOT"
                "$BASILISP" run scripts/audit_daily_report_validations.lpy -- "${audit_args[@]}"
            ); then
                :
            else
                rc=$?
                echo "  WARN: report validation audit found issues exit=$rc; publishing report with visible validation issues - $(date)"
            fi
            if [[ "$MODE" != "backfill" && ! -f "$daily_dir/${TODAY//-/}.validation.json" ]]; then
                if expected_latest="$(
                    cd "$BASILISP_ROOT"
                    "$BASILISP" run scripts/previous_trading_day.lpy -- "$TODAY"
                )"; then
                    :
                else
                    rc=$?
                    echo "  RESULT: FAILED could not determine previous trading day for $TODAY exit=$rc - $(date)"
                    exit "$rc"
                fi
                latest_validation="$(
                    find "$daily_dir" -maxdepth 1 -type f -name '*.validation.json' -printf '%f\n' 2>/dev/null \
                        | sort \
                        | tail -n 1
                )"
                if [[ -n "$latest_validation" ]]; then
                    latest_date="${latest_validation%.validation.json}"
                    latest_date="${latest_date:0:4}-${latest_date:4:2}-${latest_date:6:2}"
                    if [[ "$latest_date" != "$expected_latest" ]]; then
                        echo "  RESULT: FAILED latest report validation artifact is stale: latest=$latest_date expected=$expected_latest - $(date)"
                        exit 1
                    fi
                    echo "  Auditing latest existing daily validation artifact: $latest_date"
                    if (
                        cd "$BASILISP_ROOT"
                        "$BASILISP" run scripts/audit_daily_report_validations.lpy -- \
                            --daily-dir "$daily_dir" --date "$latest_date" --write-manifests --require-manifests
                    ); then
                        :
                    else
                        rc=$?
                        echo "  WARN: latest report validation audit found issues exit=$rc; publishing report with visible validation issues - $(date)"
                    fi
                else
                    echo "  RESULT: FAILED no prior daily validation artifact found for expected latest trading day $expected_latest - $(date)"
                    exit 1
                fi
            fi
        else
            echo "  RESULT: FAILED - missing Basilisp report validation audit at $BASILISP_ROOT or runner not executable: $BASILISP" >&2
            exit 2
        fi
        if publish_reports_site; then
            :
        else
            rc=$?
            echo "  RESULT: FAILED report publication exit=$rc - $(date)"
            exit "$rc"
        fi
        echo "  RESULT: SUCCESS - $(date)"
        exit 0
    else
        echo "  RESULT: FAILED report artifact build exit=$build_rc - $(date)"
        exit "$build_rc"
    fi
} >> "$LOG_FILE" 2>&1
