#!/usr/bin/env python3
"""Generate a deterministic SymbiYosys configuration for one protocol proof."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))

from scripts.setup_helpers import atomic_write  # noqa: E402


def render(
    top: str,
    design: Path,
    properties: Path,
    solver: str,
    mode: str,
    depth: int,
    vcd: bool = True,
    skip: int | None = None,
) -> str:
    options = ["[options]", f"mode {mode}", f"depth {depth}"]
    if skip is not None:
        options.append(f"skip {skip}")
    if not vcd:
        options.append("vcd off")
    return "\n".join(
        tuple(options)
        + (
            "",
            "[engines]",
            f"smtbmc --presat --nounroll {solver}",
            "",
            "[script]",
            "read_verilog -formal -sv design.v",
            "read_verilog -formal -sv properties.v",
            f"prep -top {top}",
            "async2sync",
            "dffunmap",
            "opt_clean",
            "",
            "[files]",
            f"design.v {design.resolve()}",
            f"properties.v {properties.resolve()}",
            "",
        )
    )


def positive_int(value: str) -> int:
    parsed = int(value)
    if parsed <= 0:
        raise argparse.ArgumentTypeError("value must be positive")
    return parsed


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--top", required=True)
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--properties", type=Path, required=True)
    parser.add_argument("--solver", required=True)
    parser.add_argument("--mode", choices=("prove", "bmc", "cover"), required=True)
    parser.add_argument("--depth", type=positive_int, required=True)
    parser.add_argument("--no-vcd", action="store_false", dest="vcd")
    parser.add_argument("--skip", type=positive_int)
    parser.add_argument("--output", type=Path, required=True)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    atomic_write(
        args.output.resolve(),
        render(
            args.top,
            args.input,
            args.properties,
            args.solver,
            args.mode,
            args.depth,
            args.vcd,
            args.skip,
        ),
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
