"""HP flash bundle and handwritten mailbox ABI tests."""

from __future__ import annotations

import argparse
import ctypes
import importlib.util
import re
import struct
import subprocess
import zlib
from pathlib import Path

import pytest

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
    magic, version, header_size, entry_count, total_size, header_crc, flags, workload = (
        header_values
    )
    assert magic == module.MAGIC
    assert version == module.VERSION
    assert header_size == module.HEADER_SIZE == 128
    assert entry_count == len(module.ARTIFACTS) == 4
    assert total_size == len(image) - module.BUNDLE_OFFSET
    assert flags == module.REQUIRED
    assert workload == 1

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


@pytest.fixture(scope="module")
def loader(tmp_path_factory):
    library = tmp_path_factory.mktemp("hp-loader") / "loader.so"
    subprocess.run(["cc", "-Wall", "-Wextra", "-Werror", "-shared", "-fPIC",
                    str(ROOT / "app/apps/hp_boot/hp_boot_bundle.c"), "-o", str(library)], check=True)
    result = ctypes.CDLL(str(library))
    result.rs_hp_boot_header_valid.argtypes = [ctypes.c_void_p]
    result.rs_hp_boot_header_valid.restype = ctypes.c_bool
    result.rs_hp_boot_message_status.argtypes = [ctypes.c_uint32] * 6
    result.rs_hp_boot_message_status.restype = ctypes.c_uint32
    return result


@pytest.mark.parametrize("workload", ["linux", "smoke", "rtthread"])
def test_v2_loader_accepts_canonical_bundle_and_rejects_bad_headers(tmp_path, loader, workload):
    module = load_packager()
    firmware = tmp_path / "lp.bin"
    firmware.write_bytes(b"LP")
    images = tmp_path / "images"
    images.mkdir()
    for _, name, _, _ in module.artifacts_for(workload):
        (images / name).write_bytes(b"payload")
    output = tmp_path / "bundle.bin"
    module.package(argparse.Namespace(firmware=firmware, images=images, output=output,
                                      manifest=tmp_path / "bundle.json", workload=workload))
    header = output.read_bytes()[module.BUNDLE_OFFSET:module.BUNDLE_OFFSET + 128]
    assert loader.rs_hp_boot_header_valid(ctypes.create_string_buffer(header))
    # Every mutation has a corrected CRC, so structural checks are exercised.
    mutations = [(4, 1), (8, 64), (12, 0), (16, 0xFFFFFFFF), (24, 3), (28, 99),
                 (32, 99), (36, 0x100000), (36, 0xFFFFFFFF), (40, 0x38000004),
                 (44, 0), (44, 0x80001), (52, 3)]
    mutations += [(60, 0x101000)] if workload == "linux" else [(56, 1)]
    for offset, value in mutations:
        changed = bytearray(header)
        struct.pack_into("<I", changed, offset, value)
        struct.pack_into("<I", changed, 20, 0)
        struct.pack_into("<I", changed, 20, zlib.crc32(changed))
        assert not loader.rs_hp_boot_header_valid(ctypes.create_string_buffer(bytes(changed))), (offset, value)
    changed = bytearray(header)
    changed[20] ^= 1
    assert not loader.rs_hp_boot_header_valid(ctypes.create_string_buffer(bytes(changed)))


def test_mailbox_verdict_rejects_bad_codes_arguments_and_sequences(loader):
    status = loader.rs_hp_boot_message_status
    assert status(1, 0x52545401, 1, 1, 0x52545401, 1) == 1
    assert status(2, 0x52545401, 2, 2, 0x52545401, 2) == 1
    assert status(0, 0, 0, 1, 0x52545401, 1) == 0
    assert status(1, 0x52545401, 1, 2, 0x52545401, 2) == 0
    assert status(3, 7, 1, 2, 0x52545401, 2) == 2
    assert status(3, 0, 2, 1, 0x52545401, 1) == 2
    assert status(1, 0x52545401, 2, 1, 0x52545401, 1) == 2
    assert status(2, 0x52545401, 1, 1, 0x52545401, 1) == 2
    assert status(1, 0x4C4E5801, 1, 1, 0x52545401, 1) == 2


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


def test_hp_boot_uses_private_ga2d_mailbox_and_resource_lifecycle() -> None:
    source = (ROOT / "app/apps/hp_boot/main.c").read_text(encoding="utf-8")

    for requirement in (
        "RS_HP_BOOT_READY_EVENT",
        "RS_HP_BOOT_READY_ARG",
        "RS_HP_BOOT_GA2D_START_COMMAND",
        "RS_HP_BOOT_GA2D_PASS_EVENT",
        "RS_HP_BOOT_GA2D_FAIL_EVENT",
        "RS_HP_BOOT_GA2D_CACHE_EVENT",
        "rs_resource_set_owner(RS_RESOURCE_GA2D, RS_RESOURCE_OWNER_HP, false)",
        "rs_resource_set_owner(RS_RESOURCE_GA2D, RS_RESOURCE_OWNER_LP, false)",
        "rs_resource_acknowledge_cache_clean()",
        "rs_hp_boot_wait_message",
        "rs_hp_boot_wait_cache_request",
        "rs_hp_boot_wait_hp_held",
        "HP_GA2D_PASS",
        "HP_GA2D_IDLE",
        "HP_GA2D_CACHE_REQUESTED",
        "HP_GA2D_CACHE_REQUEST",
        "HP_GA2D_CACHE_MESSAGE",
        "HP_GA2D_CACHE_ACK",
        "HP_GA2D_HELD",
        "HP_GA2D_CACHE_CLEAN",
    ):
        assert requirement in source


def test_hp_boot_p5_transfers_npu_resource_and_reports_completion() -> None:
    source = (ROOT / "app/apps/hp_boot/main.c").read_text(encoding="utf-8")
    makefile = (ROOT / "Makefile").read_text(encoding="utf-8")

    for requirement in (
        "rs_resource_set_owner(RS_RESOURCE_NPU, RS_RESOURCE_OWNER_HP, false)",
        "rs_resource_set_owner(RS_RESOURCE_NPU, RS_RESOURCE_OWNER_LP, false)",
        "rs_hp_boot_wait_npu_idle",
        "HP_NPU_PASS",
        "npu-p5-hp-sim",
    ):
        assert requirement in source or requirement in makefile
