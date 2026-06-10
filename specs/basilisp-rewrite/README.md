---
title: "Basilisp Rewrite"
status: planned
date: 2026-06-10
priority: 1
---
# Basilisp Rewrite

Ground-up implementation of the StevenTrading Basilisp rewrite, end to end, per the locked v0.1 architecture package (`docs/architecture/`, `docs/adr/`, `NORTHSTAR.md`). Replaces the ~226K-LOC Python system's runtime with a Polylith-style modular monolith: append-only fact ledger, deterministic engine step function, replay-stable order-intent identity, explicit state machines, control plane as data.

See [research.md](research.md) for exploration findings and [implementation-plan.md](implementation-plan.md) for the phased plan.

## Scope

**In:** the full NORTHSTAR build order — domain model, engine kernel, persistence + recovery, sim broker, replay mode, first E2E strategy, options execution path, paper broker adapter (stub-transport contract tests), control plane, observability, recovery/parity validation, reports base.

**Out (explicit non-goals):** live trading cutover, real Alpaca API calls (Steve's paper accounts are production experiment accounts; connection limits are shared with the running Python daemon), model training pipeline, performance optimization, UI/dashboard.

## Key Decisions

| Decision | Choice | Alternative rejected | Why |
|---|---|---|---|
| Fact store | SQLite, insert-only, lineage-indexed | JSONL append files | PERSISTENCE §12 operational queries (by order-intent-id, broker-order-id, correlation-id) need indexes; JSONL is part of why the Python system's recovery was unreliable |
| Snapshot/control-plane/fixture storage | EDN files (atomic tmp+rename writes) | SQLite blobs | Human-inspectable, matches `resources/` examples, snapshots are replaceable accelerators |
| Durable wire format | EDN via `basilisp.edn` | JSON | Namespaced keywords and sets must round-trip exactly (CANONICAL_SCHEMAS §4.4); JSON needs a lossy mapping layer. JSON used only for structured log output |
| Record ids | `python-ulid` dependency wrapped behind `domain.identifiers/new-record-id` | hand-rolled ULID | Crockford base32 + monotonicity is easy to get subtly wrong; wrapper keeps it swappable |
| Intent-identity hashing | Hand-rolled canonical serializer (sorted keys, canonical leg sort) + SHA-256 | rely on `edn/write-string` ordering | Printer ordering is an implementation detail; identity must be stable across versions (CANONICAL_SCHEMAS §12) |
| Decimals | `decimal.Decimal` in memory, decimal **string** durable | floats | CANONICAL_SCHEMAS §4.2 forbids binary floats in canonical numeric fields |
| Engine step shape | `step1(state, fact) → {state', commands, facts}` + `cycle` batcher | monolithic per-bar loop | Fold purity is the hard center (ARCHITECTURE §8.2); cycle batching keeps command dispatch at the shell |
| Paper broker testing | Contract tests against stub transport | live Alpaca paper calls | Zero risk to production paper accounts; deterministic CI; live smoke is an operator action |
| Alpaca transport | stdlib `urllib.request` behind an injectable transport fn | `requests`/`httpx` dep | One less dependency; transport injection is needed for contract tests anyway |
| Test layout | `tests/<area>/test_*.lpy`, ns relative to `tests/` | per-component `test/` dirs | Verified working with `basilisp test` (pytest wrapper); component test dirs can come later without moving logic |
| Repo/git | Own repo, local-only branch `feature/basilisp-rewrite`, no remote | push to GitHub | No remote authorized for this client work yet; PR step degrades gracefully; operator can add a remote later |

## Implementation Status

See [implementation-plan.md](implementation-plan.md). Phases:

- Phase 0: Toolchain hardening (scripts, lint, deps)
- Phase 1: Domain core (`domain.*`)
- Phase 2: Engine kernel (`engine.state`, `engine.fold`, `engine.machines`)
- Phase 3: Persistence + recovery (`persistence.*`, `engine.recovery`)
- Phase 4: Sim broker (`broker.protocol`, `broker.sim`)
- Phase 5: Market data replay (`market-data.*`, `replay.fixture`)
- Phase 6: Ledger + portfolio (`ledger.core`, `portfolio.core`)
- Phase 7: Strategy pipeline (`strategy.registry`, `feature/inference/signal/risk/execution.core`, `artifact.*`)
- Phase 8: Replay base end-to-end + golden tests (`engine.commands`, `base.engine-replay`)
- Phase 9: Options execution path (multi-leg intents, spread strategy)
- Phase 10: Control plane, observability, Alpaca adapter, live base
- Phase 11: Recovery validation suite + reports + doc sync
