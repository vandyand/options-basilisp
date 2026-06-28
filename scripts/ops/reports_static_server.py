#!/usr/bin/env python3
"""Compatibility wrapper for the ops project script."""

from pathlib import Path
import runpy


ROOT = Path(__file__).resolve().parents[2]
runpy.run_path(str(ROOT / "projects/ops/scripts/reports_static_server.py"), run_name="__main__")
