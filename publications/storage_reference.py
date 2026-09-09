"""Resolve architectural storage geometry and linker/load placement for publication."""
from __future__ import annotations

import copy
import json
import math
import re
from pathlib import Path

from publications.circuit_reference import closing_parenthesis
from publications.register_reference import number
from publications.waveform_reference import declaration, uncomment


def constants(root: Path, file: str, defines: list[str] = (), overrides: dict | None = None) -> dict[str, int]:
    values = dict(overrides or {})
    expressions = []
    for path in [*defines, file]:
        source = uncomment((root / path).read_text(encoding="utf-8"))
        expressions += re.findall(r"\b(?:parameter|localparam)\b[^=\n;]*?\b(\w+)\s*=\s*([^,;\n]+)", source)
        expressions += re.findall(r"^\s*`define\s+(\w+)\s+([^\n]+)", source, re.M)
        expressions += re.findall(r"^\s*#define\s+(\w+)\s+([^\n]+)", source, re.M)
    for _ in range(len(expressions) + 1):
        changed = False
        for name, expression in expressions:
            if name not in values:
                try:
                    value = re.sub(r"UINT(?:8|16|32|64)_C\(([^)]+)\)", r"\1", expression)
                    value = re.sub(r"\b(0[xX][0-9a-fA-F]+|\d+)[uUlL]+\b", r"\1", value)
                    values[name] = number(value.replace("`", ""), values)
                    changed = True
                except ValueError:
                    pass
        if not changed:
            break
    return values


def fifo_geometry(root: Path, store: dict) -> tuple[int, int]:
    source = uncomment((root / store["file"]).read_text(encoding="utf-8"))
    matches = list(re.finditer(r"\b" + re.escape(store["instance"]) + r"\s*\(", source))
    if len(matches) != 1:
        raise ValueError("storage FIFO instance missing or ambiguous")
    prefix = source[source.rfind(";", 0, matches[0].start()) + 1:matches[0].start()]
    params = {}
    for match in re.finditer(r"\.(\w+)\s*\(", prefix):
        end = closing_parenthesis(prefix, match.end() - 1)
        params[match[1]] = prefix[match.end():end].strip()
    symbols = constants(root, store["file"], store.get("defines", []), store.get("parameters", {}))
    if "DATA_WIDTH" not in params or "BUFFER_DEPTH" not in params:
        raise ValueError("storage FIFO width/depth parameter changed")
    depth = number(params["BUFFER_DEPTH"].replace("`", ""), symbols)
    bits = number(params["DATA_WIDTH"].replace("`", ""), symbols)
    if depth < 1 or bits < 1 or depth & (depth - 1):
        raise ValueError("FIFO geometry requires positive width and power-of-two depth")
    return depth, bits


def array_geometry(root: Path, store: dict) -> tuple[int, int]:
    geometries = []
    for symbol in store["symbols"]:
        model = declaration(root, {"file": store["file"], "scope": Path(store["file"]).stem, "symbol": symbol}, store.get("parameters", {}))
        packed = list(model["packed"])
        unpacked = list(model["unpacked"])
        if store.get("packed_array"):
            unpacked.append(packed.pop(0))
        depth = math.prod(abs(a - b) + 1 for a, b in unpacked)
        width = math.prod(abs(a - b) + 1 for a, b in packed)
        geometries.append((depth, width))
    if len({depth for depth, _ in geometries}) != 1:
        raise ValueError("storage entry component arrays have different depths")
    depth, bits = geometries[0][0], sum(width for _, width in geometries)
    if "word_view" in store:
        word_bits = store["word_view"]
        if depth * bits % word_bits:
            raise ValueError("storage vector cannot be represented by whole words")
        depth, bits = depth * bits // word_bits, word_bits
    return depth, bits


def geometry_reference(root: Path, reference: dict) -> int:
    if "constant" in reference:
        value = constants(root, reference["file"])[reference["constant"]]
    else:
        model = declaration(root, {"file": reference["file"], "scope": Path(reference["file"]).stem,
                                   "symbol": reference["symbol"]}, {})
        value = math.prod(abs(a - b) + 1 for a, b in model["packed"])
    if reference.get("power2"):
        value = 1 << value
    return value * reference.get("multiply", 1)


def validate_ranges(rows: list[dict]) -> None:
    previous = {}
    for row in rows:
        if type(row["base"]) is not int or type(row["bytes"]) is not int or row["base"] < 0 or row["bytes"] < 1:
            raise ValueError("invalid storage range")
        end = row["base"] + row["bytes"]
        space = row.get("space", "main")
        if end > 1 << 32 or row["base"] < previous.get(space, 0):
            raise ValueError("storage ranges overlap or exceed the address width")
        previous[space] = end
        row["base_hex"] = f"0x{row['base']:08X}"
        row["end_hex"] = f"0x{end - 1:08X}"
        row["size_label"] = f"{row['bytes'] // 1024} KiB" if row["bytes"] % 1024 == 0 else f"{row['bytes']} B"


def linker_sections(root: Path, file: str) -> list[dict]:
    source = uncomment((root / file).read_text(encoding="utf-8"))
    sections = []
    for name, body, vma, lma in re.findall(
        r"\.(init|text|data|bss)\s*(?:ORIGIN\([^)]*\))?\s*(?:\([^)]*\))?\s*:\s*\{([\s\S]*?)\}\s*>\s*(\w+)(?:\s+AT\s*>\s*(\w+))?", source):
        sections.append({"name": "." + name, "vma": vma, "lma": lma or vma,
                         "includes_init": ".init" in body,
                         "initialization": "zero" if name == "bss" else "copy" if lma and lma != vma else "resident"})
    names = {row["name"] for row in sections}
    if names not in ({".init", ".text", ".data", ".bss"}, {".text", ".data", ".bss"}) or (
        ".init" not in names and not any(row["includes_init"] for row in sections)):
        raise ValueError("review linker placement diagram after section change")
    return sections


def collect_storage(root: Path, catalog_path: str, regions: list[dict], system: dict, layouts: dict) -> dict[str, dict]:
    catalog = json.loads((root / catalog_path).read_text(encoding="utf-8"))
    result = {}
    for specification in catalog:
        record = copy.deepcopy(specification)
        if record["id"] in result:
            raise ValueError("duplicate storage illustration")
        for store in record.get("stores", []):
            if store.get("instance"):
                depth, bits = fifo_geometry(root, store)
            elif store.get("symbols"):
                depth, bits = array_geometry(root, store)
            elif "depth_ref" in store:
                depth, bits = geometry_reference(root, store["depth_ref"]), geometry_reference(root, store["bits_ref"])
            elif "layout_ref" in store:
                depth, bits = store["depth"], layouts[store["layout_ref"]]["bits"]
                if not store.get("example") or depth < 1:
                    raise ValueError("descriptor storage illustration lacks an example bound")
                if "max_ref" in store and depth > geometry_reference(root, store["max_ref"]):
                    raise ValueError("descriptor example exceeds its software traversal bound")
            else:
                raise ValueError("storage geometry lacks a source reference")
            if (depth, bits) != (store["depth"], store["bits"]) or min(depth, bits) < 1:
                raise ValueError("architectural storage geometry changed")
        if record.get("region_symbols"):
            selected = [r for r in regions if r["symbol"] in record["region_symbols"]]
            if {r["symbol"] for r in selected} != set(record["region_symbols"]):
                raise ValueError("storage window illustration lost an address region")
            record["ranges"] = [{"name": row["symbol"], "base": row["base"], "bytes": row["size"]}
                                for row in sorted(selected, key=lambda row: row["base"])]
        if record.get("derived") == "apu-local":
            values = constants(root, "rtl/ip/multimedia/apu_define.svh")
            names = [("Tables / scratch", 0), ("Input workspace", values["APB4_APU__LOCAL_INPUT_BASE"]),
                     ("Output workspace", values["APB4_APU__LOCAL_OUTPUT_BASE"]),
                     ("KWS reserve (not advertised)", values["APB4_APU__LOCAL_KWS_BASE"]),
                     ("Internal/common reserve", values["APB4_APU__LOCAL_INTERNAL_BASE"])]
            end = values["APB4_APU__LOCAL_DATA_BYTES"]
            record["ranges"] = [{"name": name, "base": base, "bytes": (names[index + 1][1] if index + 1 < len(names) else end) - base}
                                for index, (name, base) in enumerate(names)]
        if record.get("derived") == "hp-load":
            record["ranges"] = [{"name": row["name"], "base": int(row["address"], 16), "bytes": row["max_size_kib"] * 1024}
                                for row in system["boot_layout"]]
        if record.get("derived") == "hp-flash":
            bundle = system["software"]["bundle_reference"]
            example = bundle["example"]
            record["ranges"] = [{"name": "Synthetic LP prefix", "base": 0, "bytes": example["lp_bytes"]},
                                {"name": "Header + four descriptors", "base": bundle["bundle_offset"], "bytes": example["header"]["header_size"]}]
            record["ranges"] += [{"name": entry["name"], "base": entry["flash_offset"], "bytes": entry["size"]} for entry in example["entries"]]
            record["note"] += f" Generated image: {example['image_bytes']} bytes. Unlisted gaps and trailing alignment are padding."
        if record.get("derived") == "worked-budgets":
            record["budgets"] = copy.deepcopy(system["programming"]["budgets"])
        if record.get("linker"):
            profiles = [profile for profile in system["software"]["profiles"] if profile["profile"] == record["profile"]]
            if len(profiles) != 1 or Path(record["linker"]).stem != profiles[0]["link_type"]:
                raise ValueError("linker diagram no longer matches the committed profile")
            record["startup"] = profiles[0]["startup"]
            record["sections"] = linker_sections(root, record["linker"])
            source = uncomment((root / record["linker"]).read_text(encoding="utf-8"))
            stack = re.findall(r"ORIGIN\((\w+)\)\s*\+\s*LENGTH\(\w+\)\s*:\s*\{[^}]*_stack_point", source)
            if not stack:
                stack = re.findall(r"_stack_point\s*=\s*ORIGIN\((\w+)\)\s*\+\s*LENGTH\(\w+\)", source)
            if len(stack) != 1:
                raise ValueError("linker stack placement missing or ambiguous")
            record["stack_region"] = stack[0]
        if "ranges" in record:
            validate_ranges(record["ranges"])
        result[record["id"]] = record
    return result
