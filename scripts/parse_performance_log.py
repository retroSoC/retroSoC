#!/usr/bin/env python3
"""Parse reproducible SoC performance benchmark output into structured JSON."""

from __future__ import annotations

import argparse
import json
import re
import sys
from decimal import Decimal, ROUND_HALF_UP
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
    "apb4_periph_wait",
    "sdram_wait",
    "psram_wait",
    "flash_wait",
    "dma_wait",
    "workload_bytes",
    "pixels",
    "jobs",
    "cpu_cycles",
    "cpu_hz",
    "pclk_hz",
    "ga2d_features",
    "ga2d_limits",
    "ga2d_formats",
    "ga2d_cycles",
    "ga2d_read_bytes",
    "ga2d_write_bytes",
}
OPTIONAL_FIELDS = ("width", "height", "pitch")
TOKEN = re.compile(r"([a-z0-9_]+)=([^\s]+)")
QUANTUM = Decimal("0.001")


def parse_number(value: str) -> int:
    return int(value, 0)


def ratio_string(numerator: int, denominator: int) -> str:
    value = (Decimal(numerator) / Decimal(denominator)).quantize(
        QUANTUM, rounding=ROUND_HALF_UP
    )
    return str(value)


def derived_ga2d_metrics(fields: dict[str, str]) -> dict[str, str]:
    ga2d_cycles = parse_number(fields["ga2d_cycles"])
    cpu_cycles = parse_number(fields["cpu_cycles"])
    pixels = parse_number(fields["pixels"])
    workload_bytes = parse_number(fields["workload_bytes"])
    cpu_hz = parse_number(fields["cpu_hz"])
    pclk_hz = parse_number(fields["pclk_hz"])
    derived: dict[str, str] = {}
    if ga2d_cycles <= 0 or pclk_hz <= 0:
        return derived
    derived["ga2d_job_latency_us"] = ratio_string(ga2d_cycles * 1_000_000, pclk_hz)
    derived["ga2d_effective_mb_per_s"] = ratio_string(
        workload_bytes * pclk_hz, ga2d_cycles * 1_000_000
    )
    if pixels > 0:
        derived["ga2d_pixels_per_s"] = ratio_string(pixels * pclk_hz, ga2d_cycles)
    if cpu_hz > 0:
        derived["lp_cpu_us"] = ratio_string(cpu_cycles * 1_000_000, cpu_hz)
        if pixels > 0:
            derived["lp_cpu_cycles_per_pixel"] = ratio_string(cpu_cycles, pixels)
    return derived


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
            "workload_bytes": parse_number(fields["workload_bytes"]),
            "pixels": parse_number(fields["pixels"]),
            "jobs": parse_number(fields["jobs"]),
            "cpu_cycles": parse_number(fields["cpu_cycles"]),
            "ga2d_cycles": parse_number(fields["ga2d_cycles"]),
            "ga2d_read_bytes": parse_number(fields["ga2d_read_bytes"]),
            "ga2d_write_bytes": parse_number(fields["ga2d_write_bytes"]),
            "configuration": {
                "cpu_hz": parse_number(fields["cpu_hz"]),
                "pclk_hz": parse_number(fields["pclk_hz"]),
                "ga2d_features": parse_number(fields["ga2d_features"]),
                "ga2d_limits": parse_number(fields["ga2d_limits"]),
                "ga2d_formats": parse_number(fields["ga2d_formats"]),
            },
        }
        for optional in OPTIONAL_FIELDS:
            if optional in fields:
                sample[optional] = parse_number(fields[optional])
        derived = derived_ga2d_metrics(fields)
        if derived:
            sample["derived"] = derived
        for counter in sorted(
            REQUIRED_FIELDS
            - {
                "region",
                "op",
                "words",
                "checksum",
                "cycles",
                "workload_bytes",
                "pixels",
                "jobs",
                "cpu_cycles",
                "cpu_hz",
                "pclk_hz",
                "ga2d_features",
                "ga2d_limits",
                "ga2d_formats",
                "ga2d_cycles",
                "ga2d_read_bytes",
                "ga2d_write_bytes",
            }
        ):
            sample[counter] = parse_number(fields[counter])
        samples.append(sample)
    passed = PASS_MARKER in content
    failure_marker = any(line.startswith(FAIL_PREFIX) for line in content.splitlines())
    return {
        "schema_version": 3,
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
