# Statistical Same-Population Testing Plan

This guide defines how to test whether live paper trading behavior and
performance are plausibly drawn from the same process as historical
backtest/replay behavior.

The core principle: **do not compare P&L distributions until trade behavior is
aligned.** If live and replay do not enter/exit the same trades under the same
inputs and rules, a P&L significance test is answering the wrong question.

Canonical representation: see `projects/ops/docs/analysis-contract.md`. The
cohort profile, feature behavior table, behavior tape, trade episode table, and
execution calibration layers are the required inputs to this plan.

## Objectives

1. Verify data parity: live market data and replay/backtest market data produce
   compatible features, predictions, signals, intents, and fills.
2. Verify behavior parity: live and replay produce aligned trade decisions over
   the same dates, times, accounts, strategies, and instruments.
3. Verify execution parity: live paper fills are consistent with the assumed
   backtest/sim fill model after accounting for quotes, lag, spread, and order
   type.
4. Verify performance parity: conditional on behavior and execution parity,
   test whether live trade outcomes are statistically compatible with replay or
   historical backtest outcomes.
5. Detect drift early enough to stop deploying false-positive strategies.

## Definitions

- **Live tape:** chronological facts from a live/paper run: signal decisions,
  order intents, broker acknowledgements, fills, closes, and position state.
- **Replay tape:** same schema as live tape, generated offline over the exact
  same market interval using frozen code, frozen artifacts, and the same
  strategy config.
- **Historical backtest tape:** older broad-window backtest output, useful for
  distributional context but not sufficient for direct live alignment unless
  generated with the same code/artifacts/data contract.
- **Trade episode:** flat-to-position-to-flat interval, grouped by account,
  strategy, instrument family, direction, and entry decision.
- **Same-population condition:** live outcomes are statistically compatible
  with replay/historical outcomes after conditioning on comparable behavior,
  market regime, sizing, risk constraints, and fill assumptions.

## Required Artifacts

For every trading day under analysis, preserve:

- `facts.db` from live paper.
- `audit.jsonl` from the same session.
- feature capture `.npz` if model features are involved.
- control-plane manifest/revision.
- strategy artifact paths and checksums.
- model bundle checksums.
- calibration files and thresholds.
- sim broker/fill policy config.
- market data provider settings and feed names.
- daily report account-state snapshot.

For every replay/backtest day, generate:

- replay `facts.db` with the same fact schema as live.
- replay tape CSV.
- replay account-state and position snapshots.
- feature parity report.
- fill model assumptions.
- config/artifact manifest.

## Stage 0: Freeze The Experiment Contract

Before comparing anything, write a run manifest:

- Date range.
- Strategies/accounts included.
- Code commit.
- Model bundle directories.
- Feature stats and neutralization list.
- Control-plane revision.
- Broker target: live paper, sim, replay.
- Market data provider and feed.
- Entry/exit windows.
- Forced-flatten policy.
- Sizing.
- Fill policy.

No statistical result is valid without this manifest. If any artifact changes,
start a new experiment cohort.

The behavior-alignment exporter now also emits a cohort gate. If strategy IDs,
account IDs, account-strategy pairs, or nonempty alignable event coverage do not
match, the alignment status is `:alignment/invalid-cohort` and the run must not
be used for same-population P&L tests.

## Stage 1: Feature/Data Parity Gate

Goal: prove live features are not obviously broken before comparing trades.

Checks:

- Feature count and order match the model bundle.
- Live features standardize under training stats without massive offset or
  degenerate variance.
- Neutralized features are actually neutralized at inference time.
- Option-chain grids have plausible fill ratios, IV scale, Greek scale, DTE
  coverage, and moneyness structure.
- Equity/index proxy bars have expected coverage and timestamp alignment.
- Latest live captures are compared against previous captures to detect sudden
  source changes.

Artifacts:

- `live_feature_parity_baseline_YYYYMMDD.md`
- `live_feature_parity_baseline_YYYYMMDD.csv`
- `phase_b_drop.json`
- `neutralize_features.json`

Pass criteria:

- No active feature is `ZERO_FILLED_LIVE` unless intentionally neutralized.
- No active feature is non-finite.
- Active degenerate features are either justified or neutralized.
- Large offsets are classified as expected market-level shift or remediated.
- Feature capture coverage is near full session for normal trading days.

Fail action:

- Do not run same-population P&L tests.
- Fix source, feature computation, standardization, or neutralization first.

Current June 29 baseline:

- Captured live rows: `2,098` across seven available capture files.
- Model features: `918`.
- Corrected bundle neutralized features: `826`.
- Active sane features: `55`.
- Active suspicious features: `37`.
- Active zero-filled features: `0`.
- Active degenerate features: `0`.
- Remaining active issues are `25` low-variance features and `12` offset
  features, concentrated in SPY/TLT/SPX/TNX price-level and indicator fields.
- Model usage audit across chestnut/lynx/moose corrected XGB heads shows active
  suspicious features account for roughly `0.84%` to `1.40%` of splits and
  `0.52%` to `0.77%` of split gain.
- Today's partial June 29 capture currently has `117` rows, `0` active
  zero-filled features, `5` active degenerate features, and `70` active
  low-variance features. This is mostly intraday price-level low variance, but
  it is not automatically benign.
- Offline prediction-delta audit for today shows that neutralizing the
  aggregate `37` active suspicious features would move predictions by about
  `0.30` calibration-sigma at p95 for chestnut/lynx and about `0.42`
  calibration-sigma at p95 for moose. The max observed move is about `0.49`
  calibration-sigma.

Interpretation: the previous zero-fill/degenerated-feature problem is mostly
contained by runtime neutralization, but price-level distribution shift remains
nonzero and prediction-material. This is not enough by itself to claim the
models are live/backtest equivalent, and it is enough to keep feature parity as
a required gate before same-population P&L tests.

## Stage 2: Live Tape Normalization

Goal: convert live facts into a stable event schema.

Minimum columns:

- `event_type`
- `occurred_at`
- `account_id`
- `strategy_id`
- `decision_id`
- `order_intent_id`
- `broker_order_id`
- `instrument_id`
- `direction`
- `posture`
- `role`
- `effect`
- `side`
- `quantity`
- `limit_price`
- `fill_price`
- `fill_quantity`
- `correlation_id`
- `reason_codes`

Existing tool:

```bash
PYTHONPATH="components/analysis.core/src" \
  .venv/bin/basilisp run scripts/export_live_tape.lpy -- \
  --facts live_runtime/hetzner-snapshots/steve-session-YYYY-MM-DD-facts.db \
  --out live_runtime/analysis/live_tape_YYYYMMDD.csv
```

Required improvements:

- Add replay tape export with the same columns.
- Add episode assembly from signal/intent/fill/position facts.
- Preserve unmatched signals, rejected orders, missing fills, and forced
  flatten events rather than dropping them.

## Stage 3: Replay Over The Live Window

Goal: generate replay behavior for the exact dates live paper traded.

Requirements:

- Same strategies.
- Same model artifacts.
- Same thresholds/calibrations.
- Same session clock.
- Same warmup behavior.
- Same input market data contract where possible.
- Deterministic replay output.

Preferred path:

- Use Basilisp replay/backtest over the live paper window and emit facts in the
  same schema as live.

Fallback path:

- Recover old Python backtest date maps and old trade parquets only for
  historical context. Do not treat these as direct alignment truth unless their
  time indices are recovered exactly.

## Stage 4: Behavior Alignment

Goal: determine whether live and replay make the same decisions.

Alignment keys:

- `strategy_id`
- `account_id`
- `decision timestamp`, bucketed to the strategy bar cadence
- `instrument family`
- `direction`
- `entry/exit role`

Metrics:

- Signal precision: live signals that replay also produced.
- Signal recall: replay signals that live also produced.
- Intent precision/recall.
- Fill precision/recall.
- Entry-time delta distribution.
- Exit-time delta distribution.
- Direction mismatch rate.
- Instrument mismatch rate.
- Quantity mismatch rate.
- Rejected/missing order rate.
- Forced-flatten mismatch rate.

Pass criteria:

- For deterministic strategies, near-exact match on signal and intent timing.
- For quote/options strategies, acceptable tolerance must be declared upfront.
- Any mismatch cluster must be explainable by data availability, fill policy,
  session clock, or intentional live-only safety gates.

Fail action:

- Stop. Do not compare P&L distributions until behavior mismatch is understood.

## Stage 5: Execution/Fills Parity

Goal: determine whether paper fills are compatible with sim/backtest fill
assumptions.

For each option fill:

- Match nearest quote snapshot by instrument and timestamp.
- Calculate bid, ask, mid, spread, lag.
- Calculate edge versus crossing price.
- Bucket by side, spread, time of day, option right, moneyness, DTE, and
  liquidity proxy.

Metrics:

- Match rate to quotes.
- Median/p25/p75 improvement versus crossing.
- Slippage versus mid.
- Lag distribution.
- Fill rejection/cancel rate.
- Partial fill rate.

Initial June 25 result:

- `187` option fills.
- `112` quote-matched fills.
- Conservative improvement default: `0.0`.

Policy:

- Use no-improvement or pessimistic fills unless paper data robustly supports
  price improvement.
- Re-estimate periodically as paper fill sample grows.

## Stage 6: Trade Episode Assembly

Goal: convert events into comparable trades.

Episode fields:

- `episode_id`
- `strategy_id`
- `account_id`
- `direction`
- `instrument_group`
- `entry_time`
- `entry_price`
- `entry_quantity`
- `exit_time`
- `exit_price`
- `exit_quantity`
- `holding_minutes`
- `gross_pnl`
- `net_pnl`
- `return_on_risk`
- `max_favorable_excursion`
- `max_adverse_excursion`
- `exit_reason`
- `forced_flatten`
- `data_quality_flags`

Do not aggregate too early. Preserve leg-level economics for options spreads.

## Stage 7: Performance Same-Population Tests

Only run this after Stages 1-6 pass.

Primary unit:

- Trade episode, not account-day P&L.

Secondary units:

- Strategy-day P&L.
- Account-day P&L.
- Time-in-market-normalized return.

Tests:

- Bootstrap confidence interval for mean trade P&L difference.
- Bootstrap confidence interval for median trade P&L difference.
- Mann-Whitney U / rank-based distribution shift test.
- Kolmogorov-Smirnov test for full distribution shape.
- Permutation test on live-vs-replay labels.
- Binomial/Beta-binomial test for win-rate difference.
- Bayesian posterior for live mean P&L relative to backtest mean.
- Sequential drift test by day, with explicit multiple-testing control.

Effect sizes:

- Mean P&L delta.
- Median P&L delta.
- Win-rate delta.
- Profit-factor delta.
- Tail-loss delta.
- Sharpe/Sortino delta where sample size permits.
- Cliff's delta or rank-biserial correlation.

Minimum reporting:

- Sample size.
- Confidence intervals.
- P-values or posterior probabilities.
- Practical significance threshold.
- Data exclusions.
- Mismatch filters used.

## Stage 8: Regime Conditioning

Live and historical samples must be conditioned by market regime before drawing
strong conclusions.

Suggested conditioning variables:

- Realized volatility.
- VIX/VXX proxy level.
- Trend regime.
- Intraday time bucket.
- Spread width/liquidity.
- DTE.
- Moneyness.
- Strategy family.
- Direction.
- Long vs short.
- Holding-time bucket.

Do not compare a tiny live sample from one high-volatility week to a broad
multi-year backtest without conditioning.

## Stage 9: Decision Rules

Declare decision rules before looking at results.

Examples:

- Promote only if behavior parity passes and live mean P&L is not materially
  below replay after costs at 80% confidence.
- Pause if live/replay intent mismatch exceeds 5% for deterministic strategies.
- Pause if active feature parity has any non-neutralized zero-filled model
  input.
- Reduce sizing if live drawdown breaches replay 95th-percentile expected
  drawdown for the same number of trades.
- Require at least N matched live trades before judging performance.

## Stage 10: Deliverables

For each strategy/account cohort:

- `manifest.json`
- `feature_parity.md`
- `live_tape.csv`
- `replay_tape.csv`
- `alignment_report.md`
- `fill_alignment_report.md`
- `episodes_live.csv`
- `episodes_replay.csv`
- `same_population_report.md`

The report should end with one of:

- `PASS`: behavior and performance compatible.
- `WATCH`: behavior compatible, performance sample too small or mildly weak.
- `FAIL-BEHAVIOR`: live and replay do not trade the same.
- `FAIL-FILLS`: fill assumptions not compatible.
- `FAIL-PERFORMANCE`: behavior compatible but outcomes materially worse.
- `BLOCKED-DATA`: required artifacts missing or unreliable.

## Immediate Implementation Plan

1. Refresh live feature parity baseline over all existing captures.
2. Regenerate corrected neutralization list if needed.
3. Export live tapes for all reliable live days.
4. Build Basilisp replay over the same live dates.
5. Emit replay tape with the same schema.
6. Assemble aligned episodes.
7. Run behavior alignment metrics.
8. Only then implement same-population statistical tests.

## Known Current Gaps

- Trade-level replay over the live paper window is not yet generated.
- Existing old Python backtest artifacts lack the date map needed for direct
  old-parquet trade alignment.
- Live feature parity no longer shows active zero-filled or degenerate features
  as of the June 29 baseline, but it still shows active price-level
  offset/low-variance features.
- Model-materiality audits now exist for XGB split usage and offline
  prediction-delta testing. We still need to decide whether price-level
  features should be transformed, neutralized, or explicitly accepted as
  market-regime shift.
- Paper fill sample is still sparse; sim fills should remain conservative.
