#!/usr/bin/env bash
# Run the Basilisp test suite (pytest wrapper) from the repo root.
# Usage: scripts/test.sh [pytest-args...]
set -euo pipefail
cd "$(dirname "$0")/.."
exec .venv/bin/basilisp test "$@"
