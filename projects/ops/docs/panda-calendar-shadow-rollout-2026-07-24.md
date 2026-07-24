# Panda Core Calendar Forward Shadow

**Status:** deployed only as a quote-recording shadow; broker writes are absent

**Current release:** `20260724T190043Z`, policy
`dual-selector-observation-v2-2026-07-24`, Git commit `812a2d3`

## Frozen research rule

The forward shadow observes SPY, QQQ, and IWM in fixed priority order. At
12:00:00 ET it selects the common put strike nearest the back-expiration
synthetic-forward ATM. At 12:01:00 ET it records a marketable one-contract
calendar entry, and it records the marketable close at 15:15:00 ET exactly
five later market sessions after entry.

The v2 forward design records two versioned selectors for every symbol:

- `GM`, the primary research candidate, selects any listed front expiration
  from 7-9 DTE nearest 7 DTE and the nearest standard-monthly back expiration
  to 42 DTE within 21-63 DTE.
- `GG`, the research comparator, uses the same granular front and any listed
  back expiration from 37-47 DTE nearest 42 DTE.

Both selectors are observed for SPY, QQQ, and IWM. Only `GM` is eligible for
the constrained 2x portfolio; `GG` is always marked research-only. Selector
comparison is therefore not confounded with symbol identity.

The fifth market session comes from Alpaca's read-only market calendar. A
candidate is skipped when its short option expires before that exit session.
This preserves the historical eligibility rule across weekends and holidays;
it does not equate "five sessions" with an arbitrary number of calendar days.

## Account and risk contract

- Dedicated broker account: Panda, Alpaca paper, approximately $100,000 equity.
- Account capability required by every run: ACTIVE, unblocked, Level 3 options.
- Individual entry-debit ceiling: 2.5% of current equity.
- Aggregate active entry-debit ceiling: 10% of current equity.
- Aggregate active short-put assignment notional ceiling: 2.0 times equity,
  effective prospectively under policy
  `assignment-notional-2x-2026-07-24`.
- Candidate priority is fixed as SPY, then QQQ, then IWM. It is not reordered
  using observed forward outcomes.
- This ceiling is a conservative assignment-bridge stress rule, not a claim
  about the spread's economic maximum loss or Alpaca's margin calculation.

The first July 24 entry receipt was captured under the original 1x policy and
used the cross-symbol Thursday/Friday/standard-monthly selector for all three
symbols. It is preserved as an immutable operational diagnostic. It must not
be relabeled as an exact SPY 7/42 maturity-grid observation. The per-symbol
selector correction and 2x risk policy apply only to later entry receipts.

## July 24 selector follow-up

The completed matched historical comparison now favors expiration flexibility
for the **front** leg on all three symbols. Averaged across back-leg choices,
the flexible-front one-lot P&L effect was +$17.85 for SPY, +$24.73 for QQQ,
and +$9.37 for IWM; all three remained positive after cluster inference and
Holm correction. Back-expiration flexibility had no reliable positive P&L
effect. A standard-monthly back was slightly more capital-efficient on the
shared four-cell portfolio sample.

These findings do not retroactively alter existing receipts. With explicit
user authorization, the quote-only shadow was promoted prospectively to the
granular-front + standard-monthly-back candidate for all three symbols, with
fully granular retained as a research comparator. The versioned migration
keeps old and new observations distinguishable. It does not authorize paper
orders. The full evidence and limitations are recorded in
`projects/ops/docs/calendar-expiration-selector-comparison-2026-07-24.md`.

## Observation ledger versus constrained portfolio

Version 2 deliberately separates two questions that v1 combined:

1. **What happened to every candidate?** Every GM and GG candidate receives an
   immutable entry receipt, active observation, five-session exit quote, and
   executable P&L reconstruction. Risk-rejected candidates remain observable.
2. **What would the frozen portfolio have admitted?** Only GM candidates enter
   the SPY-then-QQQ-then-IWM allocator. The 2.5% individual debit, 10%
   aggregate debit, and 2x assignment-notional limits remain unchanged.

`portfolio_admitted=false` observations never contribute debit or assignment
notional to the constrained exposure calculation. Legacy v1 positions lack
that field and are intentionally treated as admitted so migration cannot hide
existing exposure. Status output reports constrained exposure and total active
observations separately.

The isolated migration smoke test copied the live v1 state and produced six
v2 observations plus the existing legacy SPY position. It admitted primary
SPY and IWM, rejected primary QQQ on the 2x notional limit, retained all three
GG comparators, and reported seven total observations but only three admitted
positions. A synthetic future exit closed all seven; replaying the exit was
idempotent. Every broker check remained flat and both no-order assertions
remained false.

The validated release was promoted after the July 24 v1 exit timer completed
successfully. Its deployment receipt is
`/opt/stevetrading/shared/panda-calendar-v1/deployments/dual-selector-observation-v2-2026-07-24/receipt.json`.
Post-promotion status preserved the legacy SPY observation, reported the v2
policy current, and showed zero Panda broker positions and orders.

## Paper-order data collection boundary

Raising paper-account limits is not required to collect selector, quote-path,
or counterfactual executable-P&L evidence. The unconstrained observation
ledger supplies that coverage without depending on Alpaca's paper fill model
or creating assignment operations.

Actual paper orders add different evidence: multi-leg acceptance, fill
latency, partial fills, buying-power treatment, early assignment, and close
behavior. If paper writes are later authorized, they must use a separate
versioned policy. A stronger predicted signal may rank candidates inside that
policy but may not silently override its limits. Before increasing exposure,
freeze and validate:

- the signal and threshold known at entry;
- the maximum simultaneous contracts and per-symbol concentration;
- aggregate debit and assignment-bridge notional;
- multi-leg-only submission and naked-leg rejection;
- assignment and forced-close procedures;
- stop conditions for rejects, buying-power drift, or state divergence.

A small paper-order sentinel cohort is the appropriate first fill-quality
experiment. The unconstrained shadow should continue recording every candidate
in parallel, so research coverage does not depend on how many orders the
broker accepts.

## Entry weekday and cadence

The frozen research generated candidates on every eligible session and
allowed overlapping five-session positions subject to the entry-known risk
limits. It was not a once-per-week or Friday-only rule. The forward runner
therefore evaluates the portfolio every weekday. A symbol can be skipped
because its selected short leg expires before the five-session exit, or because
an active-position limit prevents admission.

A post-hoc weekday summary did not identify one consistent best weekday. SPY's
mean executable return declined from 18.05% on Monday to 9.77% on Friday, but
QQQ was strongest on Thursday and IWM was strongest on Friday. QQQ and IWM had
only one and three Monday observations respectively. These overlapping,
unequal samples are descriptive and do not authorize a weekday filter. The
shadow retains every eligible weekday to avoid selecting a calendar day after
seeing its historical outcome.

## Safety boundary

`scripts/panda_calendar_shadow.lpy` has no broker POST function or order-submit
branch. `orders_enabled` and `broker_orders_submitted` are durably stored as
false and rechecked whenever state is loaded. The Alpaca calls are read-only:
account, positions, open orders, and market calendar. Any unexpected Panda
position or open order makes the shadow fail closed.

The shadow does not control the ThetaData terminal. Its services merely query
`127.0.0.1:25503`; an unavailable terminal causes a failed capture. It is not
part of the six-bot process and therefore does not inherit that process's daily
15:45 flattening behavior.

## Durable evidence and recovery

The deployment root is `/opt/stevetrading/shared/panda-calendar-v1`. Raw
ThetaData and Alpaca responses are written beside immutable entry/exit
receipts with SHA-256 hashes. `state.json` tracks active shadows and their
five-session exits. If a process stops after writing a receipt but before
updating state, rerunning the phase applies the existing receipt instead of
recapturing or duplicating the shadow position.

The timers are:

- 09:40 ET: read-only Panda/ThetaData/state preflight;
- 11:59:15 ET: start and wait for the 12:00 decision and 12:01 quote capture;
- 15:14:15 ET: start and wait for any due 15:15 exit capture.

All timers use the `America/New_York` timezone explicitly. A persistent timer
started too late still fails the runner's 45-second lateness gate instead of
recording a misleading off-clock quote.

## Gates before any paper order implementation

Paper orders require a separate code change and explicit authorization. Before
that change, all of the following must pass:

1. Complete, hash-verifiable SPY/QQQ/IWM decision and entry receipts.
2. A successful restart/idempotency recovery exercise.
3. Correct five-session 15:15 exit capture and P&L reconstruction.
4. Continued static and runtime proof that this deployed version cannot write
   broker orders.
5. No unexplained Panda broker position, order, or buying-power drift.
6. Separate validation of Alpaca multi-leg order construction, recognition,
   assignment behavior, and reject handling without exposing a naked leg.
7. An explicit go/no-go decision based on the forward evidence.
