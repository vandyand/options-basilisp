# ADR Index

This directory records the first irreversible architecture decisions for the Basilisp rewrite.

Current ADR set:

1. `ADR-0001`: modular monolith runtime with Polylith-style codebase
2. `ADR-0002`: append-only canonical fact ledger as system of record
3. `ADR-0003`: deterministic order-intent identity and idempotent broker boundary
4. `ADR-0004`: snapshot plus replay plus broker-reconciliation recovery model
5. `ADR-0005`: control plane as data with explicit activation

ADR rules:

- ADRs record decisions, not brainstorming
- decisions here should align with the architecture package
- later reversals should happen through superseding ADRs, not silent edits

Implementation note (2026-06-10): the basilisp-rewrite spec implemented the system conforming to ADR-0001..0005; no ADR required amendment during implementation.
