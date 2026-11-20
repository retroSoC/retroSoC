"""Prepare the source-bound Tiny system clock drawing in millimetres."""

from collections import defaultdict

from publications.soc_diagram_geometry import geometry_issues, routes


def _segments(paths):
    """Split each net at its branch points and retain one copy of each shaft."""
    wires = {}
    junctions = []
    by_source = defaultdict(list)
    for path in paths:
        by_source[path["net"]].append(path)
    for source, group in by_source.items():
        kinds = {path["kind"] for path in group}
        if len(kinds) != 1:
            raise ValueError("Tiny clock net mixes clock, control or reset roles")
        vertices = {tuple(round(v, 6) for v in p) for path in group for p in path["points"]}
        neighbors = defaultdict(set)
        for path in group:
            for first, last in zip(path["points"], path["points"][1:]):
                a, b = sorted(tuple(round(v, 6) for v in p) for p in (first, last))
                axis = int(a[0] == b[0])
                on_segment = sorted(p for p in vertices if p[1 - axis] == a[1 - axis] and a[axis] <= p[axis] <= b[axis])
                for p, q in zip(on_segment, on_segment[1:]):
                    wires[p, q, source] = path["kind"]
                    neighbors[p].add(q)
                    neighbors[q].add(p)
        junctions.extend(dict(point=p, kind=group[0]["kind"]) for p, others in sorted(neighbors.items()) if len(others) > 2)
    return wires, junctions


def _separate_crossings(wires):
    """Leave a visible gap in the horizontal shaft at an unrelated crossing."""
    gap = 0.8
    cuts = defaultdict(set)
    keys = sorted(wires)
    for i, (a, b, source) in enumerate(keys):
        horizontal = a[1] == b[1]
        for c, d, other in keys[i + 1:]:
            if source == other:
                continue
            if horizontal == (c[1] == d[1]):
                axis = 0 if horizontal else 1
                if a[1 - axis] == c[1 - axis] and max(a[axis], c[axis]) <= min(b[axis], d[axis]):
                    raise ValueError(f"Tiny clock shafts overlap or touch: {source} / {other}")
                continue
            left, right, top, bottom = (a, b, c, d) if horizontal else (c, d, a, b)
            x, y = top[0], left[1]
            if left[0] <= x <= right[0] and top[1] <= y <= bottom[1]:
                if min(x - left[0], right[0] - x, y - top[1], bottom[1] - y) <= gap:
                    raise ValueError(f"Tiny clock crossing crowds a terminal or corner: {source} / {other}")
                cuts[(left, right, source if horizontal else other)].add(x)
    drawn = []
    for (a, b, source), kind in sorted(wires.items()):
        positions = sorted(cuts[a, b, source])
        if positions and any(q - p <= 2 * gap for p, q in zip(positions, positions[1:])):
            raise ValueError(f"Tiny clock crossings are too close: {source}")
        starts = [a, *((x + gap, a[1]) for x in positions)]
        ends = [*((x - gap, a[1]) for x in positions), b]
        drawn.extend(dict(points=[p, q], kind=kind) for p, q in zip(starts, ends))
    return drawn


def prepare(circuit: dict, domains: list[dict]) -> None:
    """Build drawing paths from the same ports checked against RTL bindings."""
    sheet = circuit["clock_tree"]
    width, height = sheet["width_mm"], sheet["height_mm"]
    if not 0 < width <= 172 or not 0 < height <= 180:
        raise ValueError("Tiny clock drawing exceeds the page envelope")
    if {n["domain"] for n in circuit["nodes"] if "domain" in n} != {d["name"] for d in domains}:
        raise ValueError("Tiny clock drawing differs from the seven-domain inventory")
    nodes = {node["id"]: dict(node, role="block") for node in circuit["nodes"]}
    ports = {f"{node['id']}.{p['id']}": p for node in nodes.values() for p in node["ports"]}
    for node in [*nodes.values(), *sheet["groups"]]:
        x, y, w, h = (node[key] for key in ("x", "y", "w", "h"))
        if min(x, y) < 1 or min(w, h) <= 0 or x + w > width - 1 or y + h > height - 1:
            raise ValueError("Tiny clock symbol or group lies outside the frame")
    for node in nodes.values():
        if node["shape"] not in {"block", "gate", "mux", "pin", "sink", "tap"}:
            raise ValueError("Tiny clock drawing contains an unknown symbol")
        if node["shape"] == "tap" and ports.get(node.get("source_port"), {}).get("direction") != "out":
            raise ValueError("Tiny CLKOUT tap has no named driving port")
    edges = []
    for edge in circuit["edges"]:
        source, target = (ports[edge[key]] for key in ("from", "to"))
        edges.append(dict(edge, id=edge["from"] + " -> " + edge["to"], net=edge["from"],
                          **{"from": edge["from"].split(".")[0], "to": edge["to"].split(".")[0]},
                          source_side=source["side"], source_position=source["position"],
                          target_side=target["side"], target_position=target["position"], arrow=True))
    diagram = dict(nodes=list(nodes.values()), edges=edges, routing=sheet["routing"])
    issues = geometry_issues(diagram)
    if issues:
        raise ValueError("Tiny clock tree geometry: " + "; ".join(issues))
    paths = routes(diagram)
    points = (p for path in paths for p in path["points"])
    if any(not 1 <= x <= width - 1 or not 1 <= y <= height - 1 for x, y in points):
        raise ValueError("Tiny clock route lies outside the frame")
    wires, junctions = _segments(paths)
    sheet["segments"] = _separate_crossings(wires)
    sheet["junctions"] = junctions
    sheet["arrows"] = [dict(points=head, kind=path["kind"]) for path in paths for head in path["heads"]]
