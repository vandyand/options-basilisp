#!/usr/bin/env python3
"""Cost-gated, raw DBN live-vs-historical comparison for one live capture.

The capture directory must contain ``receipt.json`` and ``live.dbn`` from
``databento_live_multischema_capture.py``.  The tool quotes every schema
first, sums the quotes, and refuses every historical request if the total is
above ``--max-total-cost-usd`` (default: zero).
"""

from __future__ import annotations

import argparse
import collections
import datetime as dt
import json
import os
import sys
from decimal import Decimal
from pathlib import Path
from typing import Any

import databento as db


TRANSPORT_RECORDS = {"SystemMsg", "SymbolMappingMsg", "ErrorMsg"}
DERIVED_FIELDS = {
    "pretty_ts_event", "pretty_ts_index", "pretty_ts_out", "record_size", "size_hint",
    "ts_index", "ts_out",
}

# ``ts_recv`` is a Databento transport/receipt timestamp.  It is useful for
# latency research but not a stable market-event field across a live feed and
# Historical replay (notably on derived EQUS data).  It is excluded only when
# the operator explicitly selects the ``market`` representation below.
MARKET_TRANSPORT_FIELDS = {"ts_recv", "ts_out", "ts_index", "ts_in_delta"}


def utc_now() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat(timespec="microseconds").replace("+00:00", "Z")


def json_value(value: Any) -> Any:
    if value is None or isinstance(value, (str, int, float, bool)):
        return value
    if isinstance(value, bytes):
        return value.hex()
    try:
        return int(value)
    except (TypeError, ValueError):
        return str(value)


def signature(
    record: Any,
    excluded_fields: set[str],
) -> tuple[str, tuple[tuple[str, Any], ...]] | None:
    record_type = type(record).__name__
    if record_type in TRANSPORT_RECORDS:
        return None
    values: list[tuple[str, Any]] = []
    for field in dir(record):
        if (
            field.startswith("_")
            or field in DERIVED_FIELDS
            or field in excluded_fields
            or field.startswith("pretty_")
        ):
            continue
        try:
            value = getattr(record, field)
        except (AttributeError, RuntimeError):
            continue
        if callable(value):
            continue
        if isinstance(value, (list, dict, set, tuple)):
            continue
        values.append((field, json_value(value)))
    return record_type, tuple(values)


def counters(
    path: Path,
    excluded_fields: set[str],
) -> dict[str, collections.Counter[tuple[str, tuple[tuple[str, Any], ...]]]]:
    records: list[Any] = []
    db.read_dbn(path).replay(records.append)
    result: dict[str, collections.Counter[tuple[str, tuple[tuple[str, Any], ...]]]] = {}
    for record in records:
        item = signature(record, excluded_fields)
        if item is None:
            continue
        result.setdefault(item[0], collections.Counter())[item] += 1
    return result


def rtypes(counter: collections.Counter[tuple[str, tuple[tuple[str, Any], ...]]]) -> set[Any]:
    """Return DBN rtype values represented by a counter's record signatures.

    ``OHLCVMsg`` is used for every OHLCV interval in the Python client.  The
    DBN ``rtype`` field, which remains in ``signature()``, distinguishes 1s
    and 1m bars.  Without this filter a multi-schema live capture incorrectly
    compares all bar intervals against every historical bar request.
    """
    result: set[Any] = set()
    for _, fields in counter:
        field_map = dict(fields)
        if "rtype" in field_map:
            result.add(field_map["rtype"])
    return result


def with_rtypes(
    counter: collections.Counter[tuple[str, tuple[tuple[str, Any], ...]]],
    allowed: set[Any],
) -> collections.Counter[tuple[str, tuple[tuple[str, Any], ...]]]:
    """Keep only records whose DBN rtype appears in a schema's history."""
    if not allowed:
        return collections.Counter()
    return collections.Counter(
        {item: count for item, count in counter.items() if dict(item[1]).get("rtype") in allowed}
    )


def write_json(path: Path, payload: Any) -> None:
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--run-dir", required=True)
    parser.add_argument(
        "--schemas",
        nargs="+",
        help="Optional subset of schemas from receipt.json to compare.",
    )
    parser.add_argument(
        "--limit",
        type=int,
        help="Maximum historical market-data records per request. A limited run is diagnostic only, never full-window certification.",
    )
    parser.add_argument(
        "--representation",
        choices=("strict", "market"),
        default="strict",
        help="strict retains all DBN fields; market excludes live-vs-history transport timestamps.",
    )
    parser.add_argument(
        "--start-override",
        help="Optional UTC historical start for a bounded diagnostic; receipt values remain the evidence of actual capture boundaries.",
    )
    parser.add_argument(
        "--end-override",
        help="Optional UTC historical end for a bounded diagnostic.",
    )
    parser.add_argument(
        "--result-name",
        help="Optional suffix so an alternate bounded diagnostic cannot overwrite the default comparison artifacts.",
    )
    parser.add_argument("--max-total-cost-usd", default="0")
    parser.add_argument(
        "--max-total-billable-bytes",
        type=int,
        default=268435456,
        help="Hard aggregate historical payload ceiling (default: 256 MiB).",
    )
    parser.add_argument("--api-key-env", default="DATABENTO_API_KEY")
    args = parser.parse_args()
    try:
        maximum = Decimal(args.max_total_cost_usd)
    except Exception as exc:
        parser.error(f"invalid --max-total-cost-usd: {exc}")
    if maximum < 0:
        parser.error("--max-total-cost-usd cannot be negative")
    if args.max_total_billable_bytes <= 0:
        parser.error("--max-total-billable-bytes must be positive")
    if args.limit is not None and args.limit <= 0:
        parser.error("--limit must be positive")
    run_dir = Path(args.run_dir)
    receipt = json.loads((run_dir / "receipt.json").read_text(encoding="utf-8"))
    live_path = run_dir / "live.dbn"
    if not live_path.is_file():
        raise SystemExit("live.dbn not found")
    key = os.environ.get(args.api_key_env)
    if not key:
        raise SystemExit(f"missing required environment variable: {args.api_key_env}")
    historical = db.Historical(key=key)
    common: dict[str, Any] = {
        "dataset": receipt["dataset"], "symbols": receipt["symbols"], "stype_in": receipt["stype_in"],
        "start": args.start_override or receipt["started_at"],
        "end": args.end_override or receipt["ended_at"],
    }
    if args.limit is not None:
        common["limit"] = args.limit
    schemas = receipt["schemas"]
    if args.schemas:
        unknown = sorted(set(args.schemas) - set(schemas))
        if unknown:
            parser.error(f"--schemas not present in receipt.json: {', '.join(unknown)}")
        schemas = args.schemas
    quotes = []
    for schema in schemas:
        quote = Decimal(str(historical.metadata.get_cost(schema=schema, **common)))
        size = int(historical.metadata.get_billable_size(schema=schema, **common))
        quotes.append({"schema": schema, "quoted_cost_usd": str(quote), "billable_size_bytes": size})
    total = sum((Decimal(item["quoted_cost_usd"]) for item in quotes), Decimal("0"))
    total_bytes = sum(item["billable_size_bytes"] for item in quotes)
    plan = {
        "approved": total <= maximum and total_bytes <= args.max_total_billable_bytes,
        "checked_at_utc": utc_now(),
        "max_total_billable_bytes": args.max_total_billable_bytes,
        "max_total_cost_usd": str(maximum),
        "quoted_total_billable_bytes": total_bytes,
        "quoted_total_cost_usd": str(total),
        "request": common,
        "schemas": quotes,
    }
    suffix = f"-{args.result_name}" if args.result_name else ""
    write_json(run_dir / f"historical-cost-plan{suffix}.json", plan)
    if total > maximum or total_bytes > args.max_total_billable_bytes:
        print(json.dumps(plan, indent=2), file=sys.stderr)
        print("COST/SIZE PLAN BLOCKED: no historical request was submitted.", file=sys.stderr)
        return 3

    historical_dir = run_dir / f"historical{suffix}"
    historical_dir.mkdir(exist_ok=True)
    excluded_fields = MARKET_TRANSPORT_FIELDS if args.representation == "market" else set()
    live = counters(live_path, excluded_fields)
    result: dict[str, Any] = {
        "classes": {},
        "cost_plan": plan,
        "status": "INCONCLUSIVE",
        "representation": args.representation,
        "excluded_fields": sorted(excluded_fields),
        "limited_historical_records": args.limit,
        "scope": "bounded diagnostic; not full-window certification" if args.limit else "full captured window",
    }
    schema_statuses = []
    for schema in schemas:
        history_path = historical_dir / f"{schema}.dbn"
        try:
            historical.timeseries.get_range(schema=schema, path=history_path, **common)
        except Exception as exc:
            result["classes"][schema] = {"status": "INCONCLUSIVE", "reason": type(exc).__name__}
            schema_statuses.append("INCONCLUSIVE")
            continue
        history = counters(history_path, excluded_fields)
        # A capture can contain several schemas. The just-fetched historical
        # file identifies the record type(s) relevant to this schema.
        live_types = {
            kind: with_rtypes(live[kind], rtypes(history[kind]))
            for kind in history
            if kind in live and live[kind]
        }
        per_type = {}
        for kind, live_counter in live_types.items():
            historical_counter = history.get(kind, collections.Counter())
            if args.limit is not None:
                # History is an intentionally bounded chronological subset.
                # Its records must all be present in the complete live capture;
                # live extras are outside this requested subset and are not a
                # discrepancy.
                historical_only = historical_counter - live_counter
                live_only = collections.Counter()
                historical_for_live = historical_counter
            else:
                live_only = live_counter - historical_counter
                historical_for_live = collections.Counter({key: historical_counter[key] for key in live_counter})
                historical_only = historical_for_live - live_counter
            per_type[kind] = {
                "historical_count_for_live_cohort": sum(historical_for_live.values()),
                "live_count": sum(live_counter.values()),
                "live_only_count": sum(live_only.values()),
                "historical_only_count": sum(historical_only.values()),
            }
        # Each live file can contain multiple schemas. Limit a schema conclusion
        # to its expected DBN record type(s) by requiring actual historical matches.
        relevant = {kind: value for kind, value in per_type.items() if value["live_count"]}
        if not relevant:
            status = "INCONCLUSIVE"
        elif any(value["live_only_count"] or value["historical_only_count"] for value in relevant.values()):
            status = "FAIL"
        else:
            status = "PARTIAL_PASS" if args.limit is not None else "PASS"
        result["classes"][schema] = {"status": status, "record_types": relevant}
        schema_statuses.append(status)
    if schema_statuses and all(status in {"PASS", "PARTIAL_PASS"} for status in schema_statuses):
        result["status"] = "PARTIAL_PASS" if args.limit is not None else "PASS"
    elif any(status == "FAIL" for status in schema_statuses):
        result["status"] = "FAIL"
    write_json(run_dir / f"summary{suffix}.json", result)
    print(json.dumps({"run_dir": str(run_dir), "status": result["status"], "cost": plan}, indent=2))
    return {"PASS": 0, "PARTIAL_PASS": 0, "FAIL": 1, "INCONCLUSIVE": 2}[result["status"]]


if __name__ == "__main__":
    raise SystemExit(main())
