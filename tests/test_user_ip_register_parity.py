"""Keep the integrated user-IP RTL and application register ABI synchronized."""

from __future__ import annotations

import json
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
C_DEFINE = ROOT / "app/network/userip/src/user_ip_regs.h"
EXTENSIONS = ROOT / "rtl/mini/integration/user_extensions.json"
SOC_HEADER = ROOT / "crt/include/retrosoc/core/soc.h"
RTL_DEFINES = {
    1: ROOT / "rtl/managed/mpw/ip/username1/user_ip_design.sv",
    2: ROOT / "rtl/managed/mpw/ip/username2/user_ip_design.sv",
}


def _rtl_values(path: Path) -> dict[str, int]:
    values: dict[str, int] = {}
    pattern = re.compile(r"^\s*localparam\s+(\w+)\s*=\s*8'h([0-9a-fA-F]+);(?:\s*//.*)?$")
    for line in path.read_text(encoding="utf-8").splitlines():
        match = pattern.match(line)
        if match is not None:
            name, value = match.groups()
            values[name] = int(value, 16)
    return values


def _c_values() -> dict[str, int]:
    values: dict[str, int] = {}
    pattern = re.compile(r"^#define\s+(\w+)\s+UINT(?:8|32)_C\((0x[0-9a-fA-F]+|\d+)\)$")
    for line in C_DEFINE.read_text(encoding="utf-8").splitlines():
        match = pattern.match(line)
        if match is not None:
            name, value = match.groups()
            values[name] = int(value, 0)
    return values


def test_user_ip_register_offsets_match_integrated_rtl() -> None:
    c = _c_values()
    mappings = {
        1: {
            "USER_IP_APB_ID": "RS_USER_TIMER_REG_ID",
            "USER_IP_APB_DIV": "RS_USER_TIMER_REG_DIV",
            "USER_IP_APB_CNT": "RS_USER_TIMER_REG_COUNT",
        },
        2: {
            "USER_IP_APB_ID": "RS_USER_GPIO_REG_ID",
            "USER_IP_APB_OE": "RS_USER_GPIO_REG_OE",
            "USER_IP_APB_DO": "RS_USER_GPIO_REG_DATA_OUT",
            "USER_IP_APB_DI": "RS_USER_GPIO_REG_DATA_IN",
        },
    }

    for slot, mapping in mappings.items():
        rtl = _rtl_values(RTL_DEFINES[slot])
        for rtl_name, c_name in mapping.items():
            assert rtl[rtl_name] == c[c_name], f"slot {slot}: {rtl_name} != {c_name}"


def test_user_ip_software_slots_match_extension_manifest() -> None:
    c = _c_values()
    document = json.loads(EXTENSIONS.read_text(encoding="utf-8"))
    targets = {(target["slot"], target["module"]) for target in document["ip_targets"]}

    assert targets == {
        (c["RS_USER_TIMER_SLOT"], "mpw_i1"),
        (c["RS_USER_GPIO_SLOT"], "mpw_i2"),
    }


def test_legacy_user_ip_register_macros_are_retired() -> None:
    assert "reg_user_ip_reg" not in SOC_HEADER.read_text(encoding="utf-8")
