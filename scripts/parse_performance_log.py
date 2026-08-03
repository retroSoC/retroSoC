#!/usr/bin/env python3
"""Parse reproducible SoC performance benchmark output into structured JSON."""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path


PERF_PREFIX = "PERF "
PASS_MARKER = "PERF_BENCHMARK_PASS"
FAIL_PREFIX = "PERF_FAIL"
REQUIRED_FIELDS = {
    "region",
    "op",
    "words",
    "checksum",
    "cycles",
    "mgmt_wait",
    "rib_wait",
    "sdram_wait",
    "psram_wait",
    "flash_wait",
    "dma_wait",
}
TOKEN = re.compile(r"([a-z_]+)=([^\s]+)")


def parse_number(value: str) -> int:
    return int(value, 0)


def parse_log(content: str) -> dict[str, object]:
    samples: list[dict[str, object]] = []
    for line in content.splitlines():
        if not line.startswith(PERF_PREFIX):
            continue
        fields = {name: value for name, value in TOKEN.findall(line)}
        missing = REQUIRED_FIELDS.difference(fields)
        if missing:
            raise ValueError(f"performance sample is missing fields: {sorted(missing)}")
        sample: dict[str, object] = {
            "region": fields["region"],
            "operation": fields["op"],
            "words": parse_number(fields["words"]),
            "checksum": int(fields["checksum"], 16),
            "cycles": parse_number(fields["cycles"]),
        }
        for counter in sorted(
            REQUIRED_FIELDS - {"region", "op", "words", "checksum", "cycles"}
        ):
            sample[counter] = parse_number(fields[counter])
        samples.append(sample)
    passed = PASS_MARKER in content
    failure_marker = any(line.startswith(FAIL_PREFIX) for line in content.splitlines())
    return {
        "schema_version": 1,
        "status": "passed" if passed and samples and not failure_marker else "failed",
        "failure_marker": failure_marker,
        "pass_marker": passed,
        "samples": samples,
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
        print("performance benchmark did not emit a complete passing report", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
