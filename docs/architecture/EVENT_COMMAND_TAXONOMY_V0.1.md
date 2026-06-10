# Event And Command Taxonomy v0.1

## 1. Purpose

This document formalizes the canonical taxonomy of:

- facts
- commands
- projections
- snapshots

for the Basilisp rewrite of StevenTrading.

This taxonomy is one of the system's hard centers. If the event and command language is unclear, the engine, persistence, recovery, replay, and observability layers all become unclear.

## 2. Core Definitions

### 2.1 Fact

A fact is an immutable record of something that has happened or has been observed.

Examples:

- a market bar was observed
- an order intent was created
- a broker acknowledgement was received
- a fill was observed
- a control-plane revision was activated

Facts are append-only.

Facts are canonical truth.

### 2.2 Command

A command is an explicit request for an effectful action.

Examples:

- submit this order intent to the broker
- cancel this broker order
- persist a snapshot
- emit a health heartbeat

Commands are not truth.

Commands are instructions derived from current state and incoming facts.

### 2.3 Projection

A projection is a derived read model computed from canonical facts.

Examples:

- current positions
- open orders
- realized P&L
- current strategy posture
- health dashboard state

Projections are replaceable.

### 2.4 Snapshot

A snapshot is a persisted acceleration structure containing enough engine state to reduce recovery replay cost.

Snapshots are not canonical truth.

Snapshots are caches over truth plus a cursor or watermark.

## 3. Design Rules

### 3.1 Rule: Facts Are Immutable

Facts must never be updated in place.

Corrections are represented as new facts.

### 3.2 Rule: Commands Are Not Stored As Truth By Themselves

If command history is retained, it is retained for auditability only.

The truth-bearing records are the resulting facts:

- order intent created
- command dispatched
- broker acknowledged
- fill observed

### 3.3 Rule: Projections Are Rebuildable

Any projection must be derivable from:

- canonical facts
- the latest accepted snapshot
- subsequent facts after the snapshot watermark

### 3.4 Rule: Every Effect Must Be Traceable To A Fact

All effectful commands must be causally attributable to one or more existing facts and the engine decision cycle that produced them.

### 3.5 Rule: Naming Must Encode Meaning

Type names must clearly distinguish:

- observations
- decisions
- effect requests
- effect results
- state rollups

## 4. Naming Conventions

### 4.1 Fact Naming

Facts use past-tense or observed-result language.

Recommended forms:

- `market-bar-observed`
- `quote-observed`
- `option-chain-observed`
- `prediction-produced`
- `signal-decision-produced`
- `order-intent-created`
- `broker-ack-accepted`
- `broker-ack-rejected`
- `broker-order-status-observed`
- `fill-observed`
- `cash-movement-recorded`
- `risk-decision-recorded`
- `control-plane-activated`
- `snapshot-written`
- `fault-recorded`
- `health-heartbeat-recorded`

### 4.2 Command Naming

Commands use imperative language.

Recommended forms:

- `submit-order-intent`
- `cancel-broker-order`
- `request-broker-open-orders`
- `request-broker-fills-since`
- `persist-snapshot`
- `emit-health-heartbeat`
- `emit-audit-event`

### 4.3 Projection Naming

Projections use present-state nouns.

Recommended forms:

- `open-orders-view`
- `positions-view`
- `portfolio-view`
- `strategy-state-view`
- `account-exposure-view`
- `health-view`

## 5. Canonical Envelopes

All facts and commands should use canonical envelopes so the infrastructure layer has one transport shape.

## 5.1 Fact Envelope

Every fact should carry:

- `fact-id`
- `fact-type`
- `fact-version`
- `occurred-at`
- `recorded-at`
- `run-id`
- `mode`
- `correlation-id`
- `causation-fact-id` or list of causation ids where needed
- `strategy-id` when applicable
- `account-id` when applicable
- `instrument-id` when applicable
- `source-system`
- `source-ref`
- `payload`

## 5.2 Command Envelope

Every command should carry:

- `command-id`
- `command-type`
- `command-version`
- `issued-at`
- `run-id`
- `mode`
- `correlation-id`
- `causation-fact-id`
- `strategy-id` when applicable
- `account-id` when applicable
- `target-adapter`
- `payload`

## 5.3 Common Identity Rules

- `run-id` ties all facts and commands to one engine execution attempt
- `correlation-id` ties a business action across facts and commands
- `causation-*` ties a record to the prior record that directly caused it

These are distinct.

They should not be conflated.

## 5.4 Ordering And Watermark Rules

The taxonomy assumes multiple partially independent streams.

Ordering rules:

- fact-log append order is the canonical processing order inside one fact store
- `occurred-at` captures domain time
- `recorded-at` captures durable-ingest time
- adapter cursors or offsets capture source-specific progress

Implications:

- facts from different streams must not be globally ordered by `occurred-at` alone
- recovery must resume from explicit per-stream watermarks, not from one wall-clock timestamp
- late observations remain valid facts if their lineage and timestamps are clear

## 6. Top-Level Categories Of Facts

There are five top-level fact families.

### 6.1 External Observation Facts

These are normalized observations from systems outside the decision core.

Types:

- `market-bar-observed`
- `quote-observed`
- `option-chain-observed`
- `calendar-session-observed`
- `broker-account-observed`
- `broker-order-status-observed`
- `fill-observed`

Rules:

- they must carry provenance
- they must not contain provider-specific SDK objects
- they must be normalized before entering the core

### 6.2 Decision Facts

These are products of pure or mostly pure core computation.

Types:

- `prediction-produced`
- `signal-decision-produced`
- `risk-decision-recorded`
- `execution-plan-produced`
- `order-intent-created`

Rules:

- they must be deterministic given prior state and inputs
- they must not embed transport- or SDK-specific data

### 6.3 Execution Outcome Facts

These record how external systems responded to commands.

Types:

- `broker-ack-accepted`
- `broker-ack-rejected`
- `broker-order-status-observed`
- `fill-observed`
- `cancel-ack-accepted`
- `cancel-ack-rejected`

Rules:

- they must preserve broker correlation fields
- they must retain enough identity to reconcile across restart

### 6.4 Control Facts

These record policy changes and runtime governance.

Types:

- `control-plane-activated`
- `control-plane-violation-recorded`
- `strategy-enabled`
- `strategy-disabled`
- `account-route-changed`
- `kill-switch-activated`

### 6.5 Operational Facts

These record system behavior and operator-relevant runtime state.

Types:

- `snapshot-written`
- `command-dispatched`
- `recovery-started`
- `recovery-completed`
- `fault-recorded`
- `health-heartbeat-recorded`
- `degraded-mode-recorded`

## 7. Top-Level Categories Of Commands

There are four top-level command families.

### 7.1 Broker Commands

Types:

- `submit-order-intent`
- `cancel-broker-order`
- `request-broker-open-orders`
- `request-broker-fills-since`
- `request-broker-account-state`
- `request-broker-health`

### 7.2 Persistence Commands

Types:

- `persist-snapshot`
- `append-facts`
- `advance-recovery-watermark`

### 7.3 Observability Commands

Types:

- `emit-health-heartbeat`
- `emit-audit-event`
- `emit-metric`

### 7.4 Data Acquisition Commands

If direct pull behavior is required for some adapters:

- `request-market-bars`
- `request-quotes`
- `request-option-chain`
- `request-calendar-state`

These remain adapter-side concerns even if represented as commands.

## 8. Canonical Fact Types

The following fact types are considered part of the canonical v0.1 language.

### 8.1 Market Facts

- `market-bar-observed`
- `quote-observed`
- `option-chain-observed`
- `calendar-session-observed`

Required identifiers:

- `instrument-id`
- `source-system`
- market timestamp

### 8.2 Inference Facts

- `prediction-produced`

Required identifiers:

- `strategy-id`
- model reference
- prediction timestamp

### 8.3 Strategy Decision Facts

- `signal-decision-produced`
- `risk-decision-recorded`
- `execution-plan-produced`

Required identifiers:

- `strategy-id`
- decision timestamp

### 8.4 Order Lifecycle Facts

- `order-intent-created`
- `broker-ack-accepted`
- `broker-ack-rejected`
- `broker-order-status-observed`
- `fill-observed`
- `cancel-ack-accepted`
- `cancel-ack-rejected`

Required identifiers:

- `strategy-id`
- `account-id`
- `order-intent-id`
- `broker-order-id` once known

### 8.5 Ledger Facts

- `cash-movement-recorded`
- `position-lot-opened`
- `position-lot-closed`
- `position-mark-recorded`

These may be explicit stored facts or durable derived facts depending on the final ledger design. v0.1 allows either, provided lineage remains clear.

### 8.6 Control Facts

- `control-plane-activated`
- `control-plane-violation-recorded`
- `kill-switch-activated`
- `kill-switch-cleared`

### 8.7 Recovery And Health Facts

- `command-dispatched`
- `recovery-started`
- `recovery-completed`
- `snapshot-written`
- `fault-recorded`
- `health-heartbeat-recorded`
- `degraded-mode-recorded`

## 9. Canonical Command Types

The following commands are part of the canonical v0.1 language.

### 9.1 Trading Commands

- `submit-order-intent`
- `cancel-broker-order`

### 9.2 Broker State Query Commands

- `request-broker-open-orders`
- `request-broker-fills-since`
- `request-broker-account-state`
- `request-broker-health`

### 9.3 Persistence Commands

- `persist-snapshot`
- `append-facts`

### 9.4 Operational Commands

- `emit-health-heartbeat`
- `emit-audit-event`

## 10. Order Lineage Model

The order lineage is:

1. `signal-decision-produced`
2. `risk-decision-recorded`
3. `execution-plan-produced`
4. `order-intent-created`
5. `submit-order-intent`
6. `broker-ack-*`
7. `broker-order-status-observed`
8. `fill-observed`

The canonical internal anchor is `order-intent-created`.

Broker order ids are external correlation values that attach later.

### 10.1 Dispatch Lineage

The command layer sits between internal intent and external outcome.

Recommended lineage:

1. `order-intent-created`
2. `submit-order-intent`
3. `command-dispatched`
4. `broker-ack-*` or broker-side fault fact

`command-dispatched` is operational rather than business truth, but it is useful for:

- recovery diagnostics
- latency measurement
- proving whether a command left the process before a crash

### 10.2 End-To-End Example

One normal trade path should read like this:

1. `market-bar-observed`
2. `prediction-produced`
3. `signal-decision-produced`
4. `risk-decision-recorded`
5. `execution-plan-produced`
6. `order-intent-created`
7. `submit-order-intent`
8. `command-dispatched`
9. `broker-ack-accepted`
10. `fill-observed`
11. `cash-movement-recorded`
12. `position-lot-opened` or `position-lot-closed`

## 11. Idempotency Model

### 11.1 Order Intent Idempotency

An order intent must be identifiable independent of process lifetime.

The intent identity should be derived from stable business inputs, not random process-local memory.

### 11.2 Observation Deduplication

Broker observations and market observations may arrive more than once.

Deduplication must happen using canonical identity rules, not ad hoc string matching.

### 11.3 Command Reissue Rules

A command may be reissued on restart only if the system cannot prove that the intended effect was already accepted or completed.

This rule depends on recorded facts, not optimism.

### 11.4 Canonical Deduplication Keys

Deduplication keys should be explicit per fact family.

Recommended examples:

- market observations: provider name plus provider event identity or provider cursor plus instrument scope
- order intents: stable business identity for the intended action
- broker acknowledgements: broker order id plus normalized status identity
- fills: broker fill id where available, otherwise a documented composite surrogate

The system should reject fact families whose deduplication rules are undefined.

## 12. What Must Not Be Facts

The following should not be stored as canonical facts:

- raw SDK objects
- opaque adapter exceptions without normalization
- transient caches
- in-memory only heuristics
- mutable projection state with no underlying lineage

## 13. Relationship To Snapshots

Snapshots are not part of the canonical fact taxonomy.

They are persistence accelerators containing:

- enough state to shorten recovery
- enough watermarks to know where recovery resumes

Snapshots must point back to fact-log watermarks.

## 14. Taxonomy Stability Rules

The following rules govern taxonomy evolution:

1. Fact types are versioned.
2. Command types are versioned.
3. Removing a fact type requires a migration plan.
4. Renaming a fact type is treated as deprecation plus replacement, not silent mutation.
5. Identity fields must be stable across versions unless a migration is explicitly defined.

## 15. Acceptance Criteria

This taxonomy is considered sufficient for v0.1 if it supports:

1. deterministic replay of decisions
2. exact order-intent to broker-order to fill lineage
3. restart-safe reconciliation
4. explicit control-plane governance
5. structured observability without adapter leakage
