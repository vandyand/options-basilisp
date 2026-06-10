# NORTHSTAR

This project is a ground-up Basilisp rewrite of the current StevenTrading Python system.

The rewrite exists because the current system is hard to reason about, hard to restart safely, and too structurally mixed to support reliable iteration. The goal is not to transliterate Python into Basilisp. The goal is to build a new system with a simpler center, stricter boundaries, and better operational correctness.

## Core Direction

The system will be a **modular monolith** implemented with a **Polylith-style codebase**:

- one deployable system
- many well-bounded components
- clear internal contracts
- shared development ergonomics without shared architectural chaos

Polylith is the codebase pattern. Modular monolith is the runtime/deployment pattern.

## Primary Principles

The project will prefer:

- data-oriented design over object-heavy design
- functional core, imperative shell
- append-only facts over mutable hidden state
- explicit state machines over implicit workflow
- deterministic replay over ad hoc runtime behavior
- strict boundary protocols over cross-module reach-through
- boring operational architecture over premature distribution

## Hard Centers

The architecture must be built around these hard centers:

1. Canonical domain schema
2. Deterministic engine step function
3. Append-only event ledger
4. Broker boundary with strict idempotency
5. Market data boundary with explicit provenance
6. Control plane as data
7. Structured observability
8. Snapshot and restore as first-class architecture

If these are correct, strategies and adapters become manageable.

## System Goals

- one coherent runtime model for live, paper, sim, shadow, and replay
- one canonical model for predictions, signals, intents, acks, fills, positions, and cash
- restart-safe execution
- deterministic replayability
- high legibility
- strong internal boundaries
- simple operator model
- robust behavior under faults and restarts

## Anti-Goals

- no microservices-first design
- no global registries as the core composition mechanism
- no import-time filesystem reads
- no duplicate live and sim architectures
- no strategy-owned infrastructure
- no hidden mutable runtime state that cannot be reconstructed

## Runtime North Star

Every mode should use the same conceptual loop:

1. ingest external events
2. normalize to canonical internal events
3. fold through pure decision logic
4. emit commands and audit events
5. execute commands in adapters
6. record resulting facts
7. persist snapshot and resume cursor

Live, paper, sim, and replay should differ at the edges, not in the core.

## Persistence North Star

Canonical truth should live in append-only facts:

- market events
- order intents
- broker acknowledgements
- fills
- control-plane changes
- health and fault events

Snapshots are acceleration structures for restart, not the source of truth.

## Strategy North Star

A strategy should mostly be:

- metadata
- required instruments
- required features
- required models
- signal logic
- risk policy
- execution policy
- schedule

A strategy should not:

- construct providers directly
- own a broker connection
- own its own event loop
- manage persistence directly
- hide side effects

## Quality Bar

The new system is only acceptable if it proves:

- replay determinism
- restart correctness during unresolved orders
- exact intent-to-ack-to-fill lineage
- no cross-strategy state bleed
- no forbidden real-account routing
- understandable control flow from reading data and functions

## Architectural Stance

Use SOLID where it helps boundary design, but do not make SOLID the center of the system.

The real center is:

- immutable data
- explicit transitions
- narrow protocols
- deterministic execution
- operational correctness

## Build Order

The rewrite should proceed in this order:

1. architecture package
2. canonical domain model
3. event ledger and snapshot model
4. engine kernel
5. simulated broker
6. replay mode
7. first end-to-end simple strategy
8. options execution path
9. paper broker adapter
10. parity and recovery validation

Breadth comes after the core is trustworthy.

