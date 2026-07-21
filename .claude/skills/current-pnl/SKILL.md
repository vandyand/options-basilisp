---
name: current-pnl
description: Use when the user runs /current-pnl, $current-pnl, or asks for today's P&L across SteveTrading live Alpaca, local sim, and VentureVD accounts. Optional groups: all|alpaca|sim|venturevd|trades (default all).
---

# Current P&L

## Overview
Prints today's per-strategy P&L as Markdown tables. The six Alpaca paper
accounts (CHESTNUT/LYNX/MOOSE/PARROT/OAK/DOLPHIN), local sim fleets, volatility
sim strategies, V2 rows, and VentureVD are read through the Basilisp P&L CLI.
Read-only (no orders).

## Core Pattern
Run the Basilisp wrapper. It defaults to all groups and Markdown output:

```bash
~/.codex/skills/current-pnl/scripts/current-pnl "${ARG:-all}"
```

Equivalent repo-local command:

```bash
cd /home/kingjames/contracting/upwork/steven-tran/stevetrading-basilisp
.venv/bin/basilisp run scripts/current_pnl.lpy -- "${ARG:-all}" --markdown
```

Display every table returned. Do not collapse rows for brevity. Alpaca live
paper accounts belong under `HETZNER / LIVE ALPACA PAPER`; sim accounts and
strategy rows belong under `LOCAL / SIM EXPERIMENTS` and/or `LOCAL / SIM
SHADOWS`. Volatility and V2 rows such as `VOL-TERM`, `SIM-VOL-*`,
`SIM-TERM-*`, `V2-TERM-*`, and `V2-VOL-*` must be shown when present.

## Quick Reference
| Group | Day-P&L definition |
|-------|--------------------|
| alpaca (6 bots) | `equity − last_equity` per real paper account (incl. unrealized) |
| sim | local fact-store/sim broker P&L, including active volatility and V2 rows |
| venturevd | same, single account |

## Common Mistakes
- Omitting flat V2/VOL rows; zero-P&L activity rows are still operational evidence.
- Combining Alpaca and sim strategies into one table; keep live broker and sim rows separate.
- Alpaca ConnectTimeout is intermittent; the Basilisp script retries, else re-run.
- Strictly read-only — never add order logic here.
