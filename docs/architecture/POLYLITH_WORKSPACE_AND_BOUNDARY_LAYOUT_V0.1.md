# Polylith Workspace And Boundary Layout v0.1

## 1. Purpose

This document formalizes the initial Polylith-oriented workspace structure and the bounded-context edges for the Basilisp rewrite of StevenTrading.

It locks:

- top-level workspace layout
- component and base responsibilities
- dependency direction rules
- context edge rules
- initial project compositions

This spec is normative for v0.1.

## 2. Design Intent

The Polylith shape exists to support:

1. a modular monolith runtime
2. clear business boundaries
3. reusable pure components
4. thin app-specific assembly bases
5. the ability to test and evolve runtime slices without structural sprawl

Polylith is the codebase pattern, not an excuse to weaken boundaries.

## 3. Workspace Shape

Recommended top-level layout:

```text
stevetrading-basilisp/
  NORTHSTAR.md
  docs/
    architecture/
    adr/
  components/
  bases/
  projects/
  development/
  resources/
  scripts/
```

Top-level responsibilities:

- `components/`: reusable business and adapter components
- `bases/`: executable compositions and application wiring
- `projects/`: deployable or testable workspace projections
- `development/`: REPL and local developer tooling
- `resources/`: control-plane manifests, static schemas, fixture data
- `scripts/`: operational scripts that are not part of the pure core

## 4. Initial Component Set

These are the initial components the system should expect to have.

## 4.1 Core Domain Components

- `domain.identifiers`
- `domain.enums`
- `domain.instruments`
- `domain.schemas`
- `domain.validation`

Responsibilities:

- canonical ids
- enums
- canonical envelopes
- shared validation

These components must have no dependency on adapters or bases.

## 4.2 Engine Components

- `engine.state`
- `engine.fold`
- `engine.machines`
- `engine.recovery`
- `engine.commands`

Responsibilities:

- engine state maps
- fact folding
- transition table execution
- recovery planning
- command derivation

Engine components may depend on `domain.*` components only, plus carefully bounded protocol components.

## 4.3 Strategy Pipeline Components

- `strategy.registry`
- `feature.core`
- `inference.core`
- `signal.core`
- `risk.core`
- `execution.core`

Responsibilities:

- strategy declarations
- feature derivation
- prediction normalization
- signal decisions
- risk evaluation
- order-intent planning

These remain pure or mostly pure.

## 4.4 Ledger And Portfolio Components

- `ledger.core`
- `portfolio.core`

Responsibilities:

- cash and position facts
- derived positions
- P&L and exposure views

## 4.5 Boundary Protocol Components

- `broker.protocol`
- `market-data.protocol`
- `persistence.protocol`
- `observability.protocol`
- `control-plane.protocol`
- `artifact.protocol`

Responsibilities:

- define small stable protocols
- define adapter request and response shapes
- forbid SDK leakage into the core

## 4.6 Adapter Components

- `broker.alpaca`
- `broker.sim`
- `market-data.polygon`
- `market-data.replay`
- `persistence.fact-store`
- `persistence.snapshot-store`
- `observability.structured-log`
- `control-plane.file-store`
- `artifact.file-store`

Responsibilities:

- translate external systems to canonical shapes
- execute commands defined by protocol components

Adapter components may depend inward on protocol and domain components, never the other way around.

## 4.7 Support Components

- `time.core`
- `calendar.core`
- `config.core`
- `replay.fixture`

These exist only if their boundaries stay crisp.

No junk-drawer utility component is allowed.

## 5. Initial Base Set

Bases are where components are assembled into runnable applications.

## 5.1 `base.engine-live`

Purpose:

- assemble the live or paper engine runtime

Composes:

- engine
- strategy pipeline
- ledger and portfolio
- chosen broker adapter
- chosen market-data adapter
- persistence adapters
- observability adapters
- control-plane reader

## 5.2 `base.engine-replay`

Purpose:

- assemble deterministic replay and historical simulation

Composes:

- engine
- strategy pipeline
- replay market-data adapter
- sim broker or deterministic execution adapter
- persistence reader
- observability adapters

## 5.3 `base.control-plane`

Purpose:

- validate and activate control-plane manifests

## 5.4 `base.reports`

Purpose:

- produce reports and derived analytics from canonical facts

## 5.5 `base.dev`

Purpose:

- support REPL-driven local development and debugging

This base may be richer than production bases, but it must not become a hidden runtime architecture.

## 6. Initial Project Set

Projects are workspace projections for concrete use cases.

Recommended initial projects:

- `projects/engine-live`
- `projects/engine-replay`
- `projects/control-plane`
- `projects/reports`
- `projects/test`

Expected use:

- `engine-live`: one deployable runtime for live or paper mode
- `engine-replay`: offline replay and simulator workflows
- `control-plane`: validation and activation tooling
- `reports`: reporting and analytics jobs
- `test`: broad integration and replay test composition

## 7. Dependency Direction Rules

The dependency rule is inward only.

Allowed direction:

- adapters -> protocols -> domain/core
- bases -> components
- projects -> bases and selected components

Forbidden direction:

- domain/core -> adapters
- pure strategy pipeline -> broker SDK code
- engine core -> file-system specific control-plane code
- one adapter reaching into another adapter's private internals

## 8. Bounded Context Edges

The main context edges are:

1. `engine` <-> `strategy pipeline`
2. `engine` <-> `broker`
3. `engine` <-> `market-data`
4. `engine` <-> `persistence`
5. `engine` <-> `observability`
6. `app/control-plane` <-> `engine`
7. `ledger` <-> `portfolio`

## 8.1 Engine To Strategy Pipeline

The engine supplies:

- normalized market state slices
- strategy-local state
- control-plane and schedule context

The strategy pipeline returns:

- predictions
- signal decisions
- risk decisions
- execution plans
- order intents

The engine does not let strategies call adapters directly.

## 8.2 Engine To Broker

The engine sends:

- submit commands
- cancel commands
- query commands

The broker returns:

- normalized acknowledgements
- normalized order status facts
- normalized fill facts
- normalized account observations

The broker does not own portfolio truth.

## 8.3 Engine To Market Data

The engine consumes only normalized market facts.

Market-data adapters may poll or subscribe as needed, but those mechanics stay outside the core.

## 8.4 Engine To Persistence

The engine requests:

- fact appends
- snapshot writes
- recovery reads

Persistence components do not decide business semantics.

## 8.5 Engine To Observability

The engine emits:

- health events
- fault events
- audit events
- metrics payloads

Observability adapters do not mutate core state.

## 8.6 Ledger To Portfolio

`ledger.core` owns the canonical cash and position-affecting facts.

`portfolio.core` builds derived position, exposure, and P&L views from ledger facts.

Portfolio must not become a second source of truth.

## 9. Namespace And Ownership Rules

Each component should own one clear namespace family.

Examples:

- `stevetrading.domain.identifiers.*`
- `stevetrading.engine.fold.*`
- `stevetrading.broker.protocol.*`
- `stevetrading.broker.alpaca.*`

Ownership rules:

- one component owns its public API
- cross-component use goes through public namespaces only
- internal helper namespaces stay private to the component

## 10. Composition Rules

1. Bases perform wiring only.
2. Business logic belongs in components.
3. Environment-specific choices happen at the base level.
4. A base may select a broker adapter, but it may not redefine broker semantics.
5. The same engine components must be reused across live, paper, sim, and replay bases.

## 11. What We Intentionally Avoid

The Polylith layout must not drift into:

- a giant `shared` component
- duplicate engine implementations per mode
- adapter-specific domain objects leaking into the core
- one base per strategy
- hidden runtime behavior in dev-only tooling

## 12. Migration-Oriented Mapping

The initial workspace should make migration sequencing obvious.

Suggested build order:

1. `domain.*`
2. `engine.state`, `engine.fold`, `engine.machines`
3. `persistence.protocol`, `persistence.fact-store`, `persistence.snapshot-store`
4. `broker.protocol`, `broker.sim`
5. `market-data.protocol`, `market-data.replay`
6. `ledger.core`, `portfolio.core`
7. `strategy.registry`, `feature.core`, `signal.core`, `risk.core`, `execution.core`
8. `base.engine-replay`
9. `broker.alpaca`, `market-data.polygon`
10. `base.engine-live`

This sequence gets replay and simulator correctness before live integration.

## 13. Acceptance Criteria

This workspace and boundary spec is sufficient for v0.1 if:

1. every major module has one clear home
2. dependency direction is obvious and enforceable
3. live, paper, sim, and replay share the same engine components
4. strategies remain adapter-blind
5. there is no need for a legacy-style script stack to compose the runtime
