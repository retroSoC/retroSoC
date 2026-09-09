"""Publication-only binary layouts, resolved from C structures and existing exporters."""
from __future__ import annotations

import copy
import json
import re
from pathlib import Path

from publications.implementation_reference import without_comments


def structure_fields(root: Path, specification: dict) -> list[dict]:
    source = without_comments((root / specification["file"]).read_text(encoding="utf-8"))
    bodies = re.findall(r"typedef\s+struct\s*\{([^}]+)\}\s*" + re.escape(specification["name"]) + r"\s*;", source)
    if len(bodies) != 1:
        raise ValueError("binary-layout C structure missing or ambiguous")
    pattern = r"(u?int)(8|16|32|64)_t\s+(\w+)\s*(?:\[\s*(\d+)\s*\])?\s*;"
    if re.sub(pattern, "", bodies[0]).strip():
        raise ValueError("unreviewed type in binary-layout C structure")
    result, offset = [], 0
    for signed, width, member, count in re.findall(pattern, bodies[0]):
        bits, count = int(width), int(count or "1")
        if count < 1 or offset % (bits // 8):
            raise ValueError("binary-layout structure needs an explicit padding/alignment review")
        role = "reserved" if member.startswith("reserved") else "writeback" if member in specification.get("writeback", []) else "mixed" if member in specification.get("mixed", []) else "configuration"
        for index in range(count):
            name = member if count == 1 else f"{member}[{index}]"
            result.append({"name": name, "label": name, "member": member, "array_index": index if count > 1 else None,
                           "offset": offset, "lsb": offset * 8, "bits": bits,
                           "role": role, "signed": signed == "int"})
            offset += bits // 8
    if offset != specification["bytes"]:
        raise ValueError("binary-layout C structure size changed")
    return result


def word_fields(fields: list[dict]) -> list[dict]:
    return [{"name": row["name"], "label": row["name"], "offset": row["offset"],
             "lsb": row["offset"] * 8, "bits": row["bytes"] * 8,
             "role": "reserved" if row["name"].startswith("reserved") else "configuration"}
            for row in fields]


def collect_layouts(root: Path, catalog_path: str, system: dict) -> dict[str, dict]:
    catalog = json.loads((root / catalog_path).read_text(encoding="utf-8"))
    result = {}
    product_formats = {row["id"]: row for row in system["product_details"]["formats"]}
    for specification in catalog:
        record = copy.deepcopy(specification)
        identifier = record["id"]
        if identifier in result or not record.get("chapters") or not record.get("sources"):
            raise ValueError("duplicate binary layout or missing chapter/source")
        if record.get("structure"):
            record["fields"] = structure_fields(root, record["structure"])
            record["bits"] = record["structure"]["bytes"] * 8
        if record.get("derived") in {"hp-header", "hp-entry"}:
            bundle = system["software"]["bundle_reference"]
            key = "header_fields" if record["derived"] == "hp-header" else "entry_fields"
            record["fields"] = word_fields(bundle[key])
            record["bits"] = sum(field["bits"] for field in record["fields"])
        if record.get("product_format"):
            original = product_formats[record["product_format"]]
            record["note"] = original["layout"] + " " + original["boundary"]
            record["sources"] = sorted(set(record["sources"]) | set(original["sources"]))
            record["bindings"] = record.get("bindings", []) + original["bindings"]
        if record["kind"] == "bytes":
            for field in record["fields"]:
                field["offset"] = field["lsb"] // 8
                if field["lsb"] % 8 or field["bits"] % 8:
                    raise ValueError("byte layout contains a non-byte-aligned field")
        result[identifier] = record
    return result
