"""Chapter coverage and actual renderer-use checks for specialized publication figures."""
from __future__ import annotations

PACKAGES = ("circuiteria", "bytefield", "rivet", "blockcell")


def inventory(diagrams: dict) -> dict[str, dict]:
    result = {}
    for package, values in (("circuiteria", diagrams["circuits"]), ("bytefield", diagrams["layouts"]),
                            ("blockcell", diagrams["storage"])):
        for identifier, record in values.items():
            sources = set(record.get("sources", []))
            if package == "circuiteria":
                for node in record["nodes"]:
                    sources.update(node["sources"])
                for edge in record["edges"]:
                    sources.update(binding["file"] for binding in edge["bindings"])
            result[package + ":" + identifier] = {"package": package, "id": identifier,
                                                    "sources": sorted(sources)}
    for identifier in ("apu-common", *("apu-family-" + family["name"].lower() for family in diagrams["apu"]["families"])):
        result["rivet:" + identifier] = {"package": "rivet", "id": identifier,
                                        "sources": ["scripts/apu_isa.py", "rtl/ip/multimedia/apu_microcode_pkg.sv", "rtl/ip/multimedia/apu_define.svh"]}
    for identifier, sources in (("product-memory-windows", ["rtl/mini/address_map/memory_map.json"]),
                                ("cache-boundaries", ["app/ports/linux/linux/retrosoc_hp.dts"])):
        result["blockcell:" + identifier] = {"package": "blockcell", "id": identifier, "sources": sources}
    return result


def coverage(contract: dict, diagrams: dict) -> list[dict]:
    items = inventory(diagrams)
    ip_ids = set(contract["ip_ids"])
    chapters = {}
    for identifier in ip_ids:
        chapters[identifier] = {"circuiteria": ["circuiteria:" + identifier], "bytefield": [], "rivet": [], "blockcell": []}
    for package, values in (("bytefield", diagrams["layouts"]), ("blockcell", diagrams["storage"])):
        for identifier, record in values.items():
            for chapter in record["chapters"]:
                chapters.setdefault(chapter, {key: [] for key in PACKAGES})[package].append(package + ":" + identifier)
    chapters["apu"]["rivet"] = [key for key in items if key.startswith("rivet:")]
    direct = {
        "Typical Applications and System Configurations": ["circuiteria:system-media"],
        "Interconnect": ["circuiteria:system-fabric", "blockcell:product-memory-windows"],
        "Memory Attributes, Cache and DMA Coherency": ["blockcell:cache-boundaries"],
        "Clock and Reset": ["circuiteria:system-clocks"],
        "SoC Template": ["circuiteria:system-mpw"],
        "Worked Buffer Budgets": ["blockcell:worked-buffer-budgets"],
    }
    aliases = {"Boot Configuration, Initialization and Recovery": "software-boot", "Runtime, SDK and Shell": "software-runtime"}
    shared = {
        "Interface Standards and Supported Subsets": ["bytefield:" + key for key, record in diagrams["layouts"].items() if record.get("product_format")],
        "Linker Layout and Runtime Accounting": chapters["software-runtime"]["blockcell"],
    }
    reasons = {
        "circuiteria": "No separate hardware-port connection diagram is required here; existing workflows, matrices or lookup tables retain their own rendering.",
        "bytefield": "No additional binary frame/container layout is owned by this section; existing MMIO register bit layouts remain with the register renderer.",
        "rivet": "No APU internal instruction encoding is defined here; CPU ISA/CSR manuals remain outside this publication's scope.",
        "blockcell": "No additional architectural storage/buffer geometry is owned by this section; registers, evidence and narrative are not fabricated into memory arrays.",
    }
    result = []
    for index, entry in enumerate(contract["entries"]):
        key = entry["anchor"] or "section-" + str(index)
        owner = aliases.get(entry["title"], key)
        values = {package: list(chapters.get(owner, {}).get(package, [])) for package in PACKAGES}
        for identifier in direct.get(entry["title"], []):
            values[identifier.split(":")[0]].append(identifier)
        for identifier in shared.get(entry["title"], []):
            values[identifier.split(":")[0]].append(identifier)
        for identifiers in values.values():
            if any(identifier not in items for identifier in identifiers):
                raise ValueError("chapter coverage refers to an unknown diagram")
        result.append({"index": index, **entry, "key": key, "categories": {
            package: {"diagrams": sorted(set(identifiers)),
                      "status": "covered" if identifiers else "not_applicable",
                      "reason": "Primary diagram or explicit shared-format reference in this chapter." if identifiers else reasons[package]}
            for package, identifiers in values.items()}})
    if len(result) != len(contract["entries"]) or len(ip_ids) != 40:
        raise ValueError("diagram chapter coverage differs from the frozen inventory")
    for row in reversed(result):
        descendants = []
        for child in result[row["index"] + 1:]:
            if child["level"] <= row["level"]:
                break
            descendants.append(child)
        for package, category in row["categories"].items():
            if category["status"] == "not_applicable" and descendants:
                included = sorted({identifier for child in descendants for identifier in child["categories"][package]["diagrams"]})
                if included:
                    category.update(status="covered_by_subchapters", diagrams=included,
                                    reason="Detailed figures are placed in the owned subchapters; no duplicate parent figure is required.")
            category["sources"] = sorted({source for identifier in category["diagrams"] for source in items[identifier]["sources"]})
    return result


def validate_usage(diagrams: dict, records: list[dict]) -> list[dict]:
    expected = inventory(diagrams)
    actual = {}
    for record in records:
        key = record["package"] + ":" + record["id"]
        if key not in expected or key in actual or type(record["page"]) is not int or record["page"] < 1:
            raise ValueError("unknown, repeated or unlocated specialized diagram")
        actual[key] = {**expected[key], "page": record["page"]}
    if actual.keys() != expected.keys():
        raise ValueError("specialized diagrams not rendered: " + ", ".join(sorted(expected.keys() - actual.keys())))
    return sorted(actual.values(), key=lambda row: (row["page"], row["package"], row["id"]))
