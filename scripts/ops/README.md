# Ops scripts (version-controlled copies)

The **operational** copy of `thetadata_lifecycle.sh` runs from
`SteveTrading/ref/Data-Preprocessor/thetadata_lifecycle.sh` (the path the
orchestrator's `$LIFECYCLE` points at, and where the systemd sudoers rule is
scoped). That location is **not** git-tracked, so this directory holds the
canonical version-controlled copy. **Edit here, then copy to the REF path:**

    cp scripts/ops/thetadata_lifecycle.sh \
       "$HOME/contracting/upwork/steven-tran/SteveTrading/ref/Data-Preprocessor/thetadata_lifecycle.sh"

Hardened 2026-06-20 after the 06-17/06-18 outage (DNS root cause): DNS
precheck + bounded wait, patient non-thrashing start, honest failure
classification, orphan reaping. See the script header for detail.
