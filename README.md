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

Use this path for a fresh local development checkout. It does not require
Alpaca credentials, ThetaData, or a VPS.

Requirements:

- Python 3.12 recommended. The package metadata allows `>=3.10`, but current
  development and VPS runtime use Python 3.12.
- Bash plus standard Unix tooling.
- SQLite is used by the fact store and durable sim broker.

```bash
# 1. environment
python3 -m venv .venv
.venv/bin/pip install -U pip
.venv/bin/pip install -e .

# 2. gates
scripts/lint.sh    # compile check + dependency-direction check
scripts/test.sh    # full suite; narrow: scripts/test.sh tests/<area>/

# 3. replay a fixture session end to end (SQLite fact log + snapshots
#    + summary printed to stdout)
.venv/bin/basilisp run -n stevetrading.base.engine-replay -- \
  --fixture resources/fixtures/replay/simple-paper-session-v0.2.edn \
  --out /tmp/replay-out

# 4. report over the session's fact log
.venv/bin/basilisp run -n stevetrading.base.reports -- \
  --facts /tmp/replay-out/facts.db --out /tmp/replay-report
```

Re-running the replay command against the same `--out` dir resumes via
snapshot + fact replay. Interrupting and re-running is the designed restart
path, not an error.

## Daily Development Loop

Most work should use these commands:

```bash
# fast feedback for a topic
scripts/test.sh tests/broker/test_sim.lpy
scripts/test.sh tests/e2e/test_live_gate.lpy

# full confidence before committing
scripts/lint.sh
scripts/test.sh

# current local git state
git status --short
```

Use `scripts/test.sh`, not raw `python -m pytest`, for Basilisp tests. The
wrapper runs the pinned repo environment and avoids stale importer/cache issues.
The full suite is currently hundreds of tests and can take several minutes.

For REPL-driven development see [development/README.md](development/README.md).

## Common Workflows

### Sim Replay

Use `engine-replay` when you want deterministic behavior over fixture data:

```bash
.venv/bin/basilisp run -n stevetrading.base.engine-replay -- \
  --fixture resources/fixtures/replay/simple-paper-session-v0.2.edn \
  --out /tmp/replay-out
```

### Control-Plane Sim Session

Use `engine-live` with a replay fixture and sim broker when you want the live
base wiring, control-plane gates, broker commands, and persistence without real
external services:

```bash
.venv/bin/basilisp run -n stevetrading.base.control-plane -- \
  activate resources/control-plane/examples/sim-main-v0.1.edn --root /tmp/cp-root

.venv/bin/basilisp run -n stevetrading.base.engine-live -- \
  --control-plane-root /tmp/cp-root \
  --process-id engine-sim-main \
  --out-dir /tmp/live-sim-out \
  --fixture resources/fixtures/replay/simple-paper-session-v0.2.edn
```

The live base refuses to start on any control-plane violation and records the
refusal as a canonical fact.

### Durable Sim Broker

The sim broker can persist broker state to SQLite via `:store-path`. The live
launchers use `sim-broker.db` under the session directory, so a restarted sim
broker can answer open orders, fills, account state, and option settlements.

Useful status helpers:

```bash
.venv/bin/basilisp run scripts/sim_broker_status.lpy
SIM_STORE_PATH=live_runtime/<session>/sim-broker.db \
  .venv/bin/basilisp run scripts/current_sim_account_state.lpy
```

### Live Paper / VPS Ops

Production paper-trading ops live in the `projects/ops` projection.

- `projects/ops/scripts/deploy_live_vps.sh` deploys a release to Hetzner.
- `projects/ops/scripts/systemd/` contains canonical unit/timer files.
- `projects/ops/docs/live-vps-rollout.md` is the VPS rollout runbook.

Do not edit `/opt/stevetrading/current` directly on the VPS. Deploy a release,
run preflight, then promote. During market hours, do not restart live services
unless explicitly doing an incident fix.

### Analysis And Fill Calibration

Offline analysis is read-only against copied or local `facts.db` files:

```bash
.venv/bin/basilisp run scripts/export_live_tape.lpy -- \
  --facts live_runtime/<session>/facts.db \
  --out /tmp/live-tape.csv

.venv/bin/basilisp run scripts/calibrate_sim_fills.lpy -- \
  --facts live_runtime/<session>/facts.db \
  --out /tmp/sim-fill-calibration.edn
```

See `projects/ops/docs/analysis-and-sim-fill-calibration.md`.

## Workspace Map

Polylith layout: `components/` hold all logic, `bases/` are thin imperative
shells that wire adapters around the shared engine loop, and dependency
direction is enforced by `scripts/check_deps.lpy` (core never imports
adapters; protocols are importable by anyone).

| Area | Bricks |
|---|---|
| Domain core | `domain.identifiers`, `domain.instruments`, `domain.enums`, `domain.schemas` (canonical envelopes + deterministic decision/order-intent ids), `domain.validation` |
| Engine kernel | `engine.state`, `engine.machines` (4 state machines as data), `engine.fold` (pure fact fold), `engine.commands`, `engine.loop` (THE shared cycle), `engine.recovery` (planner + executor) |
| Money | `ledger.core` (derive/fold split, FIFO lots, deterministic dedupe keys), `portfolio.core` (derived views) |
| Strategy pipeline | `strategy.registry`, `feature.core`, `inference.core`, `signal.core`, `risk.core`, `execution.core` (equity market orders + multi-leg options spreads), `artifact.protocol`/`artifact.file-store` |
| Adapters | `broker.protocol`, `broker.sim` (durable deterministic simulator), `broker.alpaca`, `broker.fanout`, `broker.router`, `market-data.protocol`, `market-data.replay`, `market-data.alpaca`, `market-data.thetadata`, `market-data.composite`, `replay.fixture`, `persistence.fact-store` (SQLite), `persistence.snapshot-store`, `control-plane.protocol`/`control-plane.file-store`, `observability.protocol`/`observability.structured-log` |
| Bases | `engine-replay` (fixture sessions), `engine-live` (control-plane-gated live/paper/sim assembly), `control-plane` (validate/activate/show CLI), `reports` (fact-log summaries), `dev` |
| Projects | `projects/ops` (hosting/deployment/systemd/report service), plus projection stubs for live, replay, reports, control-plane, and tests |
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

## Operational Safety

Local development should default to replay and sim. Real Alpaca paper sessions
require operator-owned credentials, ThetaData access, active control-plane
manifests, and the VPS/systemd runtime described under `projects/ops`.

Broker target modes:

- `BROKER_TARGET=alpaca`: canonical Alpaca paper route.
- `BROKER_TARGET=sim`: replace Alpaca children with the shared durable sim broker.
- `BROKER_TARGET=both`: keep Alpaca canonical and mirror order intents into sim.

Never assume live paper is running because a process exists. Verify the systemd
timer, service status, import preflight, and advancing facts before market open.

## Documents

- [NORTHSTAR.md](NORTHSTAR.md) — direction, hard centers, build order
- `docs/architecture/` — normative package (schemas, state machines,
  recovery, broker/market-data contracts, persistence, control plane,
  observability, testing strategy, Polylith layout)
- `docs/adr/` — ADR-0001..0005 (Polylith monolith, append-only fact ledger,
  deterministic intent identity, snapshot+replay+reconciliation recovery,
  control plane as data)
- `projects/ops/` — hosting/deployment scripts, systemd units, and operator
  runbooks
- `specs/basilisp-rewrite/` — implementation spec, research, phased plan
