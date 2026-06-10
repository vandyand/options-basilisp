# Engine State And Recovery v0.1

## 1. Purpose

This document defines:

- the canonical engine state model
- what is durable vs transient vs derived
- snapshot expectations
- startup and recovery semantics
- broker reconciliation rules

This is a binding companion to the top-level architecture spec and the event/command taxonomy.

## 2. Design Intent

The engine must be able to:

1. make decisions deterministically
2. survive interruption
3. recover unresolved work correctly
4. reconcile with external broker truth safely
5. continue without duplicating exposure

The current Python system's hardest problems sit exactly here. The rewrite should treat this area as core architecture, not implementation detail.

## 3. Engine State Layers

The engine state is divided into three classes:

1. durable state
2. transient runtime state
3. derived state

## 3.1 Durable State

Durable state is either canonical truth or persisted acceleration data.

Durable items:

- canonical fact log
- latest accepted snapshot
- recovery watermarks
- control-plane revision in force
- unresolved order lineage recorded in facts
- strategy-local persisted state if included in snapshots

## 3.2 Transient Runtime State

Transient runtime state exists only to make the active process efficient.

Transient items:

- in-memory adapter clients
- latest polled raw payloads before normalization
- current command batch awaiting execution
- temporary retry counters
- in-flight telemetry buffers

Transient runtime state must be safe to lose.

## 3.3 Derived State

Derived state is recomputable from durable state.

Derived items:

- current positions
- current cash
- realized and unrealized P&L
- open order view
- latest signal posture
- risk exposure view
- health dashboard view

Derived state may be cached in memory or in snapshots but is not canonical truth.

## 4. Canonical Engine State Shape

At a conceptual level, engine state contains:

- engine metadata
- control-plane state
- strategy state map
- unresolved order state
- ledger-derived portfolio state
- recovery cursors and watermarks
- health and degradation state

## 4.1 Engine Metadata

Fields:

- `run-id`
- `engine-version`
- `mode`
- `started-at`
- `current-control-plane-revision`

## 4.2 Strategy State Map

For each strategy:

- strategy metadata reference
- signal-local state
- risk-local state if any
- execution-local state if any
- last processed market timestamp
- last decision timestamp
- latest posture view

Strategy-local state should be explicit and serializable.

No hidden closure state should be required for correctness.

## 4.3 Unresolved Order State

This is one of the most important state shards.

For each unresolved order intent:

- `order-intent-id`
- `strategy-id`
- `account-id`
- `instrument-id`
- intended quantity and side
- broker route target
- broker-order-id if known
- current internal order lifecycle status
- creation fact id
- latest broker update fact id if any
- latest fill fact id(s) if any
- cancellation requested flag if applicable

This state must be reconstructible from facts and snapshot data.

## 4.4 Portfolio State

The engine may hold derived portfolio state for efficiency:

- open lots
- net positions
- cash
- exposure
- realized P&L
- unrealized P&L

The source of truth remains ledger facts plus accepted snapshot.

## 4.5 Watermarks And Cursors

The engine state must track:

- latest fact-log offset incorporated into snapshot
- latest market data offset or timestamp consumed
- latest broker observation offset or timestamp consumed
- latest control-plane revision observed

Without explicit watermarks, recovery will be ambiguous.

## 4.6 Health And Degradation State

The engine should track:

- current health level
- active degradations
- dependency availability summary
- last successful snapshot write
- last successful broker poll
- last successful market-data normalization

## 5. State Classification Rules

### 5.1 Persisted-In-Snapshot

These should normally be persisted:

- engine metadata sufficient for recovery
- strategy-local serializable state
- unresolved order state
- watermarks
- control-plane revision
- optionally portfolio derived state

### 5.2 Not Persisted

These should not normally be persisted:

- adapter clients
- raw provider SDK objects
- ephemeral retry counters with no correctness significance
- transient command queues not reflected as facts

### 5.3 Derived-On-Recovery

These may be recomputed:

- positions
- cash
- P&L
- current posture view
- reporting views

## 6. Decision Cycle Model

Each decision cycle follows this conceptual order:

1. ingest and normalize new external observations
2. append resulting observation facts
3. fold facts into current engine state
4. compute strategy decisions
5. produce order intents and operational commands
6. append decision facts
7. dispatch commands to adapters
8. normalize adapter outcomes into facts
9. append outcome facts
10. update state
11. persist snapshot on configured cadence

The important rule is:

`order-intent-created` is recorded before broker acknowledgement exists.

That creates the canonical internal anchor for later reconciliation.

## 7. Engine Sub-State Machines

The engine contains at least these sub-state machines:

1. strategy lifecycle
2. order lifecycle
3. recovery lifecycle
4. health lifecycle

## 7.1 Strategy Lifecycle

Minimum strategy states:

- `inactive`
- `warming-up`
- `active`
- `degraded`
- `halted`

Transitions must be explicit and event-driven.

## 7.2 Order Lifecycle

Minimum order states:

- `intent-created`
- `submit-requested`
- `acknowledged`
- `partially-filled`
- `filled`
- `cancel-requested`
- `cancelled`
- `rejected`
- `orphaned-needs-reconcile`

This lifecycle is internal and canonical.

Broker-specific lifecycle terms must be normalized into it.

## 7.3 Recovery Lifecycle

Minimum recovery states:

- `not-started`
- `loading-snapshot`
- `replaying-facts`
- `reconciling-broker`
- `ready`
- `degraded-ready`
- `blocked`
- `recovery-failed`

## 7.4 Health Lifecycle

Minimum health states:

- `starting`
- `healthy`
- `degraded`
- `stopping`
- `stopped`

## 8. Snapshot Model

## 8.1 Snapshot Purpose

Snapshots exist to reduce replay cost and speed restart.

Snapshots do not replace the need for:

- append-only facts
- broker reconciliation
- durable watermarks

## 8.2 Snapshot Contents

A snapshot should contain:

- snapshot metadata
- run-independent recovery metadata
- control-plane revision in force
- strategy-local state
- unresolved order state
- latest watermarks
- optional derived portfolio state
- optional health summary

## 8.3 Snapshot Metadata

Fields:

- `snapshot-id`
- `snapshot-version`
- `engine-version`
- `written-at`
- `fact-watermark`
- `market-watermark`
- `broker-watermark`
- `control-plane-revision`

## 8.4 Snapshot Rules

1. A snapshot is only valid together with its watermarks.
2. A snapshot may be discarded and rebuilt from facts.
3. Snapshot writes must be atomic.
4. Corrupt snapshots must fail loud and fall back to prior good recovery path.

## 8.5 Snapshot Acceptance Rules

A snapshot should only be accepted for recovery if:

- its schema version is supported
- its control-plane revision can still be validated
- its watermarks are internally consistent
- its unresolved order shard can be parsed without ambiguity

If any of these checks fail, the engine must reject the snapshot and recover from an older valid snapshot or the fact log alone.

## 9. Recovery Modes

There are four recovery modes.

## 9.1 Fresh Start

No usable snapshot and no prior facts relevant to the run.

Behavior:

- initialize empty engine state
- start normal intake

## 9.2 Warm Restart

Usable snapshot exists and recent facts exist after its watermark.

Behavior:

- load snapshot
- replay facts after watermark
- reconcile unresolved orders
- continue

## 9.3 Crash Recovery

Process died mid-session with unresolved external work.

Behavior:

- load latest valid snapshot
- replay facts after watermark
- query broker for unresolved order truth
- normalize broker truth into facts
- reconcile state
- continue

## 9.4 Replay Recovery

Historical replay mode.

Behavior:

- load optional replay snapshot
- consume historical normalized events
- do not consult live broker truth

## 9.5 Recovery Outcomes

Recovery should terminate in one of three outcomes:

- `ready`: recovery completed and the engine may trade
- `degraded-ready`: recovery completed but one or more non-fatal degradations remain visible
- `blocked`: recovery found ambiguity that could create unsafe exposure

`blocked` is a valid and necessary outcome.

## 10. Recovery Algorithm

The canonical recovery algorithm is:

1. load control-plane artifact
2. validate configuration and routing
3. locate latest valid snapshot
4. load snapshot metadata and watermarks
5. read all canonical facts after snapshot watermark
6. fold those facts into engine state
7. derive unresolved order set
8. query broker for unresolved truth where the mode permits
9. normalize broker results into canonical facts
10. fold reconciliation facts into state
11. derive final projections
12. emit `recovery-completed`
13. enter normal runtime

## 10.1 Why Broker Reconciliation Is Separate

Broker reconciliation must happen after fact replay because:

- internal truth should be restored first
- reconciliation requires a candidate unresolved set
- external broker truth is only meaningful relative to unresolved intent lineage

## 11. Broker Reconciliation Model

Broker reconciliation exists to close uncertainty gaps, not replace internal history.

## 11.1 Reconciliation Inputs

Inputs:

- unresolved order set
- broker-order-id correlations already known
- order-intent lineage
- broker query results

## 11.2 Reconciliation Outputs

Outputs:

- normalized broker status facts
- normalized fill facts
- orphan detection facts where needed
- degradation or fault facts if ambiguity remains

## 11.3 Reconciliation Cases

### Case A: Intent Exists, Ack Exists, No Fill Yet

If broker still shows order open:

- record status fact
- remain unresolved

If broker shows rejected or cancelled:

- record corresponding status fact
- mark resolved

### Case B: Intent Exists, Ack Exists, Fill Occurred Before Crash

If broker returns fill:

- record `fill-observed`
- resolve order lifecycle
- update derived portfolio state

### Case C: Intent Exists, Ack Missing Internally, Broker Shows Order Exists

This means external truth outran local durable acknowledgement handling.

Behavior:

- record normalized broker status fact tied back to the known order intent if identity permits
- do not issue a second submit

### Case D: Intent Exists, Broker Shows Nothing

If broker confirms no such order and no fill:

- mark unresolved item as reconciliation anomaly
- do not silently resubmit until policy decides whether resubmission is safe

### Case E: Broker Returns Fill With Unknown Intent Lineage

Behavior:

- record anomaly fact
- fail loud or degrade according to policy
- do not silently attach the fill to a guessed strategy or order

### Case F: Cancel Requested, Fill Arrives Before Cancel Confirmation

Behavior:

- record the fill fact
- record subsequent cancel outcome if it arrives
- resolve portfolio state from fill truth, not from cancel intent alone
- do not treat a locally requested cancel as evidence that no fill occurred

### Case G: Broker Returns Open Order With No Known Internal Intent

Behavior:

- record anomaly fact tied to broker identity
- block automatic adoption into a strategy unless an explicit recovery policy can prove lineage
- prefer operator-visible reconciliation over guessed attachment

## 12. Duplicate Prevention Rules

### 12.1 Submit Duplication Rule

The engine may only submit an intent if it cannot prove that the same intent has already been accepted or completed.

### 12.2 Fill Duplication Rule

The engine must deduplicate fills based on canonical fill identity rules, not naive object equality.

### 12.3 Ack Duplication Rule

Multiple identical acknowledgement observations must converge to the same internal state.

### 12.4 Cancel Race Rule

Cancel requests and fills may cross in flight.

The engine must treat:

- fill truth as portfolio truth
- cancel acknowledgements as order-lifecycle truth

These are related, but not interchangeable.

## 13. Watermark Rules

Watermarks should be tracked independently for:

- fact log
- market observations
- broker observations
- control-plane revision stream if externalized

One global timestamp is not sufficient.

Different streams move at different rates and have different recovery semantics.

## 14. Mode-Specific Recovery Behavior

## 14.1 Live And Paper

- broker reconciliation is required
- unresolved orders block naive resubmission

## 14.2 Sim

- reconciliation may happen against simulator state rather than external broker truth
- same internal order lifecycle model should still apply

## 14.3 Replay

- no live broker reconciliation
- uncertainty is resolved from replay source only

## 15. Degradation Rules

The engine may degrade in place for:

- temporary market-data gaps
- temporary broker query failures
- temporary snapshot write failures

The engine must fail loud for:

- invariant violations
- ambiguous order lineage that could create duplicate exposure
- corrupt canonical fact storage

## 16. What The Engine Must Never Do

The engine must never:

- rebuild critical order lineage from guesses
- silently reissue uncertain submits
- infer fills from mutable adapter memory alone
- silently adopt unknown broker orders into a strategy
- allow strategy state to depend on unpersistable hidden closures
- treat snapshots as canonical truth

## 17. Recovery Acceptance Tests

The design is only acceptable if the implementation can pass these scenarios:

1. crash after `order-intent-created` but before broker submit
2. crash after broker submit but before internal ack handling
3. crash after ack but before fill observation
4. crash after fill observation but before snapshot write
5. duplicate broker status or fill replay after restart
6. replayed recovery converges to uninterrupted-run state
7. unresolved orders do not create duplicate exposure after recovery

## 18. Required Golden Properties

The engine must satisfy:

1. state convergence between uninterrupted and restarted runs
2. exact lineage from decision to fill
3. deterministic fact folding
4. explicit anomaly surfacing when reconciliation is ambiguous

## 19. Immediate Next Design Tasks

The next architecture round should refine:

1. exact snapshot payload shape
2. exact identity rules for order intents, broker orders, and fills
3. exact reconciliation policy for ambiguous broker truth
4. exact fact-log and storage partitioning strategy
