"""Keep the handwritten APU RTL and SDK register ABI synchronized through P3."""

from __future__ import annotations

import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

from apu_isa import abi_manifest  # noqa: E402


RTL_DEFINE = ROOT / "rtl/ip/multimedia/apu_define.svh"
C_HEADER = ROOT / "crt/include/retrosoc/hal/apu_regs.h"
REGISTER_TESTBENCH = ROOT / "tests/rtl/apu_reg_tb.sv"


def _rtl_values() -> dict[str, int]:
    values: dict[str, int] = {}
    pattern = re.compile(
        r"^`define\s+APB4_APU__(\w+)\s+((?:\d+)'[hHdDbB][0-9a-fA-F_]+|\d+)\s*$"
    )
    for line in RTL_DEFINE.read_text(encoding="utf-8").splitlines():
        match = pattern.match(line)
        if match is None:
            continue
        name, literal = match.groups()
        if "'" in literal:
            _, value = literal.split("'", maxsplit=1)
            radix = {"h": 16, "d": 10, "b": 2}[value[0].lower()]
            values[name] = int(value[1:].replace("_", ""), radix)
        else:
            values[name] = int(literal, 10)
    return values


def _c_values() -> dict[str, int]:
    values: dict[str, int] = {}
    pattern = re.compile(
        r"^#define\s+RS_APU_ABI_(\w+)\s+"
        r"(?:UINT32_C\((0[xX][0-9a-fA-F]+)\)|(\d+)[uU]?)\s*$"
    )
    for line in C_HEADER.read_text(encoding="utf-8").splitlines():
        match = pattern.match(line)
        if match is None:
            continue
        name, hexadecimal, decimal = match.groups()
        values[name] = int(hexadecimal, 16) if hexadecimal is not None else int(decimal, 10)
    return values


def test_apu_register_constants_match_expected_abi() -> None:
    assert _c_values() == _rtl_values()


def test_apu_register_matrix_covers_each_offset_once() -> None:
    offset_pattern = re.compile(
        r"^`define\s+APB4_APU__(\w+)\s+12'[hH][0-9a-fA-F_]+\s*$"
    )
    table_pattern = re.compile(r"add_register\(`APB4_APU__(\w+),")
    expected = [
        match.group(1)
        for line in RTL_DEFINE.read_text(encoding="utf-8").splitlines()
        if (match := offset_pattern.match(line)) is not None
    ]
    covered = table_pattern.findall(REGISTER_TESTBENCH.read_text(encoding="utf-8"))

    assert len(covered) == len(set(covered))
    assert set(covered) == set(expected)


def test_apu_p3_tool_isa_matches_handwritten_rtl_and_c() -> None:
    rtl = _rtl_values()
    manifest = abi_manifest()
    exact = {
        "APUMC_MAGIC": manifest["apumc"]["magic"],
        "APUMC_ABI": manifest["apumc"]["abi"],
        "APUMC_HEADER_BYTES": manifest["apumc"]["header_bytes"],
        "APUMC_ENTRY_BYTES": manifest["apumc"]["entry_bytes"],
        "APUMC_ENTRY_COUNT": manifest["apumc"]["entry_count"],
        "APUMC_MAX_INSTRUCTIONS": manifest["apumc"]["max_instructions"],
    }
    for name, value in manifest["classes"].items():
        exact[f"MC_CLASS_{name.upper()}"] = value
    for name, value in manifest["control_opcodes"].items():
        exact[f"MC_CONTROL_{name.upper()}"] = value
    for name, value in manifest["scalar_opcodes"].items():
        exact[f"MC_SCALAR_{name.upper()}"] = value
    for class_name, opcodes in manifest["deferred_opcodes"].items():
        for name, value in opcodes.items():
            exact[f"MC_{class_name.upper()}_{name.upper()}"] = value
    predicate_names = {
        "always": "ALWAYS",
        "eq": "EQ",
        "ne": "NE",
        "slt": "SIGNED_LT",
        "sge": "SIGNED_GE",
        "ult": "UNSIGNED_LT",
        "uge": "UNSIGNED_GE",
        "input_exhausted": "INPUT_EXHAUSTED",
        "input_ready": "INPUT_READY",
        "output_ready": "OUTPUT_READY",
        "kernel_done": "KERNEL_DONE",
        "transport_done": "TRANSPORT_DONE",
    }
    for name, value in manifest["predicates"].items():
        exact[f"MC_PRED_{predicate_names[name]}"] = value
    for name, value in manifest["wait_sources"].items():
        exact[f"MC_WAIT_{name.upper()}"] = value
    for name, value in manifest["primitives"].items():
        exact[f"MC_PRIMITIVE_{name.upper()}"] = value
    for name, value in manifest["instruction_fields"].items():
        exact[f"MC_INSTRUCTION_{name.upper()}"] = value
    for name, value in manifest["entry_words"].items():
        exact[f"APUMC_ENTRY_{name.upper()}"] = value
    trap_names = {
        "illegal": "ILLEGAL",
        "pc_range": "PC_RANGE",
        "call_stack": "CALL_STACK",
        "loop": "LOOP",
        "local_range": "LOCAL_RANGE",
        "unavailable": "UNAVAILABLE",
        "watchdog": "WATCHDOG",
        "retired_budget": "RETIRED_BUDGET",
        "engine": "ENGINE",
        "explicit": "EXPLICIT",
    }
    for name, value in manifest["trap_reasons"].items():
        if name != "reserved":
            exact[f"MC_TRAP_{trap_names[name]}"] = value
    assert {name: rtl[name] for name in exact} == exact
