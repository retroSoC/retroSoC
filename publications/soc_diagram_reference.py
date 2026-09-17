"""Source checks for the compact, regular-weight PRODUCT functional overview."""
from __future__ import annotations

import copy
import json
import re
from pathlib import Path

from publications.circuit_reference import instance_ports
from publications.waveform_reference import uncomment

TOP = "rtl/mini/top/retrosoc.sv"
PLANE = "rtl/mini/top/soc_data_plane.sv"
PERIPH = "rtl/mini/top/apb4_periph.sv"
SYSTEM = "rtl/mini/top/apb4_system.sv"
CLOCKS = "rtl/mini/integration/clock_reset_domains.json"
TOPOLOGY = "rtl/mini/integration/soc_topology.json"
PINS = "rtl/mini/pin_map/pin_map.json"


def bound_clock(root: Path, binding: dict, domains: dict) -> str:
    ports = instance_ports(root, binding)
    if ports.get(binding["port"]) != {binding["signal"]}:
        raise ValueError("SoC diagram clock connection changed")
    for name, domain in domains.items():
        if binding["file"] == domain["path"] and binding["signal"] == domain["clock"]:
            return name
    aliases = {
        TOP: {"clk_lp_i": "lp", "clk_hp_i": "hp", "clk_hp_core_i": "hp", "clk_pclk_i": "pclk", "clk_mem_i": "memory", "clk_aud_i": "audio"},
        PLANE: {"clk_hp_i": "hp", "clk_io_i": "pclk", "clk_lp_i": "lp", "clk_mem_i": "memory"},
        PERIPH: {"clk_i": "pclk", "clk_mem_i": "memory", "clk_aud_i": "audio", "clk_ulpi_i": "usb2_ulpi"},
        SYSTEM: {"clk_i": "pclk", "clk_aud_i": "audio"},
    }
    domain = aliases.get(binding["file"], {}).get(binding["signal"])
    if domain is None:
        raise ValueError("SoC diagram has an unreviewed clock alias")
    return domain


def interface_parameter(root: Path, source: dict, parameter: str) -> int:
    text = uncomment((root / source["file"]).read_text(encoding="utf-8"))
    matches = re.findall(r"axi4_if\s*#\(([^;]+?)\)\s*" + re.escape(source["name"]) + r"(?:\s*\[[^\]]+\])*\s*\(", text, re.S)
    if len(matches) != 1:
        raise ValueError("SoC diagram interface declaration changed")
    values = re.findall(r"\." + re.escape(parameter) + r"\s*\(\s*(\d+)\s*\)", matches[0])
    if len(values) != 1:
        raise ValueError("SoC diagram requires a literal interface width")
    return int(values[0])


def validate_soc_diagram(root: Path, diagram: dict) -> None:
    if diagram["font_size_pt"] != 9 or diagram["font_weight"] != 400:
        raise ValueError("SoC diagram requires regular 9 pt text")
    sources = set(diagram["sources"])
    for source in sources:
        path = root / source
        if not path.is_file() or not path.resolve().is_relative_to(root.resolve()):
            raise ValueError("SoC diagram source missing or outside repository")
    if not {TOP, PLANE, PERIPH, SYSTEM, CLOCKS, TOPOLOGY, PINS} <= sources:
        raise ValueError("SoC diagram source inventory incomplete")
    clocks = json.loads((root / CLOCKS).read_text(encoding="utf-8"))
    domains = {row["name"]: row for row in clocks["domains"]}
    if {row["id"] for row in diagram["domains"]} != domains.keys():
        raise ValueError("SoC diagram domain inventory changed")
    topology = json.loads((root / TOPOLOGY).read_text(encoding="utf-8"))
    expected_masters = [{"index": row["index"], "name": row["name"]} for row in topology["data_master_policies"]]
    if diagram["masters"] != expected_masters:
        raise ValueError("SoC diagram master map changed")
    if diagram["pclk_parent"] != "lp" or not any(row["name"] == "lp_pclk_generated_clock" and row["relationship"] == "synchronous_generated_clock" for row in clocks["same_domain_contracts"]):
        raise ValueError("SoC diagram LP/PCLK relationship changed")
    for module, name, port, signal in [("apb4_periph", "u_apb4_periph", "clk_i", "clk_pclk_i"),
                                       ("apb4_system", "u_apb4_system", "clk_i", "clk_pclk_i"),
                                       ("soc_data_plane", "u_data_plane", "clk_io_i", "clk_pclk_i")]:
        if instance_ports(root, {"file": TOP, "module": module, "name": name}).get(port) != {signal}:
            raise ValueError("SoC diagram parent clock connection changed")
    nodes = {}
    coverage = set()
    for node in diagram["nodes"]:
        if node["id"] in nodes:
            raise ValueError("duplicate SoC diagram node")
        nodes[node["id"]] = node
        coverage.update(node.get("ips", []))
        if re.search(r"AXI(?:32|64)", node["label"]) and node["role"] not in {"bus", "bridge"}:
            raise ValueError("SoC diagram width label outside bus or bridge")
        if node.get("clock"):
            if node["clock"]["file"] not in sources or bound_clock(root, node["clock"], domains) != node["domain"]:
                raise ValueError("SoC diagram node clock domain contradicts RTL")
        elif node["role"] not in {"bus", "bridge", "io", "rail"}:
            raise ValueError("SoC diagram module lacks clock evidence")
        for part in node.get("parts", []):
            if part["domain"] != node["domain"] and (not part.get("clock") or bound_clock(root, part["clock"], domains) != part["domain"]):
                raise ValueError("SoC diagram clock-domain subcell lacks evidence")
    index = json.loads((root / "publications/datasheets/chapter-index.json").read_text(encoding="utf-8"))
    expected_ips = {row["id"] for row in index if not row["id"].startswith("mpw-")}
    if coverage != expected_ips:
        raise ValueError("SoC diagram PRODUCT IP coverage incomplete")
    instances = {"uart0", "uart1", "i2c0", "i2c1", "tim0", "tim1", "sdio0", "sdio1"}
    if not instances <= nodes.keys():
        raise ValueError("SoC diagram collapsed independently required instances")
    edges = diagram["edges"]
    for edge in edges:
        if edge["from"] not in nodes or edge["to"] not in nodes:
            raise ValueError("SoC diagram edge lacks endpoint")
        if re.search(r"AXI(?:32|64)", edge.get("label", "")):
            raise ValueError("SoC diagram repeated a width label on a wire")
    for gateway in diagram["gateways"]:
        ports = instance_ports(root, gateway["instance"])
        if any(ports.get(port) != {member["signal"]} for port, member in gateway["members"].items()):
            raise ValueError("SoC diagram gateway membership contradicts RTL")
        inputs = [edge["from"] for edge in edges if edge["to"] == gateway["id"] and edge["kind"] == "data"]
        outputs = [edge["to"] for edge in edges if edge["from"] == gateway["id"] and edge["kind"] == "data"]
        expected = [member["node"] for member in gateway["members"].values()]
        if sorted(inputs) != sorted(expected) or outputs != [gateway["bridge"]]:
            raise ValueError("SoC diagram gateway must have separate inputs and one output")
        if not any(edge["from"] == gateway["bridge"] and edge["to"] == "hp_bus" for edge in edges):
            raise ValueError("SoC diagram gateway output does not reach the HP fabric")
    for bridge in diagram["bridges"]:
        ports = instance_ports(root, bridge["instance"])
        if any(ports.get(port) != {signal} for port, signal in bridge["ports"].items()):
            raise ValueError("SoC diagram bridge source connection changed")
        for side, binding in bridge.get("widths", {}).items():
            if interface_parameter(root, binding, "DATA_WIDTH") != bridge[side]:
                raise ValueError("SoC diagram bridge width contradicts RTL")
        label = re.sub(r"\s+", "", nodes[bridge["node"]]["label"])
        expected = (f"AXI{bridge['input_bits']}→APB4" if bridge.get("output_protocol") == "APB4"
                    else f"AXI{bridge['input_bits']}→AXI{bridge['output_bits']}" if bridge["input_bits"] != bridge["output_bits"]
                    else f"AXI{bridge['input_bits']}")
        if expected not in label:
            raise ValueError("SoC diagram printed bridge width contradicts its source")
    for bus in diagram["bus_widths"]:
        width = interface_parameter(root, bus["interface"], "DATA_WIDTH")
        if width != bus["bits"] or re.findall(r"AXI(32|64)", nodes[bus["node"]]["label"]) != [str(width)]:
            raise ValueError("SoC diagram bus width label changed")
    for stream in diagram["stream_bindings"]:
        ports = instance_ports(root, stream["instance"])
        if any(ports.get(port) != {signal} for port, signal in stream["ports"].items()):
            raise ValueError("SoC diagram stream connection changed")
    for interface in diagram["interfaces"]:
        if interface["source"] not in sources or interface["node"] not in nodes:
            raise ValueError("SoC diagram interface source missing")
        text = (root / interface["source"]).read_text(encoding="utf-8")
        if not interface["tokens"] or any(token not in text for token in interface["tokens"]):
            raise ValueError("SoC diagram external signal source changed")
        if interface.get("af_prefix") and interface["af_prefix"] not in json.dumps(topology["gpio_alt_functions"]):
            raise ValueError("SoC diagram GPIO alternate-function route missing")
        if interface.get("pin_bus"):
            pin_map = json.loads((root / PINS).read_text(encoding="utf-8"))
            bus = interface["pin_bus"]
            if not any(row.get("prefix") == bus["prefix"] and row.get("count") == bus["count"] for row in pin_map["pads"]):
                raise ValueError("SoC diagram external pin-group width changed")


def collect_soc_diagram(root: Path, catalog: str, regions: list[dict]) -> dict:
    diagram = json.loads((root / catalog).read_text(encoding="utf-8"))
    validate_soc_diagram(root, diagram)
    result = copy.deepcopy(diagram)
    sram = next(row for row in regions if row["symbol"] == "SRAM")
    for node in result["nodes"]:
        node["label"] = node["label"].replace("{sram_kib}", str(sram["size"] // 1024))
    return {result["id"]: result}
