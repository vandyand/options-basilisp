# Panda Core Calendar Forward Shadow

**Status:** deployed only as a quote-recording shadow; broker writes are absent

## Frozen research rule

The forward shadow observes SPY, QQQ, and IWM in fixed priority order. At
12:00:00 ET it selects the common put strike nearest the back-expiration
synthetic-forward ATM. At 12:01:00 ET it records a marketable one-contract
calendar entry, and it records the marketable close at 15:15:00 ET exactly
five later market sessions after entry.

The expiration selector is intentionally symbol-specific because the frozen
SPY maturity-grid study and the later cross-symbol replication did not use the
same listing convention:

- SPY selects any listed front expiration from 7-9 DTE nearest 7 DTE and any
  listed back expiration from 37-47 DTE nearest 42 DTE.
- QQQ and IWM select the nearest Thursday/Friday weekly-cycle expiration to 7
  DTE within 3-10 DTE and the nearest standard monthly expiration to 42 DTE
  within 21-63 DTE.

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
