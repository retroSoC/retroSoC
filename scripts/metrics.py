#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import re
import statistics
import sys
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from scripts.setup_helpers import atomic_write  # noqa: E402


AREA_RE = re.compile(r"Chip area for top module[^:]*:\s*([0-9.eE+-]+)")
HIERARCHY_RE = re.compile(r"^\s*(\d+)\s+[0-9.eE+-]+\s+retrosoc_asic\s*$", re.MULTILINE)


def collect(args: argparse.Namespace) -> int:
    root = args.variant_root.resolve()
    metrics: dict[str, Any] = {
        "schema_version": 1,
        "policy": "observe",
        "firmware": {},
        "synthesis": {},
        "timing": {},
        "flows": {},
    }
    for binary in sorted((root / "sw").glob("*.bin")):
        metrics["firmware"][binary.name] = {"bytes": binary.stat().st_size}

    area_json = root / "syn/yosys/rpt/retrosoc_asic_area.json"
    area_report = root / "syn/yosys/rpt/retrosoc_asic_area.rpt"
    if area_json.is_file():
        design = json.loads(area_json.read_text(encoding="utf-8"))["design"]
        metrics["synthesis"]["top_area"] = float(design["area"])
        metrics["synthesis"]["top_cells"] = int(design["num_cells"])
    elif area_report.is_file():
        text = area_report.read_text(encoding="utf-8", errors="replace")
        areas = AREA_RE.findall(text)
        hierarchy = HIERARCHY_RE.findall(text)
        if areas:
            metrics["synthesis"]["top_area"] = float(areas[-1])
        if hierarchy:
            metrics["synthesis"]["top_cells"] = int(hierarchy[-1])

    timing_report = root / "sta/opensta/timing_metrics.rpt"
    if timing_report.is_file():
        labels = ("wns_min", "wns_max", "tns_min", "tns_max")
        timing_text = timing_report.read_text(encoding="utf-8", errors="replace")
        for line in timing_text.splitlines():
            label, separator, value = line.partition("=")
            numbers = re.findall(r"[-+]?(?:\d+\.\d+|\d+)", value)
            if separator and label in labels and numbers:
                metrics["timing"][label] = float(numbers[-1])
        if not metrics["timing"]:
            values = [
                float(value)
                for value in re.findall(r"[-+]?(?:\d+\.\d+|\d+)", timing_text)
            ]
            metrics["timing"].update(dict(zip(labels, values[-4:])))

    for result in sorted(root.glob("**/result*.json")):
        try:
            data = json.loads(result.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            continue
        metrics["flows"][str(result.relative_to(root))] = {
            "status": data.get("status"),
            "duration_seconds": data.get("duration_seconds"),
        }
    atomic_write(args.output, json.dumps(metrics, indent=2, sort_keys=True) + "\n")
    print(f"metrics: {args.output.resolve()}")
    return 0


def numeric_values(value: Any, prefix: str = "") -> dict[str, float]:
    output: dict[str, float] = {}
    if isinstance(value, dict):
        for key, child in value.items():
            path = f"{prefix}.{key}" if prefix else key
            output.update(numeric_values(child, path))
    elif isinstance(value, (int, float)) and not isinstance(value, bool):
        output[prefix] = float(value)
    return output


def baseline(args: argparse.Namespace) -> int:
    if len(args.input) != 10:
        raise SystemExit("exactly 10 --input metrics files are required")
    samples = [numeric_values(json.loads(path.read_text(encoding="utf-8"))) for path in args.input]
    common = set.intersection(*(set(sample) for sample in samples))
    medians = {key: statistics.median(sample[key] for sample in samples) for key in sorted(common)}
    data = {"schema_version": 1, "sample_count": 10, "values": medians}
    atomic_write(args.output, json.dumps(data, indent=2, sort_keys=True) + "\n")
    print(f"metrics baseline: {args.output.resolve()}")
    return 0


def check(args: argparse.Namespace) -> int:
    policy = json.loads(args.policy.read_text(encoding="utf-8"))
    current = numeric_values(json.loads(args.metrics.read_text(encoding="utf-8")))
    mode = policy.get("mode")
    if mode == "observe":
        print("metrics policy: observe")
        return 0
    if mode != "gate":
        raise SystemExit(f"unsupported metrics policy mode: {mode}")
    if args.baseline is None or not args.baseline.is_file():
        raise SystemExit("a metrics baseline is required when policy mode is gate")
    baseline_data = json.loads(args.baseline.read_text(encoding="utf-8"))["values"]
    failures: list[str] = []
    for key, maximum_growth in policy["maximum_growth"].items():
        if key in current and key in baseline_data and current[key] > baseline_data[key] * (1 + maximum_growth):
            failures.append(key)
    wns_key = "timing.wns_max"
    if wns_key in current and wns_key in baseline_data:
        if current[wns_key] < baseline_data[wns_key] - policy["maximum_wns_regression"]:
            failures.append(wns_key)
    print("metrics check: " + ("failed: " + ", ".join(failures) if failures else "passed"))
    return int(bool(failures))


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Collect and compare retroSoC metrics")
    subparsers = parser.add_subparsers(dest="command", required=True)
    collect_parser = subparsers.add_parser("collect")
    collect_parser.add_argument("--variant-root", type=Path, required=True)
    collect_parser.add_argument("--output", type=Path, required=True)
    baseline_parser = subparsers.add_parser("baseline")
    baseline_parser.add_argument("--input", type=Path, action="append", required=True)
    baseline_parser.add_argument("--output", type=Path, required=True)
    check_parser = subparsers.add_parser("check")
    check_parser.add_argument("--metrics", type=Path, required=True)
    check_parser.add_argument("--baseline", type=Path)
    check_parser.add_argument("--policy", type=Path, required=True)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    return {"collect": collect, "baseline": baseline, "check": check}[args.command](args)


if __name__ == "__main__":
    raise SystemExit(main())
