from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
RUNNER = ROOT / "scripts" / "panda_calendar_shadow.lpy"
UNIT_ROOT = ROOT / "projects" / "ops" / "scripts" / "systemd"


def test_runner_is_structurally_quote_only_and_uses_frozen_rule():
    source = RUNNER.read_text(encoding="utf-8")

    assert "(def orders-enabled false)" in source
    assert "alpaca-post" not in source.lower()
    assert '"POST"' not in source
    assert ":data" not in source
    assert '(def symbols ["SPY" "QQQ" "IWM"])' in source
    assert '(def symbol-priority ["SPY" "QQQ" "IWM"])' in source
    assert '"aggregate_assignment_notional_multiple" 2.0' in source
    assert 'policy-version "assignment-notional-2x-2026-07-24"' in source
    assert "shadow/spy-expiration-buckets" in source
    assert '"individual_debit_fraction" 0.025' in source
    assert '"aggregate_debit_fraction" 0.10' in source
    assert '"12:00:00"' in source
    assert '"12:01:00"' in source
    assert '"15:15:00"' in source
    assert '"horizon_sessions" 5' in source
    assert "fetch-market-calendar" in source
    assert "SHORT_EXPIRES_BEFORE_FIVE_SESSION_EXIT" in source


def test_systemd_schedule_is_exact_and_does_not_own_shared_terminal():
    expected = {
        "preflight": "09:40:00",
        "entry": "11:59:15",
        "exit": "15:14:15",
    }

    for phase, clock in expected.items():
        timer = (UNIT_ROOT / f"stevetrading-panda-calendar-{phase}.timer").read_text(
            encoding="utf-8"
        )
        service = (UNIT_ROOT / f"stevetrading-panda-calendar-{phase}.service").read_text(
            encoding="utf-8"
        )

        assert f"OnCalendar=Mon..Fri *-*-* {clock} America/New_York" in timer
        assert "AccuracySec=1s" in timer
        assert "RandomizedDelaySec=0" in timer
        assert f"--phase {phase}" in service
        assert "--capture-now" not in service
        assert "Environment=PYTHONPATH=/opt/stevetrading/shared/panda-calendar-v1/tool/components/analysis.core/src" in service
        assert "systemctl" not in service
        assert "terminal" not in service.lower()
        assert "Wants=stevetrading-six.service" not in service
        assert "Requires=stevetrading-six.service" not in service
