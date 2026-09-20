"""Keep the handwritten NPU RTL and SDK register constants synchronized.

Both sides are handwritten from the frozen register/ABI tables in
docs/ip/npu.md; no register generator is involved. The naming and radix
conventions follow ga2d_define.svh / ga2d_regs.h:

- `APB4_NPU__<REGISTER>` (12'h...) in the svh matches `RS_NPU_REG_<REGISTER>`
  (UINT32_C hex) in C, one entry per register map row including the ten
  PERF counter low/high pairs at 8-byte stride.
- Bit groups (CONTROL, STATUS, IRQ, CAPABILITY, PERF_CONTROL, PERF_STATUS,
  OWNER_STATUS lock/quiesce/reset-request) carry bit INDICES as plain
  decimals in the svh and one-bit MASKS UINT32_C(1U << index) in C.
- Sub-field shifts (FAULT_INFO, OWNER_STATUS owner) are plain decimals in
  the svh; C keeps the matching _SHIFT plus a C-only _MASK. Further C-only
  shifts/masks (MAC_CONFIG, JOB_COUNT, VERSION_OPCODE) decode fields the
  RTL does not name in the svh.
- Scalar values are 32'h.../16'h.../decimal in the svh and UINT32_C(...) in
  C. DESCRIPTOR_BYTES_VALUE carries a _VALUE suffix only on the svh side
  because the bare name is a register offset there; DESCRIPTOR_VERSION
  matches RS_NPU_DESCRIPTOR_ABI_VERSION. Reset/limit values the RTL does
  not instantiate (timeout reset, implemented memory/lane limits, MVP
  operator mask, descriptor ABI sizes) are C-only constants.
- Enumerations are plain decimals on both sides with asymmetric group
  names: APB4_NPU__RESULT_CODE_<NAME> vs RS_NPU_RESULT_<NAME>,
  APB4_NPU__FAULT_CODE_<NAME> vs RS_NPU_FAULT_<NAME> (the bare FAULT_CODE
  and FAULT_DESCRIPTOR names are register offsets), and
  APB4_NPU__OP_<NAME> vs RS_NPU_OPCODE_<NAME>.
- svh entries under LAUNCH_PAYLOAD/RESULT_PAYLOAD/SNAPSHOT_PAYLOAD plus
  EPOCH_WIDTH and PERF_COUNTER_COUNT describe the hardware-internal
  shell/HP mailbox ABI and have no C counterpart; they are pinned by an
  explicit RTL-internal list so the exhaustiveness check still rejects
  unexpected names on either side.
"""

from __future__ import annotations

import re
from pathlib import Path

import pytest


ROOT = Path(__file__).resolve().parents[1]
RTL_DEFINE = ROOT / "rtl/ip/multimedia/npu_define.svh"
C_DEFINE = ROOT / "crt/include/retrosoc/hal/npu_regs.h"


def _literal_value(value: str) -> int:
    value = value.replace("_", "")
    if "'" in value:
        _, encoded = value.split("'", maxsplit=1)
        base = 16 if encoded[0].lower() == "h" else 10
        return int(encoded[1:], base)
    return int(value, 10)


def _rtl_values() -> dict[str, int]:
    if not RTL_DEFINE.is_file():
        pytest.skip("rtl/ip/multimedia/npu_define.svh is not present yet")
    pattern = re.compile(r"^`define\s+(APB4_NPU__\w+)\s+((?:\d+)'[hHdD][0-9a-fA-F_]+|\d+)\s*$")
    values: dict[str, int] = {}
    for line in RTL_DEFINE.read_text(encoding="utf-8").splitlines():
        match = pattern.match(line)
        if match is not None:
            values[match.group(1)] = _literal_value(match.group(2))
    return values


def _c_values() -> dict[str, int]:
    pattern = re.compile(r"^#define\s+(RS_NPU_\w+)\s+(?:UINT32_C\((0x[0-9a-fA-F]+|\d+)\)|(\d+)U)\s*$")
    values: dict[str, int] = {}
    for line in C_DEFINE.read_text(encoding="utf-8").splitlines():
        match = pattern.match(line)
        if match is not None:
            values[match.group(1)] = int(
                match.group(2) if match.group(2) is not None else match.group(3), 0
            )
    return values


OFFSETS = (
    "IP_ID",
    "IP_VERSION",
    "CAPABILITY",
    "STATUS",
    "CONTROL",
    "IRQ_STATE",
    "IRQ_ENABLE",
    "IRQ_TEST",
    "JOB_BASE",
    "JOB_COUNT",
    "JOB_ID",
    "TIMEOUT_CYCLES",
    "RESULT_JOB_ID",
    "RESULT_CODE",
    "COMPLETED_DESCRIPTORS",
    "FAULT_DESCRIPTOR",
    "FAULT_CODE",
    "FAULT_ADDRESS",
    "FAULT_INFO",
    "NUMERIC_PROFILE",
    "LOCAL_BYTES",
    "MAC_CONFIG",
    "MAX_K_SLICE",
    "MAX_DIMENSION",
    "OP_CAPABILITY",
    "OWNER_STATUS",
    "RECOVERY_GENERATION",
    "PERF_CONTROL",
    "PERF_STATUS",
    "PERF_JOB_ID",
    "PERF_GENERATION",
    "DESCRIPTOR_BYTES",
    "PERF_ACTIVE_CYCLES_LO",
    "PERF_ACTIVE_CYCLES_HI",
    "PERF_CLOCK_PAUSE_CYCLES_LO",
    "PERF_CLOCK_PAUSE_CYCLES_HI",
    "PERF_USEFUL_MACS_LO",
    "PERF_USEFUL_MACS_HI",
    "PERF_PACK_CYCLES_LO",
    "PERF_PACK_CYCLES_HI",
    "PERF_LOCAL_BANK_STALL_LO",
    "PERF_LOCAL_BANK_STALL_HI",
    "PERF_DMA_READ_BYTES_LO",
    "PERF_DMA_READ_BYTES_HI",
    "PERF_DMA_WRITE_BYTES_LO",
    "PERF_DMA_WRITE_BYTES_HI",
    "PERF_DMA_STALL_CYCLES_LO",
    "PERF_DMA_STALL_CYCLES_HI",
    "PERF_REQUANT_STALL_LO",
    "PERF_REQUANT_STALL_HI",
    "PERF_RETIRED_DESCRIPTORS_LO",
    "PERF_RETIRED_DESCRIPTORS_HI",
)

SCALARS = {
    "APB4_NPU__IP_ID_VALUE": "RS_NPU_IP_ID_VALUE",
    "APB4_NPU__IP_VERSION_VALUE": "RS_NPU_IP_VERSION_VALUE",
    "APB4_NPU__CAPABILITY_P4": "RS_NPU_CAPABILITY_P4",
    "APB4_NPU__NUMERIC_PROFILE_VALUE": "RS_NPU_NUMERIC_PROFILE_VALUE",
    "APB4_NPU__DESCRIPTOR_BYTES_VALUE": "RS_NPU_DESCRIPTOR_BYTES",
    "APB4_NPU__LOCAL_BYTES_VALUE": "RS_NPU_LOCAL_BYTES_VALUE",
    "APB4_NPU__MAC_CONFIG_VALUE": "RS_NPU_MAC_CONFIG_VALUE",
    "APB4_NPU__MAX_K_SLICE_VALUE": "RS_NPU_MAX_K_SLICE",
    "APB4_NPU__MAX_DIMENSION_VALUE": "RS_NPU_MAX_DIMENSION",
    "APB4_NPU__OP_CAPABILITY_VALUE": "RS_NPU_OP_CAPABILITY_MVP",
    "APB4_NPU__DESCRIPTOR_VERSION": "RS_NPU_DESCRIPTOR_ABI_VERSION",
    "APB4_NPU__FAULT_DESCRIPTOR_RESET": "RS_NPU_FAULT_DESCRIPTOR_RESET",
    "APB4_NPU__IRQ_ALL": "RS_NPU_IRQ_ALL",
}

C_ONLY_SCALARS = (
    "RS_NPU_IP_VERSION_MAJOR_MASK",
    "RS_NPU_IP_VERSION_MAJOR_1",
    "RS_NPU_TIMEOUT_CYCLES_RESET",
    "RS_NPU_MAX_TILE",
    "RS_NPU_DESCRIPTOR_WORDS",
    "RS_NPU_DESCRIPTOR_BASE_ALIGNMENT",
    "RS_NPU_PARAM_RECORD_BYTES",
    "RS_NPU_ADD_PARAM_BYTES",
)

BIT_GROUPS = {
    "CONTROL": ("START", "ABORT", "SOFT_RESET"),
    "STATUS": ("READY", "BUSY", "DRAINING", "CLOCK_PAUSED", "RECOVERING", "RESULT_VALID"),
    "IRQ": ("DONE", "ERROR", "ABORTED"),
    "CAPABILITY": (
        "PRESENT",
        "EXECUTION_READY",
        "PRIVATE_AXI64_DMA",
        "INTERRUPTS",
        "DOUBLE_ROUNDING",
        "NATIVE_HP_CLOCK",
        "SOFTWARE_ABORT",
    ),
    "PERF_CONTROL": ("SNAPSHOT",),
    "PERF_STATUS": ("SNAP_BUSY", "SNAP_VALID"),
    "OWNER_STATUS": ("LOCK", "QUIESCE", "RESET_REQUEST"),
}

SHIFT_GROUPS = {
    "FAULT_INFO": ("AXI_RESPONSE", "DIRECTION", "LANE"),
    "OWNER_STATUS": ("OWNER",),
}

C_ONLY_SHIFT_GROUPS = {
    "MAC_CONFIG": ("DENSE", "DEPTHWISE"),
    "JOB_COUNT": ("VALUE",),
    "VERSION_OPCODE": ("VERSION", "OPCODE"),
}

C_ONLY_VALUES = (
    "RS_NPU_FAULT_INFO_DIRECTION_INTERNAL",
    "RS_NPU_FAULT_INFO_DIRECTION_READ",
    "RS_NPU_FAULT_INFO_DIRECTION_WRITE",
    "RS_NPU_FAULT_INFO_LANE_NONE",
)

RTL_INTERNAL = (
    "APB4_NPU__PERF_COUNTER_COUNT",
    "APB4_NPU__LAUNCH_PAYLOAD_WIDTH",
    "APB4_NPU__LAUNCH_JOB_BASE",
    "APB4_NPU__LAUNCH_JOB_ID",
    "APB4_NPU__LAUNCH_TIMEOUT_CYCLES",
    "APB4_NPU__LAUNCH_JOB_COUNT",
    "APB4_NPU__RESULT_PAYLOAD_WIDTH",
    "APB4_NPU__RESULT_PAYLOAD_JOB_ID",
    "APB4_NPU__RESULT_PAYLOAD_COMPLETED",
    "APB4_NPU__RESULT_PAYLOAD_FAULT_DESC",
    "APB4_NPU__RESULT_PAYLOAD_FAULT_ADDR",
    "APB4_NPU__RESULT_PAYLOAD_FAULT_INFO",
    "APB4_NPU__RESULT_PAYLOAD_CODE",
    "APB4_NPU__RESULT_PAYLOAD_FAULT_CODE",
    "APB4_NPU__RESULT_PAYLOAD_IRQ_EVENTS",
    "APB4_NPU__SNAPSHOT_PAYLOAD_WIDTH",
    "APB4_NPU__SNAPSHOT_PAYLOAD_JOB_ID",
    "APB4_NPU__SNAPSHOT_PAYLOAD_COUNTERS",
    "APB4_NPU__EPOCH_WIDTH",
)

RESULT_NAMES = ("NONE", "DONE", "ERROR", "ABORTED", "RESET_CANCELLED")

FAULT_NAMES = (
    "NONE",
    "DESCRIPTOR",
    "UNSUPPORTED",
    "RANGE",
    "AXI_READ",
    "AXI_WRITE",
    "AXI_PROTOCOL",
    "ARITHMETIC",
    "NO_PROGRESS",
    "LOCAL_STATE",
    "RESET_CANCELLED",
)

OPCODE_NAMES = (
    "CONV2D",
    "DEPTHWISE3X3",
    "FULLY_CONNECTED",
    "ADD",
    "MAX_POOL",
    "AVERAGE_POOL",
    "GLOBAL_AVERAGE_POOL",
    "CLAMP",
)

DESCRIPTOR_WORD_NAMES = (
    "VERSION_OPCODE",
    "RESERVED",
    "INPUT0_BASE",
    "INPUT1_BASE",
    "OUTPUT_BASE",
    "PARAM_BASE",
    "INPUT_HW",
    "CHANNELS",
    "OUTPUT_HW",
    "INPUT0_ROW_BYTES",
    "OUTPUT_ROW_BYTES",
    "INPUT1_ROW_BYTES",
    "KERNEL_STRIDE",
    "PADDING",
    "TILE_HW",
    "K_SLICE",
    "INPUT0_BYTES",
    "INPUT1_BYTES",
    "OUTPUT_BYTES",
    "PARAM_BYTES",
    "INPUT0_ZERO",
    "INPUT1_ZERO",
    "OUTPUT_ZERO",
    "ACTIVATION_BOUNDS",
    "WEIGHT_BASE",
    "WEIGHT_BYTES",
)


def test_npu_register_offsets_and_scalar_encodings_are_exhaustive() -> None:
    rtl = _rtl_values()
    c = _c_values()
    offset_mapping = {f"APB4_NPU__{name}": f"RS_NPU_REG_{name}" for name in OFFSETS}

    for rtl_name, c_name in {**offset_mapping, **SCALARS}.items():
        assert rtl[rtl_name] == c[c_name], f"{rtl_name} != {c_name}"

    assert rtl["APB4_NPU__IP_ID_VALUE"] == 0x4E505531
    assert rtl["APB4_NPU__IP_VERSION_VALUE"] == 0x00010000
    assert rtl["APB4_NPU__CAPABILITY_P4"] == 0x0000007F
    assert rtl["APB4_NPU__NUMERIC_PROFILE_VALUE"] == 1
    assert rtl["APB4_NPU__DESCRIPTOR_BYTES_VALUE"] == 128
    assert rtl["APB4_NPU__DESCRIPTOR_VERSION"] == 0x0100
    assert rtl["APB4_NPU__FAULT_DESCRIPTOR_RESET"] == 0xFFFFFFFF
    assert rtl["APB4_NPU__IRQ_ALL"] == 0x7
    assert c["RS_NPU_TIMEOUT_CYCLES_RESET"] == 72000000
    assert rtl["APB4_NPU__LOCAL_BYTES_VALUE"] == 65536
    assert rtl["APB4_NPU__MAC_CONFIG_VALUE"] == 0x00080040
    assert rtl["APB4_NPU__MAX_K_SLICE_VALUE"] == 1024
    assert rtl["APB4_NPU__MAX_DIMENSION_VALUE"] == 4096
    assert rtl["APB4_NPU__OP_CAPABILITY_VALUE"] == 0x000001FE
    assert c["RS_NPU_MAX_K_SLICE"] == 1024
    assert c["RS_NPU_MAX_DIMENSION"] == 4096
    assert c["RS_NPU_OP_CAPABILITY_MVP"] == 0x000001FE
    assert c["RS_NPU_DESCRIPTOR_WORDS"] == 32
    for index, name in enumerate(OFFSETS):
        if index < 32:
            expected = 4 * index
        else:
            expected = 0x080 + 8 * ((index - 32) // 2) + (4 if index % 2 == 1 else 0)
        assert rtl[f"APB4_NPU__{name}"] == expected, f"offset order mismatch for {name}"
    assert set(offset_mapping) <= set(rtl)
    assert set(offset_mapping.values()) | set(SCALARS.values()) | set(C_ONLY_SCALARS) <= set(c)


def test_npu_register_bit_shifts_and_enums_are_exhaustive() -> None:
    rtl = _rtl_values()
    c = _c_values()
    bit_mapping = {
        f"APB4_NPU__{group}_{name}": f"RS_NPU_{group}_{name}"
        for group, names in BIT_GROUPS.items()
        for name in names
    }
    shift_mapping = {
        f"APB4_NPU__{group}_{name}": f"RS_NPU_{group}_{name}_SHIFT"
        for group, names in SHIFT_GROUPS.items()
        for name in names
    }
    result_mapping = {
        f"APB4_NPU__RESULT_CODE_{name}": f"RS_NPU_RESULT_{name}" for name in RESULT_NAMES
    }
    fault_mapping = {f"APB4_NPU__FAULT_CODE_{name}": f"RS_NPU_FAULT_{name}" for name in FAULT_NAMES}
    opcode_mapping = {f"APB4_NPU__OP_{name}": f"RS_NPU_OPCODE_{name}" for name in OPCODE_NAMES}
    word_mapping = {
        f"APB4_NPU__DESCRIPTOR_WORD_{name}": f"RS_NPU_DESCRIPTOR_WORD_{name}"
        for name in DESCRIPTOR_WORD_NAMES
    }

    for rtl_name, c_name in bit_mapping.items():
        assert c[c_name] == 1 << rtl[rtl_name], f"{rtl_name} != {c_name}"
    for rtl_name, c_name in {
        **shift_mapping,
        **result_mapping,
        **fault_mapping,
        **opcode_mapping,
        **word_mapping,
    }.items():
        assert rtl[rtl_name] == c[c_name], f"{rtl_name} != {c_name}"

    for index, name in enumerate(OPCODE_NAMES):
        assert rtl[f"APB4_NPU__OP_{name}"] == index + 1
    for index, name in enumerate(DESCRIPTOR_WORD_NAMES):
        assert rtl[f"APB4_NPU__DESCRIPTOR_WORD_{name}"] == index
    for index, name in enumerate(FAULT_NAMES):
        assert rtl[f"APB4_NPU__FAULT_CODE_{name}"] == index


def test_npu_handwritten_definition_sets_have_no_missing_or_extra_entries() -> None:
    rtl = _rtl_values()
    c = _c_values()
    expected_rtl = (
        {f"APB4_NPU__{name}" for name in OFFSETS}
        | set(SCALARS)
        | {f"APB4_NPU__{group}_{name}" for group, names in BIT_GROUPS.items() for name in names}
        | {f"APB4_NPU__{group}_{name}" for group, names in SHIFT_GROUPS.items() for name in names}
        | {f"APB4_NPU__RESULT_CODE_{name}" for name in RESULT_NAMES}
        | {f"APB4_NPU__FAULT_CODE_{name}" for name in FAULT_NAMES}
        | {f"APB4_NPU__OP_{name}" for name in OPCODE_NAMES}
        | {f"APB4_NPU__DESCRIPTOR_WORD_{name}" for name in DESCRIPTOR_WORD_NAMES}
        | set(RTL_INTERNAL)
    )
    expected_c = (
        {f"RS_NPU_REG_{name}" for name in OFFSETS}
        | set(SCALARS.values())
        | set(C_ONLY_SCALARS)
        | {f"RS_NPU_{group}_{name}" for group, names in BIT_GROUPS.items() for name in names}
        | {
            f"RS_NPU_{group}_{name}_{suffix}"
            for groups in (SHIFT_GROUPS, C_ONLY_SHIFT_GROUPS)
            for group, names in groups.items()
            for name in names
            for suffix in ("SHIFT", "MASK")
        }
        | set(C_ONLY_VALUES)
        | {f"RS_NPU_RESULT_{name}" for name in RESULT_NAMES}
        | {f"RS_NPU_FAULT_{name}" for name in FAULT_NAMES}
        | {f"RS_NPU_OPCODE_{name}" for name in OPCODE_NAMES}
        | {f"RS_NPU_DESCRIPTOR_WORD_{name}" for name in DESCRIPTOR_WORD_NAMES}
    )

    assert set(rtl) == expected_rtl
    assert set(c) == expected_c
