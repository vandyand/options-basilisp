#!/usr/bin/env python3
"""Compare Alpaca paper option fills to nearest observed ThetaData quotes.

Read-only analysis over a facts.db snapshot. This intentionally uses regexes
against canonical EDN strings instead of adding runtime dependencies.
"""

from __future__ import annotations

import argparse
import re
import sqlite3
from dataclasses import dataclass
from datetime import datetime, timezone
from decimal import Decimal
from statistics import mean, median


FILL_RE = {
    "price": re.compile(r":fill/price \"([^\"]+)\""),
    "qty": re.compile(r":fill/quantity \"([^\"]+)\""),
}
CONTRACT_RE = re.compile(
    r"\{:quote/bid \"([^\"]+)\" :instrument/id \"([^\"]+)\" :quote/ask \"([^\"]+)\""
)


@dataclass(frozen=True)
class Fill:
    occurred_at: str
    account_id: str
    strategy_id: str | None
    instrument_id: str
    order_intent_id: str
    price: Decimal
    qty: Decimal


@dataclass(frozen=True)
class Quote:
    observed_at: str
    instrument_id: str
    bid: Decimal
    ask: Decimal

    @property
    def mid(self) -> Decimal:
        return (self.bid + self.ask) / Decimal("2")


def one(pattern: re.Pattern[str], text: str, default: str | None = None) -> str | None:
    m = pattern.search(text)
    return m.group(1) if m else default


def ts(s: str) -> datetime:
    return datetime.fromisoformat(s.replace("Z", "+00:00")).astimezone(timezone.utc)


def side_for_intent(record: str, instrument_id: str) -> str | None:
    idx = record.find(f':instrument/id "{instrument_id}"')
    if idx < 0:
        return None
    window = record[max(0, idx - 240) : idx + 240]
    m = re.search(r":leg/side :(order-side/(?:buy|sell))", window)
    return m.group(1) if m else None


def load_fills(conn: sqlite3.Connection) -> list[Fill]:
    rows = conn.execute(
        """
        select occurred_at, account_id, strategy_id, instrument_id,
               order_intent_id, record
        from facts
        where fact_type=':fact/fill-observed'
          and instrument_id like 'option/%'
        order by occurred_at
        """
    ).fetchall()
    fills: list[Fill] = []
    for occurred_at, account_id, strategy_id, instrument_id, oi, record in rows:
        price = one(FILL_RE["price"], record)
        qty = one(FILL_RE["qty"], record, "0")
        if not price or not oi:
            continue
        fills.append(
            Fill(
                occurred_at=occurred_at,
                account_id=account_id or "",
                strategy_id=strategy_id,
                instrument_id=instrument_id or "",
                order_intent_id=oi,
                price=Decimal(price),
                qty=Decimal(qty or "0"),
            )
        )
    return fills


def load_intent_sides(conn: sqlite3.Connection) -> dict[tuple[str, str], str]:
    rows = conn.execute(
        """
        select order_intent_id, record
        from facts
        where fact_type=':fact/order-intent-created'
        """
    ).fetchall()
    out: dict[tuple[str, str], str] = {}
    instruments = conn.execute(
        """
        select distinct order_intent_id, instrument_id
        from facts
        where fact_type=':fact/fill-observed'
          and instrument_id like 'option/%'
        """
    ).fetchall()
    records = {oi: record for oi, record in rows}
    for oi, instrument_id in instruments:
        record = records.get(oi)
        if not record:
            continue
        side = side_for_intent(record, instrument_id)
        if side:
            out[(oi, instrument_id)] = side
    return out


def load_quotes(conn: sqlite3.Connection) -> dict[str, list[Quote]]:
    rows = conn.execute(
        """
        select occurred_at, record
        from facts
        where fact_type=':fact/option-chain-observed'
        order by occurred_at
        """
    ).fetchall()
    quotes: dict[str, list[Quote]] = {}
    for observed_at, record in rows:
        for bid, instrument_id, ask in CONTRACT_RE.findall(record):
            quotes.setdefault(instrument_id, []).append(
                Quote(
                    observed_at=observed_at,
                    instrument_id=instrument_id,
                    bid=Decimal(bid),
                    ask=Decimal(ask),
                )
            )
    return quotes


def nearest(quotes: list[Quote], fill_ts: str) -> tuple[Quote, float] | None:
    if not quotes:
        return None
    t = ts(fill_ts)
    q = min(quotes, key=lambda x: abs((ts(x.observed_at) - t).total_seconds()))
    return q, abs((ts(q.observed_at) - t).total_seconds())


def fmt(d: Decimal | None) -> str:
    return "-" if d is None else f"{d:.4f}"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("facts_db")
    ap.add_argument("--max-lag-seconds", type=float, default=90.0)
    ap.add_argument("--limit", type=int, default=80)
    args = ap.parse_args()

    with sqlite3.connect(args.facts_db) as conn:
        fills = load_fills(conn)
        sides = load_intent_sides(conn)
        quotes_by_instrument = load_quotes(conn)

    rows = []
    for fill in fills:
        hit = nearest(quotes_by_instrument.get(fill.instrument_id, []), fill.occurred_at)
        if not hit:
            continue
        quote, lag = hit
        if lag > args.max_lag_seconds:
            continue
        side = sides.get((fill.order_intent_id, fill.instrument_id))
        edge = None
        if side == "order-side/buy":
            edge = fill.price - quote.ask
        elif side == "order-side/sell":
            edge = quote.bid - fill.price
        rows.append(
            {
                "fill": fill,
                "quote": quote,
                "lag": lag,
                "side": side or "?",
                "mid_delta": fill.price - quote.mid,
                "edge": edge,
                "spread": quote.ask - quote.bid,
            }
        )

    print("ALPACA OPTION FILL ALIGNMENT")
    print(f"fills={len(fills)} matched={len(rows)} max_lag_seconds={args.max_lag_seconds}")
    print(
        "time | account | side | instrument | fill | bid | ask | mid_delta | edge_vs_cross | lag_s"
    )
    print("-" * 132)
    for r in rows[-args.limit :]:
        fill: Fill = r["fill"]
        quote: Quote = r["quote"]
        print(
            f"{fill.occurred_at} | {fill.account_id.split('/')[-1]:<14} | "
            f"{r['side'].replace('order-side/', ''):<4} | {fill.instrument_id:<36} | "
            f"{fmt(fill.price):>8} | {fmt(quote.bid):>8} | {fmt(quote.ask):>8} | "
            f"{fmt(r['mid_delta']):>9} | {fmt(r['edge']):>13} | {r['lag']:.1f}"
        )

    if rows:
        mid_deltas = [float(r["mid_delta"]) for r in rows]
        spreads = [float(r["spread"]) for r in rows]
        edge_rows = [float(r["edge"]) for r in rows if r["edge"] is not None]
        print("-" * 132)
        print(
            "summary: "
            f"mid_delta mean={mean(mid_deltas):.4f} median={median(mid_deltas):.4f}; "
            f"spread mean={mean(spreads):.4f} median={median(spreads):.4f}; "
            f"edge_vs_cross mean={mean(edge_rows):.4f} median={median(edge_rows):.4f}"
            if edge_rows
            else "summary: no side-inferred rows"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
