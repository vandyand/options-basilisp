# Historical Acquisition Feasibility

**Status:** active acquisition gate, updated 2026-07-20

## Decision target

The complete selected corpus must support two years of historical retrieval in
at most 24 wall-clock hours. A representative month therefore has a shared
3,600-second budget across every selected provider and data class. With 22
sessions in the June 2026 reference month, this is approximately 171 seconds
per session.

The eventual trading target is SPY options across directional, volatility,
calendar, and skew strategy families. That target governs later signal-density
evaluation. The present gate evaluates acquisition feasibility only.

## Current metadata and receipt evidence

Databento's metadata endpoints were queried for June 2026. These calls returned
byte and cost estimates only; no market-data payload was downloaded.

| Candidate | Billable size | Estimated compressed wire size | Current serial projection |
| --- | ---: | ---: | ---: |
| GLBX six futures parents, MBP-1 + trades | 169.6 GiB | 56.1 GiB | 5.7 hours/month |
| GLBX ES futures options, MBP-1 + trades | 255.2 GiB | 85.8 GiB | 12.7 hours/month |
| EQUS Mini 15-symbol universe, MBP-1 + trades | 40.4 GiB | 9.2 GiB | 1.8 hours/month |
| **Databento total** | **465.2 GiB** | **151.1 GiB** | **20.2 hours/month** |

Compressed-size and time projections use the median compression ratio and
observed end-to-end throughput from the completed fixed-window receipts. They
are screening estimates, not admission evidence.

ThetaData index ticks remain plausible: four observed one-hour requests took a
median 6.64 seconds. Linear cash-session projection is about 15.8 minutes for a
22-session month. VIXN was unavailable for the measured date and is not counted
as silently delivered.

ThetaData full-chain option quote/trade ticks fail. The corrected receipt-based
runtime for the completed 15-minute, five-root request is 87.86 minutes—not the
previously reported 5.5 hours. The earlier number double-applied the UTC/local
offset in PowerShell. The corrected result remains far outside the gate. This
rejection applies to the combined full-chain quote/trade request, not to the
separately measured SPY trade-only request contract below.

ThetaData SPY option trades now have a promising vendor-side delivery contract:
full-root event trades in CSV, requested by trading date with bounded
concurrency. A one-minute CSV/JSON/NDJSON probe returned the same 8,844 events
and 14 fields with zero row/field mismatches. CSV used 872,277 bytes versus
2,393,305 bytes for NDJSON, a 63.55% wire reduction. The terminal ignored
`Accept-Encoding: gzip`; CSV itself is therefore the current compact wire form.

Four identical 15-minute CSV windows took 60.88 seconds sequentially and 41.01
seconds at four-way concurrency: a 1.48x speedup, not 4x. Two full-session CSV
requests then delivered July 6 and July 7 concurrently in 163.83 seconds total,
or 81.92 effective seconds per session. Their payloads were 140,864,943 and
163,137,985 bytes. This passes the per-session screening target, but a complete
representative-month run is still required before the request contract is
admitted for a two-year bulk pull. Based on the five-session evidence and the
measured CSV/NDJSON ratio, two years of SPY option trades screen at roughly 71
GiB and 11–18 wall-clock hours, depending on sustained concurrency throughput.

## Immediate decision

- Do not repeat the failed ThetaData five-root full-chain quote/trade request.
- Use CSV, never NDJSON, for new ThetaData SPY option-trade acquisition. Treat
  four concurrent requests as a measured 1.48x optimization rather than 4x.
- Run a complete representative-month SPY trade-only CSV test before any
  two-year bulk request.
- Retain ThetaData index ticks as a plausible acquisition class.
- Do not use the current serial Databento downloader for bulk history.
- Test whether Databento batch DBN/Zstd with bounded parallel downloading can
  sustain approximately 58 MiB/s after reserving the measured index budget.
- Keep ThetaData SPY trade-quote and interval-quote forms unestimated until a
  strict byte/time-capped pilot is specified. Neither is admitted by existence
  alone.

The current Databento estimate is about 3.54 TiB for 24 months before indexes,
which fits inside the 4.5-TB allocation but leaves limited headroom. Retrieval
speed, not nominal storage, is the immediate failing gate.

## Steve's one-year, 20-symbol Databento run

Steve reported the following end-to-end measurements on 2026-07-20. His job
includes Databento queue/processing, download, local handling, and upload to
GCP; the OHLCV-1m span is explicitly inflated by troubleshooting.

| Schema | Files completed | Data | Batches | Average Databento response/batch | E2E span | Effective rate including Databento |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| OHLCV-1m | 5,000 | 0.09 GB | 17 | 15.7 min | 23.8 h | 8.4 Kbps |
| OHLCV-1s | 5,000 | 0.57 GB | 7 | 8.8 min | 2.06 h | 620 Kbps |
| Trades | 5,000 | 1.80 GB | 10 | 3.8 min | 2.21 h | 1.81 Mbps |
| TBBO | 5,000 | 2.22 GB | 12 | 2.9 min | 1.83 h | 2.70 Mbps |
| MBP-1 | 3,488 of 5,000 | 88.09 GB | 23 | 6.5 min | 14.0 h | 13.98 Mbps |

At the observed MBP-1 average, completing 5,000 files projects to roughly
126 GB and 20 hours. Two years would therefore exceed the full 24-hour corpus
budget before adding any other class. The rates also show that a nominal
250-Mbps internet connection is not the binding constraint: request setup,
Databento queue/processing, small-file overhead, retries, and GCP upload govern
the end-to-end rate.

Databento's official schema contract makes the current all-schema pull
redundant for a lossless event-native seed: MBP-1 contains every BBO-changing
book event and every trade; TBBO and Trades can be derived from MBP-1, and
OHLCV can be derived from Trades. Retain small vendor-schema validation samples,
but do not bulk-download TBBO, Trades, OHLCV-1s, and OHLCV-1m for the same
symbol/time range when MBP-1 is already retained.

The next acquisition pilot must use Databento batch delivery for requests over
5 GB, DBN encoding with Zstd compression, multi-symbol requests, and bounded
large-file splitting (week/month or 2–10 GB) rather than one remote request per
symbol-day. Parallelism should download already-prepared batch files; it should
not create thousands of independent Databento jobs.

## Databento batch-delivery result, 2026-07-20

The first prepared-batch pilot passed for the 15-symbol `EQUS.MINI` universe,
`mbp-1`, over 2026-06-08 through 2026-06-12. The request was delivered as DBN
with Zstd and 2-GB file splitting. It cost $0 under the current entitlement.

| Measurement | Result |
| --- | ---: |
| Records | 170,758,658 |
| Uncompressed/billable bytes | 13,660,692,640 |
| Prepared Zstd package | 3,042,906,425 bytes |
| Wire/raw ratio | 22.27% |
| Server queue plus preparation | 210 seconds |
| Resumed download plus local SHA-256 verification | 359 seconds |
| Verified local files | 10 files, zero size/hash failures |

The safety gate initially stopped because Databento's `actual_size` field is
the uncompressed DBN size, not the transfer size. The collector now gates the
download against `package_size` (and remote file sizes as a fallback), while
retaining `actual_size`/`billed_size` as the billing-volume measurement. The
already-prepared job was resumed rather than submitted twice.

This result overturns the prior assumption that the current Databento path is
necessarily too slow for every selected class. For this EQUS Mini universe,
the measured batch path is plausibly inside the 24-hour/two-year target. It
does not prove that the combined GLBX futures and futures-option corpus fits;
those materially larger classes require their own batch measurements. A
one-day, six-root GLBX futures MBP-1 pilot is the next bounded gate.

That GLBX gate subsequently passed for 2026-06-10. The six parent roots
(`ES.FUT`, `NQ.FUT`, `RTY.FUT`, `ZN.FUT`, `ZB.FUT`, and `SR3.FUT`) produced
135,643,787 MBP-1 records, 10,851,502,960 uncompressed/billable bytes, and a
3,221,447,572-byte Zstd package. The complete submit, queue, preparation,
download, extraction, and local hashing path took 551 seconds, cost $0, and
ended with nine verified files and zero size/hash failures. This validates the
batch mechanism for a bounded GLBX day; it does not yet admit a two-year
six-root backfill because the measured one-day volume still projects to a
large multi-terabyte corpus.

## Pilot rules

Every pilot must declare its exact symbols, schema, time range, maximum bytes,
maximum wall time, cost ceiling, and output receipt before execution. It must
stop rather than broaden its universe or time range. Passing a small pilot only
permits a representative-month test; it does not authorize a two-year pull.
