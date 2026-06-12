#!/usr/bin/env python3
"""Re-bucket the Phase A replay results using the CORRECTED raw feature
stats (recovered on Lightning by parity_stats_v2v3.py).

The training cache X is standardized; the live engine emits raw values.
parity_replay.py compared raw-vs-z (meaningless for scale). This script
standardizes the captured live-raw vectors with the corrected stats and
re-buckets — the honest computation+data parity verdict.

Usage (REF venv):
    .venv/bin/python3 parity_rebucket.py
"""
import json
import os
from pathlib import Path

import numpy as np

PARITY = Path(os.path.expanduser("~/contracting/upwork/steven-tran/parity"))
BUNDLE = Path(os.path.expanduser(
    "~/contracting/upwork/steven-tran/SteveTrading/ref/Data-Preprocessor/"
    "pipeline_data/live_model_chestnut_multihead"))


def main():
    res = np.load(PARITY / "replay_results.npz")
    L_raw, T = res["live"].astype(np.float64), res["train"].astype(np.float64)
    names = json.loads((BUNDLE / "feature_names.json").read_text())
    cs = np.load(PARITY / "feature_stats_raw_corrected.npz")
    mean, std = cs["mean"].astype(np.float64), cs["std"].astype(np.float64)

    # train rows are ceil-stamped: train row m == live bar m-1 (verified
    # via spy_prices anchor, corr 0.99997 at shift -1)
    L = (L_raw[:-1] - mean) / np.where(std == 0, 1.0, std)
    T = T[1:]

    report, buckets = {}, {}
    for j, name in enumerate(names):
        lv, tv = L[:, j], T[:, j]
        live_zero = bool(np.all(L_raw[:-1, j] == 0))
        train_zero = bool(np.all(tv == 0))
        nmad = float(np.mean(np.abs(lv - tv)))  # already in train-sigma units
        corr = (float(np.corrcoef(lv, tv)[0, 1])
                if np.std(lv) > 1e-12 and np.std(tv) > 1e-12 else None)
        if live_zero and not train_zero:
            b = "ZERO_FILLED_LIVE"
        elif live_zero and train_zero:
            b = "BOTH_ZERO"
        elif nmad < 0.05:
            b = "MATCH"
        elif corr is not None and corr > 0.99:
            b = "SCALE_OR_OFFSET"
        elif corr is not None and corr > 0.9:
            b = "CLOSE"
        else:
            b = "MISMATCH"
        report[name] = {"bucket": b, "nmad_sigma": round(nmad, 4),
                        "corr": None if corr is None else round(corr, 4)}
        buckets.setdefault(b, []).append(name)

    print("=== CORRECTED-STATS PARITY BUCKETS ===")
    for b in ["MATCH", "SCALE_OR_OFFSET", "CLOSE", "MISMATCH",
              "ZERO_FILLED_LIVE", "BOTH_ZERO"]:
        print(f"  {b:18} {len(buckets.get(b, [])):4}")
    print("\nworst 20 MISMATCH:")
    for v, n in sorted(((r["nmad_sigma"], n) for n, r in report.items()
                        if r["bucket"] == "MISMATCH"), reverse=True)[:20]:
        print(f"  {n:45} nmad={v:8.3f}σ corr={report[n]['corr']}")
    print("\nbest-behaved nonzero families (sample of MATCH):")
    print(" ", sorted(buckets.get("MATCH", []))[:12])
    (PARITY / "rebucket_report.json").write_text(json.dumps(
        {"buckets": {b: sorted(ns) for b, ns in buckets.items()},
         "per_feature": report}, indent=1))
    print(f"\nwrote {PARITY}/rebucket_report.json")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
