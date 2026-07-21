# Event-Stream Representation Study

**Status:** pre-download study protocol for the Monday 2026-07-20 ingestion decision.

## Purpose

Choose what to retain and derive from each declared hard-parity event class
without assuming either that every tick is valuable or that calendar bars are
sufficient. This is not a vendor-bar comparison: every candidate is derived
causally from the same retained raw event cohort.

The raw corpus is capped at 4.5 TB of the external volume. The remaining
space is reserved for staging, manifests, quarantine, and filesystem safety.

## Separate the two kinds of compression

1. **Physical compression** changes only storage encoding. It is lossless and
   is benchmarked by bytes, write/read throughput, and CPU.
2. **Representation compression** maps an event history to a smaller causal
   state or sequence. It is potentially lossy and must earn adoption through
   the protocol below.

No physical codec is considered a market representation, and no lossy
representation is permitted to overwrite its retained raw evidence.

## Candidate grammar

For every compatible source class, evaluate only the following versioned,
finite candidates. Candidates may be inapplicable where the source lacks
quotes, trades, or a book; inapplicability is a fact, not a zero-filled
feature.

| ID | Causal output | Parameters searched |
| --- | --- | --- |
| `raw-market-events` | Declared parity-safe quote/book/trade events | none; reference only |
| `state-on-change` | Last quote/book state plus all trades; duplicate state revisions removed only when the declared state is identical | field policy |
| `calendar-summary` | Locally constructed quote/trade state and OHLCVT summaries | 1 s, 5 s, 15 s, 60 s |
| `activity-summary` | Event-count, volume, notional, volatility, and imbalance windows | log-spaced threshold bank |
| `causal-filter-bank` | Last state, spread/midpoint, arrivals, signed-volume proxies, and causal filters | log-spaced half-lives/windows |
| `option-panel-state` | Option quote/trade state by root, DTE, log-moneyness, right, and liquidity cell | pre-registered panel allocation |

Vendor-produced OHLCV is a validation control only. MBO/L3 is not introduced
by this study unless separately admitted and budgeted.

## Measurements

Every raw capture and derived candidate receives an immutable study receipt
with:

- source, schema, symbology, time range, raw SHA-256, and selection receipt;
- raw and encoded bytes; bytes per event, active instrument, and trading
  minute;
- event-rate distribution by minute and instrument;
- materialization wall time, peak memory, read throughput, and live-update
  CPU/latency on a fixed local machine;
- causal state-reconstruction error at declared decision times relative to
  `raw-market-events`;
- source-specific parity restrictions and ambiguous-classification rate.

The first study cohort is a bounded seed: Friday's ES futures-options windows,
plus one-week event-native seeds for admitted classes after the ingestion
manifest is approved. It is not a production backfill.

## Decision rule

Let `g` be a candidate representation and `S` a source group. Its final
promotion value is estimated only with purged, embargoed walk-forward tests:

```text
U(g, S) = out-of-sample net utility after execution costs and risk penalty
```

The study retains the nondominated candidates in the vector:

```text
( -U, storage bytes, materialization compute, live latency, reconstruction loss )
```

subject to the charter's cost, 4.5 TB storage, causality, and parity gates.
A candidate is rejected when another candidate is no worse on every component
and strictly better on at least one. This Pareto rule avoids an arbitrary
single weight before the team has evidence for a particular storage or latency
trade-off.

Before sufficient history exists for `U`, the study may reject candidates only
for failed parity, causality, budget, or demonstrated inability to reconstruct
the pre-declared causal state. It may not call a representation alpha-positive
or select it for production from a short live sample.

## Historical-horizon rule

The collection target is maximum valid raw history by admitted class. Current
account availability is:

| Class | Earliest available event history | Collection implication |
| --- | --- | --- |
| Databento EQUS Mini MBP-1/trades | 2023-03-28 | Retain the full available period after the seed forecast passes. |
| Databento GLBX MBP-1/trades | 2010-06-06 | Backfill in cost/byte-gated chronological waves; do not truncate merely to match EQUS Mini. |
| ThetaData indexes | provider event history, to be probed per symbol | Compact candidate; include in the seed after receipt verification. |
| ThetaData options | provider event history, to be probed per root/contract | Full-chain all-session archival is not assumed feasible; use discovery plus causal stratified panels. |
| GLBX ES/NQ futures options | hard | Retain MBP-1 and trades under the event-time-intersection representation; continue scheduled finalized rechecks. |
| GLBX SR3 futures options | probationary | Capture/compare only until MBP-1 parity and ordinary trades are observed. |

Long-history and short-history modalities are trained with the charter's
separate backbone/encoder/fusion rule; shorter data are never fabricated for
earlier years.

## Monday decision deliverables

1. Raw-profile receipts for every Friday ES-options capture and finalized
   parity results for a concrete contract panel.
2. Measured storage and compute estimates for each hard source class from its
   seed, rather than vendor-wide guesses.
3. A cost-gated, chronological ingestion manifest naming the raw schemas,
   universe, historical range, and explicit exclusions.
4. A first Pareto set of causal representations. This is a research baseline,
   not a claim of trading edge.
