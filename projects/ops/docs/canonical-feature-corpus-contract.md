# Canonical Feature Corpus Contract

Version: `steve-v2-canonical-input/v2`

This contract defines the only admissible input lineage for retraining the
Steve direction architectures. It replaces the legacy GCS feature-matrix
assumption. A model architecture may be reused; a legacy feature value may not
enter this corpus without this evidence.

## Canonical Inputs

Each inference row is an immutable tuple of:

- Four completed one-minute stock bars: `SPY`, `HYG`, `TLT`, and `VXX`, with
  provider endpoint, venue, and opening-time bar-label semantics.
- The exact option quote snapshot contract universe used to build the grid,
  including endpoint, selection rule, strike range, and observation time.
- A UTC observation timestamp, provider identity, endpoint semantics, and
  raw-sidecar retention declaration.
- The rolling bar and grid histories used by the feature function.

Live capture writes `provenance_json` on every row. Historical reconstruction
writes the same field. Required provenance values are a non-empty stock
provider, option provider, feature contract, stock venue and endpoint, option
endpoint and selection rule, Greek policy, and `stock.bar_status=completed`.
Missing provenance makes an artifact replayable only; it cannot certify a
training corpus.

## Admission Gate

For every source session, `audit_captured_source_parity.lpy` must pass before
the historical tensor is admitted:

1. At least the configured number of matched UTC rows exists.
2. Every final stock-buffer timestamp matches and all canonical OHLCV, VWAP,
   and trade-count values meet the declared tolerance.
3. The option universe is exact after contract selection and bid/ask values
   meet the declared tolerance.
4. Both artifacts carry valid, stable, compatible provenance. A different
   stock venue, Greek policy, or interval quote history in place of a live
   snapshot fails the gate even when values happen to be close.

Historical option reconstruction must use ThetaData
`/v3/option/at_time/quote` at the captured observation minute. The
`history/quote` last-quote-per-minute path is diagnostic only.

The corpus builder additionally requires historical provenance
`capture.feature_implementation=native`. This forces historical and live
feature vectors through `stevetrading.feature-parity.raw-unlock`, the shared
Basilisp implementation. `legacy-python` artifacts remain diagnostics only.

## Feature Family Status

| Family | Count | Status | Rule |
| --- | ---: | --- | --- |
| Stock base and TA | 215 or fewer active fields | pending source audit | Admit only after completed-bar parity. |
| SPY option aggregates and grid features | source-dependent | pending exact contract audit | No partial-chain substitutes. |
| V2 grid features | 11 | pending grid-input audit | Require exact grid history. |
| TDA and dictionary features | subset of V3 | pending native replay audit | Require artifact-backed native calculation. |
| Wasserstein | 72 | legacy mismatch | Retrain only with the native live formula; never compare to legacy training values. |
| Scattering | 84 | legacy mismatch | Retrain only with the native live formula; never compare to legacy training values. |
| Remaining neutralized fields | 703 currently | excluded until independently certified | Neutralization is not evidence of parity. |

The feature count for a new model is deliberately not fixed at 918. The corpus
manifest is the authoritative feature set. A smaller certified set is valid; a
larger set requires separate admission evidence.
