#!/usr/bin/env python3
"""Build *_corrected copies of the three live bundles with the recovered
raw feature stats + a neutralization list.

Policy (clean-feature-parity, 2026-06-12):
  - feature_stats.npz <- feature_stats_raw_corrected.npz (recovered on
    Lightning by exact re-runs of the cache builders; v2/v3 stages
    reproduced the training cache to 0 error)
  - neutralize_features.json <- features whose LIVE source is missing or
    broken, pinned to train-mean (z=0) by the bridge pre-inference:
      ZERO_FILLED_LIVE  engine zero-fills (GCS-only chain features)
      BOTH_ZERO         no information either way
      MISMATCH          live source disagrees with training source
                        (IEX volume, bid/ask close-fallback, ...)
    Kept live: MATCH + SCALE_OR_OFFSET + CLOSE (corr > 0.9 vs training).

Originals are never touched — rollback = point the launcher back at the
original bundle dirs.

Usage (any python3): python3 deploy_corrected_bundles.py
"""
import json
import shutil
from pathlib import Path

import numpy as np

REF = Path.home() / ("contracting/upwork/steven-tran/SteveTrading/ref/"
                     "Data-Preprocessor")
PARITY = Path.home() / "contracting/upwork/steven-tran/parity"
PD = REF / "pipeline_data"
ACCOUNTS = ["chestnut", "lynx", "moose"]
NEUTRALIZE_BUCKETS = {"ZERO_FILLED_LIVE", "BOTH_ZERO", "MISMATCH"}


def main():
    rb = json.loads((PARITY / "rebucket_report.json").read_text())
    buckets = rb["buckets"]
    neutralize = sorted(n for b, ns in buckets.items()
                        if b in NEUTRALIZE_BUCKETS for n in ns)
    kept = sorted(n for b, ns in buckets.items()
                  if b not in NEUTRALIZE_BUCKETS for n in ns)
    print(f"neutralize: {len(neutralize)}  kept-live: {len(kept)}")

    cs = np.load(PARITY / "feature_stats_raw_corrected.npz")
    for acct in ACCOUNTS:
        src = PD / f"live_model_{acct}_multihead"
        dst = PD / f"live_model_{acct}_multihead_corrected"
        if dst.exists():
            shutil.rmtree(dst)
        shutil.copytree(src, dst)
        np.savez_compressed(dst / "feature_stats.npz",
                            mean=cs["mean"], std=cs["std"])
        (dst / "neutralize_features.json").write_text(json.dumps(neutralize))
        (dst / "CORRECTED_README.txt").write_text(
            "feature_stats.npz replaced with recovered RAW train stats\n"
            "(original was identity — computed on standardized data).\n"
            "neutralize_features.json pins broken live sources to z=0.\n"
            "Built by deploy_corrected_bundles.py on 2026-06-12.\n")
        print(f"  {dst.name}: stats replaced, {len(neutralize)} neutralized")
    print("done — launcher must point at *_corrected dirs")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
