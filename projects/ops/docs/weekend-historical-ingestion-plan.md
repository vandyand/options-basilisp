# Weekend historical-ingestion plan

## Goal

Collect enough parity-qualified raw evidence to measure the storage, compute,
and signal-preservation trade-off without pretending that a blind multi-terabyte
backfill is itself a research result.

The governing optimization is the charter's constrained, out-of-sample
incremental utility problem. Before there is sufficient history to estimate
utility, a representation may be rejected for parity, causality, cost, storage,
or demonstrated reconstruction failure—but cannot be called superior merely
because it is smaller or more convenient.

## Non-negotiable controls

Every request must have all of the following before submission:

1. A hard-qualified source and declared representation.
2. A point-in-time symbol/contract selection receipt.
3. A Databento cost and byte quote, with an explicit ceiling.
4. Immutable raw DBN/vendor payload and SHA-256 receipt on `D:`.
5. A measured event profile: bytes, events, active instruments, events per
   minute, read/write time, and peak memory.
6. A separate derived benchmark for every representation candidate. Raw data
   is never overwritten by compression output.

## Collection waves

| Wave | Purpose | What is collected | Gate to continue |
| --- | --- | --- | --- |
| 0 | Prove the machinery | Definitions, cost quotes, receipt writing, volume health | Zero unreceipted writes; quote agrees with manifest |
| 1 | Establish broad event evidence cheaply | One week of raw **trades** for GLBX six-root futures basket, then compact index/event classes | All daily requests complete and profile receipts exist |
| 2 | Measure quote/book cost rather than guess | Fixed-duration, full-universe MBP-1 and trade windows | Several complete windows per source have enough temporal coverage to forecast a week |
| 3 | Evaluate representations | Apply causal, reproducible transforms to the measured full-universe seed; no instrument is omitted merely to make the seed smaller | Each candidate has an immutable raw parent, reconstruction test, and cost profile |
| 4 | Compare representations | Raw events, state-on-change, activity windows, causal filter banks, and option-panel state on the same seed | Nondominated Pareto set, with no parity or causality violation |
| 5 | Expand only justified data | Twenty sessions, then longer historical ranges by source | Walk-forward incremental utility is positive and stable after costs |

## Why trades come first

Trades are event-native and often much smaller than quote/book updates. They
give the representation study genuine market events, timing, price, and size
without immediately committing the project to terabytes of book revisions.
They do **not** replace book data; they establish a low-risk baseline and
measure the downloader, storage layout, profiler, and walk-forward plumbing.

## Quote/book full-window rule

The storage study must measure the full available universe for a source, not a
convenient subset of roots or contracts. For example, a GLBX futures request
contains all six declared roots and their exchange-listed instruments; an ES
futures-options request contains the full `ES.OPT` parent universe; an EQUS
Mini request contains all 15 declared equities/ETFs.

The only permitted operational adjustment is **time duration**, never symbol
or contract selection, during this measurement stage:

1. Request a complete one-hour window for the declared source universe.
2. Preserve the provider's quoted bytes/cost and the actual received bytes.
3. If the one-hour request exceeds the explicit operational byte/cost ceiling,
   do not drop instruments. Retry a complete 15-minute window for the exact
   same universe.
4. After several complete windows spanning distinct session regimes, estimate
   full-week storage from observed bytes/minute and events/minute, including a
   conservative uncertainty band.

This is not representation compression and not a model-universe decision. It
is an honest physical measurement of what full source data costs. A later
representation experiment may derive a smaller causal view from this complete
seed, but may never rewrite the physical measurement by selectively omitting
contracts, roots, or symbols first.

## Fixed-window measurement schedule v1

The first measurement day is 2026-07-10, a normal US session.  Each completed
request is the entire declared source universe, with MBP-1 and trades together.
The schedule deliberately samples different market-intensity regimes rather
than treating one quiet or noisy hour as representative:

| Regime | UTC window | US Eastern window | Sources |
| --- | --- | --- | --- |
| Cash open | 13:30–14:30 | 09:30–10:30 | GLBX futures, EQUS Mini, ES options |
| Active morning | 14:30–15:30 | 10:30–11:30 | GLBX futures, EQUS Mini, ES options — complete |
| Midday | 17:30–18:30 | 13:30–14:30 | GLBX futures, EQUS Mini, ES options |
| Cash close | 19:00–20:00 | 15:00–16:00 | GLBX futures, EQUS Mini, ES options |
| Globex overnight | 00:00–01:00 | 20:00–21:00 prior Eastern date | GLBX futures and ES options |

After this schedule, the weekly forecast is a stratified sum of observed
bytes/minute and events/minute for each source and regime. It will report the
observed mean, a conservative high-rate estimate, the assumptions used for the
number of weekly minutes in each regime, and the resulting raw-storage range.
It will not use a contract panel as an input.

## Observed full-universe evidence so far

The completed active-morning window demonstrates that a one-hour request is
currently operationally safe for the three Databento source universes:

| Source universe, 2026-07-10 14:30–15:30 UTC | MBP-1 | Trades | Total received |
| --- | ---: | ---: | ---: |
| GLBX six futures parents | 140,122,323 B; 5,321,242 events | 3,647,918 B; 180,742 events | 143,770,241 B |
| EQUS Mini 15-symbol universe | 67,077,833 B | 893,420 B | 67,971,253 B |
| Full ES.OPT parent | 284,979,404 B; 10,387,369 events | 63,773 B; 388 events | 285,043,177 B |

Provider preflight cost was $0 for each of these requests.  These are physical
raw-payload measurements, not compressed or contract-filtered estimates.

## Monday futures-options matrix

At the next active session, collect and later replay:

| Family | Required evidence |
| --- | --- |
| NQ options | Calls and puts across expiry, moneyness, right, and low/high activity strata |
| SR3 options | The same, with explicit coverage of rate-option expiry structure |
| RTY / ZN / ZB options | First resolve exact Databento parent symbology and live entitlement; then use the same capture/replay test if available |
| Futures spreads | Outright futures, simple calendar spreads, and active complex SR3 spreads as separate strata |

No result from ES is inherited by another root or spread subtype.

## Current action

Begin Wave 1 with a one-week GLBX raw-trade request for the six futures roots.
It is explicitly capped at $10 and 1 GiB; the provider quote must approve it
before download. The receipt becomes the first measured input to the storage
forecast, not a commitment to a broad backfill.
