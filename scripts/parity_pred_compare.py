#!/usr/bin/env python3
"""Prediction-level validation of the corrected feature stats.

Runs the full live inference (encoder embeddings + 3 XGB heads) for each
account over the 1,560 Phase-A replayed bars (Apr 14-17, live-engine raw
features + training grids), under BOTH stats variants:

  identity   — the deployed bug (raw values straight into the heads)
  corrected  — recovered raw stats + neutralize list (the *_corrected
               bundles built by deploy_corrected_bundles.py)

Reports per account/head: prediction mean/std vs the bundle's calibration
seed stats (what the train-set predictions looked like), plus the entry-
band crossing rate under the Optuna hysteresis sigmas — a trade-frequency
sanity gauge.

Usage (REF venv): .venv/bin/python3 parity_pred_compare.py
"""
import json
import os
import sys
from pathlib import Path

import numpy as np

REF = Path(os.path.expanduser(
    "~/contracting/upwork/steven-tran/SteveTrading/ref/Data-Preprocessor"))
PARITY = Path(os.path.expanduser("~/contracting/upwork/steven-tran/parity"))
PD = REF / "pipeline_data"
sys.path.insert(0, str(REF))
from scripts_5yr.live.model_inference import MultiHeadLiveInference  # noqa: E402

ACCOUNTS = ["chestnut", "lynx", "moose"]
HEADS = ["long", "gen", "short"]


def seed_stats(bdir, head):
    d = np.load(bdir / f"calibration_seed_{head}.npz")
    n = float(d["pred_count"])
    mu = float(d["pred_sum"]) / n
    var = float(d["pred_sum_sq"]) / n - mu * mu
    return mu, max(var, 0.0) ** 0.5


def main():
    res = np.load(PARITY / "replay_results.npz")
    L = res["live"].astype(np.float32)
    minutes = res["minutes"]
    dates = [str(d) for d in res["dates"]]
    gf = np.load(PARITY / "train_grids_apr13-17.npz")
    grids, gday_ids = gf["grids"].astype(np.float32), gf["day_ids"]
    uniq = sorted(set(gday_ids.tolist()))
    date_for_id = dict(zip(uniq, ["20260413", "20260414", "20260415",
                                  "20260416", "20260417"]))
    id_for_date = {v: k for k, v in date_for_id.items()}
    day_offset = {d: np.where(gday_ids == d)[0][0] for d in uniq}

    def grid_seq(row_i):
        d_id = id_for_date[dates[row_i]]
        g_end = day_offset[d_id] + minutes[row_i] + 1
        return grids[max(0, g_end - 10):g_end]

    out = {}
    for acct in ACCOUNTS:
        for variant, suffix in [("identity", ""), ("corrected", "_corrected")]:
            bdir = PD / f"live_model_{acct}_multihead{suffix}"
            if not bdir.exists():
                print(f"SKIP {acct}/{variant}: {bdir} missing")
                continue
            inf = MultiHeadLiveInference(str(bdir))
            nz_path = bdir / "neutralize_features.json"
            nz_idx, nz_mean = None, None
            if nz_path.exists():
                names = json.loads((bdir / "feature_names.json").read_text())
                ni = {n: i for i, n in enumerate(names)}
                nz_idx = np.array([ni[n] for n in
                                   json.loads(nz_path.read_text())
                                   if n in ni])
                nz_mean = inf.feature_mean[nz_idx]
            preds = []
            for i in range(L.shape[0]):
                f = L[i].copy()
                if nz_idx is not None:
                    f[nz_idx] = nz_mean
                preds.append(inf.predict(f, grid_seq(i)))
            P = np.array(preds)  # (n, 3) long/gen/short
            cal = json.loads((REF / "pipeline_data/calibrations/"
                              f"dir_cal_{acct}_h3_v1/v0_legacy_freeze.json"
                              ).read_text())
            row = {}
            for h, head in enumerate(HEADS):
                smu, ssd = seed_stats(bdir, head)
                pmu, psd = float(P[:, h].mean()), float(P[:, h].std())
                row[head] = {"pred_mean": round(pmu, 4),
                             "pred_std": round(psd, 4),
                             "seed_mean": round(smu, 4),
                             "seed_std": round(ssd, 4)}
            # entry-band gauge: z = pred/seed_std (zero-mean anchor, the
            # production convention); enter-long sigma from optuna params
            cfgp = json.loads((bdir / "config.json").read_text())[
                "best_optuna_params"]
            z_long = P[:, 0] / max(seed_stats(bdir, "long")[1], 1e-9)
            row["pct_bars_above_enter_long_sigma"] = round(float(
                (z_long > cfgp["enter_long_sigma"]).mean() * 100), 1)
            out[f"{acct}/{variant}"] = row
            print(f"{acct}/{variant}: " + " ".join(
                f"{h}:μ={row[h]['pred_mean']:+.3f}σ̂={row[h]['pred_std']:.3f}"
                f"(seed σ={row[h]['seed_std']:.3f})" for h in HEADS)
                + f"  enterL>{cfgp['enter_long_sigma']:.2f}σ: "
                  f"{row['pct_bars_above_enter_long_sigma']}%")
    (PARITY / "pred_compare_report.json").write_text(
        json.dumps(out, indent=1))
    print(f"\nwrote {PARITY}/pred_compare_report.json")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
