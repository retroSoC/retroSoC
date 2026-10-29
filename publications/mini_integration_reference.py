"""Resolve the Mini publication's deployed parameters without importing Tiny data."""
from __future__ import annotations

import copy
import json
import re
from pathlib import Path

from publications.register_reference import named_argument, number, select_conditionals, strip_comments

SOURCES = (
    "configs/ci/ihp130.mk", "configs/ci/ihp130-hp.mk", "configs/ci/ihp130-apu.mk",
    "rtl/mini/top/apb4_periph.sv", "rtl/mini/integration/soc_topology.json",
    "rtl/ip/peripheral/apb4_dma.sv",
    "rtl/ip/peripheral/dma_reg.sv", "rtl/ip/peripheral/gpio_pad_caps_pkg.sv",
    "rtl/ip/multimedia/apb4_apu.sv", "rtl/ip/multimedia/apu_reg.sv",
    "rtl/ip/security/apb4_crypto.sv", "rtl/ip/security/crypto_mem_ctrl.sv",
    "rtl/ip/security/crypto_mem_pkg.sv", "crt/src/hal/crypto_lifecycle.c",
    "rtl/ip/storage/apb4_xpi.sv", "rtl/ip/storage/apb4_sdio.sv",
    "crt/src/hal/dma.c", "crt/src/hal/dma_math.c", "crt/include/retrosoc/hal/dma.h",
    "rtl/mini/top/apb4_system.sv", "rtl/mini/integration/user_extensions.json",
    "rtl/mini/integration/generate_user_extensions.py", "rtl/mini/Makefile",
    "rtl/managed/clusterip/archinfo/scripts/generate_metadata.py",
    "rtl/mini/top/resource_controller.sv", "rtl/mini/top/fabric_monitor.sv",
    "rtl/mini/top/soc_data_plane.sv",
)


def profile_values(path: Path) -> dict[str, str]:
    """Read committed literal Make profiles; never evaluate Make or shell code."""
    result: dict[str, str] = {}
    for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        line = line.split("#", 1)[0].strip()
        if not line:
            continue
        match = re.fullmatch(r"([A-Z][A-Z0-9_]*)\s*:?=\s*([A-Za-z0-9_.+-]+)", line)
        if not match:
            raise ValueError(f"unsupported profile expression at {path}:{line_number}")
        if match[1] in result:
            raise ValueError(f"duplicate profile assignment: {match[1]}")
        result[match[1]] = match[2]
    return result


def selected_profile(root: Path) -> dict[str, str]:
    config = json.loads((root / "publications/datasheets/mini.json").read_text(encoding="utf-8"))
    return profile_values(root / config["profile"])


def instance_parameters(text: str, module: str, instance: str) -> dict[str, str]:
    pattern = rf"\b{re.escape(module)}\s*(?:#\s*\(([^;]*?)\))?\s+{re.escape(instance)}\s*\("
    matches = re.findall(pattern, strip_comments(text), re.S)
    if len(matches) != 1:
        raise ValueError(f"Mini instance missing or ambiguous: {instance}")
    names = re.findall(r"\.(\w+)\s*\(", matches[0])
    if len(names) != len(set(names)):
        raise ValueError(f"duplicate Mini instance parameter: {instance}")
    return {name: named_argument(matches[0], name) for name in names}


def module_parameters(text: str, module: str, overrides: dict[str, str]) -> dict[str, int]:
    matches = re.findall(rf"\bmodule\s+{re.escape(module)}\s*#\s*\((.*?)\)\s*\(",
                         strip_comments(text), re.S)
    if len(matches) != 1:
        raise ValueError(f"Mini module parameters missing or ambiguous: {module}")
    pairs = re.findall(r"\bparameter\b[^=]*?\b(\w+)\s*=\s*([^,\n]+)", matches[0])
    if len(pairs) != len(dict(pairs)) or not overrides.keys() <= dict(pairs).keys():
        raise ValueError(f"unknown or duplicate Mini module parameter: {module}")
    expressions = dict(pairs) | overrides
    values = {}
    for _ in range(len(expressions) + 1):
        for name, expression in expressions.items():
            if name not in values:
                try:
                    values[name] = number(expression, values)
                except ValueError:
                    pass
    if values.keys() != expressions.keys():
        raise ValueError(f"unresolved Mini module parameters: {module}")
    return values


def collect_mini_bindings(root: Path, product: dict[str, str]) -> dict:
    from publications.dev_reference import apu_configurations

    expected = {"SOC": "MINI", "MINI_MODE": "PRODUCT", "PDK": "IHP130",
                "HAVE_HP": "YES",
                "HAVE_PLL": "NO", "HAVE_SRAM_IF": "YES", "HAVE_SRAM_MACRO": "YES",
                "SRAM_SIZE_KIB": "32", "EXT_CLK_HZ": "72000000", "ISA": "RV32IM"}
    if "HP_CONFIG" in product or any(product.get(key) != value for key, value in expected.items()):
        raise ValueError("Mini publication reference profile changed; review its product/ISA/SRAM binding")
    top = (root / "rtl/mini/top/apb4_periph.sv").read_text(encoding="utf-8")
    dma = module_parameters((root / "rtl/ip/peripheral/apb4_dma.sv").read_text(encoding="utf-8"),
                            "apb4_dma", instance_parameters(top, "apb4_dma", "u_apb4_dma"))
    expected_dma = {"AddrWidth": 32, "DataWidth": 32, "NumChannels": 8, "MaxBurstBeats": 16,
                    "FifoDepth": 32, "RequestMask": 0x3FFF, "SupportedRequests": 0x3FFF,
                    "IpVersion": 0x20000, "EnableStreams": 1, "EnableSpi": 0,
                    "EnableOriginQualifier": 0, "SpiTxAddress": 0, "SpiRxAddress": 0}
    if dma != expected_dma or re.search(r"\bapb4_spi\b", strip_comments(top)):
        raise ValueError("Mini DMA integration changed; Tiny SPI/PIO routes are not Mini capabilities")
    if instance_parameters(top, "apb4_xpi", "u_apb4_xpi"):
        raise ValueError("Mini XPI instance selection changed")
    topology = json.loads((root / "rtl/mini/integration/soc_topology.json").read_text(encoding="utf-8"))
    if any("xpi" in row["write_targets"] for row in topology["data_master_policies"]):
        raise ValueError("Mini XPI mapped-write permission changed")
    sdio = []
    for index in range(2):
        sdio.append(module_parameters(
            (root / "rtl/ip/storage/apb4_sdio.sv").read_text(encoding="utf-8"), "apb4_sdio",
            instance_parameters(top, "apb4_sdio", f"u_apb4_sdio{index}")))
    if any(row.get("UseRuntimeClockHz") != 0 or row.get("InputClockHz") != 72000000 for row in sdio):
        raise ValueError("Mini SDIO static clock-reporting selection changed")
    pad_source = (root / "rtl/ip/peripheral/gpio_pad_caps_pkg.sv").read_text(encoding="utf-8")
    pad_text = select_conditionals(strip_comments(pad_source), {
        "PDK_BEHAV": product.get("PDK_BEHAV") == "YES", "PDK_GF180": False,
        "PDK_ICS55": False, "PDK_SKY130": False,
    })
    pads = {name: number(value) for name, value in
            re.findall(r"localparam\s+bit\s+(\w+)\s*=\s*([^;]+);", pad_text)}
    if pads != {"HasInputCmos": 0, "HasPullUp": 0, "HasPullDown": 0}:
        raise ValueError("Mini IHP130 GPIO pad capabilities changed")
    apu = apu_configurations(root)
    system = strip_comments((root / "rtl/mini/top/apb4_system.sv").read_text(encoding="utf-8"))
    arch_parameters = instance_parameters(system, "apb4_archinfo", "u_apb4_archinfo")
    for name in ("BUILD_ID", "CONFIG_ID", "BUILD_STATUS"):
        if arch_parameters.get(name) != "`ARCHINFO_INTEGRATION_" + name:
            raise ValueError("Mini ARCHINFO generated build identity binding changed")
    for name, expression in {"TOPOLOGY": "ARCHINFO_TOPOLOGY", "FEATURES0": "ARCHINFO_FEATURES0",
                             "TECHNOLOGY": "ARCHINFO_TECHNOLOGY", "SRAM_BYTES": "ARCHINFO_SRAM_BYTES",
                             "REFERENCE_CLOCK_HZ": "`SOC_EXT_CLK_HZ"}.items():
        if arch_parameters.get(name) != expression:
            raise ValueError("Mini ARCHINFO integration parameter binding changed")
    system = select_conditionals(system, {"HAVE_PLL": False, "HAVE_SRAM_IF": True,
        "HAVE_SRAM_MACRO": True, "MINI_PRODUCT": True, "PDK_IHP130": True,
        "PDK_GF180": False, "PDK_SKY130": False, "PDK_ICS55": False})
    tokens = re.sub(r"\s+", "", system)
    requirements = (
        "localparamlogic[7:0]ARCHINFO_MGMT_HART_COUNT=8'd1;",
        "localparamlogic[7:0]ARCHINFO_GPIO_COUNT=8'd32;",
        "localparamlogic[7:0]ARCHINFO_USER_CORE_COUNT=`USER_CORE_COUNT;",
        "localparamlogic[7:0]ARCHINFO_IRQ_COUNT=`SOC_IRQ_VECTOR_WIDTH;",
        "localparamlogic[31:0]ARCHINFO_SRAM_BYTES=`SOC_ADDR_SRAM_SIZE;",
        "localparamlogic[31:0]ARCHINFO_TOPOLOGY={ARCHINFO_IRQ_COUNT,ARCHINFO_GPIO_COUNT,ARCHINFO_USER_CORE_COUNT,ARCHINFO_MGMT_HART_COUNT};",
        "32'h0000_FFF8|({24'd0,ARCHINFO_EXTENSION_COUNT}<<16)|{31'd0,ARCHINFO_HAVE_PLL}|({31'd0,ARCHINFO_HAVE_SRAM_IF}<<1)|({31'd0,ARCHINFO_HAVE_SRAM_MACRO}<<2)",
    )
    if any(value not in tokens for value in requirements):
        raise ValueError("Mini ARCHINFO topology/feature producer changed")
    flags = {name: number(value) for name, value in re.findall(
        r"localparam\s+logic\s+(ARCHINFO_HAVE_\w+)\s*=\s*([^;]+);", system)}
    if flags != {"ARCHINFO_HAVE_PLL": 0, "ARCHINFO_HAVE_SRAM_IF": 1, "ARCHINFO_HAVE_SRAM_MACRO": 1}:
        raise ValueError("Mini ARCHINFO selected feature flags changed")
    extensions = json.loads((root / "rtl/mini/integration/user_extensions.json").read_text(encoding="utf-8"))
    generator = re.sub(r"\s+", "", (root / "rtl/mini/integration/generate_user_extensions.py").read_text(encoding="utf-8"))
    if (extensions.get("mode") != "product" or len(extensions["extensions"]) != 2
            or "ExtensionMap(1,1,parsed.gpio_width,(),())ifisinstance(parsed,ProductExtensionMap)elseparsed" not in generator
            or topology["irq_vector_width"] != 64 or topology["gpio_pins"] != 32):
        raise ValueError("Mini ARCHINFO core/extension/topology inventory changed")
    technology = re.findall(r"ARCHINFO_TECHNOLOGY\s*=\s*([^;]+);", system)
    if len(technology) != 1 or number(technology[0]) != 0x02010082:
        raise ValueError("Mini ARCHINFO selected technology changed")
    archinfo = {"TOPOLOGY": (topology["irq_vector_width"] << 24) | (topology["gpio_pins"] << 16) | 1,
                "FEATURES0": 0xFFF8 | (len(extensions["extensions"]) << 16)
                | flags["ARCHINFO_HAVE_PLL"] | (flags["ARCHINFO_HAVE_SRAM_IF"] << 1)
                | (flags["ARCHINFO_HAVE_SRAM_MACRO"] << 2),
                "TECHNOLOGY": number(technology[0]), "SRAM_BYTES": int(product["SRAM_SIZE_KIB"]) * 1024,
                "REFERENCE_CLOCK_HZ": int(product["EXT_CLK_HZ"])}
    resource = module_parameters((root / "rtl/mini/top/resource_controller.sv").read_text(encoding="utf-8"),
        "resource_controller", instance_parameters(system, "resource_controller", "u_resource_controller"))
    plane = strip_comments((root / "rtl/mini/top/soc_data_plane.sv").read_text(encoding="utf-8"))
    masters = re.findall(r"localparam\s+int\s+unsigned\s+NumDataMasters\s*=\s*(\d+)\s*;", plane)
    if len(masters) != 1 or int(masters[0]) != len(topology["data_master_policies"]):
        raise ValueError("Mini monitor/data-master count changed")
    monitor_args = instance_parameters(plane, "fabric_monitor", "u_fabric_monitor")
    monitor_args = {key: str(number(value, {"NumDataMasters": int(masters[0])}))
                    for key, value in monitor_args.items()}
    monitor = module_parameters((root / "rtl/mini/top/fabric_monitor.sv").read_text(encoding="utf-8"),
                                "fabric_monitor", monitor_args)
    if resource != {"ResourceCount": 10} or monitor != {"NumMasters": 10, "NumTargets": 6}:
        raise ValueError("Mini resource/monitor instance coverage changed")
    return {"profile": product, "dma": dma, "apu": apu, "gpio": pads, "xpi_mapped_writes": False,
            "sdio": sdio, "crypto_macro": product["HAVE_SRAM_MACRO"] == "YES",
            "archinfo": archinfo, "resource": resource, "monitor": monitor, "sources": list(SOURCES)}


def bind_register_profiles(specs: dict, bindings: dict) -> dict:
    result = copy.deepcopy(specs)
    dma = bindings["dma"]
    result["dma"]["parameters"].update(dma | {"ChannelIndexWidth": 3,
                                             "supported_requests_i": dma["SupportedRequests"]})
    result["apu"]["parameters"].update({"EnableP5": 1, "EnableP7": int(bindings["apu"][0]["enabled"])})
    result["crypto"]["conditionals"] = {"HAVE_SRAM_MACRO": bindings["crypto_macro"]}
    result["gpio"]["parameters"].update(bindings["gpio"])
    result["archinfo"]["parameters"].update(bindings["archinfo"])
    for family in ("resource", "monitor"):
        result[family]["parameters"] = dict(bindings[family])
    for family, group, parameter in (("resource", "resource", "ResourceCount"),
                                     ("monitor", "master", "NumMasters"),
                                     ("monitor", "target", "NumTargets")):
        next(g for g in result[family]["groups"] if g["id"] == group)["count"] = bindings[family][parameter]
    for family in ("dma", "apu", "crypto", "gpio", "archinfo", "resource", "monitor"):
        result[family]["binding_sources"] = list(SOURCES)
    return result


def validate_register_bindings(registers: dict, bindings: dict) -> None:
    for family, group, parameter in (("dma", "ch", "NumChannels"),
                                    ("resource", "resource", "ResourceCount"),
                                    ("monitor", "master", "NumMasters"),
                                    ("monitor", "target", "NumTargets")):
        groups = [g for g in registers[family]["groups"] if g["id"] == group]
        if len(groups) != 1 or groups[0]["count"] != bindings[family][parameter]:
            raise ValueError(f"Mini register instance coverage differs from integration: {family}/{group}")
