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
Six production accounts — MUST use system python3 (the repo venv lacks alpaca-py):

```bash
cd /home/kingjames/contracting/upwork/steven-tran/SteveTrading/ref/Data-Preprocessor
python3 scripts_5yr/live/current_pnl.py alpaca 2>&1 | grep -vE 'Warning|pandas|bottleneck'
```

venturevd dev account (when asked, or arg venturevd):

```bash
eval "$(grep '^export ALPACA_VENTUREVD_' ~/.bashrc)"
curl -s -H "APCA-API-KEY-ID: $ALPACA_VENTUREVD_API_KEY" \
     -H "APCA-API-SECRET-KEY: $ALPACA_VENTUREVD_API_SECRET" \
     https://paper-api.alpaca.markets/v2/account | \
  python3 -c "import json,sys; d=json.load(sys.stdin); print('VENTUREVD today:', float(d['equity'])-float(d['last_equity']), '| equity:', d['equity'])"
```

`sim` arg: the old Python sim-broker table — DEFUNCT since the Python stack wound
down (2026-06-10); say so rather than running it.

## Quick Reference
| Group | Day-P&L definition |
|-------|--------------------|
| alpaca (6 bots) | `equity − last_equity` per real paper account (incl. unrealized) |
| venturevd | same, single account |

## Common Mistakes
- Running the script with the repo venv python (ModuleNotFoundError: alpaca) — use system python3.
- Alpaca ConnectTimeout is intermittent; script retries 3×, else re-run.
- Strictly read-only — never add order logic here.
