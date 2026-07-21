#!/usr/bin/env python3
"""Broker-truth reconciliation and last-resort flattening for paper accounts.

This intentionally talks to Alpaca directly instead of relying on the strategy
ledger.  A process restart can lose an in-memory/partial-session view while a
broker position remains real; this guard makes that mismatch safe.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path


BASE_URL = "https://paper-api.alpaca.markets/v2"
ACCOUNT_SLUGS = ("chestnut", "lynx", "moose", "oak", "parrot", "dolphin")


def parse_dotenv(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    if not path.is_file():
        return values
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        values[key.strip()] = value.strip().strip('"').strip("'")
    return values


def credentials(env: dict[str, str], slug: str) -> tuple[str, str]:
    prefix = f"ALPACA_{slug.upper()}"
    key = env.get(f"{prefix}_API_KEY") or env.get(f"{prefix}_PAPER_API_KEY")
    secret = (
        env.get(f"{prefix}_API_SECRET")
        or env.get(f"{prefix}_SECRET_KEY")
        or env.get(f"{prefix}_PAPER_SECRET_KEY")
    )
    if not key or not secret:
        raise ValueError(f"missing Alpaca paper credentials for {slug}")
    return key, secret


def request(key: str, secret: str, method: str, path: str) -> tuple[int, object]:
    req = urllib.request.Request(
        BASE_URL + path,
        method=method,
        headers={
            "APCA-API-KEY-ID": key,
            "APCA-API-SECRET-KEY": secret,
            "Accept": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as response:
            body = response.read().decode("utf-8")
            return response.status, json.loads(body) if body else {}
    except urllib.error.HTTPError as error:
        body = error.read().decode("utf-8")
        try:
            payload: object = json.loads(body)
        except json.JSONDecodeError:
            payload = {"message": body}
        return error.code, payload


def positions_for(key: str, secret: str) -> list[dict[str, object]]:
    status, payload = request(key, secret, "GET", "/positions")
    if status != 200 or not isinstance(payload, list):
        raise RuntimeError(f"position query failed: HTTP {status} {payload}")
    return payload


def compact_position(position: dict[str, object]) -> dict[str, object]:
    return {
        key: position.get(key)
        for key in ("symbol", "qty", "side", "avg_entry_price", "current_price",
                    "market_value", "unrealized_pl")
    }


def flatten_account(key: str, secret: str, positions: list[dict[str, object]]) -> list[dict[str, object]]:
    # Cancel resting orders first.  A stale close order must not race a new
    # close request or silently prevent the emergency flatten from filling.
    cancel_status, cancel_payload = request(key, secret, "DELETE", "/orders")
    if cancel_status not in (200, 207):
        raise RuntimeError(f"open-order cancellation failed: HTTP {cancel_status} {cancel_payload}")
    submitted: list[dict[str, object]] = []
    for position in positions:
        symbol = str(position["symbol"])
        path = "/positions/" + urllib.parse.quote(symbol, safe="")
        status, payload = request(key, secret, "DELETE", path)
        if status < 200 or status >= 300 or not isinstance(payload, dict):
            raise RuntimeError(f"close request for {symbol} failed: HTTP {status} {payload}")
        submitted.append({
            "symbol": symbol,
            "order_id": payload.get("id"),
            "side": payload.get("side"),
            "qty": payload.get("qty"),
            "status": payload.get("status"),
        })
    return submitted


def run(args: argparse.Namespace) -> int:
    dotenv = parse_dotenv(Path(args.ref_root) / ".env")
    env = {**dotenv, **os.environ}
    accounts = args.account or list(ACCOUNT_SLUGS)
    initial: dict[str, list[dict[str, object]]] = {}
    submitted: dict[str, list[dict[str, object]]] = {}

    for slug in accounts:
        key, secret = credentials(env, slug)
        positions = positions_for(key, secret)
        initial[slug] = [compact_position(position) for position in positions]
        if args.mode == "flatten" and positions:
            submitted[slug] = flatten_account(key, secret, positions)

    deadline = time.monotonic() + args.timeout_seconds
    final = initial
    while args.mode == "flatten" and any(final.values()) and time.monotonic() < deadline:
        time.sleep(args.poll_seconds)
        final = {}
        for slug in accounts:
            key, secret = credentials(env, slug)
            final[slug] = [compact_position(position) for position in positions_for(key, secret)]

    result = {"mode": args.mode, "initial_positions": initial,
              "close_requests": submitted, "final_positions": final}
    print(json.dumps(result, sort_keys=True))
    return 0 if not any(final.values()) else 1


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mode", choices=("audit", "flatten"), default="audit")
    parser.add_argument("--ref-root", default=os.environ.get("STEVE_REF_ROOT", "."))
    parser.add_argument("--account", action="append", choices=ACCOUNT_SLUGS)
    parser.add_argument("--timeout-seconds", type=int, default=90)
    parser.add_argument("--poll-seconds", type=int, default=3)
    args = parser.parse_args()
    if args.timeout_seconds < 0 or args.poll_seconds <= 0:
        parser.error("timeout must be non-negative and poll interval must be positive")
    try:
        return run(args)
    except (OSError, RuntimeError, ValueError) as error:
        print(f"alpaca position safety failed: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
