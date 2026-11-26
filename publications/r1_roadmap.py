"""Calendar coordinates for the publication-only R1 family roadmap."""
from __future__ import annotations

from datetime import date
import re


def _quarter(value: str) -> int:
    match = re.fullmatch(r"(\d{4})Q([1-4])", value)
    if not match:
        raise ValueError(f"invalid R1 roadmap quarter: {value!r}")
    return 4 * int(match[1]) + int(match[2]) - 1


def _quarter_label(index: int) -> str:
    year, q = divmod(index, 4)
    return f"{year} Q{q + 1}"


def _day_position(iso: str, *, inclusive_end: bool = False) -> float:
    day = date.fromisoformat(iso)
    q = (day.month - 1) // 3
    first = date(day.year, 3 * q + 1, 1)
    next_year, next_q = divmod(day.year * 4 + q + 1, 4)
    days = (date(next_year, 3 * next_q + 1, 1) - first).days
    return day.year * 4 + q + ((day - first).days + int(inclusive_end)) / days


def roadmap_reference(config: dict) -> dict:
    """Keep date precision for observations and include the first and last quarters of a plan."""
    first = _quarter(config["first_quarter"])
    stop = _quarter(config["last_quarter"]) + 1
    cutoff = _day_position(config["as_of"], inclusive_end=True)
    products = config["products"]
    if [p["name"] for p in products] != ["TINY", "MINI", "STD", "PRO", "MAX", "ULTRA"]:
        raise ValueError("R1 roadmap requires the six product-line chips in reading order")
    if not first < cutoff <= stop:
        raise ValueError("R1 roadmap review date falls outside the quarter axis")

    def source(key: str, kind: str) -> dict:
        record = config["sources"].get(key, {})
        if (record.get("kind") != kind or not record.get("title")
                or (kind == "history" and not record.get("url", "").startswith("https://"))):
            raise ValueError(f"R1 roadmap requires a {kind} source for {key!r}")
        return record

    rows = []
    for p in products:
        if p["status"] not in {"In development", "Roadmap", "Concept"} or p["group"] not in {"embedded", "professional"}:
            raise ValueError(f"unknown R1 roadmap status or family group for {p['name']}")
        observed = p["status"] == "In development"
        evidence = source(p["source"], "history" if observed else "plan")
        if observed:
            if p["end"] is not None:
                raise ValueError("R1 in-development history requires an open end")
            start = _quarter(p["start"]) if "Q" in p["start"] else _day_position(p["start"])
            end = cutoff
            period = _quarter_label(int(start)) + "–ongoing"
        else:
            start = _quarter(p["start"])
            if not p["end"] or start < cutoff:
                raise ValueError(f"R1 planned window must have future quarters for {p['name']}")
            end = _quarter(p["end"]) + 1
            label = _quarter_label(end - 1)
            period = _quarter_label(start) + "–" + (label.split()[1] if start // 4 == (end - 1) // 4 else label)
        if not first <= start < end <= stop:
            raise ValueError(f"invalid R1 roadmap interval for {p['name']}")
        milestone = p.get("milestone")
        if milestone is not None:
            event_date = milestone.get("date", p["start"])
            when = _day_position(event_date)
            if not observed or not start <= when < end:
                raise ValueError("R1 milestone must lie inside recorded history")
            event_source = source(milestone.get("source", p["source"]), "history")
            milestone = dict(milestone, date=event_date, offset=when - first,
                             quarter=_quarter_label(int(when)), url=event_source["url"])
        rows.append(dict(p, observed=observed, start_offset=start - first, end_offset=end - first,
                         period=period, source_url=evidence.get("url"), milestone=milestone))
    quarters = [dict(year=q // 4, label=f"Q{q % 4 + 1}") for q in range(first, stop)]
    return dict(as_of=config["as_of"], cutoff_offset=cutoff - first, quarters=quarters,
                sources=config["sources"], products=rows)
