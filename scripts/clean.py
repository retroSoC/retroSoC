#!/usr/bin/env python3

from __future__ import annotations

import argparse
import shutil
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Remove retroSoC generated output")
    parser.add_argument("--root", type=Path, required=True)
    return parser.parse_args()


def remove(root: Path, relative: str) -> None:
    target = (root / relative).resolve()
    target.relative_to(root)
    if target.is_dir() and not target.is_symlink():
        shutil.rmtree(target)
    elif target.exists() or target.is_symlink():
        target.unlink()
    print(f"cleaned {target}")


def main() -> int:
    root = parse_args().root.resolve()
    if not (root / "Makefile").is_file() or not (root / ".git").exists():
        raise SystemExit(f"not a retroSoC repository root: {root}")
    generated = (
        ".sw_build",
        "rtl/mini/.generated_fl",
        "rtl/mini/.iverilog_build",
        "rtl/mini/.verilator_build",
        "rtl/mini/.vcs_build",
        "syn/yosys/.synth_build",
        "sta/opensta/retrosoc_sta.log",
        "export/rtl",
    )
    for relative in generated:
        remove(root, relative)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
