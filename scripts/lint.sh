#!/usr/bin/env bash
# Lint gate: compile-check every namespace, then enforce dependency direction.
# Exit code propagates from the first failing check.
set -euo pipefail
cd "$(dirname "$0")/.."
.venv/bin/python scripts/compile_check.py
.venv/bin/python scripts/check_deps.py
