# Strategy Pipeline And Artifact Model v0.1

## 1. Purpose

This document formalizes the strategy pipeline and artifact model for the Basilisp rewrite of StevenTrading.

It locks:

- strategy declaration shape
- feature, inference, signal, risk, and execution stage boundaries
- artifact reference rules
- strategy-local state expectations
- versioning and compatibility rules

This spec is normative for v0.1.

## 2. Design Intent

The strategy layer must make it possible to:

1. declare strategies as data plus pure functions where possible
2. separate feature derivation from inference from execution planning
3. version artifacts explicitly
4. replay the same strategy logic across modes
5. keep infrastructure concerns out of strategy definitions

Strategies are compositions of pipeline stages, not mini-applications.

## 3. Strategy Pipeline Stages

The canonical strategy pipeline is:

1. market-state selection
2. feature derivation
3. inference or model scoring
4. signal decision
5. risk decision
6. execution planning
7. order-intent creation

Each stage should have explicit inputs and outputs.

## 4. Strategy Declaration Shape

Minimum strategy declaration:

```clojure
{:strategy/id "strategy/spx-credit/spread-entry/v1"
 :strategy/family :strategy-family/spx-credit
 :strategy/name :strategy-name/spread-entry
 :strategy/version 1
 :strategy/mode-policy #{:mode/replay :mode/sim :mode/paper}
 :strategy/schedule {:session :session/us-equities-regular}
 :strategy/warmup {:required-bars 120}
 :strategy/features {:manifest-ref "feature/spx-credit/v3"}
 :strategy/inference {:artifact-ref "model/spx-credit/v7"}
 :strategy/signal {:fn-id :signal/spx-credit-v1}
 :strategy/risk {:policy-id :risk/spx-credit-default}
 :strategy/execution {:policy-id :execution/spread-limit-v1}}
```

Required rule:

- every strategy must be serializable and reviewable without executing code

## 5. Stage Boundaries

## 5.1 Market-State Selection

Inputs:

- normalized market facts
- session facts
- strategy-local state

Outputs:

- strategy-specific market-state slice

This stage must not fetch new data directly.

## 5.2 Feature Derivation

Inputs:

- strategy market-state slice
- feature manifest

Outputs:

- canonical feature map

Rules:

- features must be deterministic
- features must not perform provider I/O
- feature ordering must be explicit where model input order matters

## 5.3 Inference

Inputs:

- canonical feature map
- model artifact reference

Outputs:

- canonical prediction record

Rules:

- artifact loading is an adapter or artifact-service concern
- inference stage sees artifact handles or loaded model abstractions, not filesystem policy

## 5.4 Signal Decision

Inputs:

- prediction record
- market-state slice
- strategy-local state

Outputs:

- signal decision fact candidates

Signal code should answer:

- what opportunity exists
- in what direction
- with what confidence or posture

## 5.5 Risk Decision

Inputs:

- signal decision
- portfolio view
- account constraints
- strategy-local risk state

Outputs:

- allow, deny, resize, or defer decision

Risk code should answer:

- are we allowed to act
- at what size or under what constraints

## 5.6 Execution Planning

Inputs:

- risk-approved signal
- instrument definitions
- execution policy

Outputs:

- canonical execution plan
- one or more order intents

Execution code should answer:

- how do we express this safely as orders

## 6. Strategy-Local State

Strategy-local state may include:

- warmup completion markers
- cooldown timers
- posture memory
- strategy-specific deterministic accumulators

Strategy-local state must be:

- serializable
- explicit
- replay-safe
- reconstructible from snapshots plus facts where required

Hidden closure state is forbidden for correctness.

## 7. Artifact Model

Artifacts are immutable versioned references used by strategy stages.

Artifact classes:

1. feature manifests
2. model artifacts
3. optional calibration metadata

## 7.1 Feature Manifest

A feature manifest should define:

- manifest id
- version
- feature names
- feature ordering if needed
- required market inputs
- compatibility notes

Example:

```clojure
{:feature-manifest/id "feature/spx-credit/v3"
 :feature-manifest/version 3
 :feature-manifest/features [:feature/iv-rank
                             :feature/realized-vol-20d
                             :feature/spread-width]
 :feature-manifest/required-inputs [:input/bar-1m :input/option-chain]}
```

## 7.2 Model Artifact Reference

A model reference should define:

- artifact id
- version
- expected feature manifest
- prediction schema version
- training or build metadata reference

Example:

```clojure
{:model/id "model/spx-credit/v7"
 :model/version 7
 :model/feature-manifest-ref "feature/spx-credit/v3"
 :model/prediction-schema-version 1}
```

## 8. Version Compatibility Rules

The control plane and runtime validators must reject incompatible combinations such as:

- strategy declaration references missing feature manifest
- model artifact expects different feature manifest version
- signal stage expects a prediction schema not produced by the model artifact
- execution policy incompatible with declared instrument family

## 9. Mode Independence Rules

The same strategy declaration should be usable in:

- replay
- sim
- paper
- live where allowed by policy

Allowed mode differences:

- adapter implementations
- live availability of certain external observations

Forbidden mode differences:

- alternate strategy logic path hidden by mode
- replay-only feature semantics
- paper-only order-intent identity logic

## 10. Acceptance Criteria

This strategy pipeline spec is sufficient for v0.1 if:

1. a strategy can be described as data plus explicit stage functions
2. feature, inference, signal, risk, and execution boundaries are clean
3. artifact compatibility can be validated before runtime
4. strategy-local state is explicit and replay-safe
5. the same strategy definition can run across modes without core branching
