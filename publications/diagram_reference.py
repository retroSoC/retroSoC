"""Source-bound data for representative field, instruction, memory and circuit diagrams."""
from __future__ import annotations

import copy
import importlib.util
import json
import re
import sys
from pathlib import Path

from publications.implementation_reference import without_comments
from publications.register_reference import number
from publications.circuit_reference import validate_instance_connections
from publications.instruction_reference import instruction_families
from publications.format_reference import collect_layouts
from publications.storage_reference import collect_storage


def dependencies(spec: dict) -> set[str]:
    paths = set(spec.get("sources", []))
    for binding in spec.get("bindings", []):
        paths.add(binding["file"])
    for circuit in spec.get("circuits", {}).values():
        for node in circuit["nodes"]:
            paths.update(node.get("sources", []))
        for edge in circuit["edges"]:
            paths.update(binding["file"] for binding in edge["bindings"])
    return paths


def validate_bindings(root: Path, bindings: list[dict]) -> None:
    for binding in bindings:
        source = (root / binding["file"]).read_text(encoding="utf-8")
        if re.sub(r"\s+", "", without_comments(binding["text"])) not in re.sub(r"\s+", "", without_comments(source)):
            raise ValueError(f"diagram source binding changed: {binding['file']}")


def validate_fields(fields: list[dict], total_bits: int) -> None:
    occupied, names = set(), set()
    for field in fields:
        name, lsb, bits = field["name"], field["lsb"], field["bits"]
        if name in names or type(lsb) is not int or type(bits) is not int or lsb < 0 or bits < 1:
            raise ValueError("invalid or duplicate diagram field")
        positions = set(range(lsb, lsb + bits))
        if occupied & positions or max(positions) >= total_bits:
            raise ValueError("diagram fields overlap or exceed the layout")
        names.add(name)
        occupied.update(positions)
    if occupied != set(range(total_bits)):
        raise ValueError("diagram layout has undocumented gaps")


def dma_fields(root: Path) -> list[dict]:
    source = (root / "crt/include/retrosoc/hal/dma.h").read_text(encoding="utf-8")
    matches = re.findall(r"typedef\s+struct\s*\{([^}]+)\}\s*rs_dma_tcd_t\s*;", source)
    if len(matches) != 1:
        raise ValueError("DMA TCD structure missing or ambiguous")
    members = re.findall(r"(u?int)(16|32)_t\s+(\w+)\s*;", matches[0])
    if re.sub(r"(?:u?int)(?:16|32)_t\s+\w+\s*;", "", matches[0]).strip():
        raise ValueError("unreviewed DMA TCD member type")
    fields, offset = [], 0
    for signed, width, name in members:
        bits = int(width)
        role = "reserved" if name.startswith("reserved") else "writeback" if name in {
            "crc_result", "status", "bytes_done", "error_status"} else "configuration"
        fields.append({"name": name, "lsb": offset * 8, "bits": bits, "offset": offset,
                       "role": role, "signed": signed == "int"})
        offset += bits // 8
    validate_fields(fields, 512)
    return fields


def apu_formats(root: Path) -> dict:
    path = root / "scripts/apu_isa.py"
    source = path.read_text(encoding="utf-8")
    declarations = re.findall(r"\(self\.(\w+),\s*(\d+),\s*(\d+)\)", source)
    aliases = {"instruction_class": "class", "opcode": "opcode", "predicate": "predicate",
               "dst": "dst", "src0": "src0", "src1": "src1", "aux": "aux", "immediate": "immediate"}
    if len(declarations) != 8 or {row[0] for row in declarations} != aliases.keys():
        raise ValueError("APU encoder field inventory changed")
    rtl = (root / "rtl/ip/multimedia/apu_microcode_pkg.sv").read_text(encoding="utf-8")
    fields = []
    for name, width, shift in declarations:
        bits, lsb = int(width), int(shift)
        slices = set(re.findall(r"s_" + aliases[name] + r"\s*=\s*instruction_i\[(\d+):(\d+)\]", rtl))
        if slices != {(str(lsb + bits - 1), str(lsb))}:
            raise ValueError("APU encoder/RTL diagram slice mismatch")
        fields.append({"name": name, "label": aliases[name].upper(), "bits": bits, "lsb": lsb})
    validate_fields(fields, 64)
    spec = importlib.util.spec_from_file_location("publication_apu_diagram_isa", path)
    if spec is None or spec.loader is None:
        raise ValueError("APU encoder could not be loaded")
    isa = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = isa
    spec.loader.exec_module(isa)
    defines = (root / "rtl/ip/multimedia/apu_define.svh").read_text(encoding="utf-8")
    for suffix, value in (("CLASS_CONTROL", int(isa.InstructionClass.CONTROL)),
                          ("CLASS_SCALAR", int(isa.InstructionClass.SCALAR)),
                          ("CONTROL_WAIT", int(isa.ControlOpcode.WAIT)),
                          ("SCALAR_MOVI", int(isa.ScalarOpcode.MOVI)),
                          ("PRED_ALWAYS", 0)):
        found = re.findall(r"^`define\s+APB4_APU__MC_" + suffix + r"\s+(\S+)", defines, re.M)
        if len(found) != 1 or number(found[0]) != value:
            raise ValueError("APU example opcode/predicate differs from RTL")
    maximum = re.findall(r"^`define\s+APB4_APU__APUMC_MAX_INSTRUCTIONS\s+(\d+)", defines, re.M)
    if maximum != [str(isa.APUMC_MAX_INSTRUCTIONS)]:
        raise ValueError("APU control-store capacity differs from the encoder")
    instructions = (
        ("SCALAR.MOVI: r1 = 0x12345678", isa.Instruction(int(isa.InstructionClass.SCALAR), int(isa.ScalarOpcode.MOVI), dst=1, immediate=0x12345678)),
        ("CONTROL.WAIT: DMA source", isa.Instruction(int(isa.InstructionClass.CONTROL), int(isa.ControlOpcode.WAIT), aux=isa.WAIT_SOURCES.index("dma"))),
    )
    examples = []
    for title, instruction in instructions:
        word = instruction.encode()
        if isa.Instruction.decode(word) != instruction:
            raise ValueError("APU instruction diagram failed round-trip encoding")
        examples.append({"title": title, "word": f"0x{word:016X}",
                         "values": {name: getattr(instruction, name) for name in aliases}})
    return {"bits": 64, "fields": fields, "examples": examples, "max_instructions": isa.APUMC_MAX_INSTRUCTIONS,
            "families": instruction_families(isa, defines)}


def uart_fifo(root: Path) -> dict:
    source = (root / "rtl/ip/serial/uart_reg.sv").read_text(encoding="utf-8")
    result = {}
    for direction in ("Tx", "Rx"):
        depth = re.findall(r"parameter\s+int\s+" + direction + r"FifoDepth\s*=\s*(\d+)", source)
        fifo = re.findall(r"fifo\s*#\s*\((.*?)\)\s+u_" + direction.lower() + r"_fifo\s*\(", source, re.S)
        if len(depth) != 1 or len(fifo) != 1:
            raise ValueError("UART FIFO instance missing or ambiguous")
        # Select the final declaration before the named instance, not a preceding FIFO.
        widths = re.findall(r"\.DATA_WIDTH\s*\((\d+)\)", fifo[0])
        result[direction.lower()] = {"depth": int(depth[0]), "bits": int(widths[-1])}
    if result != {"tx": {"depth": 64, "bits": 8}, "rx": {"depth": 64, "bits": 12}}:
        raise ValueError("review UART storage diagram after FIFO geometry change")
    return result


def validate_circuit(root: Path, circuit: dict) -> None:
    nodes, ports = {}, {}
    for node in circuit["nodes"]:
        if node["id"] in nodes:
            raise ValueError("duplicate circuit node")
        nodes[node["id"]] = node
        if not node.get("sources") or not node.get("title"):
            raise ValueError("circuit node lacks source/title")
        instance = node.get("instance_source", {})
        if any(instance[key] not in node["sources"] for key in ("file", "declaration_file") if key in instance):
            raise ValueError("circuit instance declaration is outside its source inventory")
        for port in node["ports"]:
            key = node["id"] + "." + port["id"]
            if key in ports or port["side"] not in {"north", "south", "east", "west"}:
                raise ValueError("duplicate or invalid circuit port")
            width_valid = (type(port["width"]) is int and port["width"] > 0) or (
                port["width"] is None and port.get("bundle") is True)
            if port["direction"] not in {"in", "out"} or not width_valid:
                raise ValueError("invalid circuit port direction/width")
            ports[key] = port
    seen = set()
    for edge in circuit["edges"]:
        src, dst = edge["from"], edge["to"]
        if src not in ports or dst not in ports or (src, dst) in seen:
            raise ValueError("missing or duplicate circuit connection")
        if ports[src]["direction"] != "out" or ports[dst]["direction"] != "in":
            raise ValueError("circuit connection direction mismatch")
        if ports[src]["width"] != ports[dst]["width"] or edge["kind"] not in {"control", "data"}:
            raise ValueError("circuit connection width/kind mismatch")
        if not edge.get("bindings") or not edge.get("label"):
            raise ValueError("circuit connection lacks source binding")
        validate_bindings(root, edge["bindings"])
        seen.add((src, dst))
    validate_instance_connections(root, circuit)


def collect_diagrams(root: Path, spec: dict, regions: list[dict], system: dict) -> dict:
    for relative in dependencies(spec):
        path = root / relative
        if Path(relative).is_absolute() or ".." in Path(relative).parts or not path.resolve().is_relative_to(root.resolve()) or not path.is_file():
            raise ValueError("missing or invalid diagram source")
    validate_bindings(root, spec["bindings"])
    additional = json.loads((root / spec["circuit_catalog"]).read_text(encoding="utf-8"))
    if set(additional) & set(spec["circuits"]):
        raise ValueError("duplicate circuit illustration identifier")
    circuits = {**spec["circuits"], **additional}
    index = json.loads((root / "publications/datasheets/chapter-index.json").read_text(encoding="utf-8"))
    expected = {row["id"] for row in index} | {"system-fabric", "system-clocks", "system-media", "system-mpw"}
    if set(circuits) != expected:
        raise ValueError("full-document circuit coverage changed")
    for circuit in circuits.values():
        validate_circuit(root, circuit)
    validate_fields(spec["sdio_command"], 48)
    command_fields = [(f["name"], f["lsb"], f["bits"]) for f in spec["sdio_command"]]
    if command_fields != [("start", 47, 1), ("direction", 46, 1), ("command", 40, 6),
                          ("argument", 8, 32), ("crc7", 1, 7), ("end", 0, 1)]:
        raise ValueError("SDIO field order differs from the bound transmitter assembly")
    dts = (root / "app/ports/linux/linux/retrosoc_hp.dts").read_text(encoding="utf-8")
    cbo = re.findall(r"riscv,cbom-block-size\s*=\s*<(\d+)>", dts)
    if cbo != ["64"]:
        raise ValueError("review cache-maintenance diagram after platform granule change")
    windows = [{k: r[k] for k in ("symbol", "base", "size", "base_hex", "end_hex", "size_label")}
               for r in regions if r["size"] > 4096 and r["route"] in {"axi4", "ram"} and r["kind"] == "active"]
    if not windows or any(r["base"] + r["size"] > 1 << 32 for r in windows):
        raise ValueError("memory diagram has an invalid address window")
    if any(int(r["base_hex"], 16) != r["base"] or int(r["end_hex"], 16) != r["base"] + r["size"] - 1 for r in windows):
        raise ValueError("memory diagram range labels disagree with numeric bounds")
    layouts = collect_layouts(root, spec["layout_catalog"], system)
    for layout in layouts.values():
        validate_bindings(root, layout.get("bindings", []))
        for row in layout.get("rows", [layout]):
            validate_fields(row["fields"], row["bits"])
            groups = row.get("display_groups", layout.get("display_groups"))
            if groups is not None:
                indexes = [index for lo, hi in groups for index in range(lo, hi + 1)]
                if indexes != list(range(len(row["fields"]))):
                    raise ValueError("compressed binary diagram drops or repeats fields")
    storage = collect_storage(root, spec["storage_catalog"], regions, system, layouts)
    for record in storage.values():
        validate_bindings(root, record.get("bindings", []))
    return {"sources": sorted(dependencies(spec)), "dma_tcd": dma_fields(root),
            "sdio_command": copy.deepcopy(spec["sdio_command"]), "apu": apu_formats(root),
            "uart_fifo": uart_fifo(root), "windows": sorted(windows, key=lambda r: r["base"]),
            "cache": {"granule": 64, "offset": 16, "length": 64, "end": 80, "covered_bytes": 128},
            "circuits": circuits, "layouts": layouts, "storage": storage}
