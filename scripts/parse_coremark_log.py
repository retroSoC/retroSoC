#!/usr/bin/env python3
"""Convert the quick Hazard3 CoreMark UART report into structured JSON."""

from __future__ import annotations

import argparse
import json
import re
import sys
from decimal import Decimal, InvalidOperation, ROUND_HALF_UP
from pathlib import Path


RESULT_PREFIX = "COREMARK_RESULT "
PASS_MARKER = "COREMARK_PASS"
FAIL_PREFIX = "COREMARK_FAIL"
REQUIRED_FIELDS = {"mode", "qualified", "memory", "iterations", "cycles", "cpu_hz"}
TOKEN = re.compile(r"([a-z_]+)=([^\s]+)")


def parse_number(value: str) -> int:
    return int(value, 0)


def parse_log(content: str) -> dict[str, object]:
    results: list[dict[str, object]] = []
    for line in content.splitlines():
        if not line.startswith(RESULT_PREFIX):
            continue
        fields = {name: value for name, value in TOKEN.findall(line)}
        missing = REQUIRED_FIELDS.difference(fields)
        if missing:
            raise ValueError(f"CoreMark result is missing fields: {sorted(missing)}")
        mode = fields["mode"]
        if mode not in {"quick", "standard"}:
            raise ValueError(f"unsupported CoreMark mode: {mode}")
        memory = fields["memory"]
        if memory != "sram":
            raise ValueError(f"CoreMark result must execute from SRAM, got: {memory}")
        qualified = parse_number(fields["qualified"])
        if qualified not in {0, 1}:
            raise ValueError("CoreMark qualified flag must be zero or one")
        iterations = parse_number(fields["iterations"])
        cycles = parse_number(fields["cycles"])
        cpu_hz = parse_number(fields["cpu_hz"])
        if iterations <= 0 or cycles <= 0 or cpu_hz <= 0:
            raise ValueError("CoreMark iterations, cycles, and cpu_hz must be positive")
        try:
            score = (Decimal(iterations) * Decimal(1_000_000) / Decimal(cycles)).quantize(
                Decimal("0.001"), rounding=ROUND_HALF_UP
            )
        except (InvalidOperation, ZeroDivisionError) as error:
            raise ValueError("invalid CoreMark score inputs") from error
        results.append(
            {
                "mode": mode,
                "qualified": bool(qualified),
                "memory": memory,
                "iterations": iterations,
                "cycles": cycles,
                "cpu_hz": cpu_hz,
                "coremark_per_mhz": str(score),
            }
        )

    pass_marker = PASS_MARKER in content
    failure_marker = any(line.startswith(FAIL_PREFIX) for line in content.splitlines())
    quick_results = [result for result in results if result["mode"] == "quick"]
    passed = pass_marker and not failure_marker and len(quick_results) == 1
    return {
        "schema_version": 1,
        "status": "passed" if passed else "failed",
        "failure_marker": failure_marker,
        "pass_marker": pass_marker,
        "results": results,
    }


def atomic_write(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(content, encoding="utf-8")
    temporary.replace(path)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--log", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    report = parse_log(args.log.read_text(encoding="utf-8", errors="replace"))
    atomic_write(args.output, json.dumps(report, indent=2, sort_keys=True) + "\n")
    if report["status"] != "passed":
        print("CoreMark did not emit one complete quick passing report", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
