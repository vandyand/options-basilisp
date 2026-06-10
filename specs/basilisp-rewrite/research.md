# Basilisp Rewrite — Research

## Problem Statement

Implement the StevenTrading Basilisp rewrite end to end: a ground-up replacement for the ~226K-LOC Python trading system, built per the **locked, normative v0.1 architecture package** in `docs/architecture/` (14 specs), `docs/adr/` (5 ADRs), and `NORTHSTAR.md`.

The Python system's chronic failure modes — train/serve skew, warm-restart fill drops, hidden mutable state, dual codebases, ambiguous broker truth — are all addressed structurally in the architecture: append-only fact ledger, deterministic engine step function, replay-stable order-intent identity, explicit state machines, control plane as data.

The deliverable is the full system through the NORTHSTAR build order: domain model → engine kernel → persistence/replay → sim broker → first E2E strategy → options execution path → paper broker adapter → parity and recovery validation. **Live trading cutover is explicitly out of scope** (gated on operator-run shadow validation per `MIGRATION_AND_IMPLEMENTATION_PLAN_V0.1.md` Phase 7).

## North-Star Orientation

- **Primary north star:** `NORTHSTAR.md` (repo root). Hard centers: canonical domain schema, deterministic engine step, append-only ledger, idempotent broker boundary, market-data provenance, control plane as data, structured observability, snapshot/restore as first-class.
- **Normative companion specs (all read end-to-end during exploration):**
  - `docs/architecture/ARCHITECTURE_SPEC_V0.1.md` — top-level shape, 17 bounded contexts, acceptance criteria §27
  - `docs/architecture/EVENT_COMMAND_TAXONOMY_V0.1.md` — fact/command/projection/snapshot language, envelopes, lineage
  - `docs/architecture/CANONICAL_SCHEMAS_V0.1.md` — ids, scalar conventions, envelope shapes, order-intent identity algorithm (§12)
  - `docs/architecture/ENGINE_STATE_AND_RECOVERY_V0.1.md` — state layers, decision cycle, recovery algorithm, reconciliation cases A–G
  - `docs/architecture/ENGINE_STATE_MACHINES_V0.1.md` — 4 transition tables (strategy/order/recovery/health)
  - `docs/architecture/PERSISTENCE_SCHEMA_AND_STORAGE_LAYOUT_V0.1.md` — 6 storage classes, partitioning, recovery read order
  - `docs/architecture/POLYLITH_WORKSPACE_AND_BOUNDARY_LAYOUT_V0.1.md` — component set, dependency rules, build order §12
  - `docs/architecture/BROKER_ADAPTER_CONTRACTS_V0.1.md` — command/fact shapes, reconciliation contract
  - `docs/architecture/MARKET_DATA_ADAPTER_CONTRACTS_V0.1.md` — observation families, provenance/quality rules
  - `docs/architecture/CONTROL_PLANE_MANIFESTS_AND_VALIDATION_V0.1.md` — manifest schema, validation, activation
  - `docs/architecture/STRATEGY_PIPELINE_AND_ARTIFACT_MODEL_V0.1.md` — 7 pipeline stages, artifact model
  - `docs/architecture/LEDGER_AND_PORTFOLIO_MODEL_V0.1.md` — lot model, cash model, derivation rules
  - `docs/architecture/OBSERVABILITY_AND_OPERATIONS_V0.1.md` — audit events, metrics, health
  - `docs/architecture/TESTING_AND_VERIFICATION_STRATEGY_V0.1.md` — test pyramid, golden properties, release gates
  - `docs/architecture/MIGRATION_AND_IMPLEMENTATION_PLAN_V0.1.md` — phases 0–7, parity strategy

## Codebase Context

### This repo (stevetrading-basilisp)

Workspace scaffold only — git-initialized during this exploration (initial commit `8af9f35`):

- `pyproject.toml` — pins `basilisp==0.5.1`, declares pytest `pythonpath` for ~40 planned component/base src dirs (most don't exist yet)
- `basilisp.edn` — empty map (project marker for editor jack-in)
- **6 stub component namespaces** (trivial defs only):
  - `components/domain.schemas/src/stevetrading/domain/schemas.lpy` — `schema-version`, `canonical-record-kinds`
  - `components/engine.state/src/stevetrading/engine/state.lpy` — `empty-engine-state`, `fresh-state`
  - `components/engine.machines/src/stevetrading/engine/machines.lpy` — `lifecycle-machine-ids`
  - `components/broker.protocol/src/stevetrading/broker/protocol.lpy` — command/fact type sets
  - `components/market-data.protocol/src/stevetrading/market_data/protocol.lpy` — observation/command type sets
  - `components/persistence.protocol/src/stevetrading/persistence/protocol.lpy` — command/read-model type sets
- **5 base stubs** (`describe-base` only): engine-live, engine-replay, control-plane, reports, dev
- `resources/` — example EDN artifacts: control-plane manifest (`control-plane/examples/paper-main-v0.1.edn`), replay fixture metadata (`fixtures/replay/simple-paper-session-v0.1.edn`), contract payloads (broker submit/ack, market bar/chain), artifact manifests (model + feature-manifest examples)
- `tests/` — README only; no tests exist
- Namespace convention: `stevetrading.<context>.<name>`, file extension `.lpy`, dirs with dots in component names (e.g. `components/domain.schemas/`)

### Reference: ascolais (~/ascolais)

Polylith Clojure monorepo this skill/lifecycle was extracted from. Relevant conventions adopted: components own public APIs, bases wire only, specs live under `specs/`, bb-task-style lint/test gates (replaced here by `scripts/lint.sh` + `scripts/test.sh` since this is Basilisp/pytest, not JVM/babashka).

### Reference: Python system (behavioral reference ONLY, per migration plan §2)

`~/contracting/upwork/steven-tran/SteveTrading/ref/Data-Preprocessor/` — ~226K LOC. Key behavioral references:
- V2 engine loop: `src/stevetrading_v2/engine/run_engine.py` (bar → signal → executor → broker → fills → portfolio)
- Broker ABC: `src/stevetrading_v2/brokers/broker.py` (submit_order/poll_fills/cancel/flatten)
- Sim broker: `src/stevetrading_v2/brokers/sim_broker.py` (mid ± slippage fills)
- Iron-condor execution: `scripts_5yr/live/iron_condor_executor.py` (4-leg entry/exit state machine)
- Control plane: `CONTROL_PLANE.md` + `src/stevetrading_v2/tools/control_plane.py`
- The architecture docs already encode the lessons from this system; do NOT port its structure.

## REPL Findings

All verified live against Basilisp 0.5.1 nREPL (port 36915, started via `.venv/bin/basilisp nrepl-server --port 36915` with component src dirs on `PYTHONPATH`):

1. **Toolchain:** `python3 -m venv .venv && .venv/bin/pip install basilisp==0.5.1 pytest` works (Python 3.12.3). `.venv/bin/basilisp version` → `Basilisp 0.5.1`.
2. **nREPL + clj-nrepl-eval:** `clj-nrepl-eval -p 36915 "(+ 1 2)"` → `3`. Stub namespaces load: `(require '[stevetrading.engine.state :as es]) (es/fresh-state)` returns the expected map.
3. **EDN:** `basilisp.edn` namespace provides `read-string`/`write-string` — round-trips maps, sets, keywords, strings. This is the canonical wire format.
4. **Python interop for canonical scalars:**
   - `(import hashlib)` → `(.hexdigest (hashlib/sha256 (.encode s "utf-8")))` works → SHA-256 for order-intent identity (CANONICAL_SCHEMAS §12.2)
   - `(import decimal)` → `(decimal/Decimal "1.25")` works → arbitrary-precision decimals; durable form is decimal **string**
   - `(import datetime)` → `(datetime.datetime/now (.-utc datetime/timezone))` works; datetime prints as `#inst`. Durable form is RFC 3339 UTC string.
   - **Syntax note:** module attribute access is `module/Attr` or `module.submodule/Attr`; dotted symbols like `decimal.Decimal` in operator position are a compile error (`symbol names may not contain the '.' operator`). Class attribute access uses `(.-attr obj)`.
5. **Protocols and records:** `defprotocol` + `defrecord` + inline implementation works (verified `(do-thing (->TestRec 10) 5)` → `15`).
6. **Test runner:** `basilisp test` (a pytest wrapper) discovers `tests/*.lpy`. Convention verified: `tests/` is on `sys.path` by default; a file `tests/test_probe.lpy` must declare ns `test-probe` (flat name relative to `tests/`, NOT `tests.test-probe` — that fails with ModuleNotFoundError). Subdirectory tests will use dotted ns relative to `tests/` (verify in Phase 0).
7. **pyproject pythonpath:** `[tool.pytest.ini_options].pythonpath` already lists every planned component src dir, so `basilisp test` run from repo root can require any component namespace without env vars.

## Requirements

### Functional (from ARCHITECTURE_SPEC §27 acceptance criteria + NORTHSTAR quality bar)

1. **One engine model across modes** — identical pure core for live/paper/sim/replay; mode differences only in adapters.
2. **Deterministic engine step** — `step(state, fact) → {state', commands, facts}` pure fold; replay of the same fact sequence produces identical decisions and identical `order-intent-id`s.
3. **Append-only fact ledger** — canonical envelopes per CANONICAL_SCHEMAS §7–8; facts never mutated; dedupe keys per family.
4. **Order-intent identity** — SHA-256 over canonicalized identity input (decision-id, intent-slot, account-id, role, order shape) per §12; restart/replay produce the same id; identity changes exactly when §12.4 says it must.
5. **Order lifecycle state machine** — all transitions from ENGINE_STATE_MACHINES §5.2 including cancel races and `orphaned-needs-reconcile`; illegal transitions fault without state mutation.
6. **Recovery** — fresh-start / warm-restart / crash-recovery / replay modes; snapshot + post-watermark fact replay + broker reconciliation (cases A–G); outcomes ready/degraded-ready/blocked/recovery-failed; all 7 crash-point acceptance tests from ENGINE_STATE_AND_RECOVERY §17 pass.
7. **Ledger and portfolio** — lot model with intent lineage; positions/cash/P&L derived purely from facts; partial fills/closes preserve lineage.
8. **Sim broker** — full broker protocol; deterministic fills; supports dedup/reconciliation tests.
9. **Paper broker adapter (Alpaca)** — canonical commands → Alpaca REST shapes; normalization of acks/status/fills; idempotency via client_order_id; contract tests against a stub transport (no live API calls in CI).
10. **Market data** — replay adapter emitting canonical observation facts from EDN fixtures; provenance and quality fields mandatory; live-source adapter shares the exact same fact shapes.
11. **Strategy pipeline** — 7 stages (market-state → features → inference → signal → risk → execution → intents) as pure functions; strategy declared as data; one simple direction strategy + one multi-leg options (iron-condor-style spread) strategy.
12. **Control plane** — EDN manifests with structural/safety/policy validation; activation records; runtime refuses unsafe bindings; kill switches.
13. **Observability** — structured audit events for every lifecycle/decision/order/recovery transition; health heartbeats; one trading session explainable from facts alone.
14. **Bases** — engine-replay (deterministic, fixture-driven) and engine-live (paper-capable assembly) runnable as CLI entrypoints; control-plane validate/activate CLI; reports base reading facts.
15. **Golden tests** — uninterrupted vs restarted convergence; duplicate-observation no-double-exposure; intent→ack→fill lineage; replay determinism.

### Non-Functional

- **Dependency direction enforced:** adapters → protocols → domain/core; no core → adapter imports (checked by a lint script).
- **No import-time I/O** (NORTHSTAR anti-goal). All config/artifact reads happen in base wiring functions.
- **No hidden closure state for correctness** — strategy-local state explicit and serializable.
- **Canonical scalars:** decimal strings, RFC 3339 UTC strings, namespaced keywords, ULIDs for record ids.
- **Tooling:** `scripts/test.sh` (basilisp test via pytest), `scripts/lint.sh` (compile-check all namespaces + dependency-direction check). Both must exit non-zero on failure.
- **Performance:** non-goal for v0.1 beyond "replay a session fixture in seconds."

## Options Considered

### Fact store technology

| Option | Pros | Cons |
|---|---|---|
| **SQLite (insert-only table + lineage indexes)** ✅ | Stdlib (`sqlite3`), economical lineage queries (PERSISTENCE §12: by order-intent-id, broker-order-id, correlation-id), monotonic offsets via rowid/autoincrement, atomic appends | Schema discipline needed to keep envelope canonical (store EDN payload column + indexed metadata columns) |
| JSONL/EDN-L append files | Trivially append-only, human-readable | Lineage queries require full scans or hand-rolled indexes; the Python system's JSONL logs are part of why recovery was unreliable |
| Embedded KV (lmdb etc.) | Fast | New dependency, no query model, overkill |

**Recommendation:** SQLite for canonical facts (single file per partition scope), EDN files for snapshots, control-plane revisions, fixtures, and artifacts. The persistence spec explicitly allows relational fact/projection storage (§13).

### ULID generation

| Option | Pros | Cons |
|---|---|---|
| **`python-ulid` dependency** ✅ | Tiny, battle-tested, monotonic option | One more dep |
| Hand-roll in domain.identifiers | Zero deps | Crockford base32 + monotonicity is easy to get subtly wrong; not core domain value |

**Recommendation:** `python-ulid` (add to pyproject). Wrap behind `stevetrading.domain.identifiers/new-record-id` so the dependency is swappable.

### Wire format for durable records

EDN (via `basilisp.edn`) ✅ over JSON — preserves keywords/sets exactly (CANONICAL_SCHEMAS requires namespaced-keyword enums round-tripping); JSON would need a lossy mapping layer. JSON reserved for structured log output where external tooling matters (observability adapter may emit JSON lines).

### Paper broker scope in this run

| Option | Pros | Cons |
|---|---|---|
| **Adapter + contract tests against stub transport** ✅ | Proves normalization/idempotency/reconciliation logic; zero risk to Steve's production paper accounts (CHESTNUT/LYNX/etc. are live experiment accounts; Alpaca connection limits are shared) | Live connectivity unproven until operator smoke test |
| Hit real Alpaca paper API in tests | "Realer" | Risks interfering with the production Python daemon's accounts and connection limits; non-deterministic CI |

**Recommendation:** stub-transport contract tests. Live smoke is an operator action post-run (documented in the engine-live base README).

## Recommendation

Implement in the POLYLITH_WORKSPACE §12 build order, one spec with phased delivery (each phase = one or more components brought from stub to spec-complete with tests):

0. Toolchain hardening (venv, scripts/test.sh, scripts/lint.sh, nREPL workflow, test-layout conventions)
1. `domain.*` (identifiers, enums, instruments, schemas, validation) — envelopes, ids, intent-identity algorithm
2. `engine.state`, `engine.fold`, `engine.machines` — state shape, fact fold, 4 transition tables
3. `persistence.protocol/fact-store/snapshot-store` + `engine.recovery` — SQLite fact log, EDN snapshots, watermarks, recovery planner
4. `broker.protocol`, `broker.sim` — sim broker with deterministic fills
5. `market-data.protocol`, `market-data.replay`, `replay.fixture` — fixture-driven observation stream
6. `ledger.core`, `portfolio.core` — lot/cash folds, derived views
7. `strategy.registry`, `feature.core`, `inference.core`, `signal.core`, `risk.core`, `execution.core` — pipeline + simple direction strategy
8. `base.engine-replay` — end-to-end happy path over `simple-paper-session-v0.1.edn` fixture + golden replay/restart tests
9. Options execution path — multi-leg intents, spread strategy, sim fills for legs
10. `broker.alpaca` (stub-transport contract tests; NO live market-data adapter — explicitly deferred to operator-phase work) + `control-plane.*` + `observability.structured-log` + `base.engine-live`, `base.control-plane`
11. Recovery/parity validation suite (7 crash scenarios, golden properties) + `base.reports`
12. Doc sync (NORTHSTAR status, repo README, spec index)

## Resolved Questions (verified during exploration)

- **Q: Does Basilisp 0.5.1 support everything needed?** Yes — protocols, records, EDN, hashlib/decimal/datetime interop, nREPL, pytest integration all verified at the REPL (see REPL Findings).
- **Q: How do tests get discovered?** `basilisp test` from repo root; files under `tests/` with ns named relative to `tests/`; component src dirs resolvable via pyproject `pythonpath`.
- **Q: Git situation?** Repo initialized (was untracked inside an unrelated parent repo); branch `feature/basilisp-rewrite`; no remote — PR step degrades gracefully to local-only; polish runs local lint/test + codex adversary.

## Open Questions

All initial open questions were resolved during init (decisions recorded in the README Key Decisions table):

1. **Subdirectory test namespaces** — RESOLVED (verified at REPL): `tests/domain/test_schemas.lpy` with ns `domain.test-schemas` is discovered and passes.
2. **Canonical EDN serialization for hashing** — RESOLVED (decision): hand-rolled canonical serializer in `domain.schemas` (sorted keys, canonical leg sort). `basilisp.edn/write-string` printed test maps stably, but printer internals are not a contract — do not rely on them for identity hashing.
3. **Decimal handling in EDN** — RESOLVED (decision): durable form is decimal *string* per CANONICAL_SCHEMAS §4.2; payloads store strings, domain logic converts via `decimal/Decimal` at the boundary.
4. **Engine step granularity** — RESOLVED (decision): `step1(state, fact)` pure primitive (named `fold-fact` in `engine.fold`) + cycle batcher; commands dispatched once per cycle at the shell.
5. **Alpaca REST surface for the adapter** — RESOLVED (approach): capture shapes from the proven local Python reference (`alpaca_paper_broker.py`) during Phase 10; tests use a stub transport. Remaining unknowns (exact multi-leg response fields) are bounded inside Phase 10's tasks.

## References

- Architecture package: `docs/architecture/*.md` (14 files), `docs/adr/ADR-000[1-5]*.md`, `NORTHSTAR.md`
- Example resources: `resources/control-plane/examples/paper-main-v0.1.edn`, `resources/fixtures/replay/simple-paper-session-v0.1.edn`, `resources/contracts/**/*.edn`, `resources/artifacts/examples/*.edn`
- Stub namespaces: `components/{domain.schemas,engine.state,engine.machines,broker.protocol,market-data.protocol,persistence.protocol}/src/stevetrading/**/*.lpy`
- Python behavioral reference: `~/contracting/upwork/steven-tran/SteveTrading/ref/Data-Preprocessor/src/stevetrading_v2/` (engine, brokers, primitives)
- Basilisp docs: https://basilisp.readthedocs.io (v0.5.1); test runner = pytest plugin
- REPL: `.venv/bin/basilisp nrepl-server --port 36915` with `PYTHONPATH=$(cat .nrepl-pythonpath)`; evaluate via `clj-nrepl-eval -p 36915 "<form>"`
