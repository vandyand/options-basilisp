# StevenTrading — Basilisp Rewrite

A ground-up rewrite of the StevenTrading Python system in
[Basilisp](https://basilisp.readthedocs.io/) (Clojure on Python), built as a
Polylith-style modular monolith around an append-only **fact ledger**:
every market observation, decision, order, fill, and recovery event is a
canonical fact; engine state is a pure fold over the log; order-intent
identity is deterministic and content-addressed, so replays, restarts, and
broker reconciliation all converge on the same truth.

Direction lives in [NORTHSTAR.md](NORTHSTAR.md). The normative architecture
package is `docs/architecture/` (15 documents); irreversible decisions are
recorded in `docs/adr/`. The implementation spec and phase plan are under
`specs/basilisp-rewrite/`.

## Quick Start

Requirements: Python 3.12.

```bash
# 1. environment
python3 -m venv .venv
.venv/bin/pip install -e .          # basilisp, python-ulid (pytest for tests)

# 2. gates
scripts/lint.sh    # compile check + dependency-direction check
scripts/test.sh    # full test suite (~4 min); narrow: scripts/test.sh tests/<area>/

# 3. replay a fixture session end to end (SQLite fact log + snapshots
#    + summary printed to stdout)
.venv/bin/basilisp run -n stevetrading.base.engine-replay -- \
  --fixture resources/fixtures/replay/simple-paper-session-v0.2.edn \
  --out /tmp/replay-out

# 4. report over the session's fact log
.venv/bin/basilisp run -n stevetrading.base.reports -- \
  --facts /tmp/replay-out/facts.db --out /tmp/replay-report
```

Re-running step 3 on the same `--out` dir resumes via recovery
(snapshot + fact replay) — interrupting it mid-session and re-running is the
designed restart path, not an error.

For REPL-driven development see [development/README.md](development/README.md).

## Workspace Map

Polylith layout: `components/` hold all logic, `bases/` are thin imperative
shells that wire adapters around the shared engine loop, and dependency
direction is enforced by `scripts/check_deps.py` (core never imports
adapters; protocols are importable by anyone).

| Area | Bricks |
|---|---|
| Domain core | `domain.identifiers`, `domain.instruments`, `domain.enums`, `domain.schemas` (canonical envelopes + deterministic decision/order-intent ids), `domain.validation` |
| Engine kernel | `engine.state`, `engine.machines` (4 state machines as data), `engine.fold` (pure fact fold), `engine.commands`, `engine.loop` (THE shared cycle), `engine.recovery` (planner + executor) |
| Money | `ledger.core` (derive/fold split, FIFO lots, deterministic dedupe keys), `portfolio.core` (derived views) |
| Strategy pipeline | `strategy.registry`, `feature.core`, `inference.core`, `signal.core`, `risk.core`, `execution.core` (equity market orders + multi-leg options spreads), `artifact.protocol`/`artifact.file-store` |
| Adapters | `broker.protocol`, `broker.sim` (deterministic simulator), `broker.alpaca` (paper REST, stub-transport tested), `market-data.protocol`, `market-data.replay`, `replay.fixture`, `persistence.fact-store` (SQLite), `persistence.snapshot-store`, `control-plane.protocol`/`control-plane.file-store`, `observability.protocol`/`observability.structured-log` |
| Bases | `engine-replay` (fixture sessions), `engine-live` (control-plane-gated live/paper/sim assembly), `control-plane` (validate/activate/show CLI), `reports` (fact-log summaries), `dev` |
| Tests | `tests/` by area; `tests/recovery/` is the ENGINE_STATE_AND_RECOVERY §17 crash-scenario acceptance suite; `tests/e2e/` golden replay + live-gate sessions |

## What the Test Suite Proves

The recovery validation suite (`tests/recovery/`) runs the seven §17
acceptance scenarios as deterministic tests — a crash is injected
after/before a precise fact append, in-memory state dropped, recovery runs
from disk, the session continues, and the result is compared against an
uninterrupted control run:

1. crash after `order-intent-created` before submit → exactly one submit
2. crash after dispatch before ack persisted (broker HAS the order) →
   reconciliation restores ack/fill, never resubmits
3. crash after ack before fill → fill recovered via reconciliation
4. crash after fill before snapshot → recovered portfolio equals the
   uninterrupted run's (rebuilt from ledger facts, never stale)
5. duplicate broker status/fill replay after restart → converges, one lot
6. crash anywhere + resume → identical final state (normalized)
7. unknown-lineage fill → recovery `:blocked`, zero exposure change

plus the TESTING §8 golden properties (stable intent ids across
replay+restart, duplicate observations never duplicate exposure, one
`validate-fact` for replay/sim/alpaca-normalized facts, control-plane
violations prevent startup).

## Operator Notes

### Running engine-live against the sim route

```bash
# activate the example sim manifest into a control-plane root
.venv/bin/basilisp run -n stevetrading.base.control-plane -- \
  activate resources/control-plane/examples/sim-main-v0.1.edn --root /tmp/cp-root

# start the live base (sim broker route, replay market data)
.venv/bin/basilisp run -n stevetrading.base.engine-live -- \
  --control-plane-root /tmp/cp-root --process-id engine-sim-main \
  --out /tmp/live-out \
  --fixture resources/fixtures/replay/simple-paper-session-v0.2.edn
```

The live base refuses to start on any control-plane violation (unknown
process, kill switch, bad routes, artifact mismatch), durably recording
`:fact/control-plane-violation-recorded`.

### Before real paper use (explicitly deferred, operator-owned)

This spec ships **no live market-data adapter**: `engine-live`'s source is
injected and is always the replay fixture source. Pairing a replay feed with
a real broker is blocked by the stale-feed safety gate
(`:violation/replay-feed-with-real-broker`) unless `--allow-replay-feed` is
passed (tests only, with a stub transport). Before any real Alpaca paper
session an operator must:

1. build/wire a live market-data adapter at the `market-data.protocol` seam
   (`market-data.polygon` is a stub placeholder; thetadata/alpaca candidates)
2. author + `activate` a real paper manifest (accounts, routes, process ids)
   through the control-plane base
3. run an operator-supervised live smoke with real Alpaca paper credentials
   (the `broker.alpaca` adapter is fully stub-transport tested but has never
   made a network call from this repo)
4. validate parity against the Python system (post-spec work)

## Documents

- [NORTHSTAR.md](NORTHSTAR.md) — direction, hard centers, build order
- `docs/architecture/` — normative package (schemas, state machines,
  recovery, broker/market-data contracts, persistence, control plane,
  observability, testing strategy, Polylith layout)
- `docs/adr/` — ADR-0001..0005 (Polylith monolith, append-only fact ledger,
  deterministic intent identity, snapshot+replay+reconciliation recovery,
  control plane as data)
- `specs/basilisp-rewrite/` — implementation spec, research, phased plan
