# Components

This directory contains the reusable Polylith-style components for the Basilisp rewrite.

Initial planned component families:

- `domain.*`
- `engine.*`
- `strategy.*`
- `feature.*`
- `inference.*`
- `signal.*`
- `risk.*`
- `execution.*`
- `ledger.*`
- `portfolio.*`
- `broker.*`
- `market-data.*`
- `persistence.*`
- `observability.*`
- `control-plane.*`
- `artifact.*`
- support components such as `time.core`, `calendar.core`, `config.core`, and `replay.fixture`

Each component directory currently contains empty `src/` and `test/` folders.

Implementation rule:

- public ownership belongs to the component
- cross-component usage should flow through the component's public API only
