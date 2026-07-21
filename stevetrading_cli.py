"""Small, cross-platform operator CLI for the Basilisp trading system.

This module intentionally contains no trading logic.  It validates the local
checkout and delegates every operation to an existing Basilisp entry point.
"""

from __future__ import annotations

import argparse
import importlib.metadata
import importlib.util
import os
from pathlib import Path
import shutil
import subprocess
import sys
from typing import Sequence


PROJECT_NAME = "stevetrading-basilisp"
ALPACA_CREDENTIAL_PAIRS = (
    ("APCA_API_KEY_ID", "APCA_API_SECRET_KEY"),
    ("ALPACA_API_KEY_ID", "ALPACA_API_SECRET"),
    ("ALPACA_VENTUREVD_API_KEY", "ALPACA_VENTUREVD_API_SECRET"),
)


def repo_root() -> Path:
    explicit = os.environ.get("STEVE_REPO_ROOT")
    return Path(explicit).expanduser().resolve() if explicit else Path(__file__).resolve().parent


def basilisp_executable() -> str | None:
    name = "basilisp.exe" if os.name == "nt" else "basilisp"
    alongside_python = Path(sys.executable).resolve().parent / name
    if alongside_python.is_file():
        return str(alongside_python)
    return shutil.which("basilisp")


def ref_basilisp_executable(ref_root: Path) -> str | None:
    candidates = (
        ref_root / ".venv" / "Scripts" / "basilisp.exe",
        ref_root / ".venv" / "bin" / "basilisp",
    )
    return next((str(candidate) for candidate in candidates if candidate.is_file()), None)


def source_paths(root: Path) -> list[str]:
    return [
        str(path)
        for parent in (root / "components", root / "bases")
        if parent.is_dir()
        for path in sorted(parent.glob("*/src"))
    ]


def forwarded_args(values: Sequence[str]) -> list[str]:
    result = list(values)
    return result[1:] if result[:1] == ["--"] else result


def run_basilisp(
    arguments: Sequence[str],
    extra_env: dict[str, str] | None = None,
    executable: str | None = None,
) -> int:
    executable = executable or basilisp_executable()
    if not executable:
        print("ERROR: Basilisp is not installed in this Python environment.", file=sys.stderr)
        print("Run: python -m pip install -e .", file=sys.stderr)
        return 2
    env = os.environ.copy()
    root = repo_root()
    env["STEVE_REPO_ROOT"] = str(root)
    python_path = source_paths(root)
    if env.get("PYTHONPATH"):
        python_path.append(env["PYTHONPATH"])
    env["PYTHONPATH"] = os.pathsep.join(python_path)
    if extra_env:
        env.update(extra_env)
    return subprocess.call([executable, *arguments], cwd=root, env=env)


def project_version() -> str:
    try:
        return importlib.metadata.version(PROJECT_NAME)
    except importlib.metadata.PackageNotFoundError:
        return "not-installed"


def credential_pair() -> tuple[str, str] | None:
    for key_name, secret_name in ALPACA_CREDENTIAL_PAIRS:
        if os.environ.get(key_name) and os.environ.get(secret_name):
            return key_name, secret_name
    return None


def command_doctor(args: argparse.Namespace) -> int:
    checks: list[tuple[str, bool, str]] = []
    root = repo_root()
    checks.append(("Python", sys.version_info >= (3, 10), sys.version.split()[0]))
    checks.append(("Repository", (root / "pyproject.toml").is_file(), str(root)))
    checks.append(("Basilisp", basilisp_executable() is not None,
                   basilisp_executable() or "not installed"))
    for module in ("basilisp", "databento"):
        checks.append((f"Python module {module}", importlib.util.find_spec(module) is not None,
                       "installed" if importlib.util.find_spec(module) else "missing"))
    version = project_version()
    checks.append(("Project installation", version != "not-installed",
                   version if version != "not-installed" else "run: python -m pip install -e ."))

    pair = credential_pair()
    credential_ok = pair is not None
    credential_detail = (
        f"{pair[0]} + {pair[1]} are set" if pair
        else "not set (needed only for Alpaca commands/experiments)"
    )

    failed = False
    for label, ok, detail in checks:
        print(f"[{'OK' if ok else 'FAIL'}] {label}: {detail}")
        failed = failed or not ok
    credential_status = "OK" if credential_ok else ("FAIL" if args.require_alpaca else "WARN")
    print(f"[{credential_status}] Alpaca credentials: {credential_detail}")
    failed = failed or (args.require_alpaca and not credential_ok)
    if not failed:
        print("Ready.")
    return 1 if failed else 0


def command_status(args: argparse.Namespace) -> int:
    values = forwarded_args(args.arguments) or ["all", "--markdown"]
    return run_basilisp(["run", "scripts/current_pnl.lpy", "--", *values])


def command_alpaca(_: argparse.Namespace) -> int:
    if not credential_pair():
        print("ERROR: no supported Alpaca credential pair is set.", file=sys.stderr)
        print("Set APCA_API_KEY_ID and APCA_API_SECRET_KEY, then retry.", file=sys.stderr)
        return 2
    return run_basilisp(["run", "scripts/alpaca_paper_check.lpy"])


def command_run(args: argparse.Namespace) -> int:
    root = repo_root()
    script = Path(args.script)
    resolved = script.resolve() if script.is_absolute() else (root / script).resolve()
    try:
        display = str(resolved.relative_to(root))
    except ValueError:
        print("ERROR: --script must point to a .lpy file inside this checkout.", file=sys.stderr)
        return 2
    if resolved.suffix.lower() != ".lpy" or not resolved.is_file():
        print(f"ERROR: Basilisp script not found: {display}", file=sys.stderr)
        return 2
    values = forwarded_args(args.arguments)
    command = ["run", display]
    if values:
        command.extend(["--", *values])
    return run_basilisp(command)


def command_six(args: argparse.Namespace) -> int:
    root = repo_root()
    ref_root_value = args.ref_root or os.environ.get("STEVE_REF_ROOT")
    if not ref_root_value:
        print("ERROR: supply --ref-root or set STEVE_REF_ROOT.", file=sys.stderr)
        print("This must be SteveTrading/ref/Data-Preprocessor, containing .env and model artifacts.",
              file=sys.stderr)
        return 2
    ref_root = Path(ref_root_value).expanduser().resolve()
    if not (ref_root / ".env").is_file():
        print(f"ERROR: expected credential file is missing: {ref_root / '.env'}", file=sys.stderr)
        return 2
    ref_basilisp = ref_basilisp_executable(ref_root)
    if not ref_basilisp:
        print(f"ERROR: the legacy model environment has no Basilisp executable: {ref_root / '.venv'}",
              file=sys.stderr)
        print("Install this project into that environment before launching the six legacy models.",
              file=sys.stderr)
        return 2
    env = {
        "STEVE_REF_ROOT": str(ref_root),
        "STEVE_DRY_RUN": "0" if args.execute else "1",
        "BROKER_TARGET": args.broker,
        "STEVE_STOCK_BAR_SOURCE": args.stock_source,
    }
    if args.execute:
        print(f"Starting the six-strategy PAPER session with broker target '{args.broker}'.")
    else:
        print("Running six-strategy preflight only; no trading loop will start.")
    return run_basilisp(["run", "scripts/launch_steve_six.lpy"], env,
                        executable=ref_basilisp)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="steve",
        description="Safe operator commands for the SteveTrading Basilisp system.",
    )
    parser.add_argument("--version", action="version", version=f"%(prog)s {project_version()}")
    commands = parser.add_subparsers(dest="command", required=True)

    doctor = commands.add_parser("doctor", help="Check installation and optional Alpaca credentials.")
    doctor.add_argument("--require-alpaca", action="store_true",
                        help="Fail unless a supported Alpaca credential pair is set.")
    doctor.set_defaults(handler=command_doctor)

    status = commands.add_parser("status", help="Show current Alpaca and simulator status/P&L.")
    status.add_argument("arguments", nargs=argparse.REMAINDER,
                        help="Arguments forwarded to current_pnl.lpy (default: all --markdown).")
    status.set_defaults(handler=command_status)

    alpaca = commands.add_parser(
        "alpaca",
        help="Read-only Alpaca paper connectivity and credential check.",
    )
    alpaca.set_defaults(handler=command_alpaca)

    run = commands.add_parser("run", help="Run a repository Basilisp script.")
    run.add_argument("script", help="Repository-relative path to a .lpy script.")
    run.add_argument("arguments", nargs=argparse.REMAINDER,
                     help="Arguments after an optional -- are forwarded to the script.")
    run.set_defaults(handler=command_run)

    six = commands.add_parser("six", help="Preflight or launch the established six-strategy paper session.")
    six.add_argument("--ref-root", help="Path to SteveTrading/ref/Data-Preprocessor.")
    six.add_argument("--broker", choices=("sim", "alpaca", "both"), default="sim",
                     help="Broker target (default: sim).")
    six.add_argument("--stock-source", choices=("alpaca", "thetadata"), default="alpaca")
    six.add_argument("--execute", action="store_true",
                     help="Start the session. Without this flag, only the launcher's dry-run runs.")
    six.set_defaults(handler=command_six)
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    return int(args.handler(args))


if __name__ == "__main__":
    raise SystemExit(main())
