# Ops Project

Canonical hosting and deployment material lives here. Top-level `scripts/ops/*`
files are compatibility wrappers only.

## Layout

- `scripts/`: Hetzner provisioning, release deployment, reports service, and
  ThetaData lifecycle scripts.
- `scripts/systemd/`: canonical systemd units and timers installed by deploy.
- `docs/`: operator runbooks for VPS rollout and sim/live analysis workflows.

## Common Commands

Provision dry-run:

```bash
python projects/ops/scripts/hetzner_vps.py --env-file ~/ascolais/.env \
  provision stevetrading-live-1 --location ash --dry-run
```

Deploy current working tree to an existing VPS release:

```bash
projects/ops/scripts/deploy_live_vps.sh bot@<host>
```

Compatibility path:

```bash
scripts/ops/deploy_live_vps.sh bot@<host>
```

## ThetaData Lifecycle

The operational ThetaData lifecycle script also gets copied into
`SteveTrading/ref/Data-Preprocessor/thetadata_lifecycle.sh`, because the
runtime `$LIFECYCLE` points there. Edit the canonical version here, then copy
it to the REF tree when running locally outside the VPS deploy flow:

```bash
cp projects/ops/scripts/thetadata_lifecycle.sh \
  "$HOME/contracting/upwork/steven-tran/SteveTrading/ref/Data-Preprocessor/thetadata_lifecycle.sh"
```

Hardened 2026-06-20 after the 06-17/06-18 outage (DNS root cause): DNS
precheck + bounded wait, patient non-thrashing start, honest failure
classification, orphan reaping. See the script header for detail.
