# Broker Adapter Contracts v0.1

## 1. Purpose

This document formalizes the broker boundary for the Basilisp rewrite of StevenTrading.

It locks:

- broker protocol responsibilities
- canonical broker command set
- canonical broker response and observation shapes
- reconciliation expectations
- adapter error and idempotency rules

This spec is normative for v0.1.

## 2. Design Intent

The broker boundary must make it possible to:

1. submit and cancel orders safely
2. reconcile after restart without duplicate exposure
3. normalize heterogeneous broker APIs into one internal contract
4. separate broker transport details from portfolio truth

The broker adapter is an edge translator, not a second engine.

## 3. Broker Boundary Responsibilities

The broker adapter is responsible for:

- translating canonical broker commands to broker-native calls
- attaching adapter-facing idempotency keys where supported
- normalizing broker responses into canonical facts
- exposing broker truth needed for reconciliation
- surfacing health and dependency status

The broker adapter is not responsible for:

- strategy decisions
- portfolio accounting
- order-intent creation
- deciding whether ambiguous truth is safe to resubmit

## 4. Canonical Broker Commands

The canonical command families are:

1. submit
2. cancel
3. query open orders
4. query fills since cursor
5. query account state
6. health check

## 4.1 `:command/submit-order-intent`

Purpose:

- submit one canonical order intent to the broker

Required payload:

```clojure
{:order-intent/id "oi_..."
 :command/idempotency-key "submit/intent/oi_..."
 :broker/account-id "account/alpaca/paper-ops"
 :broker/route {:broker/source-system :broker/alpaca-paper}
 :order-intent/payload {...canonical order intent...}}
```

Required adapter behavior:

- map internal order shape to broker-native request
- preserve enough correlation data to map later acks and fills back to `order-intent-id`
- emit canonical facts for success, rejection, or transport fault

## 4.2 `:command/cancel-broker-order`

Purpose:

- request cancellation for a known unresolved order

Required payload:

```clojure
{:order-intent/id "oi_..."
 :broker/account-id "account/alpaca/paper-ops"
 :broker/order-id "8b8f3b7d-1234-5678-90ab-fedcba123456"
 :command/idempotency-key "cancel/intent/oi_..."}
```

Required rule:

- cancel commands require proven lineage to an existing unresolved order

## 4.3 `:command/request-broker-open-orders`

Purpose:

- retrieve currently open broker orders for one account scope

Required payload:

```clojure
{:broker/account-id "account/alpaca/paper-ops"
 :query/scope :query-scope/open-orders}
```

## 4.4 `:command/request-broker-fills-since`

Purpose:

- retrieve fills or executions after a broker-specific cursor

Required payload:

```clojure
{:broker/account-id "account/alpaca/paper-ops"
 :query/cursor {:cursor/type :cursor/timestamp
                :cursor/value "2026-06-10T14:30:00Z"}}
```

## 4.5 `:command/request-broker-account-state`

Purpose:

- query broker cash, buying power, positions, or similar account truth used for observation and diagnostics

Required rule:

- account observations may inform reconciliation and diagnostics, but canonical portfolio truth still comes from internal facts plus normalized broker observations

## 4.6 `:command/request-broker-health`

Purpose:

- verify adapter connectivity and broker-service availability

## 5. Canonical Broker Observations And Outcomes

The adapter must normalize broker results into canonical facts, not return raw SDK objects.

## 5.1 Acknowledgement Facts

Accepted form:

```clojure
{:record/type :fact/broker-ack-accepted
 :fact/payload
 {:order-intent/id "oi_..."
  :broker/source-system :broker/alpaca-paper
  :broker/account-id "account/alpaca/paper-ops"
  :broker/order-id "8b8f3b7d-1234-5678-90ab-fedcba123456"
  :broker/status :broker-status/accepted
  :broker/observed-at "2026-06-10T14:31:02.181Z"}}
```

Rejected form:

```clojure
{:record/type :fact/broker-ack-rejected
 :fact/payload
 {:order-intent/id "oi_..."
  :broker/source-system :broker/alpaca-paper
  :broker/account-id "account/alpaca/paper-ops"
  :broker/rejection-code :broker-rejection/insufficient-buying-power
  :broker/rejection-message "normalized message"
  :broker/observed-at "2026-06-10T14:31:02.181Z"}}
```

## 5.2 Order Status Facts

Normalized status facts must use canonical status semantics.

Minimum fields:

- `order-intent-id` if lineage is proven
- broker account id
- broker order id
- canonical broker status
- observed timestamp

Allowed canonical statuses:

- `:broker-status/new`
- `:broker-status/accepted`
- `:broker-status/open`
- `:broker-status/partially-filled`
- `:broker-status/filled`
- `:broker-status/cancelled`
- `:broker-status/rejected`
- `:broker-status/expired`

## 5.3 Fill Facts

Minimum normalized payload:

```clojure
{:order-intent/id "oi_..."
 :broker/source-system :broker/alpaca-paper
 :broker/account-id "account/alpaca/paper-ops"
 :broker/order-id "8b8f3b7d-1234-5678-90ab-fedcba123456"
 :fill/id "trade-42"
 :fill/occurred-at "2026-06-10T14:31:04.001Z"
 :fill/quantity "1"
 :fill/price "2.10"}
```

## 5.4 Account Observation Facts

These are normalized observations, not authoritative replacements for internal ledger truth.

Minimum fields:

- account id
- source system
- observed timestamp
- buying power if available
- cash if available
- broker-reported positions if available

## 6. Submit Flow Contract

The expected submit path is:

1. engine emits `submit-order-intent`
2. adapter sends broker-native request
3. adapter emits `command-dispatched`
4. adapter emits `broker-ack-accepted`, `broker-ack-rejected`, or `fault-recorded`
5. later broker updates emit status and fill facts

Required rule:

- `command-dispatched` is operational evidence only
- `broker-ack-*` and `fill-observed` are canonical broker outcomes

## 7. Cancel Flow Contract

The expected cancel path is:

1. engine emits `cancel-broker-order`
2. adapter sends broker-native cancel request
3. adapter emits `command-dispatched`
4. adapter emits normalized cancel acknowledgement or later broker cancelled status
5. if a fill races the cancel, fill truth wins for portfolio effects

## 8. Reconciliation Contract

The adapter must support recovery-time truth gathering.

Required reconciliation capabilities:

- query open orders for an account
- query fills since a durable cursor or equivalent fallback
- map broker identities back to internal lineage where possible

If the broker cannot provide one of these directly, the adapter must document its fallback semantics explicitly.

## 8.1 Reconciliation Inputs

The adapter should accept:

- account scope
- known broker order ids
- durable fill cursor if available
- time window if cursor is unavailable

## 8.2 Reconciliation Outputs

The adapter returns canonical facts only:

- open-order status facts
- fill facts
- account observation facts
- anomaly or fault facts

## 9. Idempotency Rules

1. Submit must use a stable idempotency key when the broker supports one.
2. If the broker does not support client idempotency, the adapter must preserve enough correlation state to avoid unsafe duplicate submits.
3. Cancel commands must be idempotent with respect to retries.
4. Duplicate broker observations must normalize to duplicate-safe canonical facts.

## 10. Error Model

Broker adapter faults must be normalized into these categories:

- transport unavailable
- authentication or authorization failure
- rate limiting
- request validation failure
- broker-side rejection
- ambiguous response
- reconciliation failure

The adapter must not throw opaque SDK exceptions across the boundary as the primary contract.

## 11. Health Contract

The broker adapter must expose at least:

- connectivity status
- credential validity status where safely testable
- rate-limit or quota pressure where available
- last successful broker interaction time

Health checks must not submit live orders.

## 12. Live, Paper, Sim Differences

The same broker protocol applies to:

- live broker adapter
- paper broker adapter
- simulator adapter

Differences are limited to:

- external transport
- execution semantics
- reconciliation source

The canonical command and fact language must stay stable across all of them.

## 13. Acceptance Criteria

This broker contract is sufficient for v0.1 if:

1. one engine can use live, paper, or sim adapters without branching the core
2. restart reconciliation can recover unresolved orders without duplicate exposure
3. broker SDK payloads never leak into canonical facts
4. fill and status observations are lineage-safe
5. adapter faults are normalized and observable
