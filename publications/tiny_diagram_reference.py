"""Validate Tiny-only circuit, binary-format and architectural-storage illustrations."""
from __future__ import annotations

import json
import re
from collections import Counter
from pathlib import Path

from publications.circuit_reference import validate_instance_connections
from publications.format_reference import collect_layouts
from publications.register_reference import strip_comments
from publications.soc_diagram_geometry import routes, segment_distance, validate_geometry
from publications.storage_reference import collect_storage
from publications.waveform_reference import declaration, selected_width

BOOK = "publications/datasheets/tiny"
SYSTEM_CIRCUITS = {"system-fabric", "system-clocks", "system-media"}


def source_paths(value) -> set[str]:
    paths = set()
    if isinstance(value, dict):
        for key, child in value.items():
            if key == "sources":
                paths.update(child)
            elif key in {"file", "declaration_file", "linker"} and isinstance(child, str):
                paths.add(child)
            else:
                paths.update(source_paths(child))
    elif isinstance(value, list):
        for child in value:
            paths.update(source_paths(child))
    return paths


def validate_bindings(root: Path, bindings: list[dict]) -> None:
    for binding in bindings:
        path = root / binding["file"]
        source = re.sub(r"\s+", "", strip_comments(path.read_text(encoding="utf-8")))
        expected = re.sub(r"\s+", "", strip_comments(binding["text"]))
        if not expected or expected not in source:
            raise ValueError(f"Tiny illustration source binding changed: {binding['file']}")


def validate_circuit(root: Path, circuit: dict) -> None:
    nodes, ports = {}, {}
    for node in circuit["nodes"]:
        if node["id"] in nodes or not node.get("title") or not node.get("sources"):
            raise ValueError("Tiny circuit node missing or duplicated")
        nodes[node["id"]] = node
        if min(node["w"], node["h"]) <= 0:
            raise ValueError("Tiny circuit node has invalid geometry")
        for port in node["ports"]:
            key = node["id"] + "." + port["id"]
            if key in ports or port["side"] not in {"north", "south", "east", "west"}:
                raise ValueError("Tiny circuit port missing or duplicated")
            if port["direction"] not in {"in", "out"} or not (
                    isinstance(port["width"], int) and port["width"] > 0 or
                    port["width"] is None and port.get("bundle") is True):
                raise ValueError("Tiny circuit port direction/width invalid")
            ports[key] = port
    seen = set()
    for edge in circuit["edges"]:
        a, b = edge["from"], edge["to"]
        if (a, b) in seen or a not in ports or b not in ports:
            raise ValueError("Tiny circuit connection missing or duplicated")
        if ports[a]["direction"] != "out" or ports[b]["direction"] != "in":
            raise ValueError("Tiny circuit connection direction mismatch")
        if ports[a]["width"] != ports[b]["width"] or edge["kind"] not in {"control", "data"}:
            raise ValueError("Tiny circuit connection width/kind mismatch")
        width = re.search(r"/\s*(\d+)$", edge.get("label", ""))
        if width and ports[a]["width"] is not None and int(width[1]) != ports[a]["width"]:
            raise ValueError("Tiny circuit displayed width differs from source port")
        if not edge.get("label") or not edge.get("bindings"):
            raise ValueError("Tiny circuit edge has no source binding")
        validate_bindings(root, edge["bindings"])
        for signal in edge.get("signals", []):
            model = declaration(root, signal, signal.get("parameters", {}))
            width = selected_width(model, signal.get("select", ""))
            if width != signal["bits"] or ports[a]["width"] != width or ports[b]["width"] != width:
                raise ValueError("Tiny circuit width differs from the selected RTL signal")
        seen.add((a, b))
    # The shared instance checker checks actual named-port connections. Tiny
    # checks signal selections above because its SRAM uses unpacked arrays.
    validate_instance_connections(root, {**circuit, "edges": [{**e, "signals": []} for e in circuit["edges"]]})


def validate_fields(fields: list[dict], bits: int) -> None:
    used = set()
    for field in fields:
        indexes = set(range(field["lsb"], field["lsb"] + field["bits"]))
        if field["bits"] <= 0 or field["lsb"] < 0 or used & indexes or max(indexes) >= bits:
            raise ValueError("Tiny binary diagram has overlapping or invalid fields")
        used.update(indexes)
    if used != set(range(bits)):
        raise ValueError("Tiny binary diagram omits fields")


def functional_routes(diagram: dict, ip_ids: set[str], fabric: dict, clocks: dict,
                      apb_domains: dict[str, str]) -> list[dict]:
    """Check logical owners and clock crossings before rendering the exact routes."""
    nodes = {node["id"]: node for node in diagram["nodes"]}
    edges = {edge["id"]: edge for edge in diagram["edges"]}
    if len(nodes) != len(diagram["nodes"]) or len(edges) != len(diagram["edges"]):
        raise ValueError("Tiny functional architecture repeats a node or edge")
    if Counter(n["ip"] for n in nodes.values() if "ip" in n) != Counter(ip_ids):
        raise ValueError("Tiny functional architecture must show each IP chapter once")
    domains = {domain["name"] for domain in clocks["domains"]}
    if {panel["domain"] for panel in diagram["panels"] if "label" in panel} != domains:
        raise ValueError("Tiny functional architecture clock-domain key differs")
    for box in [*diagram["panels"], *nodes.values()]:
        if (box["domain"] not in domains or min(box["x"], box["y"]) < 0 or min(box["w"], box["h"]) <= 0
                or box["x"] + box["w"] > diagram["width_mm"] or box["y"] + box["h"] > diagram["height_mm"]):
            raise ValueError("Tiny functional architecture box or clock domain is invalid")
    for edge in edges.values():
        if edge["from"] not in nodes or edge["to"] not in nodes or edge["kind"] not in {"data", "control", "stream"}:
            raise ValueError("Tiny functional architecture has an invalid route")
    expected_owners = [fabric["owners"][owner] for owner in fabric["active_owners"]]
    if [e["owner"] for e in edges.values() if "owner" in e] != expected_owners:
        raise ValueError("Tiny functional architecture AXI owners differ from the fabric")
    required_paths = {
        "cpu-ahb": ("cpu", "cpu-mem", "data"),
        "cpu-local": ("cpu-mem", "sram", "data"),
        "cpu-slow": ("cpu-mem", "fabric", "data"),
        "sram-axi": ("fabric", "sram", "data"),
        "dma-admit": ("dma", "dma-admission", "data"),
        "dma-axi": ("dma-admission", "dma-cdc", "data"),
        "dma-owner": ("dma-cdc", "fabric", "data"),
        "sdio-private": ("sdio", "sdio-dma", "data"),
        "sdio-admit": ("sdio-dma", "sdio-admission", "data"),
        "sdio-owner": ("sdio-admission", "fabric", "data"),
        "xpi-axi": ("fabric", "xpi-axi", "data"),
        "xpi-data": ("xpi-axi", "xpi", "data"),
        "xpi-apb": ("fabric", "xpi-apb", "control"),
        "pclk-apb": ("fabric", "pclk-apb", "control"),
        "pclk-rail": ("pclk-apb", "pclk-rail", "control"),
        "aon-apb": ("fabric", "aon-apb", "control"),
        "aon-rail": ("aon-apb", "aon-rail", "control"),
        "rcu-commands": ("sysctrl", "rcu", "control"),
    }
    for identifier, expected in required_paths.items():
        edge = edges.get(identifier, {})
        if tuple(edge.get(k) for k in ("from", "to", "kind")) != expected:
            raise ValueError(f"Tiny functional architecture path differs: {identifier}")
    endpoints = {n["apb_target"]: n for n in nodes.values() if "apb_target" in n}
    if Counter(n["apb_target"] for n in nodes.values() if "apb_target" in n) != Counter(apb_domains.keys()):
        raise ValueError("Tiny functional architecture APB targets differ from the integration map")
    bridges = {"system": "fabric", "aon": "aon-rail", "memory": "xpi-apb", "peripheral": "pclk-rail"}
    control_paths = {(e["from"], e["to"]) for e in edges.values() if e["kind"] == "control"}
    for target, node in endpoints.items():
        domain = apb_domains[target]
        if node["domain"] != domain or (bridges[domain], node["id"]) not in control_paths:
            raise ValueError(f"Tiny functional architecture APB route or domain differs: {target}")
    crossings = {c["name"]: (c["source"], c["destination"]) for c in clocks["crossings"]}
    bound = set()
    for edge in edges.values():
        pair = (nodes[edge["from"]]["domain"], nodes[edge["to"]]["domain"])
        for key, direction in (("crossing", pair), ("reverse_crossing", pair[::-1])):
            if key in edge:
                name = edge[key]
                if name in bound or crossings.get(name) != direction or (key == "reverse_crossing" and not edge.get("duplex")):
                    raise ValueError(f"Tiny functional architecture crossing differs: {name}")
                bound.add(name)
    required_crossings = {"debug_dmi", "dma_axi", "xpi_mem_axi", "rcu_commands", "i2s_tx_samples", "i2s_rx_samples",
                          "dvp_payload", "dvp_configuration"}
    if not required_crossings <= bound:
        raise ValueError("Tiny functional architecture omits a required crossing")
    validate_geometry(diagram)
    paths = routes(diagram)
    if any(not 0 <= x <= diagram["width_mm"] or not 0 <= y <= diagram["height_mm"]
           for path in paths for x, y in path["points"]):
        raise ValueError("Tiny functional architecture route leaves its canvas")
    by_id = {p["id"]: p["points"] for p in paths}
    local, slow = by_id["cpu-local"], by_id["cpu-slow"]
    if any(segment_distance(a, b, c, d) < 0.5 for a, b in zip(local, local[1:]) for c, d in zip(slow, slow[1:])):
        raise ValueError("Tiny functional architecture joins or crowds the two CPU routes")
    return paths


def collect(root: Path, catalog: list[dict], regions: list[dict]) -> dict:
    def read(name: str):
        return json.loads((root / BOOK / name).read_text(encoding="utf-8"))
    circuits = read("diagram-circuits.json")
    ids = {r["id"] for r in catalog}
    if set(circuits) != ids | SYSTEM_CIRCUITS:
        raise ValueError("Tiny circuit inventory must contain every current IP and three system diagrams")
    clocks = json.loads((root / "rtl/tiny/integration/clock_reset_domains.json").read_text(encoding="utf-8"))
    branches = clocks["generated_apb_crossings"]
    names = {"timer": "timer0", "i2c": "i2c0"}
    apb_domains = {name: domain for domain, values in branches["destinations"].items() for name in values}
    apb_domains.update({name: "system" for name in branches["native_system"] + branches["same_clock_isolation"]})
    functional = read("soc-functional.json")
    topology = json.loads((root / "rtl/tiny/integration/soc_topology.json").read_text(encoding="utf-8"))
    functional["routes"] = functional_routes(functional, ids, topology["fabric"], clocks, apb_domains)
    validate_bindings(root, functional["bindings"])
    descriptions = {"aon": "AON REF24", "system": "SYS", "memory": "MEM", "peripheral": "PCLK"}
    extra = {"rtc": "; functional counter: AON REF24", "wdg": "; functional counter: AON REF24",
             "i2s": "; serial engine: AUDIO", "dvp": "; sampler: external PIX",
             "dma": "; AXI transport crosses to SYS", "sysctrl": "; RCU state/backend: AON REF24"}
    for identifier in ids:
        if identifier == "rcu":
            note = "RCU state/backend: AON REF24; register requests arrive from SYS through SYSCTRL."
        else:
            name = names.get(identifier, identifier)
            if name not in apb_domains:
                raise ValueError("Tiny diagram clock-domain owner is missing")
            note = "APB/control: " + descriptions[apb_domains[name]] + extra.get(identifier, "") + "."
        circuits[identifier]["clock_note"] = note
    layouts = collect_layouts(root, BOOK + "/diagram-layouts.json", {"product_details": {"formats": []}})
    budgets = []
    for name, payload, stored, stride in [
            ("QVGA RGB565", 320 * 240 * 2, 320 * 240 * 2, 320 * 2),
            ("VGA RGB565", 640 * 480 * 2, 640 * 480 * 2, 640 * 2),
            ("256 stereo16 frames", 256 * 2 * 2, 256 * 4, 4),
            ("256 stereo24 frames", 256 * 2 * 3, 256 * 2 * 4, 8),
            ("16 DMA descriptors", 16 * 64, 16 * 64, 64)]:
        budgets.append(dict(name=name, payload_bytes=payload, storage_bytes=stored,
                            stride_bytes=stride, total_bytes=stored))
    context = {"software": {"profiles": [{"profile": "configs/ci/ics55-tiny.mk",
               "link_type": "ld2_all_sram", "startup": "crt/arch/riscv/startup.S"}]},
               "programming": {"budgets": budgets}}
    stores = collect_storage(root, BOOK + "/diagram-storage.json", regions, context, layouts)
    flows = read("diagram-flows.json")
    all_records = [*circuits.values(), *layouts.values(), *stores.values(), *flows.values(), functional]
    paths = source_paths(all_records)
    paths.update({"rtl/tiny/integration/clock_reset_domains.json", "scripts/generate_tiny.py",
                  "publications/soc_diagram_geometry.py"})
    for path in paths:
        resolved = (root / path).resolve()
        if path.startswith("rtl/mini/") or not resolved.is_relative_to(root.resolve()) or not resolved.is_file():
            raise ValueError(f"Tiny illustration contains missing/non-Tiny source: {path}")
    for circuit in circuits.values():
        validate_circuit(root, circuit)
    for record in flows.values():
        if record["owner"] not in ids or not record.get("bindings"):
            raise ValueError("Tiny lifecycle diagram has no owner/source binding")
        validate_bindings(root, record["bindings"])
    for record in [*layouts.values(), *stores.values()]:
        if not record.get("chapters") or not set(record["chapters"]) <= ids | {"tiny-memory-budget", "tiny-boot", "tiny-dma-format"}:
            raise ValueError("Tiny illustration has an unknown owning chapter")
        validate_bindings(root, record.get("bindings", []))
    for record in layouts.values():
        for row in record.get("rows", [record]):
            validate_fields(row["fields"], row["bits"])
    inventory = [{"id": "circuit-" + key, "package": "circuiteria", "source_id": key}
                 for key in circuits]
    inventory += [{"id": "format-" + key, "package": "bytefield", "source_id": key} for key in layouts]
    inventory += [{"id": "storage-" + key, "package": "blockcell", "source_id": key} for key in stores]
    native_owners = {"tiny-overview": "tiny-overview", "application-composition": "tiny-applications",
                     "tiny-soc-functional": "tiny-core",
                     "master-ownership": "tiny-master-ownership", "fault-recovery": "tiny-system-diagnostics",
                     "boot": "tiny-boot", "snapshot": "tiny-diagnostics", "dma-recovery": "tiny-dma-format",
                     "tiny-access-matrix": "tiny-bus", **{key: r["owner"] for key, r in flows.items()}}
    native = [dict(id=key, package="cetz", owner=owner) for key, owner in native_owners.items()]
    native += [dict(id="wave-" + key, package="wavedrom", owner=key) for key in ids]
    native += [dict(id="wave-" + key, package="wavedrom", owner="tiny-bus") for key in ["axi4", "apb4"]]
    return dict(circuits=circuits, layouts=layouts, storage=stores, flows=flows, functional=functional, inventory=inventory,
                native_inventory=native, source_paths=sorted(paths))


def validate_rendered(illustrations: dict, items: list[dict]) -> None:
    expected = {r["id"] for r in [*illustrations["inventory"], *illustrations["native_inventory"]]}
    actual = [r["id"] for r in items if isinstance(r, dict) and r.get("kind") == "tiny-diagram"
              ]
    if len(actual) != len(set(actual)) or set(actual) != expected:
        raise ValueError("Tiny specialized figure omitted, duplicated or unknown")


def coverage(illustrations: dict, navigation: dict) -> list[dict]:
    """Attribute every drawing to a primary or shared chapter without inventing diagrams."""
    packages = ("circuiteria", "bytefield", "blockcell", "cetz", "wavedrom")
    direct = {}
    def add(owner: str, package: str, identifier: str, shared: bool = False):
        direct.setdefault(owner, []).append(dict(package=package, id=identifier, shared=shared))
    system = {"system-fabric": "tiny-core", "system-clocks": "tiny-clock", "system-media": "tiny-applications"}
    for key in illustrations["circuits"]:
        add(system.get(key, key), "circuiteria", "circuit-" + key)
    for collection, package, prefix in [("layouts", "bytefield", "format-"), ("storage", "blockcell", "storage-")]:
        for key, record in illustrations[collection].items():
            primary = record.get("existing_label", record["chapters"][0])
            add(primary, package, prefix + key)
            for chapter in record["chapters"]:
                if chapter != primary:
                    add(chapter, package, prefix + key, True)
    for row in illustrations["native_inventory"]:
        add(row["owner"], row["package"], row["id"])
    result = []
    for index, row in enumerate(navigation["entries"]):
        key = row["anchor"] or "section-" + str(index)
        values = direct.get(key, [])
        result.append({**row, "key": key, "categories": {
            package: {"status": "covered" if any(r["package"] == package for r in values) else "not_applicable",
                      "diagrams": [r for r in values if r["package"] == package],
                      "reason": "Primary or explicitly shared source-bound drawing." if any(r["package"] == package for r in values)
                      else "This section owns no additional drawing of this type; no storage, binary format or hardware is inferred."}
            for package in packages}})
    known = {r["key"] for r in result}
    if set(direct) - known:
        raise ValueError("Tiny figure coverage names a missing navigation anchor")
    return result
