# Control Plane Manifests And Validation v0.1

## 1. Purpose

This document formalizes the control-plane schema and validation rules for the Basilisp rewrite of StevenTrading.

It locks:

- manifest structure
- revision and activation semantics
- routing and rollout rules
- validation requirements
- kill-switch and retirement behavior

This spec is normative for v0.1.

## 2. Design Intent

The control plane exists to make operational policy:

1. explicit
2. versioned
3. reviewable
4. validated before runtime
5. safe by default

The control plane is not a hidden runtime registry.

It is a declarative artifact.

## 3. Manifest Structure

The control plane consists of:

1. one top-level manifest document
2. one immutable revision id
3. one activation record

## 3.1 Top-Level Fields

Minimum manifest shape:

```clojure
{:control-plane/revision "cp-000014"
 :control-plane/generated-at "2026-06-10T13:55:00Z"
 :control-plane/status :control-plane-status/proposed
 :control-plane/strategies [...]
 :control-plane/accounts [...]
 :control-plane/processes [...]
 :control-plane/routes [...]
 :control-plane/kill-switches [...]
 :control-plane/policies {...}}
```

## 3.2 Revision Rules

- revisions are immutable
- activation never mutates an old revision in place
- one revision may be active per deployment scope
- the active revision id must be recorded in runtime facts and snapshots

## 4. Strategy Declaration

Each strategy entry must declare:

- `strategy-id`
- family
- version
- enabled flag
- mode
- schedule
- required account route
- artifact references
- process assignment
- degradation policy reference

Minimum example:

```clojure
{:strategy/id "strategy/spx-credit/spread-entry/v1"
 :strategy/enabled? true
 :strategy/mode :mode/paper
 :strategy/process "engine-paper-main"
 :strategy/account-route "route/paper-spreads"
 :strategy/artifacts {:model-ref "model/spx-credit/v7"
                      :feature-manifest-ref "feature/spx-credit/v3"}
 :strategy/schedule {:session :session/us-equities-regular}}
```

## 5. Account Declaration

Each account entry must declare:

- internal account id
- broker source system
- environment class
- allowed modes
- live-trading eligibility

Example:

```clojure
{:account/id "account/alpaca/paper-ops"
 :account/broker :broker/alpaca-paper
 :account/environment :environment/paper
 :account/allowed-modes #{:mode/paper :mode/shadow}
 :account/live-enabled? false}
```

## 6. Process Declaration

Each process entry must declare:

- process id
- runtime base
- allowed modes
- assigned strategies
- assigned accounts if fixed

Example:

```clojure
{:process/id "engine-paper-main"
 :process/base :base/engine-live
 :process/allowed-modes #{:mode/paper}
 :process/strategies ["strategy/spx-credit/spread-entry/v1"]}
```

## 7. Route Declaration

Routes bind strategy intent to execution destination.

Each route entry must declare:

- route id
- strategy id or strategy family scope
- account id
- broker source system
- allowed order classes if constrained

Example:

```clojure
{:route/id "route/paper-spreads"
 :route/strategy-id "strategy/spx-credit/spread-entry/v1"
 :route/account-id "account/alpaca/paper-ops"
 :route/broker :broker/alpaca-paper}
```

## 8. Kill Switches

Kill switches must be declarative and explicit.

Each kill-switch entry must declare:

- scope
- active flag
- reason
- activated-at
- actor

Allowed scopes:

- global
- process
- strategy
- account

If a kill switch matches runtime scope, trading must halt according to policy before order submission.

## 9. Validation Rules

The control plane must be validated before activation and again at runtime load.

## 9.1 Structural Validation

The validator must reject:

- missing required fields
- malformed ids
- duplicate ids
- unknown enum values
- invalid references between strategies, accounts, processes, and routes

## 9.2 Safety Validation

The validator must reject:

- live strategies routed to non-live-eligible processes where incompatible
- paper strategies routed to live-only accounts
- strategies with no valid route
- processes assigned modes they are not allowed to run
- conflicting kill-switch scope semantics

## 9.3 Policy Validation

The validator should reject or warn on:

- strategy artifact references with incompatible versions
- route declarations that violate allowed order-class policies
- account usage outside declared environment class

## 10. Activation Semantics

Activation is a separate step from manifest creation.

Activation must:

1. validate the proposed revision
2. write an activation record
3. mark the revision active for the target scope
4. make the active revision discoverable to runtime processes

Runtime processes must record which revision they loaded.

## 11. Runtime Load Semantics

At startup the engine must:

1. load the active control-plane revision
2. validate that its own process id is allowed by that revision
3. validate assigned strategies, accounts, and routes
4. refuse to trade if any blocking control-plane violation exists

## 12. Retirement Rules

Retired strategies, routes, processes, and accounts remain closed by default.

Retirement must be explicit in the control plane.

Implicit resurrection through stale config is forbidden.

## 13. Audit Rules

Every activation, kill-switch change, and material route change must be visible through:

- control-plane revision records
- activation records
- runtime facts that capture active revision and violations

## 14. Acceptance Criteria

This control-plane spec is sufficient for v0.1 if:

1. routing and rollout policy are fully declarative
2. unsafe account or process bindings fail before trading starts
3. kill switches are explicit and auditable
4. runtime snapshots and facts can prove which revision was active
5. no strategy requires hidden runtime registration to become active
