"""Trace explicit CPU configuration, reset observations and publication capability claims."""
from __future__ import annotations

import copy
import json
import re
from pathlib import Path

from publications.programming_reference import clean_source

COLLECTIONS = ("reset", "interfaces", "formats", "interoperability", "physical")


def dependencies(spec: dict) -> set[str]:
    paths = set(spec.get("sources", []))
    for key in COLLECTIONS:
        for row in spec.get(key, []):
            paths.update(row.get("sources", []))
            paths.update(b["file"] for b in row.get("bindings", []))
    return paths


def without_comments(text: str) -> str:
    return re.sub(r"/\*.*?\*/|//[^\n]*", "", text, flags=re.S)


def unique_pairs(pairs: list[tuple[str, str]], description: str) -> dict[str, str]:
    if len({key for key, _ in pairs}) != len(pairs):
        raise ValueError(f"duplicate {description} parameter")
    return {key: value.strip() for key, value in pairs}


def lp_parameters(text: str) -> dict[str, str]:
    matches = re.findall(r"\bhazard3_cpu_1port\s*#\s*\((.*?)\)\s+u_hazard3_cpu_1port\s*\(", without_comments(text), re.S)
    if len(matches) != 1:
        raise ValueError("LP instance missing or ambiguous")
    parameters = unique_pairs(re.findall(r"\.([A-Z][A-Z0-9_]*)\s*\(([^()]*)\)", matches[0]), "LP")
    # The fixed Mini integration uses the shared wrapper's Boolean feature
    # defaults. Keep configurable integer expressions (notably IRQ count) intact.
    defaults = dict(re.findall(r"parameter\s+bit\s+(\w+)\s*=\s*1'b([01])", without_comments(text)))
    return {name: defaults.get(value, value) if name.startswith("EXTENSION_") else value
            for name, value in parameters.items()}


def hp_parameters(wrapper: str, override: str) -> dict[str, str]:
    """Read the fixed OpenC906 integration constants from the Mini HP wrapper."""
    text = without_comments(wrapper)
    constants = unique_pairs(
        [(name, f"0x{int(value.replace('_', ''), 16):08X}")
         for name, value in re.findall(
             r"localparam\s+logic\s+\[39:0\]\s+(HpResetVector|HpApbBase)\s*=\s*40'h([0-9A-Fa-f_]+)\s*;", text)],
        "HP")
    interfaces = {}
    for body, name in re.findall(
            r"axi4_if\s*#\s*\(([^;]+?)\)\s*(u_c906_axi4_if|u_hp_64_axi4_if)\s*\(", text, re.S):
        width = re.findall(r"\.\s*DATA_WIDTH\s*\(\s*(\d+)\s*\)", body)
        if len(width) != 1 or name in interfaces:
            raise ValueError("HP interface width missing or ambiguous")
        interfaces[name] = width[0]
    sources = re.findall(r"input\s+logic\s+\[15:0\]\s+plic_src_i\b", text)
    hart = re.findall(r"assign\s+sysio_core_hartid\[2:0\]\s*=\s*3'd(\d)\s*;", without_comments(override))
    if len(constants) != 2 or len(interfaces) != 2 or len(sources) != 1 or len(hart) != 1:
        raise ValueError("HP OpenC906 integration constants missing or ambiguous")
    return {
        "resetVector": constants["HpResetVector"],
        "sysWindowBase": constants["HpApbBase"],
        "coreAxiDataWidth": interfaces["u_c906_axi4_if"],
        "fabricAxiDataWidth": interfaces["u_hp_64_axi4_if"],
        "externalInterruptSources": "16",
        "hartId": hart[0],
    }


def hp_isa(dts: str) -> dict[str, object]:
    """Read the software-visible HP ISA/MMU identity from the reviewed device tree."""
    cpu = re.findall(r"cpu@1\s*\{(.*?)hp_cpu_intc:", dts, re.S)
    if len(cpu) != 1:
        raise ValueError("HP device-tree CPU node missing or ambiguous")
    node = cpu[0]
    compatible = re.findall(r'compatible\s*=\s*"thead,c906"', node)
    base = re.findall(r'riscv,isa-base\s*=\s*"(\w+)"', node)
    extensions = re.findall(r'riscv,isa-extensions\s*=\s*((?:\s*"[a-z0-9]+",?)+)\s*;', node)
    mmu = re.findall(r'mmu-type\s*=\s*"riscv,(\w+)"', node)
    if not compatible or len(base) != 1 or len(extensions) != 1 or len(mmu) != 1:
        raise ValueError("HP device-tree ISA/MMU identity missing or ambiguous")
    return {"compatible": "thead,c906", "isa_base": base[0],
            "extensions": re.findall(r'"([a-z0-9]+)"', extensions[0]), "mmu": mmu[0]}


def reset_assignments(text: str, signal: str, module: str | None = None) -> dict[str, str]:
    text = without_comments(text)
    if module:
        scoped = re.findall(rf"\bmodule\s+{re.escape(module)}\b(.*?)\bendmodule\b", text, re.S)
        if len(scoped) != 1:
            raise ValueError("reset module missing or ambiguous")
        text = scoped[0]
    blocks = re.findall(rf"if\s*\(\s*[!~]\s*{re.escape(signal)}\s*\)\s*begin(.*?)\bend\s+else", text, re.S)
    if len(blocks) != 1:
        raise ValueError("reset branch missing or ambiguous")
    return unique_pairs(re.findall(r"\b(\w+)\s*<=\s*([^;]+);", blocks[0]), "reset")


def programming_result(record: dict) -> str:
    if type(record.get("executed")) is not bool or type(record.get("passed")) is not bool:
        raise ValueError("programming result requires boolean executed and passed")
    if not record["executed"]:
        return "Script generated; device not programmed" if record["passed"] else "Preparation failed; no execution recorded"
    return "Tool reported execution success" if record["passed"] else "Execution failed or success marker absent"


def validate_details(spec: dict, ids: set[str], root: Path, active_limits: set[str]) -> None:
    for relative in dependencies(spec):
        path = root / relative
        if Path(relative).is_absolute() or ".." in Path(relative).parts or not path.resolve().is_relative_to(root.resolve()):
            raise ValueError("implementation source escapes repository")
        if not path.is_file():
            raise ValueError(f"missing implementation source: {relative}")
    for collection in COLLECTIONS:
        rows = spec[collection]
        if len({row["id"] for row in rows}) != len(rows):
            raise ValueError(f"duplicate implementation identifier: {collection}")
        for row in rows:
            if not row.get("sources") or not set(row.get("ips", [])) <= ids:
                raise ValueError(f"missing source or unknown implementation IP: {row['id']}")
            if collection in {"interfaces", "formats", "interoperability"} and not row.get("bindings"):
                raise ValueError(f"capability claim lacks binding: {row['id']}")
            for binding in row.get("bindings", []):
                text = (root / binding["file"]).read_text(encoding="utf-8")
                if binding.get("kind") == "reset":
                    found = reset_assignments(text, binding["signal"], binding.get("module"))
                    if found.get(binding["state"]) != binding["value"]:
                        raise ValueError(f"untraceable reset value: {row['id']}")
                elif clean_source(binding["text"]) not in clean_source(text):
                    raise ValueError(f"implementation binding changed: {row['id']}")
            if collection == "reset":
                if row["value_class"] not in {"Fixed", "Configured", "Input-dependent", "Dynamic"}:
                    raise ValueError("invalid reset classification")
                if row["value_class"] in {"Fixed", "Configured"} and not row.get("bindings"):
                    raise ValueError(f"untraceable reset value: {row['id']}")
            if collection == "interfaces" and row["evidence"] != "Source-level subset; no compliance report attached":
                raise ValueError("interface qualification requires separately reviewed report support")
            if collection == "interoperability":
                if row["classification"] not in {"Format-compatible", "Conversion required", "Conditional", "Blocked"}:
                    raise ValueError("invalid interoperability classification")
                if set(row.get("blockers", [])) - active_limits:
                    raise ValueError("unknown interoperability limitation")
                if row.get("blockers") and row["classification"] != "Blocked":
                    raise ValueError("interoperability claim ignores active blocker")


def collect_details(root: Path, spec: dict, ids: set[str], active_limits: set[str]) -> dict:
    validate_details(spec, ids, root, active_limits)
    lp = lp_parameters((root / "rtl/ip/core/mgmt_core_wrapper.sv").read_text(encoding="utf-8"))
    hp = hp_parameters((root / "rtl/mini/top/hp_core_wrapper.sv").read_text(encoding="utf-8"),
                       (root / "rtl/mini/ip_overrides/aq_sysio_kid.v").read_text(encoding="utf-8"))
    identity = hp_isa((root / "app/ports/linux/linux/retrosoc_hp.dts").read_text(encoding="utf-8"))
    for required, actual, name in ((spec["cpu"]["lp_fields"], lp, "LP"), (spec["cpu"]["hp_fields"], hp, "HP")):
        if len(set(required)) != len(required) or not set(required) <= set(actual):
            raise ValueError(f"missing or duplicate requested {name} parameters")
    config = json.loads((root / "publications/datasheets/mini.json").read_text(encoding="utf-8"))
    profile = (root / config["profile"]).read_text(encoding="utf-8")
    build = unique_pairs(re.findall(r"^\s*(ISA|HAVE_CSR|HAVE_HP)\s*:?=\s*([^\n#]+)", profile, re.M), "firmware")
    if set(build) != {"ISA", "HAVE_CSR", "HAVE_HP"} or build["HAVE_HP"] != "YES":
        raise ValueError("incomplete firmware/core profile identity")
    lock = json.loads((root / "dependencies/dependencies.lock.json").read_text(encoding="utf-8"))
    result = copy.deepcopy(spec)
    result["cpu"] = {
        "lp": lp, "hp": hp, "hp_isa": identity["extensions"], "build": build,
        "hp_isa_base": identity["isa_base"], "hp_mmu": identity["mmu"],
        "hp_compatible": identity["compatible"],
        "lp_extensions": [name.removeprefix("EXTENSION_") for name, value in lp.items() if name.startswith("EXTENSION_") and value == "1"],
        "hp_revision": lock["sources"]["openc906"]["revision"],
        "generated_artifact_basis": "Pre-generated vendored OpenC906 RTL at the locked revision, with the reviewed retroSoC hart-ID override; no new core generation",
        "hp_cache_capacity": "Default OpenC906 configuration (32 KiB instruction + 32 KiB data L1 per the T-Head C906 manuals); not independently re-measured",
    }
    result["service_results"] = [{"executed": str(e).lower(), "passed": str(p).lower(),
                                 "meaning": programming_result({"executed": e, "passed": p})}
                                for e, p in ((False, True), (False, False), (True, False), (True, True))]
    return result
