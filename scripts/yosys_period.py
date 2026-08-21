#!/usr/bin/env python3
"""Derive the Yosys ABC target period from the SoC clock/reset inventory."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any


def require_object(value: Any, field: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise ValueError(f"{field} must be an object")
    return value


def require_string(value: Any, field: str) -> str:
    if not isinstance(value, str) or not value:
        raise ValueError(f"{field} must be a non-empty string")
    return value


def period_ps(document: dict[str, Any], domain: str = "external") -> int:
    require_string(domain, "domain")
    domains = document.get("domains")
    if not isinstance(domains, list) or not domains:
        raise ValueError("domains must be a non-empty list")
    for entry in domains:
        item = require_object(entry, "domains entry")
        if item.get("name") != domain:
            continue
        sta = require_object(item.get("sta"), f"domain {domain}.sta")
        period_ns = sta.get("period_ns")
        if not isinstance(period_ns, (int, float)) or isinstance(period_ns, bool) or period_ns <= 0:
            raise ValueError(f"domain {domain}.sta.period_ns must be a positive number")
        return round(float(period_ns) * 1000)
    raise ValueError(f"domain {domain} is not declared")


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--domains", type=Path, required=True)
    parser.add_argument("--domain", default="external")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    try:
        document = require_object(
            json.loads(args.domains.read_text(encoding="utf-8")), "domain map"
        )
        print(period_ps(document, args.domain))
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(error, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
