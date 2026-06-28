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
