"""PDF-bound typography and visible-route checks for the functional overview."""
from __future__ import annotations

import io

from publications.soc_diagram_geometry import routes, segment_distance

PT_PER_MM = 72 / 25.4


def contains(region: dict, char: dict, page: int, tolerance: float = 0.05) -> bool:
    return (region["page"] == page
            and char["x0"] >= region["x"] - tolerance
            and char["x1"] <= region["x"] + region["width"] + tolerance
            and char["top"] >= region["y"] - tolerance
            and char["bottom"] <= region["y"] + region["height"] + tolerance)


def collect_text_regions(diagram: dict, items: list[dict]) -> list[dict]:
    origins = [r for r in items if isinstance(r, dict) and r.get("kind") == "soc-canvas-origin"]
    if len(origins) != 1 or origins[0].get("id") != "soc-functional":
        raise ValueError("SoC diagram requires one rendered canvas origin")
    origin = origins[0]
    result = []
    for node in diagram["nodes"]:
        if node.get("compact") or node["role"] == "bus":
            result.append({"kind": "soc-compact" if node.get("compact") else "soc-bus",
                           "id": node["id"], "page": origin["page"],
                           "x": origin["x"] + node["x"] * PT_PER_MM,
                           "y": origin["y"] + node["y"] * PT_PER_MM,
                           "width": node["w"] * PT_PER_MM, "height": node["h"] * PT_PER_MM})
    emphasis = [r for r in items if isinstance(r, dict) and r.get("kind") == "soc-emphasis-region"]
    expected = sum(r["label"] for r in diagram["regions"]) + len(diagram["domains"])
    if len(emphasis) != expected or any(r["page"] != origin["page"] for r in emphasis):
        raise ValueError("SoC diagram rendered domain labels incomplete or split")
    return result + emphasis


def font_weights(pdf_page, source_font) -> dict[str, int]:
    """Identify instanced Inter outlines; variable subsets retain 'Regular' names."""
    try:
        from fontTools.ttLib import TTFont
        from fontTools.varLib.instancer import instantiateVariableFont
    except ImportError as error:
        raise ValueError("SoC PDF font checks require fonttools; use the bundled runtime") from error

    source = TTFont(source_font)
    instances = {weight: instantiateVariableFont(source, {"opsz": 14, "wght": weight}, inplace=False)
                 for weight in (400, 700)}
    weights = {}
    for ref in pdf_page["/Resources"]["/Font"].get_object().values():
        font = ref.get_object()
        child = font.get("/DescendantFonts", [font])[0].get_object()
        descriptor = child["/FontDescriptor"].get_object()
        name = str(font["/BaseFont"]).lstrip("/")
        if not name.endswith("+Inter-Regular") or "/FontFile2" not in descriptor:
            continue
        embedded = TTFont(io.BytesIO(descriptor["/FontFile2"].get_object().get_data()))
        # Compare named glyphs whose point topology survives subsetting instead
        # of trusting a subset name, head.macStyle or stripped OS/2 table.
        matches = []
        for weight, instance in instances.items():
            checked = 0
            valid = True
            for name_glyph in embedded.getGlyphOrder():
                if name_glyph not in instance["glyf"] or name_glyph in {".notdef", "space"}:
                    continue
                actual, ends, flags = embedded["glyf"][name_glyph].getCoordinates(embedded["glyf"])
                wanted, expected_ends, expected_flags = instance["glyf"][name_glyph].getCoordinates(instance["glyf"])
                if not actual:
                    continue
                # Instancing may remove redundant contour points (e.g. bold P).
                if (len(actual) != len(wanted) or ends != expected_ends
                        or [f & 1 for f in flags] != [f & 1 for f in expected_flags]):
                    continue
                if any(abs(a - b) > 1.01 for p, q in zip(actual, wanted) for a, b in zip(p, q)):
                    valid = False
                    break
                checked += 1
            if valid and checked >= 3:
                matches.append(weight)
        if len(matches) != 1:
            raise ValueError("SoC diagram embedded font does not match locked Inter 400/700 outlines")
        weights[name] = matches[0]
    return weights


def check_diagram_pdf(page, pdf_page, diagram: dict, regions: list[dict], bounds: dict, source_font) -> dict:
    weights = font_weights(pdf_page, source_font)
    relevant = [r for r in regions if r["kind"].startswith("soc-")]
    chars = [c for c in page.chars if c["text"].strip()
             and bounds["top"] - 0.05 <= c["top"] and c["bottom"] <= bounds["bottom"] + 0.05]
    counts = {"compact": 0, "bold": 0, "regular": 0}
    seen = set()
    for char in chars:
        matches = [r for r in relevant if contains(r, char, page.page_number)]
        if len(matches) > 1:
            raise ValueError("SoC diagram overlapping typography regions")
        region = matches[0] if matches else None
        kind = region["kind"] if region else "ordinary"
        compact = kind == "soc-compact"
        bold = kind in {"soc-bus", "soc-emphasis-region"}
        expected = 8 if compact else 9
        matrix = char.get("matrix", ())
        rotated = len(matrix) == 6 and abs(matrix[0]) < 1e-8 and abs(matrix[3]) < 1e-8
        size = char["width"] if rotated else char["size"]
        if abs(size - expected) > 0.05 or weights.get(char["fontname"]) != (700 if bold else 400):
            raise ValueError(f"SoC diagram PDF type mismatch at {char['text']!r}: {kind}")
        counts["compact" if compact else "bold" if bold else "regular"] += 1
        if region:
            seen.add(id(region))
    if not chars or any(id(r) not in seen for r in relevant):
        raise ValueError("SoC diagram typography region has no rendered text")
    # Real exported character boxes, including domain titles, must clear routes.
    origin = next(r for r in relevant if r.get("id") == "lp_bus")
    bus = next(n for n in diagram["nodes"] if n["id"] == "lp_bus")
    ox, oy = origin["x"] - bus["x"] * PT_PER_MM, origin["y"] - bus["y"] * PT_PER_MM
    segments = []
    for route in routes(diagram):
        for points in [route["points"], *route["heads"]]:
            converted = [[ox + p[0] * PT_PER_MM, oy + p[1] * PT_PER_MM] for p in points]
            segments.extend(zip(converted, converted[1:]))
    for char in chars:
        corners = [[char["x0"], char["top"]], [char["x1"], char["top"]],
                   [char["x1"], char["bottom"]], [char["x0"], char["bottom"]]]
        for a, b in segments:
            if any(segment_distance(a, b, c, d) < 0.01 for c, d in zip(corners, corners[1:] + corners[:1])):
                raise ValueError(f"SoC diagram route crosses PDF text {char['text']!r} at {(char['x0'], char['top'])}")
    return {"page": page.page_number, "characters": counts, "embedded_weights": weights,
            "text_regions": len(relevant), "orthogonal_routes": len(diagram["edges"])}
