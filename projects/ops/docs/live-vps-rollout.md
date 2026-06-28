# Live VPS Rollout

This repo owns SteveTrading production deployment. `~/ascolais` is only a
reference for Hetzner patterns; do not mutate it for this project.

## Provision

Dry-run first:

```bash
python projects/ops/scripts/hetzner_vps.py --env-file ~/ascolais/.env \
  provision stevetrading-live-1 \
  --location ash --min-ram 4 --min-disk 40 --arch amd --max-price-monthly 25 \
  --dry-run
```

Create:

```bash
python projects/ops/scripts/hetzner_vps.py --env-file ~/ascolais/.env \
  provision stevetrading-live-1 \
  --location ash --min-ram 4 --min-disk 40 --arch amd --max-price-monthly 25
```

The provisioner creates a non-Tailscale Ubuntu host, a `bot` sudo user,
public-key SSH access, basic SSH hardening, UFW with SSH allowed, and
`/opt/stevetrading/{releases,shared}`.

## Production Shape

Use the VPS as the canonical paper-trading production box. Local development can
continue against sim broker and replay, but live Alpaca paper should not depend
on a laptop/WSL session once the VPS is cut over.

Required runtime payload:

- `stevetrading-basilisp` release checkout under `/opt/stevetrading/releases/<git-sha>`.
- `current` symlink pointing at the active release.
- Data-Preprocessor reference tree under `/opt/stevetrading/shared/Data-Preprocessor`.
- Secrets in `/etc/stevetrading/env`, never committed.
- ThetaData lifecycle installed as a systemd-owned service.
- `stevetrading-six.timer` starts `stevetrading-six.service` at 09:20 ET on weekdays.
- `stevetrading-watchdog.timer` checks and heals the live session every five minutes.

## Change Rollout Rule

Never edit the production checkout in place.

1. Build a new release directory on the VPS.
2. Install dependencies and regenerate `.nrepl-pythonpath` in that release.
3. Run tests or at least focused live gates plus `scripts/preflight_live_imports.lpy`.
4. Promote by switching `/opt/stevetrading/current` only after preflight passes.
5. During market hours, deploy to an inactive release only. Do not restart live services unless explicitly doing an incident fix.
6. If a promoted release fails readiness, switch `current` back to the previous release and restart.

## Cutover Gate

Before disabling local cron, confirm on the VPS:

```bash
systemctl status stevetrading-six.service
systemctl status stevetrading-six.timer
systemctl status stevetrading-watchdog.timer
systemctl list-timers --all | grep stevetrading
journalctl -u stevetrading-six.service -n 100 --no-pager
```

Then verify the live ledger is advancing:

```bash
sqlite3 /opt/stevetrading/current/live_runtime/steve-session-$(date -u +%F)/facts.db \
  "select fact_type, count(*), max(occurred_at) from facts group by fact_type order by fact_type;"
```
