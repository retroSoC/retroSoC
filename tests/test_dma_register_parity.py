"""Keep the handwritten DMA RTL and SDK register constants synchronized."""

from __future__ import annotations

import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
RTL_DEFINE = ROOT / "rtl/ip/peripheral/dma_define.svh"
C_DEFINE = ROOT / "crt/include/retrosoc/hal/dma_regs.h"


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


def test_dma_register_offsets_match_rtl() -> None:
    rtl = _rtl_values()
    c = _c_values()
    mapping = {
        "APB4_DMA__IP_ID": "RS_DMA_REG_IP_ID",
        "APB4_DMA__IP_VERSION": "RS_DMA_REG_IP_VERSION",
        "APB4_DMA__CAPABILITY": "RS_DMA_REG_CAPABILITY",
        "APB4_DMA__GLOBAL_CTRL": "RS_DMA_REG_GLOBAL_CTRL",
        "APB4_DMA__GLOBAL_STATUS": "RS_DMA_REG_GLOBAL_STATUS",
        "APB4_DMA__IRQ_STATE": "RS_DMA_REG_IRQ_STATE",
        "APB4_DMA__IRQ_ENABLE": "RS_DMA_REG_IRQ_ENABLE",
        "APB4_DMA__IRQ_TEST": "RS_DMA_REG_IRQ_TEST",
        "APB4_DMA__ERROR_SUMMARY": "RS_DMA_REG_ERROR_SUMMARY",
        "APB4_DMA__REQUEST_STATUS": "RS_DMA_REG_REQUEST_STATUS",
        "APB4_DMA__CH_BASE": "RS_DMA_CH_BASE",
        "APB4_DMA__CH_STRIDE": "RS_DMA_CH_STRIDE",
        "APB4_DMA__CH_CTRL": "RS_DMA_CH_REG_CTRL",
        "APB4_DMA__CH_CFG": "RS_DMA_CH_REG_CFG",
        "APB4_DMA__CH_SRC_ADDR": "RS_DMA_CH_REG_SRC_ADDR",
        "APB4_DMA__CH_DST_ADDR": "RS_DMA_CH_REG_DST_ADDR",
        "APB4_DMA__CH_BYTE_COUNT": "RS_DMA_CH_REG_BYTE_COUNT",
        "APB4_DMA__CH_REQUEST_SEL": "RS_DMA_CH_REG_REQUEST_SEL",
        "APB4_DMA__CH_BURST_CFG": "RS_DMA_CH_REG_BURST_CFG",
        "APB4_DMA__CH_EVENT_ENABLE": "RS_DMA_CH_REG_EVENT_ENABLE",
        "APB4_DMA__CH_STATUS": "RS_DMA_CH_REG_STATUS",
        "APB4_DMA__CH_EVENT_STATUS": "RS_DMA_CH_REG_EVENT_STATUS",
        "APB4_DMA__CH_ERROR_STATUS": "RS_DMA_CH_REG_ERROR_STATUS",
        "APB4_DMA__CH_ERROR_ADDR": "RS_DMA_CH_REG_ERROR_ADDR",
        "APB4_DMA__CH_CURRENT_SRC": "RS_DMA_CH_REG_CURRENT_SRC",
        "APB4_DMA__CH_CURRENT_DST": "RS_DMA_CH_REG_CURRENT_DST",
        "APB4_DMA__CH_REMAINING": "RS_DMA_CH_REG_REMAINING",
        "APB4_DMA__CH_BYTES_DONE": "RS_DMA_CH_REG_BYTES_DONE",
        "APB4_DMA__CH_STALL_CYCLES_LO": "RS_DMA_CH_REG_STALL_CYCLES_LO",
        "APB4_DMA__CH_STALL_CYCLES_HI": "RS_DMA_CH_REG_STALL_CYCLES_HI",
    }
    for rtl_name, c_name in mapping.items():
        assert rtl[rtl_name] == c[c_name], f"{rtl_name} != {c_name}"


def test_dma_register_fields_match_rtl() -> None:
    rtl = _rtl_values()
    c = _c_values()
    mapping = {
        "APB4_DMA__GLOBAL_CTRL_RESET": "RS_DMA_GLOBAL_CTRL_RESET",
        "APB4_DMA__CH_CTRL_START": "RS_DMA_CH_CTRL_START",
        "APB4_DMA__CH_CTRL_SUSPEND": "RS_DMA_CH_CTRL_SUSPEND",
        "APB4_DMA__CH_CTRL_RESUME": "RS_DMA_CH_CTRL_RESUME",
        "APB4_DMA__CH_CTRL_ABORT": "RS_DMA_CH_CTRL_ABORT",
        "APB4_DMA__CH_CTRL_RESET": "RS_DMA_CH_CTRL_RESET",
        "APB4_DMA__CH_CFG_KIND_LSB": "RS_DMA_CH_CFG_KIND_SHIFT",
        "APB4_DMA__CH_CFG_WIDTH_LSB": "RS_DMA_CH_CFG_WIDTH_SHIFT",
        "APB4_DMA__CH_CFG_SRC_INCREMENT": "RS_DMA_CH_CFG_SRC_INCREMENT",
        "APB4_DMA__CH_CFG_DST_INCREMENT": "RS_DMA_CH_CFG_DST_INCREMENT",
        "APB4_DMA__CH_CFG_PRIORITY_LSB": "RS_DMA_CH_CFG_PRIORITY_SHIFT",
        "APB4_DMA__EVENT_DONE": "RS_DMA_EVENT_DONE",
        "APB4_DMA__EVENT_HALF": "RS_DMA_EVENT_HALF",
        "APB4_DMA__EVENT_ERROR": "RS_DMA_EVENT_ERROR",
        "APB4_DMA__STATUS_BUSY": "RS_DMA_STATUS_BUSY",
        "APB4_DMA__STATUS_SUSPENDED": "RS_DMA_STATUS_SUSPENDED",
        "APB4_DMA__STATUS_DONE": "RS_DMA_STATUS_DONE",
        "APB4_DMA__STATUS_ABORTED": "RS_DMA_STATUS_ABORTED",
        "APB4_DMA__STATUS_ERROR": "RS_DMA_STATUS_ERROR",
        "APB4_DMA__STATUS_STREAM_LAST": "RS_DMA_STATUS_STREAM_LAST",
    }
    bit_mask_names = {
        "RS_DMA_GLOBAL_CTRL_RESET",
        "RS_DMA_CH_CTRL_START",
        "RS_DMA_CH_CTRL_SUSPEND",
        "RS_DMA_CH_CTRL_RESUME",
        "RS_DMA_CH_CTRL_ABORT",
        "RS_DMA_CH_CTRL_RESET",
        "RS_DMA_CH_CFG_SRC_INCREMENT",
        "RS_DMA_CH_CFG_DST_INCREMENT",
        "RS_DMA_EVENT_DONE",
        "RS_DMA_EVENT_HALF",
        "RS_DMA_EVENT_ERROR",
        "RS_DMA_STATUS_BUSY",
        "RS_DMA_STATUS_SUSPENDED",
        "RS_DMA_STATUS_DONE",
        "RS_DMA_STATUS_ABORTED",
        "RS_DMA_STATUS_ERROR",
        "RS_DMA_STATUS_STREAM_LAST",
    }
    for rtl_name, c_name in mapping.items():
        expected = 1 << rtl[rtl_name] if c_name in bit_mask_names else rtl[rtl_name]
        assert expected == c[c_name], f"{rtl_name} != {c_name}"
