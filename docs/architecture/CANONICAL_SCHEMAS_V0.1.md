# Canonical Schemas v0.1

## 1. Purpose

This document defines the first formal schema layer for the Basilisp rewrite of StevenTrading.

It locks:

- canonical identifier classes
- durable scalar conventions
- fact, command, and snapshot envelope shapes
- minimal payload requirements for load-bearing records
- deterministic order-intent identity rules

This spec is normative for v0.1.

## 2. Scope

This document does not yet choose:

- a storage engine
- a wire format such as JSON, Transit, or EDN
- a full field list for every future fact type

It does define the canonical in-memory and durable logical shapes that all storage and transport choices must preserve.

## 3. Schema Design Rules

1. Canonical records are plain data maps.
2. Required keys must remain stable across adapters.
3. Persistence format must preserve exact values for ids, timestamps, decimals, and enums.
4. Random process-local identifiers are forbidden for business lineage.
5. Schema evolution happens by explicit versioning, not silent field mutation.

## 4. Durable Scalar Conventions

### 4.1 Time

- canonical in-memory type: instant
- canonical durable form: UTC RFC 3339 timestamp with offset `Z`
- examples: `2026-06-10T14:30:00Z`, `2026-06-10T14:30:00.125Z`

All persisted timestamps must be UTC.

### 4.2 Decimal Values

- canonical in-memory type: arbitrary-precision decimal
- canonical durable form: decimal string
- examples: `"1"`, `"1.25"`, `"552.375"`

Binary floating-point values must not be canonical.

### 4.3 Integer Values

- canonical in-memory type: integer
- canonical durable form: integer

Use integers for counts, sequence numbers, and discrete quantities when fractional precision is impossible by domain.

### 4.4 Enumerations

- canonical in-memory form: namespaced keywords
- canonical durable form: keyword string or equivalent exact token
- examples: `:mode/paper`, `:order-side/buy`, `:health/degraded`

### 4.5 Booleans

Use booleans only for true binary properties.

State must not be encoded as multiple loosely related booleans when an enum is clearer.

## 5. Identifier Specification

The system uses two identifier families:

1. opaque record ids
2. stable business ids

## 5.1 Opaque Record Ids

These ids are uniqueness-oriented and sortable.

Recommended format:

- ULID string

Applies to:

- `fact-id`
- `command-id`
- `run-id`
- `snapshot-id`

Example:

- `01JX8H0V7QMP2T8A3N8D0SY5Z4`

## 5.2 Stable Business Ids

These ids are meaning-oriented and deterministic.

They must survive restart, replay, and storage migration.

### 5.2.1 Strategy Id

Format:

- `strategy/<family>/<name>/v<major>`

Example:

- `strategy/spx-credit/spread-entry/v1`

Rules:

- `family` groups related strategies
- `name` identifies the specific deployed behavior
- `major` changes when replay compatibility is intentionally broken

### 5.2.2 Account Id

Format:

- `account/<broker>/<logical-name>`

Examples:

- `account/alpaca/live-primary`
- `account/alpaca/paper-ops`
- `account/sim/main`

The account id is internal and stable even if the broker rotates an external account number.

### 5.2.3 Instrument Id

`instrument-id` is a deterministic canonical string derived from a structured instrument reference.

Formats:

- equity: `equity/<venue>/<symbol>`
- option: `option/<venue>/<underlying>/<expiry>/<right>/<strike>`
- future: `future/<venue>/<root>/<expiry>`

Examples:

- `equity/NYSE/IBM`
- `equity/NASDAQ/SPY`
- `option/OPRA/SPY/2026-06-19/C/550.000`

If a venue is unknown at normalization time, use a documented placeholder such as `XUNK` and normalize later only through explicit corrective facts.

### 5.2.4 Broker Order Id

`broker-order-id` is the external broker's native identifier.

It is not globally unique without broker context.

Therefore canonical correlation requires:

- `account-id`
- `source-system`
- `broker-order-id`

### 5.2.5 Fill Id

If the broker supplies a stable fill/execution id, use it.

If not, derive a surrogate from a documented composite key:

- broker context
- broker order id
- execution timestamp
- execution quantity
- execution price

Undocumented surrogate construction is forbidden.

### 5.2.6 Decision Id

`decision-id` is a deterministic identifier for one strategy decision point.

Format:

- hash over canonical decision seed

Decision seed must include:

- `strategy-id`
- `decision-scope`
- source fact ids or source watermark tuple
- decision timestamp
- deterministic decision slot where more than one decision may arise from the same source event set

`decision-id` is not required to be human-readable.

### 5.2.7 Order Intent Id

`order-intent-id` is deterministic and replay-stable.

It must not be random.

It is derived from:

- `decision-id`
- `intent-slot`
- `account-id`
- canonical order shape
- schema version for the order-intent identity algorithm

The canonical order shape must include:

- side
- opening or closing effect
- instrument or leg set
- target quantity
- order type
- time in force
- limit or stop parameters when applicable

Two replays of the same logical decision must produce the same `order-intent-id`.

## 6. Structured References

Some values need both a stable id and a structured form for business logic.

## 6.1 Instrument Reference

Canonical shape:

```clojure
{:instrument/id "option/OPRA/SPY/2026-06-19/C/550.000"
 :instrument/asset-class :asset-class/option
 :instrument/venue "OPRA"
 :instrument/underlying "SPY"
 :instrument/expiry "2026-06-19"
 :instrument/right :option-right/call
 :instrument/strike "550.000"}
```

The id is used for joins, storage, and lineage.

The structured form is used for decision logic and validation.

## 6.2 Broker Reference

Canonical shape:

```clojure
{:broker/source-system :broker/alpaca-paper
 :broker/account-id "account/alpaca/paper-ops"
 :broker/order-id "8b8f3b7d-1234-5678-90ab-fedcba123456"}
```

## 7. Common Record Metadata

Facts and commands share a common metadata vocabulary.

Canonical common keys:

```clojure
{:record/id "01JX8H0V7QMP2T8A3N8D0SY5Z4"
 :record/type :fact/order-intent-created
 :record/version 1
 :record/run-id "01JX8GZY6S3N8W3PK0T4V8M6C2"
 :record/mode :mode/paper
 :record/correlation-id "01JX8H0CKVJ9P4CZAFSRJ5VY5H"
 :record/causation-ids ["01JX8H07B9M0AZ6KN4V1M4VE0P"]
 :record/strategy-id "strategy/spx-credit/spread-entry/v1"
 :record/account-id "account/alpaca/paper-ops"
 :record/instrument-id "option/OPRA/SPY/2026-06-19/C/550.000"
 :record/source-system :engine/core}
```

Rules:

- `:record/id` is unique per durable record
- `:record/type` is a namespaced keyword
- `:record/version` versions the schema for that record type
- `:record/correlation-id` ties one business thread together
- `:record/causation-ids` identifies the immediate prior records that caused this one

## 8. Fact Envelope

Canonical logical shape:

```clojure
{:record/id ...
 :record/type :fact/fill-observed
 :record/version 1
 :record/run-id ...
 :record/mode :mode/paper
 :record/correlation-id ...
 :record/causation-ids [...]
 :record/strategy-id ...
 :record/account-id ...
 :record/instrument-id ...
 :record/source-system :broker/alpaca-paper
 :fact/occurred-at "2026-06-10T14:31:02.125Z"
 :fact/recorded-at "2026-06-10T14:31:02.182Z"
 :fact/source-ref "alpaca:trade-update:abc123"
 :fact/dedupe-key "fill/alpaca-paper/8b8f3b7d/trade-42"
 :fact/payload {...}}
```

Required fact keys:

- all common record keys
- `:fact/occurred-at`
- `:fact/recorded-at`
- `:fact/payload`

Recommended fact keys:

- `:fact/source-ref`
- `:fact/dedupe-key`

## 9. Command Envelope

Canonical logical shape:

```clojure
{:record/id ...
 :record/type :command/submit-order-intent
 :record/version 1
 :record/run-id ...
 :record/mode :mode/paper
 :record/correlation-id ...
 :record/causation-ids [...]
 :record/strategy-id ...
 :record/account-id ...
 :record/instrument-id ...
 :record/source-system :engine/core
 :command/issued-at "2026-06-10T14:31:02.126Z"
 :command/target-adapter :adapter/broker
 :command/idempotency-key "submit/intent/7f7ef..."
 :command/payload {...}}
```

Required command keys:

- all common record keys except fields that are not applicable
- `:command/issued-at`
- `:command/target-adapter`
- `:command/idempotency-key`
- `:command/payload`

`command-id` uniqueness is not enough.

The idempotency key is the adapter-facing proof that retries refer to the same logical effect.

## 10. Snapshot Envelope

Canonical logical shape:

```clojure
{:snapshot/id "01JX8H5K7QAX9Q91AM6N0R1YQ5"
 :snapshot/version 1
 :snapshot/engine-version "0.1.0"
 :snapshot/written-at "2026-06-10T14:35:00Z"
 :snapshot/control-plane-revision "cp-000014"
 :snapshot/run-independent? true
 :snapshot/fact-watermark {:stream "fact-log" :offset 183225}
 :snapshot/market-watermarks [{:stream "bars" :cursor "2026-06-10T14:34:59Z"}]
 :snapshot/broker-watermarks [{:stream "alpaca-paper-fills" :cursor "2026-06-10T14:34:58.821Z"}]
 :snapshot/state {...}}
```

Rules:

- snapshot contents must be serializable without live objects
- watermarks must be explicit per stream family
- the snapshot's state payload must be sufficient to restart efficiently but not required for correctness

## 11. Minimal Payload Requirements For Load-Bearing Facts

This section defines the smallest acceptable durable payloads for the most critical record types.

## 11.1 `:fact/market-bar-observed`

```clojure
{:bar/time "2026-06-10T14:30:00Z"
 :bar/timeframe :timeframe/1m
 :bar/open "550.10"
 :bar/high "550.22"
 :bar/low "549.98"
 :bar/close "550.05"
 :bar/volume "18234"
 :bar/provider :market-data/polygon}
```

## 11.2 `:fact/signal-decision-produced`

```clojure
{:decision/id "dec_..."
 :decision/posture :posture/enter-long
 :decision/reason-codes [:reason/model-positive :reason/risk-allowed]
 :decision/market-time "2026-06-10T14:30:00Z"}
```

## 11.3 `:fact/order-intent-created`

```clojure
{:order-intent/id "oi_..."
 :order-intent/decision-id "dec_..."
 :order-intent/intent-slot 0
 :order-intent/role :intent-role/entry
 :order-intent/side :order-side/buy
 :order-intent/effect :position-effect/open
 :order-intent/order-type :order-type/limit
 :order-intent/time-in-force :tif/day
 :order-intent/quantity "1"
 :order-intent/limit-price "2.15"
 :order-intent/legs [{:instrument/id "option/OPRA/SPY/2026-06-19/C/550.000"
                      :leg/side :order-side/buy
                      :leg/quantity "1"}]}
```

At least one leg is required.

A single-leg equity order still uses the `:order-intent/legs` collection.

## 11.4 `:fact/broker-ack-accepted`

```clojure
{:order-intent/id "oi_..."
 :broker/source-system :broker/alpaca-paper
 :broker/order-id "8b8f3b7d-1234-5678-90ab-fedcba123456"
 :broker/status :broker-status/accepted
 :broker/observed-at "2026-06-10T14:31:02.181Z"}
```

## 11.5 `:fact/fill-observed`

```clojure
{:order-intent/id "oi_..."
 :broker/source-system :broker/alpaca-paper
 :broker/order-id "8b8f3b7d-1234-5678-90ab-fedcba123456"
 :fill/id "trade-42"
 :fill/occurred-at "2026-06-10T14:31:04.001Z"
 :fill/quantity "1"
 :fill/price "2.10"
 :fill/liquidity :liquidity/unknown}
```

## 12. Order-Intent Identity Algorithm

The order-intent identity model is one of the most important choices in the system.

It must support:

- deterministic replay
- restart-safe submit deduplication
- explicit differentiation between logically distinct intents

## 12.1 Identity Inputs

The canonical order-intent identity input is:

```clojure
{:identity/version 1
 :identity/decision-id "dec_..."
 :identity/intent-slot 0
 :identity/account-id "account/alpaca/paper-ops"
 :identity/role :intent-role/entry
 :identity/order-shape
 {:side :order-side/buy
  :effect :position-effect/open
  :order-type :order-type/limit
  :time-in-force :tif/day
  :quantity "1"
  :limit-price "2.15"
  :stop-price nil
  :legs [{:instrument/id "option/OPRA/SPY/2026-06-19/C/550.000"
          :leg/side :order-side/buy
          :leg/quantity "1"}]}}
```

## 12.2 Identity Algorithm

Recommended algorithm:

1. canonicalize the identity input map
2. sort map keys and preserve leg ordering rules
3. serialize canonically
4. hash with SHA-256
5. encode as lowercase hex or base32 token

The encoded hash is the durable `order-intent-id`.

## 12.3 Leg Ordering Rule

If the strategy generates a multi-leg order, leg ordering must be canonical.

Recommended canonical sort:

1. `instrument-id`
2. side
3. quantity

If business semantics require preserving explicit leg sequence, then the sequence itself must be part of the identity input.

## 12.4 What Must Change The Identity

These changes must produce a different `order-intent-id`:

- different account
- different role
- different quantity
- different instrument leg set
- different order type
- different limit or stop prices
- different decision slot

## 12.5 What Must Not Change The Identity

These must not change the identity:

- process restarts
- snapshot boundaries
- broker acknowledgement timing
- adapter retry count
- storage location

## 13. Validation Rules

The schema layer must reject:

- missing required keys
- unknown enum values in strict fields
- binary floating-point payloads in canonical numeric fields
- malformed business ids
- random order-intent ids that do not match the identity algorithm

## 14. Acceptance Criteria

This schema spec is sufficient for v0.1 if:

1. a fact from any adapter can be normalized into these envelopes
2. replay produces the same `order-intent-id` for the same logical decision
3. fill deduplication can rely on explicit identity fields
4. snapshots can be validated without live objects
5. a developer can inspect one durable record and understand its lineage
