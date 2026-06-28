#!/usr/bin/env python3
"""Summarize durable sim broker journals under live_runtime.

This is intentionally stdlib-only and read-only. It does not parse EDN; the
canonical details remain in facts.db. The durable broker DB proves the broker
journal exists and when it was last persisted.
"""

from __future__ import annotations

import glob
import os
import sqlite3


ROOT = "live_runtime"


def one(sql_path: str, sql: str, params: tuple = ()):
    try:
        with sqlite3.connect(sql_path) as conn:
            row = conn.execute(sql, params).fetchone()
            return row[0] if row else None
    except sqlite3.Error:
        return None


def fact_count(facts_db: str, fact_type: str) -> int:
    value = one(
        facts_db,
        "select count(*) from facts where fact_type = ?",
        (fact_type,),
    )
    return int(value or 0)


def journal_text(sql_path: str) -> str:
    try:
        with sqlite3.connect(sql_path) as conn:
            row = conn.execute(
                "select record from sim_journal where id = 'main'"
            ).fetchone()
            return row[0] if row else ""
    except sqlite3.Error:
        return ""


def main() -> int:
    paths = sorted(glob.glob(os.path.join(ROOT, "*", "sim-broker.db")))
    if not paths:
        print("No durable sim broker journals found under live_runtime/*/sim-broker.db")
        return 0

    print("SIM BROKER JOURNALS")
    print("session | updated_at | journal_bytes | settlements | order_intents | fills")
    print("-" * 86)
    for path in paths:
        session = os.path.basename(os.path.dirname(path))
        updated = one(path, "select updated_at from sim_journal where id = 'main'")
        size = one(path, "select length(record) from sim_journal where id = 'main'")
        settlements = journal_text(path).count(":fact/option-settlement-recorded")
        facts_db = os.path.join(os.path.dirname(path), "facts.db")
        if os.path.exists(facts_db):
            intents = fact_count(facts_db, ":fact/order-intent-created")
            fills = fact_count(facts_db, ":fact/fill-observed")
        else:
            intents = fills = 0
        print(
            f"{session} | {updated or '-'} | {size or 0} | "
            f"{settlements} | {intents} | {fills}"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
