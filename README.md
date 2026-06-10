# StevenTrading Basilisp Rewrite

This repository is the ground-up Basilisp rewrite of the existing StevenTrading Python system.

The current status is:

- north-star document written
- architecture package written
- initial conversion layer started
- Polylith-oriented workspace directories created
- ADR set started
- example manifests, fixtures, and contract payloads added under `resources/`

## Workspace Overview

- `NORTHSTAR.md`: project direction and hard centers
- `docs/architecture/`: normative architecture package
- `docs/adr/`: key irreversible architecture decisions
- `components/`: reusable Polylith-style components
- `bases/`: runtime assembly bases
- `projects/`: deployable or test-focused workspace projections
- `development/`: local development notes and REPL-oriented material
- `resources/`: manifests, fixtures, and example contract payloads
- `scripts/`: operational scripts and future tooling

## Current Intent

The next implementation steps are:

1. keep turning architecture into concrete assets
2. add the first empty-but-owned component and base modules
3. add initial workspace/tooling files
4. begin core domain and engine kernel work only after the scaffold is coherent
