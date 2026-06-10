# ADR-0001: Modular Monolith Runtime With Polylith-Style Codebase

## Status

Accepted

## Context

The existing Python system mixes multiple runtime styles, overlapping abstractions, and legacy script composition.

The rewrite needs:

- one coherent runtime model
- strong internal boundaries
- reusable components
- simpler deployment and operations

## Decision

The system will use:

- a modular monolith runtime
- a Polylith-style codebase structure

That means:

- one primary deployable engine process initially
- internal components around bounded business concepts
- bases for runtime composition
- no microservices-first split

## Consequences

Positive:

- simpler restart and observability story
- easier reasoning about state and recovery
- clearer dependency direction

Negative:

- less immediate independent scaling by subsystem
- requires discipline to preserve boundaries inside one codebase
