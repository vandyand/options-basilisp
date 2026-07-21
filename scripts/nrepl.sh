#!/usr/bin/env bash
# (Re)start the Basilisp nREPL server on port 36915 with all workspace src
# dirs on PYTHONPATH. Regenerates .nrepl-pythonpath so restarts pick up any
# newly created component/base src dirs.
set -euo pipefail
REPO="${STEVE_REPO_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
BASILISP="${BASILISP_BIN:-$REPO/.venv/bin/basilisp}"
cd "$REPO"
export STEVE_REPO_ROOT="$REPO"

PORT=36915

# Kill any existing nrepl-server on this port.
pkill -f "nrepl-server --port ${PORT}" 2>/dev/null || true
sleep 1

# Regenerate the PYTHONPATH manifest from the actual workspace layout.
ls -d components/*/src bases/*/src | paste -sd: - > .nrepl-pythonpath

PYTHONPATH=$(cat .nrepl-pythonpath) nohup "$BASILISP" nrepl-server --port "${PORT}" \
  > /tmp/basilisp-nrepl.log 2>&1 &

echo "nREPL starting on port ${PORT} (log: /tmp/basilisp-nrepl.log)"
