#!/usr/bin/env python3
"""Capture and test Databento GLBX completed OHLCV live/history parity.

The ``capture`` phase is live-only and creates a DBN evidence file.  The
``compare`` phase first invokes ``databento_cost_preflight.py`` with the exact
captured interval. It will not submit the Historical request unless that
preflight exits successfully (default approved cost: $0.00).

This is deliberately limited to completed ``ohlcv-1s`` and ``ohlcv-1m`` bars
for the initial study. Raw trades and MBP are much higher-volume follow-up
classes and require their own bounded, representation-aware comparator.
"""

from __future__ import annotations

import argparse
import collections
import datetime as dt
import json
import os
import subprocess
import sys
import time
from pathlib import Path
from typing import Any

try:
    import databento as db
except ImportError as exc:  # pragma: no cover - operator setup failure
    raise SystemExit(
        "The Databento SDK is required. Install it in an isolated environment: "
        "python -m pip install databento"
    ) from exc


ALLOWED_SCHEMAS = ("ohlcv-1s", "ohlcv-1m")


def utc_now() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat(timespec="microseconds").replace("+00:00", "Z")


def write_json(path: Path, value: dict[str, Any]) -> None:
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def replay_records(path: Path) -> list[Any]:
    store = db.read_dbn(path)
    records: list[Any] = []
    store.replay(records.append)
    return records


def ohlcv_signature(record: Any) -> tuple[Any, ...] | None:
    """Return the complete model-data identity for one completed OHLCV bar.

    DBN system and symbol-mapping messages are intentionally excluded: they are
    subscription-session transport metadata, not market data. ``ts_out`` is
    disabled during live capture, so no local-receipt timestamp is compared.
    """
    if type(record).__name__ != "OHLCVMsg":
        return None
    return (
        int(record.rtype),
        int(record.publisher_id),
        int(record.instrument_id),
        int(record.ts_event),
        int(record.open),
        int(record.high),
        int(record.low),
        int(record.close),
        int(record.volume),
    )


def ohlcv_counter(path: Path) -> collections.Counter[tuple[Any, ...]]:
    signatures = (ohlcv_signature(record) for record in replay_records(path))
    return collections.Counter(signature for signature in signatures if signature is not None)


def first_complete_bar_start_ns(capture_started_at: str, schema: str) -> int:
    """Return the earliest bar-start timestamp fully observable after subscribe.

    Live OHLCV messages are emitted when an interval closes but use the start
    of that interval as ``ts_event``. A subscription that starts in the middle
    of a minute can therefore receive a minute bar whose opening trades were
    not observed. It is not a valid live-vs-history parity cohort member.
    """
    interval_seconds = {"ohlcv-1s": 1, "ohlcv-1m": 60}[schema]
    started = dt.datetime.fromisoformat(capture_started_at.replace("Z", "+00:00"))
    started_ns = int(started.timestamp() * 1_000_000_000)
    interval_ns = interval_seconds * 1_000_000_000
    return ((started_ns + interval_ns - 1) // interval_ns) * interval_ns


def complete_ohlcv_counter(
    path: Path,
    minimum_ts_event: int,
) -> collections.Counter[tuple[Any, ...]]:
    counter: collections.Counter[tuple[Any, ...]] = collections.Counter()
    for record in replay_records(path):
        signature = ohlcv_signature(record)
        if signature is not None and signature[3] >= minimum_ts_event:
            counter[signature] += 1
    return counter


def command_capture(args: argparse.Namespace) -> int:
    api_key = os.environ.get(args.api_key_env)
    if not api_key:
        raise SystemExit(f"missing required environment variable: {args.api_key_env}")
    run_id = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    run_dir = Path(args.out_root) / dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%d") / run_id
    run_dir.mkdir(parents=True, exist_ok=False)
    live_path = run_dir / "live.dbn"

    started_at = utc_now()
    client = db.Live(key=api_key, ts_out=False)
    try:
        client.add_stream(live_path)
        client.subscribe(
            dataset=args.dataset,
            schema=args.schema,
            symbols=args.symbols,
            stype_in=args.stype_in,
        )
        client.start()
        subscribed_at = utc_now()
        time.sleep(args.duration_seconds)
    finally:
        client.stop()
    ended_at = utc_now()
    record_count = len(replay_records(live_path))
    market_bars = sum(ohlcv_counter(live_path).values())
    receipt = {
        "dataset": args.dataset,
        "duration_seconds": args.duration_seconds,
        "ended_at": ended_at,
        "live_dbn": live_path.name,
        "market_bar_count": market_bars,
        "record_count": record_count,
        "schema": args.schema,
        "started_at": started_at,
        "stype_in": args.stype_in,
        "subscribed_at": subscribed_at,
        "symbols": args.symbols,
        "ts_out": False,
    }
    write_json(run_dir / "receipt.json", receipt)
    print(json.dumps({"run_dir": str(run_dir), **receipt}, indent=2, sort_keys=True))
    return 0 if market_bars else 2


def command_compare(args: argparse.Namespace) -> int:
    run_dir = Path(args.run_dir)
    receipt_path = run_dir / "receipt.json"
    live_path = run_dir / "live.dbn"
    if not receipt_path.is_file() or not live_path.is_file():
        raise SystemExit("--run-dir must contain capture-phase receipt.json and live.dbn")
    receipt = json.loads(receipt_path.read_text(encoding="utf-8"))
    schema = receipt["schema"]
    if schema not in ALLOWED_SCHEMAS:
        raise SystemExit(f"unsupported captured schema: {schema}")

    # This subprocess is the billing gate. Keep the request parameters in one
    # place, and retain its sanitized receipt beside the subsequent DBN file.
    preflight = Path(__file__).with_name("databento_cost_preflight.py")
    cost_receipt = run_dir / "historical-cost-preflight.json"
    cost_command = [
        sys.executable, str(preflight),
        "--dataset", receipt["dataset"],
        "--symbols", receipt["symbols"],
        "--schema", schema,
        "--start", receipt["started_at"],
        "--end", receipt["ended_at"],
        "--max-cost-usd", str(args.max_cost_usd),
        "--api-key-env", args.api_key_env,
        "--receipt-path", str(cost_receipt),
    ]
    if receipt.get("stype_in"):
        cost_command.extend(("--stype-in", receipt["stype_in"]))
    preflight_result = subprocess.run(cost_command, check=False)
    if preflight_result.returncode:
        write_json(run_dir / "summary.json", {
            "cost_preflight_receipt": cost_receipt.name if cost_receipt.is_file() else None,
            "cost_preflight_returncode": preflight_result.returncode,
            "reason": "historical download was blocked by the cost/availability preflight",
            "schema": schema,
            "status": "INCONCLUSIVE",
        })
        print("Historical download was not submitted because the cost preflight did not approve it.", file=sys.stderr)
        return preflight_result.returncode

    api_key = os.environ.get(args.api_key_env)
    if not api_key:
        raise SystemExit(f"missing required environment variable: {args.api_key_env}")
    history_path = run_dir / "historical.dbn"
    try:
        db.Historical(key=api_key).timeseries.get_range(
            dataset=receipt["dataset"],
            start=receipt["started_at"],
            end=receipt["ended_at"],
            symbols=receipt["symbols"],
            schema=schema,
            stype_in=receipt["stype_in"],
            path=history_path,
        )
    except Exception as exc:  # preserve evidence, but do not mistake latency for a mismatch
        write_json(run_dir / "summary.json", {
            "status": "INCONCLUSIVE",
            "reason": "historical request failed after approved cost preflight",
            "error_type": type(exc).__name__,
        })
        print(f"Historical request failed after preflight: {type(exc).__name__}: {exc}", file=sys.stderr)
        return 2

    minimum_ts_event = first_complete_bar_start_ns(receipt["subscribed_at"], schema)
    live = complete_ohlcv_counter(live_path, minimum_ts_event)
    historical_all = ohlcv_counter(history_path)
    # History can include partial boundary bars. Compare only the complete bar
    # records observed live; extras outside that observed cohort are irrelevant.
    historical = collections.Counter({key: historical_all[key] for key in live})
    live_only = live - historical
    historical_only = historical - live
    if not live:
        status, reason = "INCONCLUSIVE", "live capture contained no completed OHLCV bars"
    elif not historical:
        status, reason = "INCONCLUSIVE", "historical response contained no captured live bar"
    elif live_only or historical_only:
        status, reason = "FAIL", "one or more captured live OHLCV records differed from history"
    else:
        status, reason = "PASS", "all captured live completed OHLCV records matched history exactly"
    summary = {
        "historical_bar_count_for_live_cohort": sum(historical.values()),
        "historical_total_bar_count": sum(historical_all.values()),
        "historical_only_count": sum(historical_only.values()),
        "live_bar_count": sum(live.values()),
        "live_only_count": sum(live_only.values()),
        "reason": reason,
        "record_representation": "DBN OHLCV fields; excludes system/mapping messages and ts_out",
        "first_complete_bar_start_ns": minimum_ts_event,
        "partial_start_boundary_bars_excluded": True,
        "schema": schema,
        "status": status,
    }
    write_json(run_dir / "summary.json", summary)
    print(json.dumps({"run_dir": str(run_dir), **summary}, indent=2, sort_keys=True))
    return {"PASS": 0, "FAIL": 1, "INCONCLUSIVE": 2}[status]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    capture = commands.add_parser("capture", help="Capture a bounded live DBN evidence file.")
    capture.add_argument("--out-root", required=True)
    capture.add_argument("--dataset", default="GLBX.MDP3")
    capture.add_argument("--symbols", default="ES.FUT")
    capture.add_argument("--stype-in", default="parent")
    capture.add_argument("--schema", choices=ALLOWED_SCHEMAS, default="ohlcv-1s")
    capture.add_argument("--duration-seconds", type=float, default=120.0)
    capture.add_argument("--api-key-env", default="DATABENTO_API_KEY")

    compare = commands.add_parser("compare", help="Preflight then compare an existing live capture.")
    compare.add_argument("--run-dir", required=True)
    compare.add_argument("--max-cost-usd", default="0")
    compare.add_argument("--api-key-env", default="DATABENTO_API_KEY")
    args = parser.parse_args()
    return command_capture(args) if args.command == "capture" else command_compare(args)


if __name__ == "__main__":
    raise SystemExit(main())
