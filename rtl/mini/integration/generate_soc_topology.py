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
FABRIC_LINK_NAMES = ("mgmt", "user", "dma", "sdio0", "sdio1", "usb2", "cfg", "system")
FABRIC_PROTOCOLS = {name: "axi4" for name in FABRIC_LINK_NAMES}
IRQ_GROUP_NAMES = ("apb4_periph", "apb4_system")
IRQ_VECTOR_WIDTH = 32
COMPATIBILITY_IRQ_BINDINGS = (
    ("clint_software", "apb4_periph", 0, 0, "u_clint_if.software_irq_o[0]"),
    ("clint_timer", "apb4_periph", 1, 1, "u_clint_if.timer_irq_o[0]"),
    ("uart0", "apb4_periph", 2, 2, "uart.irq_o"),
    ("timer0", "apb4_periph", 3, 3, "s_tim0_irq"),
    ("timer1", "apb4_periph", 4, 4, "s_tim1_irq"),
    ("psram", "apb4_periph", 5, 5, "psram.irq_o"),
    ("spisd", "apb4_periph", 6, 6, "spisd.irq_o"),
    ("i2c0", "apb4_periph", 7, 7, "i2c0.irq_o"),
    ("i2s", "apb4_periph", 8, 8, "i2s.irq_o"),
    ("xpi", "apb4_periph", 9, 9, "s_xpi_irq"),
    ("pwm", "apb4_system", 0, 11, "pwm.irq_o"),
    ("ps2", "apb4_system", 1, 12, "ps2.irq_o"),
    ("rtc", "apb4_system", 2, 13, "u_rtc_if.irq_o"),
    ("watchdog_early_warning", "apb4_system", 3, 14, "u_wdg_if.irq_o"),
    ("rng", "apb4_system", 4, 16, "s_rng_irq"),
    ("ws2812", "apb4_periph", 10, 17, "ws2812.irq_o"),
    ("gpio", "apb4_periph", 11, 18, "gpio.irq_o"),
    ("i2c1", "apb4_periph", 12, 19, "i2c1.irq_o"),
    ("dvp", "apb4_periph", 13, 15, "s_dvp_irq"),
)


@dataclass(frozen=True)
class ApbTarget:
    slot: int
    name: str
    timed_interface: str
    pure_interface: str
    regions: tuple[str, ...]
    disabled: bool = False
    external: bool = False


@dataclass(frozen=True)
class FabricLink:
    name: str
    interface: str
    protocol: str


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


@dataclass(frozen=True)
class IrqGroup:
    name: str
    width: int
    top_signal: str


@dataclass(frozen=True)
class Interrupt:
    name: str
    description: str
    group: str
    group_bit: int
    core_bit: int
    signal: str
    user_visible: bool


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


def require_comment_text(value: Any, field: str) -> str:
    text = require_string(value, field)
    if "\n" in text or "\r" in text:
        raise ValueError(f"{field} must be a single-line string")
    return text


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


def parse_apb4_island_targets(
    value: Any,
    memory_regions: dict[str, dict[str, Any]],
    field: str,
    expected_route: str,
) -> list[ApbTarget]:
    if not isinstance(value, list) or not value:
        raise ValueError(f"{field} must be a non-empty list")
    targets: list[ApbTarget] = []
    claimed_regions: set[str] = set()
    names: set[str] = set()
    timed_interfaces: set[str] = set()
    pure_interfaces: set[str] = set()
    slots: set[int] = set()
    for index, entry in enumerate(value):
        target = require_object(entry, f"{field}[{index}]")
        slot = target.get("slot")
        if not isinstance(slot, int) or slot < 0:
            raise ValueError(f"{field}[{index}].slot must be a non-negative integer")
        name = require_identifier(target.get("name"), f"{field}[{index}].name")
        timed_interface = require_identifier(
            target.get("timed_interface"), f"{field}[{index}].timed_interface"
        )
        pure_interface = require_identifier(
            target.get("pure_interface"), f"{field}[{index}].pure_interface"
        )
        disabled = target.get("disabled", False)
        if not isinstance(disabled, bool):
            raise ValueError(f"{field}[{index}].disabled must be boolean")
        if disabled:
            if "regions" in target or "region" in target:
                raise ValueError(f"{field}[{index}] is disabled but declares regions")
            regions: tuple[str, ...] = ()
        elif "regions" in target:
            regions = parse_regions(target.get("regions"), f"{field}[{index}].regions")
        else:
            region_name = require_identifier(
                target.get("region"), f"{field}[{index}].region"
            )
            regions = (region_name,)
        for region_name in regions:
            region = memory_regions.get(region_name)
            if region is None:
                raise ValueError(
                    f"{field}[{index}] references unknown region {region_name}"
                )
            if region.get("route") != expected_route or region.get("kind") != "active":
                raise ValueError(
                    f"{field}[{index}] region {region_name} is not an active "
                    f"{expected_route} region"
                )
            if region_name in claimed_regions:
                raise ValueError(f"{expected_route} region {region_name} has multiple targets")
            claimed_regions.add(region_name)
        external = target.get("external", False)
        if not isinstance(external, bool):
            raise ValueError(f"{field}[{index}].external must be boolean")
        if external and disabled:
            raise ValueError(f"{field}[{index}] cannot be both external and disabled")
        if name in names:
            raise ValueError(f"{field} target name {name} is duplicated")
        if timed_interface in timed_interfaces:
            raise ValueError(f"{field} timed interface {timed_interface} is duplicated")
        if pure_interface in pure_interfaces:
            raise ValueError(f"{field} pure interface {pure_interface} is duplicated")
        if slot in slots:
            raise ValueError(f"{field} target slot {slot} is duplicated")
        names.add(name)
        timed_interfaces.add(timed_interface)
        pure_interfaces.add(pure_interface)
        slots.add(slot)
        targets.append(
            ApbTarget(slot, name, timed_interface, pure_interface, regions, disabled, external)
        )

    ordered = sorted(targets, key=lambda item: item.slot)
    if [target.slot for target in ordered] != list(range(len(ordered))):
        raise ValueError(f"{field} slots must be contiguous from zero")
    active_regions = {
        symbol
        for symbol, region in memory_regions.items()
        if region.get("route") == expected_route and region.get("kind") == "active"
    }
    if claimed_regions != active_regions:
        missing = sorted(active_regions - claimed_regions)
        extra = sorted(claimed_regions - active_regions)
        details: list[str] = []
        if missing:
            details.append(f"missing {', '.join(missing)}")
        if extra:
            details.append(f"extra {', '.join(extra)}")
        raise ValueError(
            f"{field} regions do not cover the memory map ({'; '.join(details)})"
        )
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
        protocol = require_string(link.get("protocol"), f"fabric_links[{index}].protocol")
        if name not in FABRIC_LINK_NAMES:
            raise ValueError(f"fabric_links[{index}].name is not a supported SoC fabric role")
        if name in names:
            raise ValueError(f"SoC fabric role {name} is duplicated")
        if interface in interfaces:
            raise ValueError(f"SoC fabric interface {interface} is duplicated")
        if protocol != FABRIC_PROTOCOLS[name]:
            raise ValueError(
                f"fabric_links[{index}].protocol must be {FABRIC_PROTOCOLS[name]} for {name}"
            )
        names.add(name)
        interfaces.add(interface)
        links.append(FabricLink(name, interface, protocol))
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


def parse_irq_groups(value: Any) -> list[IrqGroup]:
    if not isinstance(value, list) or len(value) != len(IRQ_GROUP_NAMES):
        raise ValueError("irq_groups must define every supported interrupt group exactly once")
    groups: list[IrqGroup] = []
    names: set[str] = set()
    top_signals: set[str] = set()
    for index, entry in enumerate(value):
        group = require_object(entry, f"irq_groups[{index}]")
        name = require_identifier(group.get("name"), f"irq_groups[{index}].name")
        width = group.get("width")
        if not isinstance(width, int) or width <= 0:
            raise ValueError(f"irq_groups[{index}].width must be a positive integer")
        top_signal = require_identifier(group.get("top_signal"), f"irq_groups[{index}].top_signal")
        if name not in IRQ_GROUP_NAMES:
            raise ValueError(f"irq_groups[{index}].name is not a supported interrupt group")
        if name in names:
            raise ValueError(f"interrupt group {name} is duplicated")
        if top_signal in top_signals:
            raise ValueError(f"interrupt group top signal {top_signal} is duplicated")
        names.add(name)
        top_signals.add(top_signal)
        groups.append(IrqGroup(name, width, top_signal))
    if names != set(IRQ_GROUP_NAMES):
        missing = ", ".join(sorted(set(IRQ_GROUP_NAMES) - names))
        raise ValueError(f"irq_groups does not cover required groups: {missing}")
    return sorted(groups, key=lambda item: IRQ_GROUP_NAMES.index(item.name))


def parse_interrupts(value: Any, groups: list[IrqGroup], vector_width: int) -> list[Interrupt]:
    if not isinstance(value, list) or not value:
        raise ValueError("interrupts must be a non-empty list")
    group_widths = {group.name: group.width for group in groups}
    interrupts: list[Interrupt] = []
    names: set[str] = set()
    group_bits: dict[str, set[int]] = {group.name: set() for group in groups}
    core_bits: set[int] = set()
    for index, entry in enumerate(value):
        interrupt = require_object(entry, f"interrupts[{index}]")
        name = require_identifier(interrupt.get("name"), f"interrupts[{index}].name")
        description = require_comment_text(
            interrupt.get("description"), f"interrupts[{index}].description"
        )
        group = require_identifier(interrupt.get("group"), f"interrupts[{index}].group")
        group_bit = interrupt.get("group_bit")
        core_bit = interrupt.get("core_bit")
        signal = require_value(interrupt.get("signal"), f"interrupts[{index}].signal")
        user_visible = interrupt.get("user_visible", True)
        if not isinstance(user_visible, bool):
            raise ValueError(f"interrupts[{index}].user_visible must be boolean")
        if group not in group_widths:
            raise ValueError(f"interrupts[{index}].group is not a supported interrupt group")
        if not isinstance(group_bit, int) or not 0 <= group_bit < group_widths[group]:
            raise ValueError(f"interrupts[{index}].group_bit is out of range")
        if not isinstance(core_bit, int) or not 0 <= core_bit < vector_width:
            raise ValueError(f"interrupts[{index}].core_bit is out of range")
        if name in names:
            raise ValueError(f"interrupt name {name} is duplicated")
        if group_bit in group_bits[group]:
            raise ValueError(f"interrupt group {group} bit {group_bit} is duplicated")
        if core_bit in core_bits:
            raise ValueError(f"core interrupt bit {core_bit} is duplicated")
        names.add(name)
        group_bits[group].add(group_bit)
        core_bits.add(core_bit)
        interrupts.append(
            Interrupt(name, description, group, group_bit, core_bit, signal, user_visible)
        )

    for group in groups:
        expected = set(range(group.width))
        if group_bits[group.name] != expected:
            missing = sorted(expected - group_bits[group.name])
            extra = sorted(group_bits[group.name] - expected)
            details: list[str] = []
            if missing:
                details.append(f"missing {', '.join(str(bit) for bit in missing)}")
            if extra:
                details.append(f"extra {', '.join(str(bit) for bit in extra)}")
            raise ValueError(
                f"interrupt group {group.name} does not cover every group bit "
                f"({'; '.join(details)})"
            )
    return sorted(interrupts, key=lambda item: item.core_bit)


def validate_compatibility_irq_bindings(interrupts: list[Interrupt]) -> None:
    by_core_bit = {interrupt.core_bit: interrupt for interrupt in interrupts}
    for name, group, group_bit, core_bit, signal in COMPATIBILITY_IRQ_BINDINGS:
        interrupt = by_core_bit.get(core_bit)
        actual = None
        if interrupt is not None:
            actual = (
                interrupt.name,
                interrupt.group,
                interrupt.group_bit,
                interrupt.core_bit,
                interrupt.signal,
            )
        expected = (name, group, group_bit, core_bit, signal)
        if actual != expected:
            raise ValueError(f"core interrupt bit {core_bit} must retain its compatibility binding")


def read_topology(
    topology_path: Path, memory_map_path: Path
) -> tuple[
    list[ApbTarget],
    list[ApbTarget],
    list[FabricLink],
    list[GpioFunction],
    int,
    list[IrqGroup],
    list[Interrupt],
]:
    document = require_object(json.loads(topology_path.read_text(encoding="utf-8")), "topology")
    if document.get("schema_version") != 1:
        raise ValueError("schema_version must be 1")
    gpio_pins = document.get("gpio_pins")
    if not isinstance(gpio_pins, int) or gpio_pins <= 0:
        raise ValueError("gpio_pins must be a positive integer")
    irq_vector_width = document.get("irq_vector_width")
    if irq_vector_width != IRQ_VECTOR_WIDTH:
        raise ValueError(f"irq_vector_width must be {IRQ_VECTOR_WIDTH}")
    memory_regions = read_memory_regions(memory_map_path)
    irq_groups = parse_irq_groups(document.get("irq_groups"))
    interrupts = parse_interrupts(document.get("interrupts"), irq_groups, irq_vector_width)
    validate_compatibility_irq_bindings(interrupts)
    return (
        parse_apb4_island_targets(
            document.get("apb4_periph_targets"),
            memory_regions,
            "apb4_periph_targets",
            "apb4_periph",
        ),
        parse_apb4_island_targets(
            document.get("apb4_system_targets"),
            memory_regions,
            "apb4_system_targets",
            "apb4_system",
        ),
        parse_fabric_links(document.get("fabric_links")),
        parse_gpio_functions(document.get("gpio_alt_functions"), gpio_pins),
        irq_vector_width,
        irq_groups,
        interrupts,
    )


def render_apb_interfaces(targets: list[ApbTarget]) -> str:
    lines = ["// Generated by rtl/mini/integration/generate_soc_topology.py; do not edit."]
    for target in targets:
        if not target.external:
            lines.append(f"  apb4_if {target.timed_interface} (clk_i, rst_n_i);")
        lines.append(f"  apb4_pure_if {target.pure_interface} ();")
    return "\n".join(lines) + "\n"


def render_apb_bridges(targets: list[ApbTarget]) -> str:
    lines = ["// Generated by rtl/mini/integration/generate_soc_topology.py; do not edit."]
    for target in targets:
        lines.extend(
            [
                f"  apb4_if_bridge u_{target.name}_apb4_bridge (",
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
            "  logic [NSLV-1:0] s_psel_comb, s_psel_q;",
            "",
        ]
    )


def render_apb_request_routes(targets: list[ApbTarget]) -> str:
    lines = ["// Generated by rtl/mini/integration/generate_soc_topology.py; do not edit."]
    for target in targets:
        lines.extend(
            [
                f"  assign {target.name}.paddr = s_addr_q;",
                f"  assign {target.name}.pprot = '0;",
                f"  assign {target.name}.psel = s_xfer_valid && s_psel_q[{target.slot}];",
                f"  assign {target.name}.penable = s_fsm_q == FSM_ENAB;",
                f"  assign {target.name}.pwrite = s_write_q;",
                f"  assign {target.name}.pwdata = s_wdata_q;",
                f"  assign {target.name}.pstrb = s_wstrb_q;",
                "",
            ]
        )
    return "\n".join(lines) + "\n"


def render_apb_select_routes(targets: list[ApbTarget]) -> str:
    lines = ["// Generated by rtl/mini/integration/generate_soc_topology.py; do not edit."]
    for target in targets:
        if target.disabled:
            lines.append(f"  assign s_psel_comb[{target.slot}] = 1'b0;")
        else:
            terms = [
                f"`SOC_ADDR_IS_{region}(s_decode_addr)" for region in target.regions
            ]
            lines.append(
                f"  assign s_psel_comb[{target.slot}] = {' || '.join(terms)};"
            )
    return "\n".join(lines) + "\n"


def render_apb_response_mux(targets: list[ApbTarget]) -> str:
    lines = ["// Generated by rtl/mini/integration/generate_soc_topology.py; do not edit."]
    for signal, expression, width in (
        ("s_rd_data", "prdata", "32"),
        ("s_xfer_ready", "pready", "1"),
        ("s_xfer_err", "pslverr", "1"),
    ):
        terms = [
            f"({{{width}{{s_psel_q[{target.slot}]}}}} & "
            f"{target.name}.{expression})"
            for target in targets
        ]
        lines.append(f"  assign {signal} = {' | '.join(terms)};")
    return "\n".join(lines) + "\n"


def render_fabric_interfaces(links: list[FabricLink]) -> str:
    lines = ["// Generated by rtl/mini/integration/generate_soc_topology.py; do not edit."]
    interface_types = {
        "ribp": "ribp_if",
        "rib": "rib_if",
        "axi4": "axi4_if",
    }
    for link in links:
        if link.protocol == "axi4":
            lines.extend(
                [
                    "  axi4_if #(",
                    "      .ADDR_WIDTH(32),",
                    "      .DATA_WIDTH(32),",
                    "      .ID_WIDTH  (1),",
                    "      .USER_WIDTH(1)",
                    f"  ) {link.interface} (",
                    "      .aclk   (clk_i),",
                    "      .aresetn(rst_n_i)",
                    "  );",
                ]
            )
        else:
            lines.append(f"  {interface_types[link.protocol]} {link.interface} ();")
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
        "mgmt": "mgmt_axi4",
        "user": "user_axi4",
        "dma": "dma_axi4",
        "sdio0": "sdio0_axi4",
        "sdio1": "sdio1_axi4",
        "usb2": "usb2_axi4",
        "cfg": "cfg_axi4",
        "system": "system_axi4",
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


def irq_width_macro(group: IrqGroup) -> str:
    return f"SOC_IRQ_{group.name.upper()}_WIDTH"


def render_irq_config(
    vector_width: int, groups: list[IrqGroup], interrupts: list[Interrupt]
) -> str:
    user_irq_mask = sum(
        1 << interrupt.core_bit for interrupt in interrupts if interrupt.user_visible
    )
    lines = [
        "// Generated by rtl/mini/integration/generate_soc_topology.py; do not edit.",
        "`ifndef RETROSOC_SOC_IRQ_CONFIG_SVH",
        "`define RETROSOC_SOC_IRQ_CONFIG_SVH",
        "",
        f"`define SOC_IRQ_VECTOR_WIDTH {vector_width}",
        f"`define SOC_USER_IRQ_MASK {vector_width}'h{user_irq_mask:0{vector_width // 4}X}",
    ]
    lines.extend(f"`define {irq_width_macro(group)} {group.width}" for group in groups)
    lines.extend(["", "`endif"])
    return "\n".join(lines) + "\n"


def render_irq_group_bindings(group: IrqGroup, interrupts: list[Interrupt]) -> str:
    lines = ["// Generated by rtl/mini/integration/generate_soc_topology.py; do not edit."]
    for interrupt in interrupts:
        if interrupt.group != group.name:
            continue
        lines.extend(
            [
                f"  // Core IRQ {interrupt.core_bit}: {interrupt.name} ({interrupt.description}).",
                f"  assign irq_o[{interrupt.group_bit}] = {interrupt.signal};",
            ]
        )
    return "\n".join(lines) + "\n"


def render_irq_wiring(
    vector_width: int, groups: list[IrqGroup], interrupts: list[Interrupt]
) -> str:
    group_signals = {group.name: group.top_signal for group in groups}
    lines = [
        "// Generated by rtl/mini/integration/generate_soc_topology.py; do not edit.",
        "  always_comb begin",
        "    s_irq = '0;",
    ]
    for interrupt in interrupts:
        lines.extend(
            [
                f"    // {interrupt.name}: {interrupt.description}",
                f"    s_irq[{interrupt.core_bit}] = {group_signals[interrupt.group]}[{interrupt.group_bit}];",
            ]
        )
    lines.extend(["  end", ""])
    return "\n".join(lines)


def render_irq_sva(vector_width: int, groups: list[IrqGroup], interrupts: list[Interrupt]) -> str:
    group_signals = {group.name: group.top_signal for group in groups}
    lines = [
        "// Generated by rtl/mini/integration/generate_soc_topology.py; do not edit.",
        '`include "soc_irq_config.svh"',
        "",
        "module soc_irq_topology_sva (",
        "    input logic                         clk_i,",
        "    input logic                         rst_n_i,",
        "    input logic [`SOC_IRQ_VECTOR_WIDTH-1:0] irq_i,",
    ]
    lines.extend(
        f"    input logic [`{irq_width_macro(group)}-1:0] {group.name}_irq_i," for group in groups
    )
    if lines[-1].endswith(","):
        lines[-1] = lines[-1][:-1]
    lines.extend([");", ""])
    for interrupt in interrupts:
        lines.extend(
            [
                f"  // Core IRQ {interrupt.core_bit} remains bound to {interrupt.name}.",
                "  assert property (@(posedge clk_i) disable iff (!rst_n_i)",
                f"      irq_i[{interrupt.core_bit}] == {interrupt.group}_irq_i[{interrupt.group_bit}]);",
            ]
        )
    used_core_bits = {interrupt.core_bit for interrupt in interrupts}
    for core_bit in range(vector_width):
        if core_bit not in used_core_bits:
            lines.extend(
                [
                    f"  // Unallocated core IRQ {core_bit} must remain inactive.",
                    "  assert property (@(posedge clk_i) disable iff (!rst_n_i)",
                    f"      irq_i[{core_bit}] == 1'b0);",
                ]
            )
    lines.extend(
        ["", "endmodule", "", "bind retrosoc soc_irq_topology_sva u_soc_irq_topology_sva ("]
    )
    lines.extend(
        [
            "    .clk_i(clk_i),",
            "    .rst_n_i(rst_n_i),",
            "    .irq_i(s_irq),",
        ]
    )
    for index, group in enumerate(groups):
        separator = "," if index != len(groups) - 1 else ""
        lines.append(f"    .{group.name}_irq_i({group_signals[group.name]}){separator}")
    lines.append(");")
    return "\n".join(lines) + "\n"


def generate(topology_path: Path, memory_map_path: Path, output_dir: Path) -> None:
    (
        periph_targets,
        system_targets,
        fabric_links,
        gpio_functions,
        irq_vector_width,
        irq_groups,
        interrupts,
    ) = read_topology(topology_path, memory_map_path)
    rtl_dir = output_dir / "rtl"

    def write_island(prefix: str, targets: list[ApbTarget]) -> None:
        atomic_write(rtl_dir / f"{prefix}_interfaces.svh", render_apb_interfaces(targets))
        atomic_write(rtl_dir / f"{prefix}_bridges.svh", render_apb_bridges(targets))
        atomic_write(rtl_dir / f"{prefix}_ports.svh", render_apb_ports(targets))
        atomic_write(rtl_dir / f"{prefix}_connections.svh", render_apb_connections(targets))
        atomic_write(rtl_dir / f"{prefix}_declarations.svh", render_apb_declarations(targets))
        atomic_write(rtl_dir / f"{prefix}_request_routes.svh", render_apb_request_routes(targets))
        atomic_write(rtl_dir / f"{prefix}_select_routes.svh", render_apb_select_routes(targets))
        atomic_write(rtl_dir / f"{prefix}_response_mux.svh", render_apb_response_mux(targets))

    write_island("apb4_periph", periph_targets)
    write_island("apb4_system", system_targets)
    atomic_write(rtl_dir / "soc_fabric_interfaces.svh", render_fabric_interfaces(fabric_links))
    atomic_write(
        rtl_dir / "soc_mgmt_core_wrapper_fabric.svh",
        render_fabric_connection(fabric_links, "mgmt", "axi4"),
    )
    atomic_write(
        rtl_dir / "soc_user_core_fabric.svh",
        render_fabric_connection(fabric_links, "user", "axi4"),
    )
    atomic_write(rtl_dir / "soc_bus_fabric.svh", render_bus_fabric_connections(fabric_links))
    atomic_write(
        rtl_dir / "apb4_periph_fabric.svh",
        render_fabric_connection(fabric_links, "cfg", "cfg_axi4")
        + render_fabric_connection(fabric_links, "dma", "dma_axi4")
        + render_fabric_connection(fabric_links, "sdio0", "sdio0_axi4")
        + render_fabric_connection(fabric_links, "sdio1", "sdio1_axi4")
        + render_fabric_connection(fabric_links, "usb2", "usb2_axi4"),
    )
    atomic_write(
        rtl_dir / "apb4_system_fabric.svh",
        render_fabric_connection(fabric_links, "system", "axi4"),
    )
    atomic_write(rtl_dir / "soc_gpio_alt_bindings.svh", render_gpio_bindings(gpio_functions))
    atomic_write(
        rtl_dir / "soc_irq_config.svh",
        render_irq_config(irq_vector_width, irq_groups, interrupts),
    )
    for group in irq_groups:
        filename = f"{group.name}_irq_bindings.svh"
        atomic_write(
            rtl_dir / filename,
            render_irq_group_bindings(group, interrupts),
        )
    atomic_write(
        rtl_dir / "soc_irq_wiring.svh",
        render_irq_wiring(irq_vector_width, irq_groups, interrupts),
    )
    atomic_write(
        rtl_dir / "soc_irq_sva.svh",
        render_irq_sva(irq_vector_width, irq_groups, interrupts),
    )
    atomic_write(output_dir / "soc_topology.fl", f"+incdir+{rtl_dir}\n")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--map", required=True, type=Path)
    parser.add_argument("--memory-map", required=True, type=Path)
    parser.add_argument("--output-dir", type=Path)
    parser.add_argument("--check", action="store_true", help="validate only; write nothing")
    arguments = parser.parse_args()
    try:
        if arguments.check:
            read_topology(arguments.map, arguments.memory_map)
        else:
            if arguments.output_dir is None:
                parser.error("--output-dir is required unless --check is used")
            generate(arguments.map, arguments.memory_map, arguments.output_dir)
    except (OSError, ValueError, json.JSONDecodeError) as error:
        parser.error(str(error))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
