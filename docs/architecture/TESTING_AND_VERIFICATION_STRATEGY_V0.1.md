# Testing And Verification Strategy v0.1

## 1. Purpose

This document formalizes the testing and verification strategy for the Basilisp rewrite of StevenTrading.

It locks:

- test layers
- golden properties
- replay and recovery verification expectations
- contract testing approach
- release-gating expectations

This spec is normative for v0.1.

## 2. Design Intent

Testing must prove:

1. deterministic core behavior
2. restart correctness
3. broker and market-data contract conformance
4. no duplicate exposure under failure and replay
5. control-plane enforcement

This system is not acceptable if it is merely unit-test clean while operationally ambiguous.

## 3. Test Pyramid For This Project

The testing stack should be:

1. pure function and schema tests
2. state-machine and invariant tests
3. adapter contract tests
4. replay and recovery scenario tests
5. end-to-end mode tests

## 4. Pure Function And Schema Tests

These test:

- canonical id generation
- schema validation
- envelope normalization
- strategy pure logic
- feature derivation
- risk and execution transforms

Required property:

- same inputs always produce same outputs

## 5. State-Machine And Invariant Tests

These test:

- legal and illegal lifecycle transitions
- duplicate fact convergence
- cancel-race handling
- unresolved-order state transitions
- ledger and portfolio invariants

Recommended style:

- table-driven tests
- property tests where state explosion is likely

## 6. Adapter Contract Tests

Every adapter must be tested against the canonical contract, not only against its own implementation details.

Required broker contract cases:

- submit accepted
- submit rejected
- duplicate broker observation
- partial fill then full fill
- cancel race
- reconciliation query with unresolved orders

Required market-data contract cases:

- live-like observation normalization
- replay observation normalization
- provenance completeness
- stale-data signaling
- malformed payload rejection

## 7. Replay And Recovery Scenario Tests

These are first-class tests, not extras.

Required scenarios:

1. crash after `order-intent-created` but before submit dispatch
2. crash after dispatch but before ack handling
3. crash after ack but before fill handling
4. crash after fill but before snapshot
5. duplicate fill after restart
6. replay produces same decisions as uninterrupted run
7. recovery blocks when lineage is ambiguous

## 8. Golden Properties

The system must maintain these golden properties:

1. uninterrupted and restarted runs converge to the same durable truth
2. one logical decision yields one stable `order-intent-id`
3. duplicate broker observations do not create duplicate fills or positions
4. replay and live-normalized inputs share the same fact shapes
5. control-plane violations prevent unsafe startup

## 9. End-To-End Mode Tests

The project should run end-to-end tests for:

- replay mode
- simulator mode
- paper mode with broker test doubles where needed

Live mode should be validated through controlled shadow or pre-production workflows, not casual ad hoc testing.

## 10. Test Fixtures

The system should maintain durable fixture sets for:

- normalized market event streams
- broker acknowledgement and fill traces
- control-plane manifest samples
- expected decision outputs

Fixture versions must be immutable for stable regression tests.

## 11. Release Gates

No runtime-capable release is acceptable unless it passes:

- schema and pure-core tests
- state-machine tests
- replay and recovery golden tests
- adapter contract tests for all enabled adapters
- control-plane validation tests

## 12. Incident Regression Rule

Every production-significant bug should produce:

1. a minimal reproducer fixture
2. a regression test at the correct layer
3. a documented invariant or contract clarification if needed

## 13. Acceptance Criteria

This testing strategy is sufficient for v0.1 if:

1. operational correctness is tested explicitly, not assumed
2. replay and restart behavior are part of ordinary CI, not manual drills
3. adapters are verified against canonical contracts
4. every severe bug can be locked behind a regression test
5. the release bar aligns with the system's financial-risk profile
