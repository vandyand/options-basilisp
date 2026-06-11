#!/usr/bin/env python3
"""Current-day P&L + activity stats for the SteveTrading paper accounts.

Engine-agnostic (reads broker truth only). Stdlib-only. Read-only.

Per account:
  day P&L   = equity - last_equity (includes unrealized)
  trades    = completed in-market episodes today (any position != 0 ->
              back to fully flat), +1 marked (open) if currently in market
  % in mkt  = fraction of the regular session so far (09:30 ET -> min(now,
              16:00)) with any nonzero position
  avg trade = mean completed-episode duration (minutes)

Usage: current_pnl.py [all|alpaca|venturevd]   (default all)
"""
import json
import os
import re
import sys
import urllib.request
from collections import defaultdict
from datetime import datetime, time as dtime, timedelta, timezone
from zoneinfo import ZoneInfo

ET = ZoneInfo("America/New_York")
REF_ENV = os.path.expanduser(
    "~/contracting/upwork/steven-tran/SteveTrading/ref/Data-Preprocessor/.env")
BASHRC = os.path.expanduser("~/.bashrc")
BOTS = ["CHESTNUT", "LYNX", "MOOSE", "PARROT", "OAK", "DOLPHIN"]


def env_creds(text, prefix):
    k = re.search(rf"^(?:export )?{prefix}_API_KEY=(.+)$", text, re.M)
    s = re.search(rf"^(?:export )?{prefix}_API_SECRET=(.+)$", text, re.M)
    return (k.group(1).strip(), s.group(1).strip()) if k and s else None


def get(url, key, secret):
    req = urllib.request.Request(url)
    req.add_header("APCA-API-KEY-ID", key)
    req.add_header("APCA-API-SECRET-KEY", secret)
    req.add_header("Accept", "application/json")
    with urllib.request.urlopen(req, timeout=15) as r:
        return json.loads(r.read().decode())


def today_fills(key, secret):
    today_et = datetime.now(ET).date().isoformat()
    fills, page_token = [], None
    while True:
        url = (f"https://paper-api.alpaca.markets/v2/account/activities/FILL"
               f"?date={today_et}&page_size=100")
        if page_token:
            url += f"&page_token={page_token}"
        batch = get(url, key, secret)
        if not batch:
            break
        fills.extend(batch)
        if len(batch) < 100:
            break
        page_token = batch[-1]["id"]
    fills.sort(key=lambda f: f["transaction_time"])
    return fills


def episode_stats(fills, open_positions):
    """In-market episodes from today's fills (any symbol nonzero)."""
    session_open = datetime.combine(datetime.now(ET).date(), dtime(9, 30), ET)
    session_close = datetime.combine(datetime.now(ET).date(), dtime(16, 0), ET)
    now = min(datetime.now(ET), session_close)
    qty = defaultdict(float)
    # If positions exist that today's fills don't explain (overnight carry),
    # seed in-market from the session open.
    explained = defaultdict(float)
    for f in fills:
        side = 1 if f["side"].startswith("buy") else -1
        explained[f["symbol"]] += side * float(f["qty"])
    carry = any(abs(float(p["qty"]) - explained.get(p["symbol"], 0.0)) > 1e-9
                for p in open_positions)

    episodes, in_mkt_since = [], (session_open if carry else None)
    for f in fills:
        t = datetime.fromisoformat(f["transaction_time"]).astimezone(ET)
        side = 1 if f["side"].startswith("buy") else -1
        was_flat = all(abs(q) < 1e-9 for q in qty.values())
        qty[f["symbol"]] += side * float(f["qty"])
        is_flat = all(abs(q) < 1e-9 for q in qty.values())
        if was_flat and not is_flat and in_mkt_since is None:
            in_mkt_since = t
        elif not was_flat and is_flat and in_mkt_since is not None:
            episodes.append((in_mkt_since, t))
            in_mkt_since = None
    open_episode = in_mkt_since is not None
    if open_episode:
        episodes.append((in_mkt_since, now))

    in_mkt = sum((b - a).total_seconds() for a, b in episodes)
    session = max(1.0, (now - session_open).total_seconds())
    completed = episodes[:-1] if open_episode else episodes
    avg_min = (sum((b - a).total_seconds() for a, b in completed)
               / len(completed) / 60) if completed else None
    n = len(completed)
    return {
        "trades": f"{n}+1o" if open_episode else str(n),
        "pct_in_mkt": min(100.0, 100.0 * in_mkt / session),
        "avg_trade_min": avg_min,
        "fills": len(fills),
    }


def account_row(name, key, secret):
    try:
        acct = get("https://paper-api.alpaca.markets/v2/account", key, secret)
        pnl = float(acct["equity"]) - float(acct["last_equity"])
        positions = get("https://paper-api.alpaca.markets/v2/positions", key, secret)
        pos = ", ".join(f"{p['symbol']}:{p['qty']}" for p in positions) or "flat"
        stats = episode_stats(today_fills(key, secret), positions)
        return (name, pnl, stats, pos)
    except Exception as e:  # noqa: BLE001 — report row, never crash the table
        return (name, None, {"trades": "?", "pct_in_mkt": 0.0,
                             "avg_trade_min": None, "fills": 0}, f"({type(e).__name__})")


def main():
    group = (sys.argv[1] if len(sys.argv) > 1 else "all").lower()
    rows = []
    if group in ("all", "alpaca"):
        ref = open(REF_ENV).read()
        for bot in BOTS:
            creds = env_creds(ref, f"ALPACA_{bot}")
            if creds:
                rows.append(account_row(bot, *creds))
    if group in ("all", "venturevd"):
        creds = env_creds(open(BASHRC).read(), "ALPACA_VENTUREVD")
        if creds:
            rows.append(account_row("VENTUREVD", *creds))

    now = datetime.now(ET).strftime("%Y-%m-%d %H:%M:%S %Z")
    print(f"Current-day P&L — {now}")
    print(f"  {'ACCOUNT':10} {'TODAY P&L':>11} {'TRADES':>7} {'%MKT':>6} "
          f"{'AVG-TRADE':>9} {'FILLS':>5}  POSITION")
    print("  " + "-" * 92)
    total = 0.0
    for name, pnl, s, pos in sorted(rows, key=lambda r: -(r[1] or 0)):
        pnl_s = f"{pnl:+,.2f}" if pnl is not None else "n/a"
        avg = f"{s['avg_trade_min']:.1f}m" if s["avg_trade_min"] else "-"
        print(f"  {name:10} {pnl_s:>11} {s['trades']:>7} "
              f"{s['pct_in_mkt']:>5.0f}% {avg:>9} {s['fills']:>5}  {pos}")
        total += pnl or 0.0
    print("  " + "-" * 92)
    print(f"  {'TOTAL':10} {total:>+11,.2f}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
