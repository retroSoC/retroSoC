from pathlib import Path
from types import SimpleNamespace

import pytest

from scripts.program_xpi_flash import (
    FlashChunk,
    build_gdb_commands,
    parse_symbol_address,
    run,
    split_image,
)

ROOT = Path(__file__).resolve().parents[1]


def test_split_image_preserves_sector_boundaries() -> None:
    chunks = split_image(bytes(range(256)) * 20, 0x0F80)

    assert [(chunk.address, len(chunk.data)) for chunk in chunks] == [
        (0x0F80, 128),
        (0x1000, 4096),
        (0x2000, 896),
    ]
    assert b"".join(chunk.data for chunk in chunks) == bytes(range(256)) * 20


@pytest.mark.parametrize("address,data", [(0, b""), (-1, b"x"), (0x0100_0000, b"x")])
def test_split_image_rejects_invalid_ranges(address: int, data: bytes) -> None:
    with pytest.raises(ValueError):
        split_image(data, address)


def test_parse_staging_symbol() -> None:
    output = "30000100 T main\n30002400 B rs_xpi_flash_staging\n"

    assert parse_symbol_address(output, "rs_xpi_flash_staging") == 0x30002400


def test_gdb_script_loads_sram_buffer_and_checks_each_sector(tmp_path: Path) -> None:
    chunk_path = tmp_path / "chunk.bin"
    chunk_path.write_bytes(b"abc")
    commands = build_gdb_commands(
        tmp_path / "loader.elf",
        "localhost:3333",
        0x30002000,
        [(FlashChunk(0x1234, b"abc"), chunk_path)],
    )

    assert "target extended-remote localhost:3333" in commands
    assert f"restore {chunk_path.resolve()} binary 0x30002000" in commands
    assert "rs_xpi_flash_update(0x00001234, 3)" in commands
    assert "XPI_FLASH_PROGRAM_PASS" in commands


def test_dry_run_requires_persistent_script_path(tmp_path: Path) -> None:
    args = SimpleNamespace(
        execute=False,
        gdb_script=None,
        loader=tmp_path / "loader.elf",
        image=tmp_path / "image.bin",
    )

    with pytest.raises(ValueError, match="--gdb-script"):
        run(args)


def test_jtag_loader_keeps_gdb_entry_points() -> None:
    linker_script = (ROOT / "crt/linker/jtag_sram.lds").read_text(encoding="utf-8")

    assert "KEEP(*(.text.rs_xpi_flash_probe))" in linker_script
    assert "KEEP(*(.text.rs_xpi_flash_update))" in linker_script
    assert "KEEP(*(.bss.rs_xpi_flash_staging))" in linker_script
