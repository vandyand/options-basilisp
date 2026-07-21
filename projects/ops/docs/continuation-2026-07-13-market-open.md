# Continuation Brief — 2026-07-13 Market Open

## How to use this document

This is the detailed working handoff for the Basilisp rewrite and the Monday
2026-07-13 market-open evidence run. It separates established facts, current
hypotheses, and planned evidence so a later session does not silently turn a
plausible inference into a conclusion.

The complete Codex transcript remains in the WSL session store as an audit
trail, but it is roughly 256 MB and mostly tool traffic and environment
details. This brief is the practical continuation context. The current
Windows worktree and the Hetzner VPS are authoritative whenever they disagree
with a historical conversation.

## Architecture and operating model

StevenTrading is being rebuilt as a Basilisp Polylith-style modular monolith,
not mechanically translated from the legacy Python system. The center is:

- canonical append-only facts instead of hidden mutable state;
- pure folds and deterministic replay;
- deterministic order-intent identity and intent -> acknowledgement -> fill
  lineage;
- strict market-data, broker, persistence, and control-plane protocols;
- control-plane validation before non-sim routes can start;
- snapshots as restart accelerators, not truth;
- thin imperative bases around a shared engine loop.

The goal is one coherent runtime model for live, paper, simulation, shadow,
and replay. Modes may vary at their adapters, but not in their conceptual
event, decision, persistence, and recovery model. `NORTHSTAR.md` and
`docs/architecture/` remain normative. The active branch is
`feature/basilisp-rewrite` at `a610e0b`; its large uncommitted change set is
the intended Basilisp/parity migration work and must not be discarded as noise.

## Why parity is the immediate focus

Several questions had been compressed into the word "parity". They need a
strict order:

1. Can native Basilisp reproduce the old Steve V2 tensor from identical
   captured inputs?
2. Did live and historical inputs represent the same market state, endpoint,
   venue, contract universe, and point-in-time selection rule?
3. Given comparable inputs, do predictions, signals, decisions, orders, and
   fills agree under replay/backtest and live/paper execution?
4. Is there enough matched, same-population evidence to make a statistical
   statement about a strategy?

The answers are not interchangeable. A tensor replay can prove implementation
reproducibility while saying nothing about the underlying market source. A
performance comparison can look compelling while being invalid because the
two populations observed different data. Raw source/provenance evidence must
therefore precede feature admission, model confidence, unmasking, and
same-population significance tests.

## Established results and their limits

### Native Steve V2 feature path

For a July 10 production tensor, native Basilisp reproduced `918/918`
features within `1e-4`, with maximum reported deviation `6.1e-5`. The key
compatibility work included TA smoothing, V3 array-to-scalar materialization,
and production-compatible SciPy Gaussian filtering.

That is strong evidence for the native implementation when given known
captured inputs. It is not proof that the captured input equals the historical
or backtest market-data population.

### Feature neutralization

Neutralization is a safety control, not a verdict that a feature is useless.
Prior work found feature families that were zero-filled, degenerate,
unproven, or unsafe under the available provenance evidence. The active Steve
V2 stack no longer has zero-filled or degenerate aggregate features, but still
has suspicious raw-price-level/nonstationary features that require explicit
remediation or acceptance based on prediction impact.

No neutralized feature may be unmasked merely because a replay test passes.
It needs a provenance-compatible raw cohort, native feature evidence, and its
applicable promotion gate.

### Reports, metrics, and Mission Control

Legacy reporting produced misleading carry-over, realized-PnL, trade-count,
and position views. That led to a decision to bring reports and metrics into
Basilisp/Polylith rather than keep patching disconnected Python scripts. The
worktree now contains reporting, report-metrics, status components, report
viewer work, and a status-dashboard/Mission Control direction.

Reports must be interpreted from durable facts: distinguish closed-trade PnL
from open/carry PnL, verify the session boundary, and inspect positions/fills
before treating derived statistics as decision-grade evidence. A report cannot
be more reliable than the lifecycle and market facts it consumes.

### Strategy classes have separate parity gates

- Steve V2 uses the legacy FeatureEngine, 918-feature tensors, model bundles,
  runtime neutralization, and a live Greeks-grid history.
- Vol/calendar/condor strategies depend on option-chain snapshots,
  strike/expiry selection, mid-price construction, and term/condor formulas.
- Local simple-bar simulations depend on source-bar completeness, warmup
  rules, deterministic signals, and bar replay.

Do not apply a Steve V2 tensor report to option-chain strategies, or treat a
bar replay as proof that an option-surface strategy saw the same market.

## Intraminute versus minute data: the forward decision

### The actual decision

The important question was not whether every strategy should run at tick
frequency. It was whether minute bars are sufficient as the system's
canonical evidence layer. They are not. The system needs event/snapshot-level
evidence to prove what a minute-cadenced strategy actually observed, while
retaining completed bars as explicit derived views for strategies that are
intentionally bar-based.

### What a completed minute bar can establish

ThetaData OHLC bars are labelled by their opening timestamp and include trades
in the following interval. A consumer must not act as if an in-progress minute
were final. Completed one-minute OHLCV bars are useful, compact inputs for
bar-defined strategies and are appropriate derived artifacts when their
provider, venue, timeframe, completion rule, and timestamp semantics are
preserved.

### What a minute bar cannot establish

Minute bars do not recreate a live option NBBO snapshot, contract universe,
quote/trade ordering, point-in-time observation watermark, sparse-event
carry-forward state, or whether a value came from a bid, ask, mid, trade,
bar close, or provider-specific field. They therefore cannot certify the
inputs of a Steve V2 model or option strategy that consumes current chain or
quote state.

### Why investigation shifted to intraminute data

The retained legacy logs were decision-level, not complete provider payloads.
A July 9 diagnostic found live option-chain density around 768 contracts per
minute versus about 80 in an old historical reconstruction. This demonstrates
a request-universe/representation mismatch; it does not show that ThetaData
lacks the contracts.

The GCS archive is useful intraminute diagnostic material but cannot certify
source identity by itself: it lacks original endpoint, venue, request
parameters, snapshot watermark, and selection-rule metadata. Legacy SPY
prices were broadly compatible with archive events, but option snapshot
cardinality could not match an event stream without an explicit carry-forward
and selection policy.

The governing direction is therefore:

1. Retain raw event and snapshot receipts first, with parameters, observation
   watermarks, normalized events, and hashes.
2. Build minute bars and other aggregates as provenance-labelled derived data.
3. Reconstruct option surfaces with a documented point-in-time and
   carry-forward policy; never equate an event stream with a snapshot.
4. Derive features/tensors only from an identified raw corpus and selection
   policy.

This permits minute-cadenced strategies. It prevents minute-level aggregates
from erasing the evidence required to audit or reproduce their decisions.

## Raw ThetaData parity contract

`resources/thetadata/raw-parity-v1.edn` defines the executable raw corpus
boundary. The current inventory covers option quotes, option trades, option
open interest, stock quotes/trades, and index prices. `nqb` and `utp_cta` are
explicitly distinct stock-source contracts, not interchangeable fallbacks.

The pipeline saves direct terminal response receipts, captures a bounded
event stream, creates a historical request manifest, fetches raw history, and
compares full contract identity plus timestamps. Same-millisecond duplicates
are matched as exact field multisets rather than occurrence order, avoiding a
false mismatch when a historical response reorders events.

Certification requires, among other gates:

- at least 60 matching UTC observations for the relevant study;
- exact completed-bar timestamp agreement and declared field tolerance;
- at least 99.5% exact option contract-universe coverage in both directions,
  with declared bid/ask tolerance;
- compatible V2 provenance and native Basilisp feature implementation;
- retained source-audit JSON, historical cohort JSON/NPZ, and hash-identified
  corpus manifest.

For option quotes, interval history cannot prove the selection of the live
snapshot by itself. The intended historical reconstruction is the `at_time`
quote endpoint with a stated observation time. Broad all-chain requests are
operationally unsafe; terminal probing established that bounded strike-range
requests are required.

## Monday 2026-07-13 responsibilities

### Hetzner owns capture and comparison

Do not duplicate these data jobs on Windows. The VPS currently owns:

| ET | Unit | Responsibility |
|---|---|---|
| 09:10 | `stevetrading-market-evidence-preflight.timer` | evidence prerequisites |
| 09:20 | `stevetrading-six.timer` | strategy-session start |
| 09:31 | `stevetrading-raw-thetadata-parity.timer` | raw snapshot probe |
| 09:32 | `stevetrading-thetadata-stream-capture.timer` | 900-second event stream |
| 09:45 | `stevetrading-market-evidence-capture-smoke.timer` | capture smoke |
| 09:50 | `stevetrading-raw-history-parity.timer` | historical fetch/match |
| 10:45 | `stevetrading-market-evidence-collect.timer` | broader collection |

The raw landing root is
`/opt/stevetrading/shared/thetadata-parity-v1`. The 09:50 runner refuses to
continue without a `CAPTURED` stream receipt and nonzero event count, then
builds the request manifest, saves raw historical responses, and writes the
comparison. Theta Terminal is expected to be inactive off-hours; it should be
observed during the scheduled sequence rather than manually launched.

### Former WSL-local jobs

The last session added two transient, one-shot user-systemd timers:

- 09:40: liveness observation during stream capture;
- 10:10: evidence observation after a local transfer.

They lived under `/run/user/...` and disappeared when WSL stopped. A separate
WSL crontab entry ran `pull_thetadata_parity.sh` at 10:00 on weekdays.

### What the 10:00 local pull does

The pull does not capture data, start a strategy, or affect the remote
matcher. It copies the VPS immutable landing root to local `D:` storage and
runs `verify_raw_parity_evidence.lpy`. That verifier marks a corpus `READY`
only when it has a captured receipt, a matching stream-event hash, comparison
counts/statuses, and every expected historical raw-response file.

It is useful for independent local retention and later offline source audit,
feature-cohort, and corpus-building work. It is not a Monday collection gate:
the VPS evidence is the primary result, the copy can legitimately still be
retrying at 10:10, and a local `PENDING` status is not automatically an
incident.

Current decision: Windows should install the 09:40 observational checkpoint.
The local transfer should remain optional until the native Windows storage and
transfer design are consciously chosen. A Windows 10:10 checkpoint should
report remote evidence separately from any local-copy state.

## Windows migration rules

Windows is now the active development environment. The Linux shell scripts
are specifications, not native PowerShell entrypoints. Windows Task Scheduler
may observe the VPS, save JSON results locally, pull immutable artifacts after
a transfer design is selected, and verify a local corpus. It must not start a
second ThetaData terminal, strategy session, raw snapshot, or stream capture.

Before Windows tasks use SSH, establish host trust by comparing the presented
VPS public host key with WSL's existing trusted identity and then updating
Windows `known_hosts`. Never disable host-key verification simply to make an
automated task run.

## Next evidence-driven sequence

1. Inspect remote receipts/comparison artifacts after Monday's scheduled run.
2. Classify each raw class as pass, fail, or inconclusive and name the cause:
   source, endpoint, venue, request universe, timestamp, or selection policy.
3. If source provenance is certified, admit a bounded cohort to the canonical
   feature corpus and run native-feature/replay checks against it.
4. Only then perform same-population statistical testing per strategy.
5. Continue the separate reporting/metrics, Mission Control, and
   strategy-specific parity initiatives without conflating them with source
   certification.

## Guardrails

- Never call an empty or absent artifact a parity pass.
- Never treat an option event stream as a live chain snapshot without a
  documented reconstruction policy.
- Never promote neutralized features on replay evidence alone.
- Do not change real/paper routing during this evidence run without an
  explicit operational decision.
- Decide local corpus path, retention, backup, and transfer mechanism before
  restoring the former 10:00 local pull as a Windows scheduled task.
