# Market-Data Research and Collection Charter

**Status:** governing design contract

This charter records the decisions that govern source admission, raw-data
collection, representation search, and model evaluation. It is deliberately
more durable than an individual downloader or model experiment. Any proposal
that conflicts with this document must state the conflict and revise this
charter before implementation.

## 1. Non-negotiable principles

1. **Provenance first.** Every record remains identified by provider, dataset,
   transport, symbology, source symbol/contract, schema, entitlement, and
   collection receipt. Similar prices never make different feeds interchangeable.
2. **Causality first.** A live or historical representation at decision time
   `t` may use only source events at or before `t`. Selection, normalization,
   aggregation, imputation, and learned transforms obey the same rule.
3. **Event-native first.** Raw event data is the primary research corpus.
   Vendor OHLCV bars are secondary aggregations: useful as validation controls,
   but not the default primary model input.
4. **No silent filtering.** Every contract, event, time, source, or field
   filter is a versioned policy with an immutable receipt of the objects it
   selected.
5. **No source-wide claims.** Admission applies to one declared source and
   representation, never automatically to every product from a vendor.
6. **Immutable raw, separate derived.** Raw payloads and receipts are
   write-once; locally computed states, bars, features, and models live in a
   separate derived tree.

## 2. Single hard-parity policy

The project uses one accepted admission tier: **hard parity**. A source class
is hard parity when its declared model representation has passed its required
live-versus-historical evidence gate and is approved for research use.

The numerical admission floor is **99.0% shared-interior event parity**. The
rate is `matched / max(matched + live-only interior, matched + historical-only
interior)` after the class's declared field exclusions and event-time
intersection. A class below 99.0% is probationary or excluded. Passing this
floor does not turn 99.0% into 100%: receipts must preserve the exact measured
rate, residual fields, affected symbols, finalization status, and restrictions.

Hard parity does **not** erase evidence. A receipt must still state whether
the observed comparison was exact or had bounded, enumerated residuals, and
must retain any representation restrictions that made the comparison causal
and reproducible. For example, a raw event class may exclude transport
timestamps, ignore a documented packet-end flag, or prohibit count/order
features when those fields are not replay-stable. This is evidence metadata,
not a second admission tier.

The only remaining statuses are:

| Status | Meaning |
| --- | --- |
| `hard` | Approved for the declared representation; evidence and restrictions are mandatory. |
| `probationary` | May be captured for validation, but is excluded from model research until its gate passes. |
| `candidate` | Promising but insufficiently replicated or specified. |
| `quarantined` | Source contract is incompatible with the required live/historical replay. |
| `excluded` | Deliberately out of scope for the intraminute corpus. |

## 3. Current approved source classes

| Source | Declared hard representation | Current universe |
| --- | --- | --- |
| ThetaData options | OPRA option quote and trade events | `SPY`, `SPX`, `SPXW`, `VIX`, `VIXW` |
| ThetaData indexes | Causal carry-forward state from index price events | `NDX`, `RUT`, `RVX`, `SPX`, `TNX`, `VIX`, `VIXN` |
| Databento GLBX futures | MBP-1 and trade market representation, with retained residual rules | `ES.FUT`, `NQ.FUT`, `RTY.FUT`, `ZN.FUT`, `ZB.FUT`, `SR3.FUT`; MBP-1/trades available from 2010-06-06 |
| Databento GLBX ES/NQ futures options | MBP-1 and trades, event-time intersection with transport fields excluded | `ES.OPT`, `NQ.OPT`; ES has the Friday four-window exact study. NQ was explicitly admitted on 2026-07-20 with finalized MBP-1 and broader trade replication retained as follow-up evidence. |
| Databento EQUS Mini | MBP-1 and trade market representation, with retained residual rules | The qualified 15-symbol cohort remains recorded in the parity manifest. Steve's completed 20-symbol GCP corpus (`AAPL`, `AMZN`, `AVGO`, `GME`, `GOOG`, `HYG`, `LLY`, `META`, `MSFT`, `NFLX`, `NVDA`, `ORCL`, `QQQ`, `SPY`, `SQQQ`, `TLT`, `TQQQ`, `TSLA`, `TSM`, `VXX`) covers 2025-07-21 through 2026-07-17 and is the active schema-study universe; its additional symbols are undergoing an explicit 2026-07-21 live/historical expansion check before source-specific promotion. |

ThetaData stock data remains quarantined because live Nasdaq Basic and
long-horizon UTP/CTA history are different feed contracts. Alpaca IEX remains
available as prior parity evidence but is not in the active corpus because its
single-exchange view is redundant with the broader Databento equity feed.
Vendor Greeks and open interest remain excluded from the intraminute corpus.
The ES futures and NQ futures-option parents are hard-qualified under the
stated event-time boundary rule. NQ's admission is owner-directed and does not
erase its pending finalized recheck. SR3 futures are hard-qualified under the
project's 99% floor with their measured residuals retained; RTY, ZN, and ZB
returned no available option contracts under the tested option parents.

## 4. Collection is a constrained decision problem

There is no subjective pre-alpha “relevance” score. A source first passes
binary feasibility gates: declared provenance/parity, accessible entitlement,
causal representation, measured vendor cost, storage budget, compute budget,
and latency budget.

Among feasible data groups, selection optimizes incremental out-of-sample
utility under explicit constraints:

```text
maximize    U(S, g)
subject to  storage(S, g) <= B_storage
            compute(S, g) <= B_compute
            latency(S, g) <= B_latency
            vendor_cost(S, g) <= B_vendor_cost
```

`S` is a set of source groups and `g` is a causal representation function for
each group. For a trading study, utility is declared before the study and
includes net P&L, realistic execution costs, risk penalty, turnover, and any
latency penalty. A candidate’s value is conditional incremental utility:

```text
Delta-U(j | S) = U(S union {g_j(X_j)}) - U(S)
```

Standalone correlation, in-sample feature importance, and vendor reputation
are never sufficient admission evidence.

## 5. Finite, causal representation grammar

The possible aggregations of an event stream are infinite. Research therefore
searches a versioned, finite grammar rather than an unbounded function space:

- last-observed quote/book/trade state;
- spread, midpoint, imbalance, quote-revision, arrival, and signed-volume
  functions;
- causal filters over a declared log-spaced timescale bank;
- event-count, volume, dollar-volume, volatility, and imbalance windows;
- option-surface coordinates: time to expiry, log-moneyness, right, and
  liquidity;
- causal cross-source lead/lag functions.

Calendar bars are one optional member of this grammar, not a privileged source
representation. Learned compression is train-fold-only and must be causal.

Search uses successive halving or Bayesian optimization inside the training
and validation folds. Genetic search is not prohibited, but may be used only
inside the same bounded grammar and inner folds; it never sees an outer test
or final lockbox period.

## 6. Evaluation and anti-overfitting protocol

Every source or representation experiment uses chronological, purged,
embargoed walk-forward splits.

1. Training folds fit models and learned transforms.
2. Inner validation selects source groups and grammar parameters.
3. Outer folds evaluate the frozen selection.
4. A final lockbox period remains unseen until the research decision is fixed.

Promotion requires positive incremental utility across multiple outer folds,
stability across stated market regimes, realistic costs, and uncertainty
estimation with a time-series/block bootstrap. The experiment ledger records
all attempted hypotheses so repeated search cannot be mistaken for discovery.

## 7. Option-chain discovery and adaptive sampling

ThetaData option quote ticks are too large for indiscriminate full-chain,
all-session archival. Contract selection must be a causal, measurable sampling
design rather than a fixed list of named expirations or strikes.

Each seed session has two complementary captures:

1. **Full-chain discovery windows.** Short, pre-registered event-native
   windows sampled across opening, midday, and closing time strata, plus a
   reproducible random component. They expose the complete available contract
   distribution.
2. **All-session stratified panel.** Contracts selected from cells of
   `(root, DTE quantile, log-moneyness quantile, right, liquidity quantile)`
   using only information available at selection time. The selected contract
   list and source state are persisted before collection.

The discovery windows estimate coverage and the panel supplies sustained event
sequences. Subsequent budget allocation uses conservative uncertainty bounds
on conditional incremental utility while retaining a fixed exploration share;
rare regimes are not silently starved by early apparent winners.

**Current phase restriction:** this sampling design is deferred. The completed
15-minute full-chain window is sufficient to reject indiscriminate tick
retrieval operationally. No additional full-chain discovery window or
all-session panel may be downloaded until a vendor-side request contract passes
the historical acquisition gate in section 9. Local compaction research is
also deferred during this gate.

## 7.1 Unequal historical horizons

For every hard-parity class, retain the maximum history that passes the
measured cost, storage, and retrieval gates. A shorter history for one
modality is not a reason to discard its valid recent data, and a longer
history for another modality is not a reason to truncate it automatically.

Models must nevertheless respect the observable-history boundary. A
long-history backbone may be trained on features available through its full
period; source-specific encoders may be trained on each modality's own valid
period; and a fusion/gating layer may be trained only on the chronological
overlap where all of its inputs existed. Missing data are never backfilled as
zeros or treated as though the source had existed earlier. Availability masks
and modality-dropout robustness tests are trained and evaluated within the
overlap, never inferred from calendar time alone.

Consequently, the collection target is maximum valid raw history by declared
class, while promotion still depends on walk-forward incremental utility and
stability across regimes. A greater number of older observations is not by
itself evidence that they improve a current model.

## 8. Storage and operational policy

The raw corpus root is `D:\\SteveTradingData` and its layout is governed by
`resources/market-data/collection-pipeline-v1.edn`. Plan against a **4.5 TB
maximum corpus allocation**, leaving the remaining free space for staging,
archive-finalization rechecks, quarantine, manifests, and filesystem safety.

Every Databento historical request is quoted before submission and defaults to
a zero-dollar approval ceiling. Storage estimates are measured from actual
first-session payloads and recorded in the manifest; they are never inferred
only from a vendor estimate.

## 9. Historical acquisition gate and revised rollout

The immediate objective is to find a vendor-side request contract that can
retrieve the complete selected corpus for two years in at most 24 hours. The
shared gate is 3,600 end-to-end seconds per representative month, approximately
171 seconds per trading session. This is a budget for the complete corpus, not
one hour per source.

The governing plan is
`resources/market-data/historical-acquisition-gate-v1.edn`.

1. Use metadata, existing receipts, and already-captured payloads to estimate
   monthly billable bytes, wire bytes, cost, and current-pipeline wall time. No
   bulk payload may be requested during this step.
2. Reject observed request forms that cannot plausibly meet the shared gate.
   ThetaData five-root full-chain option quote/trade ticks have already failed
   this gate; do not repeat that request. SPY trade-only CSV is a distinct
   request contract and must not inherit that rejection.
3. Run only bounded, receipt-backed delivery pilots for forms that remain
   plausible. The immediate pilots are Databento batch DBN/Zstd with controlled
   parallelism and small ThetaData vendor-side forms for which no metadata size
   estimate exists. A pilot never expands automatically.
4. Admit a request contract only after an end-to-end representative-month
   measurement passes the 3,600-second gate, the 4.5-TB corpus gate, parity,
   provenance, and cost gates.
5. Download historical data only after admission. Evaluate every admitted
   input against the SPY-options task suite: directional, volatility, calendar,
   and skew. A source is judged by conditional out-of-sample contribution to
   these targets, not standalone correlation.
6. Revisit local compaction and representation search only after retrieval is
   feasible. It may reduce storage or compute, but it is not credited with
   reducing vendor retrieval time.

The Monday GLBX futures-options parity matrix remains a separate bounded live
evidence task. It does not authorize historical bulk collection.

### ThetaData SPY option-trade delivery contract

New SPY option-trade pilots use the vendor's streaming CSV representation.
The 2026-07-20 format probe found zero mismatches across 8,844 events and 14
fields relative to NDJSON while reducing wire bytes by 63.55%. HTTP gzip was
not honored by the terminal. Four-way concurrency reduced an identical
four-window workload from 60.88 to 41.01 seconds (1.48x); concurrency must
therefore be measured as shared-capacity acceleration, never assumed linear.
The five-session seed is complete, but a representative-month gate remains
mandatory before a two-year acquisition.

## 10. Required change control

Changing a source universe, parity representation, event field policy,
sampling stratum, aggregation grammar, budget, or evaluation objective
requires a versioned manifest revision and an experiment-ledger entry. This
prevents silent drift from the decisions recorded here.
