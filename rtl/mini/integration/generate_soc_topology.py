#!/usr/bin/env python3
"""Generate Mini SoC internal integration bindings from one topology map."""

from __future__ import annotations

import argparse
import json
import os
import re
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Any


SV_IDENTIFIER_RE = re.compile(r"[A-Za-z_][A-Za-z0-9_]*$")
SV_REFERENCE_RE = re.compile(r"[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*(?:\[[0-9]+\])?$")
SV_CONSTANT_RE = re.compile(r"(?:1'[bB][01]|'[01])$")
FABRIC_LINK_NAMES = ("core", "dma", "native", "apb")


@dataclass(frozen=True)
class NativeTarget:
    slot: int
    name: str
    interface: str
    regions: tuple[str, ...]
    disabled: bool


@dataclass(frozen=True)
class ApbTarget:
    slot: int
    name: str
    timed_interface: str
    pure_interface: str
    region: str
    requires_ip: str | None


@dataclass(frozen=True)
class FabricLink:
    name: str
    interface: str


@dataclass(frozen=True)
class GpioMode:
    inputs: tuple[str, ...]
    do: str
    oe: str


@dataclass(frozen=True)
class GpioFunction:
    pin: int
    alt0: GpioMode
    alt1: GpioMode


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


def require_object(value: Any, field: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise ValueError(f"{field} must be an object")
    return value


def require_string(value: Any, field: str) -> str:
    if not isinstance(value, str) or not value:
        raise ValueError(f"{field} must be a non-empty string")
    return value


def require_identifier(value: Any, field: str) -> str:
    identifier = require_string(value, field)
    if SV_IDENTIFIER_RE.fullmatch(identifier) is None:
        raise ValueError(f"{field} must be a SystemVerilog identifier")
    return identifier


def require_reference(value: Any, field: str) -> str:
    reference = require_string(value, field)
    if SV_REFERENCE_RE.fullmatch(reference) is None:
        raise ValueError(f"{field} must be a scalar SystemVerilog reference")
    return reference


def require_value(value: Any, field: str) -> str:
    rendered = require_string(value, field)
    if SV_REFERENCE_RE.fullmatch(rendered) is None and SV_CONSTANT_RE.fullmatch(rendered) is None:
        raise ValueError(f"{field} must be a scalar SystemVerilog reference or constant")
    return rendered


def read_memory_regions(path: Path) -> dict[str, dict[str, Any]]:
    document = require_object(json.loads(path.read_text(encoding="utf-8")), "memory map")
    regions = document.get("regions")
    if not isinstance(regions, list) or not regions:
        raise ValueError("memory map regions must be a non-empty list")
    parsed: dict[str, dict[str, Any]] = {}
    for index, entry in enumerate(regions):
        region = require_object(entry, f"memory map regions[{index}]")
        symbol = require_identifier(region.get("symbol"), f"memory map regions[{index}].symbol")
        if symbol in parsed:
            raise ValueError(f"memory map region {symbol} is duplicated")
        parsed[symbol] = region
    return parsed


def parse_regions(value: Any, field: str) -> tuple[str, ...]:
    if not isinstance(value, list) or not value:
        raise ValueError(f"{field} must be a non-empty list")
    regions = tuple(require_identifier(item, f"{field} entry") for item in value)
    if len(regions) != len(set(regions)):
        raise ValueError(f"{field} contains duplicate regions")
    return regions


def parse_requires_ip(value: Any, field: str) -> str | None:
    if value is None:
        return None
    if value != "MDD":
        raise ValueError(f"{field} must be MDD when present")
    return value


def parse_native_targets(
    value: Any, memory_regions: dict[str, dict[str, Any]]
) -> list[NativeTarget]:
    if not isinstance(value, list) or not value:
        raise ValueError("native_targets must be a non-empty list")
    targets: list[NativeTarget] = []
    claimed_regions: set[str] = set()
    names: set[str] = set()
    interfaces: set[str] = set()
    slots: set[int] = set()
    for index, entry in enumerate(value):
        target = require_object(entry, f"native_targets[{index}]")
        slot = target.get("slot")
        if not isinstance(slot, int) or slot < 0:
            raise ValueError(f"native_targets[{index}].slot must be a non-negative integer")
        name = require_identifier(target.get("name"), f"native_targets[{index}].name")
        interface = require_identifier(
            target.get("interface"), f"native_targets[{index}].interface"
        )
        disabled = target.get("disabled", False)
        if not isinstance(disabled, bool):
            raise ValueError(f"native_targets[{index}].disabled must be boolean")
        if disabled:
            if "regions" in target:
                raise ValueError(f"native_targets[{index}] is disabled but declares regions")
            regions: tuple[str, ...] = ()
        else:
            regions = parse_regions(target.get("regions"), f"native_targets[{index}].regions")
            for region_name in regions:
                region = memory_regions.get(region_name)
                if region is None:
                    raise ValueError(
                        f"native_targets[{index}] references unknown region {region_name}"
                    )
                if region.get("route") != "native" or region.get("kind") != "active":
                    raise ValueError(
                        f"native_targets[{index}] region {region_name} is not an active native region"
                    )
                if region_name in claimed_regions:
                    raise ValueError(f"native region {region_name} has multiple targets")
                claimed_regions.add(region_name)
        if name in names:
            raise ValueError(f"native target name {name} is duplicated")
        if interface in interfaces:
            raise ValueError(f"native target interface {interface} is duplicated")
        if slot in slots:
            raise ValueError(f"native target slot {slot} is duplicated")
        names.add(name)
        interfaces.add(interface)
        slots.add(slot)
        targets.append(NativeTarget(slot, name, interface, regions, disabled))

    ordered = sorted(targets, key=lambda item: item.slot)
    if [target.slot for target in ordered] != list(range(len(ordered))):
        raise ValueError("native target slots must be contiguous from zero")
    active_native_regions = {
        symbol
        for symbol, region in memory_regions.items()
        if region.get("route") == "native" and region.get("kind") == "active"
    }
    if claimed_regions != active_native_regions:
        missing = sorted(active_native_regions - claimed_regions)
        extra = sorted(claimed_regions - active_native_regions)
        details: list[str] = []
        if missing:
            details.append(f"missing {', '.join(missing)}")
        if extra:
            details.append(f"extra {', '.join(extra)}")
        raise ValueError(
            f"native target regions do not cover the memory map ({'; '.join(details)})"
        )
    return ordered


def parse_apb_targets(
    value: Any, memory_regions: dict[str, dict[str, Any]], ip: str
) -> list[ApbTarget]:
    if not isinstance(value, list) or not value:
        raise ValueError("apb_targets must be a non-empty list")
    targets: list[ApbTarget] = []
    names: set[str] = set()
    timed_interfaces: set[str] = set()
    pure_interfaces: set[str] = set()
    regions: set[str] = set()
    slots: set[int] = set()
    for index, entry in enumerate(value):
        target = require_object(entry, f"apb_targets[{index}]")
        slot = target.get("slot")
        if not isinstance(slot, int) or slot < 0:
            raise ValueError(f"apb_targets[{index}].slot must be a non-negative integer")
        name = require_identifier(target.get("name"), f"apb_targets[{index}].name")
        timed_interface = require_identifier(
            target.get("timed_interface"), f"apb_targets[{index}].timed_interface"
        )
        pure_interface = require_identifier(
            target.get("pure_interface"), f"apb_targets[{index}].pure_interface"
        )
        region_name = require_identifier(target.get("region"), f"apb_targets[{index}].region")
        requires_ip = parse_requires_ip(
            target.get("requires_ip"), f"apb_targets[{index}].requires_ip"
        )
        region = memory_regions.get(region_name)
        if region is None:
            raise ValueError(f"apb_targets[{index}] references unknown region {region_name}")
        if region.get("route") != "apb" or region.get("kind") != "active":
            raise ValueError(
                f"apb_targets[{index}] region {region_name} is not an active APB region"
            )
        if requires_ip != region.get("requires_ip"):
            raise ValueError(
                f"apb_targets[{index}] requires_ip does not match region {region_name}"
            )
        if name in names:
            raise ValueError(f"APB target name {name} is duplicated")
        if timed_interface in timed_interfaces:
            raise ValueError(f"APB timed interface {timed_interface} is duplicated")
        if pure_interface in pure_interfaces:
            raise ValueError(f"APB pure interface {pure_interface} is duplicated")
        if region_name in regions:
            raise ValueError(f"APB region {region_name} has multiple targets")
        if slot in slots:
            raise ValueError(f"APB target slot {slot} is duplicated")
        names.add(name)
        timed_interfaces.add(timed_interface)
        pure_interfaces.add(pure_interface)
        regions.add(region_name)
        slots.add(slot)
        targets.append(
            ApbTarget(slot, name, timed_interface, pure_interface, region_name, requires_ip)
        )

    enabled = [
        target for target in targets if target.requires_ip is None or target.requires_ip == ip
    ]
    ordered = sorted(enabled, key=lambda item: item.slot)
    if [target.slot for target in ordered] != list(range(len(ordered))):
        raise ValueError("enabled APB target slots must be contiguous from zero")
    active_regions = {
        symbol
        for symbol, region in memory_regions.items()
        if region.get("route") == "apb"
        and region.get("kind") == "active"
        and (region.get("requires_ip") is None or region.get("requires_ip") == ip)
    }
    claimed_regions = {target.region for target in ordered}
    if claimed_regions != active_regions:
        missing = sorted(active_regions - claimed_regions)
        extra = sorted(claimed_regions - active_regions)
        details: list[str] = []
        if missing:
            details.append(f"missing {', '.join(missing)}")
        if extra:
            details.append(f"extra {', '.join(extra)}")
        raise ValueError(f"APB target regions do not cover the memory map ({'; '.join(details)})")
    return ordered


def parse_fabric_links(value: Any) -> list[FabricLink]:
    if not isinstance(value, list) or len(value) != len(FABRIC_LINK_NAMES):
        raise ValueError("fabric_links must define every SoC fabric role exactly once")
    links: list[FabricLink] = []
    names: set[str] = set()
    interfaces: set[str] = set()
    for index, entry in enumerate(value):
        link = require_object(entry, f"fabric_links[{index}]")
        name = require_identifier(link.get("name"), f"fabric_links[{index}].name")
        interface = require_identifier(link.get("interface"), f"fabric_links[{index}].interface")
        if name not in FABRIC_LINK_NAMES:
            raise ValueError(f"fabric_links[{index}].name is not a supported SoC fabric role")
        if name in names:
            raise ValueError(f"SoC fabric role {name} is duplicated")
        if interface in interfaces:
            raise ValueError(f"SoC fabric interface {interface} is duplicated")
        names.add(name)
        interfaces.add(interface)
        links.append(FabricLink(name, interface))
    if names != set(FABRIC_LINK_NAMES):
        missing = ", ".join(sorted(set(FABRIC_LINK_NAMES) - names))
        raise ValueError(f"fabric_links does not cover required roles: {missing}")
    return sorted(links, key=lambda item: FABRIC_LINK_NAMES.index(item.name))


def parse_gpio_mode(value: Any, field: str) -> GpioMode:
    mode = require_object(value, field)
    inputs_value = mode.get("inputs")
    if not isinstance(inputs_value, list):
        raise ValueError(f"{field}.inputs must be a list")
    inputs = tuple(
        require_reference(item, f"{field}.inputs[{index}]")
        for index, item in enumerate(inputs_value)
    )
    if len(inputs) != len(set(inputs)):
        raise ValueError(f"{field}.inputs contains duplicates")
    return GpioMode(
        inputs=inputs,
        do=require_value(mode.get("do"), f"{field}.do"),
        oe=require_value(mode.get("oe"), f"{field}.oe"),
    )


def parse_gpio_functions(value: Any, gpio_pins: int) -> list[GpioFunction]:
    if not isinstance(value, list) or len(value) != gpio_pins:
        raise ValueError("gpio_alt_functions must contain one entry for every GPIO pin")
    parsed: list[GpioFunction] = []
    pins: set[int] = set()
    for index, entry in enumerate(value):
        function = require_object(entry, f"gpio_alt_functions[{index}]")
        pin = function.get("pin")
        if not isinstance(pin, int) or not 0 <= pin < gpio_pins:
            raise ValueError(f"gpio_alt_functions[{index}].pin is out of range")
        if pin in pins:
            raise ValueError(f"gpio pin {pin} is duplicated")
        pins.add(pin)
        parsed.append(
            GpioFunction(
                pin=pin,
                alt0=parse_gpio_mode(function.get("alt0"), f"gpio_alt_functions[{index}].alt0"),
                alt1=parse_gpio_mode(function.get("alt1"), f"gpio_alt_functions[{index}].alt1"),
            )
        )
    if pins != set(range(gpio_pins)):
        raise ValueError("gpio_alt_functions must cover contiguous pins from zero")
    return sorted(parsed, key=lambda item: item.pin)


def read_topology(
    topology_path: Path, memory_map_path: Path, ip: str
) -> tuple[list[NativeTarget], list[ApbTarget], list[FabricLink], list[GpioFunction]]:
    document = require_object(json.loads(topology_path.read_text(encoding="utf-8")), "topology")
    if document.get("schema_version") != 1:
        raise ValueError("schema_version must be 1")
    gpio_pins = document.get("gpio_pins")
    if not isinstance(gpio_pins, int) or gpio_pins <= 0:
        raise ValueError("gpio_pins must be a positive integer")
    memory_regions = read_memory_regions(memory_map_path)
    return (
        parse_native_targets(document.get("native_targets"), memory_regions),
        parse_apb_targets(document.get("apb_targets"), memory_regions, ip),
        parse_fabric_links(document.get("fabric_links")),
        parse_gpio_functions(document.get("gpio_alt_functions"), gpio_pins),
    )


def render_nmi_interfaces(targets: list[NativeTarget]) -> str:
    lines = ["// Generated by rtl/mini/integration/generate_soc_topology.py; do not edit."]
    lines.extend(f"  nmi_if {target.interface} ();" for target in targets)
    return "\n".join(lines) + "\n"


def render_region_select(region: str, memory_region: dict[str, Any]) -> str:
    base = int(require_string(memory_region.get("base"), f"memory map region {region}.base"), 0)
    if base == 0:
        return f"(nmi.addr <= `SOC_ADDR_{region}_END)"
    return f"`SOC_ADDR_IS_{region}(nmi.addr)"


def render_nmi_routes(
    targets: list[NativeTarget], memory_regions: dict[str, dict[str, Any]]
) -> str:
    count = len(targets)
    lines = ["// Generated by rtl/mini/integration/generate_soc_topology.py; do not edit."]
    lines.extend(
        [
            f"  logic [{count - 1}:0] s_slv_sel_d, s_slv_sel_q;",
            f"  logic [{count - 1}:0] s_slv_ready;",
            f"  logic [31:0] s_slv_rdata [0:{count - 1}];",
            "",
        ]
    )
    for target in targets:
        if not target.disabled:
            lines.append(f"  logic [{len(target.regions) - 1}:0] s_{target.name}_region_sel;")
    lines.append("")
    for target in targets:
        if target.disabled:
            lines.append(f"  assign {target.interface}.valid = 1'b0;")
        else:
            for index, region in enumerate(target.regions):
                lines.append(
                    f"  assign s_{target.name}_region_sel[{index}] = "
                    f"{render_region_select(region, memory_regions[region])};"
                )
            lines.append(
                f"  assign {target.interface}.valid = nmi.valid && (|s_{target.name}_region_sel);"
            )
        lines.extend(
            [
                f"  assign {target.interface}.addr = nmi.addr;",
                f"  assign {target.interface}.wdata = nmi.wdata;",
                f"  assign {target.interface}.wstrb = nmi.wstrb;",
                f"  assign s_slv_sel_d[{target.slot}] = {target.interface}.valid;",
                f"  assign s_slv_ready[{target.slot}] = {target.interface}.ready;",
                f"  assign s_slv_rdata[{target.slot}] = {target.interface}.rdata;",
                "",
            ]
        )
    lines.extend(
        [
            f"  dffr #({count}) u_slv_sel_dffr (",
            "      clk_i,",
            "      rst_n_i,",
            "      s_slv_sel_d,",
            "      s_slv_sel_q",
            "  );",
            "",
            "  assign nmi.ready = |(s_slv_sel_q & s_slv_ready);",
            "",
            "  always_comb begin",
            "    nmi.rdata = '0;",
            f"    for (int index = 0; index < {count}; index++) begin",
            "      if (s_slv_sel_q[index]) begin",
            "        nmi.rdata = nmi.rdata | s_slv_rdata[index];",
            "      end",
            "    end",
            "  end",
        ]
    )
    return "\n".join(lines) + "\n"


def render_apb_interfaces(targets: list[ApbTarget]) -> str:
    lines = ["// Generated by rtl/mini/integration/generate_soc_topology.py; do not edit."]
    for target in targets:
        lines.extend(
            [
                f"  apb4_if {target.timed_interface} (clk_i, rst_n_i);",
                f"  apb4_pure_if {target.pure_interface} ();",
            ]
        )
    return "\n".join(lines) + "\n"


def render_apb_bridges(targets: list[ApbTarget]) -> str:
    lines = ["// Generated by rtl/mini/integration/generate_soc_topology.py; do not edit."]
    for target in targets:
        lines.extend(
            [
                f"  apb4_if_bridge u_{target.name}_apb_bridge (",
                f"      .apb_pure({target.pure_interface}),",
                f"      .timed   ({target.timed_interface})",
                "  );",
                "",
            ]
        )
    return "\n".join(lines) + "\n"


def render_apb_ports(targets: list[ApbTarget]) -> str:
    lines = ["// Generated by rtl/mini/integration/generate_soc_topology.py; do not edit."]
    for index, target in enumerate(targets):
        separator = "," if index != len(targets) - 1 else ""
        lines.append(f"    apb4_pure_if.master {target.name}{separator}")
    return "\n".join(lines) + "\n"


def render_apb_connections(targets: list[ApbTarget]) -> str:
    lines = ["// Generated by rtl/mini/integration/generate_soc_topology.py; do not edit."]
    for index, target in enumerate(targets):
        separator = "," if index != len(targets) - 1 else ""
        lines.append(f"      .{target.name}({target.pure_interface}){separator}")
    return "\n".join(lines) + "\n"


def render_apb_declarations(targets: list[ApbTarget]) -> str:
    count = len(targets)
    return "\n".join(
        [
            "// Generated by rtl/mini/integration/generate_soc_topology.py; do not edit.",
            f"  localparam int NSLV = {count};",
            "  logic [NSLV-1:0] s_psel_comb, s_psel_d, s_psel_q;",
            "",
        ]
    )


def render_apb_request_routes(targets: list[ApbTarget]) -> str:
    lines = ["// Generated by rtl/mini/integration/generate_soc_topology.py; do not edit."]
    for target in targets:
        lines.extend(
            [
                f"  assign {target.name}.paddr = nmi.addr;",
                f"  assign {target.name}.pprot = '0;",
                f"  assign {target.name}.psel = s_xfer_valid && `SOC_ADDR_IS_{target.region}(nmi.addr);",
                f"  assign {target.name}.penable = s_fsm_q == FSM_ENAB;",
                f"  assign {target.name}.pwrite = |nmi.wstrb;",
                f"  assign {target.name}.pwdata = nmi.wdata;",
                f"  assign {target.name}.pstrb = nmi.wstrb;",
                "",
            ]
        )
    return "\n".join(lines) + "\n"


def render_apb_select_routes(targets: list[ApbTarget]) -> str:
    lines = ["// Generated by rtl/mini/integration/generate_soc_topology.py; do not edit."]
    lines.extend(
        f"  assign s_psel_comb[{target.slot}] = `SOC_ADDR_IS_{target.region}(nmi.addr);"
        for target in targets
    )
    return "\n".join(lines) + "\n"


def render_apb_response_mux(targets: list[ApbTarget]) -> str:
    lines = ["// Generated by rtl/mini/integration/generate_soc_topology.py; do not edit."]
    for signal, expression in (("s_rd_data", "prdata"), ("s_xfer_ready", "pready")):
        terms = [
            f"({{{'32' if signal == 's_rd_data' else '1'}{{s_psel_q[{target.slot}]}}}} & "
            f"{target.name}.{expression})"
            for target in targets
        ]
        lines.append(f"  assign {signal} = {' | '.join(terms)};")
    return "\n".join(lines) + "\n"


def render_fabric_interfaces(links: list[FabricLink]) -> str:
    lines = ["// Generated by rtl/mini/integration/generate_soc_topology.py; do not edit."]
    lines.extend(f"  nmi_if {link.interface} ();" for link in links)
    return "\n".join(lines) + "\n"


def render_fabric_connection(links: list[FabricLink], name: str, port: str) -> str:
    interface = next(link.interface for link in links if link.name == name)
    return "\n".join(
        [
            "// Generated by rtl/mini/integration/generate_soc_topology.py; do not edit.",
            f"      .{port}({interface}),",
            "",
        ]
    )


def render_bus_fabric_connections(links: list[FabricLink]) -> str:
    port_names = {
        "core": "core_nmi",
        "dma": "dma_nmi",
        "native": "natv_nmi",
        "apb": "apb_nmi",
    }
    interfaces = {link.name: link.interface for link in links}
    lines = ["// Generated by rtl/mini/integration/generate_soc_topology.py; do not edit."]
    lines.extend(f"      .{port_names[name]}({interfaces[name]})," for name in FABRIC_LINK_NAMES)
    return "\n".join(lines) + "\n"


def render_gpio_bindings(functions: list[GpioFunction]) -> str:
    lines = ["// Generated by rtl/mini/integration/generate_soc_topology.py; do not edit."]
    for function in functions:
        for mode_name, mode in (("alt0", function.alt0), ("alt1", function.alt1)):
            lines.append(f"  // GPIO{function.pin} {mode_name}")
            lines.extend(
                f"  assign {input_signal} = u_gpio_if.di_i[{function.pin}];"
                for input_signal in mode.inputs
            )
            lines.extend(
                [
                    f"  assign u_gpio_if.{mode_name}_do_i[{function.pin}] = {mode.do};",
                    f"  assign u_gpio_if.{mode_name}_oe_i[{function.pin}] = {mode.oe};",
                    "",
                ]
            )
    return "\n".join(lines) + "\n"


def generate(topology_path: Path, memory_map_path: Path, output_dir: Path, ip: str) -> None:
    targets, apb_targets, fabric_links, gpio_functions = read_topology(
        topology_path, memory_map_path, ip
    )
    memory_regions = read_memory_regions(memory_map_path)
    rtl_dir = output_dir / "rtl"
    atomic_write(rtl_dir / "soc_nmi_interfaces.svh", render_nmi_interfaces(targets))
    atomic_write(rtl_dir / "soc_nmi_routes.svh", render_nmi_routes(targets, memory_regions))
    atomic_write(rtl_dir / "soc_apb_interfaces.svh", render_apb_interfaces(apb_targets))
    atomic_write(rtl_dir / "soc_apb_bridges.svh", render_apb_bridges(apb_targets))
    atomic_write(rtl_dir / "soc_apb_ports.svh", render_apb_ports(apb_targets))
    atomic_write(rtl_dir / "soc_apb_connections.svh", render_apb_connections(apb_targets))
    atomic_write(rtl_dir / "soc_apb_declarations.svh", render_apb_declarations(apb_targets))
    atomic_write(rtl_dir / "soc_apb_request_routes.svh", render_apb_request_routes(apb_targets))
    atomic_write(rtl_dir / "soc_apb_select_routes.svh", render_apb_select_routes(apb_targets))
    atomic_write(rtl_dir / "soc_apb_response_mux.svh", render_apb_response_mux(apb_targets))
    atomic_write(rtl_dir / "soc_fabric_interfaces.svh", render_fabric_interfaces(fabric_links))
    atomic_write(
        rtl_dir / "soc_core_wrapper_fabric.svh",
        render_fabric_connection(fabric_links, "core", "nmi"),
    )
    atomic_write(rtl_dir / "soc_bus_fabric.svh", render_bus_fabric_connections(fabric_links))
    atomic_write(
        rtl_dir / "soc_ip_nmi_wrapper_fabric.svh",
        render_fabric_connection(fabric_links, "native", "nmi")
        + render_fabric_connection(fabric_links, "dma", "dma_nmi"),
    )
    atomic_write(
        rtl_dir / "soc_ip_apb_wrapper_fabric.svh",
        render_fabric_connection(fabric_links, "apb", "nmi"),
    )
    atomic_write(rtl_dir / "soc_gpio_alt_bindings.svh", render_gpio_bindings(gpio_functions))
    atomic_write(output_dir / "soc_topology.fl", f"+incdir+{rtl_dir}\n")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--map", required=True, type=Path)
    parser.add_argument("--memory-map", required=True, type=Path)
    parser.add_argument("--output-dir", type=Path)
    parser.add_argument("--ip", choices=("NONE", "MDD"), default="NONE")
    parser.add_argument("--check", action="store_true", help="validate only; write nothing")
    arguments = parser.parse_args()
    try:
        if arguments.check:
            read_topology(arguments.map, arguments.memory_map, arguments.ip)
        else:
            if arguments.output_dir is None:
                parser.error("--output-dir is required unless --check is used")
            generate(arguments.map, arguments.memory_map, arguments.output_dir, arguments.ip)
    except (OSError, ValueError, json.JSONDecodeError) as error:
        parser.error(str(error))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
