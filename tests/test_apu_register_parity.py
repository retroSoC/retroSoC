"""Keep the handwritten APU-P1 RTL and SDK register ABI synchronized."""

from __future__ import annotations

import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
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
