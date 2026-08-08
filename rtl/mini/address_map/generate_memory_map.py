#!/usr/bin/env python3
"""Generate RTL, SDK and linker address-map artifacts from one JSON source."""

from __future__ import annotations

import argparse
import json
import os
import tempfile
from pathlib import Path
from typing import Any


MAX_ADDRESS = 1 << 32
VALID_ROUTES = {"ribp", "apb", "ram", "reserved"}
VALID_KINDS = {"active", "reserved"}
VALID_USER_ACCESS = {"none", "ro", "rw"}
VALID_BURST = {"incr1", "incr4"}


def parse_integer(value: Any, field: str) -> int:
    if isinstance(value, int):
        return value
    if isinstance(value, str):
        try:
            return int(value, 0)
        except ValueError as error:
            raise ValueError(f"{field} must be an integer: {value!r}") from error
    raise ValueError(f"{field} must be an integer")


def read_map(path: Path) -> tuple[int, list[dict[str, Any]], list[dict[str, Any]]]:
    with path.open(encoding="utf-8") as source:
        document = json.load(source)
    if document.get("schema_version") != 1:
        raise ValueError("schema_version must be 1")
    cpu_reset = parse_integer(document.get("cpu_reset"), "cpu_reset")
    registers = document.get("sysctrl_registers")
    if not isinstance(registers, list) or not registers:
        raise ValueError("sysctrl_registers must be a non-empty list")
    normalized_registers: list[dict[str, Any]] = []
    register_symbols: set[str] = set()
    register_offsets: set[int] = set()
    for index, register in enumerate(registers):
        if not isinstance(register, dict):
            raise ValueError(f"sysctrl_registers[{index}] must be an object")
        symbol = register.get("symbol")
        if not isinstance(symbol, str) or not symbol or not symbol.replace("_", "").isalnum():
            raise ValueError(f"sysctrl_registers[{index}].symbol must be an uppercase identifier")
        if symbol != symbol.upper() or symbol in register_symbols:
            raise ValueError(f"sysctrl_registers[{index}].symbol must be unique and uppercase")
        offset = parse_integer(register.get("offset"), f"sysctrl_registers[{index}].offset")
        if offset < 0 or offset > 0xFFC or offset % 4 != 0 or offset in register_offsets:
            raise ValueError(f"sysctrl_registers[{index}].offset must be unique and 32-bit aligned")
        register_symbols.add(symbol)
        register_offsets.add(offset)
        normalized_registers.append({"symbol": symbol, "offset": offset})
    regions = document.get("regions")
    if not isinstance(regions, list) or not regions:
        raise ValueError("regions must be a non-empty list")
    normalized: list[dict[str, Any]] = []
    symbols: set[str] = set()
    for index, region in enumerate(regions):
        if not isinstance(region, dict):
            raise ValueError(f"regions[{index}] must be an object")
        symbol = region.get("symbol")
        if not isinstance(symbol, str) or not symbol or not symbol.replace("_", "").isalnum():
            raise ValueError(f"regions[{index}].symbol must be an uppercase identifier")
        if symbol != symbol.upper() or symbol in symbols:
            raise ValueError(f"regions[{index}].symbol must be unique and uppercase")
        symbols.add(symbol)
        route = region.get("route")
        kind = region.get("kind")
        if route not in VALID_ROUTES or kind not in VALID_KINDS:
            raise ValueError(f"regions[{index}] has invalid route or kind")
        if (route == "reserved") != (kind == "reserved"):
            raise ValueError(f"regions[{index}] reserved route and kind must agree")
        user_access = region.get("user_access")
        if user_access not in VALID_USER_ACCESS:
            raise ValueError(
                f"regions[{index}].user_access must be one of {sorted(VALID_USER_ACCESS)}"
            )
        if kind == "reserved" and user_access != "none":
            raise ValueError(f"regions[{index}] reserved regions must deny user access")
        burst = region.get("burst", "incr1")
        if burst not in VALID_BURST:
            raise ValueError(f"regions[{index}].burst must be one of {sorted(VALID_BURST)}")
        if kind == "reserved" and burst != "incr1":
            raise ValueError(f"regions[{index}] reserved regions cannot support INCR4")
        base = parse_integer(region.get("base"), f"regions[{index}].base")
        size = parse_integer(region.get("size"), f"regions[{index}].size")
        if base < 0 or size <= 0 or base + size > MAX_ADDRESS:
            raise ValueError(f"regions[{index}] exceeds the 32-bit address space")
        if base % 4 != 0 or size % 4 != 0:
            raise ValueError(f"regions[{index}] must be 32-bit aligned")
        normalized.append(
            {
                "symbol": symbol,
                "base": base,
                "size": size,
                "end": base + size - 1,
                "route": route,
                "kind": kind,
                "public": region.get("public", False) is True,
                "linker": region.get("linker"),
                "user_access": user_access,
                "burst": burst,
            }
        )
    previous: dict[str, Any] | None = None
    for region in sorted(normalized, key=lambda item: item["base"]):
        if previous is not None and region["base"] <= previous["end"]:
            raise ValueError(f"address-map overlap: {previous['symbol']} and {region['symbol']}")
        previous = region
    return cpu_reset, normalized, normalized_registers


def hex32(value: int) -> str:
    return f"32'h{value:08X}"


def c_hex32(value: int) -> str:
    return f"UINT32_C(0x{value:08X})"


def range_expression(symbol: str, base: int, end: int) -> str:
    conditions: list[str] = []
    if base != 0:
        conditions.append(f"(addr) >= `SOC_ADDR_{symbol}_BASE")
    if end != MAX_ADDRESS - 1:
        conditions.append(f"(addr) <= `SOC_ADDR_{symbol}_END")
    return "(" + " && ".join(conditions or ["1'b1"]) + ")"


def join_or(expressions: list[str]) -> str:
    return " || \\\n    ".join(expressions) if expressions else "1'b0"


def render_rtl(
    cpu_reset: int, regions: list[dict[str, Any]], sysctrl_registers: list[dict[str, Any]]
) -> str:
    lines = [
        "// Generated by rtl/mini/address_map/generate_memory_map.py; do not edit.",
        "`ifndef RETROSOC_GENERATED_MMAP_DEFINE_SVH",
        "`define RETROSOC_GENERATED_MMAP_DEFINE_SVH",
        "",
        f"`define SOC_CPU_RESET_ADDR {hex32(cpu_reset)}",
        "`define SOC_IRQ_START_ADDR `SOC_CPU_RESET_ADDR",
        "// Compatibility aliases for managed MPW cores.",
        "`define CPU_RESET_ADDR `SOC_CPU_RESET_ADDR",
        "`define IRQ_START_ADDR `SOC_IRQ_START_ADDR",
        "",
    ]
    for region in regions:
        symbol = region["symbol"]
        lines += [
            f"`define SOC_ADDR_{symbol}_BASE {hex32(region['base'])}",
            f"`define SOC_ADDR_{symbol}_END  {hex32(region['end'])}",
            f"`define SOC_ADDR_IS_{symbol}(addr) "
            f"{range_expression(symbol, region['base'], region['end'])}",
        ]
    lines.append("")
    for route in ("ribp", "apb", "ram", "reserved"):
        selected = [
            f"`SOC_ADDR_IS_{region['symbol']}(addr)"
            for region in regions
            if region["route"] == route
        ]
        lines.append(f"`define SOC_ADDR_IS_{route.upper()}(addr) ({join_or(selected)})")
    user_readable = [
        f"`SOC_ADDR_IS_{region['symbol']}(addr)"
        for region in regions
        if region["user_access"] in {"ro", "rw"}
    ]
    user_writable = [
        f"`SOC_ADDR_IS_{region['symbol']}(addr)"
        for region in regions
        if region["user_access"] == "rw"
    ]
    lines += [
        "",
        f"`define SOC_USER_ADDR_READABLE(addr) ({join_or(user_readable)})",
        f"`define SOC_USER_ADDR_WRITABLE(addr) ({join_or(user_writable)})",
    ]
    incr4_regions = [
        f"`SOC_ADDR_IS_{region['symbol']}(addr)"
        for region in regions
        if region["burst"] == "incr4"
    ]
    lines.append(f"`define SOC_ADDR_SUPPORTS_INCR4(addr) ({join_or(incr4_regions)})")
    lines.append("")
    for register in sysctrl_registers:
        macro = f"SOC_SYSCTRL_{register['symbol']}_OFFSET"
        lines.append(f"`define {macro:<31} {hex32(register['offset'])}")
    lines += ["", "`endif", ""]
    return "\n".join(lines)


def render_c(
    cpu_reset: int,
    regions: list[dict[str, Any]],
    sysctrl_registers: list[dict[str, Any]],
    have_sram_if: str,
) -> str:
    lines = [
        "/* Generated by rtl/mini/address_map/generate_memory_map.py; do not edit. */",
        "#ifndef RETROSOC_GENERATED_MEMORY_MAP_H",
        "#define RETROSOC_GENERATED_MEMORY_MAP_H",
        "",
        "#ifdef __ASSEMBLER__",
        "#define UINT32_C(value) value",
        "#else",
        "#include <stdint.h>",
        "#endif",
        "",
        f"#define RS_SOC_CPU_RESET_ADDR {c_hex32(cpu_reset)}",
        f"#define RS_SOC_HAS_SRAM {1 if have_sram_if == 'YES' else 0}U",
        "",
    ]
    for region in regions:
        if not region["public"]:
            continue
        symbol = region["symbol"]
        lines += [
            f"#define RS_SOC_{symbol}_BASE {c_hex32(region['base'])}",
            f"#define RS_SOC_{symbol}_SIZE {c_hex32(region['size'])}",
            f"#define RS_SOC_{symbol}_END {c_hex32(region['end'])}",
        ]
    lines.append("")
    lines.extend(
        f"#define RS_SOC_SYSCTRL_{register['symbol']}_OFFSET {c_hex32(register['offset'])}"
        for register in sysctrl_registers
    )
    lines += ["", "#endif", ""]
    return "\n".join(lines)


def render_linker(regions: list[dict[str, Any]]) -> str:
    lines = [
        "/* Generated by rtl/mini/address_map/generate_memory_map.py; do not edit. */",
        "MEMORY",
        "{",
    ]
    for region in regions:
        linker = region["linker"]
        if linker is None:
            continue
        attributes = "rx" if linker == "FLASH" else "wxa!ri"
        lines.append(
            f"  {linker} ({attributes}) : ORIGIN = 0x{region['base']:08X}, "
            f"LENGTH = 0x{region['size']:08X}"
        )
    lines += ["}", ""]
    return "\n".join(lines)


def atomic_write(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists() and path.read_text(encoding="utf-8") == content:
        return
    descriptor, temporary_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8", newline="\n") as output:
            output.write(content)
        os.replace(temporary_name, path)
    except BaseException:
        Path(temporary_name).unlink(missing_ok=True)
        raise


def generate(map_path: Path, output_dir: Path, have_sram_if: str) -> None:
    cpu_reset, regions, sysctrl_registers = read_map(map_path)
    atomic_write(
        output_dir / "rtl" / "mmap_define.svh",
        render_rtl(cpu_reset, regions, sysctrl_registers),
    )
    atomic_write(output_dir / "memory_map.fl", f"+incdir+{output_dir / 'rtl'}\n")
    atomic_write(
        output_dir / "include" / "retrosoc" / "generated" / "memory_map.h",
        render_c(cpu_reset, regions, sysctrl_registers, have_sram_if),
    )
    atomic_write(output_dir / "linker" / "memory_regions.ld", render_linker(regions))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--map", required=True, type=Path)
    parser.add_argument("--output-dir", type=Path)
    parser.add_argument("--have-sram-if", choices=("YES", "NO"), default="NO")
    parser.add_argument("--check", action="store_true", help="validate only; write nothing")
    arguments = parser.parse_args()
    try:
        if arguments.check:
            read_map(arguments.map)
        else:
            if arguments.output_dir is None:
                parser.error("--output-dir is required unless --check is used")
            generate(arguments.map, arguments.output_dir, arguments.have_sram_if)
    except (OSError, ValueError, json.JSONDecodeError) as error:
        parser.error(str(error))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
