#!/usr/bin/env python3
"""Validate and summarize the isolated apb4_ga2d block synthesis evidence.

Reads the reports produced by the GA2D-scoped yosys run (physical/smoke/syn/
yosys/ga2d_block.mk), fails loudly on inferred latches or non-PDK
(black-box/unmapped) cells, and writes ga2d_block_summary.json next to the
area report for the Phase 6 evidence section.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from scripts.setup_helpers import atomic_write  # noqa: E402

FIFO_INSTANCES = ("u_foreground_fifo", "u_background_fifo", "u_output_fifo")
LATCH_INFERRED = re.compile(r"latch inferred", re.IGNORECASE)
CHECK_PROBLEMS = re.compile(r"found and reported (\d+) problems?", re.IGNORECASE)
# Generic (pre-technology-mapping) cell types that must never survive the
# coarse synthesis passes: unresolved memories and inferred latches.
GENERIC_FORBIDDEN = ("$mem", "$dlatch", "$_dlatch")


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--log", type=Path, required=True, help="yosys flow log")
    parser.add_argument("--check-report", type=Path, required=True, help="yosys check report")
    parser.add_argument("--area-json", type=Path, required=True, help="yosys stat -json report")
    parser.add_argument(
        "--registers-report", type=Path, required=True, help="pre-map DFF selection report"
    )
    parser.add_argument(
        "--generic-report", type=Path, required=True, help="pre-flatten cmos stat report"
    )
    parser.add_argument("--top", required=True, help="synthesized top module name")
    parser.add_argument("--pdk", required=True)
    parser.add_argument("--recipe", required=True)
    parser.add_argument("--period-ps", type=int, required=True)
    parser.add_argument(
        "--cell-prefix",
        required=True,
        help="required prefix for every mapped cell type (PDK standard cells)",
    )
    parser.add_argument("--output", type=Path, required=True)
    return parser.parse_args(argv)


def read_text(path: Path, label: str) -> str:
    try:
        return path.read_text(encoding="utf-8", errors="replace")
    except OSError as error:
        raise ValueError(f"cannot read {label}: {error}") from error


def load_area(path: Path, top: str) -> dict:
    try:
        document = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ValueError(f"cannot parse area report {path}: {error}") from error
    modules = document.get("modules")
    if not isinstance(modules, dict):
        raise ValueError(f"area report {path} has no modules object")
    entry = modules.get(top)
    if entry is None:
        # yosys writes Verilog-escaped module names with a leading backslash.
        entry = modules.get(f"\\{top}")
    if not isinstance(entry, dict):
        raise ValueError(f"area report {path} has no modules entry for top {top}")
    if not isinstance(entry.get("num_cells"), int):
        raise ValueError(f"area report {path} is missing num_cells for top {top}")
    if not isinstance(entry.get("num_cells_by_type"), dict):
        raise ValueError(f"area report {path} is missing num_cells_by_type for top {top}")
    if not isinstance(entry.get("area"), (int, float)):
        raise ValueError(f"area report {path} is missing area for top {top}")
    return entry


def classify_cells(
    cells_by_type: dict, cell_prefix: str
) -> tuple[dict[str, int], dict[str, int], dict[str, int]]:
    dff_types: dict[str, int] = {}
    latch_types: dict[str, int] = {}
    foreign_types: dict[str, int] = {}
    for cell_type, count in sorted(cells_by_type.items()):
        if not isinstance(count, int) or count < 0:
            raise ValueError(f"invalid cell count for {cell_type}: {count}")
        if not cell_type.startswith(cell_prefix):
            foreign_types[cell_type] = count
        elif re.match(rf"^{re.escape(cell_prefix)}dl[hl]", cell_type):
            # IHP130 level-sensitive latches: dlhq/dlhr/dlhrq/dllr/dllrq. The
            # dlygate* delay cells share only the "dl" prefix and stay excluded.
            latch_types[cell_type] = count
        elif re.match(rf"^{re.escape(cell_prefix)}s?df", cell_type):
            dff_types[cell_type] = count
    return dff_types, latch_types, foreign_types


def count_register_lines(report: str) -> tuple[int, dict[str, dict[str, int]]]:
    lines = [line.strip() for line in report.splitlines() if line.strip()]
    fifo: dict[str, dict[str, int]] = {}
    for instance in FIFO_INSTANCES:
        instance_lines = [line for line in lines if instance in line]
        storage_lines = [line for line in instance_lines if "r_storage" in line]
        fifo[instance] = {
            "dff_cells": len(instance_lines),
            "storage_dff_cells": len(storage_lines),
        }
    return len(lines), fifo


def parse_generic_fifo(report: str) -> dict[str, dict[str, int]]:
    # The slang frontend specializes parameterized modules per instance, so
    # each GA2D FIFO appears as its own section: fifo$<hierarchical path>.
    sections = re.split(r"^===\s+", report, flags=re.MULTILINE)
    mapping: dict[str, dict[str, int]] = {}
    for instance in FIFO_INSTANCES:
        body = next(
            (
                section
                for section in sections
                if section.startswith("fifo$") and instance in section.split("===", 1)[0]
            ),
            None,
        )
        if body is None:
            raise ValueError(f"generic report has no fifo section for {instance}")
        cells = re.search(r"^\s+(\d+)\s+cells\s*$", body, re.MULTILINE)
        dffe_bits = {
            name: int(match.group(1))
            for name in ("$_DFFE_PP_", "$_DFFE_PN0P_")
            if (match := re.search(rf"^\s+(\d+)\s+{re.escape(name)}\s*$", body, re.MULTILINE))
            is not None
        }
        if cells is None or not dffe_bits:
            raise ValueError(f"generic report fifo section for {instance} lacks DFF counts")
        mapping[instance] = {
            "cells": int(cells.group(1)),
            "dff_cells": sum(dffe_bits.values()),
            "storage_dff_cells": dffe_bits.get("$_DFFE_PP_", 0),
        }
    return mapping


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    problems: list[str] = []
    try:
        log_text = read_text(args.log, "yosys log")
        check_text = read_text(args.check_report, "check report")
        registers_text = read_text(args.registers_report, "registers report")
        generic_text = read_text(args.generic_report, "generic report")
        area = load_area(args.area_json, args.top)
    except ValueError as error:
        print(f"ga2d_block_summary: {error}", file=sys.stderr)
        return 1

    inferred_latches = LATCH_INFERRED.findall(log_text)
    if inferred_latches:
        problems.append(f"yosys log reports {len(inferred_latches)} inferred-latch message(s)")

    problems_match = CHECK_PROBLEMS.search(check_text)
    check_problems = int(problems_match.group(1)) if problems_match else -1
    if problems_match is None:
        problems.append("check report does not end with a problem count")
    elif check_problems != 0:
        problems.append(f"yosys check reported {check_problems} problem(s)")

    generic_forbidden = sorted({token for token in GENERIC_FORBIDDEN if token in generic_text})
    if generic_forbidden:
        problems.append(
            "generic report retains forbidden cell type(s): " + ", ".join(generic_forbidden)
        )

    cells_by_type = area["num_cells_by_type"]
    dff_types, latch_types, foreign_types = classify_cells(cells_by_type, args.cell_prefix)
    if latch_types:
        problems.append(f"mapped latch cell(s): {latch_types}")
    if foreign_types:
        problems.append(f"black-box or unmapped cell type(s): {foreign_types}")

    pre_map_dff, fifo = count_register_lines(registers_text)
    try:
        generic_fifo = parse_generic_fifo(generic_text)
    except ValueError as error:
        problems.append(str(error))
        generic_fifo = {}
    for instance, counts in fifo.items():
        if counts["dff_cells"] == 0:
            problems.append(f"no DFF cells found for FIFO instance {instance}")
    for instance, counts in generic_fifo.items():
        # The Common fifo storage is expected to map to 32 x 64 DFF bits.
        if counts["storage_dff_cells"] != 32 * 64:
            problems.append(
                f"FIFO instance {instance} storage mapped to "
                f"{counts['storage_dff_cells']} DFF bit(s), expected {32 * 64}"
            )

    if problems:
        for problem in problems:
            print(f"ga2d_block_summary: FAIL: {problem}", file=sys.stderr)
        return 1

    fifo_mapping = {
        instance: {
            "pre_map_dff_cells": counts["dff_cells"],
            "pre_map_storage_dff_cells": counts["storage_dff_cells"],
            **generic_fifo.get(instance, {}),
        }
        for instance, counts in fifo.items()
    }
    summary = {
        "top": args.top,
        "pdk": args.pdk,
        "synth_recipe": args.recipe,
        "target_period_ps": args.period_ps,
        "total_cells": area["num_cells"],
        "area": area["area"],
        "dff_count": sum(dff_types.values()),
        "dff_cells_by_type": dff_types,
        "pre_map_dff_count": pre_map_dff,
        "latch_count": sum(latch_types.values()),
        "black_box_cells": sum(foreign_types.values()),
        "check_problems": check_problems,
        "fifo_mapping": fifo_mapping,
    }
    atomic_write(args.output, json.dumps(summary, indent=2, sort_keys=True) + "\n")
    print(
        "ga2d_block_summary: PASS: "
        f"cells={summary['total_cells']} area={summary['area']} "
        f"dff={summary['dff_count']} latches=0 black_boxes=0 "
        f"fifo_dff={ {name: counts['dff_cells'] for name, counts in fifo.items()} }"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
