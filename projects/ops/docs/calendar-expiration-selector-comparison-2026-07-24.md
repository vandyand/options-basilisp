# Calendar Expiration Selector Comparison

**Study date:** 2026-07-24

**Status:** historical development evidence complete; forward confirmation pending

**Locked data read:** no

## Question and frozen comparison

The earlier SPY study and QQQ/IWM replication used different expiration
conventions. SPY could select any listed expiration near 7 and 42 DTE, while
QQQ/IWM were restricted to a Thursday/Friday front and a standard-monthly
back. That made the combined portfolio heterogeneous and left open whether
the symbol differences or the expiration selector caused the result.

Before inspecting alternate-selector outcomes, the study froze two policies:

1. **Granular 7/42:** any listed front from 7-9 DTE nearest 7 and any listed
   back from 37-47 DTE nearest 42.
2. **Weekly/monthly:** a Thursday/Friday front from 3-10 DTE nearest 7 and a
   standard third-Friday monthly back from 21-63 DTE nearest 42.

Both used the same 12:01 ET marketable entry, the same 15:15 ET exit exactly
five source-index sessions later, the same common-strike construction, four
$0.65 contract-side fees, and the same short-expiration eligibility rule.
Only dates valid under both selectors were paired. Connected clusters of
overlapping five-session positions were bootstrapped, and the three symbol
tests received a Holm family-wise correction.

The evidence uses 445 development sessions beginning 2024-07-18. October
2025 and July 2026 remained excluded and unread. SPY reused its complete
wildcard snapshot panel. QQQ and IWM each required 890 compact wildcard
snapshots at 12:01 and 15:15. QQQ occupied 120,664,975 bytes and IWM
127,142,989 bytes.

## Diagonal result

Granular 7/42 beat weekly/monthly in one-lot executable net P&L for all three
symbols:

| Symbol | Paired dates | Granular minus weekly/monthly | Cluster 95% interval | Holm-adjusted p |
|---|---:|---:|---:|---:|
| SPY | 203 | +$18.66 | +$10.99 to +$25.05 | 0.00030 |
| QQQ | 183 | +$19.64 | +$7.84 to +$29.81 | 0.00480 |
| IWM | 177 | +$7.20 | +$0.31 to +$14.68 | 0.01910 |

The profile summaries did not show a material liquidity or tail-risk collapse.
Granular win rates were 71.7% for SPY, 77.1% for QQQ, and 68.1% for IWM. The
corresponding weekly/monthly win rates were 68.7%, 76.4%, and 63.9%.

The 2x fixed-priority portfolio was descriptive rather than an independent
test. Using every eligible date, all-granular produced $23,059 net P&L and an
11.85% realized-exit CAGR, versus $14,860 and 7.74% for all-weekly/monthly.
Its realized-exit maximum drawdown was slightly worse: -1.65% versus -1.34%.
These Sharpe and drawdown figures omit intrahold mark-to-market paths and must
not be interpreted as final deployable risk estimates.

## Mechanism follow-up

The diagonal comparison changed both option legs simultaneously. A second
contract was therefore frozen before either hybrid cell was inspected. It
formed a 2x2 design:

- **GG:** granular front, granular back;
- **GM:** granular front, standard-monthly back;
- **WG:** Thursday/Friday front, granular back;
- **WM:** Thursday/Friday front, standard-monthly back.

Only dates marketable in all four cells were retained. The main front effect
averages GG-WG and GM-WM. The main back effect averages GG-GM and WG-WM.

| Symbol | Flexible-front P&L effect | Cluster 95% interval | Adjusted p | Flexible-back P&L effect | Cluster 95% interval |
|---|---:|---:|---:|---:|---:|
| SPY | +$17.85 | +$12.74 to +$23.15 | 0.00060 | +$0.81 | -$5.66 to +$7.03 |
| QQQ | +$24.73 | +$18.28 to +$32.62 | 0.00060 | -$5.01 | -$16.09 to +$3.86 |
| IWM | +$9.37 | +$3.72 to +$15.16 | 0.00160 | -$2.17 | -$5.31 to +$0.85 |

The result is unusually consistent: allowing Tuesday/Wednesday front
expirations is the useful change. Back-expiration flexibility has no reliable
positive P&L effect. Its average return effect is negative for all three
symbols; the QQQ return interval excludes zero on the negative side.

On the dates shared by all four cells, GM slightly outperformed GG at the
portfolio level: $20,602.60 versus $20,253.00, 10.70% versus 10.53%
realized-exit CAGR, and -1.33% versus -1.41% realized-exit drawdown. That small
difference is not independently confirmed. It does suggest that the standard
monthly back is a sensible capital-efficient default while the granular back
remains a useful forward comparator.

## Decision boundary

Historical evidence supports making the **front selector granular for SPY,
QQQ, and IWM**. It does not justify claiming that a granular back is better.
The research candidate for forward observation is therefore granular front +
standard-monthly back, with fully granular retained as a parallel quote-only
comparator.

This follow-up was motivated by the already-observed diagonal result and is
not independent confirmation. No locked period was opened, and no Panda
broker order was authorized. Promotion requires prospective quote-only
evidence and then a separately authorized paper-order decision.

## Artifacts

- Frozen diagonal contract:
  `resources/research/calendar-expiration-selector-comparison-v1.json`
- Frozen factorial follow-up:
  `resources/research/calendar-expiration-factorial-followup-v1.json`
- Complete diagonal report:
  `D:\SteveTradingData\derived\v1\calendar-expiration-selector-comparison-v1\complete\report.json`
- Complete factorial report:
  `D:\SteveTradingData\derived\v1\calendar-expiration-factorial-followup-v1\complete\report.json`
