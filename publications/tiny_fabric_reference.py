"""Prepare the Tiny system-fabric drawing from its selected topology and RTL."""

import re
from pathlib import Path

from publications.register_reference import strip_comments
from publications.soc_diagram_geometry import endpoint, geometry_issues, routes, segment_distance


def _matrix_targets(topology: dict, apb_domains: dict) -> list[dict]:
    fabric = topology["fabric"]
    rows = [
        dict(port=f"b{target}", title=f"SRAM B{target}", targets=[target])
        for target in fabric["sram_targets"]
    ]
    rows.append(dict(port="xpi", title="XPI memory", targets=[fabric["xpi_target"]]))
    apb = {
        target["name"]: fabric["apb_target_base"] + index
        for index, target in enumerate(topology["apb_targets"])
    }
    if set(apb) != set(apb_domains):
        raise ValueError("Tiny fabric APB4 targets differ from their clock-domain map")
    for domain, name in (("system", "SYS"), ("aon", "AON"), ("peripheral", "PCLK"), ("memory", "MEM")):
        members = [target for target in apb if apb_domains[target] == domain]
        rows.append(dict(port="apb-" + domain, title=f"APB4 {name} ×{len(members)}",
                         targets=[apb[target] for target in members], members=members))
    rows.extend([
        dict(port="decerr", title="Decode error", targets=[fabric["decode_error_target"]]),
        dict(port="slverr", title="Protocol error", targets=[fabric["protocol_error_target"]]),
    ])
    if sorted(target for row in rows for target in row["targets"]) != list(range(fabric["target_count"])):
        raise ValueError("Tiny fabric drawing does not cover each target exactly once")
    return rows


def _fabric_interfaces(root: Path, owner_count: int) -> tuple[int, int, int]:
    fabric = root / "rtl/tiny/top/tiny_axi4_fabric.sv"
    source = strip_comments(fabric.read_text(encoding="utf-8"))
    channels = re.search(r"axi4_if\s*#\((.*?)\)\s*u_routes\[(\d+)\]", source, re.S)
    owners = re.search(r"for\s*\(genvar owner\s*=\s*0;\s*owner\s*<\s*(\d+);.*?begin\s*:\s*gen_route", source)
    if not channels or not owners or int(channels[2]) != owner_count or int(owners[1]) != owner_count:
        raise ValueError("Tiny fabric owner columns differ from the RTL routes")
    connectivity = (
        "u_routes[owner].araddr = masters[owner].araddr",
        "u_routes[owner].awaddr = masters[owner].awaddr",
        ".masters(u_routes)",
        ".target(targets[target_index])",
    )
    normalized = "".join(source.split())
    if any("".join(connection.split()) not in normalized for connection in connectivity):
        raise ValueError("Tiny fabric crosspoints differ from the target controller connections")
    data_width = re.search(r"\.DATA_WIDTH\s*\(\s*(\d+)\s*\)", channels[1])
    id_width = re.search(r"\.ID_WIDTH\s*\(\s*(\d+)\s*\)", channels[1])
    sram = (root / "rtl/tiny/top/tiny_sram.sv").read_text(encoding="utf-8")
    group_size = re.search(r"\.GroupBase\([^\n]*\*\s*32'h([0-9A-Fa-f_]+)\)", sram)
    if not data_width or not id_width or not group_size:
        raise ValueError("Tiny fabric width or SRAM group size is unbound")
    group_kib, remainder = divmod(int(group_size[1], 16), 1024)
    if not group_kib or remainder:
        raise ValueError("Tiny SRAM group stride is not a whole number of KiB")
    return int(data_width[1]), int(id_width[1]), group_kib


def _drawing_wires(circuit: dict, nodes: dict, routing: dict) -> list[dict]:
    ports = {f"{node['id']}.{p['id']}": p for node in nodes.values() for p in node["ports"]}
    edges = []
    for edge in circuit["edges"]:
        source, target = (ports[edge[key]] for key in ("from", "to"))
        edges.append(dict(edge, id=edge["from"] + " -> " + edge["to"],
                          **{"from": edge["from"].split(".")[0], "to": edge["to"].split(".")[0]},
                          source_side=source["side"], source_position=source["position"],
                          target_side=target["side"], target_position=target["position"], arrow=True))
    diagram = dict(nodes=list(nodes.values()), edges=edges, routing=routing)
    issues = geometry_issues(diagram)
    if issues:
        raise ValueError("Tiny fabric drawing geometry: " + "; ".join(issues))
    paths = routes(diagram)
    for index, path in enumerate(paths):
        segments = list(zip(path["points"], path["points"][1:]))
        for other in paths[index + 1:]:
            if any(segment_distance(a, b, c, d) < 0.1 for a, b in segments
                   for c, d in zip(other["points"], other["points"][1:])):
                raise ValueError(f"Tiny fabric routes intersect outside the matrix: {path['id']} / {other['id']}")
    return [dict(points=path["points"], heads=path["heads"], local=path.get("local", False)) for path in paths]


def prepare(root: Path, circuit: dict, topology: dict, apb_domains: dict) -> None:
    """Validate the plate, then attach geometry and crosspoints for the renderer."""
    plate = circuit["fabric_matrix"]
    width, height = plate["width_mm"], plate["height_mm"]
    if not 0 < width <= 172 or not 0 < height <= 165:
        raise ValueError("Tiny fabric drawing exceeds the page envelope")
    nodes = {node["id"]: dict(node, role="block") for node in circuit["nodes"]}
    for node in nodes.values():
        x, y, w, h = (node[key] for key in ("x", "y", "w", "h"))
        if min(x, y) < 1 or min(w, h) <= 0 or x + w > width - 1 or y + h > height - 1:
            raise ValueError("Tiny fabric symbol lies outside the frame")
    matrix = nodes["fabric"]
    ports = {p["id"]: p for p in matrix["ports"]}
    active = topology["fabric"]["active_owners"]
    owner_names = [topology["fabric"]["owners"][index] for index in active]
    if active != [0, 1, 2] or owner_names != ["cpu_slow", "central_dma", "sdio"]:
        raise ValueError("Tiny fabric owner order differs from its bound source")
    target_rows = _matrix_targets(topology, apb_domains)
    expected_ports = {row["port"] for row in target_rows} | {f"owner{owner}" for owner in active}
    if set(ports) != expected_ports or len(target_rows) != 11:
        raise ValueError("Tiny fabric matrix ports differ from its initiators and target rows")

    def matrix_port(name, side):
        port = ports[name]
        if port["side"] != side:
            raise ValueError("Tiny fabric has a misplaced matrix port")
        return endpoint(matrix, side, port["position"])

    columns = [dict(owner=owner, name=name, x=matrix_port(f"owner{owner}", "north")[0])
               for owner, name in zip(active, owner_names, strict=True)]
    rows = [dict(row, y=matrix_port(row["port"], "east")[1]) for row in target_rows]
    data_width, id_width, group_kib = _fabric_interfaces(root, len(columns))
    plate.update(
        columns=columns, rows=rows, data_width=data_width, id_width=id_width, group_kib=group_kib,
        sram_kib=len(topology["fabric"]["sram_targets"]) * group_kib,
        crosspoints=[[column["x"], row["y"]] for row in rows for column in columns],
        wires=_drawing_wires(circuit, nodes, plate["routing"]),
        terminals=[endpoint(n, p["side"], p["position"]) for n in nodes.values() for p in n["ports"]],
    )
    if any(not 1 <= x <= width - 1 or not 1 <= y <= height - 1
           for wire in plate["wires"] for x, y in wire["points"]):
        raise ValueError("Tiny fabric route lies outside the frame")
