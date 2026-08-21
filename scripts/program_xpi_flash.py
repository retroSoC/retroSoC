#!/usr/bin/env python3
"""Program NOR through the SRAM XPI loader and an existing OpenOCD GDB server."""

from __future__ import annotations

import argparse
import json
import subprocess
import tempfile
from dataclasses import dataclass
from pathlib import Path

FLASH_SIZE = 0x0100_0000
SECTOR_SIZE = 4096
SUCCESS_MARKER = "XPI_FLASH_PROGRAM_PASS"


@dataclass(frozen=True)
class FlashChunk:
    address: int
    data: bytes


def split_image(data: bytes, address: int) -> list[FlashChunk]:
    """Split a payload so every loader call stays within one erase sector."""
    if not data:
        raise ValueError("image is empty")
    if address < 0 or address >= FLASH_SIZE or len(data) > FLASH_SIZE - address:
        raise ValueError("image range is outside the 16 MiB NOR device")

    chunks: list[FlashChunk] = []
    offset = 0
    while offset < len(data):
        chunk_address = address + offset
        sector_remaining = SECTOR_SIZE - (chunk_address % SECTOR_SIZE)
        chunk_data = data[offset : offset + sector_remaining]
        chunks.append(FlashChunk(chunk_address, chunk_data))
        offset += len(chunk_data)
    return chunks


def parse_symbol_address(nm_output: str, symbol: str) -> int:
    for line in nm_output.splitlines():
        fields = line.split()
        if len(fields) >= 3 and fields[-1] == symbol:
            return int(fields[0], 16)
    raise ValueError(f"loader symbol not found: {symbol}")


def build_gdb_commands(
    loader: Path, target: str, staging_address: int, chunks: list[tuple[FlashChunk, Path]]
) -> str:
    lines = [
        "set confirm off",
        "set pagination off",
        "set remotetimeout 60",
        "set architecture riscv:rv32",
        f"file {loader.resolve()}",
        f"target extended-remote {target}",
        "monitor halt",
        "load",
        "break main",
        "continue",
        "set $result = (int)rs_xpi_flash_probe()",
        'if $result != 0',
        '  printf "XPI flash probe failed: %d\\n", $result',
        "  quit 1",
        "end",
    ]
    for chunk, chunk_path in chunks:
        lines.extend(
            (
                f"restore {chunk_path.resolve()} binary 0x{staging_address:08x}",
                f"set $result = (int)rs_xpi_flash_update(0x{chunk.address:08x}, {len(chunk.data)})",
                "if $result != 0",
                (
                    f'  printf "XPI flash update failed at 0x{chunk.address:08x}: '
                    '%d\\n", $result'
                ),
                "  quit 1",
                "end",
            )
        )
    lines.extend((f'printf "{SUCCESS_MARKER}\\n"', "detach", "quit", ""))
    return "\n".join(lines)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--loader", required=True, type=Path, help="SRAM loader ELF")
    parser.add_argument("--image", required=True, type=Path, help="raw binary image")
    parser.add_argument("--address", type=lambda value: int(value, 0), default=0)
    parser.add_argument("--target", default="127.0.0.1:3333", help="OpenOCD GDB endpoint")
    parser.add_argument("--gdb", default="riscv32-unknown-elf-gdb")
    parser.add_argument("--nm", default="riscv32-unknown-elf-nm")
    parser.add_argument("--gdb-script", type=Path, help="keep the generated GDB script")
    parser.add_argument("--result", type=Path, help="write a machine-readable result")
    parser.add_argument(
        "--execute", action="store_true", help="perform the destructive erase/program operation"
    )
    return parser.parse_args()


def run(args: argparse.Namespace) -> int:
    if not args.execute and args.gdb_script is None:
        raise ValueError("--gdb-script is required when --execute is not specified")

    loader = args.loader.resolve()
    image = args.image.resolve()
    if not loader.is_file():
        raise FileNotFoundError(f"loader ELF not found: {loader}")
    if not image.is_file():
        raise FileNotFoundError(f"image not found: {image}")

    chunks = split_image(image.read_bytes(), args.address)
    nm_result = subprocess.run(
        [args.nm, "-g", "--defined-only", str(loader)],
        check=True,
        capture_output=True,
        text=True,
    )
    staging_address = parse_symbol_address(nm_result.stdout, "rs_xpi_flash_staging")

    if args.gdb_script is not None:
        work_dir = args.gdb_script.resolve().with_suffix(".chunks")
        work_dir.mkdir(parents=True, exist_ok=True)
        temporary = None
    else:
        temporary = tempfile.TemporaryDirectory(prefix="retrosoc-xpi-flash-")
        work_dir = Path(temporary.name)

    chunk_files: list[tuple[FlashChunk, Path]] = []
    for index, chunk in enumerate(chunks):
        chunk_path = work_dir / f"chunk-{index:04d}.bin"
        chunk_path.write_bytes(chunk.data)
        chunk_files.append((chunk, chunk_path))
    commands = build_gdb_commands(loader, args.target, staging_address, chunk_files)
    script_path = args.gdb_script.resolve() if args.gdb_script is not None else work_dir / "flash.gdb"
    script_path.parent.mkdir(parents=True, exist_ok=True)
    script_path.write_text(commands, encoding="utf-8")

    return_code = 0
    if args.execute:
        result = subprocess.run(
            [args.gdb, "--batch", "--nx", "--quiet", "--command", str(script_path)],
            check=False,
            capture_output=True,
            text=True,
        )
        print(result.stdout, end="")
        if result.stderr:
            print(result.stderr, end="")
        return_code = result.returncode
        if return_code == 0 and SUCCESS_MARKER not in result.stdout:
            return_code = 1
    else:
        print(f"generated {script_path}; pass --execute to program the device")

    if args.result is not None:
        args.result.parent.mkdir(parents=True, exist_ok=True)
        args.result.write_text(
            json.dumps(
                {
                    "tool": "xpi-jtag-flash",
                    "passed": return_code == 0,
                    "executed": args.execute,
                    "address": args.address,
                    "bytes": image.stat().st_size,
                    "sectors": len(chunks),
                    "loader": str(loader),
                    "image": str(image),
                    "gdb_script": str(script_path),
                },
                indent=2,
            )
            + "\n",
            encoding="utf-8",
        )
    if temporary is not None:
        temporary.cleanup()
    return return_code


def main() -> int:
    return run(parse_args())


if __name__ == "__main__":
    raise SystemExit(main())
