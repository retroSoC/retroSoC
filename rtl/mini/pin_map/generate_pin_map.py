#!/usr/bin/env python3
"""Generate SoC pad declarations and platform bindings from one JSON map."""

from __future__ import annotations

import argparse
import json
import os
import re
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Any


VALID_FEATURES = {"HAVE_PLL"}
VALID_KINDS = {
    "full",
    "peripheral_output",
    "peripheral_bidir",
    "schmitt_input",
    "sdram_dq",
    "tri_input",
    "tri_output",
    "xpi_data",
    "xtal",
}
REQUIRED_PROFILES = {"fpga_mini", "tb", "verilator"}
CONNECTION_RE = re.compile(r"(?:[A-Za-z_][A-Za-z0-9_]*)(?:\[[0-9]+\])?$")
CONSTANT_RE = re.compile(r"[0-9]+'[bBdDhHoO][0-9a-fA-F_xXzZ]+$")
IHP130_POWER_PAD_COUNTS = {"vdd": 24, "vss": 24, "iovdd": 16, "iovss": 16}
POWER_CONNECTIONS = "`RETROSOC_PAD_POWER_CONNECTIONS"


@dataclass(frozen=True)
class Pad:
    name: str
    direction: str
    feature: str | None
    kind: str
    index: int | None
    signal: str | None
    input_signal: str | None
    output_signal: str | None
    output_enable_signal: str | None
    interface: str | None
    peer: str | None
    bind: bool


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


def require_string(value: Any, field: str) -> str:
    if not isinstance(value, str) or not value:
        raise ValueError(f"{field} must be a non-empty string")
    return value


def parse_feature(value: Any, field: str) -> str | None:
    if value is None:
        return None
    feature = require_string(value, field)
    if feature not in VALID_FEATURES:
        raise ValueError(f"{field} must be one of {sorted(VALID_FEATURES)}")
    return feature


def format_template(value: str | None, index: int | None, field: str) -> str | None:
    if value is None:
        return None
    if not isinstance(value, str):
        raise ValueError(f"{field} must be a string")
    if "{index}" in value:
        if index is None:
            raise ValueError(f"{field} uses {{index}} without an indexed pad")
        return value.format(index=index)
    return value


def parse_pad(entry: dict[str, Any], defaults: dict[str, Any], index: int | None) -> Pad:
    data = {**defaults, **entry}
    name = require_string(format_template(data.get("name"), index, "pad.name"), "pad.name")
    direction = require_string(data.get("direction"), f"{name}.direction")
    if direction not in {"input", "output", "inout"}:
        raise ValueError(f"{name}.direction must be input, output, or inout")
    kind = require_string(data.get("kind"), f"{name}.kind")
    if kind not in VALID_KINDS:
        raise ValueError(f"{name}.kind is not supported")
    feature = parse_feature(data.get("feature"), f"{name}.feature")
    signal = format_template(data.get("signal"), index, f"{name}.signal")
    input_signal = format_template(data.get("input"), index, f"{name}.input")
    output_signal = format_template(data.get("output"), index, f"{name}.output")
    output_enable_signal = format_template(
        data.get("output_enable"), index, f"{name}.output_enable"
    )
    interface = format_template(data.get("interface"), index, f"{name}.interface")
    peer = format_template(data.get("peer"), index, f"{name}.peer")
    bind = data.get("bind", True)
    if not isinstance(bind, bool):
        raise ValueError(f"{name}.bind must be boolean")
    if kind in {"tri_input", "schmitt_input", "tri_output", "peripheral_output"} and signal is None:
        raise ValueError(f"{name}.signal is required for {kind}")
    if kind == "full" and (interface is None or index is None):
        raise ValueError(f"{name} requires an interface and index")
    if kind in {"xpi_data", "sdram_dq"} and index is None:
        raise ValueError(f"{name} requires an index")
    if kind == "xtal" and bind and (signal is None or peer is None):
        raise ValueError(f"{name} requires signal and peer")
    if kind == "peripheral_bidir" and (
        input_signal is None or output_signal is None or output_enable_signal is None
    ):
        raise ValueError(f"{name} requires input, output, and output_enable")
    return Pad(
        name,
        direction,
        feature,
        kind,
        index,
        signal,
        input_signal,
        output_signal,
        output_enable_signal,
        interface,
        peer,
        bind,
    )


def expand_group(group: Any, index: int) -> list[Pad]:
    if not isinstance(group, dict):
        raise ValueError(f"pads[{index}] must be an object")
    defaults = {
        key: value
        for key, value in group.items()
        if key not in {"ports", "count", "prefix", "suffix"}
    }
    ports = group.get("ports")
    if ports is not None:
        if not isinstance(ports, list) or not ports:
            raise ValueError(f"pads[{index}].ports must be a non-empty list")
        if not all(isinstance(port, dict) for port in ports):
            raise ValueError(f"pads[{index}].ports entries must be objects")
        return [parse_pad(port, defaults, None) for port in ports]
    count = group.get("count")
    if not isinstance(count, int) or count <= 0:
        raise ValueError(f"pads[{index}].count must be a positive integer")
    prefix = require_string(group.get("prefix"), f"pads[{index}].prefix")
    suffix = require_string(group.get("suffix"), f"pads[{index}].suffix")
    return [
        parse_pad({"name": f"{prefix}{pad_index}{suffix}"}, defaults, pad_index)
        for pad_index in range(count)
    ]


def validate_connection(value: Any, field: str) -> str | None:
    if value is None:
        return None
    connection = require_string(value, field)
    if CONNECTION_RE.fullmatch(connection) or CONSTANT_RE.fullmatch(connection):
        return connection
    raise ValueError(f"{field} must be a signal, bit-select, constant, or null")


def read_map(path: Path) -> tuple[list[Pad], dict[str, dict[str, str | None]]]:
    with path.open(encoding="utf-8") as source:
        document = json.load(source)
    if document.get("schema_version") != 1:
        raise ValueError("schema_version must be 1")
    groups = document.get("pads")
    if not isinstance(groups, list) or not groups:
        raise ValueError("pads must be a non-empty list")
    pads: list[Pad] = []
    for index, group in enumerate(groups):
        expanded = expand_group(group, index)
        if len(expanded) == 0:
            raise ValueError(f"pads[{index}] does not expand to any pads")
        pads.extend(expanded)
    names = [pad.name for pad in pads]
    if len(names) != len(set(names)):
        raise ValueError("pad names must be unique")
    known_names = set(names)
    for pad in pads:
        if pad.peer is not None and pad.peer not in known_names:
            raise ValueError(f"{pad.name}.peer is not a known pad")
    profiles = document.get("profiles")
    if not isinstance(profiles, dict) or set(profiles) != REQUIRED_PROFILES:
        raise ValueError(f"profiles must contain exactly {sorted(REQUIRED_PROFILES)}")
    normalized_profiles: dict[str, dict[str, str | None]] = {}
    for profile, profile_data in profiles.items():
        if not isinstance(profile_data, dict):
            raise ValueError(f"profiles.{profile} must be an object")
        bindings = profile_data.get("bindings", {})
        if not isinstance(bindings, dict):
            raise ValueError(f"profiles.{profile}.bindings must be an object")
        if any(name not in known_names for name in bindings):
            raise ValueError(f"profiles.{profile} contains an unknown pad")
        normalized_profiles[profile] = {
            name: validate_connection(value, f"profiles.{profile}.bindings.{name}")
            for name, value in bindings.items()
        }
    return pads, normalized_profiles


def wrap_feature(pad: Pad, line: str) -> list[str]:
    if pad.feature is None:
        return [line]
    return [f"`ifdef {pad.feature}", line, "`endif"]


def render_ports(pads: list[Pad]) -> str:
    lines = [
        "// Generated by rtl/mini/pin_map/generate_pin_map.py; do not edit.",
        "`ifdef PDK_IHP130",
        "`ifdef USE_POWER_PINS",
        "    inout wire IOVDD,",
        "    inout wire IOVSS,",
        "    inout wire VDD,",
        "    inout wire VSS,",
        "`endif",
        "`endif",
    ]
    for index, pad in enumerate(pads):
        suffix = "," if index != len(pads) - 1 else ""
        lines.extend(wrap_feature(pad, f"    {pad.direction} {pad.name}{suffix}"))
    return "\n".join(lines) + "\n"


def render_pad_instance(pad: Pad) -> str | None:
    instance = f"u_{pad.name}"
    if pad.kind == "tri_input":
        return (
            f"  tc_io_in_pad {instance} ({POWER_CONNECTIONS}.pad({pad.name}), .p2c({pad.signal}));"
        )
    if pad.kind == "schmitt_input":
        return (
            f"  tc_io_schmitt_in_pad {instance} ({POWER_CONNECTIONS}.pad({pad.name}), "
            f".p2c({pad.signal}));"
        )
    if pad.kind == "tri_output":
        return (
            f"  tc_io_out_pad {instance} ({POWER_CONNECTIONS}.pad({pad.name}), .c2p({pad.signal}));"
        )
    if pad.kind == "peripheral_output":
        return (
            f"  tc_io_out_pad {instance} ({POWER_CONNECTIONS}.pad({pad.name}), .c2p({pad.signal}));"
        )
    if pad.kind == "peripheral_bidir":
        return (
            f"  tc_io_tri_pad {instance} ({POWER_CONNECTIONS}.pad({pad.name}), "
            f".c2p({pad.output_signal}), "
            f".c2p_en({pad.output_enable_signal}), .p2c({pad.input_signal}));"
        )
    if pad.kind == "full":
        return (
            f"  tc_io_tri_full_pad {instance} ({POWER_CONNECTIONS}.pad({pad.name}), "
            f".c2p({pad.interface}.do_o[{pad.index}]), "
            f".c2p_en({pad.interface}.oe_o[{pad.index}]), .p2c({pad.interface}.di_i[{pad.index}]), "
            f".cs({pad.interface}.cs_o[{pad.index}]), .pu({pad.interface}.pu_o[{pad.index}]), "
            f".pd({pad.interface}.pd_o[{pad.index}]));"
        )
    if pad.kind == "xpi_data":
        return (
            f"  tc_io_tri_pad {instance} ({POWER_CONNECTIONS}.pad({pad.name}), "
            f".c2p(u_xpi_if.io_do_o[{pad.index}]), "
            f".c2p_en(u_xpi_if.io_oe_o[{pad.index}]), .p2c(u_xpi_if.io_di_i[{pad.index}]));"
        )
    if pad.kind == "sdram_dq":
        return (
            f"  tc_io_tri_pad {instance} ({POWER_CONNECTIONS}.pad({pad.name}), "
            f".c2p(u_sdram_if.dq_o[{pad.index}]), "
            f".c2p_en(u_sdram_if.oe_o), .p2c(u_sdram_if.dq_i[{pad.index}]));"
        )
    if pad.kind == "xtal" and pad.bind:
        return (
            f"  tc_io_xtl_pad u_xtal_io_pad ({POWER_CONNECTIONS}.xi_pad({pad.name}), "
            f".xo_pad({pad.peer}), .en(1'b1), .clk({pad.signal}));"
        )
    return None


def render_pad_bindings(pads: list[Pad]) -> str:
    lines = [
        "// Generated by rtl/mini/pin_map/generate_pin_map.py; do not edit.",
        "`ifdef PDK_IHP130",
        "`ifdef USE_POWER_PINS",
        "`define RETROSOC_PAD_POWER_CONNECTIONS .iovdd(IOVDD), .iovss(IOVSS), .vdd(VDD), .vss(VSS),",
        "`else",
        "`define RETROSOC_PAD_POWER_CONNECTIONS",
        "`endif",
        "  generate",
    ]
    cell_suffixes = {"vdd": "Vdd", "vss": "Vss", "iovdd": "IOVdd", "iovss": "IOVss"}
    for kind, count in IHP130_POWER_PAD_COUNTS.items():
        lines.extend(
            [
                f"    for (genvar i = 0; i < {count}; i++) begin : {kind}_pads",
                '      (* keep *) (* dont_touch = "true" *)',
                f"      sg13g2_IOPad{cell_suffixes[kind]} {kind}_pad (",
                "`ifdef USE_POWER_PINS",
                "          .iovdd(IOVDD), .iovss(IOVSS), .vdd(VDD), .vss(VSS)",
                "`endif",
                "      );",
                "    end",
            ]
        )
    lines.extend(["  endgenerate", "`else", "`define RETROSOC_PAD_POWER_CONNECTIONS", "`endif"])
    for pad in pads:
        line = render_pad_instance(pad)
        if line is not None:
            lines.extend(wrap_feature(pad, line))
    lines.append("`undef RETROSOC_PAD_POWER_CONNECTIONS")
    return "\n".join(lines) + "\n"


def ihp130_pad_cell(pad: Pad) -> str | None:
    if pad.kind in {"tri_input", "schmitt_input"}:
        return "sg13g2_IOPadIn"
    if pad.kind in {"tri_output", "peripheral_output"}:
        return "sg13g2_IOPadOut4mA"
    if pad.kind in {"full", "peripheral_bidir", "sdram_dq", "xpi_data"}:
        return "sg13g2_IOPadInOut4mA"
    if pad.kind == "xtal" and pad.bind:
        return "sg13g2_IOPadIn"
    return None


def ihp130_pad_instance(pad: Pad) -> str | None:
    cell = ihp130_pad_cell(pad)
    if cell is None:
        return None
    outer = "u_xtal_io_pad" if pad.kind == "xtal" else f"u_{pad.name}"
    return f"{outer}.u_{cell}"


def render_profile_bindings(pads: list[Pad], bindings: dict[str, str | None]) -> str:
    lines = ["// Generated by rtl/mini/pin_map/generate_pin_map.py; do not edit."]
    for index, pad in enumerate(pads):
        connection = bindings.get(pad.name)
        suffix = "," if index != len(pads) - 1 else ""
        value = "" if connection is None else connection
        lines.extend(wrap_feature(pad, f"      .{pad.name}({value}){suffix}"))
    return "\n".join(lines) + "\n"


def generate(map_path: Path, output_dir: Path) -> None:
    pads, profiles = read_map(map_path)
    rtl_dir = output_dir / "rtl"
    atomic_write(rtl_dir / "retrosoc_asic_ports.svh", render_ports(pads))
    atomic_write(rtl_dir / "retrosoc_asic_pad_bindings.svh", render_pad_bindings(pads))
    for profile, bindings in profiles.items():
        atomic_write(
            rtl_dir / f"retrosoc_asic_{profile}_bindings.svh",
            render_profile_bindings(pads, bindings),
        )
    atomic_write(output_dir / "pin_map.fl", f"+incdir+{rtl_dir}\n")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--map", required=True, type=Path)
    parser.add_argument("--output-dir", type=Path)
    parser.add_argument("--check", action="store_true", help="validate only; write nothing")
    arguments = parser.parse_args()
    try:
        if arguments.check:
            read_map(arguments.map)
        else:
            if arguments.output_dir is None:
                parser.error("--output-dir is required unless --check is used")
            generate(arguments.map, arguments.output_dir)
    except (OSError, ValueError, json.JSONDecodeError) as error:
        parser.error(str(error))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
