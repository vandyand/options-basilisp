#!/usr/bin/env python3
"""Feature parity — Phase A (computation/replay parity).

Replays training-cache days through the LIVE FeatureEngine and diffs the
output against the training feature matrix, feature by feature. The live
engine gets exactly what it gets in production: Alpaca IEX 1-min bars
(seeded 200 deep before the open, proxies SPX=SPY*10 / VIX=VXX / TNX=TLT)
— but the TRAINING greeks grids, so grid-derived features test pure
computation parity while bar-derived features test computation + bar-source
(IEX vs GCS/SIP) skew combined.

Inputs (produced from cache/full_features_5yr_v3.npz on Lightning):
    parity/train_rows_apr13-17.npz   X (1950,918), spy_prices, day_ids, dates
    parity/train_grids_apr13-17.npz  grids (1950,6,21,8), day_ids

Run under the REF venv with REF on PYTHONPATH:
    cd Data-Preprocessor && .venv/bin/python3 \
        ../../stevetrading-basilisp/scripts/parity_replay.py

Writes parity/replay_results.npz (live X per day) and
parity/replay_report.json (per-feature buckets + stats), prints a summary.
"""
import json
import os
import re
import sys
import urllib.request
from collections import deque
from datetime import datetime, time as dtime, timedelta
from pathlib import Path
from zoneinfo import ZoneInfo

import numpy as np

REF = Path(os.path.expanduser(
    "~/contracting/upwork/steven-tran/SteveTrading/ref/Data-Preprocessor"))
PARITY = Path(os.path.expanduser("~/contracting/upwork/steven-tran/parity"))
BUNDLE = REF / "pipeline_data/live_model_chestnut_multihead"
ET = ZoneInfo("America/New_York")
SYMS = ["SPY", "HYG", "TLT", "VXX"]

sys.path.insert(0, str(REF))
from scripts_5yr.live.feature_engine import FeatureEngine  # noqa: E402


# --------------------------------------------------------------------------
# Alpaca historical bars (IEX — the live feed)
# --------------------------------------------------------------------------
def env_creds():
    text = (REF / ".env").read_text()
    k = re.search(r"^ALPACA_CHESTNUT_API_KEY=(.+)$", text, re.M).group(1).strip()
    s = re.search(r"^ALPACA_CHESTNUT_API_SECRET=(.+)$", text, re.M).group(1).strip()
    return k, s


def fetch_bars(sym, start_iso, end_iso, key, secret):
    bars, page = [], None
    while True:
        url = (f"https://data.alpaca.markets/v2/stocks/{sym}/bars"
               f"?timeframe=1Min&feed=iex&adjustment=raw&limit=10000"
               f"&start={start_iso}&end={end_iso}")
        if page:
            url += f"&page_token={page}"
        req = urllib.request.Request(url)
        req.add_header("APCA-API-KEY-ID", key)
        req.add_header("APCA-API-SECRET-KEY", secret)
        with urllib.request.urlopen(req, timeout=30) as r:
            doc = json.loads(r.read().decode())
        bars.extend(doc.get("bars") or [])
        page = doc.get("next_page_token")
        if not page:
            break
    out = {}
    for b in bars:
        t = datetime.fromisoformat(b["t"].replace("Z", "+00:00")).astimezone(ET)
        out[t] = {"time": t, "open": float(b["o"]), "high": float(b["h"]),
                  "low": float(b["l"]), "close": float(b["c"]),
                  "volume": float(b["v"]), "vwap": float(b.get("vw", b["c"])),
                  "trade_count": int(b.get("n", 0))}
    return out


# --------------------------------------------------------------------------
# Proxy rebuild — mirrors bridge rebuild-proxies! / data_fetcher._update_proxies
# --------------------------------------------------------------------------
def rebuild_proxies(buffers, sym):
    if sym == "SPY":
        tgt = buffers["SPX"]
        tgt.clear()
        for b in list(buffers["SPY"]):
            tgt.append({"time": b["time"], "open": b["open"] * 10,
                        "high": b["high"] * 10, "low": b["low"] * 10,
                        "close": b["close"] * 10, "volume": b["volume"],
                        "vwap": b.get("vwap", b["close"]) * 10,
                        "trade_count": b.get("trade_count", 0)})
    elif sym == "VXX":
        buffers["VIX"].clear()
        for b in list(buffers["VXX"]):
            buffers["VIX"].append(dict(b))
    elif sym == "TLT":
        buffers["TNX"].clear()
        for b in list(buffers["TLT"]):
            buffers["TNX"].append(dict(b))


def load_npz_dict(path, keys):
    d = np.load(path)
    return {k: d[k] for k in keys}


def main():
    rows = np.load(PARITY / "train_rows_apr13-17.npz", allow_pickle=True)
    grids_f = np.load(PARITY / "train_grids_apr13-17.npz")
    X_train, day_ids = rows["X"], rows["day_ids"]
    spy_train = rows["spy_prices"]
    dates = [str(d) for d in rows["dates"]]
    grids = grids_f["grids"]
    feature_names = json.loads((BUNDLE / "feature_names.json").read_text())
    hmm = load_npz_dict(BUNDLE / "hmm_model.npz",
                        ["means", "covars", "transmat", "startprob"])
    atoms = load_npz_dict(BUNDLE / "dictionary_atoms.npz",
                          ["components", "train_mean", "train_std"])
    stats = np.load(BUNDLE / "feature_stats.npz")
    train_std_global = stats["std"]

    key, secret = env_creds()
    d0 = datetime.strptime(dates[0], "%Y%m%d").date()
    dN = datetime.strptime(dates[-1], "%Y%m%d").date()
    start = (datetime.combine(d0, dtime(4, 0), ET) - timedelta(days=5))
    end = datetime.combine(dN, dtime(20, 0), ET)
    print(f"fetching IEX bars {start.date()} -> {end.date()} ...")
    fmt = "%Y-%m-%dT%H:%M:%SZ"
    all_bars = {s: fetch_bars(s, start.astimezone(ZoneInfo("UTC")).strftime(fmt),
                              end.astimezone(ZoneInfo("UTC")).strftime(fmt),
                              key, secret) for s in SYMS}
    for s in SYMS:
        print(f"  {s}: {len(all_bars[s])} bars")

    # replay days 1..4 (day 0 only provides grid/bar history)
    uniq_ids = sorted(set(day_ids.tolist()))
    live_rows, train_rows_used, minutes_used, replay_dates = [], [], [], []
    engine = FeatureEngine(str(BUNDLE / "feature_stats.npz"),
                           str(BUNDLE / "feature_names.json"))
    buffers = {s: deque(maxlen=200) for s in
               SYMS + ["SPX", "TNX", "VIX"]}

    # seed: every bar before day-1 09:30 ET (mimics the launcher's
    # 200-bar prime; deque maxlen keeps the most recent 200)
    first_replay_date = datetime.strptime(dates[1], "%Y%m%d").date()
    seed_cut = datetime.combine(first_replay_date, dtime(9, 30), ET)
    for s in SYMS:
        for t in sorted(all_bars[s]):
            if t < seed_cut:
                buffers[s].append(all_bars[s][t])
        rebuild_proxies(buffers, s)

    flat_idx = {d: np.where(day_ids == d)[0] for d in uniq_ids}
    for di, d_id in enumerate(uniq_ids[1:], start=1):
        date = datetime.strptime(dates[di], "%Y%m%d").date()
        day_rows = flat_idx[d_id]
        assert len(day_rows) == 390, f"{date}: {len(day_rows)} rows"
        print(f"replaying {date} ...")
        for m in range(390):
            t = datetime.combine(date, dtime(9, 30), ET) + timedelta(minutes=m)
            got_spy = False
            for s in SYMS:
                bar = all_bars[s].get(t)
                if bar is not None:
                    buffers[s].append(bar)
                    rebuild_proxies(buffers, s)
                    if s == "SPY":
                        got_spy = True
            if not got_spy:
                continue  # live: no SPY bar = no pipeline run
            # grid history: 10 most recent TRAINING grids up to this minute
            g_end = day_rows[m] + 1
            g_hist = [grids[i] for i in range(max(0, g_end - 10), g_end)]
            feats = engine.compute_all_features(
                bar_buffers=buffers, greeks_grids_history=g_hist,
                hmm_model=hmm, dictionary_atoms=atoms)
            live_rows.append(feats)
            train_rows_used.append(X_train[day_rows[m]])
            minutes_used.append(m)
            replay_dates.append(dates[di])

    L = np.stack(live_rows)
    T = np.stack(train_rows_used)
    print(f"\ncompared rows: {L.shape[0]} (SPY-bar coverage "
          f"{L.shape[0]/(390*(len(uniq_ids)-1))*100:.1f}%)")

    # alignment sanity: live SPY close (engine excludes it; use buffers
    # indirectly via train spy_prices vs IEX close diff on SMA-free col)
    # -> report per-feature stats
    report = {}
    eps = 1e-12
    for j, name in enumerate(feature_names):
        lv, tv = L[:, j].astype(np.float64), T[:, j].astype(np.float64)
        both_zero = np.mean((lv == 0) & (tv == 0))
        live_zero = np.all(lv == 0)
        train_zero = np.all(tv == 0)
        denom = max(float(train_std_global[j]), eps)
        nmad = float(np.mean(np.abs(lv - tv)) / denom)
        if np.std(lv) > eps and np.std(tv) > eps:
            corr = float(np.corrcoef(lv, tv)[0, 1])
        else:
            corr = None
        if live_zero and not train_zero:
            bucket = "ZERO_FILLED_LIVE"
        elif live_zero and train_zero:
            bucket = "BOTH_ZERO"
        elif nmad < 0.01:
            bucket = "MATCH"
        elif corr is not None and corr > 0.99:
            bucket = "SCALE_OR_OFFSET"  # tracks but biased
        elif corr is not None and corr > 0.9:
            bucket = "CLOSE"
        else:
            bucket = "MISMATCH"
        report[name] = {"bucket": bucket, "nmad_train_sigma": round(nmad, 5),
                        "corr": None if corr is None else round(corr, 4),
                        "pct_both_zero": round(float(both_zero), 3)}

    buckets = {}
    for name, r in report.items():
        buckets.setdefault(r["bucket"], []).append(name)
    print("\n=== PARITY BUCKETS (live engine vs training cache) ===")
    for b in ["MATCH", "SCALE_OR_OFFSET", "CLOSE", "MISMATCH",
              "ZERO_FILLED_LIVE", "BOTH_ZERO"]:
        names = buckets.get(b, [])
        print(f"  {b:18} {len(names):4}")
    print("\nworst 25 MISMATCH (by train-sigma-normalized abs diff):")
    mism = sorted(((r["nmad_train_sigma"], n) for n, r in report.items()
                   if r["bucket"] == "MISMATCH"), reverse=True)[:25]
    for v, n in mism:
        print(f"  {n:45} nmad={v:8.3f} corr={report[n]['corr']}")

    np.savez_compressed(PARITY / "replay_results.npz",
                        live=L.astype(np.float32), train=T.astype(np.float32),
                        minutes=np.array(minutes_used),
                        dates=np.array(replay_dates))
    (PARITY / "replay_report.json").write_text(json.dumps(
        {"buckets": {b: sorted(ns) for b, ns in buckets.items()},
         "per_feature": report}, indent=1))
    print(f"\nwrote {PARITY}/replay_results.npz + replay_report.json")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
