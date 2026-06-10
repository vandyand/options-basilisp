# Migration And Implementation Plan v0.1

## 1. Purpose

This document formalizes the migration and implementation sequencing for the Basilisp rewrite of StevenTrading.

It locks:

- migration principles
- implementation order
- parity strategy
- cutover expectations
- risk-reduction milestones

This spec is normative for v0.1.

## 2. Design Intent

The rewrite must reduce operational risk while replacing the current Python system.

That means:

1. prove the runtime core before broad strategy migration
2. treat the Python system as a behavioral reference, not a structural template
3. reach replay and sim correctness before live integration
4. cut over in constrained, auditable phases

## 3. Migration Principles

1. migrate by contracts and boundaries, not file-for-file porting
2. start with the engine core and persistence model
3. prove restart and replay before broker breadth
4. port the simplest strategy first
5. do not bring legacy path hacks or global registries forward

## 4. Implementation Phases

## 4.1 Phase 0: Architecture Lock

Deliverables:

- architecture doc set
- ADR backlog
- initial workspace decisions

Exit criteria:

- hard centers are explicit
- schema and state-machine docs are accepted

## 4.2 Phase 1: Workspace Skeleton

Deliverables:

- Polylith workspace skeleton
- empty components and bases
- lint and test harness
- development REPL entrypoints

Exit criteria:

- dependency direction is enforceable
- projects compile with empty skeletons

## 4.3 Phase 2: Domain And Engine Kernel

Deliverables:

- canonical schemas
- engine state maps
- state machines
- fact fold pipeline
- snapshot interfaces

Exit criteria:

- core tests pass
- deterministic replay over synthetic fixtures works

## 4.4 Phase 3: Persistence And Replay

Deliverables:

- fact store adapter
- snapshot store adapter
- replay market-data adapter
- replay scenario test suite

Exit criteria:

- restart and replay golden tests pass
- unresolved order lineage survives restart

## 4.5 Phase 4: Sim Broker And One End-To-End Strategy

Deliverables:

- simulator broker adapter
- one simple strategy path
- reporting basics

Exit criteria:

- one strategy runs through replay and sim end to end
- operator can inspect order and fill lineage clearly

## 4.6 Phase 5: Paper Broker And Real Market Data

Deliverables:

- paper-capable broker adapter
- live-source market-data adapter
- control-plane tooling

Exit criteria:

- paper mode works with the same engine core
- restart under unresolved paper orders is proven

## 4.7 Phase 6: Strategy Breadth And Shadow Validation

Deliverables:

- additional strategy ports
- options-specific execution coverage
- shadow validation workflows

Exit criteria:

- migrated strategies show acceptable replay and paper parity
- operational runbooks exist

## 4.8 Phase 7: Controlled Production Cutover

Deliverables:

- production-ready manifests
- cutover runbook
- rollback plan

Exit criteria:

- live routing passes control-plane checks
- shadow and paper evidence support live enablement

## 5. First Strategy Selection

The first strategy should be:

- operationally simple
- low branching
- easy to replay
- representative enough to validate the architecture

Recommended order:

1. one simple equity-direction strategy
2. one options strategy with non-trivial execution
3. one ensemble or multi-input strategy
4. more complex spread families after the runtime core is proven

## 6. Parity Strategy

Parity should be judged at multiple levels:

- normalized input parity
- decision parity
- order-intent parity
- restart behavior parity

The goal is not byte-for-byte imitation of every Python quirk.

The goal is behavior that is correct, explainable, and operationally safer.

## 7. Cutover Rules

1. no direct live cutover from an unproven adapter
2. every live-enabled route must first pass replay and paper gates
3. shadow evidence should exist for strategies with meaningful complexity
4. rollback path must be explicit before live activation

## 8. What We Explicitly Avoid

The migration must not become:

- an in-place rewrite inside the Python repo
- a mixed runtime where new and old engines share hidden mutable state
- a file-by-file transliteration project
- a live-first gamble

## 9. Acceptance Criteria

This migration plan is sufficient for v0.1 if:

1. sequencing reduces risk rather than merely spreading work
2. replay and restart correctness arrive before live cutover
3. strategy migration order is deliberate
4. rollback and shadow validation are part of the plan
5. the new architecture can prove value before full breadth is ported
