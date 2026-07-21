#!/usr/bin/env bash
# Run the Basilisp test suite (pytest wrapper) from the repo root.
# Usage:
#   scripts/test.sh [pytest-args...]          # full suite, existing behavior
#   scripts/test.sh inner [pytest-args...]    # fastest deterministic unit loop
#   scripts/test.sh fast [pytest-args...]     # skip heavier ops workflow/slow tests
#   scripts/test.sh changed [pytest-args...]  # run tests inferred from git-changed files
#   scripts/test.sh scope FILE... [-- pytest-args...] # run tests inferred from explicit files
#   scripts/test.sh map FILE...                # print tests inferred from explicit files
#   scripts/test.sh ops [pytest-args...]      # ops scripts/workflows only
#   scripts/test.sh status [pytest-args...]   # status dashboard contracts
#   scripts/test.sh reports [pytest-args...]  # report/report-metrics contracts
#   scripts/test.sh capture [pytest-args...]  # Steve v2 capture writer + sidecar checks
#   scripts/test.sh theta-core [pytest-args...] # fast in-process ThetaData schema/adapter tests
#   scripts/test.sh theta-smoke [pytest-args...] # ThetaData schema/payload smoke tests
#   scripts/test.sh market-evidence-core [pytest-args...] # market-evidence artifact core tests
#   scripts/test.sh market-evidence-smoke [pytest-args...] # market-evidence workflow smoke tests
#   scripts/test.sh market-evidence-deploy [pytest-args...] # slower market-evidence deploy gate
#   scripts/test.sh market-evidence-status-deploy [pytest-args...] # slower status CLI proof tests
#   scripts/test.sh replay-golden [pytest-args...] # slower replay/restart E2E proof tests
#   scripts/test.sh parity-smoke              # small feature-parity edit-loop sentinel set
#   scripts/test.sh parity [pytest-args...]   # feature parity hot path
#   scripts/test.sh full [pytest-args...]     # explicit full suite
set -euo pipefail
REPO="${STEVE_REPO_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
BASILISP="${BASILISP_BIN:-$REPO/.venv/bin/basilisp}"
if [[ ! -x "$BASILISP" && -f /etc/stevetrading/env ]]; then
  # Deployed releases keep the shared virtualenv path in the ops env file.
  set -a
  # shellcheck disable=SC1091
  . /etc/stevetrading/env
  set +a
  BASILISP="${BASILISP_BIN:-$BASILISP}"
fi
cd "$REPO"
export STEVE_REPO_ROOT="$REPO"

run_existing_tests() {
  local selected=()
  local extra=()
  local target path
  while [[ "$#" -gt 0 ]]; do
    if [[ "$1" == "--" ]]; then
      shift
      extra=("$@")
      break
    fi
    target="$1"
    shift
    path="${target%%::*}"
    if [[ -e "$path" ]]; then
      selected+=("$target")
    else
      printf 'WARN: skipping missing default test target: %s\n' "$target" >&2
    fi
  done
  exec "$BASILISP" test -m "not slow" "${selected[@]}" "${extra[@]}"
}

run_existing_tests_including_slow() {
  local selected=()
  local extra=()
  local target path
  while [[ "$#" -gt 0 ]]; do
    if [[ "$1" == "--" ]]; then
      shift
      extra=("$@")
      break
    fi
    target="$1"
    shift
    path="${target%%::*}"
    if [[ -e "$path" ]]; then
      selected+=("$target")
    else
      printf 'WARN: skipping missing default test target: %s\n' "$target" >&2
    fi
  done
  exec "$BASILISP" test "${selected[@]}" "${extra[@]}"
}

run_selected_tests() {
  local label="${STEVE_TEST_TARGET_LABEL:-changed-file test targets}"
  local selected=()
  local extra=()
  local target path
  while [[ "$#" -gt 0 ]]; do
    if [[ "$1" == "--" ]]; then
      shift
      extra=("$@")
      break
    fi
    target="$1"
    shift
    path="${target%%::*}"
    if [[ -e "$path" ]]; then
      selected+=("$target")
    fi
  done
  if [[ "${#selected[@]}" -eq 0 ]]; then
    printf 'No changed-file test targets mapped; no tests run.\n' >&2
    return 0
  fi
  printf 'Running %s:\n' "$label" >&2
  printf '  %s\n' "${selected[@]}" >&2
  exec "$BASILISP" test -m "not slow" "${selected[@]}" "${extra[@]}"
}

changed_files() {
  if [[ -n "${STEVE_TEST_CHANGED_FILES:-}" ]]; then
    printf '%s\n' "$STEVE_TEST_CHANGED_FILES"
    return
  fi
  {
    git diff --name-only --diff-filter=ACMRTUXB HEAD
    git ls-files --others --exclude-standard
  } | sort -u
}

explicit_files() {
  printf '%s\n' "$@"
}

append_target() {
  local target="$1"
  local existing
  for existing in "${targets[@]:-}"; do
    if [[ "$existing" == "$target" ]]; then
      return
    fi
  done
  targets+=("$target")
}

reject_python_test_target() {
  local target="$1"
  printf 'ERROR: Python test targets are not supported; port to Basilisp .lpy: %s\n' "$target" >&2
  return 2
}

targets_for_file_stream() {
  local file
  local -n targets_ref="$1"
  shift
  targets=()
  while IFS= read -r file; do
    [[ -z "$file" ]] && continue
    case "$file" in
      tests/*.lpy|tests/**/*.lpy)
        append_target "$file"
        ;;
      tests/*.py|tests/**/*.py)
        reject_python_test_target "$file"
        ;;
      pyproject.toml|scripts/test.sh)
        append_target tests/test_toolchain.lpy
        ;;
      components/feature-parity.core/*|scripts/live_feature_parity_*|scripts/matched_feature_parity_report.lpy|scripts/summarize_matched_feature_parity.lpy|scripts/neutralization_audit.lpy|scripts/audit_captured_source_parity.lpy|scripts/build_verified_feature_corpus.lpy)
        append_target tests/feature_parity
        ;;
      scripts/market_evidence_readiness.lpy)
        append_target tests/feature_parity
        append_target tests/ops/test_market_evidence_readiness.lpy
        ;;
      scripts/market_evidence_manifest.lpy)
        append_target tests/ops/test_market_evidence_manifest_smoke.lpy
        ;;
      scripts/market_evidence_status.lpy|scripts/assert_market_evidence_status.lpy)
        append_target tests/ops/test_market_evidence_status_smoke.lpy::market-evidence-status-rejects-unknown-cli-arguments
        append_target tests/ops/test_market_evidence_status_smoke.lpy::market-evidence-status-fails-without-matched-feature-parity-diagnostic
        append_target tests/ops/test_market_evidence_status_smoke.lpy::market-evidence-status-surfaces-optional-diagnostics-when-manifested
        append_target tests/ops/test_market_evidence_status_smoke.lpy::market-evidence-status-fails-when-manifested-matched-parity-metrics-are-missing
        append_target tests/ops/test_market_evidence_status_smoke.lpy::market-evidence-status-fails-when-readiness-matched-parity-disagrees-with-manifest
        append_target tests/feature_parity/test_evidence_status.lpy
        ;;
      scripts/collect_market_evidence.sh)
        append_target tests/ops/test_market_evidence_workflow.lpy::collect-market-evidence-threads-target-date-through-all-artifacts
        append_target tests/ops/test_market_evidence_workflow.lpy::collect-market-evidence-skips-expensive-parity-build-after-capture-check-failure
        append_target tests/ops/test_live_systemd_units.lpy::market-evidence-wrapper-targets-new-york-date-and-collector-modes
        append_target tests/ops/test_live_systemd_units.lpy::collect-market-evidence-defaults-to-shared-runtime-on-hetzner-only
        ;;
      projects/ops/scripts/run_market_evidence.sh)
        append_target tests/ops/test_live_systemd_units.lpy
        ;;
      scripts/capture_v2_sidecar_check.lpy|scripts/capture_v2_runtime_preflight.lpy|scripts/prepare_capture_v2_session.lpy)
        append_target tests/ops/test_capture_v2_sidecar_check.lpy
        ;;
      scripts/launch_steve_six.lpy)
        append_target tests/ops/test_launch_steve_six.lpy
        ;;
      scripts/build_thetadata_historical_feature_cohort.lpy|scripts/prepare_historical_feature_cohort.lpy)
        append_target tests/feature_parity/test_build_thetadata_historical_feature_cohort_cli.lpy
        append_target tests/feature_parity/test_historical_artifact_clis.lpy
        ;;
      scripts/build_historical_v3_feature_cache.lpy)
        append_target tests/feature_parity/test_historical_artifact_clis.lpy
        ;;
      scripts/reconstruct_feature_cache_date_map.lpy)
        append_target tests/feature_parity/test_historical_artifact_clis.lpy
        ;;
      scripts/replay_captured_feature_cohort.lpy)
        append_target tests/feature_parity/test_replay_captured_feature_cohort_cli.lpy
        ;;
      scripts/raw_thetadata_parity.lpy)
        append_target tests/feature_parity/test_raw_thetadata_parity_cli.lpy
        ;;
      scripts/record_thetadata_stream.lpy)
        append_target tests/feature_parity/test_record_thetadata_stream_cli.lpy
        ;;
      scripts/build_raw_history_request_manifest.lpy|scripts/execute_raw_history_parity.lpy)
        append_target tests/feature_parity/test_raw_history_parity_cli.lpy
        ;;
      scripts/raw_feature_unlock_audit.lpy)
        append_target tests/ops/test_raw_feature_unlock_audit_smoke.lpy::recompute-raw-passes-list-grid-history-to-legacy-feature-engine
        append_target tests/ops/test_raw_feature_unlock_audit_smoke.lpy::raw-feature-unlock-audit-supports-latest-row-sampling
        append_target tests/ops/test_raw_feature_unlock_audit_smoke.lpy::raw-candidate-sources-include-formula-backed-v2-replay
        ;;
      scripts/neutralization_candidate_gap_report.lpy)
        append_target tests/feature_parity/test_neutralization_candidate_gap_report_cli.lpy
        ;;
      scripts/apply_neutralization_candidates.lpy)
        append_target tests/ops/test_raw_feature_unlock_audit_smoke.lpy::apply-neutralization-candidates-dry-run-does-not-mutates-bundles
        append_target tests/ops/test_raw_feature_unlock_audit_smoke.lpy::apply-neutralization-candidates-unions-extra-audit-candidates
        ;;
      scripts/apply_verified_neutralization_unmask.lpy)
        append_target tests/ops/test_apply_verified_neutralization_unmask.lpy
        ;;
      scripts/verify_neutralization_unmask_apply.lpy)
        append_target tests/ops/test_raw_feature_unlock_audit_smoke.lpy::verify-neutralization-unmask-apply-cli-help-compiles
        ;;
      scripts/blocked_feature_provenance_audit.lpy)
        append_target tests/ops/test_raw_feature_unlock_audit_smoke.lpy::blocked-feature-provenance-audit-cli-help-documents-evidence-inputs
        ;;
      scripts/v3_grid_unlock_audit.lpy)
        append_target tests/ops/test_raw_feature_unlock_audit_smoke.lpy::v3-grid-unlock-audit-uses-strict-feature-name-json-loader
        ;;
      scripts/greek_feature_reconstruction_audit.lpy)
        append_target tests/feature_parity/test_greek_reconstruction_audit_cli.lpy
        ;;
      scripts/greek_reconstruction_promotion_gate.lpy)
        append_target tests/feature_parity/test_greek_promotion_gate_cli.lpy
        ;;
      scripts/legacy_greek_formula_search.lpy)
        append_target tests/feature_parity/test_legacy_greek_formula_search_cli.lpy
        ;;
      scripts/live_feature_prediction_delta.lpy)
        append_target tests/feature_parity/test_cli_contracts.lpy
        ;;
      scripts/neutralized_feature_unlock_plan.lpy)
        append_target tests/ops/test_raw_feature_unlock_audit_smoke.lpy::neutralized-unlock-plan-cli-help-compiles-without-python-planner-import
        ;;
      scripts/thetadata_capability_probe.lpy)
        append_target tests/feature_parity/test_thetadata_capability_probe_cli.lpy
        ;;
      scripts/verify_thetadata_payload_examples.lpy|components/market-data.thetadata-schema/*|resources/thetadata/payload_examples/*)
        append_target tests/market_data/test_thetadata_schema.lpy
        append_target tests/feature_parity/test_thetadata_payload_verifier_cli.lpy
        ;;
      components/market-data.thetadata/*|tests/market_data/test_thetadata.lpy)
        append_target tests/market_data/test_thetadata.lpy
        ;;
      components/analysis.derived-greeks/*)
        append_target tests/analysis_derived_greeks
        ;;
      components/bridge.steve-v2/*|scripts/launch_steve_v2_replay.lpy)
        append_target tests/bridge/test_steve_v2.lpy
        ;;
      components/bridge.v2-vol/*)
        append_target tests/bridge/test_v2_vol.lpy
        ;;
      components/bridge.v2-term/*)
        append_target tests/bridge/test_v2_term.lpy
        ;;
      components/current-pnl.core/*|scripts/current_pnl.*|scripts/sim_broker_status.*|scripts/current_sim_account_state.lpy)
        append_target tests/current_pnl
        ;;
      components/report-metrics.core/*|scripts/report_metrics.lpy)
        append_target tests/report_metrics
        ;;
      components/reporting.core/*|scripts/validate_report_day.lpy)
        append_target tests/reporting
        append_target tests/report_metrics
        ;;
      components/status.core/*|scripts/build_status.lpy|projects/ops/scripts/run_status_dashboard.sh)
        append_target tests/status
        ;;
      components/analysis.core/*)
        append_target tests/analysis
        ;;
      components/ledger.core/*)
        append_target tests/ledger
        ;;
      components/execution.core/*)
        append_target tests/strategy/test_direction_executors.lpy
        ;;
      components/engine.loop/*|bases/engine-*/*)
        append_target tests/engine
        ;;
      components/strategy.registry/*|resources/strategies/*)
        append_target tests/strategy
        ;;
      components/broker.alpaca/*)
        append_target tests/broker/test_alpaca.lpy
        ;;
      components/broker.sim/*)
        append_target tests/broker/test_sim.lpy
        ;;
      components/broker.router/*)
        append_target tests/broker/test_router.lpy
        ;;
      components/broker.fanout/*)
        append_target tests/broker/test_fanout.lpy
        ;;
      projects/ops/scripts/systemd/*)
        append_target tests/ops/test_live_systemd_units.lpy
        ;;
      projects/ops/scripts/run_theta_terminal.sh)
        append_target tests/ops/test_run_theta_terminal_wrapper.lpy
        append_target tests/ops/test_live_systemd_units.lpy::theta-terminal-restarts-only-on-real-failure
        ;;
      projects/ops/scripts/run_raw_history_parity.sh)
        append_target tests/feature_parity/test_raw_history_parity_cli.lpy
        append_target tests/ops/test_live_systemd_units.lpy::raw-history-wrapper-rejects-a-stream-receipt-without-market-events
        ;;
      projects/ops/scripts/run_raw_thetadata_parity.sh)
        append_target tests/feature_parity/test_raw_thetadata_parity_cli.lpy
        append_target tests/ops/test_live_systemd_units.lpy::raw-snapshot-wrapper-includes-daily-open-interest-parity
        ;;
      projects/ops/scripts/pull_thetadata_parity.sh)
        append_target tests/feature_parity/test_verify_raw_parity_evidence_cli.lpy
        append_target tests/ops/test_live_systemd_units.lpy::parity-pull-retries-until-the-complete-evidence-artifact-arrives
        ;;
      scripts/verify_raw_parity_evidence.lpy)
        append_target tests/feature_parity/test_verify_raw_parity_evidence_cli.lpy
        ;;
      projects/ops/scripts/*|scripts/ops/*)
        append_target tests/ops/test_live_systemd_units.lpy
        append_target tests/ops/test_operational_entrypoints.lpy
        ;;
      docs/*|projects/ops/docs/*|scripts/README.md|tests/README.md|tests/*.md|report-viewer/*|stevetrading_basilisp.egg-info/*)
        ;;
      *)
        append_target tests/test_toolchain.lpy
        ;;
    esac
  done
  targets_ref=("${targets[@]}")
}

targets_for_changed_files() {
  local -n out="$1"
  targets_for_file_stream out < <(changed_files)
}

targets_for_explicit_files() {
  local -n out="$1"
  shift
  targets_for_file_stream out < <(explicit_files "$@")
}

mode="${1:-}"
case "$mode" in
  fast)
    shift
    exec "$BASILISP" test -m "not slow" --ignore=tests/ops "$@"
    ;;
  inner)
    shift
    run_existing_tests \
      tests/test_toolchain.lpy \
      tests/domain \
      tests/engine \
      tests/ledger/test_ledger.lpy \
      tests/broker/test_sim.lpy \
      tests/broker/test_router.lpy \
      tests/strategy/test_direction_executors.lpy \
      tests/strategy/test_declaration_schema.lpy \
      tests/current_pnl \
      tests/status/test_core.lpy::status-payload-validation-accepts-complete-fresh-payload \
      tests/status/test_core.lpy::status-payload-validation-rejects-market-evidence-ok-with-missing-matched-proof-fields \
      tests/status/test_core.lpy::status-publication-writes-auditable-manifest \
      tests/analysis_derived_greeks \
      tests/feature_parity/test_evidence_status.lpy \
      -- \
      "$@"
    ;;
  changed)
    shift
    targets=()
    targets_for_changed_files targets
    run_selected_tests "${targets[@]}" -- "$@"
    ;;
  scope)
    shift
    files=()
    while [[ "$#" -gt 0 ]]; do
      if [[ "$1" == "--" ]]; then
        shift
        break
      fi
      files+=("$1")
      shift
    done
    targets=()
    targets_for_explicit_files targets "${files[@]}"
    STEVE_TEST_TARGET_LABEL="scoped test targets" run_selected_tests "${targets[@]}" -- "$@"
    ;;
  map)
    shift
    targets=()
    targets_for_explicit_files targets "$@"
    if [[ "${#targets[@]}" -eq 0 ]]; then
      printf 'No test targets mapped.\n' >&2
      exit 0
    fi
    printf '%s\n' "${targets[@]}"
    ;;
  ops)
    shift
    if [[ "$#" -gt 0 ]]; then
      exec "$BASILISP" test "$@"
    fi
    exec "$BASILISP" test tests/ops
    ;;
  status)
    shift
    run_existing_tests \
      tests/status \
      -- \
      "$@"
    ;;
  reports)
    shift
    run_existing_tests \
      tests/reporting \
      tests/report_metrics \
      tests/reports \
      tests/ops/test_report_validation_cli.lpy \
      -- \
      "$@"
    ;;
  capture)
    shift
    run_existing_tests \
      tests/bridge/test_steve_v2.lpy::feature-capture-writes-atomically-and-preserves_required_arrays \
      tests/bridge/test_steve_v2.lpy::feature-capture-skips-blank-bar-times \
      tests/bridge/test_steve_v2.lpy::feature-capture-appends-across-bars-and-process-restarts \
      tests/bridge/test_steve_v2.lpy::feature-capture-dedupes-equivalent-time-encodings-across-restarts \
      tests/bridge/test_steve_v2.lpy::feature-capture-failed-writes-do-not-accumulate-sidecar-backlog \
      tests/bridge/test_steve_v2.lpy::option-surface-sidecar-merges-formula-features \
      tests/bridge/test_steve_v2.lpy::live-option-sidecars-serialize-basilisp-contracts-as-json-objects \
      tests/ops/test_capture_v2_sidecar_check.lpy \
      -- \
      "$@"
    ;;
  theta-core)
    shift
    run_existing_tests \
      tests/market_data/test_thetadata.lpy \
      tests/market_data/test_thetadata_schema.lpy::expiration-list-schema \
      tests/market_data/test_thetadata_schema.lpy::quote-snapshot-schema \
      tests/market_data/test_thetadata_schema.lpy::option-surface-schemas \
      tests/market_data/test_thetadata_schema.lpy::option-surface-probes-normalize-and-validate \
      tests/market_data/test_thetadata_schema.lpy::stock-and-index-surface-schemas \
      tests/market_data/test_thetadata_schema.lpy::payload-example-verifier \
      -- \
      "$@"
    ;;
  theta-smoke)
    shift
    run_existing_tests \
      tests/market_data/test_thetadata.lpy \
      tests/market_data/test_thetadata_schema.lpy::expiration-list-schema \
      tests/market_data/test_thetadata_schema.lpy::quote-snapshot-schema \
      tests/market_data/test_thetadata_schema.lpy::option-surface-schemas \
      tests/market_data/test_thetadata_schema.lpy::option-surface-probes-normalize-and-validate \
      tests/market_data/test_thetadata_schema.lpy::stock-and-index-surface-schemas \
      tests/market_data/test_thetadata_schema.lpy::payload-example-verifier \
      tests/feature_parity/test_thetadata_payload_verifier_cli.lpy \
      -- \
      "$@"
    ;;
  market-evidence-core)
    shift
    run_existing_tests \
      tests/ops/test_market_evidence_readiness.lpy::market-evidence-readiness-passes-from-non-repo-cwd \
      tests/ops/test_market_evidence_readiness.lpy::market-evidence-readiness-fails-bad-or-sparse-capture-sidecars \
      tests/ops/test_market_evidence_readiness.lpy::market-evidence-readiness-fails-matched-feature-parity-problems \
      tests/ops/test_market_evidence_readiness.lpy::market-evidence-readiness-fails-without-raw-replay-metadata \
      tests/ops/test_market_evidence_workflow.lpy::collect-market-evidence-threads-target-date-through-all-artifacts \
      tests/ops/test_market_evidence_workflow.lpy::collect-market-evidence-skips-expensive-parity-build-after-capture-check-failure \
      -- \
      "$@"
    ;;
  market-evidence-smoke)
    shift
    run_existing_tests \
      tests/ops/test_market_evidence_readiness.lpy::market-evidence-readiness-rejects-cli-errors \
      tests/ops/test_market_evidence_readiness.lpy::market-evidence-readiness-passes-from-non-repo-cwd \
      tests/ops/test_market_evidence_readiness.lpy::market-evidence-readiness-rejects-duplicate-json \
      tests/ops/test_market_evidence_readiness.lpy::market-evidence-readiness-accepts-verified-payload-examples-without-probe-paths \
      tests/ops/test_market_evidence_readiness.lpy::market-evidence-readiness-fails-bad-or-sparse-capture-sidecars \
      tests/ops/test_market_evidence_readiness.lpy::market-evidence-readiness-fails-capture-integrity-problems \
      tests/ops/test_market_evidence_readiness.lpy::market-evidence-readiness-fails-missing-or-explicit-artifacts \
      tests/ops/test_market_evidence_readiness.lpy::market-evidence-readiness-fails-matched-feature-parity-problems \
      tests/ops/test_market_evidence_readiness.lpy::market-evidence-readiness-watches-legacy-and-greek-candidates \
      tests/ops/test_market_evidence_readiness.lpy::market-evidence-readiness-fails-greek-promotion-integrity \
      tests/ops/test_market_evidence_readiness.lpy::market-evidence-readiness-fails-without-raw-replay-metadata \
      tests/ops/test_market_evidence_manifest_smoke.lpy::market-evidence-manifest-writes-and-verifies-complete-bundle \
      tests/ops/test_market_evidence_manifest_smoke.lpy::market-evidence-manifest-includes-optional-diagnostics-when-present \
      tests/ops/test_market_evidence_status_smoke.lpy::market-evidence-status-fails-without-matched-feature-parity-diagnostic \
      tests/ops/test_market_evidence_status_smoke.lpy::market-evidence-status-surfaces-optional-diagnostics-when-manifested \
      tests/ops/test_market_evidence_status_smoke.lpy::market-evidence-status-fails-when-manifest-checksum-verification-fails \
      tests/ops/test_market_evidence_workflow.lpy \
      -- \
      "$@"
    ;;
  market-evidence-deploy)
    shift
    run_existing_tests_including_slow \
      tests/ops/test_market_evidence_readiness.lpy \
      tests/ops/test_market_evidence_manifest_smoke.lpy::market-evidence-manifest-writes-and-verifies-complete-bundle \
      tests/ops/test_market_evidence_manifest_smoke.lpy::market-evidence-manifest-includes-optional-diagnostics-when-present \
      tests/ops/test_market_evidence_status_smoke.lpy::market-evidence-status-fails-without-matched-feature-parity-diagnostic \
      tests/ops/test_market_evidence_status_smoke.lpy::market-evidence-status-surfaces-optional-diagnostics-when-manifested \
      tests/ops/test_market_evidence_status_smoke.lpy::market-evidence-status-fails-when-manifest-checksum-verification-fails \
      tests/ops/test_market_evidence_workflow.lpy \
      -- \
      "$@"
    ;;
  market-evidence-status-deploy)
    shift
    run_existing_tests_including_slow \
      tests/ops/test_market_evidence_status_smoke.lpy::market-evidence-status-fails-without-matched-feature-parity-diagnostic \
      tests/ops/test_market_evidence_status_smoke.lpy::market-evidence-status-surfaces-optional-diagnostics-when-manifested \
      tests/ops/test_market_evidence_status_smoke.lpy::market-evidence-status-fails-when-manifested-matched-parity-metrics-are-missing \
      tests/ops/test_market_evidence_status_smoke.lpy::market-evidence-status-fails-when-readiness-matched-parity-disagrees-with-manifest \
      -- \
      "$@"
    ;;
  replay-golden)
    shift
    exec "$BASILISP" test tests/e2e/test_replay_golden.lpy "$@"
    ;;
  parity-smoke)
    shift
    run_existing_tests \
      tests/feature_parity/test_core.lpy::pass-verdict-when-active-features-are-sane-and-delta-is-small \
      tests/feature_parity/test_core.lpy::feature-parity-gate-fails-empty-or-malformed-baseline-csv \
      tests/feature_parity/test_core.lpy::baseline-write-produces-expected-summary-and-files \
      tests/feature_parity/test_core.lpy::evidence-readiness-passes-for-fresh-sufficient-clean-artifacts \
      tests/feature_parity/test_core.lpy::evidence-readiness-fails-for-stale-low-row-or-malformed-capture-evidence \
      tests/feature_parity/test_core.lpy::evidence-readiness-fails-when-baseline-summary-contradicts-feature-rows \
      tests/feature_parity/test_core.lpy::matched-feature-parity-report-writes-steve-requested-metrics \
      tests/feature_parity/test_core.lpy::matched-feature-parity-report-rejects-insufficient-overlap \
      tests/bridge/test_steve_v2.lpy::feature-capture-writes-atomically-and-preserves_required_arrays \
      tests/bridge/test_steve_v2.lpy::feature-capture-appends-across-bars-and-process-restarts \
      tests/bridge/test_steve_v2.lpy::feature-capture-failed-writes-do-not-accumulate-sidecar-backlog \
      tests/market_data/test_thetadata_schema.lpy::option-surface-schemas \
      tests/market_data/test_thetadata_schema.lpy::payload-example-verifier \
      tests/analysis_derived_greeks/test_core.lpy \
      tests/ops/test_capture_v2_sidecar_check.lpy::capture-v2-sidecar-check-accepts-valid-capture \
      tests/ops/test_capture_v2_sidecar_check.lpy::capture-v2-sidecar-check-requires-grid-history-sidecar \
      tests/ops/test_capture_v2_sidecar_check.lpy::capture-v2-sidecar-check-rejects-duplicate-timestamps \
      tests/ops/test_capture_v2_sidecar_check.lpy::capture-v2-sidecar-check-does-not-count-stringified-contract-rows \
      tests/ops/test_market_evidence_readiness.lpy::market-evidence-readiness-passes-from-non-repo-cwd \
      tests/ops/test_market_evidence_readiness.lpy::market-evidence-readiness-fails-bad-or-sparse-capture-sidecars \
      tests/ops/test_market_evidence_readiness.lpy::market-evidence-readiness-fails-matched-feature-parity-problems \
      -- \
      "$@"
    ;;
  parity)
    shift
    run_existing_tests \
      tests/feature_parity \
      tests/market_data/test_thetadata.lpy \
      tests/market_data/test_thetadata_schema.lpy::expiration-list-schema \
      tests/market_data/test_thetadata_schema.lpy::quote-snapshot-schema \
      tests/market_data/test_thetadata_schema.lpy::option-surface-schemas \
      tests/market_data/test_thetadata_schema.lpy::option-surface-probes-normalize-and-validate \
      tests/market_data/test_thetadata_schema.lpy::stock-and-index-surface-schemas \
      tests/market_data/test_thetadata_schema.lpy::header-response-payloads-normalize-and-validate \
      tests/market_data/test_thetadata_schema.lpy::row-dict-payloads-normalize-and-validate \
      tests/market_data/test_thetadata_schema.lpy::header-response-length-mismatch-is-rejected \
      tests/market_data/test_thetadata_schema.lpy::header-response-wide-rows-are-rejected \
      tests/market_data/test_thetadata_schema.lpy::python-json-containers-are-validatable \
      tests/market_data/test_thetadata_schema.lpy::numeric-wire-predicate \
      tests/market_data/test_thetadata_schema.lpy::payload-example-verifier \
      tests/market_data/test_thetadata_schema.lpy::payload-example-coverage-requires-core-schema-backed-probes \
      tests/market_data/test_thetadata_schema.lpy::payload-example-verifier-cli-exits-zero-for-valid-supported-examples \
      tests/market_data/test_thetadata_schema.lpy::payload-example-verifier-cli-fails-invalid-supported-examples \
      tests/market_data/test_thetadata_schema.lpy::payload-example-verifier-cli-fails-missing-required-supported-probe-coverage \
      tests/market_data/test_thetadata_schema.lpy::payload-example-verifier-cli-fails-corrupt-example-without-probe-identity \
      tests/market_data/test_thetadata_schema.lpy::payload-example-verifier-cli-fails-stale-or-wrong-directory-examples \
      tests/market_data/test_thetadata_schema.lpy::payload-example-verifier-cli-fails-empty-directories \
      tests/analysis_derived_greeks \
      tests/ops/test_capture_v2_sidecar_check.lpy \
      tests/feature_parity/test_cli_contracts.lpy \
      tests/ops/test_market_evidence_readiness.lpy \
      tests/ops/test_market_evidence_manifest_smoke.lpy::market-evidence-manifest-writes-and-verifies-complete-bundle \
      tests/ops/test_market_evidence_manifest_smoke.lpy::market-evidence-manifest-includes-optional-diagnostics-when-present \
      tests/ops/test_market_evidence_status_smoke.lpy::market-evidence-status-fails-without-matched-feature-parity-diagnostic \
      tests/ops/test_market_evidence_status_smoke.lpy::market-evidence-status-surfaces-optional-diagnostics-when-manifested \
      tests/ops/test_market_evidence_status_smoke.lpy::market-evidence-status-fails-when-manifest-checksum-verification-fails \
      tests/feature_parity/test_build_thetadata_historical_feature_cohort_cli.lpy \
      tests/feature_parity/test_replay_captured_feature_cohort_cli.lpy \
      -- \
      "$@"
    ;;
  full)
    shift
    exec "$BASILISP" test "$@"
    ;;
  -h|--help)
    sed -n '2,19p' "$0"
    exit 0
    ;;
  *)
    for arg in "$@"; do
      case "${arg%%::*}" in
        tests/*.py|tests/**/*.py)
          reject_python_test_target "$arg"
          exit 2
          ;;
      esac
    done
    exec "$BASILISP" test "$@"
    ;;
esac
