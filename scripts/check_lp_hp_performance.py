#!/usr/bin/env python3
"""Enforce the measured HP-to-LP CoreMark/MHz performance ratio."""

from __future__ import annotations

import argparse
import json
import sys
from decimal import Decimal, InvalidOperation
from pathlib import Path


def result(report: dict[str, object], label: str) -> dict[str, object]:
    if report.get("status") != "passed":
        raise ValueError(f"{label} CoreMark report did not pass")
    results = report.get("results")
    if not isinstance(results, list) or len(results) != 1 or not isinstance(results[0], dict):
        raise ValueError(f"{label} CoreMark report must contain exactly one result")
    return results[0]


def compare(
    lp_report: dict[str, object], hp_report: dict[str, object], threshold: Decimal
) -> dict[str, object]:
    if threshold <= 0:
        raise ValueError("minimum performance ratio must be positive")
    lp = result(lp_report, "LP")
    hp = result(hp_report, "HP")
    if lp.get("mode") != hp.get("mode"):
        raise ValueError("LP and HP CoreMark reports must use the same mode")
    if lp.get("cpu_hz") != hp.get("cpu_hz"):
        raise ValueError("LP and HP CoreMark reports must use the same fixed frequency")
    try:
        lp_score = Decimal(str(lp["coremark_per_mhz"]))
        hp_score = Decimal(str(hp["coremark_per_mhz"]))
        ratio = hp_score / lp_score
    except (InvalidOperation, KeyError, ZeroDivisionError) as error:
        raise ValueError("invalid CoreMark/MHz values") from error
    passed = ratio >= threshold
    return {
        "schema_version": 1,
        "status": "passed" if passed else "failed",
        "frequency_hz": lp["cpu_hz"],
        "mode": lp["mode"],
        "lp_coremark_per_mhz": str(lp_score),
        "hp_coremark_per_mhz": str(hp_score),
        "minimum_ratio": str(threshold),
        "measured_ratio": str(ratio.quantize(Decimal("0.001"))),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lp", type=Path, required=True)
    parser.add_argument("--hp", type=Path, required=True)
    parser.add_argument("--minimum-ratio", type=Decimal, default=Decimal("2.5"))
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    try:
        report = compare(
            json.loads(args.lp.read_text(encoding="utf-8")),
            json.loads(args.hp.read_text(encoding="utf-8")),
            args.minimum_ratio,
        )
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(f"performance comparison failed: {error}", file=sys.stderr)
        return 1
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    if report["status"] != "passed":
        print(
            f"HP/LP CoreMark/MHz ratio {report['measured_ratio']} is below "
            f"{report['minimum_ratio']}",
            file=sys.stderr,
        )
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
