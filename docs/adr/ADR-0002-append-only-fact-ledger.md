# ADR-0002: Append-Only Canonical Fact Ledger As System Of Record

## Status

Accepted

## Context

The current system has correctness risk around restart, reconciliation, and hidden mutable state.

The rewrite needs:

- durable lineage from decision to fill
- replayability
- restart-safe recovery
- projections that can be rebuilt

## Decision

Canonical runtime truth will be stored as append-only facts.

Snapshots, projections, and reports are not canonical truth.

Corrections happen through new facts, not in-place mutation.

## Consequences

Positive:

- strong auditability
- deterministic recovery model
- easier replay and incident reconstruction

Negative:

- requires deliberate projection design for read performance
- demands explicit schema evolution discipline
