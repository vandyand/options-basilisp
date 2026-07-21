# Analysis Contract

This contract defines the common representation required before comparing live
paper, sim, replay, and backtest results.

## Why This Exists

Same-population testing is hard when each subsystem exports a different view of
the world. A valid comparison needs a shared contract for cohort identity,
feature behavior, trade behavior, trade performance, and execution assumptions.

The analysis pipeline must not compare P&L until the upstream representations
prove that both sides are the same experiment.

## Required Layers

1. **Cohort profile**

   Minimal identity for a run:

   - source side: live, paper, sim, replay, or historical backtest
   - account IDs
   - strategy IDs
   - account-strategy pairs
   - time range
   - event counts by normalized event type
   - artifact/config references when available

   This gate must pass before behavior alignment is meaningful. Different
   strategy universes, account universes, event-type coverage, or windows are
   separate experiments.

2. **Feature behavior table**

   Standardized feature evidence:

   - timestamp
   - account ID
   - strategy ID
   - feature manifest or model bundle ref
   - feature name
   - raw value
   - standardized value when applicable
   - neutralized flag
   - source input references
   - quality status, such as sane, zero-filled, nonfinite, degenerate,
     low-variance, offset, or missing

   Steve V2 uses the 918-feature Python stack. Vol/calendar/condor strategies
   and local bar strategies need their own exporters into this same shape.

3. **Behavior tape**

   Standardized chronological events:

   - signal
   - order intent
   - broker ack/reject/status
   - cancel intent/ack/reject
   - fill

   The existing `live-tape` / `replay-tape` schema is the canonical behavior
   layer for alignment.

4. **Trade episode table**

   Standardized performance units:

   - flat-to-position-to-flat episode
   - account ID
   - strategy ID
   - direction
   - instrument group
   - entry/exit time
   - entry/exit price and quantity
   - gross/net P&L
   - return on risk
   - holding time
   - data-quality flags for rejected, cancelled, missing-fill, or incomplete
     trades

   The existing episode exporter is the canonical trade-performance layer.

5. **Execution calibration**

   Standardized fill evidence:

   - option quote matched to fill
   - lag
   - spread
   - side
   - improvement vs bid/ask
   - conservative fill-policy estimate

   This determines whether replay/backtest fills are comparable to paper fills.

6. **Same-population statistics**

   P&L tests are allowed only after:

   - cohort gate passes
   - feature/data gate passes or has explicit acceptance
   - behavior alignment passes or mismatches are explained
   - execution/fill assumptions are declared
   - episode tables contain comparable completed trade units

## Current Status

- Steve V2 feature parity is improved but still `WATCH`, not `PASS`.
- Steve V2 now has deterministic replay plumbing through `engine-replay`:
  exported observation fixtures can drive the Python bridge and six strategy
  declarations through the sim broker. Exact live feature parity still requires
  capturing/replaying the bridge's separate 90-day option-chain inputs, because
  the live launcher previously fetched those outside the canonical market
  observation source.
- The June 25 same-pop run is invalid as a cohort because live Steve V2 Alpaca
  data was compared to replay vol-term sim data.
- The behavior tape and episode table exist and are usable as canonical layers.
- The missing work is exporter coverage and gating for every strategy family,
  especially vol/calendar/condor feature behavior and local bar-strategy replay
  parity.
