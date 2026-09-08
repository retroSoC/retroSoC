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
    return unique_pairs(re.findall(r"\.([A-Z][A-Z0-9_]*)\s*\(([^()]*)\)", matches[0]), "LP")


def hp_parameters(text: str) -> tuple[dict[str, str], list[str]]:
    text = without_comments(text)
    values = unique_pairs(re.findall(r"^\s*param\.([A-Za-z][\w.]*)\s*=\s*([^\n]+)", text, re.M), "HP")
    isa = re.findall(r"param\.addISA\(([^)]*)\)", text)
    if len(isa) != 1:
        raise ValueError("HP ISA configuration missing or ambiguous")
    return values, re.findall(r'"([a-z0-9]+)"', isa[0])


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
    lp = lp_parameters((root / "rtl/mini/top/mgmt_core_wrapper.sv").read_text(encoding="utf-8"))
    hp_source = (root / "scripts/vexiiriscv/GenerateRetroSocHp.scala").read_text(encoding="utf-8")
    hp, hp_isa = hp_parameters(hp_source)
    for required, actual, name in ((spec["cpu"]["lp_fields"], lp, "LP"), (spec["cpu"]["hp_fields"], hp, "HP")):
        if len(set(required)) != len(required) or not set(required) <= set(actual):
            raise ValueError(f"missing or duplicate requested {name} parameters")
    config = json.loads((root / "publications/datasheets/mini.json").read_text(encoding="utf-8"))
    profile = (root / config["profile"]).read_text(encoding="utf-8")
    build = unique_pairs(re.findall(r"^\s*(ISA|HAVE_CSR|HAVE_HP|HP_CONFIG)\s*:?=\s*([^\n#]+)", profile, re.M), "firmware")
    if set(build) != {"ISA", "HAVE_CSR", "HAVE_HP", "HP_CONFIG"}:
        raise ValueError("incomplete firmware/core profile identity")
    lock = json.loads((root / "dependencies/dependencies.lock.json").read_text(encoding="utf-8"))
    result = copy.deepcopy(spec)
    result["cpu"] = {
        "lp": lp, "hp": hp, "hp_isa": hp_isa, "build": build,
        "lp_extensions": [name.removeprefix("EXTENSION_") for name, value in lp.items() if name.startswith("EXTENSION_") and value == "1"],
        "hp_revision": lock["sources"]["vexiiriscv"]["revision"],
        "generated_artifact_basis": "Not supplied in the publication evidence set",
        "hp_cache_capacity": "Unconfirmed; upstream default block size not independently reviewed",
    }
    pma = re.findall(r"SizeMapping\((0x[0-9A-Fa-f]+)L,\s*(0x[0-9A-Fa-f]+)L\),\s*isMain\s*=\s*(true|false),\s*isExecutable\s*=\s*(true|false)", without_comments(hp_source))
    if not pma:
        raise ValueError("explicit HP PMA mappings missing")
    result["cpu"]["pma"] = [{"base": f"0x{int(base, 16):08X}",
                             "end": f"0x{int(base, 16)+int(size, 16)-1:08X}",
                             "bytes": int(size, 16), "main": main, "executable": execute}
                            for base, size, main, execute in pma]
    result["service_results"] = [{"executed": str(e).lower(), "passed": str(p).lower(),
                                 "meaning": programming_result({"executed": e, "passed": p})}
                                for e, p in ((False, True), (False, False), (True, False), (True, True))]
    return result
