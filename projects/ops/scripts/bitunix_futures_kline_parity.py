#!/usr/bin/env python3
"""Read-only Bitunix futures completed-1m-kline live/history parity study.

The public WebSocket pushes the in-progress one-minute market kline every
500 ms.  This collector freezes the last update from each completed minute and
compares its OHLC and base/quote volume with Bitunix's public futures kline
history.  It makes no raw-trade or depth-parity claim.
"""

import argparse
import asyncio
import collections
import datetime as dt
import json
from pathlib import Path
import time
import urllib.parse
import urllib.request

import websockets
from websockets.exceptions import ConnectionClosed


WS_URL = "wss://fapi.bitunix.com/public/"
REST_URL = "https://fapi.bitunix.com/api/v1/futures/market/kline"
DEFAULT_SYMBOLS = "BTCUSDT,ETHUSDT,SOLUSDT"
MINUTE_MS = 60_000


def utc_now():
    return dt.datetime.now(dt.timezone.utc).isoformat(timespec="microseconds").replace("+00:00", "Z")


def canonical_live(symbol, bucket, data):
    # REST calls the coin volume quoteVol and the quote-currency volume
    # baseVol; the WebSocket calls those b and q respectively.
    return {"symbol": symbol, "time": bucket, "open": data["o"], "high": data["h"],
            "low": data["l"], "close": data["c"], "quoteVol": data["b"], "baseVol": data["q"]}


def canonical_history(symbol, row):
    return {"symbol": symbol, "time": int(row["time"]), "open": row["open"], "high": row["high"],
            "low": row["low"], "close": row["close"], "quoteVol": row["quoteVol"],
            "baseVol": row["baseVol"]}


def history(symbol, start, end):
    query = urllib.parse.urlencode({"symbol": symbol, "interval": "1m", "type": "LAST_PRICE",
                                    "startTime": start, "endTime": end, "limit": 200})
    request = urllib.request.Request(REST_URL + "?" + query,
                                     headers={"User-Agent": "Mozilla/5.0", "Accept": "application/json"})
    with urllib.request.urlopen(request, timeout=45) as response:
        payload = json.loads(response.read().decode("utf-8"))
    if payload.get("code") != 0:
        raise RuntimeError(f"Bitunix history returned code {payload.get('code')}: {payload.get('msg')}")
    return [canonical_history(symbol, row) for row in payload.get("data", [])]


async def capture(symbols, duration, out_dir):
    events = out_dir / "events.ndjson"
    latest, event_counts = {}, collections.Counter()
    reconnects = 0
    started = utc_now()
    deadline = time.monotonic() + duration
    with events.open("w", encoding="utf-8") as handle:
        while time.monotonic() < deadline:
            try:
                async with websockets.connect(WS_URL, ping_interval=None, max_size=None) as websocket:
                    await websocket.send(json.dumps({"op": "subscribe", "args": [
                        {"symbol": symbol, "ch": "market_kline_1min"} for symbol in symbols]}))
                    while time.monotonic() < deadline:
                        try:
                            raw = await asyncio.wait_for(websocket.recv(), timeout=10)
                        except asyncio.TimeoutError:
                            await websocket.send(json.dumps({"op": "ping", "ping": int(time.time())}))
                            continue
                        received = utc_now()
                        message = json.loads(raw)
                        if message.get("ch") != "market_kline_1min" or message.get("symbol") not in symbols:
                            continue
                        symbol = message["symbol"]
                        bucket = int(message["ts"]) // MINUTE_MS * MINUTE_MS
                        candle = canonical_live(symbol, bucket, message["data"])
                        latest[(symbol, bucket)] = candle
                        event_counts[symbol] += 1
                        handle.write(json.dumps({"received_at": received, "source_timestamp": message["ts"],
                                                 "candle": candle}, separators=(",", ":")) + "\n")
            except (ConnectionClosed, OSError):
                reconnects += 1
                if time.monotonic() < deadline:
                    await asyncio.sleep(1)
    complete_before = int(time.time() * 1000) // MINUTE_MS * MINUTE_MS
    completed = {key: value for key, value in latest.items() if key[1] < complete_before}
    (out_dir / "receipt.json").write_text(json.dumps({
        "schema_version": 1, "provider": "bitunix", "market": "futures", "symbols": symbols,
        "started_at": started, "ended_at": utc_now(), "websocket": WS_URL,
        "event_counts": dict(event_counts), "reconnects": reconnects, "completed_candles": len(completed),
        "contract": "last websocket update for each completed market_kline_1min candle",
    }, indent=2) + "\n", encoding="utf-8")
    return completed


def compare(completed, symbols):
    historical = {}
    for symbol in symbols:
        rows = [candle for (name, _), candle in completed.items() if name == symbol]
        if not rows:
            continue
        for candle in history(symbol, min(row["time"] for row in rows),
                              max(row["time"] for row in rows) + MINUTE_MS):
            historical[(symbol, candle["time"])] = candle
    missing = different = live_gap = 0
    examples = []
    for symbol in symbols:
        points = sorted(bucket for name, bucket in completed if name == symbol)
        if points:
            expected = set(range(points[0], points[-1] + MINUTE_MS, MINUTE_MS))
            live_gap += len(expected - set(points))
    for key, live in completed.items():
        other = historical.get(key)
        if other is None:
            missing += 1
            if len(examples) < 10:
                examples.append({"kind": "missing_historical", "key": key})
        elif other != live:
            different += 1
            if len(examples) < 10:
                examples.append({"kind": "different_fields", "key": key, "live": live, "historical": other})
    return {"status": "PASS" if completed and not missing and not different and not live_gap else "FAIL",
            "compared_completed_candles": len(completed), "missing_historical": missing,
            "different_candles": different, "live_missing_minute_buckets": live_gap, "examples": examples,
            "definition": "Exact completed Bitunix futures LAST_PRICE 1m kline equality; no raw-trade/depth claim."}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--out-root", required=True)
    parser.add_argument("--duration-seconds", type=int, default=600)
    parser.add_argument("--symbols", default=DEFAULT_SYMBOLS)
    args = parser.parse_args()
    symbols = args.symbols.split(",")
    run_id = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    out_dir = Path(args.out_root) / dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%d") / run_id
    out_dir.mkdir(parents=True, exist_ok=False)
    completed = asyncio.run(capture(symbols, args.duration_seconds, out_dir))
    summary = {"schema_version": 1, "provider": "bitunix", "market": "futures", "symbols": symbols,
               **compare(completed, symbols)}
    (out_dir / "summary.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"run_dir": str(out_dir), **summary}, indent=2))
    return 0 if summary["status"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
