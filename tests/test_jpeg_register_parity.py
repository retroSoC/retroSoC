"""Keep the handwritten JPEG RTL and SDK register constants synchronized."""

from __future__ import annotations

import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
RTL_DEFINE = ROOT / "rtl/ip/multimedia/jpeg_define.svh"
C_DEFINE = ROOT / "crt/include/retrosoc/hal/jpeg_regs.h"


def _rtl_values() -> dict[str, int]:
    values: dict[str, int] = {}
    pattern = re.compile(r"^`define\s+(\w+)\s+((?:\d+)'[hHdD][0-9a-fA-F]+|\d+)\s*$")
    for line in RTL_DEFINE.read_text(encoding="utf-8").splitlines():
        match = pattern.match(line)
        if match is None:
            continue
        name, literal = match.groups()
        if "'" in literal:
            _, value = literal.split("'", maxsplit=1)
            base = 16 if value[0].lower() == "h" else 10
            values[name] = int(value[1:], base)
        else:
            values[name] = int(literal, 10)
    return values


def _c_values() -> dict[str, int]:
    values: dict[str, int] = {}
    pattern = re.compile(r"^#define\s+(\w+)\s+(?:UINT32_C\((0x[0-9a-fA-F]+)\)|(\d+)U)\s*$")
    for line in C_DEFINE.read_text(encoding="utf-8").splitlines():
        match = pattern.match(line)
        if match is None:
            continue
        name, hexadecimal, decimal = match.groups()
        values[name] = int(hexadecimal if hexadecimal is not None else decimal, 0)
    return values


def test_jpeg_register_offsets_match_rtl() -> None:
    rtl = _rtl_values()
    c = _c_values()
    rtl_offsets = {name: value for name, value in rtl.items() if name.startswith("APB4_JPEG__")}
    excluded = {
        name
        for name in rtl_offsets
        if any(
            marker in name
            for marker in (
                "COMMAND_START",
                "COMMAND_ABORT",
                "COMMAND_SOFT_RESET",
                "COMMAND_RING_KICK",
                "STATUS_BUSY",
                "STATUS_RING_ACTIVE",
                "STATUS_ENCODE",
                "STATUS_IDLE",
                "IRQ_JOB_DONE",
                "IRQ_RING_EVENT",
                "IRQ_HEADER_READY",
                "IRQ_ABORT_DONE",
                "IRQ_ERROR",
                "JOB_CONFIG_",
                    "DESCRIPTOR_",
                    "RING_CONTROL_",
                    "RING_STATUS_",
                    "TABLE_COMMAND_",
            )
        )
    }
    for rtl_name, rtl_value in rtl_offsets.items():
        if rtl_name in excluded:
            continue
        c_name = rtl_name.replace("APB4_JPEG__", "RS_JPEG_REG_")
        assert c[c_name] == rtl_value, f"{rtl_name} != {c_name}"


def test_jpeg_register_fields_match_rtl() -> None:
    rtl = _rtl_values()
    c = _c_values()
    bit_mapping = {
        "APB4_JPEG__COMMAND_START": "RS_JPEG_COMMAND_START",
        "APB4_JPEG__COMMAND_ABORT": "RS_JPEG_COMMAND_ABORT",
        "APB4_JPEG__COMMAND_SOFT_RESET": "RS_JPEG_COMMAND_SOFT_RESET",
        "APB4_JPEG__COMMAND_RING_KICK": "RS_JPEG_COMMAND_RING_KICK",
        "APB4_JPEG__IRQ_JOB_DONE": "RS_JPEG_IRQ_JOB_DONE",
        "APB4_JPEG__IRQ_RING_EVENT": "RS_JPEG_IRQ_RING_EVENT",
        "APB4_JPEG__IRQ_HEADER_READY": "RS_JPEG_IRQ_HEADER_READY",
        "APB4_JPEG__IRQ_ABORT_DONE": "RS_JPEG_IRQ_ABORT_DONE",
        "APB4_JPEG__IRQ_ERROR": "RS_JPEG_IRQ_ERROR",
        "APB4_JPEG__DESCRIPTOR_OWN": "RS_JPEG_DESCRIPTOR_OWN",
        "APB4_JPEG__DESCRIPTOR_IOC": "RS_JPEG_DESCRIPTOR_IOC",
        "APB4_JPEG__DESCRIPTOR_ENCODE": "RS_JPEG_DESCRIPTOR_ENCODE",
        "APB4_JPEG__DESCRIPTOR_AUTO_HEADER": "RS_JPEG_DESCRIPTOR_AUTO_HEADER",
        "APB4_JPEG__DESCRIPTOR_STRICT": "RS_JPEG_DESCRIPTOR_STRICT",
        "APB4_JPEG__DESCRIPTOR_METADATA": "RS_JPEG_DESCRIPTOR_METADATA",
        "APB4_JPEG__RING_CONTROL_ENABLE": "RS_JPEG_RING_CONTROL_ENABLE",
        "APB4_JPEG__RING_CONTROL_STOP_ERR": "RS_JPEG_RING_CONTROL_STOP_ERROR",
        "APB4_JPEG__RING_STATUS_ACTIVE": "RS_JPEG_RING_STATUS_ACTIVE",
        "APB4_JPEG__RING_STATUS_EMPTY": "RS_JPEG_RING_STATUS_EMPTY",
        "APB4_JPEG__RING_STATUS_STALLED": "RS_JPEG_RING_STATUS_STALLED",
        "APB4_JPEG__RING_STATUS_ERROR": "RS_JPEG_RING_STATUS_ERROR",
        "APB4_JPEG__TABLE_COMMAND_COMMIT": "RS_JPEG_TABLE_COMMAND_COMMIT",
        "APB4_JPEG__TABLE_COMMAND_DEFAULT": "RS_JPEG_TABLE_COMMAND_DEFAULT",
        "APB4_JPEG__TABLE_COMMAND_CLEAR": "RS_JPEG_TABLE_COMMAND_CLEAR",
    }
    for rtl_name, c_name in bit_mapping.items():
        assert c[c_name] == 1 << rtl[rtl_name], f"{rtl_name} != {c_name}"

    shift_mapping = {
        "APB4_JPEG__JOB_CONFIG_TABLE": "RS_JPEG_JOB_CONFIG_TABLE_SHIFT",
        "APB4_JPEG__DESCRIPTOR_TABLE": "RS_JPEG_DESCRIPTOR_TABLE_SHIFT",
        "APB4_JPEG__DESCRIPTOR_INPUT_FMT": "RS_JPEG_DESCRIPTOR_INPUT_SHIFT",
        "APB4_JPEG__DESCRIPTOR_OUTPUT_FMT": "RS_JPEG_DESCRIPTOR_OUTPUT_SHIFT",
        "APB4_JPEG__DESCRIPTOR_SAMPLING": "RS_JPEG_DESCRIPTOR_SAMPLE_SHIFT",
    }
    for rtl_name, c_name in shift_mapping.items():
        assert c[c_name] == rtl[rtl_name], f"{rtl_name} != {c_name}"
