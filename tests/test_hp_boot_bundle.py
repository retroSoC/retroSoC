"""HP flash bundle and handwritten mailbox ABI tests."""

from __future__ import annotations

import argparse
import importlib.util
import re
import struct
import zlib
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PACKAGER = ROOT / "scripts/package_hp_boot.py"
MAILBOX_RTL = ROOT / "rtl/ip/peripheral/hp_mailbox_define.svh"
MAILBOX_C = ROOT / "crt/src/hal/hp_mailbox.c"


def load_packager():
    spec = importlib.util.spec_from_file_location("package_hp_boot", PACKAGER)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_hp_boot_bundle_layout_crc_and_payloads(tmp_path: Path) -> None:
    module = load_packager()
    firmware = tmp_path / "lp.bin"
    firmware.write_bytes(b"LP" * 32)
    images = tmp_path / "images"
    images.mkdir()
    expected: dict[str, bytes] = {}
    for index, (_, name, _, _) in enumerate(module.ARTIFACTS, start=1):
        expected[name] = bytes([index]) * (31 + index)
        (images / name).write_bytes(expected[name])

    output = tmp_path / "boot.bin"
    manifest = tmp_path / "boot.json"
    module.package(
        argparse.Namespace(
            firmware=firmware,
            images=images,
            output=output,
            manifest=manifest,
        )
    )

    image = output.read_bytes()
    header_values = module.HEADER.unpack_from(image, module.BUNDLE_OFFSET)
    magic, version, header_size, entry_count, total_size, header_crc, flags, reserved = (
        header_values
    )
    assert magic == module.MAGIC
    assert version == module.VERSION
    assert header_size == module.HEADER_SIZE == 128
    assert entry_count == len(module.ARTIFACTS) == 4
    assert total_size == len(image) - module.BUNDLE_OFFSET
    assert flags == module.REQUIRED
    assert reserved == 0

    header = bytearray(image[module.BUNDLE_OFFSET : module.BUNDLE_OFFSET + header_size])
    struct.pack_into("<I", header, 20, 0)
    assert zlib.crc32(header) & 0xFFFFFFFF == header_crc
    for index, (_, name, load_address, _) in enumerate(module.ARTIFACTS):
        entry_offset = module.BUNDLE_OFFSET + module.HEADER.size + index * module.ENTRY.size
        kind, flash_offset, entry_address, size, crc32, entry_flags = module.ENTRY.unpack_from(
            image, entry_offset
        )
        assert kind == index + 1
        assert entry_address == load_address
        assert image[flash_offset : flash_offset + size] == expected[name]
        assert zlib.crc32(expected[name]) & 0xFFFFFFFF == crc32
        assert entry_flags == module.REQUIRED


def test_mailbox_c_offsets_match_handwritten_rtl() -> None:
    rtl_pattern = re.compile(r"^`define\s+APB4_HP_MAILBOX__(\w+)\s+12'h([0-9A-Fa-f]+)$")
    c_pattern = re.compile(
        r"^#define\s+RS_HP_MAILBOX_(\w+)_OFFSET\s+UINT32_C\(0x([0-9A-Fa-f]+)\)$"
    )
    rtl = {
        match.group(1): int(match.group(2), 16)
        for line in MAILBOX_RTL.read_text(encoding="utf-8").splitlines()
        if (match := rtl_pattern.match(line)) is not None
    }
    c = {
        match.group(1): int(match.group(2), 16)
        for line in MAILBOX_C.read_text(encoding="utf-8").splitlines()
        if (match := c_pattern.match(line)) is not None
    }
    assert c == {
        name: rtl[name]
        for name in (
            "IP_VERSION",
            "CAPABILITY",
            "LP_COMMAND",
            "LP_ARG0",
            "LP_SEQUENCE",
            "LP_DOORBELL",
            "HP_EVENT",
            "HP_ARG0",
            "HP_SEQUENCE",
            "LP_INTR_STATE",
            "LP_INTR_ENABLE",
        )
    }
