"""Freeze publication chapter/IP entries without freezing pagination or small subsections."""
from __future__ import annotations

import re


def content_text(value) -> str:
    if isinstance(value, str):
        return value
    if isinstance(value, list):
        return "".join(content_text(item) for item in value)
    if isinstance(value, dict):
        if value.get("func") in {"space", "linebreak"}:
            return " "
        if "text" in value:
            return content_text(value["text"])
        if "children" in value:
            return content_text(value["children"])
        if "body" in value:
            return content_text(value["body"])
    raise ValueError("unsupported publication heading content")


def structure_entries(headings: list[dict], ip_ids: set[str]) -> list[dict]:
    entries = []
    for heading in headings:
        anchor = heading.get("label")
        if anchor == "none":
            anchor = None
        elif isinstance(anchor, str) and anchor.startswith("<") and anchor.endswith(">"):
            anchor = anchor[1:-1]
        if (heading["level"] <= 2 and heading.get("outlined", True)) or anchor in ip_ids:
            entries.append({"level": heading["level"],
                            "title": re.sub(r"\s+", " ", content_text(heading["title"])).strip(),
                            "anchor": anchor})
    return entries


def validate_structure(contract: dict, headings: list[dict], index: list[dict]) -> None:
    if contract.get("schema_version") != 1 or contract.get("state") != "frozen":
        raise ValueError("publication structure requires an explicit frozen baseline")
    ids = [row["id"] for row in index]
    if ids != contract["ip_ids"] or len(ids) != len(set(ids)):
        raise ValueError("frozen publication IP entry order changed")
    actual = structure_entries(headings, set(ids))
    if actual != contract["entries"]:
        raise ValueError("frozen publication chapter/IP structure changed; review an explicit structure update")
    anchors = [row["anchor"] for row in actual if row["anchor"] in set(ids)]
    if anchors != ids:
        raise ValueError("frozen publication IP heading missing or duplicated")
