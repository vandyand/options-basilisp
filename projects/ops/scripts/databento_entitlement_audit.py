#!/usr/bin/env python3
"""Read-only Databento historical-catalogue and live-entitlement audit.

The program never calls a historical time-series endpoint. It only calls
metadata endpoints and makes very short, single-symbol live subscriptions.
It is intended to distinguish an explicit license denial from a transport or
symbol-probe problem; the latter must not be reported as a denial.
"""

from __future__ import annotations

import argparse
import collections
import datetime as dt
import json
import os
import time
from pathlib import Path
from typing import Any

import databento as db


# A small, liquid, valid-or-plausible instrument per venue. Most unlicensed
# datasets reject before symbology is evaluated; a non-license transport error
# is deliberately kept inconclusive.
CANDIDATES: dict[str, tuple[str, str]] = {
    "GLBX.MDP3": ("ES.FUT", "parent"),
    "OPRA.PILLAR": ("SPY.OPT", "parent"),
    "EQUS.MINI": ("SPY", "raw_symbol"),
    "EQUS.SUMMARY": ("SPY", "raw_symbol"),
    "XCBF.PITCH": ("VX.FUT", "parent"),
    "IFEU.IMPACT": ("BRN.FUT", "parent"),
    "IFLL.IMPACT": ("G.FUT", "parent"),
    "IFUS.IMPACT": ("DX.FUT", "parent"),
    "NDEX.IMPACT": ("TTF.FUT", "parent"),
    "XEUR.EOBI": ("AAPL", "raw_symbol"),
    "XEEE.EOBI": ("AAPL", "raw_symbol"),
}


def utc_now() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat(timespec="microseconds").replace("+00:00", "Z")


def preferred_schema(schemas: list[str]) -> str | None:
    return next(
        (schema for schema in ("mbo", "mbp-10", "cmbp-1", "mbp-1", "trades", "ohlcv-1s", "ohlcv-1d") if schema in schemas),
        None,
    )


def probe_live(key: str, dataset: str, schema: str, symbol: str, stype_in: str, seconds: float) -> dict[str, Any]:
    records: list[Any] = []
    exception: str | None = None
    started = False
    client: db.Live | None = None
    try:
        client = db.Live(key=key, ts_out=False)
        client.add_callback(records.append)
        client.subscribe(dataset=dataset, schema=schema, symbols=[symbol], stype_in=stype_in)
        client.start()
        started = True
        time.sleep(seconds)
    except Exception as exc:  # The library exposes entitlement and gateway errors here.
        exception = f"{type(exc).__name__}: {str(exc)[:500]}"
    finally:
        if client is not None:
            try:
                client.stop()
            except Exception as exc:
                exception = exception or f"stop {type(exc).__name__}: {str(exc)[:500]}"

    counts = collections.Counter(type(record).__name__ for record in records)
    errors = [str(record)[:500] for record in records if type(record).__name__ == "ErrorMsg"]
    diagnostic = " ".join(errors + ([exception] if exception else [])).lower()
    market_types = set(counts) - {"SystemMsg", "ErrorMsg", "SymbolMappingMsg"}
    if "license" in diagnostic or "not authorized" in diagnostic:
        status = "NOT_ENTITLED"
    elif market_types:
        status = "ACTIVE"
    elif started and not errors:
        status = "SESSION_ACCEPTED_NO_MARKET_RECORDS"
    else:
        status = "INCONCLUSIVE_TRANSPORT_OR_SYMBOL"
    return {
        "schema": schema,
        "symbol": symbol,
        "stype_in": stype_in,
        "status": status,
        "record_counts": dict(sorted(counts.items())),
        "errors": errors,
        "exception": exception,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", required=True, type=Path, help="Sanitized JSON report path.")
    parser.add_argument("--live-window-seconds", type=float, default=1.25)
    parser.add_argument("--api-key-env", default="DATABENTO_API_KEY")
    args = parser.parse_args()
    if args.live_window_seconds <= 0:
        parser.error("--live-window-seconds must be positive")
    key = os.environ.get(args.api_key_env)
    if not key:
        parser.error(f"missing {args.api_key_env}")

    historical = db.Historical(key=key)
    datasets = sorted(historical.metadata.list_datasets())
    report: dict[str, Any] = {
        "checked_at_utc": utc_now(),
        "historical_requests_submitted": 0,
        "live_probe_window_seconds": args.live_window_seconds,
        "datasets": {},
    }
    for dataset in datasets:
        entry: dict[str, Any] = {"dataset": dataset}
        try:
            schemas = sorted(historical.metadata.list_schemas(dataset=dataset))
            entry["historical_schemas"] = schemas
            entry["historical_range"] = historical.metadata.get_dataset_range(dataset=dataset)
        except Exception as exc:
            entry["historical_metadata_error"] = f"{type(exc).__name__}: {str(exc)[:500]}"
            report["datasets"][dataset] = entry
            continue
        schema = preferred_schema(schemas)
        if schema is None:
            entry["live_probe"] = {"status": "NO_COMPATIBLE_SCHEMA"}
        else:
            symbol, stype_in = CANDIDATES.get(dataset, ("SPY", "raw_symbol"))
            entry["live_probe"] = probe_live(key, dataset, schema, symbol, stype_in, args.live_window_seconds)
        report["datasets"][dataset] = entry

    # The broadest live feeds need schema-level, not merely dataset-level, results.
    details: dict[str, list[dict[str, Any]]] = {}
    for dataset, symbol, stype_in, schemas in (
        ("GLBX.MDP3", "ES.FUT", "parent", ("mbo", "mbp-10", "mbp-1", "trades", "ohlcv-1s", "ohlcv-1m")),
        ("EQUS.MINI", "SPY", "raw_symbol", ("mbp-1", "trades", "ohlcv-1s", "ohlcv-1m")),
    ):
        allowed = set(report["datasets"].get(dataset, {}).get("historical_schemas", []))
        details[dataset] = [
            probe_live(key, dataset, schema, symbol, stype_in, args.live_window_seconds)
            for schema in schemas
            if schema in allowed
        ]
    report["schema_level_live_probes"] = details
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps({"out": str(args.out), "datasets": len(datasets), "checked_at_utc": report["checked_at_utc"]}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
