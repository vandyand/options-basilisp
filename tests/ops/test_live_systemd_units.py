from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


def read(rel: str) -> str:
    return (ROOT / rel).read_text()


def test_six_timer_starts_before_market_open():
    timer = read("projects/ops/scripts/systemd/stevetrading-six.timer")

    assert "OnCalendar=Mon..Fri *-*-* 09:20:00 America/New_York" in timer
    assert "Unit=stevetrading-six.service" in timer
    assert "WantedBy=timers.target" in timer


def test_deploy_installs_and_preserves_live_timers_by_default():
    deploy = read("projects/ops/scripts/deploy_live_vps.sh")

    assert "stevetrading-six.timer" in deploy
    assert "DISABLE_LIVE_AFTER_DEPLOY" in deploy
    assert "leaving live timer/service enablement unchanged" in deploy
    assert "sudo systemctl enable --now stevetrading-six.timer stevetrading-watchdog.timer" in deploy


def test_watchdog_restarts_systemd_six_unit_not_orphan_child():
    watchdog = read("scripts/steve_watchdog.sh")

    assert "SYSTEMD_SIX_UNIT" in watchdog
    assert 'sudo -n systemctl restart "$SYSTEMD_SIX_UNIT"' in watchdog
    assert "watchdog Type=oneshot must not own the background child process directly" in watchdog
    assert "relaunch verified alive" in watchdog
