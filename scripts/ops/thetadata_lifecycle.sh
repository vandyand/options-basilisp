#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
exec "$ROOT/projects/ops/scripts/thetadata_lifecycle.sh" "$@"
