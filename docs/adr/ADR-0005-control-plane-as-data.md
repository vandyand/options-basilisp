# ADR-0005: Control Plane As Data With Explicit Activation

## Status

Accepted

## Context

The existing system suffers from operational ambiguity around routing, process ownership, and safe account binding.

The rewrite needs:

- declarative routing
- reviewable rollout policy
- explicit kill switches
- startup-time validation

## Decision

Control-plane policy will be represented as immutable revisioned manifests with explicit activation records.

Runtime processes load the active revision and refuse unsafe bindings before trading starts.

## Consequences

Positive:

- routing becomes auditable
- unsafe process/account combinations fail early
- kill switches become visible and testable

Negative:

- manifest validation becomes a first-class subsystem
- operators must adopt explicit activation workflows
