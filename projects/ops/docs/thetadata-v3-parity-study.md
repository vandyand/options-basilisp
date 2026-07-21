# ThetaData V3 Live/Historical Parity Study

Status: implementation ready; certification pending a fresh V2-provenance
market-session capture.

The broader source inventory, schema coverage, legacy transformation lineage,
and re-download decision are recorded in
[`raw-data-parity-catalog.md`](raw-data-parity-catalog.md).

## Question

Can a model be retrained from historical data that is demonstrably equivalent
to the inputs received during live inference? The answer is not yet proven.
The required evidence is a matched live capture and point-in-time historical
reconstruction, not a feature-vector correlation alone.

## Provider Semantics

| Input | Live contract | Historical reconstruction | Certification rule |
| --- | --- | --- | --- |
| `SPY,HYG,TLT,VXX` 1m bars | `GET /v3/stock/history/ohlc`, explicit venue, completed bars | Same endpoint and venue | Exact timestamp and OHLCV/VWAP/count values |
| SPY option chain | `GET /v3/option/snapshot/quote` per selected expiration, `strike_range=100` | `GET /v3/option/at_time/quote` at captured ET minute, same range | Exact contract universe and bid/ask tolerance |
| Greek grid | Basilisp Black-Scholes, fixed rate `0.043`, no dividend | Same Basilisp implementation and policy | Exact raw chain first, then grid/tensor checks |

ThetaData defines an OHLC bar timestamp as the **opening** time and includes
trades in `[bar_time, bar_time + interval)`. The live source records this as
`bar_timestamp=open-time`; consumers must only use a fully completed minute.
The docs describe `nqb` as the current-day real-time Nasdaq Basic venue and
distinguish it from `utp_cta`; a venue switch is therefore a source change,
not a harmless fallback. [OHLC endpoint](https://docs.thetadata.us/operations/stock_history_ohlc.html)
and [OHLC methodology](https://docs.thetadata.us/Articles/Data-And-Requests/OHLC-EOD.html)

Live option snapshots are last NBBO values. Historical interval quote history
returns quote updates and cannot by itself prove that it selected the same
point-in-time observation. The `at_time` quote endpoint is designed to return
the last OPRA NBBO at a specified ET time, so it is required for certification.
[Snapshot quote](https://docs.thetadata.us/operations/option_snapshot_quote.html),
[historical quote](https://docs.thetadata.us/operations/option_history_quote.html),
and [at-time quote](https://docs.thetadata.us/operations/option_at_time_quote.html)

### Terminal Probe (2026-07-11)

The deployed terminal was started briefly after hours and then stopped. Its
actual request contract differs from the documented aliases: it requires
`start_date`, `end_date`, and `time_of_day=HH:MM:SS.SSS`. A bounded request for
`SPY 2026-07-10 751 CALL` at `2026-07-09 15:30:00 ET` returned an OPRA quote
timestamped `15:29:59.933`, bid `1.95`, ask `1.97`. Broad `strike=*` timed out;
`strike_range=10` returned 40 contracts and `strike_range=100` returned 354
contracts for that expiration. The cohort therefore uses bounded strike-range
requests and must not substitute a broad all-chain call.

A second after-hours probe fetched July 9 SPY one-minute bars with both
`venue=nqb` and `venue=utp_cta`. Both returned the same two sampled bars,
including `2026-07-09T15:30:00` close `750.960` and count `2011`. This proves
the terminal can retrieve the selected historical `nqb` window after close;
the corpus gate still requires the live and historical venue declarations to
match.

### GCS Archive Comparison (2026-07-11)

The service-account credential already grants read access to
`gs://thetadata-raw-bucket` and `gs://thetadata-feature-bucket`. The raw bucket
contains intraminute/event data families for `stock`, `index`, `option`, and
`option_greeks`; the sampled SPY files cover 2017-01-03 through 2026-05-29.
The feature bucket is derived data and is not raw-parity evidence.

There is one date that overlaps the retained legacy live strategy logs:
2026-05-29. This is useful only as a diagnostic because those logs preserve a
decision-level `spy_price` and option-contract count, not the raw provider
payload. The old runner code shows that `spy_price` came from an Alpaca IEX
one-minute bar, while option data came from a ThetaData snapshot. It was not a
single-source ThetaData live feed.

For the 380 CHESTNUT decision records on that date, 379 can be aligned to the
final event in the preceding GCS SPY minute, which is the bar the old loop was
using at the next minute boundary. The absolute price difference was at most
`$0.3512`, mean `$0.030034`; 318/379 were within `$0.05`, and 45 were exact.
At the raw event level, 366/380 decision prices fell inside the corresponding
GCS minute's price range. This is compatible with two feeds observing the same
market, but it is not exact source parity.

The option result is more decisive: the old live snapshot retained about 493
valid SPY contracts per decision, while raw GCS events had about 190 distinct
contracts updated in the immediately preceding minute. No minute had matching
cardinality. That is expected for a full snapshot versus an event stream, but
it proves that event rows must be reconstructed with a documented carry-forward
and selection rule before they can be compared to a snapshot. The GCS objects
also have no object metadata identifying the original endpoint, venue, request
parameters, or snapshot watermark.

Conclusion: the GCS archive is a valuable candidate historical source with
intraminute resolution, but the legacy logs cannot certify it. Future captures
must save direct terminal response receipts, request parameters, observation
watermarks, and normalized raw events. The parity audit must compare those
receipts with an explicitly reconstructed GCS state at the same watermark.

## Current Evidence

- Older captures are replayable but non-certifiable: they lack the full V2
  source contract and cannot prove endpoint, venue, or option selection.
- A July 9 bounded diagnostic found median live option-chain density of about
  `768` contracts/minute versus `80` in the old history reconstruction. This
  demonstrates a request-universe mismatch; it is not evidence that ThetaData
  lacks the contracts.
- A direct Alpaca IEX audit of two July 9 capture sidecars found exact sampled
  OHLC and volume agreement. Its earlier maximum raw deviation of `97` is an
  intermittent live `trade_count=0` versus historical `97`, with small VWAP
  fallback differences (maximum `0.011202`). This is a legacy
  capture-field-preservation defect, not broad price-bar divergence.
- Captured live tensors replay through the native path within the established
  tolerance. This verifies capture/replay reproducibility only, not
  live-versus-historical provider parity.

## Enforced Contract

`steve-v2-canonical-input/v2` records every captured row with:

- stock provider family, endpoint, venue, timeframe, completed-bar status,
  opening-time label semantics, and symbols;
- option provider family, endpoint, last-NBBO selection method, observation
  timestamp rule, strike range, and symbols;
- raw-sidecar retention, native feature implementation, and Greek policy.

`audit_captured_source_parity.lpy` rejects artifacts unless these fields are
stable within each artifact and compatible across the live/historical pair.
It specifically requires a live `snapshot/quote` input and historical
`at_time/quote` reconstruction. The verified-corpus builder additionally
requires native Basilisp tensors.

## Fresh Session Procedure

1. Deploy the source-contract release with
   `STEVE_STOCK_BAR_SOURCE=thetadata`, `THETADATA_STOCK_VENUE=nqb`, and
   `STEVE_CAPTURE_SIDECAR_EVERY=1`.
2. During market hours, capture at least 60 model-input rows without changing
   source settings or Greek policy.
3. Run `collect_market_evidence.sh`. It reconstructs the bounded cohort with
   `--stock-venue` from the live environment, `--option-reconstruction
   at-time-quote`, and native Basilisp feature logic.
4. Run `audit_captured_source_parity.lpy` with zero tolerance first. Inspect
   the per-field report before considering a declared nonzero tolerance.
5. Only when the source audit is certifiable may
   `build_verified_feature_corpus.lpy` admit the cohort. Unmasking remains a
   separate feature-family promotion decision.

## Acceptance Criteria

- At least 60 matching UTC observation rows.
- No missing final stock bars, exact completed-bar timestamp agreement, and
  field-level deviations within the declared tolerance.
- At least 99.5% exact contract-universe coverage in each direction with
  bid/ask deviations within declared tolerance.
- V2 provenance compatibility and native feature implementation.
- A saved source-audit JSON, historical-cohort JSON/NPZ, and corpus manifest
  whose hashes identify the artifacts used.

No currently neutralized feature is eligible for unmasking from this study
until all criteria are met for the required sessions.
