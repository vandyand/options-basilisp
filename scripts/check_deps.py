#!/usr/bin/env python
"""Enforce dependency direction across workspace components (POLYLITH spec section 7).

Pure namespaces (domain/engine/ledger/portfolio and the pure pipeline:
strategy/feature/inference/signal/risk/execution) may NOT require adapter
namespaces or any stevetrading.base.* namespace. Protocol components
(*.protocol) are importable by anyone.

Parses (:require ...) / (require ...) forms from every component .lpy file
and matches required namespaces (hyphenated, as written in source) against
the forbidden prefixes. Violations print and exit 1.

Run with: .venv/bin/python scripts/check_deps.py
"""

import glob
import os
import re
import sys

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Namespace prefixes whose components must stay pure (no adapter/base requires).
PURE_PREFIXES = (
    "stevetrading.domain.",
    "stevetrading.engine.",
    "stevetrading.ledger.",
    "stevetrading.portfolio.",
    "stevetrading.strategy.",
    "stevetrading.feature.",
    "stevetrading.inference.",
    "stevetrading.signal.",
    "stevetrading.risk.",
    "stevetrading.execution.",
)

# Adapter namespace prefixes (hyphenated ns names as written in :require
# forms, not underscored file paths) plus all base namespaces.
FORBIDDEN_PREFIXES = (
    "stevetrading.broker.alpaca",
    "stevetrading.broker.sim",
    "stevetrading.market-data.replay",
    "stevetrading.market-data.polygon",
    "stevetrading.persistence.fact-store",
    "stevetrading.persistence.snapshot-store",
    "stevetrading.observability.structured-log",
    "stevetrading.control-plane.file-store",
    "stevetrading.artifact.file-store",
    "stevetrading.base.",
)

REQUIRE_OPEN_RE = re.compile(r"\((?::require\b|require\b)")
NS_TOKEN_RE = re.compile(r"stevetrading[\w.\-]*")


def component_files():
    return sorted(
        glob.glob(
            os.path.join(REPO_ROOT, "components", "*", "src", "**", "*.lpy"),
            recursive=True,
        )
    )


def file_namespace(path):
    """Compute the (hyphenated) namespace a component .lpy file defines."""
    # path: components/<name>/src/<pkg...>/<mod>.lpy
    parts = path.split(os.sep)
    src_idx = parts.index("src")
    rel = parts[src_idx + 1 :]
    mod = ".".join(rel)[: -len(".lpy")]
    return mod.replace("_", "-")


def strip_comments(text):
    return re.sub(r";[^\n]*", "", text)


def require_blocks(text):
    """Yield the text of each (:require ...)/(require ...) form (balanced parens)."""
    for m in REQUIRE_OPEN_RE.finditer(text):
        start = m.start()
        depth = 0
        for i in range(start, len(text)):
            ch = text[i]
            if ch == "(":
                depth += 1
            elif ch == ")":
                depth -= 1
                if depth == 0:
                    yield text[start : i + 1]
                    break


def required_namespaces(text):
    text = strip_comments(text)
    nses = set()
    for block in require_blocks(text):
        nses.update(NS_TOKEN_RE.findall(block))
    return nses


def main():
    violations = []
    for path in component_files():
        own_ns = file_namespace(path)
        if not own_ns.startswith(PURE_PREFIXES):
            continue
        with open(path, encoding="utf-8") as f:
            text = f.read()
        for req in sorted(required_namespaces(text)):
            if req.startswith(FORBIDDEN_PREFIXES):
                violations.append((own_ns, req, path))

    if violations:
        print("check_deps: dependency direction violations:", file=sys.stderr)
        for own_ns, req, path in violations:
            print(f"  {own_ns} requires {req}  ({path})", file=sys.stderr)
        sys.exit(1)
    print(f"check_deps: {len(component_files())} component files OK")


if __name__ == "__main__":
    main()
