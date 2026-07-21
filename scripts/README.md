# Scripts

Top-level scripts are developer and runtime entrypoints that do not belong in
pure components.

Common commands:

- `scripts/test.sh`: run Basilisp/Pytest tests with the repo environment.
- `scripts/lint.sh`: compile check plus dependency-direction check.
- `scripts/nrepl.sh`: start a Basilisp nREPL with regenerated pythonpath.
- `scripts/current_pnl.lpy`: current Alpaca/sim account P&L table.
- `scripts/sim_broker_status.lpy`: durable sim broker journal summary.
- `scripts/reports_static_server.lpy`: authenticated reports static server.
- `scripts/audit_daily_report_validations.lpy`: fail-closed audit for generated
  daily report validation artifacts before reports are published.
- `scripts/launch_steve_six.lpy`: six Alpaca paper strategies launcher.
  It enables Steve V2 feature-parity capture by default, including
  SPX/SPXW/VIX/VIXW option surface sidecars when those feeds are enabled.
  Production live trading may use sparse sidecars via
  `STEVE_CAPTURE_SIDECAR_EVERY > 1` to avoid inference lag. Full per-row
  parity evidence runs must set `STEVE_CAPTURE_SIDECAR_EVERY=1` in the
  evidence collection environment.
- `scripts/launch_vol_term_sim.lpy`: local vol/term sim launcher.
- `scripts/local_sim_session.sh`: sim-only daily launcher for local fleet plus
  vol/term strategies through the Hetzner ThetaData SSH tunnel.
- `scripts/export_live_tape.lpy`: export behavior tape from facts.
- `scripts/export_replay_tape.lpy`: export replay behavior tape from facts.
- `scripts/export_replay_fixture_from_facts.lpy`: export market observation
  facts from a `facts.db` snapshot into replay fixture EDN.
- `scripts/export_episodes.lpy`: export canonical trade episode rows from
  ledger/order/fill facts.
- `scripts/align_behavior.lpy`: compare live and replay behavior tapes. The
  report includes a cohort gate and marks mismatched strategy/account cohorts
  invalid before same-population interpretation.
- `scripts/analyze_alpaca_fill_alignment.lpy`: print an operator-facing table
  of Alpaca paper option fills matched to nearest saved ThetaData quotes using
  the same matching semantics as sim-fill calibration.
- `scripts/validate_same_pop_readiness.lpy`: gate same-population statistical
  tests on valid live/replay tapes, live/replay episode tables, exact behavior
  alignment, completed episodes, and usable fill calibration.
- `scripts/run_same_pop_stats.lpy`: gated episode-level same-population
  performance report. It runs the readiness gate first and refuses to compute
  P&L statistics when data, behavior, episode, or fill gates fail. Use
  `--manifest-out` to persist the reproducibility manifest as EDN next to the
  markdown report.
- `scripts/verify_same_pop_manifest.lpy`: verify a saved same-pop manifest by
  checking all referenced artifact files still exist and match recorded
  SHA-256 checksums.
- `scripts/live_feature_model_usage_audit.lpy`: inspect corrected Steve V2
  XGBoost JSON heads and report whether suspicious live features are used by
  model splits/gain.
- `scripts/live_feature_prediction_delta.lpy`: optional Steve V2 diagnostic
  that runs live inference over saved captures and quantifies whether currently
  suspicious active feature differences materially move model predictions.
- `scripts/matched_feature_parity_report.lpy`: Steve-requested matched cohort
  report for a saved live capture tensor and a historical/preprocessed tensor.
  It aligns rows by timestamp and emits per-feature live vs historical
  mean/std/min/max, zero/NaN fractions, correlation, mean absolute deviation,
  and max absolute deviation.
- `scripts/audit_captured_source_parity.lpy`: source-boundary gate that compares
  captured finalized stock buffers and exact option contract/quote inputs with
  a same-time historical reconstruction. Missing capture provenance is
  explicitly non-certifying.
- `scripts/build_verified_feature_corpus.lpy`: concatenates only
  source-parity-certified historical cohorts that declare the canonical
  contract and the shared native Basilisp feature implementation. It rejects
  legacy Python cohorts rather than silently mixing train/serve semantics.
- `scripts/replay_captured_feature_cohort.lpy`: live-pipeline determinism
  diagnostic that recomputes captured live rows from raw capture sidecars,
  overlays the same option/grid formulas as the bridge, applies bundle
  neutralization, and compares against the captured model-input vector. It is
  fail-closed on non-finite inputs and writes per-feature replay evidence. This
  is not a substitute for the matched historical parity cohort.
- `scripts/feature_drift_ledger.lpy`: writes immutable per-session feature
  drift records from exact live replay plus optional matched historical parity.
  Same-day reruns archive the prior ledger rather than overwriting observed
  discrepancies.
- `scripts/run_local_feature_parity_analysis.sh`: workstation analysis entry
  point. It snapshots the live VPS capture before transfer, reads ThetaData
  through a temporary SSH tunnel, and performs CPU-heavy replay/reconstruction
  locally without modifying live trading state.
- `scripts/raw_feature_unlock_audit.lpy`: formula/replay-backed audit over
  capture-version 2 raw sidecars (`bar_buffers_json`, `option_chain_json`,
  `option_surfaces_json`, grids) that emits candidates safe to remove from Steve V2
  `neutralize_features.json` after fresh market-hours evidence. It also reports
  guarded Greek reconstruction formulas under
  `greek_reconstruction_candidate_formula`; those rows are evidence-only and
  are intentionally excluded from automatic unmask candidates.
- `scripts/neutralization_candidate_gap_report.lpy`: post-audit diagnostic that
  explains why exact matched/cohort-neutralized features did or did not become
  unmask candidates, including raw replay statuses, unsupported families,
  candidate provenance, and optional Greek promotion-gate rejection reasons.
- `scripts/neutralized_feature_unlock_plan.lpy`: read-only pre-market planner
  that classifies every currently neutralized Steve V2 feature by the data,
  formula, or implementation work required before it can be unmasked.
- `scripts/legacy_greek_formula_search.lpy`: read-only bounded source/archive
  search for the remaining formula-blocked Greek features. It distinguishes
  source-like formula contexts from manifest/report references and checks
  whether feature-manifest implementation classes actually exist.
- `scripts/greek_feature_reconstruction_audit.lpy`: conservative classifier for
  the remaining formula-blocked Greek features. It marks which suffixes have
  plausible candidate formulas from capture-v2 sidecars and which still require
  formula provenance; it never makes a feature auto-unmaskable by itself.
- `scripts/greek_reconstruction_promotion_gate.lpy`: fail-closed promotion gate
  for guarded Greek reconstruction rows from `raw_feature_unlock_audit.lpy`.
  It emits extra-audit-compatible candidates only when capture-v2 sidecars are
  clean and reconstructed z-scale/status checks pass strict thresholds.
- `scripts/capture_v2_runtime_preflight.lpy`: static pre-market guard that
  verifies the deployed Steve V2 bridge and launcher still contain the
  capture-version-2 writer, raw sidecar arrays, atomic file replacement, and
  `CAPTURE_DIR` wiring required for the next market-hours evidence run.
- `scripts/prepare_capture_v2_session.lpy`: pre-session guard used by
  `scripts/steve_six_session.sh` to quarantine same-day capture NPZ files with
  structural defects that appending more rows cannot repair, such as duplicate
  timestamps or malformed non-object option contracts.
- `scripts/apply_neutralization_candidates.lpy`: dry-run/apply helper for
  removing audited candidate feature names from corrected Steve V2
  `neutralize_features.json` files consistently across bundles. Real writes
  require `--audit-json raw_feature_unlock_audit_YYYYMMDD.json` by default and
  preflight every target bundle before touching any file.
- `scripts/apply_verified_neutralization_unmask.lpy`: operator-facing promotion
  gate that applies neutralization unmask candidates only from a verified
  market-evidence manifest, passing status JSON, and checksummed dry-run
  artifact. Without `--apply` it validates the bundle and prints the exact
  lower-level apply command; with `--apply` it writes a separate
  `neutralization_unmask_apply_YYYYMMDD.json` result artifact.
- `scripts/verify_neutralization_unmask_apply.lpy`: post-apply verifier for
  `neutralization_unmask_apply_YYYYMMDD.json`. It checks every current
  neutralization file, backup file, recorded SHA-256, removed feature set, and
  missing-candidate count before treating an apply as verified.
- `scripts/v3_grid_unlock_audit.lpy`: Basilisp/numpy audit for residual V3 grid
  neutralization candidates where the required topology/scattering/dictionary
  arrays still live in Python `.npz` artifacts.
- `scripts/live_feature_parity_gate.lpy`: diagnostic PASS/WATCH/FAIL gate over
  the live feature parity baseline and optional prediction-delta CSV.
- `scripts/neutralization_audit.lpy`: read-only Steve V2 neutralization audit
  that ranks currently neutralized features by saved live feature health,
  model usage, and saved option-cache/capture-date evidence.
- `scripts/market_evidence_readiness.lpy`: read-only PASS/WATCH/FAIL gate for
  market-open evidence artifacts before trusting feature parity or
  neutralization conclusions.
- `scripts/verify_thetadata_payload_examples.lpy`: offline Balli/schema
  verifier for saved ThetaData capability-probe payload examples. Writes a
  dated `thetadata_payload_verification_YYYYMMDD.json` artifact for
  `market_evidence_readiness`; use `--target-date YYYY-MM-DD` so stale or
  wrong-directory payload examples fail closed.
- `scripts/raw_thetadata_parity.lpy`: captures an unmodified ThetaData live
  snapshot and matching at-time historical response, writes both payloads and
  checksummed request receipts under `/mnt/d/stevetrading/thetadata-parity-v1`,
  and emits an immediate raw `PASS`/`FAIL`/`INCONCLUSIVE` verdict. It is a
  first-open source-pair diagnostic, not event-stream certification.
- `scripts/collect_market_evidence.sh`: market-open one-shot workflow that
  runs the ThetaData probe, payload verification, baseline, optional
  prediction-delta diagnostics, parity gate, model-usage audit, neutralization
  audit, readiness, manifest generation, and manifest self-verification, then
  writes the status summary with one shared target date. It fails closed unless
  readiness, manifest generation, manifest verification, and status generation
  all pass; prediction-delta and parity-gate failures are diagnostic and do not
  replace the market-evidence readiness decision. Use
  `--preflight` before market open to validate local runners/paths and print
  the command plan without deleting or writing artifacts; use `--dry-run` when
  you only need the exact commands.
- `projects/ops/scripts/run_market_evidence.sh`: systemd-friendly wrapper for
  `collect_market_evidence.sh`. It computes the target date in
  `America/New_York`, writes `/var/log/stevetrading/market-evidence.log`, and
  supports `MARKET_EVIDENCE_MODE=preflight|capture-smoke|collect|dry-run`.
  `capture-smoke` runs after six-bot startup and calls
  `scripts/capture_v2_sidecar_check.lpy` with a low row threshold so malformed
  sidecars or missing SPX/SPXW/VIX/VIXW surfaces are caught before the full
  10:45 ET evidence collector.
- `projects/ops/scripts/run_verified_unmask_apply.sh`: manual operator wrapper
  for the final unmask apply after market evidence is already green. It does
  not collect evidence and intentionally does not allow empty applies; it calls
  `scripts/apply_verified_neutralization_unmask.lpy --apply` with the same-day
  manifest, status, and verified validation JSON, then runs
  `scripts/verify_neutralization_unmask_apply.lpy` before reporting success.
- `scripts/market_evidence_manifest.lpy`: write or verify the checksum
  manifest for a market-evidence run bundle, covering probe, raw payload
  examples, payload verification, baseline, model usage, neutralization, and
  readiness artifacts. Verification fails closed for missing required files,
  failed readiness, wrong-day artifact paths, omitted raw payloads, symlink/path
  escapes, or checksum/size drift.
- `scripts/market_evidence_status.lpy`: read-only post-run status summary that
  verifies the market-evidence manifest, reads readiness/probe/payload
  verification/neutralization artifacts, and writes concise JSON/Markdown for
  operator inspection.
- `scripts/launch_steve_v2_replay.lpy`: replay the six Steve V2 bridge
  strategies over a fixture through `engine-replay`. Run with the
  Data-Preprocessor/REF venv because the bridge imports numpy/xgboost/torch
  model dependencies.
- `scripts/build_thetadata_historical_feature_cohort.lpy`: build same-date
  historical Steve V2 918-feature tensors from ThetaData historical stock OHLC
  and option quote endpoints. `legacy-python` remains available only for
  legacy-model diagnostics; the Steve V2 bridge uses the native Basilisp
  feature path, and `--implementation native` is required by the verified
  retraining corpus. `--cohort-window-minutes` bounds broad option-chain
  fetches to a trailing matched window plus grid warmup; the local and market
  evidence runners default to 75 minutes. This is the default source for matched
  live-vs-historical feature parity on recent sessions.
- `scripts/native_feature_migration_report.lpy`: compare legacy replay tensors
  against the native Basilisp port by timestamp and feature. This records the
  native migration gap separately from live-vs-historical parity so it cannot
  be mistaken for evidence that a live source is invalid.
- `scripts/prepare_historical_feature_cohort.lpy`: archive-cache fallback for
  historical feature cohorts when same-date ThetaData reconstruction is
  intentionally disabled.
- `scripts/build_historical_v3_feature_cache.lpy`: rebuild V3 historical feature
  cache artifacts used by residual V3 grid unlock diagnostics.
- `scripts/reconstruct_feature_cache_date_map.lpy`: reconstruct date-index
  metadata for historical feature cache artifacts.
- `scripts/calibrate_sim_fills.lpy`: build sim fill calibration artifact.

Analysis contract: `projects/ops/docs/analysis-contract.md`.

Python script policy:

- Operational compatibility wrappers have been removed. Use the `.lpy`
  implementation directly in automation.
- Deprecated Python analysis entrypoints have been removed; keep new operational
  analysis in Basilisp.
- Basilisp external-boundary tooling that still calls Python runtime libraries
  through Basilisp interop:
  `scripts/thetadata_capability_probe.lpy`,
  `scripts/live_feature_prediction_delta.lpy`, and
  `scripts/raw_feature_unlock_audit.lpy`,
  `scripts/neutralized_feature_unlock_plan.lpy`,
  `scripts/blocked_feature_provenance_audit.lpy`,
  `scripts/legacy_greek_formula_search.lpy`,
  `scripts/greek_feature_reconstruction_audit.lpy`,
  `scripts/greek_reconstruction_promotion_gate.lpy`,
  `scripts/capture_v2_sidecar_check.lpy`,
  `scripts/replay_captured_feature_cohort.lpy`,
  `scripts/build_thetadata_historical_feature_cohort.lpy`,
  `scripts/prepare_historical_feature_cohort.lpy`,
  `scripts/build_historical_v3_feature_cache.lpy`,
  `scripts/reconstruct_feature_cache_date_map.lpy`,
  `scripts/prepare_capture_v2_session.lpy`,
  `scripts/capture_v2_runtime_preflight.lpy`,
  `scripts/apply_neutralization_candidates.lpy`,
  `scripts/apply_verified_neutralization_unmask.lpy`, and
  `scripts/v3_grid_unlock_audit.lpy`.
- No non-test `.py` entrypoints remain; use the Basilisp CLI wrappers.
- Historical Python parity/deploy scripts have been removed; use the Basilisp
  parity, replay, report, and deployment entrypoints instead.

Canonical hosting/deployment scripts live under `projects/ops/scripts/`.
