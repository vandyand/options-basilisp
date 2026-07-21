#!/usr/bin/env bash
# Lint gate: compile-check every namespace, then enforce dependency direction.
# Exit code propagates from the first failing check.
set -euo pipefail
REPO="${STEVE_REPO_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
BASILISP="${BASILISP_BIN:-$REPO/.venv/bin/basilisp}"
cd "$REPO"
export STEVE_REPO_ROOT="$REPO"
"$BASILISP" run scripts/compile_check.lpy
"$BASILISP" run scripts/check_deps.lpy
