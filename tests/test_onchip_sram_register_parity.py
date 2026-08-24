"""Keep the handwritten on-chip SRAM RTL and SDK register ABI synchronized."""

from __future__ import annotations

import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
RTL_DEFINE = ROOT / "rtl/mini/top/onchip_ram_define.svh"
C_HEADER = ROOT / "crt/include/retrosoc/hal/onchip_sram_regs.h"


def _rtl_offsets() -> dict[str, int]:
    return {
        name: int(value, 16)
        for name, value in re.findall(
            r"`define\s+APB4_ONCHIP_RAM__([A-Z0-9_]+)\s+12'h([0-9A-Fa-f]+)",
            RTL_DEFINE.read_text(encoding="utf-8"),
        )
    }


def _c_offsets() -> dict[str, int]:
    return {
        name: int(value, 16)
        for name, value in re.findall(
            r"#define\s+RS_ONCHIP_SRAM_REG_([A-Z0-9_]+)\s+UINT32_C\(0x([0-9A-Fa-f]+)\)",
            C_HEADER.read_text(encoding="utf-8"),
        )
    }


def test_onchip_sram_register_offsets_match_rtl() -> None:
    assert _c_offsets() == _rtl_offsets()
