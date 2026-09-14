"""Keep the handwritten GA2D RTL and SDK register constants synchronized."""

from __future__ import annotations

import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
RTL_DEFINE = ROOT / "rtl/ip/multimedia/ga2d_define.svh"
C_DEFINE = ROOT / "crt/include/retrosoc/hal/ga2d_regs.h"
C_API = ROOT / "crt/include/retrosoc/hal/ga2d.h"


def _literal_value(value: str) -> int:
    value = value.replace("_", "")
    if "'" in value:
        _, encoded = value.split("'", maxsplit=1)
        base = 16 if encoded[0].lower() == "h" else 10
        return int(encoded[1:], base)
    return int(value, 10)


def _rtl_values() -> dict[str, int]:
    pattern = re.compile(
        r"^`define\s+(APB4_GA2D__\w+)\s+((?:\d+)'[hHdD][0-9a-fA-F_]+|\d+)\s*$"
    )
    values: dict[str, int] = {}
    for line in RTL_DEFINE.read_text(encoding="utf-8").splitlines():
        match = pattern.match(line)
        if match is not None:
            values[match.group(1)] = _literal_value(match.group(2))
    return values


def _c_values() -> dict[str, int]:
    pattern = re.compile(r"^#define\s+(RS_GA2D_\w+)\s+(?:UINT32_C\((0x[0-9a-fA-F]+)\)|(\d+)U)\s*$")
    values: dict[str, int] = {}
    for line in C_DEFINE.read_text(encoding="utf-8").splitlines():
        match = pattern.match(line)
        if match is not None:
            values[match.group(1)] = int(
                match.group(2) if match.group(2) is not None else match.group(3), 0
            )
    return values


def _enum_values() -> dict[str, int]:
    pattern = re.compile(r"^\s*(RS_GA2D_(?:OP|FORMAT)_\w+)\s*=\s*(\d+),\s*$")
    values: dict[str, int] = {}
    for line in C_API.read_text(encoding="utf-8").splitlines():
        match = pattern.match(line)
        if match is not None:
            values[match.group(1)] = int(match.group(2), 10)
    return values


OFFSETS = (
    "IP_ID",
    "IP_VERSION",
    "CAPABILITY",
    "LIMITS",
    "COMMAND",
    "STATUS",
    "IRQ_STATE",
    "IRQ_ENABLE",
    "IRQ_TEST",
    "ERROR_STATUS",
    "ERROR_ADDRESS",
    "TIMEOUT_CYCLES",
    "JOB_CONFIG",
    "GLOBAL_ALPHA",
    "COLOR",
    "SIZE",
    "FG_ADDRESS",
    "FG_PITCH",
    "FG_FORMAT",
    "BG_ADDRESS",
    "BG_PITCH",
    "BG_FORMAT",
    "DST_ADDRESS",
    "DST_PITCH",
    "DST_FORMAT",
    "PERF_SNAPSHOT",
    "FORMAT_CAPABILITY",
    "SNAP_CYCLES_LO",
    "SNAP_CYCLES_HI",
    "SNAP_READ_BYTES_LO",
    "SNAP_READ_BYTES_HI",
    "SNAP_WRITE_BYTES_LO",
    "SNAP_WRITE_BYTES_HI",
    "SNAP_READ_STALL_LO",
    "SNAP_READ_STALL_HI",
    "SNAP_WRITE_STALL_LO",
    "SNAP_WRITE_STALL_HI",
    "SNAP_PIPE_STALL_LO",
    "SNAP_PIPE_STALL_HI",
    "SNAP_LINES_DONE",
)


def test_ga2d_register_offsets_and_scalar_encodings_are_exhaustive() -> None:
    rtl = _rtl_values()
    c = _c_values()
    offset_mapping = {f"APB4_GA2D__{name}": f"RS_GA2D_REG_{name}" for name in OFFSETS}
    scalar_mapping = {
        "APB4_GA2D__IP_ID_VALUE": "RS_GA2D_IP_ID_VALUE",
        "APB4_GA2D__IP_VERSION_VALUE": "RS_GA2D_IP_VERSION_VALUE",
        "APB4_GA2D__CAPABILITY_P4": "RS_GA2D_CAPABILITY_P4",
        "APB4_GA2D__LIMITS_P4": "RS_GA2D_LIMITS_P4",
        "APB4_GA2D__FORMAT_CAPABILITY_P4": "RS_GA2D_FORMAT_CAPABILITY_P4",
        "APB4_GA2D__TIMEOUT_CYCLES_RESET": "RS_GA2D_TIMEOUT_CYCLES_RESET",
        "APB4_GA2D__GLOBAL_ALPHA_RESET": "RS_GA2D_GLOBAL_ALPHA_RESET",
        "APB4_GA2D__IRQ_ALL": "RS_GA2D_IRQ_ALL",
    }
    expected_c = set(offset_mapping.values()) | set(scalar_mapping.values())

    for rtl_name, c_name in {**offset_mapping, **scalar_mapping}.items():
        assert rtl[rtl_name] == c[c_name], f"{rtl_name} != {c_name}"

    assert rtl["APB4_GA2D__CAPABILITY_P4"] == 0x000003E3
    assert rtl["APB4_GA2D__LIMITS_P4"] == 0x08202010
    assert rtl["APB4_GA2D__FORMAT_CAPABILITY_P4"] == 0x000F000F
    assert {name for name in rtl if name.endswith(tuple(OFFSETS))} >= set(offset_mapping)
    assert expected_c <= set(c)


def test_ga2d_register_bit_shifts_and_enums_are_exhaustive() -> None:
    rtl = _rtl_values()
    c = _c_values()
    enums = _enum_values()
    bit_mapping = {
        "APB4_GA2D__COMMAND_START": "RS_GA2D_COMMAND_START",
        "APB4_GA2D__COMMAND_ABORT": "RS_GA2D_COMMAND_ABORT",
        "APB4_GA2D__COMMAND_SOFT_RESET": "RS_GA2D_COMMAND_SOFT_RESET",
        "APB4_GA2D__STATUS_BUSY": "RS_GA2D_STATUS_BUSY",
        "APB4_GA2D__STATUS_DRAINING": "RS_GA2D_STATUS_DRAINING",
        "APB4_GA2D__STATUS_QUIESCED": "RS_GA2D_STATUS_QUIESCED",
        "APB4_GA2D__STATUS_DATA_READY": "RS_GA2D_STATUS_DATA_READY",
        "APB4_GA2D__STATUS_DONE": "RS_GA2D_STATUS_DONE",
        "APB4_GA2D__STATUS_ABORTED": "RS_GA2D_STATUS_ABORTED",
        "APB4_GA2D__STATUS_ERROR": "RS_GA2D_STATUS_ERROR",
        "APB4_GA2D__STATUS_RECOVERY_REQUIRED": "RS_GA2D_STATUS_RECOVERY_REQUIRED",
        "APB4_GA2D__IRQ_DONE": "RS_GA2D_IRQ_DONE",
        "APB4_GA2D__IRQ_ERROR": "RS_GA2D_IRQ_ERROR",
        "APB4_GA2D__IRQ_ABORT_DONE": "RS_GA2D_IRQ_ABORT_DONE",
        "APB4_GA2D__ERROR_STATUS_VALID": "RS_GA2D_ERROR_STATUS_VALID",
        "APB4_GA2D__CAPABILITY_FILL": "RS_GA2D_CAPABILITY_FILL",
        "APB4_GA2D__CAPABILITY_COPY": "RS_GA2D_CAPABILITY_COPY",
        "APB4_GA2D__CAPABILITY_CONVERT": "RS_GA2D_CAPABILITY_CONVERT",
        "APB4_GA2D__CAPABILITY_BLEND": "RS_GA2D_CAPABILITY_BLEND",
        "APB4_GA2D__CAPABILITY_A8_MASK": "RS_GA2D_CAPABILITY_A8_MASK",
        "APB4_GA2D__CAPABILITY_PRIVATE_DMA": "RS_GA2D_CAPABILITY_PRIVATE_DMA",
        "APB4_GA2D__CAPABILITY_IRQ": "RS_GA2D_CAPABILITY_IRQ",
        "APB4_GA2D__CAPABILITY_SNAPSHOT": "RS_GA2D_CAPABILITY_SNAPSHOT",
        "APB4_GA2D__CAPABILITY_TWO_DIMENSIONAL_PITCH": (
            "RS_GA2D_CAPABILITY_TWO_DIMENSIONAL_PITCH"
        ),
        "APB4_GA2D__CAPABILITY_BYTE_EDGES": "RS_GA2D_CAPABILITY_BYTE_EDGES",
        "APB4_GA2D__CAPABILITY_INPLACE_BACKGROUND": (
            "RS_GA2D_CAPABILITY_INPLACE_BACKGROUND"
        ),
    }
    shift_mapping = {
        "APB4_GA2D__ERROR_STATUS_CODE": "RS_GA2D_ERROR_STATUS_CODE_SHIFT",
        "APB4_GA2D__ERROR_STATUS_STAGE": "RS_GA2D_ERROR_STATUS_STAGE_SHIFT",
        "APB4_GA2D__ERROR_STATUS_AXI_RESPONSE": "RS_GA2D_ERROR_STATUS_AXI_RESPONSE_SHIFT",
        "APB4_GA2D__JOB_CONFIG_OPERATION": "RS_GA2D_JOB_CONFIG_OPERATION_SHIFT",
        "APB4_GA2D__GLOBAL_ALPHA_VALUE": "RS_GA2D_GLOBAL_ALPHA_VALUE_SHIFT",
        "APB4_GA2D__SIZE_WIDTH": "RS_GA2D_SIZE_WIDTH_SHIFT",
        "APB4_GA2D__SIZE_HEIGHT": "RS_GA2D_SIZE_HEIGHT_SHIFT",
        "APB4_GA2D__FG_FORMAT_VALUE": "RS_GA2D_FG_FORMAT_VALUE_SHIFT",
        "APB4_GA2D__BG_FORMAT_VALUE": "RS_GA2D_BG_FORMAT_VALUE_SHIFT",
        "APB4_GA2D__DST_FORMAT_VALUE": "RS_GA2D_DST_FORMAT_VALUE_SHIFT",
        "APB4_GA2D__FORMAT_CAPABILITY_FOREGROUND": (
            "RS_GA2D_FORMAT_CAPABILITY_FOREGROUND_SHIFT"
        ),
        "APB4_GA2D__FORMAT_CAPABILITY_BACKGROUND": (
            "RS_GA2D_FORMAT_CAPABILITY_BACKGROUND_SHIFT"
        ),
        "APB4_GA2D__FORMAT_CAPABILITY_DESTINATION": (
            "RS_GA2D_FORMAT_CAPABILITY_DESTINATION_SHIFT"
        ),
    }
    error_mapping = {
        f"APB4_GA2D__ERROR_{name}": f"RS_GA2D_ERROR_CODE_{name}"
        for name in (
            "NONE",
            "INVALID_SIZE",
            "INVALID_FORMAT",
            "INVALID_PITCH",
            "INVALID_ALIGNMENT",
            "ADDRESS_OVERFLOW",
            "ADDRESS_RANGE",
            "OVERLAP",
            "AXI_READ",
            "AXI_WRITE",
            "AXI_PROTOCOL",
            "TIMEOUT",
            "EPOCH_LOST",
            "INTERNAL",
        )
    }
    stage_mapping = {
        f"APB4_GA2D__ERROR_STAGE_{name}": f"RS_GA2D_ERROR_STAGE_{name}"
        for name in ("NONE", "VALIDATE", "FOREGROUND", "BACKGROUND", "DESTINATION", "LIFECYCLE")
    }
    enum_mapping = {
        "APB4_GA2D__OP_FILL": "RS_GA2D_OP_FILL",
        "APB4_GA2D__OP_COPY": "RS_GA2D_OP_COPY",
        "APB4_GA2D__OP_CONVERT": "RS_GA2D_OP_CONVERT",
        "APB4_GA2D__OP_BLEND": "RS_GA2D_OP_BLEND",
        "APB4_GA2D__FORMAT_RGB565": "RS_GA2D_FORMAT_RGB565",
        "APB4_GA2D__FORMAT_RGB888": "RS_GA2D_FORMAT_RGB888",
        "APB4_GA2D__FORMAT_XRGB8888": "RS_GA2D_FORMAT_XRGB8888",
        "APB4_GA2D__FORMAT_ARGB8888": "RS_GA2D_FORMAT_ARGB8888",
        "APB4_GA2D__FORMAT_A8": "RS_GA2D_FORMAT_A8",
    }

    for rtl_name, c_name in bit_mapping.items():
        assert c[c_name] == 1 << rtl[rtl_name], f"{rtl_name} != {c_name}"
    for rtl_name, c_name in {**shift_mapping, **error_mapping, **stage_mapping}.items():
        assert rtl[rtl_name] == c[c_name], f"{rtl_name} != {c_name}"
    for rtl_name, enum_name in enum_mapping.items():
        assert rtl[rtl_name] == enums[enum_name], f"{rtl_name} != {enum_name}"

    assert set(enums) == set(enum_mapping.values())


def test_ga2d_handwritten_definition_sets_have_no_missing_or_extra_entries() -> None:
    rtl = _rtl_values()
    c = _c_values()
    rtl_scalar_names = {
        "IP_ID_VALUE",
        "IP_VERSION_VALUE",
        "CAPABILITY_P4",
        "LIMITS_P4",
        "FORMAT_CAPABILITY_P4",
        "TIMEOUT_CYCLES_RESET",
        "GLOBAL_ALPHA_RESET",
        "IRQ_ALL",
    }
    rtl_bit_names = {
        "COMMAND_START",
        "COMMAND_ABORT",
        "COMMAND_SOFT_RESET",
        "STATUS_BUSY",
        "STATUS_DRAINING",
        "STATUS_QUIESCED",
        "STATUS_DATA_READY",
        "STATUS_DONE",
        "STATUS_ABORTED",
        "STATUS_ERROR",
        "STATUS_RECOVERY_REQUIRED",
        "IRQ_DONE",
        "IRQ_ERROR",
        "IRQ_ABORT_DONE",
        "ERROR_STATUS_VALID",
        "CAPABILITY_FILL",
        "CAPABILITY_COPY",
        "CAPABILITY_CONVERT",
        "CAPABILITY_BLEND",
        "CAPABILITY_A8_MASK",
        "CAPABILITY_PRIVATE_DMA",
        "CAPABILITY_IRQ",
        "CAPABILITY_SNAPSHOT",
        "CAPABILITY_TWO_DIMENSIONAL_PITCH",
        "CAPABILITY_BYTE_EDGES",
        "CAPABILITY_INPLACE_BACKGROUND",
    }
    rtl_shift_names = {
        "ERROR_STATUS_CODE",
        "ERROR_STATUS_STAGE",
        "ERROR_STATUS_AXI_RESPONSE",
        "JOB_CONFIG_OPERATION",
        "GLOBAL_ALPHA_VALUE",
        "SIZE_WIDTH",
        "SIZE_HEIGHT",
        "FG_FORMAT_VALUE",
        "BG_FORMAT_VALUE",
        "DST_FORMAT_VALUE",
        "FORMAT_CAPABILITY_FOREGROUND",
        "FORMAT_CAPABILITY_BACKGROUND",
        "FORMAT_CAPABILITY_DESTINATION",
    }
    error_names = {
        "NONE",
        "INVALID_SIZE",
        "INVALID_FORMAT",
        "INVALID_PITCH",
        "INVALID_ALIGNMENT",
        "ADDRESS_OVERFLOW",
        "ADDRESS_RANGE",
        "OVERLAP",
        "AXI_READ",
        "AXI_WRITE",
        "AXI_PROTOCOL",
        "TIMEOUT",
        "EPOCH_LOST",
        "INTERNAL",
    }
    stage_names = {"NONE", "VALIDATE", "FOREGROUND", "BACKGROUND", "DESTINATION", "LIFECYCLE"}
    operation_names = {"FILL", "COPY", "CONVERT", "BLEND"}
    format_names = {"RGB565", "RGB888", "XRGB8888", "ARGB8888", "A8"}
    expected_rtl = (
        {f"APB4_GA2D__{name}" for name in OFFSETS}
        | {f"APB4_GA2D__{name}" for name in rtl_scalar_names}
        | {f"APB4_GA2D__{name}" for name in rtl_bit_names}
        | {f"APB4_GA2D__{name}" for name in rtl_shift_names}
        | {f"APB4_GA2D__ERROR_{name}" for name in error_names}
        | {f"APB4_GA2D__ERROR_STAGE_{name}" for name in stage_names}
        | {f"APB4_GA2D__OP_{name}" for name in operation_names}
        | {f"APB4_GA2D__FORMAT_{name}" for name in format_names}
    )
    expected_c = (
        {f"RS_GA2D_REG_{name}" for name in OFFSETS}
        | {
            "RS_GA2D_IP_ID_VALUE",
            "RS_GA2D_IP_VERSION_VALUE",
            "RS_GA2D_IP_VERSION_MAJOR_MASK",
            "RS_GA2D_IP_VERSION_MAJOR_1",
            "RS_GA2D_CAPABILITY_P4",
            "RS_GA2D_LIMITS_P4",
            "RS_GA2D_FORMAT_CAPABILITY_P4",
            "RS_GA2D_TIMEOUT_CYCLES_RESET",
            "RS_GA2D_GLOBAL_ALPHA_RESET",
            "RS_GA2D_COMMAND_START",
            "RS_GA2D_COMMAND_ABORT",
            "RS_GA2D_COMMAND_SOFT_RESET",
            "RS_GA2D_STATUS_BUSY",
            "RS_GA2D_STATUS_DRAINING",
            "RS_GA2D_STATUS_QUIESCED",
            "RS_GA2D_STATUS_DATA_READY",
            "RS_GA2D_STATUS_DONE",
            "RS_GA2D_STATUS_ABORTED",
            "RS_GA2D_STATUS_ERROR",
            "RS_GA2D_STATUS_RECOVERY_REQUIRED",
            "RS_GA2D_IRQ_DONE",
            "RS_GA2D_IRQ_ERROR",
            "RS_GA2D_IRQ_ABORT_DONE",
            "RS_GA2D_IRQ_ALL",
            "RS_GA2D_ERROR_STATUS_VALID",
            "RS_GA2D_ERROR_STATUS_CODE_SHIFT",
            "RS_GA2D_ERROR_STATUS_CODE_MASK",
            "RS_GA2D_ERROR_STATUS_STAGE_SHIFT",
            "RS_GA2D_ERROR_STATUS_STAGE_MASK",
            "RS_GA2D_ERROR_STATUS_AXI_RESPONSE_SHIFT",
            "RS_GA2D_ERROR_STATUS_AXI_RESPONSE_MASK",
            "RS_GA2D_JOB_CONFIG_OPERATION_SHIFT",
            "RS_GA2D_JOB_CONFIG_OPERATION_MASK",
            "RS_GA2D_GLOBAL_ALPHA_VALUE_SHIFT",
            "RS_GA2D_GLOBAL_ALPHA_VALUE_MASK",
            "RS_GA2D_SIZE_WIDTH_SHIFT",
            "RS_GA2D_SIZE_WIDTH_MASK",
            "RS_GA2D_SIZE_HEIGHT_SHIFT",
            "RS_GA2D_SIZE_HEIGHT_MASK",
            "RS_GA2D_FG_FORMAT_VALUE_SHIFT",
            "RS_GA2D_BG_FORMAT_VALUE_SHIFT",
            "RS_GA2D_DST_FORMAT_VALUE_SHIFT",
            "RS_GA2D_FORMAT_VALUE_MASK",
            "RS_GA2D_FORMAT_CAPABILITY_FOREGROUND_SHIFT",
            "RS_GA2D_FORMAT_CAPABILITY_BACKGROUND_SHIFT",
            "RS_GA2D_FORMAT_CAPABILITY_DESTINATION_SHIFT",
            "RS_GA2D_FORMAT_CAPABILITY_MASK",
        }
        | {f"RS_GA2D_CAPABILITY_{name}" for name in operation_names | {
            "A8_MASK",
            "PRIVATE_DMA",
            "IRQ",
            "SNAPSHOT",
            "TWO_DIMENSIONAL_PITCH",
            "BYTE_EDGES",
            "INPLACE_BACKGROUND",
        }}
        | {f"RS_GA2D_ERROR_CODE_{name}" for name in error_names}
        | {f"RS_GA2D_ERROR_STAGE_{name}" for name in stage_names}
    )

    assert set(rtl) == expected_rtl
    assert set(c) == expected_c
