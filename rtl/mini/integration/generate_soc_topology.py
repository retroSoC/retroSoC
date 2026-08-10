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
FABRIC_LINK_NAMES = ("mgmt", "user", "dma", "rib", "apb")
FABRIC_PROTOCOLS = {
    "mgmt": "ribp",
    "user": "rib",
    "dma": "rib",
    "rib": "rib",
    "apb": "rib",
}
IRQ_GROUP_NAMES = ("ribp", "apb")
IRQ_VECTOR_WIDTH = 32
COMPATIBILITY_IRQ_BINDINGS = (
    ("clint_software", "ribp", 0, 0, "u_clint_if.software_irq_o[0]"),
    ("clint_timer", "ribp", 1, 1, "u_clint_if.timer_irq_o[0]"),
    ("uart0", "ribp", 2, 2, "uart.irq_o"),
    ("timer0", "ribp", 3, 3, "s_tim0_irq"),
    ("timer1", "ribp", 4, 4, "s_tim1_irq"),
    ("psram", "ribp", 5, 5, "psram.irq_o"),
    ("spisd", "ribp", 6, 6, "spisd.irq_o"),
    ("i2c0", "ribp", 7, 7, "i2c0.irq_o"),
    ("i2s", "ribp", 8, 8, "i2s.irq_o"),
    ("xpi", "ribp", 9, 9, "xpi.irq_o"),
    ("uart1", "apb", 0, 10, "uart.irq_o"),
    ("pwm", "apb", 1, 11, "pwm.irq_o"),
    ("ps2", "apb", 2, 12, "ps2.irq_o"),
    ("rtc", "apb", 3, 13, "u_rtc_if.irq_o"),
    ("watchdog_early_warning", "apb", 4, 14, "u_wdg_if.irq_o"),
    ("advanced_timer", "apb", 5, 15, "u_tmr_if.irq_o"),
    ("rng", "apb", 6, 16, "s_rng_irq"),
    ("ws2812", "ribp", 10, 17, "ws2812.irq_o"),
    ("gpio", "ribp", 11, 18, "gpio.irq_o"),
    ("i2c1", "ribp", 12, 19, "i2c1.irq_o"),
)


@dataclass(frozen=True)
class RIBPTarget:
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


def parse_ribp_targets(
    value: Any, memory_regions: dict[str, dict[str, Any]]
) -> list[RIBPTarget]:
    if not isinstance(value, list) or not value:
        raise ValueError("ribp_targets must be a non-empty list")
    targets: list[RIBPTarget] = []
    claimed_regions: set[str] = set()
    names: set[str] = set()
    interfaces: set[str] = set()
    slots: set[int] = set()
    for index, entry in enumerate(value):
        target = require_object(entry, f"ribp_targets[{index}]")
        slot = target.get("slot")
        if not isinstance(slot, int) or slot < 0:
            raise ValueError(f"ribp_targets[{index}].slot must be a non-negative integer")
        name = require_identifier(target.get("name"), f"ribp_targets[{index}].name")
        interface = require_identifier(
            target.get("interface"), f"ribp_targets[{index}].interface"
        )
        disabled = target.get("disabled", False)
        if not isinstance(disabled, bool):
            raise ValueError(f"ribp_targets[{index}].disabled must be boolean")
        if disabled:
            if "regions" in target:
                raise ValueError(f"ribp_targets[{index}] is disabled but declares regions")
            regions: tuple[str, ...] = ()
        else:
            regions = parse_regions(target.get("regions"), f"ribp_targets[{index}].regions")
            for region_name in regions:
                region = memory_regions.get(region_name)
                if region is None:
                    raise ValueError(
                        f"ribp_targets[{index}] references unknown region {region_name}"
                    )
                if region.get("route") != "ribp" or region.get("kind") != "active":
                    raise ValueError(
                        f"ribp_targets[{index}] region {region_name} is not an active RIBP region"
                    )
                if region_name in claimed_regions:
                    raise ValueError(f"RIBP region {region_name} has multiple targets")
                claimed_regions.add(region_name)
        if name in names:
            raise ValueError(f"RIBP target name {name} is duplicated")
        if interface in interfaces:
            raise ValueError(f"RIBP target interface {interface} is duplicated")
        if slot in slots:
            raise ValueError(f"RIBP target slot {slot} is duplicated")
        names.add(name)
        interfaces.add(interface)
        slots.add(slot)
        targets.append(RIBPTarget(slot, name, interface, regions, disabled))

    ordered = sorted(targets, key=lambda item: item.slot)
    if [target.slot for target in ordered] != list(range(len(ordered))):
        raise ValueError("RIBP target slots must be contiguous from zero")
    active_ribp_regions = {
        symbol
        for symbol, region in memory_regions.items()
        if region.get("route") == "ribp" and region.get("kind") == "active"
    }
    if claimed_regions != active_ribp_regions:
        missing = sorted(active_ribp_regions - claimed_regions)
        extra = sorted(claimed_regions - active_ribp_regions)
        details: list[str] = []
        if missing:
            details.append(f"missing {', '.join(missing)}")
        if extra:
            details.append(f"extra {', '.join(extra)}")
        raise ValueError(
            f"RIBP target regions do not cover the memory map ({'; '.join(details)})"
        )
    return ordered


def parse_apb_targets(value: Any, memory_regions: dict[str, dict[str, Any]]) -> list[ApbTarget]:
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
        region = memory_regions.get(region_name)
        if region is None:
            raise ValueError(f"apb_targets[{index}] references unknown region {region_name}")
        if region.get("route") != "apb" or region.get("kind") != "active":
            raise ValueError(
                f"apb_targets[{index}] region {region_name} is not an active APB region"
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
        targets.append(ApbTarget(slot, name, timed_interface, pure_interface, region_name))

    ordered = sorted(targets, key=lambda item: item.slot)
    if [target.slot for target in ordered] != list(range(len(ordered))):
        raise ValueError("enabled APB target slots must be contiguous from zero")
    active_regions = {
        symbol
        for symbol, region in memory_regions.items()
        if region.get("route") == "apb" and region.get("kind") == "active"
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
    list[RIBPTarget],
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
        parse_ribp_targets(document.get("ribp_targets"), memory_regions),
        parse_apb_targets(document.get("apb_targets"), memory_regions),
        parse_fabric_links(document.get("fabric_links")),
        parse_gpio_functions(document.get("gpio_alt_functions"), gpio_pins),
        irq_vector_width,
        irq_groups,
        interrupts,
    )


def render_ribp_interfaces(targets: list[RIBPTarget]) -> str:
    lines = ["// Generated by rtl/mini/integration/generate_soc_topology.py; do not edit."]
    lines.extend(f"  ribp_if {target.interface} ();" for target in targets)
    return "\n".join(lines) + "\n"


def render_region_select(region: str, memory_region: dict[str, Any]) -> str:
    base = int(require_string(memory_region.get("base"), f"memory map region {region}.base"), 0)
    if base == 0:
        return f"(ribp.addr <= `SOC_ADDR_{region}_END)"
    return f"`SOC_ADDR_IS_{region}(ribp.addr)"


def render_ribp_routes(
    targets: list[RIBPTarget], memory_regions: dict[str, dict[str, Any]]
) -> str:
    count = len(targets)
    lines = ["// Generated by rtl/mini/integration/generate_soc_topology.py; do not edit."]
    lines.extend(
        [
            f"  logic [{count - 1}:0] s_slv_sel_d, s_slv_sel_q;",
            f"  logic [{count - 1}:0] s_slv_ready;",
            f"  logic [{count - 1}:0] s_slv_resp_err;",
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
                f"  assign {target.interface}.valid = ribp.valid && (|s_{target.name}_region_sel);"
            )
        lines.extend(
            [
                f"  assign {target.interface}.addr = ribp.addr;",
                f"  assign {target.interface}.wdata = ribp.wdata;",
                f"  assign {target.interface}.wstrb = ribp.wstrb;",
                f"  assign s_slv_sel_d[{target.slot}] = {target.interface}.valid;",
                f"  assign s_slv_ready[{target.slot}] = {target.interface}.ready;",
                f"  assign s_slv_resp_err[{target.slot}] = {target.interface}.resp_err;",
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
            "  assign ribp.ready = |(s_slv_sel_q & s_slv_ready);",
            "  assign ribp.resp_err = |(s_slv_sel_q & s_slv_ready & s_slv_resp_err);",
            "",
            "  always_comb begin",
            "    ribp.rdata = '0;",
            f"    for (int index = 0; index < {count}; index++) begin",
            "      if (s_slv_sel_q[index]) begin",
            "        ribp.rdata = ribp.rdata | s_slv_rdata[index];",
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
    lines.extend(
        f"  assign s_psel_comb[{target.slot}] = `SOC_ADDR_IS_{target.region}(rib.cmd_addr);"
        for target in targets
    )
    return "\n".join(lines) + "\n"


def render_apb_response_mux(targets: list[ApbTarget]) -> str:
    lines = ["// Generated by rtl/mini/integration/generate_soc_topology.py; do not edit."]
    for signal, expression, width in (
        ("s_rd_data", "prdata", "32"),
        ("s_xfer_ready", "pready", "1"),
        ("s_xfer_error", "pslverr", "1"),
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
    }
    lines.extend(
        f"  {interface_types[link.protocol]} {link.interface} ();"
        for link in links
    )
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
        "mgmt": "mgmt_ribp",
        "user": "user_rib",
        "dma": "dma_rib",
        "rib": "rib",
        "apb": "apb_rib",
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
        targets,
        apb_targets,
        fabric_links,
        gpio_functions,
        irq_vector_width,
        irq_groups,
        interrupts,
    ) = read_topology(topology_path, memory_map_path)
    memory_regions = read_memory_regions(memory_map_path)
    rtl_dir = output_dir / "rtl"
    atomic_write(rtl_dir / "ribp_interfaces.svh", render_ribp_interfaces(targets))
    atomic_write(rtl_dir / "ribp_routes.svh", render_ribp_routes(targets, memory_regions))
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
        rtl_dir / "soc_mgmt_core_wrapper_fabric.svh",
        render_fabric_connection(fabric_links, "mgmt", "ribp"),
    )
    atomic_write(
        rtl_dir / "soc_user_core_fabric.svh",
        render_fabric_connection(fabric_links, "user", "rib"),
    )
    atomic_write(rtl_dir / "soc_bus_fabric.svh", render_bus_fabric_connections(fabric_links))
    atomic_write(
        rtl_dir / "ip_ribp_wrapper_fabric.svh",
        render_fabric_connection(fabric_links, "rib", "rib")
        + render_fabric_connection(fabric_links, "dma", "dma_rib"),
    )
    atomic_write(
        rtl_dir / "soc_ip_apb_wrapper_fabric.svh",
        render_fabric_connection(fabric_links, "apb", "rib"),
    )
    atomic_write(rtl_dir / "soc_gpio_alt_bindings.svh", render_gpio_bindings(gpio_functions))
    atomic_write(
        rtl_dir / "soc_irq_config.svh",
        render_irq_config(irq_vector_width, irq_groups, interrupts),
    )
    for group in irq_groups:
        filename = f"{group.name}_irq_bindings.svh"
        if group.name != "ribp":
            filename = f"soc_{group.name}_irq_bindings.svh"
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
