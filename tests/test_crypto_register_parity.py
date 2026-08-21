"""Keep the handwritten crypto RTL and SDK register constants synchronized."""

from __future__ import annotations

import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
RTL_DEFINE = ROOT / "rtl/ip/security/crypto_define.svh"
C_DEFINE = ROOT / "crt/include/retrosoc/hal/crypto_regs.h"


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


def test_crypto_register_offsets_match_rtl() -> None:
    rtl = _rtl_values()
    c = _c_values()
    mapping = {
        "APB4_CRYPTO__IP_ID": "RS_CRYPTO_REG_IP_ID",
        "APB4_CRYPTO__IP_VERSION": "RS_CRYPTO_REG_IP_VERSION",
        "APB4_CRYPTO__CAPABILITY0": "RS_CRYPTO_REG_CAPABILITY0",
        "APB4_CRYPTO__CAPABILITY1": "RS_CRYPTO_REG_CAPABILITY1",
        "APB4_CRYPTO__COMMAND": "RS_CRYPTO_REG_COMMAND",
        "APB4_CRYPTO__STATUS": "RS_CRYPTO_REG_STATUS",
        "APB4_CRYPTO__IRQ_STATE": "RS_CRYPTO_REG_IRQ_STATE",
        "APB4_CRYPTO__IRQ_ENABLE": "RS_CRYPTO_REG_IRQ_ENABLE",
        "APB4_CRYPTO__IRQ_TEST": "RS_CRYPTO_REG_IRQ_TEST",
        "APB4_CRYPTO__ERROR_STATUS": "RS_CRYPTO_REG_ERROR_STATUS",
        "APB4_CRYPTO__AES_CTRL": "RS_CRYPTO_REG_AES_CTRL",
        "APB4_CRYPTO__AES_CFG": "RS_CRYPTO_REG_AES_CFG",
        "APB4_CRYPTO__AES_STATUS": "RS_CRYPTO_REG_AES_STATUS",
        "APB4_CRYPTO__AES_LENGTH": "RS_CRYPTO_REG_AES_LENGTH",
        "APB4_CRYPTO__AES_DATA_IN": "RS_CRYPTO_REG_AES_DATA_IN",
        "APB4_CRYPTO__AES_DATA_OUT": "RS_CRYPTO_REG_AES_DATA_OUT",
        "APB4_CRYPTO__AES_DATA_STATUS": "RS_CRYPTO_REG_AES_DATA_STATUS",
        "APB4_CRYPTO__AES_BYTES_IN": "RS_CRYPTO_REG_AES_BYTES_IN",
        "APB4_CRYPTO__AES_BYTES_OUT": "RS_CRYPTO_REG_AES_BYTES_OUT",
        "APB4_CRYPTO__AES_CYCLES": "RS_CRYPTO_REG_AES_CYCLES",
        "APB4_CRYPTO__AES_KEY_CTRL": "RS_CRYPTO_REG_AES_KEY_CTRL",
        "APB4_CRYPTO__AES_KEY_STATUS": "RS_CRYPTO_REG_AES_KEY_STATUS",
        "APB4_CRYPTO__AES_KEY_BASE": "RS_CRYPTO_REG_AES_KEY_BASE",
        "APB4_CRYPTO__AES_IV_BASE": "RS_CRYPTO_REG_AES_IV_BASE",
        "APB4_CRYPTO__AES_CHAIN_BASE": "RS_CRYPTO_REG_AES_CHAIN_BASE",
        "APB4_CRYPTO__SHA_CTRL": "RS_CRYPTO_REG_SHA_CTRL",
        "APB4_CRYPTO__SHA_CFG": "RS_CRYPTO_REG_SHA_CFG",
        "APB4_CRYPTO__SHA_STATUS": "RS_CRYPTO_REG_SHA_STATUS",
        "APB4_CRYPTO__SHA_LENGTH_LO": "RS_CRYPTO_REG_SHA_LENGTH_LO",
        "APB4_CRYPTO__SHA_LENGTH_HI": "RS_CRYPTO_REG_SHA_LENGTH_HI",
        "APB4_CRYPTO__SHA_DATA_IN": "RS_CRYPTO_REG_SHA_DATA_IN",
        "APB4_CRYPTO__SHA_DATA_STATUS": "RS_CRYPTO_REG_SHA_DATA_STATUS",
        "APB4_CRYPTO__SHA_BYTES_IN_LO": "RS_CRYPTO_REG_SHA_BYTES_IN_LO",
        "APB4_CRYPTO__SHA_BYTES_IN_HI": "RS_CRYPTO_REG_SHA_BYTES_IN_HI",
        "APB4_CRYPTO__SHA_CYCLES": "RS_CRYPTO_REG_SHA_CYCLES",
        "APB4_CRYPTO__SHA_DIGEST_BASE": "RS_CRYPTO_REG_SHA_DIGEST_BASE",
        "APB4_CRYPTO__RSA_CTRL": "RS_CRYPTO_REG_RSA_CTRL",
        "APB4_CRYPTO__RSA_CFG": "RS_CRYPTO_REG_RSA_CFG",
        "APB4_CRYPTO__RSA_STATUS": "RS_CRYPTO_REG_RSA_STATUS",
        "APB4_CRYPTO__RSA_CYCLES": "RS_CRYPTO_REG_RSA_CYCLES",
        "APB4_CRYPTO__RSA_PROGRESS": "RS_CRYPTO_REG_RSA_PROGRESS",
        "APB4_CRYPTO__RSA_MODULUS_BASE": "RS_CRYPTO_REG_RSA_MODULUS_BASE",
        "APB4_CRYPTO__RSA_EXPONENT_BASE": "RS_CRYPTO_REG_RSA_EXPONENT_BASE",
        "APB4_CRYPTO__RSA_BASE_BASE": "RS_CRYPTO_REG_RSA_BASE_BASE",
        "APB4_CRYPTO__RSA_RESULT_BASE": "RS_CRYPTO_REG_RSA_RESULT_BASE",
    }
    for rtl_name, c_name in mapping.items():
        assert rtl[rtl_name] == c[c_name], f"{rtl_name} != {c_name}"


def test_crypto_register_fields_match_rtl() -> None:
    rtl = _rtl_values()
    c = _c_values()
    mapping = {
        "APB4_CRYPTO__COMMAND_ZEROIZE": "RS_CRYPTO_COMMAND_ZEROIZE",
        "APB4_CRYPTO__COMMAND_ABORT_AES": "RS_CRYPTO_COMMAND_ABORT_AES",
        "APB4_CRYPTO__COMMAND_ABORT_SHA": "RS_CRYPTO_COMMAND_ABORT_SHA",
        "APB4_CRYPTO__COMMAND_ABORT_RSA": "RS_CRYPTO_COMMAND_ABORT_RSA",
        "APB4_CRYPTO__AES_CTRL_START": "RS_CRYPTO_AES_CTRL_START",
        "APB4_CRYPTO__AES_CFG_MODE": "RS_CRYPTO_AES_CFG_MODE_SHIFT",
        "APB4_CRYPTO__AES_CFG_DECRYPT": "RS_CRYPTO_AES_CFG_DECRYPT",
        "APB4_CRYPTO__AES_CFG_KEY_SIZE": "RS_CRYPTO_AES_CFG_KEY_SIZE_SHIFT",
        "APB4_CRYPTO__AES_CFG_DMA": "RS_CRYPTO_AES_CFG_DMA",
        "APB4_CRYPTO__AES_KEY_CTRL_COMMIT": "RS_CRYPTO_AES_KEY_CTRL_COMMIT",
        "APB4_CRYPTO__SHA_CTRL_START": "RS_CRYPTO_SHA_CTRL_START",
        "APB4_CRYPTO__SHA_CFG_SHA256": "RS_CRYPTO_SHA_CFG_SHA256",
        "APB4_CRYPTO__SHA_CFG_DMA": "RS_CRYPTO_SHA_CFG_DMA",
        "APB4_CRYPTO__RSA_CTRL_PREPARE": "RS_CRYPTO_RSA_CTRL_PREPARE",
        "APB4_CRYPTO__RSA_CTRL_PUBLIC": "RS_CRYPTO_RSA_CTRL_PUBLIC",
        "APB4_CRYPTO__RSA_CTRL_PRIVATE": "RS_CRYPTO_RSA_CTRL_PRIVATE",
        "APB4_CRYPTO__RSA_CFG_EXPONENT_BITS": "RS_CRYPTO_RSA_CFG_EXPONENT_BITS",
        "APB4_CRYPTO__IRQ_AES_DONE": "RS_CRYPTO_IRQ_AES_DONE",
        "APB4_CRYPTO__IRQ_SHA_DONE": "RS_CRYPTO_IRQ_SHA_DONE",
        "APB4_CRYPTO__IRQ_RSA_DONE": "RS_CRYPTO_IRQ_RSA_DONE",
        "APB4_CRYPTO__IRQ_ERROR": "RS_CRYPTO_IRQ_ERROR",
        "APB4_CRYPTO__IRQ_ZEROIZED": "RS_CRYPTO_IRQ_ZEROIZED",
    }
    shift_names = {
        "RS_CRYPTO_AES_CFG_MODE_SHIFT",
        "RS_CRYPTO_AES_CFG_KEY_SIZE_SHIFT",
        "RS_CRYPTO_RSA_CFG_EXPONENT_BITS",
    }
    for rtl_name, c_name in mapping.items():
        expected = rtl[rtl_name] if c_name in shift_names else 1 << rtl[rtl_name]
        assert expected == c[c_name], f"{rtl_name} != {c_name}"
