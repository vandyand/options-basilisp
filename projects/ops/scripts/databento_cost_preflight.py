#!/usr/bin/env python3
"""Fail-closed Databento Historical cost preflight.

This program is intentionally dependency-free so it can run on both the
Windows workstation and the Linux VPS before *any* Databento Historical data
request.  It calls Databento's metadata endpoints only; it never downloads
market data.  A non-zero quoted cost fails unless the caller explicitly sets
an equal-or-higher --max-cost-usd ceiling.

Example (a zero-cost request is the only default-approved request):
  python projects/ops/scripts/databento_cost_preflight.py \\
    --dataset GLBX.MDP3 --symbols ES.FUT --stype-in parent --schema ohlcv-1s \\
    --start 2026-07-14T13:30:00Z --end 2026-07-14T13:31:00Z
"""

from __future__ import annotations

import argparse
import base64
import json
import os
import sys
from datetime import datetime, timezone
from decimal import Decimal, InvalidOperation
from pathlib import Path
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen


HISTORICAL_API = "https://hist.databento.com/v0"


def parse_timestamp(value: str) -> str:
    """Validate an ISO-8601 instant and preserve Databento-friendly UTC text."""
    normalized = value.replace("Z", "+00:00")
    try:
        parsed = datetime.fromisoformat(normalized)
    except ValueError as exc:
        raise argparse.ArgumentTypeError(
            f"invalid ISO-8601 timestamp: {value!r}"
        ) from exc
    if parsed.tzinfo is None:
        raise argparse.ArgumentTypeError("timestamp must include a UTC offset or Z")
    return parsed.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")


def non_negative_decimal(value: str) -> Decimal:
    try:
        amount = Decimal(value)
    except InvalidOperation as exc:
        raise argparse.ArgumentTypeError("must be a decimal USD amount") from exc
    if amount < 0:
        raise argparse.ArgumentTypeError("must not be negative")
    return amount


def metadata_get(endpoint: str, parameters: dict[str, str], api_key: str) -> str:
    query = urlencode(parameters)
    # Databento HTTP Basic auth uses the API key as the username and an empty
    # password. Never put the key in a URL, receipt, exception, or stdout.
    encoded_credentials = base64.b64encode(f"{api_key}:".encode("ascii")).decode("ascii")
    request = Request(
        f"{HISTORICAL_API}/{endpoint}?{query}",
        headers={"Authorization": f"Basic {encoded_credentials}"},
        method="GET",
    )
    try:
        with urlopen(request, timeout=30) as response:  # noqa: S310 -- fixed HTTPS endpoint
            return response.read().decode("utf-8").strip()
    except HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace").strip()
        raise RuntimeError(f"Databento {endpoint} returned HTTP {exc.code}: {detail}") from exc
    except URLError as exc:
        raise RuntimeError(f"Databento {endpoint} request failed: {exc.reason}") from exc


def parse_decimal_response(endpoint: str, response: str) -> Decimal:
    try:
        return Decimal(response)
    except InvalidOperation as exc:
        raise RuntimeError(f"Databento {endpoint} returned a non-numeric value: {response}") from exc


def write_receipt(path: Path, receipt: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(receipt, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Quote a Databento Historical request and fail closed above a USD ceiling."
    )
    parser.add_argument("--dataset", required=True, help="Databento dataset, e.g. GLBX.MDP3")
    parser.add_argument("--symbols", required=True, help="Comma-separated Databento symbols")
    parser.add_argument("--schema", required=True, help="Databento schema, e.g. mbp-1")
    parser.add_argument("--start", required=True, type=parse_timestamp)
    parser.add_argument("--end", required=True, type=parse_timestamp)
    parser.add_argument("--stype-in", default=None, help="Optional input symbology, e.g. parent")
    parser.add_argument(
        "--max-cost-usd",
        type=non_negative_decimal,
        default=Decimal("0"),
        help="Explicit approved ceiling; defaults to $0.00 (fail closed).",
    )
    parser.add_argument(
        "--api-key-env",
        default="DATABENTO_API_KEY",
        help="Environment variable containing the Databento key (default: DATABENTO_API_KEY).",
    )
    parser.add_argument(
        "--receipt-path",
        type=Path,
        help="Optional path for a sanitized JSON preflight receipt.",
    )
    args = parser.parse_args()

    if args.start >= args.end:
        parser.error("--end must be later than --start")
    api_key = os.environ.get(args.api_key_env)
    if not api_key:
        parser.error(f"missing required environment variable: {args.api_key_env}")

    request_spec = {
        "dataset": args.dataset,
        "symbols": args.symbols,
        "schema": args.schema,
        "start": args.start,
        "end": args.end,
    }
    if args.stype_in:
        request_spec["stype_in"] = args.stype_in

    try:
        quoted_cost = parse_decimal_response(
            "metadata.get_cost", metadata_get("metadata.get_cost", request_spec, api_key)
        )
        billable_size_bytes = int(
            parse_decimal_response(
                "metadata.get_billable_size",
                metadata_get("metadata.get_billable_size", request_spec, api_key),
            )
        )
    except (RuntimeError, ValueError) as exc:
        print(f"COST PREFLIGHT FAILED: {exc}", file=sys.stderr)
        return 2

    approved = quoted_cost <= args.max_cost_usd
    receipt: dict[str, Any] = {
        "approved": approved,
        "billable_size_bytes": billable_size_bytes,
        "checked_at_utc": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        "max_cost_usd": str(args.max_cost_usd),
        "quoted_cost_usd": str(quoted_cost),
        "request": request_spec,
    }
    if args.receipt_path:
        write_receipt(args.receipt_path, receipt)
    print(json.dumps(receipt, indent=2, sort_keys=True))

    if not approved:
        print(
            "COST PREFLIGHT BLOCKED: no historical request may be submitted. "
            "Re-run only with an explicitly approved --max-cost-usd ceiling.",
            file=sys.stderr,
        )
        return 3
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
