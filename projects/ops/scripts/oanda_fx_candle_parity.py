#!/usr/bin/env python3
"""Read-only OANDA completed-candle live/history parity evidence collector.

This intentionally tests the only comparable OANDA v20 contract: a completed
bid/ask candle fetched live through ``pricing/candles/latest`` against the
same completed candle fetched later through instrument candle history.  It
does not claim parity for the raw pricing stream, which OANDA documents as a
connection-windowed stream capped at four updates per second.
"""

import argparse
import datetime as dt
import json
import os
from pathlib import Path
import time
import urllib.parse
import urllib.request


DEFAULT_INSTRUMENTS = "EUR_USD,GBP_USD,USD_JPY,USD_CHF,USD_CAD,AUD_USD,NZD_USD"
BASE_URLS = {
    "practice": "https://api-fxpractice.oanda.com",
    "live": "https://api-fxtrade.oanda.com",
}


def utc_now():
    return dt.datetime.now(dt.timezone.utc).isoformat(timespec="microseconds").replace("+00:00", "Z")


def request_json(url, token):
    request = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}"})
    with urllib.request.urlopen(request, timeout=45) as response:
        return json.loads(response.read().decode("utf-8"))


def normalized_candle(instrument, granularity, candle):
    """Retain all model-relevant completed bid/ask candle fields."""
    return {
        "instrument": instrument,
        "granularity": granularity,
        "time": candle["time"],
        "bid": candle.get("bid"),
        "ask": candle.get("ask"),
        "volume": candle.get("volume"),
    }


def account_id(base_url, token):
    accounts = request_json(f"{base_url}/v3/accounts", token).get("accounts", [])
    if not accounts:
        raise RuntimeError("OANDA token has no accessible accounts")
    return accounts[0]["id"]


def live_completed_candles(base_url, account, token, instruments, granularities):
    specifications = ",".join(
        f"{instrument}:{granularity}:BA"
        for instrument in instruments for granularity in granularities
    )
    query = urllib.parse.urlencode({"candleSpecifications": specifications, "smooth": "false"})
    payload = request_json(f"{base_url}/v3/accounts/{account}/candles/latest?{query}", token)
    result = []
    for response in payload.get("latestCandles", []):
        instrument = response["instrument"]
        granularity = response["granularity"]
        for candle in response.get("candles", []):
            if candle.get("complete"):
                result.append(normalized_candle(instrument, granularity, candle))
    return result


def parse_time(value):
    return dt.datetime.fromisoformat(value.replace("Z", "+00:00"))


def historical_candles(base_url, account, token, instrument, granularity, start, end):
    # Extend the upper bound by one complete interval.  The result is then
    # filtered by exact live candle keys, so endpoint inclusivity cannot mask a
    # missing or differing captured candle.
    seconds = {"S5": 5, "M1": 60}[granularity]
    query = urllib.parse.urlencode({
        "price": "BA", "granularity": granularity, "from": start,
        "to": (parse_time(end) + dt.timedelta(seconds=seconds)).isoformat().replace("+00:00", "Z"),
        "smooth": "false", "includeFirst": "true",
    })
    payload = request_json(
        f"{base_url}/v3/accounts/{account}/instruments/{instrument}/candles?{query}", token
    )
    return [normalized_candle(instrument, granularity, candle)
            for candle in payload.get("candles", []) if candle.get("complete")]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--out-root", required=True)
    parser.add_argument("--environment", choices=BASE_URLS, default="practice")
    parser.add_argument("--duration-seconds", type=int, default=1800)
    parser.add_argument("--poll-seconds", type=float, default=2.0)
    parser.add_argument("--settle-seconds", type=int, default=15)
    parser.add_argument("--instruments", default=DEFAULT_INSTRUMENTS)
    parser.add_argument("--granularities", default="S5,M1", choices=["S5", "M1", "S5,M1"])
    args = parser.parse_args()

    token = os.environ.get("OANDA_API_KEY")
    if not token:
        raise SystemExit("OANDA_API_KEY is not present in the process environment")
    instruments = args.instruments.split(",")
    granularities = args.granularities.split(",")
    base_url = BASE_URLS[args.environment]
    run_id = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    out_dir = Path(args.out_root) / dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%d") / run_id
    out_dir.mkdir(parents=True, exist_ok=False)
    account = account_id(base_url, token)
    captured, conflicts = {}, []
    started = utc_now()
    deadline = time.monotonic() + args.duration_seconds
    while time.monotonic() < deadline:
        receipt = utc_now()
        for candle in live_completed_candles(base_url, account, token, instruments, granularities):
            key = (candle["instrument"], candle["granularity"], candle["time"])
            previous = captured.get(key)
            if previous and previous["candle"] != candle:
                conflicts.append({"key": key, "first": previous["candle"], "later": candle})
            else:
                captured.setdefault(key, {"candle": candle, "first_receipt_at": receipt})
        time.sleep(args.poll_seconds)
    (out_dir / "receipt.json").write_text(json.dumps({
        "schema_version": 1, "provider": "oanda", "environment": args.environment,
        "instruments": instruments, "granularities": granularities, "started_at": started,
        "ended_at": utc_now(), "poll_seconds": args.poll_seconds,
        "capture_contract": "completed OANDA pricing/candles/latest BA candles",
        "raw_stream_claim": "none",
    }, indent=2) + "\n", encoding="utf-8")
    (out_dir / "live-completed-candles.json").write_text(
        json.dumps(list(captured.values()), indent=2) + "\n", encoding="utf-8"
    )
    time.sleep(args.settle_seconds)

    historical = {}
    for instrument in instruments:
        for granularity in granularities:
            rows = [entry["candle"] for key, entry in captured.items()
                    if key[:2] == (instrument, granularity)]
            if not rows:
                continue
            for candle in historical_candles(base_url, account, token, instrument, granularity,
                                             min(row["time"] for row in rows), max(row["time"] for row in rows)):
                historical[(instrument, granularity, candle["time"])] = candle

    compared = missing = different = 0
    examples = []
    for key, entry in captured.items():
        compared += 1
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
    status = "PASS" if compared and not missing and not different and not conflicts else "FAIL"
    summary = {
        "schema_version": 1, "provider": "oanda", "environment": args.environment,
        "status": status, "compared_completed_candles": compared,
        "missing_historical": missing, "different_candles": different,
        "live_completed_candle_conflicts": len(conflicts), "examples": examples,
        "definition": "Exact complete bid/ask S5/M1 candle equality; no raw pricing-stream parity claim.",
    }
    (out_dir / "summary.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"run_dir": str(out_dir), **summary}, indent=2))
    return 0 if status == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
