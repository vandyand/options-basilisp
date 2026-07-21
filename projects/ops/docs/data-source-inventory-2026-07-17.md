# Current data-source inventory — 2026-07-17

This is a concrete, scope-limited inventory for the collection universe currently under consideration. It is **not** a claim about every instrument sold by each vendor. Counts are date-sensitive and must be refreshed before any new collection run.

## Read this first: what the numbers mean

Most confusion here comes from three different levels of “thing”:

1. A **root** is a family selector. `ES` means the E-mini S&P 500 futures family; it is not one tradeable contract.
2. An **instrument/contract** is one tradeable item. For example, `ESU6 P7150` means one specific ES futures put: September 2026 expiry, put, 7,150 strike.
3. An **event** is one price/book/trade update for one instrument. Events are what arrive in the live stream.

`ES.FUT` therefore means “give me the ES futures family,” which expands to individual future contracts such as the September and December contracts, plus separately listed spreads. It does **not** mean one instrument called `ES.FUT`.

| Data group | Root or ticker symbols in our scope | Actual tradeable instruments per root/ticker | Approx. events per minute | Are these counts from one five-minute period? |
| --- | ---: | --- | ---: | --- |
| Databento GLBX futures | 6 roots: ES, NQ, RTY, ZN, ZB, SR3 | 3–46 outright futures per root; separately, 4–1,142 spreads per root | Not yet profiled in this inventory | **No.** Reference definitions as of 2026-07-16. |
| Databento GLBX ES futures options | 1 root tested: ES | 1,823–1,930 ordinary option contracts emitted updates in each five-minute capture | 123,000–265,000; about 193,000 average | **Yes.** Four five-minute captures on 2026-07-17. |
| Databento EQUS.MINI | 15 ordinary stock/ETF tickers | Exactly 1 instrument per ticker | Not measured here | **No.** Reference definitions. |
| ThetaData listed options | 5 roots: SPY, SPX, SPXW, VIX, VIXW | 400–19,202 current call/put contracts per root | Not measured with a comparable event recorder yet | **No.** Current chain snapshots. |
| ThetaData indexes | 7 index symbols | Exactly 1 index level per symbol | Sparse/change-driven; not measured here | **No.** Fixed symbol list. |

The 15 EQUS.MINI “definitions” are simply these 15 individual stock/ETF tickers: SPY, QQQ, IWM, AAPL, MSFT, NVDA, AMD, TSLA, AMZN, META, GOOGL, NFLX, AVGO, PLTR, and XLF. A **definition** is Databento’s small metadata record describing an instrument; it is not a five-minute data block and not 15 observations.

## What was measured

| Source | Measurement | Time basis | Cost |
| --- | --- | --- | ---: |
| Databento GLBX.MDP3 | Provider `definition` records for six requested parent symbols | 2026-07-16 reference day | $0.00 |
| Databento EQUS.MINI | Provider `definition` records for the selected 15 symbols | 2026-07-16 reference day | $0.00 |
| ThetaData option terminal | A successful current quote snapshot for every non-expired expiry returned by the terminal | Live terminal, 2026-07-17 | $0.00 incremental |

`definition` is reference metadata, not event data. It is the correct small request for discovering what a Databento parent symbol expands into.

## Databento GLBX.MDP3 — futures

Databento parent symbols such as `ES.FUT` expand into both outright futures and exchange-defined futures spreads. The counts below are definition records, each with a unique Databento instrument ID; a spread is deliberately shown separately rather than silently treated as an outright contract.

| Parent/root | Outright futures (`F`) | Futures spreads (`S`) | Total definitions |
| --- | ---: | ---: | ---: |
| ES | 21 | 20 | 41 |
| NQ | 12 | 10 | 22 |
| RTY | 11 | 55 | 66 |
| ZN | 3 | 4 | 7 |
| ZB | 3 | 4 | 7 |
| SR3 | 46 | 1,142 | 1,188 |
| **Total** | **96** | **1,235** | **1,331** |

Of the 1,331 definitions, 1,319 had an expiry after the reference day. The contract counts are plainly not uniform across roots: SR3's large exchange-defined spread catalogue is the main reason. Our intended initial collection universe should default to the 96 outright futures, with spreads a separately justified expansion.

## Databento GLBX.MDP3 — futures options

The same provider reference pull was made for `ES.OPT`, `NQ.OPT`, `RTY.OPT`, `ZN.OPT`, `ZB.OPT`, and `SR3.OPT`. It returned definitions for only ES, NQ, and SR3 on this reference day. That is a concrete result, not an assumption that every futures root has an option chain in this entitlement/dataset.

| Parent/root | Calls (`C`) | Puts (`P`) | Plain calls + puts | Other native definitions (`T` / `M`) | All returned definitions |
| --- | ---: | ---: | ---: | ---: | ---: |
| ES | 1,433 | 1,433 | 2,866 | 1,492 | 4,358 |
| NQ | 928 | 928 | 1,856 | 532 | 2,388 |
| SR3 | 1,554 | 1,554 | 3,108 | 6,755 | 9,863 |
| RTY | 0 | 0 | 0 | 0 | 0 |
| ZN | 0 | 0 | 0 | 0 | 0 |
| ZB | 0 | 0 | 0 | 0 | 0 |
| **Total** | **3,915** | **3,915** | **7,830** | **8,779** | **16,609** |

`C` and `P` are the normal plain call and put contracts. `T` and `M` are retained as Databento's native instrument classifications (rather than guessed into a contract type); they are not part of the 7,830 plain-option count. ES and NQ are admitted to the hard corpus. SR3 remains probationary. RTY, ZN, and ZB returned no contracts under the tested option parents.

### ES futures-options live-versus-historical test — Friday evening result

The planned same-session test has now run. This is the actual event-stream check, not a comparison of one-second bars.

| Scope | Result |
| --- | --- |
| Live windows | Four separate five-minute ES option captures: 10:38, 12:29, 13:30, and 15:30 ET |
| Quote/book contract sample | 24 activity-stratified ordinary ES option contracts per window (96 contract-window checks); the samples cover low through high update rates |
| Exact quote/book result | 48,222 matched events; **zero** live-only and **zero** historical-only events inside the common event-time interval |
| Boundary behavior | 73 live-only and 163 historical-only events occurred only outside the common interval, because the live recorder slightly overran its nominal end while the historical request included a small leading interval |
| Trade result | All 108 ordinary ES option trades, across 43 contract-window instances, matched exactly |
| Fields compared | Every DBN market field, including event timestamp, sequence, side, price, size, and book fields; only transport/receipt timestamps were excluded |
| Decision | ES futures-option MBP-1 and trades are admitted to the parity-qualified corpus under this exact capture-boundary rule. |

The individual receipts and machine-readable comparisons are under `D:\SteveTradingData\manifests\v1\databento-live-validation`.

### NQ and SR3 Monday live study — 2026-07-20 status

The first Monday five-minute parent capture contained 1,052,506 MBP-1 events across 6,728 mapped active instruments. Within ordinary options, 1,925 ES, 532 NQ, and 1,945 SR3 contracts emitted events. Six ES and one NQ ordinary trades matched the intraday historical replay exactly; SR3 emitted no ordinary option trades in that window. Databento's explicitly unfinalized metadata overstated the exact-contract MBP-1 request as 16.4 GB, so the 200 MiB safety gate correctly blocked it pending finalized metadata.

NQ MBP-1 and trades were explicitly admitted by the owner on 2026-07-20. This is recorded as an owner-directed hard admission: the one observed NQ trade was exact, while finalized NQ MBP-1 and broader trade replication remain scheduled follow-up evidence. SR3 did not inherit that decision and remains probationary.

## Databento EQUS.MINI — equities and ETFs

EQUS.MINI is an equities/ETF dataset, not futures and not equity options. The selected universe has one security definition per requested ticker—there is no root-to-contract expansion.

| Selected symbols | Definitions returned | Contract expansion |
| --- | ---: | --- |
| SPY, QQQ, IWM, AAPL, MSFT, NVDA, AMD, TSLA, AMZN, META, GOOGL, NFLX, AVGO, PLTR, XLF | 15 | None — 15 equities/ETFs |

EQUS.MINI is a derived multi-venue composite dataset. It is not the official NBBO and it contains no options feed.

## ThetaData — listed US options and indexes

ThetaData option chains are dynamic; there is no static `definition` file. We therefore count a contract only if its current quote snapshot was successfully returned by the terminal. The terminal returned 134 non-expired expiry metadata rows; 26 were unusable far-future metadata (eight SPX and 18 SPXW), while 108 snapshots returned a nonempty current chain. This avoids an arbitrary DTE cutoff while not mistaking metadata for a tradeable contract.

| Option root | Non-expired expiry metadata | Nonempty current snapshots | Calls | Puts | Plain option contracts |
| --- | ---: | ---: | ---: | ---: | ---: |
| SPY | 34 | 34 | 7,015 | 7,015 | 14,030 |
| SPX | 29 | 21 | 5,227 | 5,227 | 10,454 |
| SPXW | 58 | 40 | 9,601 | 9,601 | 19,202 |
| VIX | 9 | 9 | 560 | 560 | 1,120 |
| VIXW | 4 | 4 | 200 | 200 | 400 |
| **Total** | **134** | **108** | **22,603** | **22,603** | **45,206** |

The ThetaData index set is seven individual index symbols—NDX, RUT, RVX, SPX, TNX, VIX, and VIXN—not option-contract universes.

## Explicit exclusions

- Databento OPRA equity options: historical/catalog access is not enough; the entitlement audit showed no live OPRA license. It is not part of the parity-qualified corpus.
- Databento EQUS.MINI options: none exist in that dataset.
- ThetaData stock events: quarantined because live NQB and historical UTP/CTA are different feeds.
- GLBX SR3 futures-option events: live MBP-1 is available, but parity certification is pending and no ordinary SR3 option trade was observed in the first Monday window.
- GLBX RTY/ZN/ZB futures-option parents: unavailable under the tested dataset/symbology; both reference inventory and isolated live definition probes returned zero contracts/events.

## Receipts

- [GLBX futures manifest](D:/SteveTradingData/manifests/v1/databento/GLBX.MDP3/hard/databento-glbx-futures-reference-inventory/trade_date=2026-07-16/run=20260717T192514340957Z.json)
- [GLBX futures-options manifest](D:/SteveTradingData/manifests/v1/databento/GLBX.MDP3/probationary/databento-glbx-futures-options-reference-inventory/trade_date=2026-07-16/run=20260717T192729160677Z.json)
- [EQUS.MINI manifest](D:/SteveTradingData/manifests/v1/databento/EQUS.MINI/hard/databento-equs-mini-reference-inventory/trade_date=2026-07-16/run=20260717T192955326119Z.json)
- [Decoded GLBX futures inventory](D:/SteveTradingData/manifests/v1/source-inventory/databento-glbx-futures-20260716.json)
- [Decoded GLBX futures-options inventory](D:/SteveTradingData/manifests/v1/source-inventory/databento-glbx-futures-options-20260716.json)
- [Decoded EQUS.MINI inventory](D:/SteveTradingData/manifests/v1/source-inventory/databento-equs-mini-20260716.json)
