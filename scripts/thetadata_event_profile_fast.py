"""Fast, checkpointed physical profiler for immutable ThetaData NDJSON files.

The project-facing collector and receipt contract remain Basilisp.  This small
standard-library scanner exists because a 19 GB, tens-of-millions-event pass is
an inner-loop workload where Basilisp persistent collections made the original
profiler take more than 18 CPU-hours without a checkpoint.  It does no network
I/O and never mutates raw payloads.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
from collections import Counter
from datetime import UTC, datetime
from pathlib import Path
from typing import Any


MANIFEST_ROOT = Path(r"D:\SteveTradingData\manifests\v1").resolve()


def now_utc() -> str:
    return datetime.now(UTC).strftime("%Y-%m-%dT%H:%M:%S.%fZ")


def ensure_under(path: Path, root: Path) -> None:
    try:
        path.resolve().relative_to(root)
    except ValueError as exc:
        raise ValueError(f"output must be below {root}: {path}") from exc


def atomic_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    staging = path.with_suffix(path.suffix + ".staging")
    staging.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    os.replace(staging, path)


def top_counts(counts: Counter[str], limit: int, label: str) -> list[dict[str, Any]]:
    return [{label: key, "events": count} for key, count in counts.most_common(limit)]


def profile_file(path: Path, top_contracts: int, progress_path: Path, completed_files: int, total_files: int) -> dict[str, Any]:
    event_class = "quote" if path.name.endswith(".quote.ndjson") else "trade"
    started = time.monotonic()
    events = source_bytes = blank_lines = 0
    first_timestamp: str | None = None
    last_timestamp: str | None = None
    per_minute: Counter[str] = Counter()
    per_expiration: Counter[str] = Counter()
    per_right: Counter[str] = Counter()
    per_contract: Counter[str] = Counter()
    quote_states: dict[str, tuple[Any, ...]] = {}
    exact_changes = price_changes = 0

    with path.open("rb", buffering=8 * 1024 * 1024) as stream:
        for line in stream:
            line_bytes = len(line)
            source_bytes += line_bytes
            if not line.strip():
                blank_lines += 1
                continue
            event = json.loads(line)
            timestamp = event.get("timestamp")
            expiration = event.get("expiration")
            right = event.get("right")
            contract = f"{event.get('symbol')}|{expiration}|{event.get('strike')}|{right}"
            events += 1
            per_contract[contract] += 1
            if timestamp:
                first_timestamp = first_timestamp or timestamp
                last_timestamp = timestamp
                per_minute[timestamp[:16]] += 1
            if expiration:
                per_expiration[expiration] += 1
            if right:
                per_right[right] += 1

            if event_class == "quote":
                state = (
                    event.get("bid"), event.get("ask"),
                    event.get("bid_size"), event.get("ask_size"),
                    event.get("bid_exchange"), event.get("ask_exchange"),
                    event.get("bid_condition"), event.get("ask_condition"),
                )
                prior = quote_states.get(contract)
                if state != prior:
                    exact_changes += 1
                if prior is None or state[:2] != prior[:2]:
                    price_changes += 1
                quote_states[contract] = state

            if events % 1_000_000 == 0:
                atomic_json(progress_path, {
                    "kind": "thetadata-event-profile-progress-v1",
                    "updated_at_utc": now_utc(),
                    "status": "running",
                    "completed_files": completed_files,
                    "total_files": total_files,
                    "active_file": path.name,
                    "active_file_events": events,
                    "active_file_bytes_read": source_bytes,
                    "active_file_total_bytes": path.stat().st_size,
                    "active_file_events_per_second": events / max(time.monotonic() - started, 0.001),
                })

    retained_exact = exact_changes if event_class == "quote" else events
    retained_price = price_changes if event_class == "quote" else events
    scale = lambda count: source_bytes * count / events if events else 0
    return {
        "file": path.name,
        "event_class": event_class,
        "source_bytes": source_bytes,
        "events": events,
        "blank_lines": blank_lines,
        "first_timestamp": first_timestamp,
        "last_timestamp": last_timestamp,
        "events_per_second_read": events / max(time.monotonic() - started, 0.001),
        "bytes_per_event": source_bytes / events if events else None,
        "active_contracts": len(per_contract),
        "per_minute": top_counts(per_minute, 20, "minute"),
        "top_expirations": top_counts(per_expiration, 20, "expiration"),
        "top_rights": top_counts(per_right, 4, "right"),
        "top_contracts": top_counts(per_contract, top_contracts, "contract"),
        "causal_retention": {
            "raw_event_stream": {"events": events, "source_byte_equivalent": source_bytes},
            "quote_state_change": {
                "events": retained_exact,
                "source_byte_equivalent": scale(retained_exact),
                "meaning": "Keeps a quote only when bid, ask, size, exchange, or condition changes.",
            },
            "quote_price_change": {
                "events": retained_price,
                "source_byte_equivalent": scale(retained_price),
                "meaning": "Keeps a quote only when bid or ask changes; this is intentionally lossier.",
            },
        },
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--raw-dir", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--top-contracts", type=int, default=30)
    args = parser.parse_args()
    if args.top_contracts <= 0:
        raise ValueError("--top-contracts must be positive")

    raw_dir = Path(args.raw_dir).resolve()
    out = Path(args.out).resolve()
    progress = out.with_suffix(out.suffix + ".progress.json")
    ensure_under(out, MANIFEST_ROOT)
    files = sorted(raw_dir.glob("*.ndjson"))
    if not files:
        raise ValueError(f"no NDJSON payloads found in {raw_dir}")

    profiles: list[dict[str, Any]] = []
    for index, path in enumerate(files):
        atomic_json(progress, {
            "kind": "thetadata-event-profile-progress-v1",
            "updated_at_utc": now_utc(),
            "status": "running",
            "completed_files": index,
            "total_files": len(files),
            "active_file": path.name,
        })
        profiles.append(profile_file(path, args.top_contracts, progress, index, len(files)))

    raw_bytes = sum(profile["source_bytes"] for profile in profiles)
    events = sum(profile["events"] for profile in profiles)
    receipt = {
        "created_at_utc": now_utc(),
        "kind": "thetadata-event-profile-v1",
        "scanner": "thetadata-event-profile-fast-v1-python-stdlib",
        "purpose": "Physical and causal-retention measurement only; this receipt does not claim alpha or approve a permanent filter.",
        "raw": {
            "directory": str(raw_dir), "files": len(profiles), "bytes": raw_bytes, "events": events,
            "bytes_per_event": raw_bytes / events if events else None,
        },
        "method": {
            "reader": "line-by-line UTF-8 NDJSON; no payload is loaded as a whole",
            "quote_state_change": "compare each contract only with its immediately preceding observed quote",
            "source_byte_equivalent": "retained-event fraction multiplied by original bytes; not a serialized-format estimate",
        },
        "files": profiles,
    }
    atomic_json(out, receipt)
    atomic_json(progress, {
        "kind": "thetadata-event-profile-progress-v1",
        "updated_at_utc": now_utc(),
        "status": "complete",
        "completed_files": len(files),
        "total_files": len(files),
        "receipt": str(out),
    })
    print(json.dumps({"status": "complete", "receipt": str(out), "events": events}, sort_keys=True))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:  # pragma: no cover - CLI failure reporting
        print(f"ERROR: {error}", file=sys.stderr)
        raise
