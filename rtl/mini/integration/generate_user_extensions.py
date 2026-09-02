#!/usr/bin/env python3
"""Generate scalar user core and user IP integration bindings."""

from __future__ import annotations

import argparse
import json
import os
import re
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Any


IDENTIFIER_RE = re.compile(r"[A-Za-z_][A-Za-z0-9_]*$")
APB_REQUEST_SIGNALS = ("paddr", "pprot", "psel", "penable", "pwrite", "pwdata", "pstrb")


@dataclass(frozen=True)
class ExtensionTarget:
    slot: int
    design_id: str
    module: str
    instance: str
    bus: str
    reset: str


@dataclass(frozen=True)
class ExtensionMap:
    core_selector_width: int
    ip_selector_width: int
    gpio_width: int
    core_targets: tuple[ExtensionTarget, ...]
    ip_targets: tuple[ExtensionTarget, ...]


@dataclass(frozen=True)
class ProductExtension:
    slot: int
    kind: str
    control_region: str
    irq_base: int
    irq_count: int
    data_master: bool
    stream: bool
    local_sram: bool


@dataclass(frozen=True)
class ProductExtensionMap:
    gpio_width: int
    extensions: tuple[ProductExtension, ...]


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


def require_identifier(value: Any, field: str) -> str:
    if not isinstance(value, str) or IDENTIFIER_RE.fullmatch(value) is None:
        raise ValueError(f"{field} must be a SystemVerilog identifier")
    return value


def require_positive_integer(value: Any, field: str) -> int:
    if not isinstance(value, int) or value <= 0:
        raise ValueError(f"{field} must be a positive integer")
    return value


def require_nonnegative_integer(value: Any, field: str) -> int:
    if not isinstance(value, int) or value < 0:
        raise ValueError(f"{field} must be a non-negative integer")
    return value


def parse_targets(
    value: Any, field: str, selector_width: int, first_slot: int
) -> tuple[ExtensionTarget, ...]:
    if not isinstance(value, list) or not value:
        raise ValueError(f"{field} must be a non-empty list")
    targets: list[ExtensionTarget] = []
    slots: set[int] = set()
    design_ids: set[str] = set()
    instances: set[str] = set()
    for index, entry in enumerate(value):
        target = require_object(entry, f"{field}[{index}]")
        slot = target.get("slot")
        if not isinstance(slot, int) or not first_slot <= slot < (1 << selector_width):
            raise ValueError(f"{field}[{index}].slot must be within the selector range")
        design_id = require_identifier(target.get("design_id"), f"{field}[{index}].design_id")
        module = require_identifier(target.get("module"), f"{field}[{index}].module")
        instance = require_identifier(target.get("instance"), f"{field}[{index}].instance")
        if field == "core_targets":
            bus = target.get("bus")
            if bus not in {"ribp", "rib"}:
                raise ValueError(f"{field}[{index}].bus must be ribp or rib")
            reset = target.get("reset")
            if reset not in {"sync", "async"}:
                raise ValueError(f"{field}[{index}].reset must be sync or async")
        else:
            bus = "apb"
            reset = "async"
        if slot in slots:
            raise ValueError(f"{field} slot {slot} is duplicated")
        if design_id in design_ids:
            raise ValueError(f"{field} design_id {design_id} is duplicated")
        if instance in instances:
            raise ValueError(f"{field} instance {instance} is duplicated")
        slots.add(slot)
        design_ids.add(design_id)
        instances.add(instance)
        targets.append(ExtensionTarget(slot, design_id, module, instance, bus, reset))
    ordered = tuple(sorted(targets, key=lambda item: item.slot))
    if [target.slot for target in ordered] != list(range(first_slot, first_slot + len(ordered))):
        raise ValueError(f"{field} slots must be contiguous from {first_slot}")
    return ordered


def parse_product_extensions(value: Any) -> tuple[ProductExtension, ...]:
    if not isinstance(value, list) or not value:
        raise ValueError("extensions must be a non-empty list")
    extensions: list[ProductExtension] = []
    slots: set[int] = set()
    regions: set[str] = set()
    irq_bits: set[int] = set()
    for index, entry in enumerate(value):
        extension = require_object(entry, f"extensions[{index}]")
        slot = require_nonnegative_integer(extension.get("slot"), f"extensions[{index}].slot")
        kind = extension.get("kind")
        if kind not in {"ext_l", "ext_h"}:
            raise ValueError(f"extensions[{index}].kind must be ext_l or ext_h")
        control_region = require_identifier(
            extension.get("control_region"), f"extensions[{index}].control_region"
        )
        irq_base = require_nonnegative_integer(
            extension.get("irq_base"), f"extensions[{index}].irq_base"
        )
        irq_count = require_positive_integer(
            extension.get("irq_count"), f"extensions[{index}].irq_count"
        )
        data_master = extension.get("data_master")
        stream = extension.get("stream")
        local_sram = extension.get("local_sram")
        if not all(isinstance(value, bool) for value in (data_master, stream, local_sram)):
            raise ValueError(
                f"extensions[{index}] data_master, stream, and local_sram must be boolean"
            )
        if kind == "ext_l" and (data_master or stream or local_sram):
            raise ValueError("EXT-L cannot expose a data master, stream, or local SRAM")
        if slot in slots or control_region in regions:
            raise ValueError(f"extensions[{index}] duplicates a slot or control region")
        allocated_irqs = set(range(irq_base, irq_base + irq_count))
        if allocated_irqs & irq_bits or irq_base + irq_count > 32:
            raise ValueError(f"extensions[{index}] has overlapping or out-of-range IRQs")
        slots.add(slot)
        regions.add(control_region)
        irq_bits.update(allocated_irqs)
        extensions.append(
            ProductExtension(
                slot, kind, control_region, irq_base, irq_count, data_master, stream, local_sram
            )
        )
    ordered = tuple(sorted(extensions, key=lambda item: item.slot))
    if [extension.slot for extension in ordered] != list(range(len(ordered))):
        raise ValueError("product extension slots must be contiguous from 0")
    return ordered


def read_extensions(path: Path) -> ExtensionMap | ProductExtensionMap:
    document = require_object(json.loads(path.read_text(encoding="utf-8")), "user extensions")
    schema_version = document.get("schema_version")
    if schema_version == 3:
        if document.get("mode") != "product":
            raise ValueError("schema version 3 requires mode=product")
        return ProductExtensionMap(
            require_positive_integer(document.get("gpio_width"), "gpio_width"),
            parse_product_extensions(document.get("extensions")),
        )
    if schema_version != 2:
        raise ValueError("schema_version must be 2 or 3")
    core_selector_width = require_positive_integer(
        document.get("core_selector_width"), "core_selector_width"
    )
    ip_selector_width = require_positive_integer(
        document.get("ip_selector_width"), "ip_selector_width"
    )
    gpio_width = require_positive_integer(document.get("gpio_width"), "gpio_width")
    return ExtensionMap(
        core_selector_width,
        ip_selector_width,
        gpio_width,
        parse_targets(document.get("core_targets"), "core_targets", core_selector_width, 0),
        parse_targets(document.get("ip_targets"), "ip_targets", ip_selector_width, 1),
    )


def render_core_bindings(extensions: ExtensionMap) -> str:
    lines = ["// Generated by rtl/mini/integration/generate_user_extensions.py; do not edit."]
    for target in extensions.core_targets:
        lines.extend(
            [
                f"  rib_if u_user_{target.slot}_rib_if ();",
                f"  logic [31:0] s_user_{target.slot}_irq;",
            ]
        )
        if target.bus == "ribp":
            lines.extend(
                [
                    f"  ribp_if u_user_{target.slot}_ribp_if ();",
                    "  ribp2rib #(",
                    f"      .SyncReset(1'b{int(target.reset == 'sync')})",
                    f"  ) u_user_{target.slot}_ribp2rib (",
                    "      .clk_i (clk_i),",
                    f"      .rst_n_i(rst_n_i && ~core_reset_i[{target.slot}]),",
                    f"      .ribp  (u_user_{target.slot}_ribp_if),",
                    f"      .rib   (u_user_{target.slot}_rib_if)",
                    "  );",
                ]
            )
    lines.extend(
        [
            "",
            "  always_comb begin",
            "    u_user_rib_if.cmd_valid = '0;",
            "    u_user_rib_if.cmd_addr = '0;",
            "    u_user_rib_if.cmd_write = '0;",
            "    u_user_rib_if.cmd_len = '0;",
            "    u_user_rib_if.w_valid = '0;",
            "    u_user_rib_if.wdata = '0;",
            "    u_user_rib_if.wstrb = '0;",
            "    u_user_rib_if.wlast = '0;",
            "    u_user_rib_if.rsp_ready = '0;",
        ]
    )
    for target in extensions.core_targets:
        lines.extend(
            [
                f"    u_user_{target.slot}_rib_if.cmd_ready = '0;",
                f"    u_user_{target.slot}_rib_if.w_ready = '0;",
                f"    u_user_{target.slot}_rib_if.rsp_valid = '0;",
                f"    u_user_{target.slot}_rib_if.rdata = '0;",
                f"    u_user_{target.slot}_rib_if.resp_err = '0;",
                f"    u_user_{target.slot}_rib_if.resp_code = '0;",
                f"    u_user_{target.slot}_rib_if.rsp_beat = '0;",
                f"    u_user_{target.slot}_rib_if.rsp_last = '0;",
                f"    s_user_{target.slot}_irq = '0;",
            ]
        )
    lines.append("    unique case (sel_i)")
    for target in extensions.core_targets:
        lines.extend(
            [
                f"      {extensions.core_selector_width}'d{target.slot}: begin",
                f"        u_user_rib_if.cmd_valid = u_user_{target.slot}_rib_if.cmd_valid;",
                f"        u_user_rib_if.cmd_addr = u_user_{target.slot}_rib_if.cmd_addr;",
                f"        u_user_rib_if.cmd_write = u_user_{target.slot}_rib_if.cmd_write;",
                f"        u_user_rib_if.cmd_len = u_user_{target.slot}_rib_if.cmd_len;",
                f"        u_user_rib_if.w_valid = u_user_{target.slot}_rib_if.w_valid;",
                f"        u_user_rib_if.wdata = u_user_{target.slot}_rib_if.wdata;",
                f"        u_user_rib_if.wstrb = u_user_{target.slot}_rib_if.wstrb;",
                f"        u_user_rib_if.wlast = u_user_{target.slot}_rib_if.wlast;",
                f"        u_user_rib_if.rsp_ready = u_user_{target.slot}_rib_if.rsp_ready;",
                f"        u_user_{target.slot}_rib_if.cmd_ready = u_user_rib_if.cmd_ready;",
                f"        u_user_{target.slot}_rib_if.w_ready = u_user_rib_if.w_ready;",
                f"        u_user_{target.slot}_rib_if.rsp_valid = u_user_rib_if.rsp_valid;",
                f"        u_user_{target.slot}_rib_if.rdata = u_user_rib_if.rdata;",
                f"        u_user_{target.slot}_rib_if.resp_err = u_user_rib_if.resp_err;",
                f"        u_user_{target.slot}_rib_if.resp_code = u_user_rib_if.resp_code;",
                f"        u_user_{target.slot}_rib_if.rsp_beat = u_user_rib_if.rsp_beat;",
                f"        u_user_{target.slot}_rib_if.rsp_last = u_user_rib_if.rsp_last;",
                f"        s_user_{target.slot}_irq = irq_i;",
                "      end",
            ]
        )
    lines.extend(["      default: ;", "    endcase", "  end", ""])
    for target in extensions.core_targets:
        interface = (
            f"u_user_{target.slot}_ribp_if"
            if target.bus == "ribp"
            else f"u_user_{target.slot}_rib_if"
        )
        lines.extend(
            [
                f"  // User core {target.slot} uses the {target.bus.upper()} contract.",
                f"  {target.module} #({target.slot}) {target.instance} (",
                "      .clk_i  (clk_i),",
                f"      .rst_n_i(rst_n_i && ~core_reset_i[{target.slot}]),",
                f"      .irq_i  (s_user_{target.slot}_irq),",
                f"      .{target.bus} ({interface})",
                "  );",
                "",
            ]
        )
    return "\n".join(lines)


def render_config(
    extensions: ExtensionMap, product: ProductExtensionMap | None = None
) -> str:
    extension_count = len(product.extensions) if product is not None else 0
    ext_l_count = (
        sum(extension.kind == "ext_l" for extension in product.extensions)
        if product is not None
        else 0
    )
    ext_h_count = extension_count - ext_l_count
    return "\n".join(
        [
            "// Generated by rtl/mini/integration/generate_user_extensions.py; do not edit.",
            "`ifndef RETROSOC_USER_EXTENSIONS_CONFIG_SVH",
            "`define RETROSOC_USER_EXTENSIONS_CONFIG_SVH",
            "",
            f"`define USER_CORESEL_WIDTH {extensions.core_selector_width}",
            f"`define USER_CORE_COUNT {len(extensions.core_targets)}",
            f"`define USER_CORE_STORAGE_COUNT {max(1, len(extensions.core_targets))}",
            f"`define USER_IPSEL_WIDTH {extensions.ip_selector_width}",
            f"`define USER_IP_COUNT {len(extensions.ip_targets)}",
            f"`define USER_IP_STORAGE_COUNT {max(1, len(extensions.ip_targets))}",
            f"`define USER_GPIO_NUM {extensions.gpio_width}",
            f"`define RETROSOC_EXTENSION__COUNT {extension_count}",
            f"`define RETROSOC_EXTENSION__EXT_L_COUNT {ext_l_count}",
            f"`define RETROSOC_EXTENSION__EXT_H_COUNT {ext_h_count}",
            "",
            "`endif",
            "",
        ]
    )


def render_c_config(
    extensions: ExtensionMap, product: ProductExtensionMap | None = None
) -> str:
    extension_count = len(product.extensions) if product is not None else 0
    return "\n".join(
        [
            "/* Generated by rtl/mini/integration/generate_user_extensions.py; do not edit. */",
            "#ifndef RETROSOC_GENERATED_USER_EXTENSIONS_H",
            "#define RETROSOC_GENERATED_USER_EXTENSIONS_H",
            "",
            "#include <stdint.h>",
            "",
            f"#define RS_SOC_USER_CORE_COUNT UINT32_C({len(extensions.core_targets)})",
            f"#define RS_SOC_USER_CORESEL_WIDTH UINT32_C({extensions.core_selector_width})",
            f"#define RS_SOC_USER_IP_COUNT UINT32_C({len(extensions.ip_targets)})",
            f"#define RS_SOC_EXTENSION_COUNT UINT32_C({extension_count})",
            f"#define RS_SOC_HAS_USER_CORES {int(bool(extensions.core_targets))}",
            f"#define RS_SOC_HAS_USER_IP_MUX {int(bool(extensions.ip_targets))}",
            "",
            "#endif",
            "",
        ]
    )


def render_product_config(product: ProductExtensionMap) -> str:
    lines = [
        "// Generated by rtl/mini/integration/generate_user_extensions.py; do not edit.",
        "`ifndef RETROSOC_PRODUCT_EXTENSIONS_CONFIG_SVH",
        "`define RETROSOC_PRODUCT_EXTENSIONS_CONFIG_SVH",
        "",
    ]
    for extension in product.extensions:
        prefix = f"RETROSOC_EXTENSION__SLOT{extension.slot}"
        lines.extend(
            [
                f"`define {prefix + '_KIND_EXT_H':<48} {int(extension.kind == 'ext_h')}",
                f"`define {prefix + '_IRQ_BASE':<48} {extension.irq_base}",
                f"`define {prefix + '_IRQ_COUNT':<48} {extension.irq_count}",
                f"`define {prefix + '_DATA_MASTER':<48} {int(extension.data_master)}",
                f"`define {prefix + '_STREAM':<48} {int(extension.stream)}",
                f"`define {prefix + '_LOCAL_SRAM':<48} {int(extension.local_sram)}",
            ]
        )
    lines.extend(["", "`endif", ""])
    return "\n".join(lines)


def render_product_design_info() -> str:
    return "\n".join(
        [
            "#ifndef RETROSOC_USER_DESIGN_INFO_DEF_H",
            "#define RETROSOC_USER_DESIGN_INFO_DEF_H",
            "",
            "typedef struct {",
            "    const char *name;",
            "    const char *isa;",
            "    const char *maintainer;",
            "    const char *repo;",
            "} design_info;",
            "",
            "static const design_info user_core_info[1] = {{0, 0, 0, 0}};",
            "static const design_info user_ip_info[1] = {{0, 0, 0, 0}};",
            "",
            "#endif",
            "",
        ]
    )


def render_ip_bindings(extensions: ExtensionMap) -> str:
    lines = ["// Generated by rtl/mini/integration/generate_user_extensions.py; do not edit."]
    for target in extensions.ip_targets:
        lines.extend(
            [
                f"  user_gpio_if #(`USER_GPIO_NUM) u_user_{target.slot}_gpio_if ();",
                f"  apb4_if u_user_{target.slot}_apb4_if (clk_i, rst_n_i);",
            ]
        )
    lines.extend(
        [
            "",
            "  always_comb begin",
            "    gpio.do_o = '0;",
            "    gpio.oe_o = '0;",
            "    apb.pready = '0;",
            "    apb.prdata = '0;",
            "    apb.pslverr = '0;",
        ]
    )
    for target in extensions.ip_targets:
        lines.extend(
            f"    u_user_{target.slot}_apb4_if.{signal} = '0;" for signal in APB_REQUEST_SIGNALS
        )
    lines.append("    unique case (sel_i)")
    for target in extensions.ip_targets:
        lines.extend(
            [
                f"      {extensions.ip_selector_width}'d{target.slot}: begin",
                f"        gpio.do_o = u_user_{target.slot}_gpio_if.do_o;",
                f"        gpio.oe_o = u_user_{target.slot}_gpio_if.oe_o;",
                f"        apb.pready = u_user_{target.slot}_apb4_if.pready;",
                f"        apb.prdata = u_user_{target.slot}_apb4_if.prdata;",
                f"        apb.pslverr = u_user_{target.slot}_apb4_if.pslverr;",
            ]
        )
        lines.extend(
            f"        u_user_{target.slot}_apb4_if.{signal} = apb.{signal};"
            for signal in APB_REQUEST_SIGNALS
        )
        lines.append("      end")
    lines.extend(["      default: ;", "    endcase", "  end", ""])
    for target in extensions.ip_targets:
        lines.append(f"  assign u_user_{target.slot}_gpio_if.di_i = gpio.di_i;")
    lines.append("")
    for target in extensions.ip_targets:
        lines.extend(
            [
                f"  {target.module} #({target.slot}) {target.instance} (",
                "      .clk_i  (clk_i),",
                "      .rst_n_i(rst_n_i),",
                f"      .gpio   (u_user_{target.slot}_gpio_if),",
                f"      .apb    (u_user_{target.slot}_apb4_if)",
                "  );",
                "",
            ]
        )
    return "\n".join(lines)


def generate(source: Path, output_dir: Path) -> None:
    parsed = read_extensions(source)
    product = parsed if isinstance(parsed, ProductExtensionMap) else None
    extensions = (
        ExtensionMap(1, 1, parsed.gpio_width, (), ())
        if isinstance(parsed, ProductExtensionMap)
        else parsed
    )
    rtl_dir = output_dir / "rtl"
    atomic_write(rtl_dir / "user_core_bindings.svh", render_core_bindings(extensions))
    atomic_write(rtl_dir / "user_ip_bindings.svh", render_ip_bindings(extensions))
    atomic_write(
        rtl_dir / "user_extensions_config.svh", render_config(extensions, product)
    )
    atomic_write(
        rtl_dir / "product_extensions_config.svh",
        render_product_config(product) if product is not None else "",
    )
    atomic_write(
        output_dir / "include" / "retrosoc" / "generated" / "user_extensions.h",
        render_c_config(extensions, product),
    )
    atomic_write(output_dir / "user_extensions.fl", f"+incdir+{rtl_dir}\n")
    atomic_write(output_dir / "legacy_core.fl", "")
    atomic_write(output_dir / "legacy_ip.fl", "")
    if product is not None:
        atomic_write(
            output_dir / "include" / "user_design_info.h",
            render_product_design_info(),
        )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--map", required=True, type=Path)
    parser.add_argument("--output-dir", type=Path)
    parser.add_argument("--check", action="store_true", help="validate only; write nothing")
    arguments = parser.parse_args()
    try:
        if arguments.check:
            read_extensions(arguments.map)
        else:
            if arguments.output_dir is None:
                parser.error("--output-dir is required unless --check is used")
            generate(arguments.map, arguments.output_dir)
    except (OSError, ValueError, json.JSONDecodeError) as error:
        parser.error(str(error))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
