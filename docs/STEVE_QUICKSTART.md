# Steve Quick Start

This is the shortest supported path from a fresh checkout to inspecting or
running SteveTrading. The `steve` command is a thin launcher: all trading,
broker, engine, and reconciliation behavior remains in Basilisp.

## 1. Install on Windows PowerShell

Requirements: Git and Python 3.12.

```powershell
git clone https://github.com/vandyand/options-basilisp.git
cd options-basilisp

py -3.12 -m venv .venv
.\.venv\Scripts\python.exe -m pip install --upgrade pip
.\.venv\Scripts\python.exe -m pip install -e .

.\.venv\Scripts\steve.exe doctor
```

`pip install -e .` installs the project's pinned Basilisp version and normal
dependencies. It does not install the legacy model bundle's large
Torch/XGBoost environment or provide credentials and model artifacts.

Linux uses the same sequence with `python3`, `.venv/bin/python`, and
`.venv/bin/steve`.

## 2. Safe commands

```powershell
# Validate the checkout. Missing Alpaca credentials are only a warning.
.\.venv\Scripts\steve.exe doctor

# Require an Alpaca credential pair to be present without printing its value.
.\.venv\Scripts\steve.exe doctor --require-alpaca

# Make a read-only request to the Alpaca paper account endpoint.
.\.venv\Scripts\steve.exe alpaca

# Show current paper/simulator P&L and positions.
.\.venv\Scripts\steve.exe status

# Run any repository Basilisp utility without remembering Basilisp CLI syntax.
.\.venv\Scripts\steve.exe run scripts\databento_schema_inventory.lpy -- --help
```

The CLI never stores or prints secret values. Credentials belong in the
operator's secret store or process environment, never in Git.

## 3. The established six-strategy session

The current six-strategy launcher is not a standalone example. It requires:

- the `SteveTrading/ref/Data-Preprocessor` directory;
- its `.env` containing the six Alpaca paper-account credential pairs;
- its `.venv`, with Basilisp plus the existing Torch/XGBoost model environment;
- live market-data dependencies required by the selected source.

Always run the preflight first. The CLI defaults to the simulator and dry-run:

```powershell
.\.venv\Scripts\steve.exe six `
  --ref-root C:\path\to\SteveTrading\ref\Data-Preprocessor
```

Starting an actual paper session requires the explicit `--execute` flag:

```powershell
.\.venv\Scripts\steve.exe six `
  --ref-root C:\path\to\SteveTrading\ref\Data-Preprocessor `
  --broker alpaca `
  --execute
```

This targets Alpaca paper trading, not a live-money brokerage endpoint.
Nevertheless, paper orders and positions are real external state: check the
account, market-data services, session clock, and active strategy files first.

## 4. Trying a new idea

Do not copy the broker adapter into a new Python trading system. Add a small
Basilisp strategy or experiment entry point and run it through:

```powershell
.\.venv\Scripts\steve.exe run scripts\my_experiment.lpy
```

The reusable Alpaca implementation is
`components/broker.alpaca/src/stevetrading/broker/alpaca.lpy`. It already
handles paper REST requests, deterministic client-order IDs, normalized
errors, fills, open-order reconciliation, and health checks.

For a new strategy, specify before allowing orders:

1. input market data and its timing;
2. entry and exit decisions;
3. position sizing and maximum exposure;
4. session cutoff and forced-flatten behavior;
5. simulator/dry-run evidence;
6. the Alpaca paper account that owns the experiment.

## Troubleshooting

- **`steve` is not recognized:** use `.\.venv\Scripts\steve.exe`, or activate
  the virtual environment first.
- **Basilisp is missing:** rerun
  `.\.venv\Scripts\python.exe -m pip install -e .`.
- **`six` asks for `--ref-root`:** point it at
  `SteveTrading/ref/Data-Preprocessor`; the launcher deliberately refuses to
  guess a machine-specific path.
- **The legacy environment has no Basilisp executable:** install the checkout
  into the Data-Preprocessor environment as well, then rerun the preflight.
- **Credentials are missing:** do not paste them into a source file. Configure
  the expected environment variables or the existing protected `.env`.
- **ThetaData is unavailable:** the six-strategy launcher may still require its
  SPY option-chain source even when Alpaca supplies stock bars.
