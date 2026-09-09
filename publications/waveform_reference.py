"""Validate publication waveform lanes against reviewed SystemVerilog declarations.

This is a bounded declaration checker, not an RTL simulator or elaborator.
Behavior and parameter qualifications are retained as explicit review notes.
"""

from __future__ import annotations

import json
import math
import re
from pathlib import Path

from publications.register_reference import number, split_top

ROOT = Path(__file__).resolve().parents[1]
WAVEFORMS = Path("publications/datasheets/waveforms.json")
SIGNAL = re.compile(r"(?P<symbol>[a-z_][a-z0-9_]*)(?P<select>(?:\[\d+(?::\d+)?\])*)\Z")
DECLARATION = re.compile(
    r"(?m)^[ \t]*(?:(input|output|inout)\s+)?(?:logic|wire|reg)\s+"
    r"(?:(?:signed|unsigned)\s+)?((?:\[[^]\n]+\][ \t]*)*)([^;\n]+)"
)


def uncomment(text: str) -> str:
    return re.sub(r"/\*[\s\S]*?\*/|//[^\n]*",
                  lambda m: "".join("\n" if c == "\n" else " " for c in m[0]), text)


def resolve_path(root: Path, name: str) -> Path:
    path = (root / name).resolve()
    if not path.is_relative_to(root.resolve()) or not name.startswith("rtl/") or not path.is_file():
        raise ValueError(f"waveform RTL source missing or outside rtl: {name}")
    return path


def dimensions(text: str, constants: dict[str, int]) -> list[tuple[int, int]]:
    result = []
    for item in re.findall(r"\[([^]]+)\]", text):
        ends = split_top(item, ":")
        if len(ends) == 1:
            count = number(ends[0], constants)
            if count < 1:
                raise ValueError("non-positive waveform array dimension")
            result.append((0, count - 1))
        elif len(ends) == 2:
            result.append((number(ends[0], constants), number(ends[1], constants)))
        else:
            raise ValueError(f"unsupported waveform dimension: {item}")
    return result


def declaration(root: Path, source: dict, overrides: dict[str, int]) -> dict:
    path = resolve_path(root, source["file"])
    text = uncomment(path.read_text(encoding="utf-8"))
    scope = re.escape(source["scope"])
    found = re.search(rf"\b(module|interface)\s+{scope}\b([\s\S]*?)\bend\1\b", text)
    if found is None:
        raise ValueError(f"waveform scope absent: {source['file']}::{source['scope']}")
    constants = dict(overrides)
    parameters = re.findall(
        r"\b(?:parameter|localparam)\b[^=\n;]*?\b(\w+)\s*=\s*([^,;\n]+)", found[0]
    )
    for _ in range(len(parameters) + 1):
        for name, expression in parameters:
            if name not in constants:
                try:
                    # A one-line parameter list may end in ") (" before ports.
                    depth = 0
                    end = len(expression)
                    for index, char in enumerate(expression):
                        if char == "(":
                            depth += 1
                        elif char == ")":
                            if depth == 0:
                                end = index
                                break
                            depth -= 1
                    constants[name] = number(expression[:end].strip(), constants)
                except ValueError:
                    pass
    for match in DECLARATION.finditer(found[0]):
        direction, packed, variables = match.groups()
        for item in split_top(variables):
            variable = re.match(r"\s*(\w+)\s*((?:\[[^]]+\]\s*)*)", item)
            if variable and variable[1] == source["symbol"]:
                return {
                    "file": source["file"], "scope": source["scope"],
                    "symbol": source["symbol"], "direction": direction or "internal/interface",
                    "packed": dimensions(packed, constants),
                    "unpacked": dimensions(variable[2], constants),
                    "line": text[:found.start() + match.start()].count("\n") + 1,
                    "declaration": " ".join(match[0].strip().split()),
                }
    raise ValueError(f"waveform signal not declared: {source['file']}::{source['symbol']}")


def selected_width(model: dict, selection: str) -> int:
    dims = [*model["unpacked"], *model["packed"]]
    unpacked = len(model["unpacked"])
    parts = re.findall(r"\[(\d+)(?::(\d+))?\]", selection)
    for index, (first, last) in enumerate(parts):
        if not dims:
            raise ValueError("waveform selection indexes a scalar or too many dimensions")
        high, low = dims.pop(0)
        values = [int(first)] if not last else [int(first), int(last)]
        if any(v < min(high, low) or v > max(high, low) for v in values):
            raise ValueError("waveform bit/array selection outside declaration range")
        if last:
            if index < unpacked or index != len(parts) - 1:
                raise ValueError("waveform part-select must select the final packed dimension")
            dims.insert(0, (int(first), int(last)))
    if len(parts) < unpacked:
        raise ValueError("waveform must select unpacked array elements explicitly")
    return math.prod(abs(a - b) + 1 for a, b in dims)


def lanes(signals: list) -> list[dict]:
    result = []
    for item in signals:
        if isinstance(item, list):
            result.extend(lanes(item[1:]))
        elif isinstance(item, dict) and item:
            result.append(item)
    return result


def source_paths(waveforms: dict) -> set[str]:
    return {entry["file"] for wave in waveforms.values() for entry in wave["signals"].values()} | {
        path for wave in waveforms.values() for path in wave["review_sources"]
    }


def validate_waveforms(waveforms: dict, root: Path = ROOT) -> dict:
    audit = {}
    for key, wave in waveforms.items():
        rows = lanes(wave["source"]["signal"])
        names = [row.get("name", "") for row in rows]
        if not rows or len(names) != len(set(names)) or set(names) != set(wave["signals"]):
            raise ValueError(f"waveform {key}: missing, duplicate or surplus signal provenance")
        if not wave.get("clock_domain") or not wave.get("review_note") or not wave.get("note"):
            raise ValueError(f"waveform {key}: clock domain and behavior review required")
        constants = wave.get("parameters", {})
        if constants and not wave.get("parameter_note"):
            raise ValueError(f"waveform {key}: parameter qualification required")
        for path in wave["review_sources"]:
            resolve_path(root, path)
        records = []
        for row in rows:
            name = row["name"]
            match = SIGNAL.fullmatch(name)
            if match is None:
                raise ValueError(f"waveform {key}: not a lowercase declaration name: {name}")
            source = wave["signals"][name]
            if source["symbol"] != match["symbol"] or not source.get("meaning"):
                raise ValueError(f"waveform {key}: signal name or meaning mismatches provenance")
            if source.get("polarity") not in {"active-high", "active-low", "rising-edge", "falling-edge", "both-edges", "data"}:
                raise ValueError(f"waveform {key}: signal polarity must be reviewed")
            model = declaration(root, source, constants)
            width = selected_width(model, match["select"])
            sequence = row.get("wave", "")
            if not sequence or re.search(r"[^01xXzZpPnNhHlLuUdD.=2-9|]", sequence):
                raise ValueError(f"waveform {key}: unsupported or missing wave sequence")
            bus_slots = len(re.findall(r"[=2-9]", sequence))
            if width == 1 and (bus_slots or row.get("data")):
                raise ValueError(f"waveform {key}: scalar {name} cannot carry a bus-value lane")
            if width != 1 and re.search(r"[pPnN]", sequence):
                raise ValueError(f"waveform {key}: bus {name} cannot be a clock")
            if "data" in row and len(row["data"]) > bus_slots:
                raise ValueError(f"waveform {key}: excess bus labels for {name}")
            records.append({**model, "name": name, "width": width,
                            "polarity": source["polarity"], "meaning": source["meaning"]})
        audit[key] = {"clock_domain": wave["clock_domain"], "signals": records,
                      "review_note": wave["review_note"], "review_sources": wave["review_sources"]}
    return {"basis": "Static declaration and behavior review; not simulation evidence.",
            "waveforms": audit, "files": sorted(source_paths(waveforms))}


def collect_waveforms(root: Path = ROOT) -> tuple[dict, dict]:
    waveforms = json.loads((root / WAVEFORMS).read_text(encoding="utf-8"))
    return waveforms, validate_waveforms(waveforms, root)
