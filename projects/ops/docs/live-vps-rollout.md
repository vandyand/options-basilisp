# Live VPS Rollout

This repo owns SteveTrading production deployment. `~/ascolais` is only a
reference for Hetzner patterns; do not mutate it for this project.

## Provision

Dry-run first:

```bash
basilisp run projects/ops/scripts/hetzner_vps.lpy -- --env-file ~/ascolais/.env \
  provision stevetrading-live-1 \
  --location ash --min-ram 4 --min-disk 40 --arch amd --max-price-monthly 25 \
  --dry-run
```

Create:

```bash
basilisp run projects/ops/scripts/hetzner_vps.lpy -- --env-file ~/ascolais/.env \
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
- Runtime env in `/etc/stevetrading/env`, never committed. It must point live
  runners at the promoted release and shared reference venv:
  `STEVE_REPO_ROOT=/opt/stevetrading/current`,
  `STEVETRADING_BASILISP_ROOT=/opt/stevetrading/current`,
  `STEVE_REF_ROOT=/opt/stevetrading/shared/Data-Preprocessor`,
  `BASILISP_BIN=/opt/stevetrading/shared/Data-Preprocessor/.venv/bin/basilisp`,
  `ANALYSIS_DIR=/opt/stevetrading/shared/live_runtime/analysis`,
  `CAPTURE_DIR=/opt/stevetrading/shared/live_runtime/feature-capture`, and
  `PAYLOAD_DIR=/opt/stevetrading/shared/payload_examples`.
- Reports web env in `/etc/stevetrading/reports.env`, never committed. It must
  include `REPORTS_ROOT=/opt/stevetrading/shared/Data-Preprocessor/report-viewer/public`,
  `REPORTS_USER=stevetrading`, `REPORTS_PASSWORD_SHA256=<sha256>`,
  `REPORTS_PUBLIC_STATUS=0`, and `REPORTS_ALLOW_NO_AUTH=0`.
- Shared evidence directories under `/opt/stevetrading/shared/live_runtime` and
  `/opt/stevetrading/shared/payload_examples`. The promoted release symlinks
  `current/live_runtime` and `current/resources/thetadata/payload_examples` to
  those shared paths, but systemd jobs should use the real shared paths from
  `/etc/stevetrading/env` so manifest verification does not trip on symlinks.
- ThetaData lifecycle installed as a systemd-owned service.
- `stevetrading-six.timer` starts `stevetrading-six.service` at 09:20 ET on weekdays.
- `stevetrading-watchdog.timer` checks and heals the live session every five minutes.
- `stevetrading-reports-build.timer` builds and audits daily reports at
  16:05 ET on weekdays. The report build service intentionally does not
  auto-restart on failure; scheduled runs resolve the latest completed trading
  session via `scripts/report_target_date.lpy`, and failures should remain
  visible instead of retrying into the next pre-market session.
- `stevetrading-status-dashboard.timer` refreshes the reports-site status
  dashboard every minute.
- `stevetrading-market-evidence-preflight.timer` checks market-evidence
  readiness before open.
- `stevetrading-market-evidence-capture-smoke.timer` validates early
  capture-v2 sidecars after open before the full evidence collector runs.
- `stevetrading-market-evidence-collect.timer` captures ThetaData payloads and
  feature-parity evidence during market hours. The collect service uses
  `Wants=theta-terminal.service`, a one-hour wrapper timeout, and four
  historical feature jobs; normal boot still does not enable
  `theta-terminal.service`.
- `stevetrading-raw-thetadata-parity.timer` runs at 09:31 ET on trading days.
  It stores first-open raw snapshot/at-time receipts in
  `/opt/stevetrading/shared/thetadata-parity-v1` and reports the same-session
  source-pair verdict without waiting for the broader feature-evidence run.
- `stevetrading-reports-web.service` serves
  `/opt/stevetrading/shared/Data-Preprocessor/report-viewer/public` and refuses
  to start without auth and required status artifacts.

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
systemctl status stevetrading-reports-build.timer
systemctl status stevetrading-status-dashboard.timer
systemctl status stevetrading-market-evidence-preflight.timer
systemctl status stevetrading-market-evidence-capture-smoke.timer
systemctl status stevetrading-market-evidence-collect.timer
systemctl status stevetrading-raw-thetadata-parity.timer
systemctl status stevetrading-reports-web.service
systemctl list-timers --all | grep stevetrading
journalctl -u stevetrading-six.service -n 100 --no-pager
journalctl -u stevetrading-status-dashboard.service -n 100 --no-pager
journalctl -u stevetrading-market-evidence-collect.service -n 100 --no-pager
journalctl -u stevetrading-raw-thetadata-parity.service -n 100 --no-pager
```

Then verify the live ledger is advancing:

```bash
sqlite3 /opt/stevetrading/current/live_runtime/steve-session-$(date -u +%F)/facts.db \
  "select fact_type, count(*), max(occurred_at) from facts group by fact_type order by fact_type;"
```

Verify report/status publication is auditable:

```bash
cd /opt/stevetrading/current
set -a && . /etc/stevetrading/env && set +a
"$BASILISP_BIN" run scripts/audit_status_publication.lpy -- \
  --out-dir "$STEVE_REF_ROOT/report-viewer/public/reports/status"
"$BASILISP_BIN" run scripts/audit_daily_report_validations.lpy -- \
  --daily-dir "$STEVE_REF_ROOT/report-viewer/public/reports/daily" \
  --write-manifests --require-manifests
```

Verify market-evidence paths use shared real directories and can preflight
without live writes:

```bash
cd /opt/stevetrading/current
set -a && . /etc/stevetrading/env && set +a
MARKET_EVIDENCE_MODE=preflight \
MARKET_EVIDENCE_SKIP_NON_TRADING_DAYS=0 \
projects/ops/scripts/run_market_evidence.sh
```

On a trading day after the 10:45 ET collector window, verify the captured
bundle and status summary:

```bash
STAMP=$(TZ=America/New_York date +%Y%m%d)
"$BASILISP_BIN" run scripts/market_evidence_manifest.lpy -- \
  --target-date "$(TZ=America/New_York date +%F)" \
  --verify "$ANALYSIS_DIR/market_evidence_manifest_$STAMP.json" \
  --analysis-dir "$ANALYSIS_DIR" \
  --payload-dir "$PAYLOAD_DIR"
test -s "$ANALYSIS_DIR/market_evidence_status_$STAMP.json"
```

If `market_evidence_status_$STAMP.json` reports `unmask_apply_ready?:
true`, inspect the dry-run bundle changes and then run the manual verified
apply wrapper. This wrapper does not collect evidence and fails closed unless
the same-day manifest, status, and non-applying validation artifact still
match. It also runs `scripts/verify_neutralization_unmask_apply.lpy` after
the apply and writes
`neutralization_unmask_apply_verification_$STAMP.json` before reporting
success:

```bash
jq '.unmask_apply_ready?, .manifest.raw_unlock.unmask_dry_run_results, .verified_apply_validation' \
  "$ANALYSIS_DIR/market_evidence_status_$STAMP.json"
projects/ops/scripts/run_verified_unmask_apply.sh \
  --target-date "$(TZ=America/New_York date +%F)"
jq '.ok, .removed_total, .missing_total, .issues' \
  "$ANALYSIS_DIR/neutralization_unmask_apply_verification_$STAMP.json"
tail -100 /var/log/stevetrading/market-evidence-apply.log
```
