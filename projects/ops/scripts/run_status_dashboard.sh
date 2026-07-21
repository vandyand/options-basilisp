#!/usr/bin/env bash
# Rebuild the lightweight reports status dashboard.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

if [[ -f /etc/stevetrading/env \
      && -z "${BASILISP_BIN:-}" \
      && -z "${STEVE_REF_ROOT:-}" \
      && -z "${ANALYSIS_DIR:-}" ]]; then
  set -a
  # shellcheck disable=SC1091
  . /etc/stevetrading/env
  set +a
fi

REF_ROOT="${STEVE_REF_ROOT:-${REF_ROOT:-/opt/stevetrading/shared/Data-Preprocessor}}"

resolve_runner() {
  local env_value="$1"
  local repo_candidate="$2"
  local shared_candidate="$3"
  local path_name="$4"
  if [[ -n "$env_value" ]]; then
    printf '%s\n' "$env_value"
  elif [[ -x "$repo_candidate" ]]; then
    printf '%s\n' "$repo_candidate"
  elif [[ -x "$shared_candidate" ]]; then
    printf '%s\n' "$shared_candidate"
  elif command -v "$path_name" >/dev/null 2>&1; then
    command -v "$path_name"
  else
    printf '%s\n' "$repo_candidate"
  fi
}

cd "$REF_ROOT"
export STEVE_REPO_ROOT="${STEVE_REPO_ROOT:-$ROOT}"
export STEVETRADING_BASILISP_ROOT="${STEVETRADING_BASILISP_ROOT:-$ROOT}"
export STATUS_REMOTE_SSH="${STATUS_REMOTE_SSH:-}"
BASILISP="$(resolve_runner "${BASILISP_BIN:-}" "${ROOT}/.venv/bin/basilisp" "${REF_ROOT}/.venv/bin/basilisp" basilisp)"
STATUS_DIR="$REF_ROOT/report-viewer/public/reports/status"

ensure_accounts_nav_target() {
  local reports_dir="$REF_ROOT/report-viewer/public/reports"
  local singular="$reports_dir/account"
  local plural="$reports_dir/accounts"

  if [[ ! -d "$singular" ]]; then
    return 0
  fi
  if [[ -L "$plural" || -e "$plural" ]]; then
    return 0
  fi
  ln -s account "$plural"
}

sync_remote_facts_snapshot() {
  local remote="${STATUS_REMOTE_SSH:-}"
  if [[ -z "$remote" ]]; then
    return 0
  fi
  local target_date="${STATUS_TARGET_DATE:-$(TZ=America/New_York date +%F)}"
  local snapshot_dir="$ROOT/live_runtime/hetzner-snapshots"
  local remote_root="${STATUS_REMOTE_LIVE_RUNTIME:-/opt/stevetrading/shared/live_runtime}"
  local remote_paths
  if ! remote_paths="$(ssh -o BatchMode=yes -o ConnectTimeout=5 "$remote" \
      "find '$remote_root' -maxdepth 2 -path '*/steve-session-${target_date}*/facts.db' -print" 2>/dev/null)"; then
    echo "WARN: could not list remote status facts from $remote" >&2
    return 0
  fi
  if [[ -z "$remote_paths" ]]; then
    return 0
  fi
  mkdir -p "$snapshot_dir"
  while IFS= read -r remote_path; do
    [[ -z "$remote_path" ]] && continue
    local parent
    parent="$(basename "$(dirname "$remote_path")")"
    scp -q "$remote:$remote_path" "$snapshot_dir/${parent}-facts.db.tmp" 2>/dev/null \
      && mv "$snapshot_dir/${parent}-facts.db.tmp" "$snapshot_dir/${parent}-facts.db" \
      || echo "WARN: could not copy remote status facts $remote:$remote_path" >&2
  done <<< "$remote_paths"
}

sync_remote_feature_capture() {
  local remote="${STATUS_REMOTE_SSH:-}"
  if [[ -z "$remote" ]]; then
    return 0
  fi
  local target_date="${STATUS_TARGET_DATE:-$(TZ=America/New_York date +%F)}"
  local stamp="${target_date//-/}"
  local capture_dir="$ROOT/live_runtime/feature-capture"
  local remote_root="${STATUS_REMOTE_LIVE_RUNTIME:-/opt/stevetrading/shared/live_runtime}"
  local remote_path="$remote_root/feature-capture/live_features_${stamp}.npz"
  local local_path="$capture_dir/live_features_${stamp}.npz"
  local remote_size
  if ! remote_size="$(ssh -o BatchMode=yes -o ConnectTimeout=5 "$remote" \
      "stat -c %s '$remote_path' 2>/dev/null" 2>/dev/null)"; then
    return 0
  fi
  if [[ -z "$remote_size" || ! "$remote_size" =~ ^[0-9]+$ ]]; then
    return 0
  fi
  local local_size=0
  if [[ -f "$local_path" ]]; then
    local_size="$(stat -c %s "$local_path" 2>/dev/null || printf '0')"
  fi
  if [[ "$local_size" == "$remote_size" ]]; then
    return 0
  fi
  mkdir -p "$capture_dir"
  scp -q "$remote:$remote_path" "$local_path.tmp" 2>/dev/null \
    && mv "$local_path.tmp" "$local_path" \
    || {
      rm -f "$local_path.tmp"
      echo "WARN: could not copy remote feature capture $remote:$remote_path" >&2
    }
}

if [[ ! -x "$BASILISP" ]]; then
  echo "RESULT: FAILED - Basilisp runner not executable: $BASILISP" >&2
  exit 2
fi
if [[ ! -f "$ROOT/scripts/build_status.lpy" || ! -f "$ROOT/scripts/audit_status_publication.lpy" ]]; then
  echo "RESULT: FAILED - hardened status builder/auditor missing under $ROOT/scripts" >&2
  exit 2
fi

cd "$ROOT"
ensure_accounts_nav_target
sync_remote_facts_snapshot
sync_remote_feature_capture
"$BASILISP" run "$ROOT/scripts/build_status.lpy" -- --out-dir "$STATUS_DIR"
"$BASILISP" run "$ROOT/scripts/audit_status_publication.lpy" -- --out-dir "$STATUS_DIR" >/dev/null
