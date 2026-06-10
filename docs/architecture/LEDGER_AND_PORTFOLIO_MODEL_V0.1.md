# Ledger And Portfolio Model v0.1

## 1. Purpose

This document formalizes the ledger and portfolio model for the Basilisp rewrite of StevenTrading.

It locks:

- canonical ledger responsibilities
- cash and position fact model
- portfolio derivation rules
- exposure and P&L expectations
- reconciliation boundaries

This spec is normative for v0.1.

## 2. Design Intent

The ledger and portfolio layers must make it possible to:

1. derive positions and cash from durable facts
2. explain P&L and exposure without mutable hidden state
3. keep broker observations and internal truth clearly related but distinct
4. rebuild portfolio views after restart and replay

The ledger is canonical.

The portfolio is derived.

## 3. Ledger Responsibilities

`ledger.core` is responsible for:

- recording cash-affecting facts
- recording position-lot open and close facts or equivalent durable lineage
- maintaining exact intent-to-fill-to-position traceability
- exposing deterministic fold logic for canonical financial state

`ledger.core` is not responsible for:

- market-data ingestion
- broker transport
- strategy decisions
- reporting presentation

## 4. Canonical Ledger Facts

The ledger must be able to derive state from these durable facts:

- `fill-observed`
- `cash-movement-recorded`
- `position-lot-opened`
- `position-lot-closed`
- `position-mark-recorded` where marks are durably stored

v0.1 allows some ledger facts to be derived from fills during folding, but the derivation rules must be explicit and deterministic.

## 5. Position Model

The portfolio should be derivable using an explicit lot model.

Each open lot should carry at least:

- lot id
- originating order-intent id
- instrument id
- open timestamp
- open quantity
- remaining quantity
- open price or cost basis components
- strategy id
- account id

This supports:

- exact lineage
- partial closes
- realized P&L attribution

## 6. Cash Model

Cash-affecting events should be explicit.

Minimum cash movement categories:

- trade principal
- fees and commissions
- financing if applicable
- dividends or distributions if modeled
- manual adjustments only through explicit corrective facts

Cash must not be a mutable field updated outside ledger folds.

## 7. Portfolio Derivation

`portfolio.core` derives:

- net positions
- open lots
- realized P&L
- unrealized P&L
- gross and net exposure
- strategy and account views

Portfolio derivations must identify their source watermarks or source fact ranges.

## 8. Marking And Valuation

Valuation should be separated from canonical trade truth.

Trade truth comes from:

- fills
- cash movements
- lot openings and closes

Valuation depends on:

- market marks
- pricing policy

If marks are stored durably, they must be clearly typed as marks, not fills.

## 9. Reconciliation Boundaries

Broker-reported positions and balances are observations, not silent replacements for internal truth.

Allowed use of broker observations:

- detect drift
- support diagnostics
- support explicit reconciliation workflows

Forbidden use:

- mutating internal portfolio truth without explicit corrective lineage

## 10. Correction Model

Corrections must happen through explicit durable facts.

Examples:

- corrected cash movement
- corrective lot adjustment
- reconciliation anomaly fact leading to explicit operator-approved correction

Silent mutation of old portfolio state is forbidden.

## 11. Exposure Model

The portfolio layer should support at least:

- per-account exposure
- per-strategy exposure
- per-underlying exposure
- gross and net notional views
- option-specific exposure extensions later as needed

Exposure is derived from canonical positions and marks.

## 12. Acceptance Criteria

This ledger and portfolio spec is sufficient for v0.1 if:

1. positions and cash can be rebuilt from durable facts
2. partial fills and partial closes preserve exact lineage
3. broker account observations do not silently replace internal truth
4. P&L and exposure are derivable rather than hand-maintained
5. corrections happen through explicit facts, not mutable state
