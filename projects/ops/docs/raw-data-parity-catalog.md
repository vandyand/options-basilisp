# Raw Data Parity Catalog

Status: inventory complete for the accessible GCS archive and current V2
captures; archive provenance and byte-level historical equivalence are not yet
certified.

## Purpose

This catalog answers a deliberately narrow question before any feature or model
work: which vendor data classes have both a retained live representation and a
historical representation, and what information is lost or added between them?
It does not treat a model tensor or a legacy feature matrix as raw data.

The executable corpus boundary is
[`resources/thetadata/raw-parity-v1.edn`](../../../resources/thetadata/raw-parity-v1.edn).
It deliberately prioritizes event-native option NBBO, option trades, and
index prices; it quarantines stock events until their distinct live and
historical feed semantics are proven. The manifest fixes the raw landing area,
distinct snapshot and stream receipt fields, initial symbols, and phased collection plan while intentionally
deferring feature selection and vendor Greeks.

## Sources Examined

| Source | Role | What it establishes | What it cannot establish |
| --- | --- | --- | --- |
| `gs://thetadata-raw-bucket` | Historical candidate | Intraminute raw-like event schemas and symbol coverage | Original terminal request, venue, endpoint, receipt watermark, and whether rows were modified before upload |
| `gs://thetadata-feature-bucket` | Legacy derived artifact | The old transformation output | Raw payload parity |
| Current V2 `live_features_*.npz` | Live decision capture | The normalized bars, chain snapshots, and inference state used at a decision | Full vendor event stream or an unselected terminal response |
| `Data-Preprocessor-II` | Legacy transformer | How GCS raw parquet was aggregated into the legacy feature bucket | How raw GCS parquet was downloaded from ThetaData |
| `/mnt/d/options-data` | Local legacy store | Direct-ThetaData historical quote retrieval was retained locally | Independent raw vendor data; stored records already contain derived IV and Greeks |

`Data-Preprocessor-II` was inspected at `main` commit
`3e5f30c598ffaedce2e135d9e6ef37dc22391117` (2026-06-02). It reads
`thetadata-raw-bucket` and writes `thetadata-feature-bucket`; no raw-bucket
writer or ThetaData downloader is present in that repository.

The `/mnt/d/options-data/spy_1min/extraction.log` identifies a separate
historical run: it queried the local ThetaData terminal's
`/v3/option/history/quote` endpoint with `interval=1m`, `right=both`, and a
45-DTE window for SPY from 2024-12-02 through 2026-03-31. It selected only up
to eight expirations per day and logged many `472` failures. The resulting
pickle rows contain `implied_vol`, Black-Scholes Greeks, bid/ask, timestamp,
and underlying price. They are therefore useful evidence of a repeatable
historical query, but not a complete or raw response archive.

## Historical Raw Inventory

The raw bucket contains four data families and 69 symbol-family partitions:

| Family | Symbol partitions | Representative schema | Cadence / semantics |
| --- | ---: | --- | --- |
| Stock | 20 | `symbol,time,size,price,bid_size,bid,ask_size,ask` | Intraminute event rows |
| Index | 7 | `time,symbol,price` | One observation per minute in sampled files |
| Option | 21 | `time,symbol,expiration,strike,option_right,size,price,bid_size,bid,ask_size,ask` | Intraminute event rows |
| Option Greeks | 21 | option identity plus `bid,ask,delta,theta,vega,rho,epsilon,lambda,implied_vol,iv_error` | Intraminute rows |

The archive includes stock data for `SPY,HYG,TLT,VXX`; index data for
`SPX,TNX,VIX`; and option plus option-Greek data for
`SPY,SPX,SPXW,VIX,VIXW`. Thus it contains historical candidates for every
currently relevant underlying, but that is only class coverage, not parity.

## Active ThetaData Entitlements

The production terminal logged the following active product tiers on 2026-07-11:

| Data family | Terminal entitlement | Practical scope for this study |
| --- | --- | --- |
| Stock | `PROFESSIONAL` | Real-time and historical tick-level stock data, with eight concurrent requests |
| Options | `STANDARD` | Real-time option quote/OHLC/open-interest snapshots; tick-level historical quotes, OHLC, open interest, implied volatility, and first-order Greeks; four concurrent requests |
| Index | `PROFESSIONAL` | Real-time and historical lowest-reported index data from 2017, with eight concurrent requests |
| Rates | `FREE` | EOD-only rate data from 2024; not an intraday source |

The July 10 capability probe empirically confirmed usable option expiration and
quote snapshots for `SPY,SPX,SPXW,VIX,VIXW`, option OHLC and open-interest
snapshots for SPY, stock quote/trade/OHLC snapshots for the required stocks,
and index price snapshots for SPX and VIX. Every future capture must persist
the terminal-reported entitlement string and endpoint outcome alongside its
payload, because entitlement changes alter the available data contract.

Options `STANDARD` is sufficient for the first-order Greek endpoints, but not
for second- or third-order or trade-Greek history. This product-tier label is
separate from OPRA's professional/non-display licensing classification; the
automated use case must remain correctly licensed independently.

## Live/Historical Pairing Status

Having both a live and a historical endpoint does not itself prove that their
feeds or semantics match. The current status is:

| Data class | Candidate pair | Status |
| --- | --- | --- |
| Option NBBO quotes | Standard quote stream -> exact-contract historical quote events | Proven on a deterministic 32-contract, millisecond-exact sample across SPY, SPX, SPXW, VIX, and VIXW. Snapshot/at-time comparisons remain diagnostics because separately fetched snapshots can move between requests. |
| Option OHLC, volume, count | Live session snapshot -> historical option OHLC interval | Candidate only. The live snapshot is session state, so a strategy must define its own completed intraminute aggregation. |
| Option open interest | Live snapshot -> historical open-interest | Proven on the July 13 market-open captures for SPY, SPX, SPXW, VIX, and VIXW. It remains prior-session daily state, not intraminute flow. |
| Vendor IV / first-order Greeks | Snapshot Greek endpoint -> historical Greek endpoint | Strict vendor parity is not established. A July 13 five-root exact-timestamp probe found zero strict passes: snapshot and historical calculations can use different underlying timestamps, causing small derived-value differences. Do not use as canonical model input; prefer locally deterministic reconstruction from parity-proven option inputs. |
| Stock quotes and trades | Live Nasdaq Basic (`nqb`) -> current-session `nqb` historical stock quote/trade | **Conditional / not admitted for long-horizon training.** July 13 exact-event checks showed 100% trade equality for a 12-symbol, 5.2-minute event-time sample, but only 81.59% raw quote-event equality. A causal last-quote-per-minute state recovered 83/84 shared one-minute buckets, not 84/84. `utp_cta` is a distinct long-horizon feed: 0% raw-quote equality and only 16.28% raw-trade equality in that sample. A prior-date `venue=nqb` probe returned byte-identical `utp_cta` payloads, so `nqb` must not be assumed to be retained historical Nasdaq Basic provenance. |
| Alpaca IEX trades | IEX websocket -> IEX tick-trade history | **Provisional candidate, not yet broadly admitted.** July 14 expanded capture matched every event: 4,362/4,362 across the 20-symbol diagnostic cohort and two independent windows. Establish multi-day / older-history coverage before promotion. |
| Alpaca IEX quotes | IEX websocket -> IEX tick-quote history | Raw event equality is not strict: July 14 expanded capture had 30 persistent live-only events out of 246,955 (zero historical-only), 28 DIA events in the first window and 2 XLF events in the second. **The causal last-quote state is admitted at 10-ms-or-coarser resolution:** all 1,076,079 shared 10-ms buckets (and therefore all 100-ms, 500-ms, one-second, and one-minute buckets) were exact across both windows. Preserve the raw stream as evidence, but train and infer only on the declared causal state representation. |
| Stock completed bars | Live completed-bar query -> historical OHLC | Candidate only until the same venue and retention behavior are proven for the training horizon. |
| Index prices | Live price updates -> historical index prices | Proven on exact intraminute SPX and VIX checks. Messages are sparse when prices do not change, so replay must still carry the prior price forward under the same rule. |
| Trade/quote joins | Historical `trade_quote` -> live quote and trade streams | No direct live endpoint. It is usable only as a locally defined join with an identical event-time/watermark policy. |

This means Options Standard can support an event-native strategy and a
historical replay built from the same raw quote classes. Stock and index data
remain useful, but their venue and event-state semantics must be proven before
they are admitted to the same training corpus.

## Canonical Corpus Admission (July 14 decision)

The canonical intraminute corpus is deliberately narrower than the set of
useful data.  A source is admitted only with its precise live and historical
contract, rather than admitting an entire vendor or asset class.

| Canonical input | Contract | Decision |
| --- | --- | --- |
| Option NBBO quote events | ThetaData OPRA quote stream -> exact-contract tick quote history | **Admitted.** Preserve contract, event timestamp, endpoint parameters, and capture receipt timestamp. |
| Option trade events | ThetaData OPRA trade stream -> exact-contract tick trade history | **Admitted.** Preserve the same provenance fields. |
| Index price events | ThetaData index-price stream -> index tick-price history | **Admitted.** The stream is change-only; build regular grids by causal carry-forward under one shared implementation. |
| Locally derived IV / Greeks | Deterministic calculation from the admitted option events and a declared observation watermark | **Admitted as derived data.** Do not substitute vendor snapshot Greeks or IV. |
| Option open interest | Snapshot -> daily OI history | **Excluded from the intraminute canonical corpus.** It is a prior-session daily state, not live intraminute flow. It may be retained separately for a future explicitly as-of-prior-close feature study. |
| ThetaData stocks | Live NQB -> historical UTP/CTA or retained NQB | **Quarantined.** Current-session NQB evidence does not establish the required long-horizon same-feed replay. |
| Alpaca IEX trades | IEX websocket -> IEX tick-trade history | **Research candidate, separately namespaced.** The July 14 20-symbol test is exact for two windows, but a multi-day / older-history study is still required before promotion. |
| Alpaca IEX quote state | IEX websocket quote events -> IEX tick-quote history -> causal last-quote state | **Admitted at 10-ms-or-coarser resolution.** July 14 expanded evidence is exact for every tested 10-ms bucket (1,076,079), and consequently for all tested 100-ms, 500-ms, one-second, and one-minute buckets. Raw IEX quote events remain excluded because their event multisets differ. |

An IEX feature must retain `provider=alpaca`, `feed=iex`, and its endpoint
semantics through training and live inference.  It must never be joined as if
it were a ThetaData NBBO/UTP/CTA observation.  The research question is
whether an independently replayable IEX-only signal adds incremental,
out-of-sample value after costs; lack of parity and lack of alpha are distinct
reasons to reject it.  At present, that question may use IEX trades and the
admitted 10-ms causal IEX quote state.  Raw IEX quote events remain
excluded; every IEX quote feature must be computed from the shared state
representation, never directly from event count/order.

### Databento Corpus Admission (July 16)

The executable Databento admission manifest is
[`resources/databento/raw-parity-v1.edn`](../../../resources/databento/raw-parity-v1.edn).
It is deliberately separate from the ThetaData manifest: provider, dataset,
symbology, event semantics, and available history differ. Admission below is
to the **parity-qualified research corpus**, not automatic authorization to
alter an existing Steve feature vector or live strategy.

For event classes, `Hard` requires at least 99.0% shared-interior matches in
the declared representation. Boundary-only events are excluded from the rate;
all interior residuals and root-level rates remain recorded even after
admission.

| Canonical input | Contract | Tier | Decision |
| --- | --- | --- | --- |
| GLBX completed OHLCV 1-second bars | `GLBX.MDP3` live -> historical, parent symbology, six-root futures/rates basket | **Hard** | **Admitted.** July 16 captured 2,265 complete bars and every OHLCV field matched exactly. The subscription-start partial bar is excluded. |
| GLBX completed OHLCV 1-minute bars | Same | **Hard** | **Admitted.** 241 complete bars matched exactly; exclude the partially observed start minute. |
| EQUS Mini completed OHLCV 1-second bars | `EQUS.MINI` live -> historical, raw-symbol symbology, 15-symbol equity basket | **Hard** | **Admitted with source qualifier.** 3,077 complete bars matched exactly. EQUS Mini is a Databento-derived top-of-book composite, not SIP/NBBO or a direct exchange. |
| EQUS Mini completed OHLCV 1-minute bars | Same | **Hard** | **Admitted with source qualifier.** 135 complete bars matched exactly. Preserve the same derived-composite provenance. |
| GLBX MBP-1 L1 events | `GLBX.MDP3` live -> historical, parent symbology | **Hard** | **Admitted.** Of 742,279 captured events, 742,277 match exactly after excluding live/history transport timestamps. One SR3 spread event differs only in side; one live event is the end-exclusive boundary. The residual evidence and declared representation remain binding. |
| GLBX trade events | `GLBX.MDP3` live -> historical, parent symbology | **Hard** | **Admitted.** The July 16 study matched every economic trade field; sixteen records differed only in Databento `F_LAST`. The unfinalized July 20 SR3-only stratum matched 710/716 trades (99.1620%), above the 99.0% floor, with six one-for-one residual pairs across four SR3 symbols. Preserve root-level rates and rerun against the finalized archive. |
| EQUS Mini MBP-1 L1 events | `EQUS.MINI` live -> historical | **Hard** | **Admitted.** 617,582/618,214 events matched (99.8978%); 632 were live-only and zero historical-only after transport timestamps were excluded. Preserve the derived-composite provenance; prohibit exact event-count, sub-bar order, event-arrival, and sequence-sensitive features. |
| EQUS Mini trade events | `EQUS.MINI` live -> historical | **Hard** | **Admitted.** 8,355/8,360 events matched (99.9402%); five were live-only and zero historical-only after transport timestamps were excluded. The same raw-event feature restrictions apply. |

The July 16 archive was still marked provisional by Databento during the
intraday requests. Therefore every GLBX raw seed session must receive the
same cost-gated comparison after the historical archive finalizes. A
finalized-session mismatch beyond the enumerated representation rules blocks
the class from entering model training, even though it remains a useful live
diagnostic source. This is an admission rule, not a claim that vendor archive
finalization is irrelevant.

#### Databento History Horizon and Cost Scope

No admitted Databento class has only one year of *retained* history. GLBX
completed bars and raw data begin in 2010 (the MBO/L3 archive begins later,
but it is not live-entitled); EQUS Mini begins in March 2023. The important
training constraint is instead the current entitlement's included range:

| Admitted class | Retained history | Included at $0 under the current entitlement, verified July 16 | Corpus implication |
| --- | --- | --- | --- |
| GLBX completed OHLCV 1s / 1m | Since 2010 | Multi-year range through the current date | Suitable for long-horizon bar research. |
| GLBX MBP-1 / trades | Since 2010 | Approximately a rolling one year; older raw data is usage-billed | A no-additional-cost raw-event seed corpus is roughly one year. Do not describe this as two years unless a cost-approved download is made. |
| EQUS Mini completed OHLCV 1s / 1m | Since March 2023 | Entire available range through the current date | Roughly three-plus years of bar history. |
| EQUS Mini MBP-1 / trades | Since March 2023 | Approximately a rolling one year; older raw data is usage-billed | A no-additional-cost raw-event seed corpus is roughly one year. |

Every historical download must still pass the cost gate before submission.
“Included at $0” is an entitlement observation from the July 16 metadata
checks, not a promise that Databento's commercial terms will never change.

### IEX Raw-Event Boundary (Do Not Confuse With Stream Reliability)

The Alpaca IEX websocket was healthy in the July 14 expanded study. The
boundary is not that live data must be polled, delayed, or discarded: live
inference should consume the websocket continuously and maintain its latest
quote state. The historical IEX tick endpoint later omitted a very small set
of individual websocket quote events, so an exact raw event sequence cannot
be reconstructed with a hard guarantee.

Observed scope: of 246,955 quote events over two same-day windows and 20
symbols, 30 (0.01215%) were live-only and none were historical-only. The 28
first-window omissions were DIA events; the 2 second-window omissions were
XLF events. The other 18 symbols had no observed raw-event mismatch. This is
evidence for this capture, not a promise that omissions cannot occur for
those symbols or on another day.

Policy:

- **Canonical hard-parity branch:** causal L1 quote state at a completed
  10-ms bucket or coarser. This matched exactly in every tested bucket.
- **Experimental near-parity branch:** raw event-count, event-arrival, or
  sub-10-ms ordering features. They may be researched, but must be labelled
  near-parity, evaluated separately, and never described as identical live
  versus historical replay.

### OANDA FX Candidate (July 14)

OANDA is not a raw-stream parity candidate. Its v20 pricing stream is capped
at four updates per second and each connection has independently aligned
250-ms windows; during rapid movement, it can omit intermediate prices and
different subscribers can observe different updates. There is no compatible
historical raw-stream endpoint. The OANDA hard-parity candidate is therefore
the **completed bid/ask S5 or M1 candle**: live
`pricing/candles/latest` versus historical `instruments/{instrument}/candles`,
with unsmoothed `BA` candles and exact `time,bid,ask,volume` comparison.

A short July 14 test at the 17:00 America/New_York FX rollover passed 8/8
completed candles, confirming endpoint access and harness mechanics only. It
is excluded from parity admission because the rollover is a low-liquidity,
spread-distorted daily transition. A following 30-minute read-only
production-endpoint capture over EUR/USD, GBP/USD, USD/JPY, USD/CHF, USD/CAD,
AUD/USD, and NZD/USD passed 1,315/1,315 completed S5/M1 bid/ask candles with
zero missing, differing, or live-capture-conflict records. This is a
provisional hard-parity completed-candle candidate; the independently
scheduled July 15 08:00 ET liquid-session run must reproduce it before full
corpus admission.

### Binance USD-M Futures REST Kline Candidate (July 14)

The available Windows and VPS networks can connect to Binance Futures public
WebSocket endpoints but did not receive market messages; Windows Futures REST
is also region-restricted (HTTP 451). The VPS can access public Futures REST,
so the current candidate is **live REST polling**, not a WebSocket stream and
not an API-key-dependent source.

The zero-lag version of this contract failed: a kline whose nominal close time
had elapsed was still revised by REST. Across BTCUSDT/ETHUSDT/SOLUSDT, 10/24
candles later differed and 350 polling observations showed a same-candle
revision. With an explicit 10-second post-close completion watermark, every
field of 21/21 completed one-minute candles matched later history exactly:
OHLC, base/quote volume, trade count, and taker-buy base/quote volume. This
is a provisional hard-parity **one-minute, 10-second-lag REST-polling**
candidate. Require multi-session and older-history validation before full
corpus admission. Do not use zero-lag closes or claim Binance WebSocket
parity from this evidence.

### Bitunix Futures Kline Candidate (July 14 — Rejected)

Bitunix public futures data is valuable to test because it offers continuously
traded crypto-perpetual market context without account authority. It is not
currently admissible as a live-stream/historical-parity source. The public
`market_kline_1min` WebSocket updates an in-progress candle every 500 ms;
the historical REST endpoint returns the server-finalized one-minute candle.

In the BTCUSDT/ETHUSDT/SOLUSDT six-minute study, the final WebSocket update
for each completed minute was compared with `LAST_PRICE` REST history. There
were no missing minute buckets, but only 4/18 full candles matched. All 14
mismatches had both volume fields different; 5 also had different closes, and
one each had a different high or low. Even OHLC alone was only 13/18 exact.
Therefore Bitunix streamed one-minute klines, and any features based on their
volume or final OHLC, are excluded from both hard- and high-parity corpus
branches. A future, distinct study could test *live REST polling of confirmed
completed candles* against REST history; it must not inherit this result.

## Endpoint-Completeness Decision

The catalogue is feature-agnostic, but it is not endpoint-count-agnostic.
Several endpoints expose the same underlying raw class in a different form.
The collection contract records the base class once and identifies those
alternate views explicitly, rather than silently omitting them or treating a
vendor aggregate as a new source.

| Vendor data class | Live representation | Historical representation | Collection decision |
| --- | --- | --- | --- |
| Option NBBO quote | OPRA quote stream; quote snapshot | tick quote history; at-time quote | Primary event capture; snapshot/at-time diagnostic is retained separately. |
| Option trade | OPRA trade stream; trade snapshot | tick trade history | Primary event capture. Snapshot is a last-event view of the same class. |
| Option open interest | snapshot | daily open-interest history | Excluded from the intraminute canonical corpus. Retain only as separately labeled prior-session daily state if a future study needs it. |
| Option OHLC / count / volume | snapshot | historical OHLC | Not a new base class: vendor aggregation over option trade/quote events. A future corpus may define an aggregation only after its policy is declared. |
| Option trade-quote | none | historical trade-quote | Excluded as a vendor join; reproduce locally from captured quote and trade events with an explicit event-time rule. |
| Vendor IV and Greeks | snapshots | historical IV / Greek endpoints | Explicitly excluded from the canonical raw corpus. They are vendor-derived fields; local deterministic reconstruction is the preferred later path. |
| Option EOD | no intraday live equivalent | EOD history | No clean live counterpart. |
| Stock NBBO quote | Nasdaq Basic quote stream / snapshot | current-day `nqb` history; long-horizon `utp_cta` history | Use `nqb` for direct live equality. Retain `utp_cta` as a distinct long-horizon research source and validate it on its own provenance, not against the live feed. |
| Stock trade | Nasdaq Basic trade stream /snapshot | current-day `nqb` history; long-horizon `utp_cta` history | Same source-policy split as stock quotes. |
| Stock OHLC / count / volume | snapshot | historical OHLC | Vendor aggregate over stock events; not a separate base class. It may be adopted only with an explicit venue and completed-interval rule. |
| Stock trade-quote, EOD, splits | no corresponding raw stream | historical-only endpoints | No clean raw live counterpart. |
| Index price | sparse index trade stream / price snapshot | tick price history / at-time price | Primary event capture with explicit carry-forward replay rule. |
| Index OHLC snapshot | snapshot only | price history, not identical OHLC endpoint | No clean raw counterpart; derive only from admitted index price events. |
| Rates | no intraday stream under the active entitlement | daily history | No intraday live counterpart. |

This classification follows ThetaData's [subscription access matrix](https://docs.thetadata.us/Articles/Getting-Started/Subscriptions.html), [option quote history](https://docs.thetadata.us/operations/option_history_quote.html), [stock at-time quote](https://docs.thetadata.us/operations/stock_at_time_quote.html), and [index price history](https://docs.thetadata.us/operations/index_history_price.html). The stock distinction is intentional: `nqb` is the live/current-day Nasdaq Basic provenance, while historical `utp_cta` is the merged long-horizon feed.

### Stock Provenance Rule, Confirmed July 13

`nqb` is the correct current-session historical selector for direct equality
against the live Nasdaq Basic stream. It is not evidence of a separately
retained Nasdaq Basic archive: querying the July 10 SPY tick window on July 13
with `venue=nqb` and `venue=utp_cta` produced byte-identical responses
(identical SHA-256 and 1,060 rows). Treat prior-session stock history as
UTP/CTA provenance even when a caller supplies `venue=nqb`. This makes the
system policy explicit: current-session NQB is used for live-contract tests;
the retained UTP/CTA corpus is used for long-horizon research/replay with its
own data-source label and validation, never as an expected byte-for-byte copy
of live NQB.

### Next Market Open — NQB Lag and Deterministic Stock Study

Before any stock source is admitted to an intraminute strategy or training
corpus, run this research-only capture and report:

1. Start a **dedicated, lightweight NQB-only** capture at the open (no broad
   option subscription batch) for a fixed basket spanning UTP and CTA names.
   Record both event time and local receive time so source lag is measurable;
   the July 13 recorder ran for roughly 20 wall-clock minutes but observed
   only 5.2 minutes of market-event time.
2. Retain the unmodified live tape, then fetch both same-session `nqb` and
   `utp_cta` histories for the exact closed event-time window. Save every raw
   response before running comparisons.
3. Re-run exact multiset event comparison and causal representations at 1m
   and 5m: last quote state; trade count/OHLC/volume/notional. A representation
   passes only with full bucket coverage and 100% equality, not merely a high
   shared-bucket ratio.
4. Repeat across several full windows and sessions. In particular, explain or
   eliminate the July 13 SPY quote collision: the same millisecond had
   different live versus historical bid/ask state.
5. Keep `utp_cta` labelled as a separate research feed. Do not train an ML
   mapper and call its predictions hard parity; use it, if at all, only as an
   explicitly approximate domain-adaptation experiment.
6. Separate the fixed **parity diagnostic cohort** from any future model
   universe. For model research, persist a daily point-in-time candidate
   universe selected solely from information available before that session
   (for example, prior-day rolling dollar-volume ranks and eligibility
   metadata). Retain symbols that subsequently delist, merge, split, or leave
   the cohort; never backfill historical sessions using a current “most
   liquid” list.

## Recorded Live Inventory

The normal July 9 and July 10 V2 captures contain:

| Retained live object | Symbols | Fields | Classification |
| --- | --- | --- | --- |
| `bar_buffers_json` | `SPY,HYG,TLT,VXX,SPX,TNX,VIX` | `time,open,high,low,close,volume,vwap,trade_count` | Normalized one-minute bars; `SPX,TNX,VIX` are derived proxies, not direct index receipts |
| `option_chain_json` | `SPY` | envelope `observed_at,spy,contracts`; contract `strike,right,bid,ask,bid_size,ask_size,expiration` | Selected ThetaData snapshot, not an event stream |
| `option_surfaces_json` | Empty in normal July 9/10 captures | N/A | Required extra surfaces were not continuously captured yet |
| `grids`, `grid_history_json` | SPY-derived | Greek grid state | Derived, not raw vendor data |
| model tensors | CHESTNUT, LYNX, MOOSE | 918 values per row | Derived model input, not raw vendor data |

Separate July 10 diagnostic sidecars prove that `SPX,SPXW,VIX,VIXW` option
surface snapshots can be retained. They add `count`, `volume`, and
`open_interest` to quote identity and bid/ask fields, but they are one-off
diagnostics rather than a continuous session record.

## Coverage Numbers

Two denominators are necessary.

1. Against the entire GCS raw archive, normal V2 captures retain direct
   source representations for four stock symbols and one option symbol:
   `5 / 69 = 7.2%` of historical symbol-family partitions. The three live
   index values are proxies and therefore do not count as direct index-class
   coverage. Including the four diagnostic option surfaces gives at most
   `9 / 69 = 13.0%`, but that is not continuous coverage.
2. Against the current Steve strategy data universe, GCS has a historical
   candidate for all four required stock symbols and all five relevant option
   symbols. That is `9 / 9 = 100%` symbol-class availability, subject to the
   semantic gaps below.

Field availability is not symmetrical:

| Live representation | GCS historical counterpart | Result |
| --- | --- | --- |
| Stock OHLCV/VWAP/trade count bar | Stock events | Reconstructable only after a declared aggregation rule; current bars are not raw event receipts |
| SPY option quote identity plus bid/ask/sizes | Option events | All seven captured contract fields exist, but events must be carried forward to reproduce a snapshot state |
| Extra surface `count`, cumulative `volume`, `open_interest` | Option events | No direct matching fields in the sampled raw option schema; no parity claim is possible until a verified historical endpoint is found |
| Live Basilisp BS grid | GCS vendor Greeks | Different data class and formula provenance; do not compare as raw payloads |
| Live SPX/TNX/VIX proxies | GCS index data | Different semantics; proxy values are not parity evidence for an index feed |

## Legacy Processing Lineage

`Data-Preprocessor-II` transforms existing raw parquet as follows:

1. Builds a full local-time grid, usually at 60 seconds.
2. Resamples raw rows using the first, max, min, and last `price` values and
   sums/counts size and quote-size fields.
3. Forward-fills price fields and zero-fills volume fields.
4. For options, retains only contracts whose daily `size` exceeds 1% of total
   daily option size.
5. Computes technical and option features, then writes feature parquet.

This is reproducible from GCS raw parquet, but it is a legacy transform with
material choices: right-labeled intervals, price forward filling, zero-filled
volume, and a daily-volume contract filter. It is not suitable as the source
contract for a new parity-first corpus without revalidation.

## Correct Evidence Order

GCS must not be used to define the new source contract. Its unknown ingestion
provenance makes it an artifact to audit, not an authority. The first gate is
ThetaData against itself:

1. Build a feature-agnostic catalog of every available ThetaData live,
   snapshot, at-time, and historical endpoint. Record actual terminal response
   schemas and entitlement failures, not just the documentation.
2. For every live/historical endpoint pair with compatible semantics, capture
   the raw live response and request receipt during market hours, then fetch
   the matching historical response at the same timestamp/watermark. Compare
   field set, contract universe, timestamps, and values before any transform.
3. Choose the canonical raw representation per class. A completed-minute stock
   query is only parity by construction after the same venue is shown to be
   retained across the full training horizon; current-day `nqb` access alone
   does not establish that. For option snapshots, use a last-NBBO at-time
   historical reconstruction.
4. Store both responses in an immutable raw landing area on `/mnt/d` with
   endpoint, parameters, observation watermark, terminal version, checksum,
   and schema fingerprint. This is required evidence collection, not a GCS
   migration.
5. Only after the ThetaData contract is proven, compare each GCS class to the
   corresponding ThetaData historical response. Admit a GCS partition only
   when it matches the contract; otherwise treat it as unusable and backfill
   that partition from ThetaData to `/mnt/d`.

This avoids both errors: trusting an archive of unknown lineage and
prematurely re-downloading a multi-gigabyte universe that may already be
correct.

## First-Open Diagnostic

`scripts/raw_thetadata_parity.lpy` now provides the fast answer requested for
the next open. It captures one unmodified live snapshot, queries ThetaData's
matching historical at-time endpoint using the saved ET watermark, stores both
responses and request receipts under `/mnt/d/stevetrading/thetadata-parity-v1`,
and reports `PASS`, `FAIL`, or `INCONCLUSIVE` immediately.

For example, use a bounded SPY expiration discovered by the market-open
capability probe:

```bash
.venv/bin/basilisp run scripts/raw_thetadata_parity.lpy -- \
  --class option-nbbo-quote --symbol SPY --expiration YYYY-MM-DD
```

The diagnostic compares the complete contract universe plus NBBO prices and
sizes, and separately captures the prior-session option-open-interest state.
It is intentionally strict: a failed or unavailable same-day
historical response is reported as evidence, never converted into a pass.
This provides a same-session answer but does not certify an event-native
corpus; stream ordering, reconnection behavior, and every intraminute update
still require the event-stream recorder.
