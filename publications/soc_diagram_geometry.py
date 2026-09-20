"""Shared physical geometry for the CeTZ functional overview (millimetres)."""
from __future__ import annotations

import math

COMPACT_NODES = frozenset({"lp_mem", "hp_mmio", "mem_bridge", "gwa", "gwb", "gca", "gcb",
                           "dma_bridge", "jpeg_cdc", "ga2d_cdc", "ext-h_cdc", "periph_bridge", "system_bridge"})


def endpoint(node: dict, side: str, fraction: float) -> list[float]:
    if side not in {"north", "south", "east", "west"} or not 0 <= fraction <= 1:
        raise ValueError("SoC diagram invalid port")
    x, y, w, h = (node[key] for key in ("x", "y", "w", "h"))
    if side in {"north", "south"}:
        return [x + w * fraction, y + (h if side == "south" else 0)]
    return [x + (w if side == "east" else 0), y + h * fraction]


def routes(diagram: dict) -> list[dict]:
    nodes = {node["id"]: node for node in diagram["nodes"]}
    style = diagram["routing"]
    result = []
    for edge in diagram["edges"]:
        start = endpoint(nodes[edge["from"]], edge["source_side"], edge["source_position"])
        end = endpoint(nodes[edge["to"]], edge["target_side"], edge["target_position"])
        raw = [start] + [[start[i] if v == "source" else end[i] if v == "target" else v
                          for i, v in enumerate(p)] for p in edge["via"]] + [end]
        points = []
        for point in raw:
            if not points or math.dist(points[-1], point) > 1e-8:
                points.append(point)
        heads = []
        terminals = []
        if edge["kind"] == "stream" and edge.get("duplex"):
            terminals.append((points[0], points[1]))
        if edge["arrow"]:
            terminals.append((points[-1], points[-2]))
        for tip, previous in terminals:
            distance = math.dist(tip, previous)
            direction = [(previous[i] - tip[i]) / distance for i in range(2)]
            base = [tip[i] + direction[i] * style["arrow_length_mm"] for i in range(2)]
            half = style["arrow_width_mm"] / 2
            heads.append([[base[0] - direction[1] * half, base[1] + direction[0] * half],
                          tip, [base[0] + direction[1] * half, base[1] - direction[0] * half]])
        result.append({**edge, "points": points, "heads": heads})
    return result


def segment_distance(a, b, c, d) -> float:
    """Distance between closed line segments, including diagonal arrow flanks."""
    def cross(p, q, r):
        return (q[0] - p[0]) * (r[1] - p[1]) - (q[1] - p[1]) * (r[0] - p[0])

    def point_distance(p, q, r):
        length = sum((r[i] - q[i]) ** 2 for i in range(2))
        t = max(0, min(1, sum((p[i] - q[i]) * (r[i] - q[i]) for i in range(2)) / length)) if length else 0
        return math.dist(p, [q[i] + t * (r[i] - q[i]) for i in range(2)])

    if (cross(a, b, c) * cross(a, b, d) <= 0 and cross(c, d, a) * cross(c, d, b) <= 0
            and all(max(min(a[i], b[i]), min(c[i], d[i])) <= min(max(a[i], b[i]), max(c[i], d[i])) + 1e-9 for i in range(2))):
        return 0.0
    return min(point_distance(a, c, d), point_distance(b, c, d), point_distance(c, a, b), point_distance(d, a, b))


def geometry_issues(diagram: dict) -> list[str]:
    paths = routes(diagram)
    style = diagram["routing"]
    issues = []
    for path in paths:
        points = path["points"]
        segments = list(zip(points, points[1:]))
        for a, b in segments:
            if abs(a[0] - b[0]) > 1e-8 and abs(a[1] - b[1]) > 1e-8:
                issues.append(f"{path['id']}: non-orthogonal segment {a} {b}")
            for node in diagram["nodes"]:
                if node["id"] in {path["from"], path["to"]} or node["role"] in {"io", "rail"}:
                    continue
                lo, hi = 0.0, 1.0
                for axis, coordinate, size in ((0, "x", "w"), (1, "y", "h")):
                    delta = b[axis] - a[axis]
                    lower, upper = node[coordinate] + 0.1, node[coordinate] + node[size] - 0.1
                    if abs(delta) < 1e-8:
                        if not lower < a[axis] < upper:
                            lo, hi = 1, 0
                            break
                    else:
                        first, last = sorted(((lower - a[axis]) / delta, (upper - a[axis]) / delta))
                        lo, hi = max(lo, first), min(hi, last)
                if lo < hi:
                    issues.append(f"{path['id']}: route enters unrelated symbol {node['id']}")
        minimum = style["arrow_length_mm"] + style["visible_shaft_mm"]
        if path["arrow"] and math.dist(*segments[-1]) < minimum - 1e-8:
            issues.append(f"{path['id']}: short terminal shaft")
        if path.get("duplex") and path["kind"] == "stream":
            first_minimum = minimum + (style["arrow_length_mm"] if len(segments) == 1 else 0)
            if math.dist(*segments[0]) < first_minimum - 1e-8:
                issues.append(f"{path['id']}: short duplex shaft")
        # Clearance is measured outside the two physical stroke envelopes.
        clearance = style["arrow_clearance_mm"] + style["stroke_pt"] * 25.4 / 72
        for other in paths:
            if other["id"] == path["id"]:
                continue
            for head in other["heads"]:
                if any(segment_distance(a, b, c, d) < clearance - 1e-8
                       for a, b in segments for c, d in zip(head, head[1:])):
                    issues.append(f"{path['id']}: arrow clearance at {other['id']}")
    return issues


def validate_geometry(diagram: dict) -> None:
    issues = geometry_issues(diagram)
    if issues:
        raise ValueError("SoC diagram geometry: " + "; ".join(issues))
