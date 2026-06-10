# Observability And Operations v0.1

## 1. Purpose

This document formalizes the observability and day-two operational model for the Basilisp rewrite of StevenTrading.

It locks:

- structured audit event expectations
- metrics and health model
- operational query model
- incident and degradation visibility rules
- routine operating workflows

This spec is normative for v0.1.

## 2. Design Intent

The system must make it possible to explain:

1. what happened
2. why it happened
3. what the system believed at the time
4. whether it was healthy or degraded
5. which policy revision was in force

Observability exists to support operations, not to produce decorative telemetry.

## 3. Observability Pillars

The architecture relies on four observability pillars:

1. canonical facts
2. structured audit events
3. metrics
4. health state

Canonical facts are the deepest truth.

The other pillars make that truth operable.

## 4. Structured Audit Events

Audit events must exist for:

- recovery start and completion
- control-plane load and validation results
- strategy lifecycle changes
- decision production
- order submission attempts
- broker acknowledgements and fills
- degradation entry and exit
- invariant violations
- process shutdown

Audit events should be machine-readable and human-inspectable.

## 4.1 Minimum Audit Fields

Every audit event should carry:

- event time
- run id
- process id
- mode
- strategy id when applicable
- account id when applicable
- correlation id
- severity
- event type
- concise message
- structured payload

## 5. Metrics Model

Metrics should answer:

- is the engine healthy
- is it current on data
- are orders flowing correctly
- are degradations increasing
- are recovery and replay behaving as expected

Recommended metric families:

- market-data lag
- broker round-trip latency
- snapshot write latency
- fact append latency
- unresolved order count
- fill observation lag
- recovery duration
- strategy decision cycle time
- degradation count
- control-plane violation count

## 6. Health Model

Health should be represented as explicit state, not inferred from the absence of logs.

Required health scopes:

- process
- dependency
- strategy
- broker adapter
- market-data adapter

Health levels:

- healthy
- degraded
- blocked
- stopped

The system should emit periodic heartbeats describing current health and active degradations.

## 7. Operational Query Model

The system must make these questions easy to answer:

1. why did this order get submitted
2. what happened to this order after restart
3. what fills affected this position
4. which strategy and policy revision were active
5. what degradations were active during this interval
6. was the broker or market-data source lagging

If answering these requires source-code archaeology, the architecture has failed.

## 8. Incident Workflow Expectations

For common incidents, observability must support a clear path.

## 8.1 Order Incident

Operator should be able to trace:

- order intent
- dispatch attempt
- broker ack or reject
- status changes
- fills
- reconciliation outcomes

## 8.2 Recovery Incident

Operator should be able to trace:

- snapshot used
- post-watermark facts replayed
- broker reconciliation queries issued
- anomalies detected
- final recovery outcome

## 8.3 Data Incident

Operator should be able to trace:

- provider source
- lag
- quality anomalies
- impacted strategies

## 9. Degradation Visibility Rules

Every degradation must be:

- explicitly classified
- timestamped
- scoped
- paired with an exit event when cleared

Recommended degradation categories:

- broker unavailable
- market-data stale
- snapshot write failure
- replay fixture corruption
- control-plane mismatch
- invariant soft-failure awaiting operator action

## 10. Routine Operations

The system should support at least these routine workflows:

- startup readiness check
- trading session supervision
- manual strategy halt
- control-plane activation review
- post-session reconciliation review
- replay-based incident reconstruction

## 11. Logging Rules

Logs must be structured first.

Rules:

- no canonical decision information should live only in free-text logs
- identifiers must be included explicitly
- one log line or event should be enough to join to deeper fact history

## 12. Alerts

Alerts should be driven by conditions that matter operationally.

Examples:

- unresolved order count exceeds threshold
- broker or market-data lag exceeds threshold
- recovery outcome is `blocked` or `recovery-failed`
- control-plane violation occurs
- snapshot writes fail repeatedly
- invariant violation occurs

## 13. Acceptance Criteria

This observability spec is sufficient for v0.1 if:

1. one trading day can be reconstructed from facts plus structured events
2. degraded and blocked states are explicit
3. operationally important identifiers are present in logs and metrics
4. incident workflows do not depend on hidden adapter state
5. routine supervision can happen without reading source code
