#!/usr/bin/env python3
"""Build the hart-1 APU ownership-evidence payload used by HP RTL simulation."""

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
    elf = output / "hp_apu.elf"
    compiler = f"{args.cross}gcc"
    objcopy = f"{args.cross}objcopy"
    includes = [f"-I{path.resolve()}" for path in args.include]
    source_dir = args.source_dir.resolve()
    subprocess.run(
        [
            compiler,
            "-march=rv64imafdc_zicsr_zifencei",
            "-mabi=lp64d",
            "-nostdlib",
            "-nostartfiles",
            "-ffreestanding",
            "-O2",
            "-Wall",
            "-Wextra",
            "-Wl,--build-id=none",
            f"-Wl,-T,{source_dir / 'linker.ld'}",
            *includes,
            "-o",
            str(elf),
            str(source_dir / "start.S"),
            str(source_dir / "main.c"),
        ],
        check=True,
    )
    require_rv64_elf(elf)
    subprocess.run(
        [objcopy, "-O", "binary", str(elf), str(images / "fw_jump.bin")],
        check=True,
    )
    (images / "retrosoc_hp.dtb").write_bytes(b"SMOK")
    (images / "Image").write_bytes(b"SMOK")
    (images / "rootfs.cpio").write_bytes(b"SMOK")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-dir", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--cross", default="riscv64-unknown-elf-")
    parser.add_argument("--include", type=Path, action="append", default=[])
    build(parser.parse_args())


if __name__ == "__main__":
    main()
