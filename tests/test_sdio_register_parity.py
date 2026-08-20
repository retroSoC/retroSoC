"""Check the handwritten SDIO ABI against the RTL register contract."""

from __future__ import annotations

import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
RTL_DEFINE = ROOT / "rtl/ip/storage/sdio_define.svh"
C_HEADER = ROOT / "crt/include/retrosoc/hal/sdio_regs.h"


def _rtl_values() -> dict[str, int]:
    values: dict[str, int] = {}
    pattern = re.compile(
        r"^`define\s+(APB4_SDIO__\w+)\s+"
        r"(?:(\d+)'([hHdDbB])([0-9a-fA-F_xXzZ]+)|(\d+))\s*$"
    )
    for line in RTL_DEFINE.read_text(encoding="utf-8").splitlines():
        match = pattern.match(line)
        if match is None:
            continue
        name, width, base, digits, decimal = match.groups()
        del width
        if decimal is not None:
            values[name] = int(decimal, 10)
        else:
            radix = {"h": 16, "d": 10, "b": 2}[base.lower()]
            values[name] = int(digits.replace("_", ""), radix)
    return values


def _c_values() -> dict[str, int]:
    values: dict[str, int] = {}
    pattern = re.compile(
        r"^#define\s+(RS_SDIO_ABI_\w+)\s+"
        r"(?:UINT32_C\((0[xX][0-9a-fA-F]+)\)|(\d+)[uU]?)\s*$"
    )
    for line in C_HEADER.read_text(encoding="utf-8").splitlines():
        match = pattern.match(line)
        if match is None:
            continue
        name, hexadecimal, decimal = match.groups()
        values[name.removeprefix("RS_SDIO_ABI_")] = int(
            hexadecimal, 16
        ) if hexadecimal is not None else int(decimal, 10)
    return values


def test_sdio_register_constants_match_expected_abi() -> None:
    rtl = _rtl_values()
    c_header = _c_values()
    assert c_header == {
        name.removeprefix("APB4_SDIO__"): value for name, value in rtl.items()
    }
