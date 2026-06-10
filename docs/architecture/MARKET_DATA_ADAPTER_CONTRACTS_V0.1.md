# Market Data Adapter Contracts v0.1

## 1. Purpose

This document formalizes the market-data boundary for the Basilisp rewrite of StevenTrading.

It locks:

- canonical market-data responsibilities
- observation shapes
- provenance and quality requirements
- adapter command and subscription semantics
- replay compatibility rules

This spec is normative for v0.1.

## 2. Design Intent

The market-data boundary must make it possible to:

1. feed live, paper, sim, and replay through one normalized event language
2. make data provenance explicit
3. keep feature and strategy code adapter-blind
4. surface data quality issues without hidden fallbacks

Market-data adapters are source translators, not feature engines.

## 3. Boundary Responsibilities

The market-data adapter is responsible for:

- subscribing, polling, or loading source data
- normalizing source payloads into canonical facts
- attaching provenance and quality metadata
- exposing source health and lag
- supporting replay-capable source cursors where possible

The adapter is not responsible for:

- feature derivation
- strategy warmup logic
- business-time interpretation beyond canonical session facts
- decision-making

## 4. Canonical Observation Families

The canonical market observation families are:

1. bars
2. quotes
3. option-chain snapshots
4. calendar and session facts
5. source health and anomaly facts

## 4.1 Bar Facts

Minimum canonical payload:

```clojure
{:bar/time "2026-06-10T14:30:00Z"
 :bar/timeframe :timeframe/1m
 :bar/open "550.10"
 :bar/high "550.22"
 :bar/low "549.98"
 :bar/close "550.05"
 :bar/volume "18234"
 :data/provider :market-data/polygon
 :data/provider-ref "polygon:bar:SPY:2026-06-10T14:30:00Z"
 :data/received-at "2026-06-10T14:30:00.412Z"
 :data/quality {:quality/complete? true}}
```

## 4.2 Quote Facts

Minimum canonical payload:

```clojure
{:quote/time "2026-06-10T14:30:00.412Z"
 :quote/bid "550.01"
 :quote/ask "550.03"
 :quote/bid-size "5"
 :quote/ask-size "7"
 :data/provider :market-data/polygon
 :data/provider-ref "polygon:quote:SPY:abc123"
 :data/received-at "2026-06-10T14:30:00.413Z"
 :data/quality {:quality/stale? false}}
```

## 4.3 Option-Chain Snapshot Facts

Minimum canonical payload:

```clojure
{:chain/observed-at "2026-06-10T14:30:00.500Z"
 :chain/underlying "equity/NASDAQ/SPY"
 :chain/contracts [{:instrument/id "option/OPRA/SPY/2026-06-19/C/550.000"
                    :quote/bid "2.10"
                    :quote/ask "2.15"}]
 :data/provider :market-data/polygon
 :data/provider-ref "polygon:chain:SPY:2026-06-10T14:30:00.500Z"}
```

## 4.4 Session Facts

Minimum canonical payload:

```clojure
{:session/exchange "XNYS"
 :session/trading-date "2026-06-10"
 :session/state :session-state/open
 :session/observed-at "2026-06-10T13:30:00Z"}
```

## 5. Provenance Rules

Every canonical market-data fact must carry:

- provider identity
- provider-specific reference or source cursor where possible
- received-at timestamp
- effective market timestamp
- quality metadata

If any of these are unavailable, the adapter must either:

- provide an explicit `unknown` value, or
- emit an anomaly fact

Silent omission is forbidden for required provenance fields.

## 6. Quality Rules

Adapters must surface at least these quality conditions where detectable:

- stale data
- partial snapshots
- out-of-order observations
- missing required fields
- source lag beyond configured threshold
- session calendar mismatch

Quality issues may degrade strategy operation according to policy, but they must not disappear silently.

## 7. Canonical Data Acquisition Commands

Not all adapters need explicit pull commands, but the canonical contract supports them.

## 7.1 `:command/request-market-bars`

Purpose:

- fetch historical or catch-up bars for one instrument scope

## 7.2 `:command/request-quotes`

Purpose:

- fetch or subscribe to quotes for one instrument scope

## 7.3 `:command/request-option-chain`

Purpose:

- fetch or refresh an option-chain snapshot

## 7.4 `:command/request-calendar-state`

Purpose:

- retrieve current session state or calendar context

These commands are adapter-facing only.

They do not belong in strategy code.

## 8. Streaming And Polling Contract

The adapter may implement:

- streaming
- polling
- hybrid ingestion

Regardless of transport mode, the output to the engine is always canonical facts.

The engine must not care whether a fact arrived through websocket, HTTP polling, file replay, or batch load.

## 9. Replay Contract

Replay adapters must emit the same canonical fact shapes as live adapters.

Allowed replay differences:

- synthetic receive timing
- deterministic pacing controls
- source references that point to fixture records instead of live providers

Forbidden replay differences:

- alternate field names
- missing provenance fields
- replay-only domain semantics

## 10. Error And Health Model

Market-data adapter faults must be normalized into categories such as:

- source unavailable
- authentication failure
- rate limiting
- malformed payload
- stale source
- session mismatch
- replay fixture corruption

Health reporting should include:

- last successful data receipt time
- observed source lag
- current subscription or polling status
- active degradation flags

## 11. Warmup Contract

Warmup is an engine and strategy concern, but adapters must support it by making historical or recent catch-up data available.

Required rule:

- warmup data and live data must normalize to the same canonical observation shapes

## 12. Acceptance Criteria

This market-data contract is sufficient for v0.1 if:

1. live and replay use the same canonical fact shapes
2. provenance is explicit on every observation
3. quality issues are observable and policy-driven
4. feature code never reaches into source-specific payloads
5. the engine can remain transport-agnostic
