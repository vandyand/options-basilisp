# Engine State Machines v0.1

## 1. Purpose

This document formalizes the engine's primary state machines as explicit transition systems.

It locks:

- machine states
- valid transitions
- transition triggers
- guard rules
- required side effects and emitted facts

This spec is normative for v0.1.

## 2. Design Rules

1. State transitions are data-driven, not hidden in ad hoc control flow.
2. Terminal states are explicit.
3. Duplicate observations converge to no-op or idempotent transitions.
4. Illegal transitions emit faults instead of mutating state silently.
5. A state machine may emit commands, but commands do not become canonical truth unless the resulting facts are recorded.

## 3. Implementation Shape

The recommended implementation is a transition table per machine.

Each row should define:

- current state
- trigger fact or control event
- guard predicate
- next state
- emitted commands
- emitted facts if any

Pure engine code should evaluate these tables.

Adapters should not own canonical state transitions.

## 4. Strategy Lifecycle Machine

### 4.1 States

- `inactive`
- `warming-up`
- `active`
- `degraded`
- `halted`

### 4.2 Transition Table

| Current | Trigger | Guard | Next | Required Effects |
| --- | --- | --- | --- | --- |
| `inactive` | strategy enabled or engine startup with strategy assigned | control-plane route valid | `warming-up` | emit lifecycle fact |
| `warming-up` | warmup satisfied | dependencies healthy and required history loaded | `active` | emit lifecycle fact |
| `warming-up` | dependency degradation | degradation policy allows continue | `degraded` | emit degradation fact |
| `active` | dependency degradation | strategy may continue without violating risk policy | `degraded` | emit degradation fact |
| `degraded` | degradation cleared | warmup still satisfied and dependencies healthy | `active` | emit recovery fact |
| `inactive` | kill switch or control violation | none | `halted` | emit control violation fact |
| `warming-up` | kill switch or invariant violation | none | `halted` | emit halt fact |
| `active` | kill switch or invariant violation | none | `halted` | emit halt fact |
| `degraded` | kill switch or invariant violation | none | `halted` | emit halt fact |
| `halted` | operator reset and strategy re-enabled | explicit recovery authorization | `inactive` | emit reset fact |

### 4.3 Behavioral Rules

- `inactive` may not emit trading decisions.
- `warming-up` may consume data and build state but may not emit order intents.
- `active` may emit full strategy decisions.
- `degraded` may emit decisions only if the degradation policy explicitly allows it.
- `halted` may not emit trading decisions or recovery actions except operator-visible status.

## 5. Order Lifecycle Machine

### 5.1 States

- `absent`
- `intent-created`
- `submit-requested`
- `acknowledged`
- `partially-filled`
- `filled`
- `cancel-requested`
- `cancelled`
- `rejected`
- `orphaned-needs-reconcile`

### 5.2 Transition Table

| Current | Trigger Fact | Guard | Next | Required Effects |
| --- | --- | --- | --- | --- |
| `absent` | `order-intent-created` | schema valid | `intent-created` | register unresolved lineage |
| `intent-created` | `command-dispatched` for submit | command idempotency valid | `submit-requested` | record dispatch metadata |
| `intent-created` | `broker-ack-accepted` | lineage proven | `acknowledged` | record external correlation |
| `intent-created` | `broker-ack-rejected` | lineage proven | `rejected` | resolve order |
| `submit-requested` | `broker-ack-accepted` | lineage proven | `acknowledged` | record external correlation |
| `submit-requested` | `broker-ack-rejected` | lineage proven | `rejected` | resolve order |
| `submit-requested` | reconciliation anomaly | ack status ambiguous | `orphaned-needs-reconcile` | emit anomaly fact |
| `acknowledged` | partial `fill-observed` | remaining quantity positive | `partially-filled` | update fill lineage |
| `acknowledged` | complete `fill-observed` | remaining quantity zero | `filled` | resolve order |
| `acknowledged` | `command-dispatched` for cancel | cancel allowed | `cancel-requested` | record cancel dispatch |
| `acknowledged` | broker cancelled status | no fill quantity | `cancelled` | resolve order |
| `partially-filled` | partial `fill-observed` | remaining quantity positive | `partially-filled` | accumulate fill facts |
| `partially-filled` | complete `fill-observed` | remaining quantity zero | `filled` | resolve order |
| `partially-filled` | `command-dispatched` for cancel | remaining quantity positive | `cancel-requested` | record cancel dispatch |
| `cancel-requested` | `fill-observed` | remaining quantity positive | `partially-filled` | apply cancel race rule |
| `cancel-requested` | `fill-observed` | remaining quantity zero | `filled` | resolve order from fill truth |
| `cancel-requested` | broker cancel acknowledgement or cancelled status | remaining quantity positive or zero and not filled | `cancelled` | resolve order |
| `cancel-requested` | reconciliation anomaly | external truth ambiguous | `orphaned-needs-reconcile` | emit anomaly fact |
| `orphaned-needs-reconcile` | reconciled open status | lineage proven | `acknowledged` | restore unresolved state |
| `orphaned-needs-reconcile` | reconciled partial fill | lineage proven | `partially-filled` | restore fill lineage |
| `orphaned-needs-reconcile` | reconciled complete fill | lineage proven | `filled` | resolve order |
| `orphaned-needs-reconcile` | reconciled reject | lineage proven | `rejected` | resolve order |
| `orphaned-needs-reconcile` | reconciled cancel | lineage proven | `cancelled` | resolve order |

### 5.3 Terminal States

Terminal states:

- `filled`
- `cancelled`
- `rejected`

Once terminal, only duplicate or explanatory anomaly facts may be accepted.

No new submit or cancel commands may be emitted.

### 5.4 Illegal Order Transitions

The engine must reject and fault on:

- `filled` to any non-terminal state
- `cancelled` to `filled` without new lineage proving the prior state was wrong
- `rejected` to `acknowledged` for the same order intent
- any transition that changes `order-intent-id`

## 6. Recovery Lifecycle Machine

### 6.1 States

- `not-started`
- `loading-snapshot`
- `replaying-facts`
- `reconciling-broker`
- `ready`
- `degraded-ready`
- `blocked`
- `recovery-failed`

### 6.2 Transition Table

| Current | Trigger | Guard | Next | Required Effects |
| --- | --- | --- | --- | --- |
| `not-started` | engine boot | none | `loading-snapshot` | emit `recovery-started` |
| `loading-snapshot` | snapshot accepted | none | `replaying-facts` | load snapshot state |
| `loading-snapshot` | no valid snapshot | allowed fallback | `replaying-facts` | begin fact replay from origin or prior watermark |
| `loading-snapshot` | snapshot parse failure with no valid fallback | none | `recovery-failed` | emit fault |
| `replaying-facts` | fact replay complete | no reconciliation required | `ready` | emit `recovery-completed` |
| `replaying-facts` | fact replay complete | reconciliation required | `reconciling-broker` | issue broker query commands |
| `replaying-facts` | replay ambiguity violates safety | none | `blocked` | emit anomaly fact |
| `reconciling-broker` | reconciliation complete | no material degradation remains | `ready` | emit `recovery-completed` |
| `reconciling-broker` | reconciliation complete | non-fatal degradation remains | `degraded-ready` | emit degradation fact |
| `reconciling-broker` | ambiguity could create unsafe exposure | none | `blocked` | emit anomaly fact |
| `reconciling-broker` | unrecoverable storage or invariant fault | none | `recovery-failed` | emit fault |
| `degraded-ready` | degradation cleared before trading starts | all blocking checks pass | `ready` | emit recovery fact |

### 6.3 Recovery Rules

- `blocked` is not a crash; it is a deliberate safety stop.
- `recovery-failed` means the engine could not establish a coherent internal state.
- `degraded-ready` allows runtime entry only if the degradation policy explicitly permits it.

## 7. Health Lifecycle Machine

### 7.1 States

- `starting`
- `healthy`
- `degraded`
- `stopping`
- `stopped`

### 7.2 Transition Table

| Current | Trigger | Guard | Next | Required Effects |
| --- | --- | --- | --- | --- |
| `starting` | startup checks pass | recovery state is `ready` or allowed `degraded-ready` | `healthy` | emit heartbeat |
| `starting` | startup checks partially fail | degradation policy allows continue | `degraded` | emit degradation fact |
| `healthy` | dependency degradation | degradation policy allows continue | `degraded` | emit degradation fact |
| `degraded` | degradations cleared | all required dependencies healthy | `healthy` | emit recovery fact |
| `healthy` | shutdown requested | none | `stopping` | emit heartbeat |
| `degraded` | shutdown requested | none | `stopping` | emit heartbeat |
| `starting` | shutdown requested | none | `stopping` | emit heartbeat |
| `stopping` | process shutdown complete | none | `stopped` | emit final heartbeat or status fact |

### 7.3 Health Rules

- `healthy` does not imply every dependency is perfect; it means all required invariants for safe operation hold.
- `degraded` means the engine is still coherent but running under reduced confidence or reduced functionality.
- `stopped` is terminal for one run id.

## 8. Transition Handling Rules

### 8.1 Duplicate Facts

If a duplicate fact arrives for the same canonical identity:

- do not re-transition
- do not emit duplicate commands
- preserve the original terminal state

### 8.2 Out-Of-Order Facts

If a fact arrives out of order but lineage is valid:

- record the fact
- apply the transition if the table and guards allow it
- emit anomaly or ordering diagnostics where useful

If lineage is not valid:

- move to anomaly handling
- do not guess

### 8.3 Illegal Transition Policy

Illegal transitions must:

1. emit a fault or anomaly fact
2. preserve the last known coherent state
3. avoid side effects that could increase exposure

## 9. Acceptance Criteria

The state-machine layer is sufficient for v0.1 if:

1. every major runtime state change can be explained as a table row
2. duplicate observations converge without duplicate exposure
3. cancel races resolve through explicit transitions rather than hidden branching
4. recovery can terminate in `ready`, `degraded-ready`, `blocked`, or `recovery-failed` with clear meaning
5. a developer can audit an order lifecycle without reading adapter code
