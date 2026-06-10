# Architecture Spec v0.1

## 1. Purpose

This document defines the initial architectural specification for the Basilisp rewrite of StevenTrading.

It is intended to establish:

- the structural shape of the system
- the runtime model
- the persistence and recovery model
- the core contracts between bounded contexts
- the initial migration strategy
- the acceptance criteria for correctness

This is a v0.1 design document. It is a directional and binding architectural baseline, not the final exhaustive implementation spec.

Companion specs:

- `EVENT_COMMAND_TAXONOMY_V0.1.md`: canonical fact, command, projection, and lineage language
- `ENGINE_STATE_AND_RECOVERY_V0.1.md`: canonical engine state partitioning, restart model, and broker reconciliation rules
- `CANONICAL_SCHEMAS_V0.1.md`: exact identifier, envelope, payload, and order-intent identity rules
- `ENGINE_STATE_MACHINES_V0.1.md`: explicit lifecycle states, transitions, guards, and terminal conditions
- `PERSISTENCE_SCHEMA_AND_STORAGE_LAYOUT_V0.1.md`: durable storage classes, truth boundaries, partitioning, and recovery read order
- `POLYLITH_WORKSPACE_AND_BOUNDARY_LAYOUT_V0.1.md`: initial workspace shape, component/base layout, and dependency edges
- `BROKER_ADAPTER_CONTRACTS_V0.1.md`: canonical broker commands, normalized outcomes, reconciliation, and error rules
- `MARKET_DATA_ADAPTER_CONTRACTS_V0.1.md`: canonical observation shapes, provenance, quality, and replay compatibility
- `CONTROL_PLANE_MANIFESTS_AND_VALIDATION_V0.1.md`: declarative rollout, routing, kill-switch, and activation semantics
- `OBSERVABILITY_AND_OPERATIONS_V0.1.md`: audit, metrics, health, and incident-operability rules
- `TESTING_AND_VERIFICATION_STRATEGY_V0.1.md`: test layers, golden properties, release gates, and regression rules
- `MIGRATION_AND_IMPLEMENTATION_PLAN_V0.1.md`: sequencing, parity, cutover, and risk-reduction milestones
- `STRATEGY_PIPELINE_AND_ARTIFACT_MODEL_V0.1.md`: strategy declaration, stage boundaries, artifact references, and compatibility rules
- `LEDGER_AND_PORTFOLIO_MODEL_V0.1.md`: canonical financial truth, lot model, cash model, and derived exposure rules

These companion specs are normative for v0.1.

## 2. Scope

This spec covers:

- system goals and non-goals
- architectural principles
- runtime and deployment model
- Polylith codebase shape
- bounded contexts
- canonical data model
- engine semantics
- persistence and recovery
- market data and broker contracts
- strategy model
- observability
- testing strategy
- migration plan
- acceptance criteria

This spec does not yet define:

- exact namespace names for every module
- exact storage technology choices
- full schema definitions for every event payload
- UI/reporting implementation details
- model training pipeline design in depth

## 3. System Goals

The system must:

1. Provide one coherent architecture for live, paper, sim, shadow, and replay.
2. Be restart-safe under unresolved orders and delayed fills.
3. Support deterministic replay from recorded facts and normalized external events.
4. Make business logic understandable through data flow and explicit transitions.
5. Separate pure decision logic from infrastructure side effects.
6. Support multiple strategies without cross-strategy state bleed.
7. Make routing and rollout policy declarative and centrally validated.
8. Make fault handling and degraded operation explicit and observable.

## 4. Non-Goals

The initial system will not:

1. Be decomposed into microservices.
2. Support multiple independent runtime architectures for different modes.
3. Use hidden global registries as the core composition model.
4. Depend on import-time I/O for configuration or artifact discovery.
5. Allow strategy modules to directly manage infrastructure concerns.
6. Pursue distributed complexity before single-process correctness is proven.

## 5. Architectural Principles

### 5.1 Primary Principles

- Data-oriented design
- Functional core, imperative shell
- Append-only facts, derived views
- Explicit state machines
- Deterministic step functions
- Small edge protocols
- Boring runtime topology

### 5.2 Secondary Principles

- SOLID is a boundary-design tool, not the main worldview
- Invalid states should be rejected explicitly
- Hidden mutable state is architectural debt
- Recovery paths must reuse ordinary runtime logic where possible
- Replayability is a first-class design constraint

## 6. Architectural Style

### 6.1 Runtime Style

The system will be a modular monolith.

That means:

- one main deployable engine process initially
- one unified runtime model
- internal modular boundaries enforced in code
- no assumption that internal modules are independently deployable

### 6.2 Codebase Style

The codebase will follow a Polylith-style structure.

That means:

- components around stable business concepts
- bases around executable applications and compositions
- shared libraries only where their boundaries are justified
- composition at the edges, not entanglement at the core

Polylith is the preferred codebase organization because it fits the desired combination of:

- strong internal modularity
- single-system deployment
- easy reuse of domain components
- reduced pressure toward premature service splitting

## 7. Bounded Contexts

The system is initially divided into these bounded contexts:

1. `domain`
2. `engine`
3. `strategy`
4. `market-data`
5. `feature`
6. `inference`
7. `signal`
8. `risk`
9. `execution`
10. `broker`
11. `ledger`
12. `portfolio`
13. `control-plane`
14. `observability`
15. `persistence`
16. `reporting`
17. `app`

### 7.1 Context Responsibilities

`domain`
- canonical value objects
- identifiers
- invariants
- event and command schemas

`engine`
- runtime step loop
- orchestration
- mode-independent state transitions
- coordination of state fold and effect execution

`strategy`
- strategy declarations
- strategy assembly
- feature/model/signal/risk/execution selection

`market-data`
- bars
- quotes
- option chains
- trading calendar and time semantics
- data normalization and provenance

`feature`
- deterministic feature derivation from normalized state

`inference`
- model artifact loading
- model execution
- prediction normalization

`signal`
- prediction to signal transformation

`risk`
- pre-trade and portfolio-level constraint evaluation

`execution`
- signal to executable order-intent translation

`broker`
- external order submission
- cancellation
- ack and fill normalization
- broker account observation

`ledger`
- canonical append-only order, fill, and cash facts

`portfolio`
- derived positions, exposure, and P&L

`control-plane`
- routing
- deployment mode
- account assignments
- rollout and retirement policy

`observability`
- structured events
- health
- metrics
- traces where useful

`persistence`
- event storage
- snapshots
- recovery cursors

`reporting`
- post-trade and operational reporting

`app`
- CLI entrypoints
- process assembly
- adapter wiring

## 8. Hard Centers

The architecture must revolve around these hard centers:

### 8.1 Canonical Domain Schema

All major runtime facts and commands must use shared data definitions.

### 8.2 Deterministic Engine Step Function

The engine must be understandable as a fold over events plus resulting effects.

### 8.3 Append-Only Event Ledger

Truth is recorded as facts, not hidden mutable runtime state.

### 8.4 Broker Boundary With Strict Idempotency

Every outbound order intent must have stable identity and replay-safe semantics.

### 8.5 Market Data Boundary With Explicit Provenance

The source and quality of data must be visible in normalized internal events.

### 8.6 Control Plane As Data

Routing and operational policy must be declarative, versionable, and validated.

### 8.7 Structured Observability

All material decisions and transitions must emit machine-readable events.

### 8.8 Snapshot And Restore As First-Class Architecture

Restart and recovery must be designed, not improvised.

## 9. Canonical Runtime Model

All operating modes will be modeled as:

1. ingest external events
2. normalize into canonical internal events
3. fold internal events through engine state
4. produce:
   - new state
   - outbound commands
   - audit/health/fault events
5. execute outbound commands through adapters
6. normalize external responses into facts
7. append facts
8. persist snapshot and resume cursor

The decision core must not know whether it is operating in live, paper, sim, or replay mode.

Mode differences are implemented at the adapter boundary only.

## 10. Operating Modes

### 10.1 Live

- real market data
- real broker adapter
- canonical engine

### 10.2 Paper

- real market data
- paper broker adapter
- canonical engine

### 10.3 Sim

- real or replayed market data
- simulated broker adapter
- canonical engine

### 10.4 Replay

- historical normalized event source
- deterministic broker/reconciliation semantics
- canonical engine

### 10.5 Shadow

- duplicate decisions into alternate execution sinks
- shadow does not own canonical truth for the live account

## 11. Canonical Data Model

The following are the core data categories.

### 11.1 Identifiers

- `strategy-id`
- `account-id`
- `instrument-id`
- `event-id`
- `run-id`
- `snapshot-id`
- `order-intent-id`
- `broker-order-id`
- `fill-id`

### 11.2 Core Facts

- `bar`
- `quote`
- `option-chain-snapshot`
- `prediction`
- `signal-decision`
- `order-intent`
- `broker-ack`
- `order-status-update`
- `fill`
- `cash-movement`
- `risk-event`
- `checkpoint-written`
- `health-event`
- `fault-event`

### 11.3 Derived Views

- open orders
- pending reconciliations
- positions
- realized P&L
- unrealized P&L
- portfolio exposure
- strategy-local state views

Derived views are recomputable from canonical facts plus the latest accepted snapshot.

## 12. Invariants

### 12.1 Order And Fill Invariants

- every fill maps to exactly one broker order
- every broker order maps to exactly one originating order intent
- every order intent has a stable idempotency key
- replay must not produce a second logically equivalent order intent
- duplicate broker observations must not create duplicate fills internally

### 12.2 Portfolio Invariants

- positions are derived from recorded facts
- cash is derived from recorded facts
- no position mutation occurs outside canonical ledger transitions

### 12.3 Control Invariants

- routing is declared in one control-plane artifact
- forbidden process/account bindings fail before runtime
- retired process paths remain closed by default

### 12.4 Persistence Invariants

- event records are append-only
- snapshots are accelerators, not canonical truth
- recovery must be possible from latest good snapshot plus subsequent facts

## 13. Engine Specification

### 13.1 Engine Responsibilities

The engine is responsible for:

- consuming normalized events
- folding state
- invoking pure strategy logic
- collecting outbound commands
- sequencing adapter execution
- recording all resulting facts
- triggering snapshot persistence

### 13.2 Engine Non-Responsibilities

The engine is not responsible for:

- direct provider-specific market data logic
- direct broker SDK logic
- artifact storage details
- reporting logic

### 13.3 Engine State

The engine state should contain:

- strategy states
- unresolved order state
- reconciliation cursors
- derived portfolio state caches
- current control-plane view
- mode and run metadata

### 13.4 Engine Step Output

A single engine step produces:

- next engine state
- outbound commands
- emitted events

Commands are effect requests for adapters.

Events are canonical internal records.

## 14. Persistence And Recovery

### 14.1 Persistence Model

Use a two-layer persistence model:

1. append-only event log
2. snapshots and indexes

### 14.2 Canonical Truth

Canonical truth includes:

- normalized market events
- order intents
- broker acknowledgements
- order status updates
- fills
- control-plane changes
- fault and health events

### 14.3 Snapshots

Snapshots exist to:

- reduce replay cost
- reduce startup latency
- support fast restart

Snapshots do not replace canonical facts.

### 14.4 Recovery Algorithm

Recovery proceeds as follows:

1. load control-plane configuration
2. load latest valid snapshot
3. read subsequent facts and replay them
4. reconstruct unresolved order state
5. query broker for unresolved truth where necessary
6. normalize reconciliation observations into facts
7. continue normal execution

### 14.5 Recovery Rules

- restart logic must not depend on transient in-memory correlation tables alone
- unresolved orders must survive process death
- the same reconciliation logic should be reusable during ordinary runtime and startup
- broker polling must augment internal truth, not substitute for proper fact recording

## 15. Broker Contract

### 15.1 Broker Commands

The broker boundary will initially support:

- submit order intent
- cancel order intent or broker order
- poll or stream acknowledgements and fills
- query account snapshot
- query open orders
- health check

### 15.2 Broker Facts

The broker adapter emits normalized internal facts:

- broker-ack-accepted
- broker-ack-rejected
- broker-order-update
- broker-fill-observed
- broker-account-observed
- broker-fault-observed

### 15.3 Broker Rules

- broker adapters must attach and preserve idempotency identity
- external response normalization must be deterministic
- broker adapters may not own portfolio logic
- broker adapters may not silently drop ambiguous data

## 16. Market Data Contract

### 16.1 Inputs

The market data boundary must provide normalized forms of:

- bars
- quotes
- chain snapshots
- session/calendar state
- optional corporate actions and metadata

### 16.2 Provenance

Every normalized market event should retain:

- provider
- retrieval timestamp
- market timestamp
- instrument scope
- quality flags

### 16.3 Rules

- feature code does not fetch market data directly
- strategy code does not fetch market data directly
- all fetch logic is adapter-side

## 17. Strategy Model

Each strategy should be declared in terms of:

- strategy metadata
- required instruments
- required features
- model dependencies
- signal function
- risk policy
- execution policy
- scheduling and warmup needs

Strategies should remain thin and declarative.

They must not:

- instantiate providers
- instantiate brokers
- own persistence
- own runtime loops
- hide side effects

## 18. Feature And Inference Model

### 18.1 Features

Features must be:

- deterministic
- versioned
- derived from normalized input state
- free of provider I/O

### 18.2 Inference

Inference must be:

- isolated behind a stable interface
- explicit about model version and artifact provenance
- normalized into a shared prediction format

Model artifact resolution belongs to adapters and application composition, not the core domain.

## 19. Risk And Execution Model

The system will separate:

- signal logic
- risk logic
- execution logic

Signal determines desired posture.

Risk determines what is allowed.

Execution determines order expression.

This separation is required for clarity and testability.

## 20. Control Plane

The control plane is a data artifact describing:

- strategy set
- version and rollout state
- account routing
- broker selection
- live/paper/sim/shadow mode
- process assignment
- kill switches
- retirement policy

The control plane must be validated before engine startup.

## 21. Observability

The system must emit structured events for:

- signal decisions
- risk decisions
- order-intent creation
- broker submission
- acknowledgement
- fill observation
- reconciliation
- restart and recovery
- health heartbeat
- degraded mode and faults

Observability must support:

- debugging
- post-trade audit
- replay diagnosis
- operator awareness

## 22. Error Model

Errors should be classified by architecture, not by arbitrary exception strings.

Initial classes:

- configuration error
- dependency unavailable
- data quality violation
- strategy evaluation fault
- risk evaluation fault
- broker submission fault
- reconciliation fault
- persistence fault
- invariant violation

Rules:

- invariant violations fail loud
- degraded operation must be explicit
- all meaningful faults must be recorded as structured events

## 23. Runtime Topology

Initial topology:

- one engine process
- separate offline jobs for training/calibration/reporting
- optional data-ingestion helpers if needed
- control-plane validation command(s)

No multi-process strategy split by default.

A strategy-specific process model is allowed later only if justified by a clear operational need.

## 24. Polylith-Oriented Project Shape

The codebase should be organized conceptually as:

- `bases/app-cli`
- `bases/app-engine`
- `components/domain-*`
- `components/engine-*`
- `components/strategy-*`
- `components/adapter-market-data-*`
- `components/adapter-broker-*`
- `components/persistence-*`
- `components/control-plane-*`
- `components/reporting-*`
- `projects/dev`
- `projects/test`

Exact namespace names can be finalized later, but the architectural rule is:

- inward dependencies only
- core components do not depend on adapters
- composition happens in bases/projects

## 25. Testing Strategy

The system requires:

1. unit tests for pure functions
2. invariant tests for state transitions
3. adapter contract tests
4. replay determinism tests
5. restart and recovery tests
6. broker dedup and reconciliation tests
7. end-to-end mode tests

Required golden properties:

- uninterrupted run and restarted run converge to the same canonical state
- duplicate broker observations do not duplicate exposure
- fill-to-order lineage remains intact
- no strategy can consume another strategy's private state implicitly

## 26. Migration Strategy

The migration plan is:

1. complete architecture package
2. define canonical schemas
3. implement event log and snapshot support
4. implement engine kernel
5. implement simulated broker
6. implement replay mode
7. port one simple strategy end to end
8. port one non-trivial options strategy
9. add paper/live broker adapter
10. expand breadth only after parity and recovery confidence is achieved

The Python system should be treated as a behavioral reference, not a structural template.

## 27. Acceptance Criteria

The architecture is considered successful only if the resulting implementation can prove:

1. one engine model works across live, paper, sim, and replay
2. restart under unresolved orders does not create duplicate exposure
3. positions and cash can be reconstructed from facts plus snapshot
4. strategies remain infrastructure-light and declarative
5. routing policy is centrally enforced
6. replay behavior is deterministic within declared tolerances
7. observability is sufficient to explain a day without reading source code line by line

## 28. Immediate Next Design Tasks

The next design round should lock:

1. exact bounded context edges
2. canonical event and command taxonomy
3. engine state machine definition
4. persistence schema strategy
5. recovery and reconciliation algorithm
6. initial Polylith workspace layout

These items are now formalized across the companion specs for:

- event and command taxonomy
- engine state and recovery
- canonical schemas
- engine state machines
- persistence and storage layout
- Polylith workspace and boundary layout
- broker contracts
- market-data contracts
- control-plane manifests
- observability and operations
- testing and verification
- migration and implementation
- strategy pipeline and artifact model
- ledger and portfolio model

The next step after this document set is to turn the architecture package into:

1. ADRs for key irreversible decisions
2. first workspace skeleton with empty Polylith components and bases
3. initial manifest, fixture, and contract examples under `resources/`
