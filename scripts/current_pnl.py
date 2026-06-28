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

Usage: current_pnl.py [all|alpaca|venturevd|sim]   (default all)
"""
import glob
import json
import os
import re
import sqlite3
import subprocess
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
REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))


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
        positions = get("https://paper-api.alpaca.markets/v2/positions", key, secret)
        equity = float(acct["equity"])
        last_equity = float(acct["last_equity"])
        cash = float(acct.get("cash", 0.0))
        buying_power = float(acct.get("buying_power", 0.0))
        pnl = equity - last_equity
        unrealized = sum(float(p.get("unrealized_intraday_pl")
                               or p.get("unrealized_pl")
                               or 0.0)
                         for p in positions)
        realized = pnl - unrealized
        gross_mv = sum(abs(float(p.get("market_value") or 0.0))
                       for p in positions)
        long_positions = sum(1 for p in positions if float(p["qty"]) > 0)
        short_positions = sum(1 for p in positions if float(p["qty"]) < 0)
        pos = ", ".join(f"{p['symbol']}:{p['qty']}" for p in positions) or "flat"
        stats = episode_stats(today_fills(key, secret), positions)
        stats.update({
            "equity": equity,
            "last_equity": last_equity,
            "cash": cash,
            "buying_power": buying_power,
            "unrealized": unrealized,
            "realized_est": realized,
            "gross_mv": gross_mv,
            "open_positions": len(positions),
            "long_positions": long_positions,
            "short_positions": short_positions,
        })
        return (name, pnl, stats, pos)
    except Exception as e:  # noqa: BLE001 — report row, never crash the table
        return (name, None, {"trades": "?", "pct_in_mkt": 0.0,
                             "avg_trade_min": None, "fills": 0,
                             "equity": None, "last_equity": None,
                             "cash": None, "buying_power": None,
                             "unrealized": None, "realized_est": None,
                             "gross_mv": None, "open_positions": 0,
                             "long_positions": 0, "short_positions": 0},
                f"({type(e).__name__})")


def fmt_money(value):
    return f"{value:+,.2f}" if value is not None else "n/a"


def fmt_plain_money(value):
    return f"{value:,.2f}" if value is not None else "n/a"


def latest_sim_store():
    today = datetime.now(ET).date().isoformat()
    pattern = os.path.join(
        REPO_ROOT, "live_runtime", f"sim-vt-session-{today}*", "sim-broker.db")
    candidates = []
    for path in glob.glob(pattern):
        if os.path.getsize(path) <= 0:
            continue
        try:
            facts_db = os.path.join(os.path.dirname(path), "facts.db")
            fact_ts = None
            if os.path.exists(facts_db):
                with sqlite3.connect(facts_db) as conn:
                    row = conn.execute(
                        "select max(occurred_at) from facts"
                    ).fetchone()
                fact_ts = row[0] if row else None
            with sqlite3.connect(path) as conn:
                row = conn.execute(
                    "select updated_at from sim_journal where id = 'main'"
                ).fetchone()
            journal_ts = row[0] if row else None
            if fact_ts or journal_ts:
                candidates.append((fact_ts or "", journal_ts or "", path))
        except sqlite3.Error:
            continue
    return max(candidates)[2] if candidates else None


def sim_counts(facts_db):
    if not os.path.exists(facts_db):
        return {"fills": 0, "trades": "0", "pct_in_mkt": 0.0,
                "avg_trade_min": None}
    session_open = datetime.combine(datetime.now(ET).date(), dtime(9, 30), ET)
    session_close = datetime.combine(datetime.now(ET).date(), dtime(16, 0), ET)
    now = min(datetime.now(ET), session_close)
    with sqlite3.connect(facts_db) as conn:
        fills = conn.execute(
            "select count(*) from facts where fact_type = ':fact/fill-observed'"
        ).fetchone()[0]
        rows = conn.execute(
            """
            select fact_type, occurred_at
            from facts
            where fact_type in (':fact/position-lot-opened',
                                ':fact/position-lot-closed')
            order by occurred_at, "offset"
            """
        ).fetchall()
    open_lots = 0
    episodes = []
    in_mkt_since = None
    for fact_type, occurred_at in rows:
        ts = datetime.fromisoformat(occurred_at.replace("Z", "+00:00")).astimezone(ET)
        was_flat = open_lots == 0
        if fact_type == ":fact/position-lot-opened":
            open_lots += 1
        else:
            open_lots = max(0, open_lots - 1)
        is_flat = open_lots == 0
        if was_flat and not is_flat and in_mkt_since is None:
            in_mkt_since = ts
        elif not was_flat and is_flat and in_mkt_since is not None:
            episodes.append((in_mkt_since, ts))
            in_mkt_since = None
    open_episode = in_mkt_since is not None
    if open_episode:
        episodes.append((in_mkt_since, now))
    in_mkt = sum(max(0.0, (b - a).total_seconds()) for a, b in episodes)
    session = max(1.0, (now - session_open).total_seconds())
    completed = episodes[:-1] if open_episode else episodes
    avg_min = (sum((b - a).total_seconds() for a, b in completed)
               / len(completed) / 60) if completed else None
    return {
        "fills": int(fills or 0),
        "trades": f"{len(completed)}+1o" if open_episode else str(len(completed)),
        "pct_in_mkt": min(100.0, 100.0 * in_mkt / session),
        "avg_trade_min": avg_min,
    }


def sim_account_row():
    store = os.environ.get("SIM_STORE_PATH") or latest_sim_store()
    if not store:
        return None
    basilisp = os.environ.get(
        "BASILISP_BIN",
        os.path.expanduser(
            "~/contracting/upwork/steven-tran/SteveTrading/ref/Data-Preprocessor/.venv/bin/basilisp"),
    )
    env = dict(os.environ)
    env["SIM_STORE_PATH"] = store
    env.setdefault("SIM_ACCOUNT_ID", "account/sim/vol-term")
    pythonpath_file = os.path.join(REPO_ROOT, ".nrepl-pythonpath")
    if "PYTHONPATH" not in env and os.path.exists(pythonpath_file):
        env["PYTHONPATH"] = open(pythonpath_file).read().strip()
    proc = subprocess.run(
        [basilisp, "run", os.path.join(REPO_ROOT, "scripts/current_sim_account_state.lpy")],
        cwd=REPO_ROOT,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
        check=True,
    )
    line = [l for l in proc.stdout.splitlines() if "\t" in l][-1]
    (account_id, cash_delta, realized, unrealized, gross_mv, open_orders,
     open_positions, longs, shorts, net_positions, _unmarked) = line.split("\t", 10)
    starting_equity = float(os.environ.get("SIM_STARTING_EQUITY", "100000"))
    realized = float(realized or 0.0)
    unrealized = float(unrealized or 0.0)
    pnl = realized + unrealized
    counts = sim_counts(os.path.join(os.path.dirname(store), "facts.db"))
    stats = {
        "equity": starting_equity + pnl,
        "last_equity": starting_equity,
        "cash": starting_equity + float(cash_delta or 0.0),
        "buying_power": starting_equity + float(cash_delta or 0.0),
        "unrealized": unrealized,
        "realized_est": realized,
        "gross_mv": float(gross_mv or 0.0),
        "open_positions": int(open_positions or 0),
        "long_positions": int(longs or 0),
        "short_positions": int(shorts or 0),
        **counts,
    }
    label = "SIM-VOLTERM"
    pos = net_positions if int(open_positions or 0) else "flat"
    return (label, pnl, stats, pos)


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
    if group in ("all", "sim"):
        sim_row = sim_account_row()
        if sim_row:
            rows.append(sim_row)

    now = datetime.now(ET).strftime("%Y-%m-%d %H:%M:%S %Z")
    print(f"Current-day P&L — {now}")
    print(
        f"  {'ACCOUNT':10} {'DAY P&L':>11} {'REALZD*':>11} {'UNREAL':>11} "
        f"{'EQUITY':>12} {'CASH':>12} {'GROSS MV':>12} {'POS':>3} "
        f"{'L/S':>5} {'TRADES':>7} {'%MKT':>6} {'AVG':>7} {'FILLS':>5}  POSITION"
    )
    print("  " + "-" * 150)
    totals = defaultdict(float)
    for name, pnl, s, pos in sorted(rows, key=lambda r: -(r[1] or 0)):
        avg = f"{s['avg_trade_min']:.1f}m" if s["avg_trade_min"] else "-"
        print(
            f"  {name:10} {fmt_money(pnl):>11} "
            f"{fmt_money(s['realized_est']):>11} "
            f"{fmt_money(s['unrealized']):>11} "
            f"{fmt_plain_money(s['equity']):>12} "
            f"{fmt_plain_money(s['cash']):>12} "
            f"{fmt_plain_money(s['gross_mv']):>12} "
            f"{s['open_positions']:>3} "
            f"{s['long_positions']}/{s['short_positions']:<3} "
            f"{s['trades']:>7} {s['pct_in_mkt']:>5.0f}% "
            f"{avg:>7} {s['fills']:>5}  {pos}"
        )
        totals["pnl"] += pnl or 0.0
        totals["realized"] += s["realized_est"] or 0.0
        totals["unrealized"] += s["unrealized"] or 0.0
        totals["equity"] += s["equity"] or 0.0
        totals["cash"] += s["cash"] or 0.0
        totals["gross_mv"] += s["gross_mv"] or 0.0
        totals["positions"] += s["open_positions"]
        totals["fills"] += s["fills"]
    print("  " + "-" * 150)
    print(
        f"  {'TOTAL':10} {totals['pnl']:>+11,.2f} "
        f"{totals['realized']:>+11,.2f} "
        f"{totals['unrealized']:>+11,.2f} "
        f"{totals['equity']:>12,.2f} "
        f"{totals['cash']:>12,.2f} "
        f"{totals['gross_mv']:>12,.2f} "
        f"{int(totals['positions']):>3} {'':5} {'':>7} {'':>6} {'':>7} "
        f"{int(totals['fills']):>5}"
    )
    print("  *REALZD is estimated as day P&L minus open-position unrealized P&L.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
