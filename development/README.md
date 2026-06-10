# Development — REPL Workflow

This workspace is REPL-first: verify shapes and behavior live before (and
after) editing files.

## Starting the nREPL

```bash
scripts/nrepl.sh
```

Kills any server on port 36915, regenerates `.nrepl-pythonpath` from the
actual `components/*/src` + `bases/*/src` layout, and starts a fresh
`basilisp nrepl-server` in the background (log: `/tmp/basilisp-nrepl.log`).

Evaluate forms with `clj-nrepl-eval` or any nREPL client:

```bash
clj-nrepl-eval -p 36915 "(require '[stevetrading.engine.state :as st]) (st/fresh-state)"
```

## sys.path and new bricks

The server's import path is frozen at start time from `.nrepl-pythonpath`.
When you create a NEW component/base src dir mid-session, either restart
via `scripts/nrepl.sh` or append the path live:

```clojure
(import sys importlib)
(.append (.-path sys) "components/<name>/src")
(importlib/invalidate_caches)   ;; required after creating new dirs/files
```

Also add the new src dir to `pyproject.toml`
`[tool.pytest.ini_options].pythonpath` (most are pre-listed — check first)
and re-run `scripts/nrepl.sh` so `.nrepl-pythonpath` includes it for the
next restart.

After editing an existing file, `(require 'the.ns :reload)` to pick up the
change.

## Tests

```bash
scripts/test.sh                       # full suite (~4 min)
scripts/test.sh tests/engine/         # narrow, per area
scripts/test.sh tests/recovery/test_crash_scenarios.lpy
scripts/lint.sh                       # compile check + dependency direction
```

Test layout conventions (Phase 0 findings — do not regress):

- test namespaces are relative to `tests/`: file
  `tests/domain/test_schemas.lpy` declares `(ns domain.test-schemas)`
- `tests/` has **no `__init__.py`** anywhere and `"tests"` is on the pytest
  `pythonpath` — adding `__init__.py` breaks the basilisp testrunner's
  ns/path matching
- shared test code lives in helper namespaces under `tests/` (e.g.
  `tests/helpers/recovery_helpers.lpy` → `(ns helpers.recovery-helpers)`),
  requirable from any test ns
- side-effecting calls belong in `let` bindings, not inside `is` —
  `basilisp.test`'s `is` can evaluate its form more than once

## Interop reminders (verified at the REPL)

- `(import hashlib)` then `(hashlib/sha256 ...)`; class attrs via
  `(.-attr obj)`; `module.submodule/fn` works (`datetime.datetime/now`)
- dotted symbols in operator position are a compile error
- KNOWN BASILISP BUG: `[& {:keys ...}]` kwargs destructuring breaks when
  the last kwarg value is a map — use explicit opts maps everywhere
- Python kwargs in interop calls use `**`:
  `(os/makedirs dir ** :exist_ok true)`
