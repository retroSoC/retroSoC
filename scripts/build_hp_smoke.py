#!/usr/bin/env python3
"""Build the minimal hart-1 smoke payload used by HP RTL simulation."""

from __future__ import annotations

import argparse
import subprocess
from pathlib import Path


def build(args: argparse.Namespace) -> None:
    output = args.output.resolve()
    images = output / "images"
    images.mkdir(parents=True, exist_ok=True)
    elf = output / "hp_smoke.elf"
    compiler = f"{args.cross}gcc"
    objcopy = f"{args.cross}objcopy"
    command = [
            compiler,
            "-march=rv32imafdc_zicbom_zicsr_zifencei",
            "-mabi=ilp32d",
            "-nostdlib",
            "-nostartfiles",
            "-ffreestanding",
            "-O3",
            "-Wall",
            "-Wextra",
            "-Werror=implicit-function-declaration",
            "-Werror=return-type",
            "-Wl,--build-id=none",
            f"-Wl,-T,{args.linker.resolve()}",
            "-o",
            str(elf),
            str(args.source.resolve()),
    ]
    for include in args.include:
        command.append(f"-I{include.resolve()}")
    command.extend(str(source.resolve()) for source in args.extra_source)
    command.extend(args.define)
    subprocess.run(command, check=True)
    subprocess.run(
        [objcopy, "-O", "binary", str(elf), str(images / "fw_jump.bin")],
        check=True,
    )
    (images / "retrosoc_hp.dtb").write_bytes(b"SMOK")
    (images / "Image").write_bytes(b"SMOK")
    (images / "rootfs.cpio.gz").write_bytes(b"SMOK")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--linker", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--cross", default="riscv32-unknown-elf-")
    parser.add_argument("--extra-source", type=Path, action="append", default=[])
    parser.add_argument("--include", type=Path, action="append", default=[])
    parser.add_argument("--define", action="append", default=[])
    build(parser.parse_args())


if __name__ == "__main__":
    main()
