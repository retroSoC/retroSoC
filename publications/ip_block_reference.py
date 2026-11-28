"""Source-bound monochrome IP views and deterministic, millimetre geometry.

The existing circuit catalogs remain the facts. This module prepares their
publication view and exports it; no RTL or register generator is introduced.
"""

from __future__ import annotations

from collections import Counter
from copy import deepcopy
from functools import lru_cache
import hashlib
import heapq
import json
import math
from pathlib import Path
import re
import struct
import subprocess

STYLE = "ip-block-v2"
PT_MM = 25.4 / 72
SYSTEM_IDS = {"system-fabric", "system-clocks", "system-media", "system-mpw"}
SOURCES = {
    "publications/ip_block_reference.py",
    "publications/ip_block_layout.py",
    "publications/ip-block-diagrams.typ",
}


def font_advances(path: Path) -> dict[str, float]:
    """Read default Inter advances without adding a runtime dependency."""
    raw = path.read_bytes()
    tables = {}
    for i in range(struct.unpack_from(">H", raw, 4)[0]):
        tag, _, offset, _ = struct.unpack_from(">4sIII", raw, 12 + 16 * i)
        tables[tag] = offset
    upm = struct.unpack_from(">H", raw, tables[b"head"] + 18)[0]
    metrics = struct.unpack_from(">H", raw, tables[b"hhea"] + 34)[0]
    cmap = tables[b"cmap"]
    subtables = []
    for i in range(struct.unpack_from(">H", raw, cmap + 2)[0]):
        _, _, offset = struct.unpack_from(">HHI", raw, cmap + 4 + 8 * i)
        start = cmap + offset
        kind = struct.unpack_from(">H", raw, start)[0]
        if kind in {4, 12}:
            subtables.append((kind, start))
    kind, start = max(subtables)

    def glyph(code):
        if kind == 12:
            for i in range(struct.unpack_from(">I", raw, start + 12)[0]):
                lo, hi, first = struct.unpack_from(">III", raw, start + 16 + i * 12)
                if lo <= code <= hi:
                    return first + code - lo
        else:
            n = struct.unpack_from(">H", raw, start + 6)[0] // 2
            for i in range(n):
                hi = struct.unpack_from(">H", raw, start + 14 + 2 * i)[0]
                lo = struct.unpack_from(">H", raw, start + 16 + 2 * n + 2 * i)[0]
                if lo <= code <= hi:
                    delta = struct.unpack_from(">h", raw, start + 16 + 4 * n + 2 * i)[0]
                    where = start + 16 + 6 * n + 2 * i
                    jump = struct.unpack_from(">H", raw, where)[0]
                    value = (
                        struct.unpack_from(">H", raw, where + jump + 2 * (code - lo))[0]
                        if jump
                        else code
                    )
                    return (value + delta) & 65535 if value else 0
        return 0

    return {
        chr(c): struct.unpack_from(">H", raw, tables[b"hmtx"] + 4 * min(glyph(c), metrics - 1))[0]
        / upm
        for c in [*range(32, 127), 0x00B5, 0x00D7, 0x00B0, 0x03A9]
    }


def text_width(text: str, advances: dict, size: float = 9) -> float:
    return sum(advances.get(c, 1) for c in text) * size * PT_MM


def wrap(text: str, width: float, advances: dict, *, bold: bool = False) -> list[str]:
    lines = []
    for paragraph in text.split("\n"):
        line = ""
        for word in paragraph.split():
            trial = (line + " " + word).strip()
            if text_width(trial, advances) * (1.08 if bold else 1) <= width:
                line = trial
            else:
                if line:
                    lines.append(line)
                line = word
                if text_width(word, advances) * (1.08 if bold else 1) > width:
                    # Real RTL names may wrap at underscores, never change spelling.
                    chunk = ""
                    for piece in re.findall(r"[^_-]+[_-]*|[_-]+", word):
                        if text_width(piece, advances) <= width:
                            if chunk and text_width(chunk + piece, advances) > width:
                                lines.append(chunk)
                                chunk = ""
                            chunk += piece
                        else:
                            for char in piece:
                                if chunk and text_width(chunk + char, advances) > width:
                                    lines.append(chunk)
                                    chunk = ""
                                chunk += char
                    # Keep short direction/reset suffixes together: ending a
                    # pin label with a lone "o" obscures the signal identity.
                    if "_" in word and len(chunk.strip("_")) <= 1 and lines:
                        match = re.fullmatch(r"(.+_)([^_]+_)", lines[-1])
                        if match and text_width(match[2] + chunk, advances) <= width:
                            lines[-1], chunk = match[1], match[2] + chunk
                    line = chunk
        lines.append(line)
    return lines


def inside(point, box, margin=0):
    return (
        box[0] - margin < point[0] < box[0] + box[2] + margin
        and box[1] - margin < point[1] < box[1] + box[3] + margin
    )


def overlaps(a, b, gap=0):
    return (
        a[0] < b[0] + b[2] + gap
        and b[0] < a[0] + a[2] + gap
        and a[1] < b[1] + b[3] + gap
        and b[1] < a[1] + a[3] + gap
    )


def orthogonal_path(
    start: list,
    end: list,
    obstacles: list,
    width: int,
    height: int,
    used: Counter,
    initial=(1, 0),
    terminal=(1, 0),
    margin=1.4,
    reservations=None,
) -> list:
    """Route around boxes; prefer short paths and unoccupied channels."""
    s, t = tuple(map(round, start)), tuple(map(round, end))
    blocked = set()
    near = set()
    for x, y, w, h in obstacles:
        for px in range(max(1, math.floor(x - 5)), min(width, math.ceil(x + w + 5)) + 1):
            for py in range(max(1, math.floor(y - 5)), min(height, math.ceil(y + h + 5)) + 1):
                near.add((px, py))
        for px in range(max(1, math.floor(x - margin)), min(width, math.ceil(x + w + margin)) + 1):
            for py in range(
                max(1, math.floor(y - margin)), min(height, math.ceil(y + h + margin)) + 1
            ):
                if x - margin < px < x + w + margin and y - margin < py < y + h + margin:
                    blocked.add((px, py))
    blocked.discard(s)
    blocked.discard(t)
    lanes, corners = reservations or (set(), set())
    queue = [(0, 0, s, initial)]
    best, previous = {(s, initial): 0}, {}
    finish = None
    while queue:
        _, cost, p, direction = heapq.heappop(queue)
        if cost > best.get((p, direction), math.inf):
            continue
        if p == t and direction != (-terminal[0], -terminal[1]):
            finish = (p, direction)
            break
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            q = (p[0] + dx, p[1] + dy)
            if not (2 <= q[0] <= width - 2 and 2 <= q[1] <= height - 2) or q in blocked:
                continue
            d = (dx, dy)
            axis = "h" if dx else "v"
            step = (min(p[0], q[0]), p[1], axis) if dx else (p[0], min(p[1], q[1]), axis)
            if step in lanes or (q in corners and q != t):
                continue
            if (q == t and d == (-terminal[0], -terminal[1])) or q == s:
                continue
            if p == s and d == (-initial[0], -initial[1]):
                continue
            value = (
                cost
                + 1
                + (3 if direction is not None and direction != d else 0)
                + min(used[q], 4) * 2
                + (6 if q in near else 0)
            )
            key = (q, d)
            if value < best.get(key, math.inf):
                best[key] = value
                previous[key] = (p, direction)
                heapq.heappush(queue, (value + abs(q[0] - t[0]) + abs(q[1] - t[1]), value, q, d))
    if finish is None:
        raise ValueError(f"IP route cannot reach its bound port: {start} -> {end}")
    points = []
    while finish in previous:
        points.append(list(finish[0]))
        finish = previous[finish]
    points.append(list(s))
    points.reverse()
    for p in points:
        used[tuple(p)] += 1
    simple = [points[0]]
    for i in range(1, len(points) - 1):
        a, b, c = points[i - 1 : i + 2]
        if (a[0] == b[0]) != (b[0] == c[0]):
            simple.append(b)
    simple.append(points[-1])
    return [list(start), *simple[1:-1], list(end)]


def route_reservations(wires: list[dict], source_key: str, kind: str):
    """Different nets may cross, but must never share a shaft or a bend."""
    lanes, corners = set(), set()
    for wire in wires:
        if wire["source_key"] == source_key:
            continue
        distance = (
            3 if kind == wire["kind"] == "data" else 2 if "data" in (kind, wire["kind"]) else 1
        )
        corners.update(tuple(p) for p in wire["points"])
        for a, b in zip(wire["points"], wire["points"][1:]):
            if a[1] == b[1]:
                for x in range(min(a[0], b[0]), max(a[0], b[0])):
                    for delta in range(1 - distance, distance):
                        lanes.add((x, a[1] + delta, "h"))
            else:
                for y in range(min(a[1], b[1]), max(a[1], b[1])):
                    for delta in range(1 - distance, distance):
                        lanes.add((a[0] + delta, y, "v"))
    return lanes, corners


def arrow_polygon(points: list, width: float = 2) -> list:
    """Outline a wide data arrow, including orthogonal bends."""
    half = width / 2
    if len(points) < 2:
        raise ValueError("IP arrow has no shaft")
    tip = points[-1]
    before = points[-2]
    length = math.dist(tip, before)
    if length < 3:
        raise ValueError(f"IP data arrow terminal is too short: {points}")
    dx, dy = ((tip[i] - before[i]) / length for i in range(2))
    base = [tip[0] - dx * 2.8, tip[1] - dy * 2.8]
    path = [*points[:-1], base]
    left, right = [], []
    for i, p in enumerate(path):
        if i == 0:
            q = path[1]
            label_entry = math.dist(p, q)
            normal = [-(q[1] - p[1]) / label_entry, (q[0] - p[0]) / label_entry]
            left.append([p[0] + normal[0] * half, p[1] + normal[1] * half])
            right.append([p[0] - normal[0] * half, p[1] - normal[1] * half])
        elif i == len(path) - 1:
            normal = [-dy, dx]
            left.append([p[0] + normal[0] * half, p[1] + normal[1] * half])
            right.append([p[0] - normal[0] * half, p[1] - normal[1] * half])
        else:
            a, b = path[i - 1], path[i + 1]
            u = [(p[k] - a[k]) / math.dist(p, a) for k in range(2)]
            v = [(b[k] - p[k]) / math.dist(p, b) for k in range(2)]
            normal = [-u[1] - v[1], u[0] + v[0]]
            left.append([p[0] + normal[0] * half, p[1] + normal[1] * half])
            right.append([p[0] - normal[0] * half, p[1] - normal[1] * half])
    return [
        *left,
        [base[0] - dy * 2.3, base[1] + dx * 2.3],
        tip,
        [base[0] + dy * 2.3, base[1] - dx * 2.3],
        *reversed(right),
    ]


def port_position(node: dict, side: str, index: int, count: int) -> list:
    x, y, w, h = (node[k] for k in ("x", "y", "w", "h"))
    fraction = (index + 1) / (count + 1)
    if side in {"west", "east"}:
        return [x + (w if side == "east" else 0), round(y + h * fraction)]
    return [round(x + w * fraction), y + (h if side == "south" else 0)]


def _make_scene(circuit: dict, advances: dict, strategy: str) -> dict:
    view = deepcopy(circuit["block_diagram"])
    nodes = {n["id"]: n for n in circuit["nodes"]}
    rows = view["rows"]
    placed = {}
    clock_ports = view.get("ports", [])
    if "port_selection" in view:
        clock_ports = [p for p in clock_ports if p["name"] in view["port_selection"]]
    if view.get("port_layout") == "grouped":
        clock_ports = [p for p in clock_ports if p["direction"] == "input" or p["role"] == "irq"]
    port_offsets = {"left": 15, "right": 15}
    for port in clock_ports:
        side = "left" if port["direction"] == "input" else "right"
        port["lines"] = wrap(port["name"], 22, advances)
        h = max(3.8, len(port["lines"]) * 3.7)
        port["y"] = port_offsets[side] + h / 2
        port_offsets[side] += max(5, h + 1)
    y = max(29, math.ceil(max(port_offsets.values()) + 4))
    first_y = y
    for row in rows:
        n = len(row)
        gutter = 26 if n == 2 else 12
        width = math.floor((98 - gutter * (n - 1)) / n)
        height = 20
        for i, key in enumerate(row):
            item = nodes[key]
            lines = wrap(view.get("titles", {}).get(key, item["title"]), width - 4, advances)
            h = max(18, math.ceil(len(lines) * 3.7 + 3))
            height = max(height, h)
            placed[key] = dict(
                id=key,
                x=36 + i * (width + gutter),
                y=y,
                w=width,
                h=h,
                lines=lines,
                role="internal",
                shape=view.get("shapes", {}).get(key, "block"),
                condition=item.get("condition"),
            )
        for key in row:
            placed[key]["h"] = height
        y += height + view.get("row_gap", 14 if len(rows) >= 4 else 18)
    bottom = y - 10
    # External context is outside the gray IP boundary; never masquerades as owned logic.
    external = view.get("external", [])
    body_height = max(bottom - first_y, 30 * math.ceil(len(external) / 2))
    bottom = first_y + body_height
    external_counts = Counter()
    external_sides = {}
    for key in external:
        incoming = any(e["to"].split(".")[0] == key for e in circuit["edges"])
        outgoing = any(e["from"].split(".")[0] == key for e in circuit["edges"])
        external_sides[key] = view.get("external_sides", {}).get(
            key, "left" if outgoing and not incoming else "right"
        )
    totals = Counter(external_sides.values())
    external_items = {}
    side_heights = Counter()
    for key in external:
        item = nodes[key]
        edge_labels = list(
            dict.fromkeys(
                e["label"]
                for e in circuit["edges"]
                if key in {e["from"].split(".")[0], e["to"].split(".")[0]}
            )
        )
        lines = wrap(
            view.get("titles", {}).get(key, item["title"]) + "\n" + "; ".join(edge_labels),
            20,
            advances,
        )
        h = max(18, math.ceil(len(lines) * 3.7 + 3))
        external_items[key] = (lines, h)
        side_heights[external_sides[key]] += h + 6
    body_height = max(body_height, max(side_heights.values(), default=0))
    bottom = first_y + body_height
    side_offsets = {
        side: first_y + (body_height - (side_heights[side] - 6 * totals[side])) / (totals[side] + 1)
        for side in totals
    }
    for i, key in enumerate(external):
        item = nodes[key]
        edge_labels = list(
            dict.fromkeys(
                e["label"]
                for e in circuit["edges"]
                if key in {e["from"].split(".")[0], e["to"].split(".")[0]}
            )
        )
        lines, height = external_items[key]
        side = external_sides[key]
        index = external_counts[side]
        external_counts[side] += 1
        yy = round(side_offsets[side])
        side_offsets[side] += height + (body_height - (side_heights[side] - 6 * totals[side])) / (
            totals[side] + 1
        )
        if side == "left" and view.get("buses"):
            yy = max(yy, 68 + index * 30)
        placed[key] = dict(
            id=key,
            x=2 if side == "left" else 146,
            y=yy,
            w=24,
            h=height,
            lines=lines,
            role="external",
            shape="block",
        )
    for i, key in enumerate(view.get("buses", [])):
        item = nodes[key]
        side = view.get("bus_sides", {}).get(key, "left")
        bus_target = placed[view.get("bus_targets", {}).get(key, rows[0][0])]
        yy = round(
            bus_target["y"]
            + bus_target["h"] / 2
            - 11
            + i * body_height / max(1, len(view["buses"]))
            + view.get("bus_offsets", {}).get(key, 0)
        )
        title = view.get("titles", {}).get(key, item["title"])
        placed[key] = dict(
            id=key,
            x=23 if side == "left" else 149,
            y=yy,
            w=0,
            h=22,
            lines=wrap(title, 19, advances),
            role="bus",
            shape="bus",
            side=side,
        )
    if set(placed) != set(nodes):
        raise ValueError("IP view omits or duplicates a source-bound functional unit")
    bottom = max(
        bottom,
        max(
            (n["y"] + n["h"] + 5 for n in placed.values() if n["role"] == "external"),
            default=bottom,
        ),
    )
    height = math.ceil(bottom + 28)
    if height > 200:
        raise ValueError("IP primary needs a functional-group detail view")
    result = dict(
        width=172,
        height=height,
        boundary=[28, 13, 114, bottom - 10],
        nodes=list(placed.values()),
        groups=[],
        wires=[],
        labels=[],
        legend=[],
        style=STYLE,
        ports=clock_ports,
        interfaces=view.get("interfaces", []),
    )
    # Port ordering is fixed by source edge order and the selected endpoint side.
    ends = []
    counts = Counter()
    port_indexes = {}
    for i, edge in enumerate(circuit["edges"]):
        a, b = [placed[edge[k].split(".")[0]] for k in ("from", "to")]
        ax, ay = a["x"] + a["w"] / 2, a["y"] + a["h"] / 2
        bx, by = b["x"] + b["w"] / 2, b["y"] + b["h"] / 2
        if a["role"] == "bus":
            sa, sb = ("east", "west") if a["x"] < b["x"] else ("west", "east")
        elif b["role"] == "bus":
            sa, sb = ("west", "east") if b["x"] < a["x"] else ("east", "west")
        elif abs(bx - ax) > abs(by - ay):
            sa, sb = ("east", "west") if bx > ax else ("west", "east")
        else:
            sa, sb = ("south", "north") if by > ay else ("north", "south")
        if a["shape"] == "mux":
            sa = "east"
        if b["shape"] == "mux":
            sb = "west"

        def physical(node, endpoint):
            bound = next(
                (p for p in edge.get("instance_ports", []) if p["node"] == node["id"]), None
            )
            if bound:
                return node["id"] + ":" + bound["port"] + ":" + bound["expression"]
            signals = edge.get("member_signals", [])
            field = "source_port" if node["id"] == edge["from"].split(".")[0] else "target_port"
            if signals and all(field in signal for signal in signals):
                return (
                    node["id"]
                    + ":"
                    + json.dumps(sorted((signal[field], signal["net"]) for signal in signals))
                )
            return endpoint

        source_key = physical(a, edge["from"])
        target_key = physical(b, edge["to"])
        for node, side, key in [(a, sa, source_key), (b, sb, target_key)]:
            slot = (node["id"], side, key)
            if slot not in port_indexes:
                port_indexes[slot] = counts[(node["id"], side)]
                counts[(node["id"], side)] += 1
        ends.append((a, b, sa, sb, source_key, target_key))
    used = Counter()
    orders = Counter()
    obstacles = [
        [n[k] for k in ("x", "y", "w", "h")] for n in placed.values() if n["role"] != "bus"
    ]
    vectors = {"west": (-1, 0), "east": (1, 0), "north": (0, -1), "south": (0, 1)}
    terminal_stubs = []
    for edge, (a, b, sa, sb, source_key, target_key) in zip(circuit["edges"], ends):
        for node, side, key in [(a, sa, source_key), (b, sb, target_key)]:
            point = port_position(
                node, side, port_indexes[(node["id"], side, key)], counts[(node["id"], side)]
            )
            away = [point[k] + vectors[side][k] * 3 for k in range(2)]
            terminal_stubs.append(
                dict(points=[point, away], source_key=source_key, kind=edge["kind"])
            )

    def route_order(index):
        a, b, *_ = ends[index]
        distance = abs(a["x"] + a["w"] / 2 - b["x"] - b["w"] / 2) + abs(
            a["y"] + a["h"] / 2 - b["y"] - b["h"] / 2
        )
        priority = (
            -distance
            if strategy == "span"
            else distance
            if strategy == "short"
            else -index
            if strategy == "reverse"
            else index
        )
        return (circuit["edges"][index]["kind"] != "data", priority, index)

    for i in sorted(range(len(circuit["edges"])), key=route_order):
        edge = circuit["edges"][i]
        a, b, sa, sb, source_key, target_key = ends[i]
        start = port_position(a, sa, port_indexes[(a["id"], sa, source_key)], counts[(a["id"], sa)])
        end = port_position(b, sb, port_indexes[(b["id"], sb, target_key)], counts[(b["id"], sb)])
        orders[(a["id"], sa)] += 1
        orders[(b["id"], sb)] += 1
        vectors = {"west": (-1, 0), "east": (1, 0), "north": (0, -1), "south": (0, 1)}
        va, vb = vectors[sa], vectors[sb]
        escape = [start[k] + va[k] * 3 for k in range(2)]
        approach = [end[k] + vb[k] * 3 for k in range(2)]
        middle = orthogonal_path(
            escape,
            approach,
            obstacles,
            172,
            math.ceil(bottom + 4),
            used,
            va,
            (-vb[0], -vb[1]),
            2.4 if edge["kind"] == "data" else 1.4,
            route_reservations([*result["wires"], *terminal_stubs], source_key, edge["kind"]),
        )
        points = []
        for point in [start, *middle, end]:
            if not points or point != points[-1]:
                points.append(point)
        # Collapse collinear segments without losing the terminal arrow shaft.
        simple = [points[0]]
        for j in range(1, len(points) - 1):
            p, q, r = points[j - 1 : j + 2]
            if (p[0] == q[0]) != (q[0] == r[0]):
                simple.append(q)
        simple.append(points[-1])
        wire = dict(
            index=i,
            points=simple,
            kind=edge["kind"],
            label=edge["label"],
            from_node=a["id"],
            to_node=b["id"],
            source_key=source_key,
            target_key=target_key,
        )
        if edge["kind"] == "data":
            wire["polygon"] = arrow_polygon(simple)
        result["wires"].append(wire)
    result["wires"].sort(key=lambda w: w["index"])
    for i, wire in enumerate(result["wires"]):
        edge = circuit["edges"][i]
        endpoint = next(
            (
                n
                for n in placed.values()
                if n["id"] in {wire["from_node"], wire["to_node"]} and n["role"] != "internal"
            ),
            None,
        )
        if endpoint is not None:
            wire["label_mode"] = "interface" if endpoint["role"] == "bus" else "endpoint"
            wire["label_node"] = endpoint["id"]
            continue
        source_title = nodes[wire["from_node"]]["title"]
        if edge["label"].casefold() == source_title.replace("\n", " ").casefold():
            wire["label_mode"] = "source"
            continue
        box = find_label(edge["label"], wire, result, obstacles, advances, first_y, 5)
        text = edge["label"]
        if box is None:
            text = chr(65 + i) if i < 26 else str(i + 1)
            box = find_label(text, wire, result, obstacles, advances, first_y, 1.2)
            if box is None:
                pair = (wire["from_node"], wire["to_node"], wire["kind"])
                if (
                    sum((w["from_node"], w["to_node"], w["kind"]) == pair for w in result["wires"])
                    != 1
                ):
                    raise ValueError(
                        "IP wire label needs a dedicated routing lane: " + edge["label"]
                    )
                wire["label_mode"] = "legend"
                result["legend"].append(
                    dict(
                        key="",
                        text=wire["kind"].title()
                        + ": "
                        + source_title.split("\n")[0]
                        + " → "
                        + nodes[wire["to_node"]]["title"].split("\n")[0]
                        + ": "
                        + edge["label"],
                        edge=i,
                    )
                )
                continue
            result["legend"].append(dict(key=text, text=edge["label"], edge=i))
        result["labels"].append(dict(text=text, x=box[0], y=box[1], w=box[2], h=box[3], edge=i))
    result["junctions"] = junctions(result["wires"])
    # Bundle spines are sourced from real wrapper interfaces. Response channels
    # belong to the same protocol bundle; they are not a second initiator.
    interface_totals = Counter((i["node"], i["side"]) for i in result["interfaces"])
    interface_offsets = Counter()
    for interface in result["interfaces"]:
        target = placed[interface["node"]]
        group = (interface["node"], interface["side"])
        count = interface_totals[group]
        offset = (interface_offsets[group] - (count - 1) / 2) * 12 + interface.get("offset", 0)
        interface_offsets[group] += 1
        if count > 2:
            raise ValueError("IP interface group requires a separate detail")
        interface.update(
            y=round(target["y"] + target["h"] / 2 + offset),
            x=23 if interface["side"] == "left" else 149,
            span=8 if count > 1 else 20,
            lines=[str(interface["width"]) + "-bit", *wrap(interface["protocol"], 19, advances)],
        )
    # Compact, explicit supplementary labels in two columns when a shaft is too short.
    legend_end = bottom + 5
    for i in range(0, len(result["legend"]), 2):
        row = result["legend"][i : i + 2]
        for j, entry in enumerate(row):
            entry.update(
                x=4 + j * 84,
                y=legend_end,
                lines=wrap(
                    (entry["key"] + ": " if entry["key"] else "") + entry["text"], 80, advances
                ),
            )
        legend_end += max(len(entry["lines"]) for entry in row) * 3.7 + 0.7
    result["height"] = math.ceil(
        max(
            bottom + 8,
            legend_end + 4,
            max((p[1] + 4 for w in result["wires"] for p in w["points"]), default=bottom),
        )
    )
    if result["height"] > 200:
        raise ValueError("IP legend needs a separate detail panel")
    return result


def make_scene(circuit: dict, advances: dict) -> dict:
    from publications.ip_block_layout import drawing_graph, overview_edges
    from publications.ip_block_layout import make_scene as explicit_scene

    view = circuit["block_diagram"]
    if not view.get("functional"):
        raise ValueError("IP has no reviewed functional expansion and explicit layout")
    graph = view["functional"]
    if view.get("route_details"):
        graph = drawing_graph(graph, overview_edges(view))
    return explicit_scene(circuit, advances, graph)


def scoped_route_detail(identifier: str, parent: dict, spec: dict, advances: dict) -> dict:
    """Render a subset of already verified local paths from the same product graph."""
    from publications.ip_block_layout import drawing_graph

    view = parent["block_diagram"]
    title = f"{view['title']} / {spec['title']}"
    graph = drawing_graph(view["functional"], set(spec["edges"]))
    if "layout" in spec:
        graph["layout"] = spec["layout"]
    elif "frame" in spec:
        graph["layout"].update(spec["frame"])
    owners = {node["owner"] for node in graph["nodes"]}
    detail = {
        "block_diagram": {
            **view,
            "title": title,
            "boundary_title": spec.get("boundary_title", view.get("boundary_title", view["title"])),
            "functional": graph,
            "ports": [],
            "interfaces": [],
            "details": [],
            "route_details": [],
            "scope": "local-routes",
        },
        "nodes": [node for node in parent["nodes"] if node["id"] in owners],
        "edges": [],
        "note": spec["note"],
        "product": view["product"],
        "renderer": "cetz",
        "parent_id": identifier,
        "detail_id": identifier + "-detail-" + spec["id"],
        "block_title": title + " block diagram",
    }
    detail["scene"] = make_scene(detail, advances)
    return detail


def validate_view(root: Path, circuit: dict) -> None:
    view = circuit.get("block_diagram")
    if not view or view.get("style") != STYLE:
        raise ValueError("IP has no reviewed block-diagram view")
    foreign = "rtl/mini/" if view.get("product") == "tiny" else "rtl/tiny/"
    if any(path.startswith(foreign) for path in trace_paths({"view": circuit})):
        raise ValueError("IP metadata uses another product's RTL")
    ids = [n["id"] for n in circuit["nodes"]]
    slots = (
        [key for row in view["rows"] for key in row]
        + view.get("external", [])
        + view.get("buses", [])
    )
    if Counter(slots) != Counter(ids):
        raise ValueError("IP functional boundaries omit or duplicate nodes")
    if not view["rows"] or any(not row or len(row) > 3 for row in view["rows"]):
        raise ValueError("IP row layout is invalid")
    if set(view.get("shapes", {})) - set(ids) or set(view.get("shapes", {}).values()) - {
        "block",
        "mux",
        "divider",
        "gate",
        "fifo",
    }:
        raise ValueError("IP symbol is unknown")
    owned = {x for row in view["rows"] for x in row}
    for node in circuit["nodes"]:
        if (
            node.get("instance_source", {}).get("file") in view.get("wrapper", [])
            and node["id"] not in owned
        ):
            raise ValueError("Owned RTL instance placed outside IP boundary")
    interfaces = view.get("interfaces", [])
    if len({(i["protocol"], i["side"], i["node"], i.get("port")) for i in interfaces}) != len(
        interfaces
    ):
        raise ValueError("IP interface is duplicated")
    for interface in interfaces:
        if (
            interface["node"] not in ids
            or type(interface["width"]) is not int
            or interface["width"] <= 0
        ):
            raise ValueError("IP interface width or owner is invalid")
        widths = {
            p["width"]
            for n in circuit["nodes"]
            if n["id"] == interface["node"]
            for p in n["ports"]
            if p["width"] is not None
        }
        if interface["protocol"] == "APB4" and interface["width"] != 32:
            raise ValueError("IP APB width differs from product bus")
        proof = interface.get("width_binding")
        if proof:
            for relative in [proof["file"], *(b["file"] for b in proof["connections"])]:
                if not relative.startswith("rtl/") or not (
                    root / relative
                ).resolve().is_relative_to(root.resolve()):
                    raise ValueError("IP bus width proof escapes RTL")
            candidates = source_members(root, proof["file"], ("axi4_if",))
            instance = next((u for u in candidates if u["id"] == proof["instance"]), None)
            if instance is None or instance["parameters"].get("DATA_WIDTH") != interface["width"]:
                raise ValueError("IP bus width differs from selected interface instance")
            for binding in proof["connections"]:
                if re.sub(r"\s+", "", binding["text"]) not in re.sub(
                    r"\s+", "", (root / binding["file"]).read_text(encoding="utf-8")
                ):
                    raise ValueError("IP bus instance connection changed")
        if interface["protocol"] == "AXI4" and interface["width"] not in widths and not proof:
            raise ValueError("IP AXI data width lacks a bound endpoint")
    if not view.get("wrapper") or not view.get("review"):
        raise ValueError("IP block view lacks its source scope and review")
    for source in view["wrapper"]:
        path = (root / source).resolve()
        if (
            not path.is_relative_to(root.resolve())
            or not source.startswith("rtl/")
            or not path.is_file()
        ):
            raise ValueError("IP wrapper is not a current RTL source")
    for port in view.get("ports", []):
        if port["file"] not in view["wrapper"]:
            raise ValueError("IP clock/reset/IRQ belongs to a different wrapper")
        declarations = boundary_ports(root / port["file"])
        if not any(
            p["name"] == port["name"]
            and p["direction"] == port["direction"]
            and p["role"] == port["role"]
            for p in declarations
        ):
            raise ValueError("IP boundary signal has no matching source declaration")
    expected_ports = {
        (source, p["name"], p["direction"], p["role"])
        for source in view["wrapper"]
        for p in boundary_ports(root / source)
    }
    if expected_ports != {
        (p["file"], p["name"], p["direction"], p["role"]) for p in view.get("ports", [])
    }:
        raise ValueError("IP clock/reset/IRQ boundary is incomplete")
    if "port_selection" in view and (
        not view["review"] or not set(view["port_selection"]) <= {p["name"] for p in view["ports"]}
    ):
        raise ValueError("IP selected integration ports are unknown")
    for interface in view.get("interfaces", []):
        path = (root / interface["file"]).resolve()
        if not interface["file"].startswith("rtl/") or not path.is_relative_to(root.resolve()):
            raise ValueError("IP interface source escapes RTL")
        source = (root / interface["file"]).read_text(encoding="utf-8")
        expression = re.escape(interface["declaration"]) + (
            r"\s+" + re.escape(interface["port"]) + r"\b" if interface.get("port") else ""
        )
        if not re.search(expression, source):
            raise ValueError("IP interface bundle lost its wrapper declaration")
        expected_direction = {
            "axi4_stream_if.source": "output",
            "axi4_stream_if.sink": "input",
        }.get(interface["declaration"])
        if expected_direction and interface.get("direction") != expected_direction:
            raise ValueError("IP stream direction differs from its source")
    stream_ports = {
        (source, decl, port)
        for source in view["wrapper"]
        for decl, port in re.findall(
            r"(axi4_stream_if\.(?:source|sink))\s+(\w+)",
            (root / source).read_text(encoding="utf-8").split(");", 1)[0],
        )
    }
    covered = {(i["file"], i["declaration"], i.get("port")) for i in interfaces}
    if circuit.get("block_diagram", {}).get("title") == "APU" and not stream_ports <= covered:
        raise ValueError("IP stream boundary interface is omitted")
    for node in circuit["nodes"]:
        units = node.get("units", [])
        if len({u["id"] for u in units}) != len(units):
            raise ValueError("IP duplicates a functional source instance")
        for unit in units:
            candidates = source_members(
                root, unit["bindings"][0]["file"], (unit["module"],), scope=unit.get("scope_module")
            )
            actual = next(
                (u for u in candidates if u["id"] == unit["id"] and u["module"] == unit["module"]),
                None,
            )
            if (
                actual is None
                or actual["ports"] != unit["ports"]
                or actual.get("parameters", {}) != unit.get("parameters", {})
                or actual.get("parameters_raw", {}) != unit.get("parameters_raw", {})
            ):
                raise ValueError("IP functional instance ports or parameters differ from source")
            for binding in unit["bindings"]:
                source = (root / binding["file"]).read_text(encoding="utf-8")
                if re.sub(r"\s+", "", binding["text"]) not in re.sub(r"\s+", "", source):
                    raise ValueError("IP functional unit lost its RTL binding")


def validate_sources(root: Path, product: str, circuits: dict) -> None:
    """Validate functional facts without requiring publication fonts or routing."""
    for identifier, circuit in circuits.items():
        if identifier in SYSTEM_IDS:
            continue
        if circuit.get("block_diagram", {}).get("product") != product:
            raise ValueError("IP block view crosses product boundaries")
        validate_view(root, circuit)
        from publications.ip_block_layout import overview_edges, validate_functional

        validate_functional(root, circuit, circuit["block_diagram"]["functional"])
        overview_edges(circuit["block_diagram"])
        for spec in circuit["block_diagram"].get("details", []):
            owner = next((n for n in circuit["nodes"] if n["id"] == spec["owner"]), None)
            if owner is None:
                raise ValueError("IP detail lost its owning functional group")
            members = {u["id"]: u for u in owner.get("units", [])}
            if not set(spec["members"]) <= members.keys():
                raise ValueError("IP detail refers to unknown functional members")
            resolved = {**spec, "units": [members[k] for k in spec["members"]]}
            detail = make_detail(
                root, product, identifier, circuit, resolved, {}, build_scene=False
            )
            detail["block_diagram"]["ports"] = detail_ports(root, spec)
            validate_functional(root, detail, spec["functional"])


def prepare(root: Path, product: str, circuits: dict) -> None:
    from publications.ip_block_layout import review_issues

    validate_sources(root, product, circuits)
    advances = font_advances(
        root / "publications/media/fonts/inter/Inter-VariableFont_opsz,wght.ttf"
    )
    for identifier, circuit in circuits.items():
        if identifier in SYSTEM_IDS:
            continue
        circuit["scene"] = cached_scene(
            json.dumps(circuit, sort_keys=True), json.dumps(advances, sort_keys=True)
        )
        details = []
        for spec in circuit["block_diagram"].get("details", []):
            owner = next(n for n in circuit["nodes"] if n["id"] == spec["owner"])
            members = {u["id"]: u for u in owner.get("units", [])}
            resolved = {**spec, "units": [members[k] for k in spec["members"]]}
            details.append(make_detail(root, product, identifier, circuit, resolved, advances))
        scoped = [
            scoped_route_detail(identifier, circuit, spec, advances)
            for spec in circuit["block_diagram"].get("route_details", [])
        ]
        details.extend(scoped)
        circuit["route_detail_links"] = [detail["detail_id"] for detail in scoped]
        circuit["details"] = details
        circuit["renderer"] = "cetz"
        circuit["product"] = product
        circuit["block_title"] = circuit["block_diagram"]["title"] + " block diagram"
        for key, record in [(identifier, circuit), *((d["detail_id"], d) for d in details)]:
            issues = geometry_issues(record["scene"], advances) + review_issues(record["scene"])
            if issues:
                raise ValueError(f"IP geometry rejected {product}/{key}: {issues}")


def boundary_ports(path: Path) -> list[dict]:
    """Selected clock, reset and IRQ boundary declarations, not configuration bits."""
    from publications.circuit_reference import closing_parenthesis
    from publications.waveform_reference import uncomment

    text = uncomment(path.read_text(encoding="utf-8"))
    first = re.search(r"\bmodule\s+\w+\s*(?:#\s*)?\(", text)
    if not first:
        return []
    start = first.end() - 1
    stop = closing_parenthesis(text, start)
    if "#" in first.group():
        start = text.find("(", stop + 1)
        stop = closing_parenthesis(text, start)
    header = text[start + 1 : stop]
    result = []
    pattern = r"\b(input|output|inout)\b(.*?)(?=\b(?:input|output|inout)\b|\b\w+_if\.\w+|$)"
    for match in re.finditer(pattern, header, re.S):
        direction, body = match.groups()
        for piece in body.split(","):
            name = re.search(r"\b([A-Za-z_]\w*)\s*$", piece.strip())
            if not name:
                continue
            name = name[1]
            if re.search(r"(?:rst|reset)", name, re.I) and not re.search(
                r"(?:done|ready|held|status|count|cause)", name, re.I
            ):
                role = "reset"
            elif re.search(r"(?:irq|interrupt|wake)", name, re.I) and direction == "output":
                role = "irq"
            elif re.search(r"(?:clk|clock)", name, re.I) and not re.search(
                r"(?:hz|div|enable|ctrl|control|valid|select|rate|fault|idle|done|current|timeout|apply|profile|paused|parked|busy)",
                name,
                re.I,
            ):
                role = "clock"
            else:
                continue
            result.append(dict(name=name, direction=direction, role=role))
    return result


@lru_cache(maxsize=256)
def _scene_cache(record: str, metrics: str) -> dict:
    return make_scene(json.loads(record), json.loads(metrics))


def cached_scene(record: str, metrics: str) -> dict:
    return deepcopy(_scene_cache(record, metrics))


def source_members(
    root: Path, relative: str, prefixes: tuple[str, ...], *, scope: str | None = None
) -> list[dict]:
    """Read selected real source instances, retaining their named ports and guard."""
    from publications.circuit_reference import closing_parenthesis
    from publications.waveform_reference import uncomment

    source = uncomment((root / relative).read_text(encoding="utf-8"))
    declarations = re.findall(r"\bmodule\s+(\w+)\b", source)
    selected = scope or (
        Path(relative).stem
        if Path(relative).stem in declarations
        else declarations[0]
        if len(declarations) == 1
        else None
    )
    if selected is None:
        raise ValueError("IP instance source requires an explicit owning module")
    scopes = re.findall(r"\bmodule\s+" + re.escape(selected) + r"\b.*?\bendmodule\b", source, re.S)
    if len(scopes) != 1:
        raise ValueError("IP instance source module is missing or ambiguous")
    source = scopes[0]
    pattern = re.compile(
        r"(?m)^\s*([A-Za-z_]\w*)\s*(?:#\s*\((?:[^()]|\([^()]*\))*\)\s*)?(u_[A-Za-z_]\w*)\s*\("
    )
    result = []
    for match in pattern.finditer(source):
        module, name = match.groups()
        if (
            module == "xchecker"
            or not module.startswith(prefixes)
            or re.search(r"(?:^|_)(?:formal|sva|assert)(?:_|$)", module)
        ):
            continue
        stop = closing_parenthesis(source, match.end() - 1)
        body = source[match.end() : stop]
        ports = {}
        ports_raw = {}
        for port in re.finditer(r"\.(\w+)\s*\(", body):
            end = closing_parenthesis(body, port.end() - 1)
            expression = re.sub(r"\s+", "", body[port.end() : end])
            ports_raw[port[1]] = expression
            if re.fullmatch(r"[A-Za-z_]\w*(?:\[\d+(?::\d+)?\])?", expression):
                ports[port[1]] = expression
        title = module
        for prefix in prefixes:
            if module.startswith(prefix) and prefix.endswith("_"):
                title = module[len(prefix) :]
                break
        title = title.replace("_", " ")
        if module == "fifo":
            title = name.removeprefix("u_").replace("_", " ")
        shape = (
            "mux"
            if "mux" in module
            else "divider"
            if "div" in module
            else "gate"
            if "gate" in module
            else "fifo"
            if "fifo" in module
            else "block"
        )
        raw_params = {}
        for parameter in re.finditer(r"\.(\w+)\s*\(", match.group()):
            end = closing_parenthesis(match.group(), parameter.end() - 1)
            raw_params[parameter[1]] = re.sub(r"\s+", "", match.group()[parameter.end() : end])
        params = {
            k: int(v)
            for k, v in re.findall(r"\.(DATA_WIDTH|BUFFER_DEPTH)\s*\(\s*(\d+)\s*\)", match.group())
        }
        result.append(
            dict(
                id=name,
                title=title,
                module=module,
                ports=ports,
                ports_raw=ports_raw,
                parameters=params,
                parameters_raw=raw_params,
                scope_module=selected,
                shape=shape,
                bindings=[dict(file=relative, text=name + " (")],
            )
        )
    counts = Counter(r["id"] for r in result)
    return [r for r in result if counts[r["id"]] == 1]


def unit_connections(units: list[dict]) -> list[dict]:
    """Pair named output/input associations carrying the identical source net."""
    links = {}
    for source in units:
        for port, signal in source["ports"].items():
            if not port.endswith("_o"):
                continue
            for target in units:
                if source["id"] == target["id"]:
                    continue
                for dest, wire in target["ports"].items():
                    if wire != signal or not dest.endswith("_i"):
                        continue
                    payload = bool(
                        re.search(
                            r"(?:data|dat_|pixel|word|sample|result|accum|products|bytes)", port
                        )
                        and not re.search(
                            r"(?:valid|ready|last|error|code|req|addr|bytes|select|enable|mode|status|busy|done|tick|clock|clk|rst|reset)",
                            port,
                        )
                    )
                    key = (source["id"], target["id"], "data" if payload else "control")
                    links.setdefault(key, []).append(
                        dict(source_port=port, target_port=dest, net=signal)
                    )
    return [
        dict(source=a, target=b, kind=kind, signals=signals)
        for (a, b, kind), signals in links.items()
    ]


def make_detail(
    root: Path,
    product: str,
    identifier: str,
    parent: dict,
    spec: dict,
    advances: dict,
    *,
    build_scene: bool = True,
) -> dict:
    units = spec["units"]
    ids = {u["id"] for u in units}
    nodes = []
    for unit in units:
        title = unit["title"]
        if sum(u["title"] == title for u in units) > 1:
            title = unit["id"].removeprefix("u_").replace("_", " ")
        if (
            unit["shape"] == "fifo"
            and {"DATA_WIDTH", "BUFFER_DEPTH"} <= unit.get("parameters", {}).keys()
        ):
            title += (
                f"\n{unit['parameters']['BUFFER_DEPTH']} x {unit['parameters']['DATA_WIDTH']} bits"
            )
        nodes.append(
            dict(
                id=unit["id"],
                title=title,
                condition=unit.get("condition"),
                ports=[],
                sources=[spec["file"]],
                instance_source=dict(file=spec["file"], name=unit["id"], module=unit["module"]),
            )
        )
    if spec.get("connections") is not None:
        return manual_detail(
            root, product, identifier, parent, spec, nodes, advances, build_scene=build_scene
        )
    parent_node = dict(
        id="parent",
        title=spec["title"] + "\nlocal sequencing / staging",
        ports=[],
        sources=[spec["file"]],
    )
    nodes.insert(0, parent_node)
    by_id = {n["id"]: n for n in nodes}
    edges = []
    links = unit_connections(units)
    for i, link in enumerate(links):
        a, b = by_id[link["source"]], by_id[link["target"]]
        key = "p" + str(i)
        for node, direction in [(a, "out"), (b, "in")]:
            node["ports"].append(
                dict(id=key, direction=direction, width=None, bundle=True, side="east")
            )
        signal = link["signals"][0]
        label = signal["net"].removeprefix("s_")
        # All member names remain in the trace table; short functional labels are
        # logical bundles, never invented numerical bit widths.
        label = label.removesuffix("_q").replace("_", " ")
        edges.append(
            dict(
                from_=a["id"] + "." + key,
                to=b["id"] + "." + key,
                kind=link["kind"],
                label=label,
                bindings=[
                    dict(file=spec["file"], text="." + signal["source_port"]),
                    dict(file=spec["file"], text="." + signal["target_port"]),
                ],
                member_signals=link["signals"],
            )
        )
        edges[-1]["from"] = edges[-1].pop("from_")
    used = {
        (item["source_port"], item["net"], link["source"])
        for link in links
        for item in link["signals"]
    }
    used |= {
        (item["target_port"], item["net"], link["target"])
        for link in links
        for item in link["signals"]
    }
    connected = {link[k] for link in links for k in ("source", "target")}
    for unit in units:
        if unit["id"] in connected:
            continue
        grouped = {}
        for port, signal in unit["ports"].items():
            if (port, signal, unit["id"]) in used:
                continue
            if not port.endswith(("_i", "_o")):
                continue
            direction = "input" if port.endswith("_i") else "output"
            payload = bool(
                re.search(r"data|dat_|pixel|word|sample|products|bytes", port)
                and not re.search(r"valid|ready|addr|count|req|resp|select|strb", port)
            )
            grouped.setdefault((direction, "data" if payload else "control"), []).append(
                (port, signal)
            )
        for (direction, kind), signals in grouped.items():
            a, b = (
                (parent_node, by_id[unit["id"]])
                if direction == "input"
                else (by_id[unit["id"]], parent_node)
            )
            key = "p" + str(len(edges))
            a["ports"].append(dict(id=key, direction="out", width=None, bundle=True, side="south"))
            b["ports"].append(dict(id=key, direction="in", width=None, bundle=True, side="north"))
            edges.append(
                {
                    "from": a["id"] + "." + key,
                    "to": b["id"] + "." + key,
                    "kind": kind,
                    "label": signals[0][1].removeprefix("s_").removesuffix("_q").replace("_", " "),
                    "bindings": [dict(file=spec["file"], text="." + port) for port, _ in signals],
                    "member_signals": [dict(port=port, net=net) for port, net in signals],
                }
            )
    has_parent = bool(parent_node["ports"])
    if not has_parent:
        nodes.remove(parent_node)
    columns = 2 if len(units) <= 6 else 3
    rows = ([["parent"]] if has_parent else []) + [
        [u["id"] for u in units[i : i + columns]] for i in range(0, len(units), columns)
    ]
    detail = dict(
        nodes=nodes,
        edges=edges,
        renderer="cetz",
        product=product,
        block_title=parent["block_diagram"]["title"] + " / " + spec["title"] + " block diagram",
        note=spec.get("note", "Named source instances and shared-net directions; protocol handshakes and generate repetition are grouped. Parent product integration and qualification limits still apply."),
        detail_id=identifier + "-detail-" + spec["id"],
        parent_id=identifier,
        block_diagram=dict(
            style=STYLE,
            product=product,
            title=parent["block_diagram"]["title"] + " / " + spec["title"],
            rows=rows,
            external=[],
            buses=[],
            ports=[],
            wrapper=[spec["file"]],
            review=spec["review"],
            shapes={u["id"]: u["shape"] for u in units},
            row_gap=26 if has_parent and len(units) <= 4 else (14 if len(rows) >= 4 else 18),
        ),
    )
    assert ids | ({"parent"} if has_parent else set()) == {key for row in rows for key in row}
    if build_scene:
        finish_detail(root, detail, spec, advances)
    return detail


def manual_detail(
    root: Path,
    product: str,
    identifier: str,
    parent: dict,
    spec: dict,
    nodes: list,
    advances: dict,
    *,
    build_scene: bool = True,
) -> dict:
    for context in spec.get("contexts", []):
        nodes.append(
            dict(
                id=context["id"],
                title=context["title"],
                ports=[],
                sources=[spec["file"]],
                scope="parent-context",
            )
        )
    by_id = {n["id"]: n for n in nodes}
    edges = []
    for i, connection in enumerate(spec["connections"]):
        a, b = by_id[connection["source"]], by_id[connection["target"]]
        key = "p" + str(i)
        a["ports"].append(dict(id=key, direction="out", width=None, bundle=True, side="east"))
        b["ports"].append(dict(id=key, direction="in", width=None, bundle=True, side="west"))
        named = []
        for endpoint, port_name in [
            (a, connection.get("source_port")),
            (b, connection.get("target_port")),
        ]:
            if port_name and "instance_source" in endpoint:
                named.append(
                    dict(node=endpoint["id"], port=port_name, expression=connection["net"])
                )
        bindings = [dict(file=spec["file"], text="." + item["port"]) for item in named]
        bindings.extend(connection.get("bindings", []))
        if not bindings:
            raise ValueError("Manual IP detail has an unbound connection")
        for binding in bindings:
            if re.sub(r"\s+", "", binding["text"]) not in re.sub(
                r"\s+", "", (root / binding["file"]).read_text(encoding="utf-8")
            ):
                raise ValueError("Manual IP detail binding changed")
        edges.append(
            {
                "from": a["id"] + "." + key,
                "to": b["id"] + "." + key,
                "kind": connection["kind"],
                "label": connection["label"],
                "bindings": bindings,
                "instance_ports": named,
            }
        )
    detail = dict(
        nodes=nodes,
        edges=edges,
        renderer="cetz",
        product=product,
        block_title=parent["block_diagram"]["title"] + " / " + spec["title"] + " block diagram",
        note=spec.get(
            "note",
            "Functional stages and named source-port connections; local control/staging is a grouping of parent RTL logic, not an extra module. Parent integration and qualification limits still apply.",
        ),
        detail_id=identifier + "-detail-" + spec["id"],
        parent_id=identifier,
        block_diagram=dict(
            style=STYLE,
            product=product,
            title=parent["block_diagram"]["title"] + " / " + spec["title"],
            rows=spec["rows"],
            external_sides=spec.get("external_sides", {}),
            external=spec.get("external", []),
            buses=[],
            ports=[],
            wrapper=[spec["file"]],
            review=spec["review"],
            shapes={u["id"]: u["shape"] for u in spec["units"]},
        ),
    )
    from publications.circuit_reference import validate_instance_connections

    validate_instance_connections(root, detail)
    if build_scene:
        finish_detail(root, detail, spec, advances)
    return detail


def finish_detail(root: Path, detail: dict, spec: dict, advances: dict) -> None:
    from publications.ip_block_layout import validate_functional

    detail["block_diagram"]["functional"] = spec["functional"]
    detail["block_diagram"]["ports"] = detail_ports(root, spec)
    validate_functional(root, detail, spec["functional"])
    detail["scene"] = cached_scene(
        json.dumps(detail, sort_keys=True), json.dumps(advances, sort_keys=True)
    )


def detail_ports(root: Path, spec: dict) -> list[dict]:
    """A detail shows its selected local scope; the primary retains full coverage."""
    ports = [dict(p, file=spec["file"]) for p in boundary_ports(root / spec["file"])]
    selected = spec.get("boundary_selection")
    if selected is not None:
        if not spec.get("boundary_review") or not set(selected) <= {p["name"] for p in ports}:
            raise ValueError("IP detail boundary selection is unknown or lacks a scope review")
        ports = [p for p in ports if p["name"] in selected]
    return ports


def records(data: dict) -> dict[str, dict]:
    illustrations = data.get(
        "illustrations", data.get("system_reference", {}).get("illustrations", {})
    )
    result = {}
    for identifier, circuit in illustrations["circuits"].items():
        if identifier in SYSTEM_IDS or circuit.get("renderer") != "cetz":
            continue
        result[identifier] = circuit
        result.update({detail["detail_id"]: detail for detail in circuit.get("details", [])})
    return result


def trace_paths(circuits: dict) -> set[str]:
    paths = set()

    def visit(value):
        if isinstance(value, dict):
            for key, item in value.items():
                if key == "file":
                    paths.add(item)
                elif key == "dependency":
                    paths.add("dependencies/dependencies.lock.json")
                elif key == "wrapper":
                    paths.update(item)
                else:
                    visit(item)
        elif isinstance(value, list):
            for item in value:
                visit(item)

    for circuit in circuits.values():
        if circuit.get("block_diagram"):
            paths.update(SOURCES)
            visit(circuit["block_diagram"])
    return paths


def export_vectors(root: Path, out: Path, data: dict, executable: str, options: list[str]) -> dict:
    destination = out / "ip-blocks"
    destination.mkdir(exist_ok=True)
    views = records(data)
    if any(p.stem not in views for p in destination.iterdir() if p.suffix in {".svg", ".pdf"}):
        raise ValueError("IP vector directory contains stale views; use a fresh build directory")
    source = destination / "ip-views.typ"
    source.write_text(
        """#import "/publications/ip-block-diagrams.typ": ip-block-view
#set page(width:auto,height:auto,margin:4mm)
#set text(font:"Inter",size:9pt,weight:"regular")
#set par(leading:1.5pt,spacing:0pt)
#let d=json(sys.inputs.at("data"))
#let circuits=if "illustrations" in d {d.illustrations.circuits} else {d.system_reference.illustrations.circuits}
#let id=sys.inputs.at("figure")
#let all=circuits.values().filter(c=>c.at("renderer",default:"")=="cetz" and "block_diagram" in c)
#let r=all.find(c=>c.block_diagram.title+"-primary"==id or c.at("export_id",default:"")==id)
#let r=if r==none {all.map(c=>c.details).flatten().find(c=>c.detail_id==id)} else {r}
#align(center,text(weight:"bold",r.block_title))
#v(6pt)
#ip-block-view(r)
#v(4pt)
#block(width:172mm)[#r.at("clock_note",default:"") #r.note]
""",
        encoding="utf-8",
        newline="\n",
    )
    files = {source.relative_to(out).as_posix(): hashlib.sha256(source.read_bytes()).hexdigest()}
    for identifier, record in views.items():
        selector = record.get("detail_id", record["block_diagram"]["title"] + "-primary")
        for suffix in ("svg", "pdf"):
            target = destination / (identifier + "." + suffix)
            result = subprocess.run(
                [
                    executable,
                    "compile",
                    str(source),
                    str(target),
                    *options,
                    "--input",
                    "figure=" + selector,
                ],
                cwd=root,
                text=True,
                capture_output=True,
                encoding="utf-8",
            )
            if result.returncode or "warning:" in result.stderr:
                raise ValueError("IP standalone vector failed: " + result.stderr)
            files[target.relative_to(out).as_posix()] = hashlib.sha256(
                target.read_bytes()
            ).hexdigest()
    return files


def source_audit(root: Path, data: dict) -> dict:
    result = {}
    for identifier, record in records(data).items():
        sources = {source for node in record["nodes"] for source in node["sources"]}
        sources.update(b["file"] for edge in record["edges"] for b in edge["bindings"])
        sources.update(record["block_diagram"]["wrapper"])
        sources.update(trace_paths({identifier: record}))
        sources.update(i["file"] for i in record["block_diagram"].get("interfaces", []))
        result[identifier] = dict(
            product=record["product"],
            style=STYLE,
            parent=record.get("parent_id", identifier),
            title=record["block_title"],
            sources={
                p: hashlib.sha256((root / p).read_bytes()).hexdigest() for p in sorted(sources)
            },
            wrapper=record["block_diagram"]["wrapper"],
            clock_reset_irq=record["block_diagram"].get("ports", []),
            interfaces=record["block_diagram"].get("interfaces", []),
            units=[
                dict(
                    id=n["id"],
                    title=n["title"],
                    boundary="soc-integration"
                    if n["id"] in record["block_diagram"].get("integration", [])
                    else "external"
                    if n["id"] in record["block_diagram"].get("external", [])
                    else "interface"
                    if n["id"] in record["block_diagram"].get("buses", [])
                    else "owned",
                    symbol=record["block_diagram"].get("shapes", {}).get(n["id"], "block"),
                    instance=n.get("instance_source"),
                    scope=n.get(
                        "scope", "rtl-instance" if n.get("instance_source") else "logical-group"
                    ),
                    ports=n["ports"],
                    members=n.get("units", []),
                    sources=n["sources"],
                )
                for n in record["nodes"]
            ],
            connections=[
                {
                    k: e[k]
                    for k in (
                        "from",
                        "to",
                        "kind",
                        "label",
                        "bindings",
                        "instance_ports",
                        "signals",
                        "member_signals",
                        "availability",
                    )
                    if k in e
                }
                for e in record["edges"]
            ],
            functional=record["block_diagram"].get("functional"),
            printed_edge_ids=[wire["id"] for wire in record["scene"]["wires"]],
            route_details=record["block_diagram"].get("route_details", []),
        )
    return result


def export_audits(root: Path, out: Path, data: dict, items: list[dict]) -> dict:
    from publications.specification_reference import write, digest

    views = records(data)
    product = "tiny" if "illustrations" in data else "mini"
    prefix = "circuit-" if product == "tiny" else ""
    actual = {}
    for item in items:
        if not isinstance(item, dict):
            continue
        if item.get("package") == "cetz" and item.get("kind") in {
            "publication-diagram",
            "tiny-diagram",
        }:
            identifier = item["id"].removeprefix(prefix)
            if identifier in views:
                if identifier in actual:
                    raise ValueError("IP view rendered more than once")
                actual[identifier] = item["page"]
    if set(actual) != set(views):
        raise ValueError("IP view use audit is incomplete")
    files = {}
    for name, value in [
        ("ip-block-sources.json", source_audit(root, data)),
        ("ip-block-geometry.json", {k: r["scene"] for k, r in views.items()}),
        (
            "ip-block-coverage.json",
            dict(
                style=STYLE,
                product=product,
                primary=sum("parent_id" not in r for r in views.values()),
                details=sum("parent_id" in r for r in views.values()),
                pages=actual,
            ),
        ),
    ]:
        write(out / name, value)
        files[name] = digest(out / name)
    return files


def verify_audit(root: Path, out: Path, data: dict) -> None:
    """Verify semantic contents as well as manifest digests against fresh inputs."""
    views = records(data)
    expected = {
        "ip-block-sources.json": source_audit(root, data),
        "ip-block-geometry.json": {key: r["scene"] for key, r in views.items()},
    }
    for filename, value in expected.items():
        if json.loads((out / filename).read_text(encoding="utf-8")) != json.loads(
            json.dumps(value)
        ):
            raise ValueError("IP audit differs from current source: " + filename)
    coverage = json.loads((out / "ip-block-coverage.json").read_text(encoding="utf-8"))
    if coverage["product"] != ("tiny" if "illustrations" in data else "mini"):
        raise ValueError("IP audit crosses product boundaries")
    if coverage["style"] != STYLE or set(coverage["pages"]) != set(views):
        raise ValueError("IP audit view coverage differs")
    if coverage["primary"] != sum("parent_id" not in r for r in views.values()) or coverage[
        "details"
    ] != sum("parent_id" in r for r in views.values()):
        raise ValueError("IP audit count differs")
    advances = font_advances(
        root / "publications/media/fonts/inter/Inter-VariableFont_opsz,wght.ttf"
    )
    for identifier, record in views.items():
        if geometry_issues(record["scene"], advances):
            raise ValueError("IP geometry differs: " + identifier)


def decoration_boxes(scene: dict, advances: dict) -> list[dict]:
    """Final-size text outside functional nodes, including clocks and bus names."""
    result = []

    def add(key, lines, x, y, right=False):
        width = max((text_width(line, advances) for line in lines), default=0)
        height = len(lines) * 3.7
        result.append(dict(id=key, box=[x - width if right else x, y - height / 2, width, height]))

    for port in scene["ports"]:
        left = port["direction"] == "input"
        add("port:" + port["name"], port["lines"], 25 if left else 147, port["y"], left)
    for node in scene["nodes"]:
        if node["role"] == "bus":
            left = node.get("side", "left") == "left"
            add(
                "bus:" + node["id"],
                node["lines"],
                node["x"] + (-3 if left else 3),
                node["y"] + node["h"] / 2,
                left,
            )
    for index, interface in enumerate(scene["interfaces"]):
        left = interface["side"] == "left"
        add(
            "interface:" + str(index),
            interface["lines"],
            interface["x"] + (-3 if left else 3),
            interface["y"],
            left,
        )
    return result


def wire_collisions(wires: list[dict]) -> list[str]:
    """Only an actual shared source permits a common shaft or a T junction."""
    issues = []

    def on(point, a, b):
        return (
            min(a[0], b[0]) <= point[0] <= max(a[0], b[0])
            and min(a[1], b[1]) <= point[1] <= max(a[1], b[1])
            and (point[0] == a[0] == b[0] or point[1] == a[1] == b[1])
        )

    for i, left in enumerate(wires):
        for right in wires[i + 1 :]:
            if left["source_key"] == right["source_key"]:
                continue
            gap = (
                3
                if left["kind"] == right["kind"] == "data"
                else 2
                if "data" in (left["kind"], right["kind"])
                else 1
            )
            for a, b in zip(left["points"], left["points"][1:]):
                for c, d in zip(right["points"], right["points"][1:]):
                    horizontal = a[1] == b[1] and c[1] == d[1]
                    vertical = a[0] == b[0] and c[0] == d[0]
                    if (
                        horizontal
                        and abs(a[1] - c[1]) < gap - 0.01
                        and max(min(a[0], b[0]), min(c[0], d[0]))
                        < min(max(a[0], b[0]), max(c[0], d[0]))
                    ) or (
                        vertical
                        and abs(a[0] - c[0]) < gap - 0.01
                        and max(min(a[1], b[1]), min(c[1], d[1]))
                        < min(max(a[1], b[1]), max(c[1], d[1]))
                    ):
                        issues.append(f"wire-overlap:{left['index']}:{right['index']}")
                    if any(on(p, a, b) for p in (c, d)) or any(on(p, c, d) for p in (a, b)):
                        issues.append(f"wire-junction:{left['index']}:{right['index']}")
    return sorted(set(issues))


def geometry_issues(scene: dict, advances: dict) -> list[str]:
    if scene.get("style") == STYLE:
        from publications.ip_block_layout import geometry_issues as explicit_issues

        return explicit_issues(scene, advances)
    from publications.soc_diagram_geometry import segment_distance

    issues = wire_collisions(scene["wires"])
    if not 0 < scene["width"] <= 172 or not 0 < scene["height"] <= 200:
        issues.append("canvas-size")
    nodes = {n["id"]: n for n in scene["nodes"]}
    for entry in scene["legend"]:
        box = [
            entry["x"],
            entry["y"],
            max((text_width(line, advances) for line in entry["lines"]), default=0),
            len(entry["lines"]) * 3.7,
        ]
        if (
            box[0] < 1
            or box[0] + box[2] > scene["width"] - 1
            or box[1] + box[3] > scene["height"] - 1
        ):
            issues.append("legend-bounds:" + entry["text"])
        for wire in scene["wires"]:
            if any(
                inside(point, box, 1.1 if wire["kind"] == "control" else 2.1)
                for point in wire["points"]
            ):
                issues.append("legend-wire:" + entry["text"])
    decorations = decoration_boxes(scene, advances)
    for item in decorations:
        box = item["box"]
        if (
            box[0] < 1
            or box[1] < 1
            or box[0] + box[2] > scene["width"] - 1
            or box[1] + box[3] > scene["height"] - 1
        ):
            issues.append("boundary-text-bounds:" + item["id"])
        if any(overlaps(box, other["box"], 0.1) for other in decorations if other is not item):
            issues.append("boundary-text-overlap:" + item["id"])
        if any(
            overlaps(box, [node[k] for k in ("x", "y", "w", "h")], 0.9)
            for node in nodes.values()
            if node["role"] != "bus"
        ):
            issues.append("boundary-text-node:" + item["id"])
        corners = [
            [box[0], box[1]],
            [box[0] + box[2], box[1]],
            [box[0] + box[2], box[1] + box[3]],
            [box[0], box[1] + box[3]],
        ]
        for wire in scene["wires"]:
            gap = 2 if wire["kind"] == "data" else 0.99
            if any(
                inside(a, box, gap)
                or inside(b, box, gap)
                or any(
                    segment_distance(a, b, corners[i], corners[(i + 1) % 4]) < gap for i in range(4)
                )
                for a, b in zip(wire["points"], wire["points"][1:])
            ):
                issues.append("boundary-text-wire:" + item["id"])
    for n in nodes.values():
        if n["role"] == "bus":
            continue
        if (
            n["x"] < 1
            or n["y"] < 1
            or n["x"] + n["w"] > scene["width"] - 1
            or n["y"] + n["h"] > scene["height"] - 1
        ):
            issues.append("node-bounds:" + n["id"])
        if (
            max((text_width(label_entry, advances) for label_entry in n["lines"]), default=0)
            > n["w"] - 3.8
        ):
            issues.append("text-width:" + n["id"])
        if len(n["lines"]) * 3.7 > n["h"] - 2.9:
            issues.append("text-height:" + n["id"])
        for other in nodes.values():
            if (
                other["id"] > n["id"]
                and other["role"] != "bus"
                and overlaps(
                    [n[k] for k in ("x", "y", "w", "h")], [other[k] for k in ("x", "y", "w", "h")]
                )
            ):
                issues.append("node-overlap:" + n["id"] + ":" + other["id"])
    for w in scene["wires"]:
        for a, b in zip(w["points"], w["points"][1:]):
            if a == b or (a[0] != b[0] and a[1] != b[1]):
                issues.append("route-diagonal:" + str(w["index"]))
            for n in nodes.values():
                if n["id"] in {w["from_node"], w["to_node"]} or n["role"] == "bus":
                    continue
                corners = [
                    [n["x"], n["y"]],
                    [n["x"] + n["w"], n["y"]],
                    [n["x"] + n["w"], n["y"] + n["h"]],
                    [n["x"], n["y"] + n["h"]],
                ]
                gap = 2.1 if w["kind"] == "data" else 1.1
                if (
                    inside(a, [n[k] for k in ("x", "y", "w", "h")])
                    or inside(b, [n[k] for k in ("x", "y", "w", "h")])
                    or any(
                        segment_distance(a, b, corners[i], corners[(i + 1) % 4]) < gap - 0.01
                        for i in range(4)
                    )
                ):
                    issues.append("wire-node:" + str(w["index"]) + ":" + n["id"])
        if any(
            not (1 <= p[0] <= scene["width"] - 1 and 1 <= p[1] <= scene["height"] - 1)
            for p in w["points"]
        ):
            issues.append("route-bounds:" + str(w["index"]))
    for label_entry in scene["labels"]:
        box = [label_entry[k] for k in ("x", "y", "w", "h")]
        if (
            box[0] < 1
            or box[1] < 1
            or box[0] + box[2] > scene["width"] - 1
            or box[1] + box[3] > scene["height"] - 1
        ):
            issues.append("label-bounds:" + label_entry["text"])
        if any(
            overlaps(box, [n[k] for k in ("x", "y", "w", "h")], 1)
            for n in nodes.values()
            if n["role"] != "bus"
        ):
            issues.append("label-node:" + label_entry["text"])
        if any(
            other is not label_entry and overlaps(box, [other[k] for k in ("x", "y", "w", "h")], 1)
            for other in scene["labels"]
        ):
            issues.append("label-overlap:" + label_entry["text"])
        corners = [
            [box[0], box[1]],
            [box[0] + box[2], box[1]],
            [box[0] + box[2], box[1] + box[3]],
            [box[0], box[1] + box[3]],
        ]
        for w in scene["wires"]:
            gap = 2.1 if w["kind"] == "data" else 1.1
            if any(
                inside(a, box, gap)
                or inside(b, box, gap)
                or any(
                    segment_distance(a, b, corners[i], corners[(i + 1) % 4]) < gap for i in range(4)
                )
                for a, b in zip(w["points"], w["points"][1:])
            ):
                issues.append("label-wire:" + label_entry["text"])
    return sorted(set(issues))


def find_label(
    text: str,
    wire: dict,
    scene: dict,
    obstacles: list,
    advances: dict,
    first_y: float,
    node_gap: float,
):
    from publications.soc_diagram_geometry import segment_distance

    width = text_width(text, advances)
    label_top = first_y - 1 if scene.get("ports") else scene["boundary"][1] + 4
    candidates = []
    segments = sorted(
        zip(wire["points"], wire["points"][1:]), key=lambda p: math.dist(*p), reverse=True
    )
    for a, b in segments:
        for fraction in (0.5, 0.3, 0.7, 0.15, 0.85):
            x = a[0] + (b[0] - a[0]) * fraction
            y = a[1] + (b[1] - a[1]) * fraction
            if a[1] == b[1] and math.dist(a, b) >= width + 2:
                for offset in (-4.5, 4.5, -6.8, 6.8, -10, 10, -13, 13):
                    candidates.append([x - width / 2, y + offset - 1.9, width, 3.8])
            if a[0] == b[0] and math.dist(a, b) >= 5:
                for offset in (3.5, -3.5, 6, -6):
                    candidates.append(
                        [x + offset if offset > 0 else x + offset - width, y - 1.9, width, 3.8]
                    )
    for box in candidates:
        if (
            box[0] < 29.2
            or box[0] + box[2] > 141
            or box[1] < label_top
            or box[1] + box[3] > scene["boundary"][1] + scene["boundary"][3] - 1
        ):
            continue
        if any(overlaps(box, o, node_gap) for o in obstacles):
            continue
        if any(
            overlaps(box, [label_entry[k] for k in ("x", "y", "w", "h")], 1)
            for label_entry in scene["labels"]
        ):
            continue
        corners = [
            [box[0], box[1]],
            [box[0] + box[2], box[1]],
            [box[0] + box[2], box[1] + box[3]],
            [box[0], box[1] + box[3]],
        ]
        blocked = False
        for other in scene["wires"]:
            if other["kind"] == "data":
                boundaries = list(
                    zip(other["polygon"], other["polygon"][1:] + other["polygon"][:1])
                )
                gap = 1.2
            else:
                boundaries = list(zip(other["points"], other["points"][1:]))
                gap = 1.2
            for a, b in boundaries:
                if (
                    inside(a, box, gap)
                    or inside(b, box, gap)
                    or any(
                        segment_distance(a, b, corners[j], corners[(j + 1) % 4]) < gap
                        for j in range(4)
                    )
                ):
                    blocked = True
                    break
            if blocked:
                break
        if not blocked:
            return box
    return None


def junctions(wires: list[dict]) -> list[list]:
    """Only identical source ports/nets authorize a connected branch dot."""
    groups = {}
    for wire in wires:
        groups.setdefault(wire["source_key"], []).append(wire)
    result = set()
    for group in groups.values():
        if len(group) < 2:
            continue
        points = {}
        for wire in group:
            for a, b in zip(wire["points"], wire["points"][1:]):
                length = round(math.dist(a, b))
                dx = 0 if a[0] == b[0] else (1 if b[0] > a[0] else -1)
                dy = 0 if a[1] == b[1] else (1 if b[1] > a[1] else -1)
                for i in range(length + 1):
                    p = (a[0] + dx * i, a[1] + dy * i)
                    value = points.setdefault(p, dict(wires=set(), directions=set()))
                    value["wires"].add(wire["index"])
                    if i:
                        value["directions"].add((-dx, -dy))
                    if i < length:
                        value["directions"].add((dx, dy))
        for point, value in points.items():
            if len(value["wires"]) >= 2 and len(value["directions"]) >= 3:
                result.add(point)
    return [list(p) for p in sorted(result)]
