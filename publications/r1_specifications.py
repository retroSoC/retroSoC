"""Resolve the four R1 specification plates from scoped design and planning records."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import re


MODELS = ("TINY", "MINI", "STD", "PRO", "MAX", "ULTRA")
TOPICS = ("compute", "memory", "graphics", "connectivity")
CATALOG = Path("publications/datasheets/tiny/r1-specifications.json")


def verify_sources(root: Path, sources: dict) -> None:
    for key, entry in sources.items():
        if "path" in entry:
            raw = (root / entry["path"]).read_bytes().replace(b"\r\n", b"\n")
            blob = hashlib.sha1(f"blob {len(raw)}\0".encode() + raw).hexdigest()
            if blob != entry["blob"]:
                raise ValueError(f"R1 specification source changed: {key} at {entry['revision']}")
        elif (entry.get("authority") != "User-approved R1 maximum concept configuration"
              or not entry.get("reviewed") or not re.fullmatch(r"[0-9a-f]{64}", entry.get("reference_image_sha256", ""))):
            raise ValueError(f"R1 concept source requires the reviewed configuration and reference image: {key}")


def resolve(catalog: dict, products: list[dict], facts: dict) -> dict:
    profiles, metrics, topics = (catalog[k] for k in ("profiles", "metrics", "topics"))
    sources = catalog["sources"]
    if (set(profiles) != set(MODELS) or tuple(p["name"] for p in products) != MODELS
            or tuple(p["key"] for p in topics) != TOPICS):
        raise ValueError("R1 specifications require four ordered topics and six ordered products")
    topic_of = {}
    for i, topic in enumerate(topics, 1):
        if len(set(topic["metrics"])) != len(topic["metrics"]):
            raise ValueError(f"duplicate metric on R1 plate {topic['key']}")
        for key in topic["metrics"]:
            topic_of.setdefault(key, f"concept-{i}")
    if set(topic_of) != set(metrics):
        raise ValueError("R1 plates and metric catalog differ")

    resolved = {}
    for key, row in metrics.items():
        derivative = row.get("derive")
        if not derivative and set(row["cells"]) != set(MODELS):
            raise ValueError(f"incomplete R1 metric: {key}")
        cells = {}
        for product in products:
            name = product["name"]
            profile = profiles[name]
            source = profile.get("source", topic_of[key])
            state = "reviewed" if name in MODELS[:2] else "target"
            unit = row["unit"]
            depends = None
            if derivative == "family status":
                source, state, value = "family-status", "positioning", product["status"]
                display = value
            elif derivative == "sum roles":
                roles = metrics["core-layout"]["cells"][name]
                if not isinstance(roles, dict) or not roles or any(type(count) is not int or count < 1 for count in roles.values()):
                    raise ValueError(f"invalid R1 CPU composition: {name}")
                value = sum(roles.values())
                display, depends = str(value), f"r1.{name.lower()}.core-layout"
            elif derivative:
                raise ValueError(f"unknown R1 derivation: {derivative}")
            else:
                raw = row["cells"][name]
                if key == "core-layout":
                    value = raw
                    display = " + ".join(f"{n} {role}" for role, n in raw.items())
                elif isinstance(raw, dict) and "from" in raw:
                    prior = resolved[raw["from"]]["cells"][name]
                    if prior["state"] in {"TBD", "None"}:
                        raise ValueError("R1 derived descriptions require a defined feature")
                    value, source, state, depends = (prior[k] for k in ("value", "source", "state", "id"))
                    display = raw["format"].format(value=value, display=prior["display"])
                else:
                    cell = raw if isinstance(raw, dict) else {"value": raw}
                    value = cell["value"]
                    source, unit = cell.get("source", source), cell.get("unit", unit)
                    if value is None:
                        state, display = "TBD", "TBD"
                    elif value == "None":
                        if state != "reviewed":
                            raise ValueError("R1 absence needs a reviewed implementation")
                        state, value, display = "None", None, "None"
                    elif (type(value) in (int, float) and value <= 0) or value == "":
                        raise ValueError(f"invalid R1 quantity: {name}/{key}")
                    else:
                        display = str(value)
                        if row.get("value_unit") and isinstance(value, (int, float)):
                            display += " " + unit
            if source not in sources or name not in sources[source]["products"] or not unit:
                raise ValueError(f"unscoped R1 specification: {name}/{key}")
            if derivative != "family status" and source == "family-status":
                raise ValueError("product positioning cannot establish an R1 hardware specification")
            cells[name] = dict(id=f"r1.{name.lower()}.{key}", product=name, profile=profile["profile"],
                               metric=key, value=value, unit=unit, display=display, state=state, source=source)
            if depends:
                cells[name]["depends_on"] = depends
            if not derivative and isinstance(raw, dict) and "note" in raw:
                cells[name]["note"] = raw["note"]
        resolved[key] = dict(label=row["label"], emphasis=row.get("emphasis", False), cells=cells)

    if (profiles["TINY"]["profile"] != facts["profile_path"]
            or resolved["sram"]["cells"]["TINY"]["value"] != facts["sram"]["CapacityKiB"]):
        raise ValueError("R1 plate disagrees with the selected TINY SRAM configuration")
    return dict(as_of=catalog["as_of"], topics=topics, products=[
        {k: p[k] for k in ("name", "group", "positioning", "status")} for p in products
    ], metrics=resolved, sources=sources)


def collect(root: Path, products: list[dict], facts: dict) -> dict:
    catalog = json.loads((root / CATALOG).read_text(encoding="utf-8"))
    verify_sources(root, catalog["sources"])
    return resolve(catalog, products, facts)


def validate_pages(specs: dict, regions: list[dict], headings: list[dict], items: list, master: dict) -> dict:
    """Bind the four bookmarks to the six unchanged Figure 3 chips and paired baselines on each page."""
    plates = sorted((r for r in regions if r["kind"] == "spec-plate"), key=lambda r: r["page"])
    chips = [r for r in regions if r["kind"] == "spec-chip"]
    rows = [r for r in items if isinstance(r, dict) and r.get("kind") == "r1-spec-row"]
    if len(plates) != len(TOPICS) or len(chips) != 6 * len(TOPICS):
        raise ValueError("R1 specification guide requires four plates and 24 chips")
    first = plates[0]["page"]
    labels = [f"<tiny-family-{key}>" for key in TOPICS] + ["<tiny-r1-roadmap>"]
    sections = [(h["label"], h["page"]) for h in headings if h["label"] in labels]
    if sections != list(zip(labels, range(first, first + 5), strict=True)):
        raise ValueError("R1 specification bookmarks must precede the roadmap on consecutive pages")
    placement = {}
    for offset, (topic, plate) in enumerate(zip(specs["topics"], plates, strict=True)):
        page = first + offset
        if plate["page"] != page or any(abs(plate[k] - plates[0][k]) > 0.05 for k in ("x", "y", "width", "height")):
            raise ValueError("R1 specification plates must use identical page coordinates")
        ordered = sorted((r for r in chips if r["page"] == page), key=lambda r: r["x"])
        if len(ordered) != len(MODELS):
            raise ValueError("R1 specification page requires six product chips")
        for i, chip in enumerate(ordered):
            if (any(abs(chip[k] - master[k]) > 0.001 for k in ("width", "height", "scale"))
                    or abs(chip["y"] - ordered[0]["y"]) > 0.05
                    or chip["y"] < plate["y"] or chip["y"] + chip["height"] > plate["y"] + plate["height"]
                    or chip["x"] < plate["x"] or chip["x"] + chip["width"] > plate["x"] + plate["width"]
                    or (i and chip["x"] < ordered[i-1]["x"] + ordered[i-1]["width"])):
                raise ValueError("R1 specification chip must use unobstructed Figure 3 geometry")
            if offset and any(abs(chip[k] - placement[first][i][k]) > 0.05 for k in ("x", "y")):
                raise ValueError("R1 specification chip columns must be fixed across pages")
        local = [r for r in rows if r["page"] == page and r["topic"] == topic["key"]]
        for group in (0, 1):
            if [r["metric"] for r in local if r["group"] == group] != topic["metrics"]:
                raise ValueError("R1 specification row order or coverage differs from its source")
        for metric in topic["metrics"]:
            pair = [r["top"] for r in local if r["metric"] == metric]
            if len(pair) != 2 or abs(pair[0] - pair[1]) > 0.05:
                raise ValueError("R1 specification metric must align across both panels")
        placement[page] = ordered
    return placement
