#!/usr/bin/env python3
"""Build the minimal hart-1 smoke payload used by HP RTL simulation."""

from __future__ import annotations

import argparse
import subprocess
from pathlib import Path

try:
    from scripts.hp_tools import require_rv64_elf
except ModuleNotFoundError:
    from hp_tools import require_rv64_elf


def build(args: argparse.Namespace) -> None:
    output = args.output.resolve()
    images = output / "images"
    images.mkdir(parents=True, exist_ok=True)
    elf = output / "hp_smoke.elf"
    compiler = f"{args.cross}gcc"
    objcopy = f"{args.cross}objcopy"
    subprocess.run(
        [
            compiler,
            "-march=rv64imafdc_zicbom_zicsr_zifencei",
            "-mabi=lp64d",
            "-nostdlib",
            "-nostartfiles",
            "-Wl,--build-id=none",
            f"-Wl,-T,{args.linker.resolve()}",
            "-o",
            str(elf),
            str(args.source.resolve()),
        ],
        check=True,
    )
    require_rv64_elf(elf)
    subprocess.run(
        [objcopy, "-O", "binary", str(elf), str(images / "hp_smoke.bin")],
        check=True,
    )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--linker", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--cross", default="riscv64-unknown-elf-")
    build(parser.parse_args())


if __name__ == "__main__":
    main()
