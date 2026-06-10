# Basilisp Rewrite — Implementation Plan

## Overview

Implement the full system in the POLYLITH_WORKSPACE §12 build order. Each phase brings one slice from stub to spec-complete with tests. The architecture docs in `docs/architecture/` are **normative** — when a task cites a section (e.g. "CANONICAL_SCHEMAS §12"), read that section before implementing; do not re-derive shapes from memory.

## Prerequisites

- Python 3.12 venv at `.venv/` with `basilisp==0.5.1`, `pytest` (exists; Phase 0 adds `python-ulid`).
- **REPL:** nREPL on port 36915. If dead, restart with:
  `PYTHONPATH=$(cat .nrepl-pythonpath) nohup .venv/bin/basilisp nrepl-server --port 36915 > /tmp/basilisp-nrepl.log 2>&1 &`
  Evaluate with `clj-nrepl-eval -p 36915 "<form>"`.
  When you add a NEW component src dir mid-session, either restart the server or append the path live: `clj-nrepl-eval -p 36915 "(import sys) (.append sys/path \"components/<name>/src\")"`. Also append the new path to `.nrepl-pythonpath` (colon-separated) so restarts pick it up.
- **Tests:** run from repo root. `scripts/test.sh [pytest-args]` (after Phase 0) or `.venv/bin/basilisp test`. Narrow per-phase: `scripts/test.sh tests/<area>/`.
- **Interop syntax reminders** (verified at REPL): `(import hashlib)` then `(hashlib/sha256 ...)`; class attrs via `(.-attr obj)`; `module.submodule/fn` works (`datetime.datetime/now`); dotted symbols in operator position are a compile error.
- **Namespace/file mapping:** ns `stevetrading.domain.identifiers` → `components/domain.identifiers/src/stevetrading/domain/identifiers.lpy`. Hyphenated ns segments map to underscored dirs (`market-data` ns segment ↔ `market_data` dir). Test ns is relative to `tests/` (file `tests/domain/test_schemas.lpy` declares ns `domain.test-schemas`).
- Every new component needs its `src` path added to `pyproject.toml` `[tool.pytest.ini_options].pythonpath` **if not already listed** (most are pre-listed — check first).

## Phase 0: Toolchain Hardening

Goal: reproducible test/lint gates so every later phase has a green/red signal.

- [ ] Add `python-ulid>=2.7` to `pyproject.toml` `[project].dependencies`; `.venv/bin/pip install python-ulid` and verify: `clj-nrepl-eval -p 36915 "(import ulid) (str (ulid/ULID))"` returns a 26-char ULID string.
- [ ] Create `scripts/test.sh` (executable): `#!/usr/bin/env bash`, `set -euo pipefail`, cd to repo root (`cd "$(dirname "$0")/.."`), exec `.venv/bin/basilisp test "$@"`. No output piping — exit code must propagate.
- [ ] Create `scripts/compile_check.py` (executable, run with `.venv/bin/python`): walks `components/*/src` and `bases/*/src`, computes each `.lpy` file's namespace from its path, puts all src dirs on `sys.path`, then imports every namespace via `basilisp.main.init()` + `importlib.import_module` (basilisp registers an import hook; module name = ns name with `-`→`_`). Any import failure prints the ns + traceback and exits 1.
- [ ] Create `scripts/check_deps.py` (executable): parses `(:require ...)` / `(require ...)` forms from every component `.lpy` via regex, and enforces dependency direction (POLYLITH §7): namespaces under `stevetrading.domain.*`, `stevetrading.engine.*`, `stevetrading.ledger.*`, `stevetrading.portfolio.*`, and the pure pipeline (`stevetrading.{strategy,feature,inference,signal,risk,execution}.*`) may NOT require adapter namespaces (`stevetrading.broker.alpaca*`, `stevetrading.broker.sim*`, `stevetrading.market-data.replay*`, `stevetrading.market-data.polygon*`, `stevetrading.persistence.fact-store*`, `stevetrading.persistence.snapshot-store*`, `stevetrading.observability.structured-log*`, `stevetrading.control-plane.file-store*`, `stevetrading.artifact.file-store*` — match the hyphenated ns names as they appear in `:require` forms, not the underscored file paths) nor any `stevetrading.base.*` namespace. Protocol components (`*.protocol`) are importable by anyone. Violations print and exit 1.
- [ ] Create `scripts/lint.sh` (executable): runs `compile_check.py` then `check_deps.py`, propagating exit codes (`set -euo pipefail`).
- [ ] Create `scripts/nrepl.sh` (executable): kills any `basilisp nrepl-server` on port 36915, regenerates `.nrepl-pythonpath` from `ls -d components/*/src bases/*/src`, starts the server backgrounded as in Prerequisites.
- [ ] Add a smoke test `tests/test_toolchain.lpy` (ns `test-toolchain`): requires `stevetrading.engine.state` and asserts `(= 1 (:engine/version (state/fresh-state)))`.
- [ ] Verify `scripts/test.sh` exits 0 and `scripts/lint.sh` exits 0 from repo root.

**REPL checkpoints:**
- `(import ulid) (str (ulid/ULID))` → 26-char string
- `(require '[stevetrading.engine.state :as es]) (:engine/version (es/fresh-state))` → `1`

**Narrow test:** `scripts/test.sh tests/test_toolchain.lpy`

## Phase 1: Domain Core

Goal: canonical ids, enums, envelopes, validation, and the order-intent identity algorithm. Normative: CANONICAL_SCHEMAS (whole doc), EVENT_COMMAND_TAXONOMY §5–9.

- [ ] `components/domain.identifiers/src/stevetrading/domain/identifiers.lpy` (new component): `new-record-id` (ULID string via python-ulid), `valid-strategy-id?` (`strategy/<family>/<name>/v<major>` per §5.2.1), `valid-account-id?` (`account/<broker>/<logical-name>`), `parse-strategy-id`/`parse-account-id` returning maps or nil.
- [ ] `components/domain.instruments/src/stevetrading/domain/instruments.lpy` (new): `instrument-id` from structured ref (equity/option/future formats per §5.2.3, strike rendered with exactly 3 decimal places like `550.000`), `parse-instrument-id` (inverse), `instrument-ref` canonical map shape per §6.1, `canonical-leg-sort` (sort legs by [instrument-id, side, quantity] per §12.3).
- [ ] `components/domain.enums/src/stevetrading/domain/enums.lpy` (new): named sets for `modes` (`:mode/live :mode/paper :mode/sim :mode/replay :mode/shadow` + `:mode/control-plane :mode/dev :mode/report` used by bases), `order-sides`, `position-effects`, `order-types`, `tifs`, `intent-roles`, `broker-statuses` (BROKER_ADAPTER §5.2 list), `liquidity`, `health-states`, `recovery-states`, `strategy-lifecycle-states`, `order-lifecycle-states` (ENGINE_STATE_MACHINES §4.1/§5.1/§6.1/§7.1), plus `fact-types` and `command-types` (the full canonical v0.1 lists from EVENT_COMMAND_TAXONOMY §8–9, as `:fact/...`/`:command/...` keywords).
- [ ] `components/domain.schemas/src/stevetrading/domain/schemas.lpy` (extend stub): 
  - `canonicalize` — recursively sort map keys (by `pr-str` of key), canonically sort legs via `instruments/canonical-leg-sort` when value is under `:legs`/`:order-intent/legs`; leave vectors otherwise ordered.
  - `canonical-edn-str` — deterministic serialization of a canonicalized value (write maps with sorted keys explicitly; verified NOT to rely on printer internals).
  - `sha256-hex` — via hashlib interop.
  - `decision-id` — `"dec_" + sha256-hex(canonical-edn-str(decision-seed))` (seed keys per §5.2.6: strategy-id, decision-scope, source-fact-ids or watermark tuple, decision timestamp, decision slot).
  - `order-intent-id` — `"oi_" + sha256-hex(canonical-edn-str(identity-input))` where identity-input is exactly the §12.1 map (`:identity/version 1`, decision-id, intent-slot, account-id, role, order-shape with side/effect/order-type/tif/quantity/limit-price/stop-price/legs).
  - `fact-envelope` / `command-envelope` constructors taking payload + metadata, filling `:record/id` via `identifiers/new-record-id`, validating required keys per CANONICAL_SCHEMAS §8/§9 (fact: occurred-at, recorded-at, payload; command: issued-at, target-adapter, idempotency-key, payload).
  - `snapshot-envelope` constructor per §10.
- [ ] `components/domain.validation/src/stevetrading/domain/validation.lpy` (new): `validate-fact`/`validate-command`/`validate-snapshot` returning `{:valid? true}` or `{:valid? false :errors [{:error/code ... :error/path ... :error/message ...}]}`. Checks: required keys present, `:record/type` in known fact/command type sets, enum values in strict fields valid, timestamps match RFC 3339 UTC regex (`Z`-suffixed), quantities/prices are strings parseable as Decimal (reject floats — `(float? v)` → error), business ids well-formed.
- [ ] Tests `tests/domain/` (ns `domain.test-*`): 
  - `test_identity.lpy` — same identity input → same `order-intent-id` across two calls and across canonical-vs-shuffled key order; each §12.4 mutation (account, role, quantity, leg set, order type, limit price, decision slot) → different id; §12.5 invariants (extra envelope metadata does not affect id).
  - `test_schemas.lpy` — envelope constructors produce validation-passing records; missing required key → invalid; float quantity → invalid.
  - `test_instruments.lpy` — equity/option id round-trip; leg sort canonical ordering; strike formatting `550.000`.
- [ ] Update the old stub API consumers: keep `schema-version`/`canonical-record-kinds` working (tests may reference).

**REPL checkpoints:**
- `(require '[stevetrading.domain.schemas :as sch])` then build the §12.1 example identity input and call `(sch/order-intent-id ident)` twice → identical `"oi_..."` strings
- `(sch/order-intent-id (assoc-in ident [:identity/order-shape :quantity] "2"))` → different id
- `(require '[stevetrading.domain.validation :as v])` `(v/validate-fact (sch/fact-envelope ...))` → `{:valid? true}`

**Narrow test:** `scripts/test.sh tests/domain/`

## Phase 2: Engine Kernel

Goal: engine state shape, the four state machines as data tables, and the pure fact fold. Normative: ENGINE_STATE_AND_RECOVERY §3–7, ENGINE_STATE_MACHINES (whole doc).

- [ ] `components/engine.state/src/stevetrading/engine/state.lpy` (extend stub): full state shape per ENGINE_STATE_AND_RECOVERY §4 — `:engine/run` (run-id, engine-version, mode, started-at, control-plane revision), `:engine/strategies` (per-strategy: lifecycle state, signal-local state, last-processed market ts, last decision ts, posture), `:engine/unresolved-orders` (keyed by order-intent-id; fields per §4.3), `:engine/portfolio` (derived cache), `:engine/watermarks` (`:watermark/fact-log`, `:watermark/market`, `:watermark/broker`, `:watermark/control-plane`), `:engine/health` (level, active degradations). Constructors: `fresh-state`, `init-run`, accessors/updaters (`strategy-state`, `unresolved-order`, `record-watermark`).
- [ ] `components/engine.machines/src/stevetrading/engine/machines.lpy` (extend stub): transition tables AS DATA — one vector of `{:machine :machine/order :from :acknowledged :trigger :fact/fill-observed :guard :guard/remaining-qty-zero :to :filled :effects [...]}` rows transcribing ENGINE_STATE_MACHINES §4.2, §5.2, §6.2, §7.2 **completely** (every row, including cancel races and `orphaned-needs-reconcile` rows). `transition` fn: `(transition machine-id current-state trigger guard-ctx)` → `{:transition/applied? true :transition/to ... :transition/effects [...]}` or `{:transition/applied? false :transition/reason :illegal|:no-row|:guard-failed}`. Guards are keywords resolved in a guard-fn map (e.g. `:guard/remaining-qty-zero` reads `guard-ctx`). Duplicate-fact convergence: a trigger that would re-enter the current terminal state returns `applied? false, reason :duplicate` without effects (§8.1).
- [ ] `components/engine.fold/src/stevetrading/engine/fold.lpy` (new component): `fold-fact` — pure `(fold-fact state fact)` → `{:state state' :emitted-facts [...] :pending-commands [...]}`. Dispatch on `:record/type`:
  - market observation facts → update market watermark + per-strategy market slices
  - `:fact/order-intent-created` → register unresolved order (machine `absent→intent-created`)
  - `:fact/command-dispatched` (submit) → `intent-created→submit-requested`
  - `:fact/broker-ack-accepted` → `→acknowledged` + record broker-order-id correlation
  - `:fact/broker-ack-rejected` → `→rejected`, resolve
  - `:fact/fill-observed` → partial/full fill transitions using remaining-quantity guard from intent qty vs cumulative fills (Decimal math); dedupe by `:fill/id` + broker context (duplicate → no-op)
  - cancel facts per table; reconciliation anomaly → `orphaned-needs-reconcile`
  - control facts → control-plane view + strategy enable/disable; kill switch → strategy halt transitions
  - illegal transitions → emit `:fact/fault-recorded` (invariant violation payload), state unchanged otherwise
- [ ] Tests `tests/engine/`:
  - `test_machines.lpy` — table-driven: every legal row applies; illegal transitions (§5.4 list) rejected; duplicate convergence; cancel-race rows (fill during cancel-requested → partially-filled/filled; cancel ack after fill → stays filled).
  - `test_fold.lpy` — fold a scripted fact sequence (intent → dispatch → ack → partial fill → full fill) and assert unresolved-order lifecycle states + final resolution; duplicate fill fact folds to identical state (`=` on state maps); out-of-order ack-after-fill handled per table.

**REPL checkpoints:**
- `(require '[stevetrading.engine.machines :as m]) (m/transition :machine/order :acknowledged :fact/fill-observed {:remaining-qty (decimal/Decimal "0")})` → `{:transition/applied? true :transition/to :filled ...}`
- fold the 5-fact happy sequence at the REPL → final unresolved-orders entry has `:order/lifecycle :filled`
- folding the same fill twice → `(= state-after-1 state-after-2)` is `true`

**Narrow test:** `scripts/test.sh tests/engine/`

## Phase 3: Persistence + Recovery

Goal: durable fact log, snapshots, watermarks, recovery planner. Normative: PERSISTENCE_SCHEMA (whole doc), ENGINE_STATE_AND_RECOVERY §8–14, ADR-0004.

- [ ] `components/persistence.protocol/src/stevetrading/persistence/protocol.lpy` (extend stub): `defprotocol FactStore` — `(append-facts! [this facts])` → `{:appended [{:fact-id ... :offset ...}] :duplicates [...]}`; `(facts-since [this offset])`; `(facts-by [this {:keys [order-intent-id correlation-id strategy-id fact-type ...]}])`; `(latest-offset [this])`. `defprotocol SnapshotStore` — `(write-snapshot! [this snapshot])`, `(latest-snapshot [this scope])`, `(snapshots [this scope])`. `defprotocol ControlPlaneStore` — `(active-revision [this scope])`, `(revision [this rev-id])`.
- [ ] `components/persistence.fact-store/src/stevetrading/persistence/fact_store.lpy` (new): SQLite implementation (`sqlite3` interop). Table `facts`: `offset INTEGER PRIMARY KEY AUTOINCREMENT`, `fact_id TEXT UNIQUE NOT NULL`, `fact_type TEXT NOT NULL`, `dedupe_key TEXT`, `correlation_id`, `strategy_id`, `account_id`, `instrument_id`, `order_intent_id`, `broker_order_id`, `occurred_at`, `recorded_at`, `mode`, `record TEXT NOT NULL` (canonical EDN of the full envelope). Unique partial index on `dedupe_key` (WHERE dedupe_key IS NOT NULL). Append is INSERT inside one transaction; a dedupe-key conflict reports the fact under `:duplicates` (no exception, no second row). Lineage columns extracted from the envelope/payload at append time. `facts-by` builds indexed WHERE clauses. WAL mode on open.
- [ ] `components/persistence.snapshot-store/src/stevetrading/persistence/snapshot_store.lpy` (new): EDN file per snapshot under `<root>/<scope>/snap-<snapshot-id>.edn` + `latest.edn` pointer; atomic write via tmp file + `os.replace`. `latest-snapshot` validates per ENGINE_STATE_AND_RECOVERY §8.5 (schema version supported, watermarks internally consistent, unresolved-order shard parseable) — invalid latest falls back to next-most-recent valid, corrupt file → skip with warning data.
- [ ] `components/engine.recovery/src/stevetrading/engine/recovery.lpy` (new): pure planner + impure executor split:
  - `plan-recovery` (pure): given control-plane revision, latest snapshot (or nil), latest fact offset → `{:recovery/mode :fresh-start|:warm-restart|:crash-recovery|:replay ...}` 
  - `run-recovery!` — executes ENGINE_STATE_AND_RECOVERY §10 steps 1–13 against the protocols + `engine.fold`: load snapshot state, fold facts after watermark, derive unresolved set, (mode-permitting) issue broker reconciliation queries via a passed-in broker, fold reconciliation facts, return `{:recovery/outcome :ready|:degraded-ready|:blocked|:recovery-failed :engine/state ... :recovery/facts [...]}` (emits `:fact/recovery-started`/`:fact/recovery-completed`).
  - Recovery lifecycle states tracked via `engine.machines` `:machine/recovery` table.
- [ ] Tests `tests/persistence/`:
  - `test_fact_store.lpy` — append/read round-trip preserves envelope exactly (EDN equality); offsets monotonic; duplicate dedupe-key reported not inserted; `facts-by` order-intent-id returns full lineage.
  - `test_snapshot_store.lpy` — write/read round-trip; corrupt latest falls back; §8.5 rejection rules.
  - `test_recovery.lpy` — warm restart: snapshot at watermark N + facts N+1.. folds to same state as folding all facts from 0 (golden convergence on a scripted sequence); unresolved order present in snapshot survives recovery; ambiguous lineage (fill fact for unknown intent) → `:blocked`.

**REPL checkpoints:**
- create a temp-dir fact store, append the Phase 2 happy sequence, `(count (facts-since fs 0))` → 5, re-append same facts → all under `:duplicates`
- `(run-recovery! ...)` over snapshot+tail → `{:recovery/outcome :ready}` and state equal to full fold

**Narrow test:** `scripts/test.sh tests/persistence/`

## Phase 4: Sim Broker

Goal: full broker protocol + deterministic simulator. Normative: BROKER_ADAPTER_CONTRACTS (whole doc).

- [ ] `components/broker.protocol/src/stevetrading/broker/protocol.lpy` (extend stub): `defprotocol Broker` — `(submit-order-intent! [this cmd])`, `(cancel-broker-order! [this cmd])`, `(open-orders [this account-id])`, `(fills-since [this account-id cursor])`, `(account-state [this account-id])`, `(health [this])`. ALL return values are canonical **facts** (or vectors of facts) built via `domain.schemas/fact-envelope` — never SDK/raw maps. Keep the existing type-set vars.
- [ ] `components/broker.sim/src/stevetrading/broker/sim.lpy` (new): `make-sim-broker` taking `{:fill-policy {:mode :immediate|:on-poll :price-source :limit|:mark :slippage "0.00"} :marks {instrument-id price-str} :clock (fn [] iso-ts)}`. Behavior:
  - submit → validates cmd payload; deterministic `broker-order-id` = `"sim-" + (subs order-intent-id 3 19)`; emits `:fact/broker-ack-accepted` (or `:fact/broker-ack-rejected` when intent invalid / kill-switched via `:reject-next` test hook); fill per policy: emits `:fact/fill-observed` per leg (fill-id `"<broker-order-id>-fill-<n>"`, price from limit or mark ± slippage, Decimal strings).
  - duplicate submit for an already-accepted idempotency key → returns the SAME ack fact content (no new broker order) per §9.
  - cancel → if unfilled: `:fact/broker-order-status-observed` with `:broker-status/cancelled`; if already filled: cancel-reject + the fill stands (cancel-race per §7).
  - partial-fill support: `:fill-policy {:mode :partial :tranches ["1" "2"]}` splits quantity.
  - internal journal (atom) answers `open-orders` / `fills-since` for reconciliation; journal is NOT canonical truth (engine appends the facts it receives).
- [ ] Tests `tests/broker/test_sim.lpy` — the six TESTING §6 broker contract cases: submit accepted; submit rejected; duplicate submit idempotent (same broker-order-id, no double fill); partial then full fill (quantities sum, lifecycle correct when folded via engine.fold); cancel race (fill before cancel → filled + cancel rejected); reconciliation: after submits, `open-orders`/`fills-since` return normalized facts that fold cleanly.

**REPL checkpoints:**
- build sim broker, submit a sample intent command → vector of facts `[:fact/broker-ack-accepted :fact/fill-observed]` with Decimal-string prices
- submit same command again → ack with same `:broker/order-id`, no new fill

**Narrow test:** `scripts/test.sh tests/broker/`

## Phase 5: Market Data Replay

Goal: fixture-driven canonical observation stream. Normative: MARKET_DATA_ADAPTER_CONTRACTS (whole doc).

- [ ] `components/market-data.protocol/src/stevetrading/market_data/protocol.lpy` (extend stub): `defprotocol MarketDataSource` — `(next-observations [this cursor max-n])` → `{:observations [facts] :cursor next-cursor :exhausted? bool}`; `(source-health [this])`. Observations are canonical facts with provenance (`:data/provider`, `:data/provider-ref`, `:data/received-at`, quality map) per §4–5.
- [ ] `components/replay.fixture/src/stevetrading/replay/fixture.lpy` (new): fixture v0.2 EDN format: `{:fixture/id ... :fixture/version 2 :fixture/inputs [{:input/at "..." :input/type :fact/market-bar-observed :input/payload {...}} ...] :fixture/expected-outputs [{:record/type ...} ...]}`. `load-fixture` (read + validate: inputs sorted by `:input/at`, payloads validate as their fact types), `write-fixture`.
- [ ] Create `resources/fixtures/replay/simple-paper-session-v0.2.edn`: ~10 one-minute SPY bars (rising then falling closes so the Phase 7 SMA-crossover strategy enters long then flattens) + 1 calendar session fact + expected-outputs listing the fact types from the v0.1 fixture (prediction-produced, signal-decision-produced, risk-decision-recorded, order-intent-created, broker-ack-accepted, fill-observed). Keep v0.1 file untouched.
- [ ] `components/market-data.replay/src/stevetrading/market_data/replay.lpy` (new): `make-replay-source` over a loaded fixture; wraps each input payload in a fact envelope with provider `:market-data/replay`, provider-ref `"<fixture-id>:<index>"`, `:data/received-at` = input timestamp (synthetic timing per §9); cursor = input index.
- [ ] Tests `tests/market_data/test_replay.lpy` — provenance completeness on every emitted fact (validate-fact passes; provider/provider-ref/received-at present); cursor pagination; exhaustion; fixture validation rejects unsorted inputs and missing provenance-required fields.

**REPL checkpoints:**
- `(load-fixture "resources/fixtures/replay/simple-paper-session-v0.2.edn")` → map with 10+ inputs
- `(next-observations src 0 3)` → 3 valid facts, `:cursor 3`

**Narrow test:** `scripts/test.sh tests/market_data/`

## Phase 6: Ledger + Portfolio

Goal: canonical financial folds and derived views. Normative: LEDGER_AND_PORTFOLIO_MODEL (whole doc).

- [ ] `components/ledger.core/src/stevetrading/ledger/core.lpy` (new): `empty-ledger`; `fold-ledger-fact` — pure fold over `:fact/fill-observed` (+ explicit `:fact/cash-movement-recorded`, `:fact/position-lot-opened/closed` if present): derives lots (lot-id `"lot-" + fill-id`, originating order-intent-id, instrument, open ts, open qty, remaining qty, cost basis from fill price × qty ± fees, strategy-id, account-id per §5); opening vs closing effect from the originating intent's `:order-intent/effect` (passed in ctx map of intent-id → intent payload); closes consume lots FIFO with partial-close splitting; cash movements: trade principal (sign by side) + fees per §6; emits derived ledger facts (`:fact/position-lot-opened`, `:fact/position-lot-closed`, `:fact/cash-movement-recorded`) so derivation is explicit and durable.
- [ ] `components/portfolio.core/src/stevetrading/portfolio/core.lpy` (new): `derive-portfolio` from ledger state (+ optional marks map): net positions per instrument, open lots, cash, realized P&L (sum of closed-lot proceeds − basis), unrealized (marks − basis on open lots; nil-safe when no mark), gross/net exposure, per-strategy and per-account views per §7/§11. Output stamps `:portfolio/source-watermark`.
- [ ] Tests `tests/ledger/`:
  - `test_ledger.lpy` — open fill creates lot + principal cash movement; partial close consumes FIFO with exact lineage (closed portion references original lot + closing intent); fees reduce cash; Decimal-string in/out everywhere (no floats).
  - `test_portfolio.lpy` — realized P&L on a round trip = (sell − buy) × qty − fees; unrealized from marks; rebuild-from-facts: fold full fact list twice → `=` portfolio.

**REPL checkpoints:**
- fold buy-fill then sell-fill at higher price → `(:portfolio/realized-pnl ...)` is positive Decimal string
- partial close: buy "3", sell "1" → one open lot remaining "2", one closed lot "1"

**Narrow test:** `scripts/test.sh tests/ledger/`

## Phase 7: Strategy Pipeline

Goal: declarative strategy + 7 pure pipeline stages + first direction strategy. Normative: STRATEGY_PIPELINE_AND_ARTIFACT_MODEL (whole doc), ARCHITECTURE §17–19.

- [ ] `components/artifact.protocol/src/stevetrading/artifact/protocol.lpy` (new): `defprotocol ArtifactStore` — `(feature-manifest [this ref])`, `(model-artifact [this ref])` returning EDN maps per STRATEGY_PIPELINE §7.
- [ ] `components/artifact.file-store/src/stevetrading/artifact/file_store.lpy` (new): reads `resources/artifacts/<kind>/<ref-with-slashes>.edn`; ref `"feature/simple-direction/v1"` → `resources/artifacts/feature/simple-direction/v1.edn`. Create example artifacts: feature manifest `feature/simple-direction/v1` (features `[:feature/sma-fast :feature/sma-slow :feature/last-close]`, required inputs `[:input/bar-1m]`) and model `model/simple-direction/v1` (`:model/type :model.type/sma-crossover`, `:model/params {:fast 3 :slow 5}`, prediction-schema-version 1).
- [ ] `components/feature.core/src/stevetrading/feature/core.lpy` (new): `derive-features` — `(derive-features manifest market-slice)` → `{:feature/values {kw decimal-str} :feature/as-of ts}`. Implement sma-n over the slice's bar closes (Decimal), last-close, bar-count. Deterministic; no I/O; insufficient history → `{:feature/insufficient? true :feature/needed n}`.
- [ ] `components/inference.core/src/stevetrading/inference/core.lpy` (new): `run-inference` — `(run-inference model-artifact features)` → canonical prediction map `{:prediction/value decimal-str :prediction/direction :direction/up|:direction/down|:direction/flat :prediction/model-ref ... :prediction/schema-version 1 :prediction/at ts}`. For `:model.type/sma-crossover`: direction up when fast > slow, down when fast < slow.
- [ ] `components/signal.core/src/stevetrading/signal/core.lpy` (new): `decide-signal` — `(decide-signal strategy-decl prediction market-slice strategy-local-state)` → `{:decision/posture :posture/enter-long|:posture/flatten|:posture/hold :decision/reason-codes [...] :decision/market-time ts :decision/id ...}` (decision-id via `domain.schemas/decision-id`). Posture change only on crossover state change (strategy-local `:last-direction` memory).
- [ ] `components/risk.core/src/stevetrading/risk/core.lpy` (new): `evaluate-risk` — `(evaluate-risk policy signal portfolio-view account-ctx)` → `{:risk/decision :risk/allow|:risk/deny|:risk/resize :risk/reason-codes [...] :risk/approved-quantity decimal-str}`. Policy `:risk/simple-direction-default`: max 1 open position per instrument, deny enter when position exists, allow flatten always.
- [ ] `components/execution.core/src/stevetrading/execution/core.lpy` (new): `plan-execution` — `(plan-execution policy risk-approved-signal instrument-ctx account-id)` → `{:execution/plan ... :execution/order-intents [full :fact/order-intent-created payloads]}` with intent ids from `domain.schemas/order-intent-id`, intent-slot per intent, policy `:execution/market-equity-v1` (market order, tif day, qty from risk).
- [ ] `components/strategy.registry/src/stevetrading/strategy/registry.lpy` (new): `validate-strategy-decl` (STRATEGY_PIPELINE §4 minimum shape + artifact compatibility per §8: model's expected feature-manifest-ref matches declared), `build-registry` (vector of decls → map by strategy-id; rejects duplicates), `run-pipeline` — the stage composer: `(run-pipeline {:strategy decl :market-slice ... :strategy-local-state ... :portfolio-view ... :artifacts {:feature-manifest m :model m} :account-id ...})` → `{:facts [prediction-produced signal-decision-produced risk-decision-recorded order-intent-created...] :strategy-local-state' ...}` — pure; emits NO facts when posture is `:posture/hold`.
- [ ] Define strategy `strategy/simple-direction/sma-cross/v1` as data (EDN at `resources/strategies/simple-direction-sma-cross-v1.edn`): mode-policy `#{:mode/replay :mode/sim :mode/paper}`, warmup `{:required-bars 5}`, features/inference/signal/risk/execution refs above, schedule `{:session :session/us-equities-regular}`.
- [ ] Tests `tests/strategy/test_pipeline.lpy` — full pipeline over a rising-bar slice emits the 4 decision facts with valid envelopes and stable intent id on re-run; hold posture emits nothing; risk denies double-entry; insufficient warmup → no decision; artifact incompatibility (mismatched manifest ref) rejected by `validate-strategy-decl`.

**REPL checkpoints:**
- `(run-pipeline ...)` on the v0.2 fixture's first 6 bars → facts ending in `:fact/order-intent-created`; running twice → same `order-intent-id`
- same input with existing position in portfolio-view → risk deny, no intent

**Narrow test:** `scripts/test.sh tests/strategy/`

## Phase 8: Replay Base End-to-End + Golden Tests

Goal: the imperative shell + first full session. Normative: ARCHITECTURE §9 (canonical runtime model), EVENT_COMMAND_TAXONOMY §10, ENGINE_STATE_AND_RECOVERY §6.

- [ ] `components/engine.commands/src/stevetrading/engine/commands.lpy` (new): `derive-commands` (pure): from intents/decisions → `:command/submit-order-intent` envelopes (idempotency-key `"submit/intent/" + order-intent-id`, target-adapter `:adapter/broker`); `dispatch-commands!` (impure): routes commands to adapters (broker protocol), emits `:fact/command-dispatched` before adapter call and appends adapter-returned facts after; submit-dedupe rule: skip dispatch when state proves the intent already accepted/completed (ENGINE_STATE_AND_RECOVERY §12.1).
- [ ] `bases/engine-replay/src/stevetrading/base/engine_replay.lpy` (extend stub): `run-replay` — `(run-replay {:fixture-path ... :strategy-paths [...] :artifact-root ... :out-dir ...})`:
  1. wire adapters (replay source, sim broker, SQLite fact store at `<out-dir>/facts.db`, snapshot store at `<out-dir>/snapshots/`)
  2. load + validate strategies, init engine state (mode `:mode/replay`, run-id)
  3. loop: pull observations → append → fold → run pipeline per active strategy (warmup via strategy lifecycle machine: `warming-up` until required-bars consumed, then `active`) → append decision facts → derive/dispatch commands → append outcome facts → fold outcomes → **ledger/portfolio integration point:** every folded `:fact/fill-observed` is also folded through `ledger.core/fold-ledger-fact` (with the intent ctx from unresolved-order state); emitted derived ledger facts are appended to the fact store; `portfolio.core/derive-portfolio` refreshes the engine state's `:engine/portfolio` cache from ledger state at the end of each cycle, so the NEXT pipeline invocation's risk stage reads a current portfolio-view → snapshot every N facts (configurable, default 50)
  4. finish: final snapshot, summary map `{:facts-appended n :orders {...} :portfolio {...} :expected-outputs-satisfied? bool}` (checks fixture expected-output fact types all present, in order).
  - CLI entry: `basilisp run -n stevetrading.base.engine-replay -- --fixture ... --out ...` via `-main`.
- [ ] Golden tests `tests/e2e/test_replay_golden.lpy`:
  - **Happy path:** run over `simple-paper-session-v0.2.edn` → `:expected-outputs-satisfied? true`; fact log contains the full §10.2 lineage chain with correct correlation/causation ids.
  - **Replay determinism:** two runs into different out-dirs → identical ordered list of `[fact-type order-intent-id]` pairs and `=` final portfolio.
  - **Restart convergence:** run once uninterrupted; run again stopping after every K facts (rebuild engine via `run-recovery!` from snapshot+facts, then continue) → identical final state and NO duplicate order intents (golden property TESTING §8.1–8.2).

**REPL checkpoints:**
- `(run-replay {...})` → summary with `:expected-outputs-satisfied? true`
- `(facts-by fs {:order-intent-id <id>})` → complete lineage chain (intent → dispatched → ack → fill)

**Narrow test:** `scripts/test.sh tests/e2e/test_replay_golden.lpy`

## Phase 9: Options Execution Path

Goal: multi-leg instruments end to end. Normative: CANONICAL_SCHEMAS §11.3/§12.3, BROKER_ADAPTER §5.3, LEDGER §5.

- [ ] Extend `execution.core`: policy `:execution/vertical-credit-spread-v1` — two-leg intent (sell near strike, buy far strike, same expiry, both puts or calls; legs canonically sorted; net-credit limit price); policy `:execution/iron-condor-v1` — 4-leg (put spread + call spread) single intent.
- [ ] Extend `broker.sim`: per-leg fills for multi-leg intents (one `:fact/fill-observed` per leg sharing broker-order-id, leg-identified by `:fill/instrument-id`); per-leg marks for pricing.
- [ ] Extend `ledger.core`/`portfolio.core` where needed: per-leg lots keyed by instrument-id (short legs = negative qty lots); spread P&L nets across legs (likely already works — prove with tests).
- [ ] Strategy `strategy/simple-vol/credit-spread/v1` (data at `resources/strategies/simple-vol-credit-spread-v1.edn`): consumes `:fact/option-chain-observed`; feature `:feature/chain-mid-width` (mid of spread credit from chain quotes); signal: enter spread when credit ≥ threshold param, flatten at session end; risk policy `:risk/defined-risk-spread` (max 1 spread, max width × qty risk cap); inference: `:model.type/threshold` model artifact.
- [ ] Fixture `resources/fixtures/replay/options-session-v0.1.edn`: bars + 2 chain snapshots (entry-attractive then exit), expected outputs covering 2-leg intent lifecycle.
- [ ] Tests `tests/options/test_spread_e2e.lpy` — leg ordering: same legs in different declaration order → same `order-intent-id`; different leg set → different id; replay of options fixture → spread opened (2 lots, one short one long) and flattened; portfolio nets to zero position with realized P&L = credit − debit − fees; 4-leg iron-condor intent builds with 4 canonical legs and round-trips the sim broker.

**REPL checkpoints:**
- build spread plan from sample chain → intent with 2 sorted legs; shuffle input leg order → identical intent id
- options fixture replay summary → `:expected-outputs-satisfied? true`

**Narrow test:** `scripts/test.sh tests/options/`

## Phase 10: Control Plane, Observability, Alpaca Adapter, Live Base

Goal: operational boundary + paper-capable assembly. Normative: CONTROL_PLANE_MANIFESTS (whole doc), OBSERVABILITY (whole doc), BROKER_ADAPTER (whole doc), ADR-0005.

- [ ] `components/control-plane.protocol/src/stevetrading/control_plane/protocol.lpy` (new): manifest schema fns — `validate-manifest` (structural §9.1: required fields, malformed/duplicate ids, unknown enums, dangling refs; safety §9.2: live strategies on non-live accounts, paper→live-only accounts, strategies with no route, process mode mismatches; policy §9.3: artifact compat warnings) → `{:valid? bool :errors [...] :warnings [...]}`; `kill-switch-active?` (scope matching: global/process/strategy/account).
- [ ] `components/control-plane.file-store/src/stevetrading/control_plane/file_store.lpy` (new): revisions under `<root>/revisions/<rev-id>.edn` (immutable — write refuses overwrite), activation records `<root>/activations/<rev-id>.edn`, `active.edn` pointer per deployment scope; implements `persistence.protocol/ControlPlaneStore` + `activate!` (validate → write activation → flip pointer atomically).
- [ ] `bases/control-plane/src/stevetrading/base/control_plane.lpy` (extend stub): `-main` with subcommands `validate <manifest.edn>`, `activate <manifest.edn> --root <dir>`, `show --root <dir>`; exit 1 on invalid; prints structured results.
- [ ] `components/observability.protocol/src/stevetrading/observability/protocol.lpy` (new): `defprotocol AuditSink` — `(emit-audit! [this event])`, `(emit-metric! [this metric])`, `(health-view [this])`. Audit event minimum fields per OBSERVABILITY §4.1.
- [ ] `components/observability.structured-log/src/stevetrading/observability/structured_log.lpy` (new): JSON-lines sink (python `json` interop; keywords → `"ns/name"` strings) to a file or stdout; in-memory ring buffer for `health-view`; engine integration: every appended fact of an audit-relevant type also emits an audit event (decision, order, recovery, lifecycle, degradation, fault).
- [ ] `components/broker.alpaca/src/stevetrading/broker/alpaca.lpy` (new): implements `broker.protocol/Broker` for Alpaca paper REST:
  - `make-alpaca-broker {:base-url ... :key-id ... :secret ... :transport (fn [req] resp)}` — transport defaults to a stdlib `urllib.request` POST/GET/DELETE wrapper; **all tests inject a stub transport**; never call the real API in tests.
  - submit: canonical intent → Alpaca order JSON (single-leg equity: symbol/qty/side/type/time_in_force/limit_price; multi-leg options: `order_class: "mleg"` + legs array with OCC symbols built from instrument-id — OCC format: `SPY260619C00550000`, derive from `domain.instruments/parse-instrument-id`); `client_order_id` = `(alpaca-client-order-id order-intent-id)` for idempotency per §9.1.
  - `alpaca-client-order-id` — deterministic pure fn: `(subs order-intent-id 0 48)` (Alpaca's client_order_id limit is 48 chars; `oi_` + first 45 hex chars = 183 bits, collision-negligible). **Recovery lineage rule:** reconciliation maps broker-returned orders back to intents by recomputing `alpaca-client-order-id` for every unresolved intent and matching on it — no extra durable mapping store is needed because the short id is a pure function of the full id. Guard: if two unresolved intents ever share a short id, emit a reconciliation anomaly fact and treat both as `orphaned-needs-reconcile` (never guess).
  - normalize responses/errors → canonical facts per §5 (ack-accepted with broker order id; rejected with normalized `:broker/rejection-code` from §10 categories; HTTP/transport errors → `:fact/fault-recorded` with fault category, NEVER raw exceptions across the boundary).
  - `open-orders`/`fills-since` (GET /v2/orders?status=open, GET /v2/orders?after=cursor + activities) → normalized status/fill facts for reconciliation per §8.
  - Reference for request/response shapes: the Python system's proven adapter `~/contracting/upwork/steven-tran/SteveTrading/ref/Data-Preprocessor/src/stevetrading_v2/brokers/alpaca_paper_broker.py` (read it; transcribe shapes, not structure).
- [ ] `bases/engine-live/src/stevetrading/base/engine_live.lpy` (extend stub): `run-live` — control-plane gate FIRST (load active revision; validate own process id + routes; **refuse to start** on any blocking violation or active kill switch, emitting `:fact/control-plane-violation-recorded`); wire chosen broker (`:broker/alpaca-paper` or `:broker/sim` from manifest route) + market data source + stores + observability; same engine loop as replay base (shared loop fn extracted to `engine.commands` or a small `engine.loop` ns — replay and live MUST share the loop per POLYLITH §10.5); `-main` reads `--control-plane-root`, `--process-id`, `--out-dir`.
  - **Market-data scope (explicit deferral):** NO live market-data adapter is built in this spec. `engine-live`'s market-data source is injected and, in this spec, is always the replay source (`market-data.replay`) — the wiring point is the seam where a future `market-data.alpaca`/`market-data.thetadata` adapter plugs in. The deferral exists because live feeds need credentials/terminals owned by the operator and parity validation against the Python system is post-spec operator work. `market-data.polygon` from the architecture component list is NOT created in this spec; document the deferral in the base README section of the repo README (Phase 11).
- [ ] Tests:
  - `tests/control_plane/test_validation.lpy` — happy manifest (port `resources/control-plane/examples/paper-main-v0.1.edn`) valid; each §9.1/§9.2 rejection case; kill-switch scope matching; activation immutability (re-activate same rev-id refuses).
  - `tests/broker/test_alpaca.lpy` — stub-transport contract tests: submit single-leg → correct request shape + ack normalization; multi-leg OCC symbols; rejection (403 insufficient buying power JSON) → `:broker-rejection/insufficient-buying-power`; transport exception → fault fact; duplicate submit reuses client_order_id; open-orders/fills-since normalization.
  - `tests/e2e/test_live_gate.lpy` — engine-live with violating manifest refuses startup; with valid manifest + sim route runs the v0.2 fixture session end to end (live base, sim adapters).

**REPL checkpoints:**
- `(validate-manifest (edn/read-string (slurp "resources/control-plane/examples/paper-main-v0.1.edn")))` → `{:valid? true}`
- alpaca submit with stub transport returning canned ack JSON → `:fact/broker-ack-accepted` with `:broker/order-id` from the canned response
- engine-live with kill-switch-active manifest → startup refusal value (no trading loop entered)

**Narrow test:** `scripts/test.sh tests/control_plane/ tests/broker/test_alpaca.lpy tests/e2e/test_live_gate.lpy`

## Phase 11: Recovery Validation Suite + Reports + Doc Sync

Goal: prove the golden properties; close the loop. Normative: ENGINE_STATE_AND_RECOVERY §17, TESTING §7–8.

- [ ] `tests/recovery/test_crash_scenarios.lpy` — the 7 acceptance scenarios as deterministic tests using the replay base with injected crash points (crash = stop loop, drop in-memory state, `run-recovery!` from disk, continue):
  1. crash after `order-intent-created`, before submit dispatch → recovery resubmits exactly once (submit-dedupe proves not-yet-accepted)
  2. crash after dispatch, before ack handling → reconciliation via broker `open-orders`/`fills-since` resolves without duplicate submit
  3. crash after ack, before fill → fill recovered via reconciliation
  4. crash after fill, before snapshot → fact replay restores; no duplicate fill on re-poll
  5. duplicate broker status/fill replay after restart → state converges, single lot
  6. replayed recovery converges to uninterrupted-run state (`=` on final state minus run metadata)
  7. unresolved-order ambiguity (broker returns unknown-lineage fill) → `:blocked`, no exposure change
- [ ] `tests/recovery/test_golden_properties.lpy` — TESTING §8: one logical decision → one stable intent id (across replay + restart); duplicate observations never duplicate fills/positions; replay and live-normalized inputs share fact shapes (validate replay facts against the same `validate-fact` used by live adapters); control-plane violation prevents startup.
- [ ] `bases/reports/src/stevetrading/base/reports.lpy` (extend stub): `-main --facts <db> --out <dir>`: daily summary from the fact store — orders submitted/filled/cancelled/rejected, fills with prices, realized P&L per strategy/account (via ledger fold), recovery events, faults; writes `summary.edn` + human-readable `summary.md`.
- [ ] `tests/reports/test_reports.lpy` — summary over a completed replay session: counts match fact log; P&L matches portfolio derivation.
- [ ] Repo `README.md`: rewrite for implemented reality — quick start (venv, scripts, replay a fixture, run tests), workspace map, operator notes (how to run engine-live against sim; what's required before real paper use: operator-run live smoke + control-plane activation).
- [ ] `development/README.md`: REPL workflow (nrepl.sh, clj-nrepl-eval, sys.path note).

## Phase 12: Doc Sync

- [ ] Update `NORTHSTAR.md`: append a `## Status` section marking the build-order items 1–10 with their state after this spec (1–9 complete with commit SHAs; 10 partial: parity vs Python = future operator work) — keep the rest of the doc untouched (it is direction, not status).
- [ ] Audit `docs/adr/README.md` — note implementation landed; ADRs unchanged (they recorded decisions; the implementation conformed).
- [ ] Update spec `README.md` Implementation Status with per-phase commit SHAs; add `### Observations` section (what surprised, what deviated).
- [ ] Regenerate spec index: `python3 ~/.claude/skills/feature-specs/scripts/index.py ./specs`
- [ ] Commit: `docs(specs): sync docs after basilisp-rewrite`

## Verification (cross-phase)

- Full gate: `scripts/lint.sh && scripts/test.sh` green at every phase boundary (preflight gate before completion).
- The golden invariant trio to spot-check at any point: (1) replay twice → same intent ids; (2) fold duplicate fact → `=` state; (3) restart mid-session → converged final state.

## Rollback

Each phase is one or more commits on `feature/basilisp-rewrite`; revert by commit. No external systems are touched (no remote, no live APIs), so rollback is purely local git.
