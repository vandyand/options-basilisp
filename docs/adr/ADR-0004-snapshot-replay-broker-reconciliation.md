# ADR-0004: Snapshot Plus Replay Plus Broker-Reconciliation Recovery Model

## Status

Accepted

## Context

The system must survive interruption during unresolved orders without duplicating exposure.

Snapshots alone are insufficient.

Broker truth alone is insufficient.

## Decision

Recovery will follow this model:

1. load the active control-plane revision
2. load the latest valid snapshot
3. replay canonical facts after the snapshot watermark
4. reconcile unresolved orders against broker truth where the mode requires it
5. resume only when recovery reaches a coherent outcome

Allowed recovery outcomes include:

- `ready`
- `degraded-ready`
- `blocked`
- `recovery-failed`

## Consequences

Positive:

- recovery becomes explicit and testable
- snapshots remain acceleration structures rather than hidden truth

Negative:

- reconciliation logic must be designed carefully up front
- broker adapters must support sufficient query capabilities
