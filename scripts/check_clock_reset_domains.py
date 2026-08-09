#!/usr/bin/env python3
"""Validate the declared Mini SoC root clock/reset domains and CDC crossings."""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from typing import Any


RESET_PRIMITIVES = {"rst_sync"}
CDC_PRIMITIVES = {
    "async_fifo",
    "cdc_2phase",
    "cdc_sync",
    "edge_det",
    "hazard3_apb_async_bridge",
}
IDENTIFIER_RE = re.compile(r"[A-Za-z_][A-Za-z0-9_]*$")
HIERARCHICAL_PIN_RE = re.compile(
    r"[A-Za-z_][A-Za-z0-9_.]*(?:/[A-Za-z_][A-Za-z0-9_.]*)+$"
)


def require_object(value: Any, field: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise ValueError(f"{field} must be an object")
    return value


def require_string(value: Any, field: str) -> str:
    if not isinstance(value, str) or not value:
        raise ValueError(f"{field} must be a non-empty string")
    return value


def require_identifier(value: Any, field: str) -> str:
    identifier = require_string(value, field)
    if IDENTIFIER_RE.fullmatch(identifier) is None:
        raise ValueError(f"{field} must be a SystemVerilog identifier")
    return identifier


def require_positive_number(value: Any, field: str) -> float:
    if not isinstance(value, (int, float)) or isinstance(value, bool) or value <= 0:
        raise ValueError(f"{field} must be a positive number")
    return float(value)


def require_hierarchical_pin(value: Any, field: str) -> str:
    pin = require_string(value, field)
    if HIERARCHICAL_PIN_RE.fullmatch(pin) is None:
        raise ValueError(f"{field} must be a hierarchical instance pin")
    return pin


def require_instance(path: Path, primitive: str, instance: str, field: str) -> None:
    if not path.is_file():
        raise ValueError(f"{field}.path does not exist: {path}")
    source = path.read_text(encoding="utf-8")
    expression = re.compile(rf"\b{re.escape(primitive)}\b[\s\S]*?\b{re.escape(instance)}\b")
    if expression.search(source) is None:
        raise ValueError(f"{field} does not declare {primitive} instance {instance}")


def validate(document_path: Path, root: Path) -> None:
    document = require_object(json.loads(document_path.read_text(encoding="utf-8")), "domain map")
    if document.get("schema_version") != 2:
        raise ValueError("schema_version must be 2")

    raw_domains = document.get("domains")
    if not isinstance(raw_domains, list) or not raw_domains:
        raise ValueError("domains must be a non-empty list")
    names: set[str] = set()
    sta_sources: dict[str, str | None] = {}
    for index, value in enumerate(raw_domains):
        field = f"domains[{index}]"
        domain = require_object(value, field)
        name = require_identifier(domain.get("name"), f"{field}.name")
        if name in names:
            raise ValueError(f"domain {name} is duplicated")
        names.add(name)
        require_identifier(domain.get("clock"), f"{field}.clock")
        require_identifier(domain.get("reset"), f"{field}.reset")
        require_identifier(domain.get("reset_source"), f"{field}.reset_source")
        primitive = require_string(domain.get("reset_primitive"), f"{field}.reset_primitive")
        if primitive not in RESET_PRIMITIVES:
            raise ValueError(f"{field}.reset_primitive is not supported")
        path = root / require_string(domain.get("path"), f"{field}.path")
        instance = require_identifier(domain.get("instance"), f"{field}.instance")
        require_instance(path, primitive, instance, field)
        sta = require_object(domain.get("sta"), f"{field}.sta")
        source_port = sta.get("source_port")
        source_domain = sta.get("source_domain")
        if (source_port is None) == (source_domain is None):
            raise ValueError(f"{field}.sta must declare exactly one source")
        if source_port is not None:
            require_identifier(source_port, f"{field}.sta.source_port")
            sta_sources[name] = None
        else:
            sta_sources[name] = require_identifier(source_domain, f"{field}.sta.source_domain")
        object_type = sta.get("object_type", "pin")
        if object_type not in {"pin", "port"}:
            raise ValueError(f"{field}.sta.object_type must be pin or port")
        if object_type == "pin":
            require_hierarchical_pin(sta.get("pin"), f"{field}.sta.pin")
        elif source_port is None:
            raise ValueError(f"{field}.sta port object requires source_port")
        require_positive_number(sta.get("period_ns"), f"{field}.sta.period_ns")
        require_identifier(sta.get("async_group"), f"{field}.sta.async_group")

    for name, source_domain in sta_sources.items():
        if source_domain is not None and source_domain not in names:
            raise ValueError(f"domain {name} STA source references unknown domain {source_domain}")

    raw_crossings = document.get("crossings")
    if not isinstance(raw_crossings, list):
        raise ValueError("crossings must be a list")
    crossing_names: set[str] = set()
    for index, value in enumerate(raw_crossings):
        field = f"crossings[{index}]"
        crossing = require_object(value, field)
        name = require_identifier(crossing.get("name"), f"{field}.name")
        if name in crossing_names:
            raise ValueError(f"crossing {name} is duplicated")
        crossing_names.add(name)
        source = require_identifier(crossing.get("source"), f"{field}.source")
        destination = require_identifier(crossing.get("destination"), f"{field}.destination")
        if source not in names or destination not in names:
            raise ValueError(f"{field} references an unknown domain")
        if source == destination:
            raise ValueError(f"{field} must cross between distinct domains")
        primitive = require_string(crossing.get("primitive"), f"{field}.primitive")
        if primitive not in CDC_PRIMITIVES:
            raise ValueError(f"{field}.primitive is not an approved CDC primitive")
        path = root / require_string(crossing.get("path"), f"{field}.path")
        instance = require_identifier(crossing.get("instance"), f"{field}.instance")
        require_instance(path, primitive, instance, field)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--map", required=True, type=Path)
    parser.add_argument("--root", required=True, type=Path)
    arguments = parser.parse_args()
    try:
        validate(arguments.map, arguments.root)
    except (OSError, ValueError, json.JSONDecodeError) as error:
        parser.error(str(error))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
