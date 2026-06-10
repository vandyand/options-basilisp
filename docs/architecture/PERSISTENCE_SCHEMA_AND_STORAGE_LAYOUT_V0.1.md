# Persistence Schema And Storage Layout v0.1

## 1. Purpose

This document formalizes the persistence partitioning strategy for the Basilisp rewrite of StevenTrading.

It locks:

- durable storage classes
- canonical truth boundaries
- logical schemas for each storage class
- partitioning and retention rules
- write and recovery responsibilities

This spec is normative for v0.1.

## 2. Design Intent

Persistence must support:

1. deterministic replay
2. restart-safe recovery
3. exact order and fill lineage
4. cheap operational inspection
5. incremental scale without architectural rework

The persistence model is not allowed to smuggle hidden truth into mutable tables or opaque caches.

## 3. Storage Classes

The system has six logical storage classes.

1. canonical fact storage
2. snapshot storage
3. control-plane storage
4. projection and reporting storage
5. artifact reference storage
6. replay fixture storage

## 3.1 Canonical Fact Storage

This is the system of record for runtime truth.

It stores:

- normalized market facts
- strategy decision facts
- order-intent facts
- broker acknowledgement and status facts
- fill facts
- ledger facts
- recovery facts
- health and fault facts

Properties:

- append-only
- immutable records
- per-record schema version
- queryable by lineage keys

## 3.2 Snapshot Storage

This stores restart accelerators only.

It stores:

- latest accepted snapshot per runtime stream
- optional historical snapshots for audit and debugging

Properties:

- replaceable
- versioned
- not canonical truth

## 3.3 Control-Plane Storage

This stores declared operational policy.

It stores:

- strategy assignment manifests
- routing and account policy
- rollout and retirement flags
- kill-switch declarations
- revision history

Properties:

- versioned
- validated before activation
- readable independently of runtime state

## 3.4 Projection And Reporting Storage

This stores derived views optimized for inspection and reporting.

It stores:

- open-orders view
- positions view
- portfolio exposure view
- realized and unrealized P&L views
- operational dashboards
- daily reports

Properties:

- rebuildable
- disposable
- never the source of recovery truth

## 3.5 Artifact Reference Storage

This stores references to offline artifacts needed by runtime logic.

It stores:

- model artifact references
- feature-manifest references
- strategy package references

The artifacts themselves may live elsewhere.

The runtime only requires durable references and versions here.

## 3.6 Replay Fixture Storage

This stores replay-ready normalized historical inputs and expected outputs.

It stores:

- normalized historical market facts
- broker simulation traces where applicable
- expected decisions for golden runs

Properties:

- immutable per fixture version
- suitable for deterministic tests and audits

## 4. Canonical Truth Boundary

The following are canonical truth:

- canonical facts
- active control-plane revision

The following are not canonical truth:

- snapshots
- projections
- reports
- temporary caches
- adapter-local raw payload buffers

## 5. Logical Schemas

This section defines the logical store shapes, not a concrete database product.

## 5.1 Canonical Fact Store

Recommended logical record:

```clojure
{:fact-log/stream "runtime-main"
 :fact-log/offset 183225
 :fact-log/partition-date "2026-06-10"
 :fact-log/partition-mode :mode/paper
 :fact-log/partition-account-id "account/alpaca/paper-ops"
 :fact-log/record {...canonical fact envelope...}}
```

Required indexing dimensions:

- `fact-id`
- `fact-type`
- `correlation-id`
- `strategy-id`
- `account-id`
- `instrument-id`
- `order-intent-id`
- `broker-order-id`
- `occurred-at`
- `recorded-at`
- stream offset

Rules:

- stream offset is monotonic within one fact stream
- the record envelope remains the canonical application-level schema
- storage metadata must not replace envelope fields

## 5.2 Snapshot Store

Recommended logical record:

```clojure
{:snapshot/key {:runtime-stream "runtime-main"
                :mode :mode/paper
                :account-scope "account/alpaca/paper-ops"}
 :snapshot/record {...snapshot envelope...}}
```

Required query dimensions:

- runtime stream
- mode
- account scope or deployment scope
- written-at
- snapshot version

## 5.3 Control-Plane Store

Recommended logical record:

```clojure
{:control-plane/revision "cp-000014"
 :control-plane/activated-at "2026-06-10T13:55:00Z"
 :control-plane/status :control-plane-status/active
 :control-plane/document {...validated manifest...}}
```

Required query dimensions:

- revision id
- activation time
- status
- strategy id
- account id

## 5.4 Projection Store

Recommended logical record:

```clojure
{:projection/name :projection/open-orders
 :projection/as-of "2026-06-10T14:35:00Z"
 :projection/scope {:mode :mode/paper
                    :account-id "account/alpaca/paper-ops"}
 :projection/source-watermarks {...}
 :projection/payload {...}}
```

Required rule:

- every projection record must identify the source watermarks or source fact range from which it was built

## 6. Partitioning Strategy

Partitioning must support both recovery and operational queries.

## 6.1 Fact Store Partitioning

Primary logical partitions:

1. date
2. mode
3. account scope

Secondary query keys:

- strategy id
- instrument id
- correlation id
- order-intent id

Rationale:

- date bounds operational scans
- mode separates live, paper, sim, and replay domains
- account scope separates materially distinct execution truth

## 6.2 Snapshot Partitioning

Snapshots are partitioned by:

1. runtime stream
2. mode
3. account scope or deployment scope

Only one latest accepted snapshot per partition needs to be hot.

Historical snapshots may be retained on a policy basis.

## 6.3 Projection Partitioning

Projections are partitioned by:

1. projection name
2. date or as-of bucket
3. scope

They should be easy to expire and rebuild.

## 7. Write Responsibilities

## 7.1 Engine Writes

The engine owns writes to:

- canonical fact storage
- snapshot storage
- projection refresh triggers

The engine must not write directly to:

- ad hoc mutable portfolio tables as primary truth
- adapter-private persistence formats as canonical records

## 7.2 Adapter Writes

Adapters may write:

- raw temporary buffers
- transport logs
- diagnostic traces

Adapters must not write canonical truth directly unless they do so through the canonical envelope and engine-approved append path.

## 7.3 Control-Plane Writes

Control-plane tools write only validated manifests and activation records.

Runtime processes consume them read-only.

## 8. Recovery Read Order

The canonical recovery read order is:

1. read latest active control-plane revision
2. read latest accepted snapshot for the runtime partition
3. read canonical facts after snapshot watermark
4. read broker-side truth only if the mode requires reconciliation
5. optionally rebuild projections

Projections are never read as recovery truth.

## 9. Storage Invariants

1. No canonical fact is ever updated in place.
2. A snapshot is valid only with explicit per-stream watermarks.
3. Control-plane revisions are immutable once activated.
4. Every projection is traceable to source watermarks.
5. Canonical facts are sufficient to rebuild unresolved order lineage.

## 10. Retention Rules

## 10.1 Canonical Facts

Canonical facts should be retained long enough to support:

- audit
- replay
- incident investigation
- tax and performance reporting

v0.1 default posture:

- do not delete canonical facts as part of ordinary operations

If archival tiers are introduced later, retrieval semantics must remain stable.

## 10.2 Snapshots

Snapshots may use bounded retention.

Recommended posture:

- keep latest accepted snapshot always
- keep recent snapshot history for incident analysis
- expire old snapshots without affecting correctness

## 10.3 Projections

Projections may be expired aggressively.

They are rebuildable.

## 11. What Must Never Be Persisted As Canonical Truth

The following must not become canonical storage records:

- raw SDK objects
- live connection handles
- mutable in-memory portfolio caches
- hidden closure state
- transport-specific retry bookkeeping
- reports without their source lineage

## 12. Operational Query Model

The persistence layout must make these queries straightforward:

1. show all facts for one `order-intent-id`
2. show all fills for one broker order
3. reconstruct one strategy's decisions over one session
4. list unresolved orders at one recovery point
5. prove which control-plane revision was active for one run

If the chosen storage technology cannot support these economically, it is a bad fit.

## 13. Future Technology Mapping

This spec intentionally avoids committing to one product.

Acceptable future implementations may include:

- relational storage for fact and projection indexes
- object or blob storage for snapshot payloads
- append-oriented log implementations

The product choice must preserve the logical model above.

## 14. Acceptance Criteria

This persistence spec is sufficient for v0.1 if:

1. recovery can be performed from control-plane revision plus snapshot plus post-watermark facts
2. order and fill lineage queries are first-class
3. projections can be dropped and rebuilt without loss of truth
4. canonical fact storage remains append-only
5. the system can explain a trading day without depending on mutable caches
