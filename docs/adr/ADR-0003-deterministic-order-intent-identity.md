# ADR-0003: Deterministic Order-Intent Identity And Idempotent Broker Boundary

## Status

Accepted

## Context

The hardest operational failures in the existing system center on duplicate exposure, ambiguous broker truth, and restart-time uncertainty.

The rewrite needs:

- replay-stable order identities
- submit deduplication
- exact lineage from strategy decision to broker outcome

## Decision

`order-intent-id` will be deterministic and derived from canonical business inputs.

Broker adapters must preserve and use idempotency keys where possible.

Broker transport details must normalize into canonical acknowledgement, status, and fill facts.

## Consequences

Positive:

- duplicate-submit prevention becomes architectural rather than ad hoc
- recovery and reconciliation can rely on stable lineage

Negative:

- identity rules must remain carefully versioned
- some brokers may require extra correlation bookkeeping when native idempotency support is weak
