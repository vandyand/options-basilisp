# Analysis And Sim Fill Calibration

Local-only evidence tooling. These commands read `facts.db` snapshots and write
analysis artifacts; they do not contact Alpaca or mutate live broker state.

## Live Behavior Tape

```bash
PYTHONPATH="components/analysis.core/src" \
  .venv/bin/basilisp run scripts/export_live_tape.lpy -- \
  --facts live_runtime/hetzner-snapshots/steve-session-2026-06-25-facts.db \
  --out live_runtime/analysis/live_tape_20260625.csv
```

The tape normalizes signal, order-intent, and fill facts into one chronological
CSV. Use this before P&L significance tests: if live behavior does not match the
backtest/replay behavior, P&L distribution comparisons are not meaningful.

## Sim Fill Calibration

```bash
PYTHONPATH="components/analysis.core/src" \
  .venv/bin/basilisp run scripts/calibrate_sim_fills.lpy -- \
  --facts live_runtime/hetzner-snapshots/steve-session-2026-06-25-facts.db \
  --out live_runtime/analysis/sim_fill_calibration_20260625.edn \
  --max-lag-seconds 90 \
  --prior-strength 30
```

The estimator measures Alpaca-paper option fill improvement versus crossing
Theta bid/ask, buckets by side and spread width, shrinks sparse bucket estimates
toward the global estimate, and emits conservative improvements. Conservative
means lower-quartile improvement, floored at zero.

Jun 25 initial result:

```edn
{:input/option-fills 187
 :input/matched-fills 112
 :global {:median-improvement 0.009999999999999787
          :p25-improvement -0.06000000000000005
          :conservative-price-improvement 0.0}}
```

This supports a no-improvement default for sim fills until more clean paper-fill
data proves otherwise.

## Applying To Local Sim

`scripts/launch_vol_term_sim.lpy` defaults to `SIM_PRICE_IMPROVEMENT=0.00`.
To use a generated artifact:

```bash
SIM_FILL_CALIBRATION=live_runtime/analysis/sim_fill_calibration_20260625.edn \
  .venv/bin/basilisp run scripts/launch_vol_term_sim.lpy
```

The sim broker uses the calibration only in quote-price mode and still caps any
improvement at mid. If no calibration is supplied, explicit
`SIM_PRICE_IMPROVEMENT` still works.

## Backtest Parity Blocker

The old directional backtest trade parquets use `entry_day` / `entry_min`
indices. The expected `date_map_5yr.json` / `date_map_5yr_v1.json` files were
not present in the local Data-Preprocessor checkout when checked on
2026-06-25. Direct historical-trade alignment needs that map recovered or a
dated backtest/replay regenerated over the live paper window.

