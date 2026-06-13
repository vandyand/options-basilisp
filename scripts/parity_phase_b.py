#!/usr/bin/env python3
"""Phase B feature-parity checks — the LIVE paths that Phase A (replay)
could not exercise, run against a day's live feature capture.

Phase A replayed training-cache days through the live FeatureEngine with
TRAINING grids, so two things stayed untested:
  1. the live chain -> IV/BS -> greeks-grid construction (Phase A used
     training grids), and
  2. whether the grid-DERIVED features (v2 vix/regime, v3 tda/scat/wass/
     dict) standardize sanely when fed LIVE grids.

This script reads one live_features_<date>.npz (per-bar raw 918-vectors +
the live greeks grids + SPY) and runs:

  CHECK 1  live greeks-grid distributions vs the training grids
           (per channel: scale, fill ratio, ATM-moneyness structure,
           DTE-term structure) — structural breaks (wrong IV scale,
           inverted/empty axes) show at a glance.
  CHECK 2  live feature z-sanity: standardize every raw feature with the
           CORRECTED stats and check the live z-distribution is plausible
           under training (mean~0, std~1). Bucketed by feature family so
           the grid-derived families (the Phase-A blind spot) are called
           out separately.

Read-only. Run under the REF venv (numpy):
    .venv/bin/python3 scripts/parity_phase_b.py [YYYYMMDD]
"""
import json
import sys
from pathlib import Path

import numpy as np

REPO = Path(__file__).resolve().parent.parent
PARITY = Path.home() / "contracting/upwork/steven-tran/parity"
BUNDLE = (Path.home() / "contracting/upwork/steven-tran/SteveTrading/ref/"
          "Data-Preprocessor/pipeline_data/live_model_chestnut_multihead")
CHANNELS = ["IV", "delta", "vega", "theta", "rho", "gamma_proxy"]
# grid axes (build_5yr_cache.py): 21 moneyness bins 0.90->1.10, 8 DTE buckets
MONEYNESS = np.linspace(0.90, 1.10, 22)


def fam(name):
    head = name.split("_")[0]
    if head in ("dict", "scat", "tda", "wass"):
        return "v3-grid"
    if name in ("vix_proxy", "vix_term_slope", "put_call_ratio",
                "vix_momentum_5", "vix_momentum_20", "realized_vol_20",
                "realized_vol_60", "vol_ratio", "hmm_state_0", "hmm_state_1",
                "hmm_state_2"):
        return "v2-grid"
    if head in ("SPX", "VIX", "TNX"):
        return "index-proxy"
    if "opt" in name or "greeks" in name or head in ("SPXW", "VIXW", "SPX"):
        return "options-base"
    return "equity-base"


def check1_grids(live_grids):
    train = np.load(PARITY / "train_grids_apr13-17.npz")["grids"]
    print("=" * 72)
    print("CHECK 1 — live greeks-grid distributions vs TRAINING grids")
    print(f"  live: {live_grids.shape[0]} bars   train: {train.shape[0]} bars")
    print("=" * 72)
    print(f"  {'channel':12} {'live μ':>9} {'train μ':>9} {'live σ':>8}"
          f" {'train σ':>8} {'live fill':>9} {'trn fill':>9}  verdict")
    verdicts = {}
    for c, name in enumerate(CHANNELS):
        lv, tv = live_grids[:, c], train[:, c]
        lnz = (lv != 0)
        tnz = (tv != 0)
        lmu = float(lv[lnz].mean()) if lnz.any() else 0.0
        tmu = float(tv[tnz].mean()) if tnz.any() else 0.0
        lsd = float(lv[lnz].std()) if lnz.any() else 0.0
        tsd = float(tv[tnz].std()) if tnz.any() else 0.0
        lfill = float(lnz.mean())
        tfill = float(tnz.mean())
        # verdict: same order of magnitude on nonzero-mean + comparable fill
        ratio = (abs(lmu) + 1e-9) / (abs(tmu) + 1e-9)
        ok_scale = 0.2 < ratio < 5.0
        ok_fill = lfill > 0.3 * tfill
        v = "OK" if (ok_scale and ok_fill) else (
            "SCALE?" if not ok_scale else "SPARSE?")
        verdicts[name] = v
        print(f"  {name:12} {lmu:>9.4f} {tmu:>9.4f} {lsd:>8.4f} {tsd:>8.4f}"
              f" {lfill:>9.3f} {tfill:>9.3f}  {v}")

    # ATM structure: which moneyness bin carries the most IV mass?
    print("\n  IV moneyness profile (mean IV per moneyness bin, summed DTE):")
    live_iv_money = live_grids[:, 0].mean(axis=(0, 2))  # (21,)
    train_iv_money = train[:, 0].mean(axis=(0, 2))
    l_atm = int(np.argmax(live_iv_money))
    t_atm = int(np.argmax(train_iv_money))
    print(f"    live  peak moneyness bin {l_atm} (~{MONEYNESS[l_atm]:.3f})")
    print(f"    train peak moneyness bin {t_atm} (~{MONEYNESS[t_atm]:.3f})")
    # DTE term structure: near vs far populated?
    live_dte = (live_grids[:, 0] != 0).mean(axis=(0, 1))  # (8,) fill per DTE
    train_dte = (train[:, 0] != 0).mean(axis=(0, 1))
    print("\n  IV fill ratio per DTE bucket (0=near ... 7=far):")
    print("    live :", " ".join(f"{x:.2f}" for x in live_dte))
    print("    train:", " ".join(f"{x:.2f}" for x in train_dte))
    return verdicts


def check2_zsanity(live_feats, feature_names):
    cs = np.load(PARITY / "feature_stats_raw_corrected.npz")
    mean, std = cs["mean"].astype(np.float64), cs["std"].astype(np.float64)
    rb = json.loads((PARITY / "rebucket_report.json").read_text())
    kept = set()
    for b in ("MATCH", "CLOSE", "SCALE_OR_OFFSET"):
        kept.update(rb["buckets"].get(b, []))

    z = (live_feats.astype(np.float64) - mean) / np.where(std == 0, 1.0, std)
    print("\n" + "=" * 72)
    print("CHECK 2 — live feature z-sanity (corrected stats)")
    print(f"  {live_feats.shape[0]} bars x {live_feats.shape[1]} features")
    print("=" * 72)

    by_fam = {}
    for j, name in enumerate(feature_names):
        live_zero = bool(np.all(live_feats[:, j] == 0))
        zmu = float(z[:, j].mean())
        zsd = float(z[:, j].std())
        # sane = plausible under N(0,1): centered + non-degenerate + not wild
        sane = (not live_zero) and abs(zmu) < 2.0 and 0.1 < zsd < 4.0
        rec = {"zmu": zmu, "zsd": zsd, "zero": live_zero, "sane": sane,
               "kept": name in kept}
        by_fam.setdefault(fam(name), []).append((name, rec))

    print(f"  {'family':14} {'n':>4} {'zero':>5} {'sane':>5} {'kept-live':>9}"
          f"  {'sane∧kept':>9}")
    for f in ["equity-base", "options-base", "index-proxy", "v2-grid",
              "v3-grid"]:
        rows = by_fam.get(f, [])
        if not rows:
            continue
        n = len(rows)
        nzero = sum(r["zero"] for _, r in rows)
        nsane = sum(r["sane"] for _, r in rows)
        nkept = sum(r["kept"] for _, r in rows)
        nsk = sum(r["sane"] and r["kept"] for _, r in rows)
        print(f"  {f:14} {n:>4} {nzero:>5} {nsane:>5} {nkept:>9} {nsk:>9}")

    # the Phase-A blind spot: grid-derived families fed LIVE grids
    print("\n  GRID-DERIVED families (Phase-A blind spot — live grids now):")
    for f in ("v2-grid", "v3-grid"):
        rows = by_fam.get(f, [])
        kept_rows = [(n, r) for n, r in rows if r["kept"]]
        if not kept_rows:
            print(f"    {f}: no kept-live features")
            continue
        sane = sum(r["sane"] for _, r in kept_rows)
        print(f"    {f}: {sane}/{len(kept_rows)} kept-live features sane "
              f"under live grids")
        for n, r in kept_rows:
            if not r["sane"]:
                print(f"      DRIFT {n}: z μ={r['zmu']:+.2f} σ={r['zsd']:.2f}"
                      f"{' (all-zero live)' if r['zero'] else ''}")

    # worst kept-live drifters overall (these feed the models today)
    kept_all = [(n, r) for rows in by_fam.values() for n, r in rows
                if r["kept"]]
    drift = sorted(((abs(r["zmu"]), n, r) for n, r in kept_all), reverse=True)
    print("\n  worst 12 kept-live z-offsets (feed the live models):")
    for zmu, n, r in drift[:12]:
        flag = "" if r["sane"] else "  <-- INSANE"
        print(f"    {n:42} z μ={r['zmu']:+.3f} σ={r['zsd']:.2f}{flag}")
    sane_kept = sum(r["sane"] for _, r in kept_all)
    print(f"\n  VERDICT: {sane_kept}/{len(kept_all)} kept-live features "
          f"standardize sanely on live data")

    # actionable: kept-live features that are DEGENERATE on live data
    # (zero intraday variance = broken computation, e.g. v3 multi-day
    # "_d5" deltas that can't form in a single session; or wildly mis-
    # scaled |z|>8). NOT price-level non-stationarity (real but OOD —
    # those stay, flagged to Steve). These should join the neutralize
    # list so the live models don't ingest broken inputs.
    drop = sorted(n for n, r in kept_all
                  if r["kept"] and (r["zero"] or r["zsd"] < 1e-3
                                    or abs(r["zmu"]) > 8.0))
    (PARITY / "phase_b_drop.json").write_text(json.dumps(drop, indent=1))
    print(f"\n  -> {len(drop)} kept-live features are DEGENERATE on live "
          f"(zero-variance / |z|>8); written to phase_b_drop.json:")
    for n in drop:
        print(f"       {n}")
    return sane_kept, len(kept_all)


def main():
    date = sys.argv[1] if len(sys.argv) > 1 else "20260612"
    cap = REPO / "live_runtime/feature-capture" / f"live_features_{date}.npz"
    d = np.load(cap, allow_pickle=True)
    feature_names = json.loads((BUNDLE / "feature_names.json").read_text())
    # chestnut/lynx/moose share the FeatureEngine — verify identical first
    drift = float(np.abs(d["chestnut"] - d["lynx"]).max())
    print(f"sanity: per-bot feature vectors identical? max|chestnut-lynx| "
          f"= {drift:.2e} (engines share features)\n")
    feats = d["chestnut"]  # representative
    check1_grids(d["grids"])
    check2_zsanity(feats, feature_names)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
