#!/usr/bin/env python3
"""Read-only Binance USD-M Futures completed-kline polling/history parity study.

This is deliberately a REST-polling contract.  It is not a Binance WebSocket
parity claim: the public stream must be independently reachable and tested
before it can be admitted as a live-stream source.
"""

import argparse
import datetime as dt
import json
from pathlib import Path
import time
import urllib.parse
import urllib.request


REST_URL = "https://fapi.binance.com/fapi/v1/klines"
DEFAULT_SYMBOLS = "BTCUSDT,ETHUSDT,SOLUSDT"


def utc_now():
    return dt.datetime.now(dt.timezone.utc).isoformat(timespec="microseconds").replace("+00:00", "Z")


def fetch(symbol, start=None, end=None):
    query = {"symbol": symbol, "interval": "1m", "limit": 1000}
    if start is not None:
        query["startTime"] = start
    if end is not None:
        query["endTime"] = end
    request = urllib.request.Request(REST_URL + "?" + urllib.parse.urlencode(query),
                                     headers={"User-Agent": "Mozilla/5.0", "Accept": "application/json"})
    with urllib.request.urlopen(request, timeout=45) as response:
        return json.loads(response.read().decode("utf-8"))


def canonical(symbol, row):
    # Keep every documented REST kline field except Binance's ignored final
    # element; unlike a derived OHLC-only check, this detects volume/count and
    # taker-flow revision as well.
    return {"symbol": symbol, "open_time": row[0], "open": row[1], "high": row[2], "low": row[3],
            "close": row[4], "base_volume": row[5], "close_time": row[6], "quote_volume": row[7],
            "trade_count": row[8], "taker_buy_base": row[9], "taker_buy_quote": row[10]}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--out-root", required=True)
    parser.add_argument("--duration-seconds", type=int, default=600)
    parser.add_argument("--poll-seconds", type=float, default=2.0)
    parser.add_argument("--settle-seconds", type=int, default=15)
    parser.add_argument("--completion-lag-seconds", type=float, default=10.0,
                        help="Minimum wall-clock delay after close_time before admitting a live candle.")
    parser.add_argument("--symbols", default=DEFAULT_SYMBOLS)
    args = parser.parse_args()
    symbols = args.symbols.split(",")
    run_id = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    out_dir = Path(args.out_root) / dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%d") / run_id
    out_dir.mkdir(parents=True, exist_ok=False)
    captured, conflicts = {}, []
    started = utc_now()
    deadline = time.monotonic() + args.duration_seconds
    while time.monotonic() < deadline:
        receipt_ms = int(time.time() * 1000)
        for symbol in symbols:
            # A candle whose documented close timestamp is already behind the
            # receipt watermark is completed at this live REST observation.
            for row in fetch(symbol)[-3:]:
                candle = canonical(symbol, row)
                if candle["close_time"] + int(args.completion_lag_seconds * 1000) >= receipt_ms:
                    continue
                key = (symbol, candle["open_time"])
                prior = captured.get(key)
                if prior and prior["candle"] != candle:
                    conflicts.append({"key": key, "first": prior["candle"], "later": candle})
                else:
                    captured.setdefault(key, {"candle": candle, "first_receipt_at": utc_now()})
        time.sleep(args.poll_seconds)
    (out_dir / "receipt.json").write_text(json.dumps({
        "schema_version": 1, "provider": "binance", "market": "usds-m-futures", "symbols": symbols,
        "started_at": started, "ended_at": utc_now(), "poll_seconds": args.poll_seconds,
        "completion_lag_seconds": args.completion_lag_seconds,
        "contract": "live REST polling of completed /fapi/v1/klines 1m candles", "raw_stream_claim": "none",
    }, indent=2) + "\n", encoding="utf-8")
    (out_dir / "live-completed-candles.json").write_text(json.dumps(list(captured.values()), indent=2) + "\n", encoding="utf-8")
    time.sleep(args.settle_seconds)

    historical = {}
    for symbol in symbols:
        rows = [entry["candle"] for key, entry in captured.items() if key[0] == symbol]
        if not rows:
            continue
        for row in fetch(symbol, min(row["open_time"] for row in rows),
                         max(row["open_time"] for row in rows) + 60_000):
            candle = canonical(symbol, row)
            historical[(symbol, candle["open_time"])] = candle
    missing = different = 0
    examples = []
    for key, entry in captured.items():
        other = historical.get(key)
        if other is None:
            missing += 1
            if len(examples) < 10:
                examples.append({"kind": "missing_historical", "key": key})
        elif other != entry["candle"]:
            different += 1
            if len(examples) < 10:
                examples.append({"kind": "different_fields", "key": key,
                                 "live": entry["candle"], "historical": other})
    summary = {"schema_version": 1, "provider": "binance", "market": "usds-m-futures",
               "symbols": symbols, "status": "PASS" if captured and not conflicts and not missing and not different else "FAIL",
               "compared_completed_candles": len(captured), "missing_historical": missing,
               "different_candles": different, "live_completed_candle_conflicts": len(conflicts),
               "examples": examples,
               "definition": ("Exact Binance Futures REST 1m kline equality after the declared "
                              "post-close completion watermark; no WebSocket parity claim.")}
    (out_dir / "summary.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"run_dir": str(out_dir), **summary}, indent=2))
    return 0 if summary["status"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
