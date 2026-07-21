#!/usr/bin/env python3
"""Capture Alpaca IEX stock events, then test same-feed historical equality.

This is intentionally a research-only collector.  It never submits orders and
does not share event identity with ThetaData.  Credentials are read only from
``APCA_API_KEY_ID`` / ``APCA_API_SECRET_KEY`` (or their ``ALPACA_*`` aliases).
"""

import argparse
import asyncio
import collections
import datetime as dt
import json
import os
from pathlib import Path
import time
import urllib.parse
import urllib.request

import websockets


SYMBOLS = (
    "SPY,QQQ,IWM,DIA,HYG,TLT,GLD,VXX,AAPL,MSFT,NVDA,AMD,TSLA,AMZN,META,"
    "GOOGL,NFLX,AVGO,PLTR,XLF"
).split(",")
WS_URL = "wss://stream.data.alpaca.markets/v2/iex"
REST_ROOT = "https://data.alpaca.markets/v2/stocks"


def utc_now():
    return dt.datetime.now(dt.timezone.utc).isoformat(timespec="microseconds").replace("+00:00", "Z")


def credentials():
    key = (os.environ.get("APCA_API_KEY_ID") or os.environ.get("ALPACA_API_KEY_ID")
           or os.environ.get("ALPACA_CHESTNUT_API_KEY"))
    secret = (os.environ.get("APCA_API_SECRET_KEY") or os.environ.get("ALPACA_API_SECRET_KEY")
              or os.environ.get("ALPACA_CHESTNUT_API_SECRET"))
    if not key or not secret:
        raise SystemExit("Alpaca credentials are not present in the environment")
    return key, secret


def event_key(kind, event):
    # These are the documented Alpaca IEX event fields.  Keeping only the
    # feed-level payload avoids comparing receipt time or websocket framing.
    fields = {
        "T": ("S", "t", "i", "x", "p", "s", "c", "z"),
        "Q": ("S", "t", "bx", "bp", "bs", "ax", "ap", "as", "c", "z"),
    }[kind]
    return json.dumps([kind, *[(field, event.get(field)) for field in fields]],
                      separators=(",", ":"), sort_keys=True)


def historical_events(kind, symbols, start, end, key, secret):
    resource = "trades" if kind == "T" else "quotes"
    query = {
        "symbols": ",".join(symbols), "feed": "iex", "start": start,
        "end": end, "sort": "asc", "limit": "10000",
    }
    result = []
    while True:
        request = urllib.request.Request(
            f"{REST_ROOT}/{resource}?{urllib.parse.urlencode(query)}",
            headers={"APCA-API-KEY-ID": key, "APCA-API-SECRET-KEY": secret},
        )
        with urllib.request.urlopen(request, timeout=60) as response:
            payload = json.loads(response.read().decode("utf-8"))
        for symbol, rows in payload.get(resource, {}).items():
            for row in rows:
                row = dict(row)
                row["S"] = symbol
                result.append(row)
        token = payload.get("next_page_token")
        if not token:
            return result
        query["page_token"] = token


async def capture(out_dir, symbols, duration):
    key, secret = credentials()
    events_path = out_dir / "events.ndjson"
    receipt_path = out_dir / "receipt.json"
    accepted = []
    counts = collections.Counter()
    started = utc_now()
    async with websockets.connect(WS_URL, max_size=None, ping_interval=20, ping_timeout=20) as websocket:
        connected = json.loads(await asyncio.wait_for(websocket.recv(), timeout=15))
        if not any(item.get("msg") == "connected" for item in connected):
            raise RuntimeError(f"Alpaca websocket did not acknowledge connection: {connected!r}")
        await websocket.send(json.dumps({"action": "auth", "key": key, "secret": secret}))
        auth = json.loads(await asyncio.wait_for(websocket.recv(), timeout=15))
        if not any(item.get("msg") == "authenticated" for item in auth):
            raise RuntimeError(f"Alpaca websocket authentication failed: {auth!r}")
        await websocket.send(json.dumps({"action": "subscribe", "trades": symbols, "quotes": symbols}))
        subscription = json.loads(await asyncio.wait_for(websocket.recv(), timeout=15))
        if not any(item.get("T") == "subscription" for item in subscription):
            raise RuntimeError(f"Alpaca subscription was not acknowledged: {subscription!r}")
        subscribed = utc_now()
        deadline = time.monotonic() + duration
        with events_path.open("w", encoding="utf-8") as handle:
            while time.monotonic() < deadline:
                try:
                    batch = json.loads(await asyncio.wait_for(websocket.recv(), timeout=5))
                except asyncio.TimeoutError:
                    continue
                received_at = utc_now()
                for event in batch:
                    kind = str(event.get("T", "")).upper()
                    if kind not in ("T", "Q") or event.get("S") not in symbols:
                        continue
                    handle.write(json.dumps({"received_at": received_at, "event": event}, separators=(",", ":")) + "\n")
                    accepted.append((kind, event))
                    counts[kind] += 1
    receipt_path.write_text(json.dumps({
        "schema_version": 1, "provider": "alpaca", "feed": "iex", "symbols": symbols,
        "started_at": started, "subscribed_at": subscribed, "ended_at": utc_now(),
        "event_counts": dict(counts), "websocket": WS_URL,
    }, indent=2) + "\n", encoding="utf-8")
    # The IEX REST feed can lag the websocket briefly.  This pause is evidence
    # hygiene, not a source transformation.
    await asyncio.sleep(35)
    summary = {"schema_version": 1, "provider": "alpaca", "feed": "iex", "symbols": symbols,
               "status": "INCONCLUSIVE", "classes": {}}
    for kind, label in (("T", "trades"), ("Q", "quotes")):
        live = [event for event_kind, event in accepted if event_kind == kind]
        if not live:
            summary["classes"][label] = {"status": "INCONCLUSIVE", "reason": "no captured live events"}
            continue
        times = [event["t"] for event in live]
        live_counter = collections.Counter(event_key(kind, event) for event in live)
        # Alpaca's historical IEX endpoint is eventually, rather than
        # instantaneously, complete after a websocket event.  Retry a failed
        # *identical* request before classifying an end-of-window event as a
        # feed mismatch; preserve the final attempt count in the evidence.
        for attempt in range(1, 4):
            history = historical_events(kind, symbols, min(times), max(times), key, secret)
            history_counter = collections.Counter(event_key(kind, event) for event in history)
            live_only = live_counter - history_counter
            history_only = history_counter - live_counter
            if (not live_only and not history_only) or attempt == 3:
                break
            await asyncio.sleep(30)
        passed = not live_only and not history_only
        summary["classes"][label] = {
            "status": "PASS" if passed else "FAIL", "live_events": sum(live_counter.values()),
            "historical_events": sum(history_counter.values()), "live_only_events": sum(live_only.values()),
            "historical_only_events": sum(history_only.values()), "start": min(times), "end": max(times),
            "historical_fetch_attempts": attempt,
        }
    statuses = [value["status"] for value in summary["classes"].values()]
    summary["status"] = "PASS" if statuses and all(value == "PASS" for value in statuses) else "FAIL"
    (out_dir / "summary.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    return summary


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--out-root", required=True)
    parser.add_argument("--duration-seconds", type=int, default=720)
    parser.add_argument("--symbols", default=",".join(SYMBOLS))
    args = parser.parse_args()
    run_id = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    out_dir = Path(args.out_root) / dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%d") / run_id
    out_dir.mkdir(parents=True, exist_ok=False)
    summary = asyncio.run(capture(out_dir, args.symbols.split(","), args.duration_seconds))
    print(json.dumps({"run_dir": str(out_dir), **summary}, indent=2))
    return 0 if summary["status"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
