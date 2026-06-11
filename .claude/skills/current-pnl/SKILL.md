---
name: current-pnl
description: Use when the user runs /current-pnl or asks for today's P&L across the SteveTrading bots — prints per-strategy current-day P&L for the six Alpaca paper accounts (and venturevd). Optional arg all|alpaca|sim|venturevd (default all).
---

# Current P&L

## Overview
Prints today's per-strategy P&L. The six production accounts (CHESTNUT/LYNX/
MOOSE/PARROT/OAK/DOLPHIN) are read via the proven Python report script; the
venturevd dev account is read directly from Alpaca. Read-only (no orders).

NOTE (2026-06-11): the bots now run under the BASILISP engine
(~/contracting/upwork/steven-tran/stevetrading-basilisp), but this report reads
broker-account equity directly, so it is engine-agnostic.

## Core Pattern
Run the engine-agnostic stdlib report (six production accounts + venturevd;
day P&L, trade count, % time in market, avg trade duration, fill count):

```bash
python3 /home/kingjames/contracting/upwork/steven-tran/stevetrading-basilisp/scripts/current_pnl.py "${ARG:-all}"   # ARG ∈ all | alpaca | venturevd
```

- TRADES `N+1o` means N completed round trips plus one episode still open.
- %MKT = share of the regular session so far with any nonzero position.
- AVG-TRADE = mean completed-episode duration; `-` when nothing closed yet.
- Legacy table (equity-only, per-strategy naming) if ever needed:
  `cd .../Data-Preprocessor && python3 scripts_5yr/live/current_pnl.py alpaca`
  (system python3 — the repo venv lacks alpaca-py).

## Quick Reference
| Group | Day-P&L definition |
|-------|--------------------|
| alpaca (6 bots) | `equity − last_equity` per real paper account (incl. unrealized) |
| venturevd | same, single account |

## Common Mistakes
- Running the script with the repo venv python (ModuleNotFoundError: alpaca) — use system python3.
- Alpaca ConnectTimeout is intermittent; script retries 3×, else re-run.
- Strictly read-only — never add order logic here.
