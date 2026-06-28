# Ops scripts (version-controlled copies)

The **operational** copy of `thetadata_lifecycle.sh` runs from
`SteveTrading/ref/Data-Preprocessor/thetadata_lifecycle.sh` (the path the
orchestrator's `$LIFECYCLE` points at, and where the systemd sudoers rule is
scoped). That location is **not** git-tracked, so this directory holds the
canonical version-controlled copy. **Edit here, then copy to the REF path:**

    cp projects/ops/scripts/thetadata_lifecycle.sh \
       "$HOME/contracting/upwork/steven-tran/SteveTrading/ref/Data-Preprocessor/thetadata_lifecycle.sh"

## Layout

- `scripts/`: canonical hosting, deployment, report-service, and ThetaData lifecycle scripts.
- `scripts/systemd/`: canonical systemd unit and timer files installed by deploy.
- `docs/`: operator runbooks for VPS rollout and sim/live analysis workflows.

Compatibility wrappers may remain under top-level `scripts/ops/`, but new
ops work should live in this project projection.

Hardened 2026-06-20 after the 06-17/06-18 outage (DNS root cause): DNS
precheck + bounded wait, patient non-thrashing start, honest failure
classification, orphan reaping. See the script header for detail.
