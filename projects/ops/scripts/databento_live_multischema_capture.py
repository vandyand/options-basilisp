#!/usr/bin/env python3
"""Bounded, raw Databento Live capture for later historical parity testing."""

from __future__ import annotations

import argparse
import collections
import datetime as dt
import hashlib
import json
import os
import time
import uuid
from pathlib import Path

import databento as db


def utc_now() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat(timespec="microseconds").replace("+00:00", "Z")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out-root", required=True)
    parser.add_argument("--dataset", required=True)
    parser.add_argument("--symbols", required=True, help="Comma-separated symbols in --stype-in symbology")
    parser.add_argument("--stype-in", required=True)
    parser.add_argument("--schemas", required=True, help="Comma-separated Databento schemas")
    parser.add_argument("--duration-seconds", type=float, required=True)
    parser.add_argument("--api-key-env", default="DATABENTO_API_KEY")
    args = parser.parse_args()
    key = os.environ.get(args.api_key_env)
    if not key:
        raise SystemExit(f"missing required environment variable: {args.api_key_env}")
    schemas = [value.strip() for value in args.schemas.split(",") if value.strip()]
    symbols = [value.strip() for value in args.symbols.split(",") if value.strip()]
    # Parallel captures can enter this code within the same Windows clock tick.
    # Entropy keeps independent evidence streams from sharing a directory.
    run_id = f'{dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")}-{uuid.uuid4().hex[:8]}'
    out_dir = Path(args.out_root) / args.dataset / dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%d") / run_id
    out_dir.mkdir(parents=True, exist_ok=False)
    live_path = out_dir / "live.dbn"
    started_at = utc_now()
    client = db.Live(key=key, ts_out=False)
    try:
        client.add_stream(live_path)
        for schema in schemas:
            client.subscribe(dataset=args.dataset, schema=schema, symbols=symbols, stype_in=args.stype_in)
        client.start()
        subscribed_at = utc_now()
        time.sleep(args.duration_seconds)
    finally:
        client.stop()
    ended_at = utc_now()
    counts: collections.Counter[str] = collections.Counter()
    messages: list[str] = []

    def tally(record: object) -> None:
        record_type = type(record).__name__
        counts[record_type] += 1
        if record_type == "SystemMsg":
            messages.append(record.msg)

    # Unsupported or inactive parents can legitimately produce an empty DBN.
    # Preserve a zero-event receipt instead of losing the negative evidence.
    if live_path.stat().st_size:
        db.read_dbn(live_path).replay(tally)
    receipt = {
        "dataset": args.dataset,
        "duration_seconds": args.duration_seconds,
        "ended_at": ended_at,
        "event_type_counts": dict(sorted(counts.items())),
        "live_dbn": live_path.name,
        "live_dbn_bytes": live_path.stat().st_size,
        "live_dbn_sha256": sha256_file(live_path),
        "schemas": schemas,
        "started_at": started_at,
        "stype_in": args.stype_in,
        "subscribed_at": subscribed_at,
        "symbols": symbols,
        "system_messages": messages,
        "ts_out": False,
    }
    (out_dir / "receipt.json").write_text(json.dumps(receipt, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps({"run_dir": str(out_dir), **receipt}, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
