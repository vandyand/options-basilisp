# Scripts

Top-level scripts are developer and runtime entrypoints that do not belong in
pure components.

Common commands:

- `scripts/test.sh`: run Basilisp/Pytest tests with the repo environment.
- `scripts/lint.sh`: compile check plus dependency-direction check.
- `scripts/nrepl.sh`: start a Basilisp nREPL with regenerated pythonpath.
- `scripts/current_pnl.py`: current Alpaca/sim account P&L table.
- `scripts/launch_steve_six.lpy`: six Alpaca paper strategies launcher.
- `scripts/launch_vol_term_sim.lpy`: local vol/term sim launcher.
- `scripts/export_live_tape.lpy`: export behavior tape from facts.
- `scripts/calibrate_sim_fills.lpy`: build sim fill calibration artifact.

Canonical hosting/deployment scripts live under `projects/ops/scripts/`.
`scripts/ops/` contains compatibility wrappers.
