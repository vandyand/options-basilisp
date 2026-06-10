#!/usr/bin/env bash
# (Re)start the Basilisp nREPL server on port 36915 with all workspace src
# dirs on PYTHONPATH. Regenerates .nrepl-pythonpath so restarts pick up any
# newly created component/base src dirs.
set -euo pipefail
cd "$(dirname "$0")/.."

PORT=36915

# Kill any existing nrepl-server on this port.
pkill -f "basilisp nrepl-server --port ${PORT}" 2>/dev/null || true
sleep 1

# Regenerate the PYTHONPATH manifest from the actual workspace layout.
ls -d components/*/src bases/*/src | paste -sd: - > .nrepl-pythonpath

PYTHONPATH=$(cat .nrepl-pythonpath) nohup .venv/bin/basilisp nrepl-server --port "${PORT}" \
  > /tmp/basilisp-nrepl.log 2>&1 &

echo "nREPL starting on port ${PORT} (log: /tmp/basilisp-nrepl.log)"
