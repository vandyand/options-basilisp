# Tests

This directory exists to support Basilisp and Pytest discovery at the repository root.

Component-local tests may still live with their owning components, but root-level integration,
replay, and contract tests should land here first.

Run tests through the repo wrapper:

```bash
scripts/test.sh
scripts/test.sh tests/broker/test_sim.lpy
```

Avoid raw `python -m pytest` for normal Basilisp work; it can pick up a
different environment than `.venv/bin/basilisp test`.

On deployed Hetzner releases, the wrapper auto-loads `/etc/stevetrading/env`
when the release-local `.venv/bin/basilisp` path is absent, so direct
`scripts/test.sh ...` commands use the shared runtime virtualenv.

Use targeted loops during development:

```bash
scripts/test.sh inner
scripts/test.sh fast
scripts/test.sh changed --durations=20
scripts/test.sh scope scripts/market_evidence_status.lpy -- --durations=20
scripts/test.sh map components/feature-parity.core/src/stevetrading/feature_parity/core.lpy
scripts/test.sh capture --durations=20
scripts/test.sh theta-core --durations=20
scripts/test.sh theta-smoke --durations=20
scripts/test.sh market-evidence-core --durations=20
scripts/test.sh market-evidence-smoke --durations=20
scripts/test.sh market-evidence-deploy --durations=20
scripts/test.sh parity-smoke --durations=20
scripts/test.sh parity --durations=20
scripts/test.sh status --durations=20
scripts/test.sh reports --durations=20
scripts/test.sh ops tests/ops/test_market_evidence_manifest_smoke.lpy::market-evidence-manifest-includes-optional-diagnostics-when-present
scripts/test.sh full
```

Mode guide:

- `inner`: fastest deterministic edit loop; runs a curated sentinel set for core units and avoids ops/e2e/process-heavy checks.
- `fast`: all non-ops, non-slow tests; use this as the normal edit loop.
- `changed`: infer a compact target list from changed source/script/test files; use this before widening to subsystem gates.
- `scope`: infer tests from explicitly named files; use this instead of `changed` when the worktree is broad or dirty.
- `map`: print the test targets inferred from explicitly named files without running them.
- `capture`: Steve v2 live feature-capture writer and sidecar integrity checks.
- `theta-core`: fast in-process ThetaData adapter/schema/payload tests.
- `theta-smoke`: broader ThetaData adapter/schema/payload tests including CLI process-boundary checks.
- `market-evidence-core`: narrow readiness and collection sentinels for artifact-contract edits.
- `market-evidence-smoke`: broader readiness, manifest, status, and collection workflow contract tests, excluding tests marked `slow`.
- `market-evidence-deploy`: slower market-evidence deploy gate, including the full manifest-generation workflow and other `slow` market-evidence tests.
- `parity-smoke`: feature-parity and Steve-v2 capture-writer sentinels for the normal parity edit loop; run this before the broader `parity` gate.
- `parity`: feature-parity, non-fuzz ThetaData schema, capture, and market-evidence smoke tests, excluding `slow`.
- `status`: status dashboard contracts and publication audits.
- `reports`: daily/weekly/account report generation, metrics, and report validation CLI contracts.
- `ops`: operational scripts/workflows only; pass files or `::test_name` to keep this atomic.
- `full`: the entire suite; reserve for deploy gates or broad refactors.

Default escalation path for feature-parity work:

```bash
scripts/test.sh changed
scripts/test.sh inner
scripts/test.sh capture
scripts/test.sh theta-core
scripts/test.sh market-evidence-core
scripts/test.sh parity-smoke
scripts/test.sh theta-smoke
scripts/test.sh market-evidence-smoke
scripts/test.sh parity
scripts/test.sh market-evidence-deploy
```

Stop at the smallest failing command while iterating. Only move rightward when
the edit touches that layer or when preparing to deploy.

For market-evidence orchestrator edits, `changed` and `scope` intentionally map
`scripts/collect_market_evidence.sh` to a compact sentinel set. Use
`market-evidence-smoke` or `market-evidence-deploy` when validating the full
workflow contract.

For very large dirty trees, scope `changed` to the file you are actively editing:

```bash
STEVE_TEST_CHANGED_FILES=components/feature-parity.core/src/stevetrading/feature_parity/core.lpy scripts/test.sh changed --durations=20
scripts/test.sh scope components/feature-parity.core/src/stevetrading/feature_parity/core.lpy -- --durations=20
```

When a loop feels slow, add `--durations=20` to the targeted mode rather than
switching to `full`. The curated modes keep their test selections when pytest
flags are passed, so `scripts/test.sh parity-smoke --durations=20` still runs
the smoke set rather than accidentally widening to the full suite.
