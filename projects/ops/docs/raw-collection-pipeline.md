# Raw Collection Pipeline v1

The collection contract is [`resources/market-data/collection-pipeline-v1.edn`](../../../resources/market-data/collection-pipeline-v1.edn). It creates one durable raw landing area on the Windows external corpus volume while keeping source identity and parity status explicit.

## Storage boundary

The intended root is `D:\SteveTradingData`. It contains four separate trees:

| Tree | Contents | Permitted consumers |
| --- | --- | --- |
| `raw/v1` | Original vendor payloads (`.dbn`, JSON, Parquet) and no feature transformations | Receipt verifier and reproducible replay only |
| `manifests/v1` | Collection, hash, cost-preflight, archive-finalization, and comparison receipts | Audit and corpus builders |
| `derived/v1` | Explicitly versioned features, bars, or replay outputs | Only the feature/model contract that names them |
| `quarantine/v1` | Failed or disputed source evidence | Review only |

Each raw run is partitioned by provider, dataset, admission state, class, trade date, and UTC run ID. A raw payload is immutable once its receipt has recorded its SHA-256.

Initialize only after the volume-health guard passes:

```powershell
pwsh -File projects/ops/scripts/initialize_raw_corpus_volume.ps1 -Initialize
```

The initializer refuses a wrong volume label or any non-healthy volume/disk state. It does not repair a filesystem.

## GLBX futures-options policy

`ES.OPT` and `NQ.OPT` MBP-1/trades are `qualified-hard` under the declared event-time-intersection representation. ES has replicated exact evidence; NQ was explicitly admitted on 2026-07-20 while its finalized MBP-1 and broader trade checks remain scheduled, so the root-level evidence must never be conflated.

`SR3.OPT` remains `probationary`: raw validation capture is permitted, but it is excluded from training, backtests, features, and live strategies until promoted. `RTY.OPT`, `ZN.OPT`, and `ZB.OPT` are rejected as unavailable under the tested parent symbology because both historical inventory and isolated live probes returned zero contracts/events.

Each historical request must pass `projects/ops/scripts/databento_cost_preflight.py` with the exact dataset, parent symbols, schemas, window, and explicit dollar ceiling before the request is submitted. The existing multi-schema comparator also enforces an aggregate size ceiling.

For event-native historical seed collection, use `scripts/databento_event_collection.lpy`. It independently quotes every requested schema before any data request, writes only below the canonical external `raw/v1` and `manifests/v1` trees, stores DBN payloads without bar aggregation, and preserves any failed partial download only under `quarantine/v1`.

The scheduled sequence captures bounded in-session ES/NQ/SR3 windows, preflights exact-contract historical requests, compares trades as soon as the intraday archive permits, and repeats MBP-1 against finalized metadata. Later evidence appends root-specific residuals; it may not silently transfer evidence between ES, NQ, and SR3.
