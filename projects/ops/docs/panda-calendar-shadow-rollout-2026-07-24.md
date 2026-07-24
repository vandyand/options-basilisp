# Panda Core Calendar Forward Shadow

**Status:** deployed only as a quote-recording shadow; broker writes are absent

## Frozen research rule

The forward shadow observes SPY, QQQ, and IWM in fixed priority order. At
12:00:00 ET it selects the common put strike nearest the monthly
synthetic-forward ATM. At 12:01:00 ET it records a marketable one-contract
calendar entry: sell the nearest eligible approximately 7-DTE Thursday/Friday
put and buy the standard approximately 42-DTE monthly put at the same strike.
It records the marketable close at 15:15:00 ET exactly five later market
sessions after entry.

The fifth market session comes from Alpaca's read-only market calendar. A
candidate is skipped when its short option expires before that exit session.
This preserves the historical eligibility rule across weekends and holidays;
it does not equate "five sessions" with an arbitrary number of calendar days.

## Account and risk contract

- Dedicated broker account: Panda, Alpaca paper, approximately $100,000 equity.
- Account capability required by every run: ACTIVE, unblocked, Level 3 options.
- Individual entry-debit ceiling: 2.5% of current equity.
- Aggregate active entry-debit ceiling: 10% of current equity.
- Aggregate active short-put assignment notional ceiling: 1.0 times equity.
- Candidate priority is fixed as SPY, then QQQ, then IWM. It is not reordered
  using observed forward outcomes.
- This ceiling is a conservative assignment-bridge stress rule, not a claim
  about the spread's economic maximum loss or Alpaca's margin calculation.

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
