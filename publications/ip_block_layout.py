"""Explicit RCC-style IP geometry; facts remain in each product circuit catalog.

All coordinates are final millimetres. There is deliberately no route search or
label fallback here: an authored route either satisfies the contract or fails.
"""

from __future__ import annotations

from collections import Counter, defaultdict
from copy import deepcopy
import math
from pathlib import Path
import re

STYLE = "ip-block-v2"
STROKE = 0.65 * 25.4 / 72
MIN_SEGMENT = 4.0
MAX_BENDS = 4
PARALLEL_PITCH = 3.0
BRIDGE_RADIUS = 1.0


def normalized(value: str) -> str:
    from publications.implementation_reference import without_comments

    return re.sub(r"\s+", "", without_comments(value))


def canonical_net(circuit: dict, edge: dict) -> str:
    """Only explicit, source-checked expressions authorize shared wire trunks."""
    if edge.get("boundary"):
        names = edge.get("boundary_signals", [edge["label"]])
        ports = {p["name"]: p for p in circuit["block_diagram"].get("ports", [])}
        return "|".join(ports[name]["file"] + ":" + name for name in sorted(names))
    if "interface" in edge:
        item = circuit["block_diagram"]["interfaces"][edge["interface"]]
        return item["file"] + ":interface:" + str(edge["interface"])
    if "parent_edge" in edge:
        return "parent:" + circuit["edges"][edge["parent_edge"]]["from"]
    source = edge.get("source", {})
    if source.get("nets"):
        return source["file"] + ":" + "|".join(sorted(normalized(net) for net in source["nets"]))
    return "internal:" + edge["id"]


def validate_functional(root: Path, circuit: dict, graph: dict) -> None:
    """Check every new functional block in its actual owning RTL scope."""
    from publications.ip_block_reference import source_members

    owners = {n["id"]: n for n in circuit["nodes"]}
    product = circuit["block_diagram"].get("product")
    if product not in {"tiny", "mini"}:
        raise ValueError("IP functional view has no selected product")

    def product_source(relative):
        for other in {"tiny", "mini"} - {product}:
            if relative.startswith("rtl/" + other + "/"):
                raise ValueError("IP functional evidence crosses product boundaries")

    for owner in owners.values():
        for relative in owner["sources"]:
            product_source(relative)
    parameter_values = {}
    for parameter in graph.get("parameters", []):
        product_source(parameter["file"])
        if type(parameter["value"]) is not int or parameter["value"] < 0:
            raise ValueError("IP numeric parameter is unknown or has the wrong type")
        if parameter.get("kind", "instance") == "literal":
            template = parameter.get("template", "")
            if template.count("{value}") != 1:
                raise ValueError("IP literal dimension lacks a unique source placeholder")
            text = (root / parameter["file"]).read_text(encoding="utf-8")
            scopes = re.findall(
                r"\bmodule\s+" + re.escape(parameter["module"]) + r"\b(.*?)\bendmodule\b",
                text,
                re.S,
            )
            if len(scopes) != 1 or normalized(
                template.format(value=parameter["value"])
            ) not in normalized(scopes[0]):
                raise ValueError("IP literal dimension differs from its owning RTL scope")
        elif parameter.get("kind", "instance") == "instance":
            candidates = source_members(root, parameter["file"], (parameter["module"],))
            actual = next((u for u in candidates if u["id"] == parameter["instance"]), None)
            if actual is None:
                raise ValueError("IP selected parameter instance disappeared")
            raw = actual["parameters_raw"].get(parameter["parameter"])
            if raw is None or not re.fullmatch(r"[0-9]+", raw) or int(raw) != parameter["value"]:
                raise ValueError(
                    "IP displayed parameter differs from its selected product instance"
                )
        else:
            raise ValueError("IP numeric parameter has an unknown evidence kind")
        if parameter["id"] in parameter_values:
            raise ValueError("IP selected parameter is duplicated")
        parameter_values[parameter["id"]] = parameter["value"]
    nodes = {n["id"]: n for n in graph["nodes"]}
    if len(nodes) != len(graph["nodes"]):
        raise ValueError("IP functional node is duplicated")
    declarations = {p["name"]: p for p in circuit["block_diagram"].get("ports", [])}
    boundary_members = []
    interface_members = []
    physical = Counter()
    for node in nodes.values():
        if node.get("title_template") and node["title"] != node["title_template"].format(
            **parameter_values
        ):
            raise ValueError("IP functional parameter label is stale")
        if node.get("pin_list") and set(node["pin_list"]) != set(node.get("boundary_members", [])):
            raise ValueError("IP boundary pin list differs from its declared signals")
        if not node.get("title") or node.get("owner") not in owners:
            raise ValueError("IP functional node has no title or owning source group")
        owner = owners[node["owner"]]
        if node.get("boundary_members"):
            members = node["boundary_members"]
            if any(p not in declarations for p in members):
                raise ValueError("IP functional boundary signal is unknown")
            if len({declarations[p]["direction"] for p in members}) != 1:
                raise ValueError("IP functional boundary mixes input and output directions")
            boundary_members.extend(members)
        if node.get("interface_refs"):
            interfaces = circuit["block_diagram"].get("interfaces", [])
            for ref in node["interface_refs"]:
                if (
                    type(ref) is not int
                    or not 0 <= ref < len(interfaces)
                    or interfaces[ref]["node"] != node["owner"]
                ):
                    raise ValueError("IP functional interface is unknown or has the wrong owner")
            interface_members.extend(node["interface_refs"])
            continue
        if node.get("ref"):
            if node["ref"] != owner["id"]:
                raise ValueError("IP functional context references another owner")
            if owner["id"] in circuit["block_diagram"].get("buses", []) + circuit[
                "block_diagram"
            ].get("external", []):
                continue
            if owner.get("instance_source"):
                original = owner["instance_source"]
                physical[(owner["id"], original["name"])] += 1
                actual = source_members(root, original["file"], (original["module"],))
                if not any(u["id"] == original["name"] for u in actual):
                    raise ValueError("IP referenced instance disappeared")
                continue
        if node.get("boundary_members"):
            continue
        refs = ([node["instance_ref"]] if node.get("instance_ref") else []) + node.get(
            "instance_refs", []
        )
        for instance in refs:
            instance_owner = owners[instance["owner"]] if isinstance(instance, dict) else owner
            name = instance["id"] if isinstance(instance, dict) else instance
            physical[(instance_owner["id"], name)] += 1
            unit = next((u for u in instance_owner.get("units", []) if u["id"] == name), None)
            if unit is None:
                raise ValueError("IP functional block refers to an unknown instance")
            actual = source_members(
                root, unit["bindings"][0]["file"], (unit["module"],), scope=unit.get("scope_module")
            )
            if not any(u["id"] == name and u["module"] == unit["module"] for u in actual):
                raise ValueError("IP functional instance disappeared")
        proof = node.get("logic_source")
        if not refs and not proof:
            raise ValueError("IP functional block lacks instance or local-logic evidence")
        if proof:
            relative = proof["file"]
            product_source(relative)
            path = (root / relative).resolve()
            if (
                not path.is_relative_to(root.resolve())
                or relative not in owner["sources"]
                or not relative.startswith(("rtl/", ".cache/retrosoc/sources/"))
            ):
                raise ValueError("IP local logic escapes its owning RTL source")
            if not relative.startswith("rtl/"):
                from scripts.dependency_lock import load_lock
                from scripts.setup_helpers import git_output

                dependency = load_lock(root / "dependencies/dependencies.lock.json")["sources"].get(
                    proof.get("dependency")
                )
                if dependency is None or not path.is_relative_to(
                    (root / dependency["destination"]).resolve()
                ):
                    raise ValueError("IP managed logic has no selected locked dependency")
                repository = root / dependency["destination"]
                if git_output(repository, "rev-parse", "HEAD") != dependency[
                    "revision"
                ] or git_output(repository, "status", "--porcelain"):
                    raise ValueError("IP managed logic differs from its clean locked source")
            text = path.read_text(encoding="utf-8")
            scope = re.findall(
                r"\bmodule\s+" + re.escape(proof["module"]) + r"\b(.*?)\bendmodule\b",
                text,
                re.S,
            )
            if len(scope) != 1:
                raise ValueError("IP local-logic module is missing or ambiguous")
            source = normalized(scope[0])
            if not proof.get("symbols") or not proof.get("bindings"):
                raise ValueError("IP local logic lacks signals and executable bindings")
            for symbol in proof["symbols"]:
                if not re.fullmatch(r"[A-Za-z_]\w*", symbol) or not re.search(
                    r"\b" + re.escape(symbol) + r"\b", scope[0]
                ):
                    raise ValueError("IP local-logic signal differs from source")
            for binding in proof["bindings"]:
                if normalized(binding) not in source:
                    raise ValueError("IP local-logic binding differs from source")
        if node.get("scope", "local-logic") not in {"local-logic", "rtl-instance"}:
            raise ValueError("IP functional block has an unknown hardware identity")
    if any(count > 1 for count in physical.values()):
        raise ValueError("IP functional drawing repeats the same physical instance")
    if Counter(boundary_members) != Counter(list(declarations)):
        raise ValueError("IP functional clock/reset/IRQ coverage is incomplete")
    if Counter(interface_members) != Counter(
        range(len(circuit["block_diagram"].get("interfaces", [])))
    ):
        raise ValueError("IP functional bus/stream interface coverage is incomplete")
    represented = {
        n["owner"]
        for n in nodes.values()
        if (not n.get("boundary_members") and not n.get("interface_refs")) or n.get("ref")
    }
    if represented != set(owners):
        raise ValueError("IP functional drawing omits an original source group")
    edge_ids = [e["id"] for e in graph["edges"]]
    if len(set(edge_ids)) != len(edge_ids):
        raise ValueError("IP functional connection is duplicated")
    covered = set()
    projected_ports = defaultdict(set)
    input_instances = {}
    for edge in graph["edges"]:
        if edge["from"] not in nodes or edge["to"] not in nodes or edge["from"] == edge["to"]:
            raise ValueError("IP functional connection has an unknown endpoint")
        if edge["kind"] not in {"data", "control", "clock", "reset", "irq", "status"}:
            raise ValueError("IP functional connection has an unknown role")
        if not edge.get("label") or edge["label"] in {
            "Payload",
            "Control / status",
            "Parent connections",
        }:
            raise ValueError("IP functional connection has no meaningful signal name")
        if edge.get("width") is not None and (type(edge["width"]) is not int or edge["width"] <= 0):
            raise ValueError("IP functional signal width is invalid")
        if "parent_edge" in edge:
            index = edge["parent_edge"]
            if type(index) is not int or not 0 <= index < len(circuit["edges"]):
                raise ValueError("IP functional connection has an unknown parent binding")
            original = circuit["edges"][index]
            if [nodes[edge[k]]["owner"] for k in ("from", "to")] != [
                original[k].split(".")[0] for k in ("from", "to")
            ]:
                raise ValueError("IP functional connection reverses its source direction")
            ports = {n["id"] + "." + p["id"]: p for n in circuit["nodes"] for p in n["ports"]}
            if edge.get("width") != ports[original["from"]]["width"]:
                raise ValueError("IP functional signal width differs from its source port")
            if edge["kind"] not in {"clock", "reset"}:
                for end in ("from", "to"):
                    function = nodes[edge[end]]
                    for port in original.get("instance_ports", []):
                        if port["node"] != function["owner"]:
                            continue
                        if port["port"] not in function.get("functional_ports", []):
                            raise ValueError(
                                "IP functional port targets a different local function"
                            )
                        projected_ports[function["id"]].add(port["port"])
            covered.add(index)
        elif "interface" in edge:
            ref = edge["interface"]
            interface = circuit["block_diagram"]["interfaces"][ref]
            endpoints = [nodes[edge[k]] for k in ("from", "to")]
            terminal = next((n for n in endpoints if ref in n.get("interface_refs", [])), None)
            if terminal is None or edge.get("width") != interface["width"]:
                raise ValueError("IP functional bus/stream width or identity differs from source")
            direction = interface.get(
                "direction", "input" if interface["side"] == "left" else "output"
            )
            if (edge["from"] == terminal["id"]) != (direction == "input"):
                raise ValueError("IP functional interface direction differs from its source")
        elif edge.get("boundary"):
            port_node = (
                nodes[edge["from"]]
                if nodes[edge["from"]].get("boundary_members")
                else nodes[edge["to"]]
            )
            if not port_node.get("boundary_members"):
                raise ValueError("IP boundary connection has no declared signal")
            direction = declarations[port_node["boundary_members"][0]]["direction"]
            if (edge["from"] == port_node["id"]) != (direction == "input"):
                raise ValueError("IP boundary connection direction differs from RTL")
            if direction == "input" and edge["kind"] in {"clock", "reset"}:
                function_owner = owners[nodes[edge["to"]]["owner"]]
                info = function_owner.get("instance_source")
                if info:
                    identity = (info["file"], info["module"], info["name"])
                    if identity not in input_instances:
                        input_instances[identity] = next(
                            (
                                u
                                for u in source_members(root, info["file"], (info["module"],))
                                if u["id"] == info["name"]
                            ),
                            None,
                        )
                    instance = input_instances[identity]
                    if instance is None:
                        raise ValueError("IP input clock/reset has no selected source instance")
                    for name in edge.get("boundary_signals", port_node["boundary_members"]):
                        declared_file = declarations[name]["file"]
                        if declared_file == info.get("declaration_file"):
                            matched = name in instance["ports_raw"]
                        elif declared_file == info["file"]:
                            matched = any(
                                re.search(r"\b" + re.escape(name) + r"\b", value)
                                for value in instance["ports_raw"].values()
                            )
                        else:
                            raise ValueError(
                                "IP input clock/reset needs an explicit hierarchy scope"
                            )
                        if not matched:
                            raise ValueError(
                                "IP input clock/reset targets an unrelated source function"
                            )
        else:
            proof = edge.get("source")
            if not proof or not proof.get("signals") or not proof.get("bindings"):
                raise ValueError("IP internal connection lacks signal/relationship evidence")
            relative = proof["file"]
            if relative not in set(owners[nodes[edge["from"]]["owner"]]["sources"]) | set(
                owners[nodes[edge["to"]]["owner"]]["sources"]
            ) | set(circuit["block_diagram"]["wrapper"]):
                raise ValueError("IP internal connection crosses an unrelated source scope")
            text = (root / relative).read_text(encoding="utf-8")
            module = proof.get("module")
            if not module:
                raise ValueError("IP internal connection lacks its owning RTL module")
            scopes = re.findall(
                r"\bmodule\s+" + re.escape(module) + r"\b(.*?)\bendmodule\b", text, re.S
            )
            if len(scopes) != 1:
                raise ValueError("IP internal connection has a missing/ambiguous RTL module")
            text = scopes[0]
            for signal in proof["signals"]:
                if not re.fullmatch(r"[A-Za-z_]\w*", signal) or not re.search(
                    r"\b" + re.escape(signal) + r"\b", text
                ):
                    raise ValueError("IP internal connection signal differs from source")
            if any(normalized(b) not in normalized(text) for b in proof["bindings"]):
                raise ValueError("IP internal connection binding differs from source")
            for expression in proof.get("nets", []):
                if not re.fullmatch(
                    r"[A-Za-z_]\w*(?:\.\w+|\[[A-Za-z_0-9:+*-]+\])*", expression
                ) or normalized(expression) not in normalized(text):
                    raise ValueError("IP shared-net expression differs from its source")
        if edge.get("boundary"):
            names = edge.get("boundary_signals", [edge["label"]])
            for name in names:
                if name not in declarations:
                    raise ValueError("IP boundary connection names a non-existent port")
                port = declarations[name]
                terminal = (
                    nodes[edge["from"]] if port["direction"] == "input" else nodes[edge["to"]]
                )
                if name not in terminal.get("boundary_members", []):
                    raise ValueError("IP boundary connection targets the wrong declared port")
        if edge.get("net") != canonical_net(circuit, edge):
            raise ValueError("IP shared trunk is not the same source-qualified net")
        if edge.get("both") and edge.get("protocol") not in {"APB4", "AHB-Lite", "AXI4"}:
            raise ValueError("IP bidirectional bundle lacks a declared bus protocol")
        if edge.get("label_in_node") and not any(
            normalized(edge["label"]).lower() in normalized(nodes[edge[k]]["title"]).lower()
            or edge["label"] in nodes[edge[k]].get("pin_list", {})
            for k in ("from", "to")
        ):
            raise ValueError("IP signal label is absent from its selected endpoint")
    if covered != set(range(len(circuit["edges"]))):
        raise ValueError("IP functional drawing omits a source-bound parent connection")
    for node in nodes.values():
        declared = node.get("functional_ports", [])
        if len(declared) != len(set(declared)) or set(declared) != projected_ports[node["id"]]:
            raise ValueError(
                "IP functional port projection is duplicated or lacks a source connection"
            )
    linked = {e[k] for e in graph["edges"] for k in ("from", "to")}
    if linked != set(nodes):
        raise ValueError("IP functional block is disconnected")
    layout = graph.get("layout", {})
    if set(layout.get("nodes", {})) != set(nodes) or set(layout.get("routes", {})) != set(edge_ids):
        raise ValueError("IP explicit layout is incomplete")


def endpoint(node: dict, side: str, offset: float) -> list[float]:
    if side in {"west", "east"}:
        if not 0 <= offset <= node["h"]:
            raise ValueError("IP port offset exceeds its block")
        return [node["x"] + (node["w"] if side == "east" else 0), node["y"] + offset]
    if side not in {"north", "south"} or not 0 <= offset <= node["w"]:
        raise ValueError("IP port side or offset is invalid")
    return [node["x"] + offset, node["y"] + (node["h"] if side == "south" else 0)]


def simplify(points: list) -> list:
    result = []
    for p in points:
        if result and p == result[-1]:
            continue
        if len(result) >= 2 and (
            result[-2][0] == result[-1][0] == p[0] or result[-2][1] == result[-1][1] == p[1]
        ):
            result.pop()
        result.append(list(p))
    return result


def triangle(points: list, reverse: bool = False) -> list:
    route = list(reversed(points)) if reverse else points
    tip, previous = route[-1], route[-2]
    distance = math.dist(tip, previous)
    if not distance:
        raise ValueError("IP arrow has no terminal shaft")
    u, v = [(tip[k] - previous[k]) / distance for k in (0, 1)]
    return [
        [tip[0] - u * 1.8 - v * 0.75, tip[1] - v * 1.8 + u * 0.75],
        tip,
        [tip[0] - u * 1.8 + v * 0.75, tip[1] - v * 1.8 - u * 0.75],
    ]


def make_scene(circuit: dict, advances: dict, graph: dict | None = None) -> dict:
    from publications.ip_block_reference import wrap

    graph = graph or circuit["block_diagram"]["functional"]
    layout = graph["layout"]
    originals = {n["id"]: n for n in circuit["nodes"]}
    view = circuit["block_diagram"]
    scene = dict(
        width=172,
        height=layout["height"],
        boundary=layout["boundary"],
        style=STYLE,
        nodes=[],
        wires=[],
        labels=[],
        legend=[],
        ports=[],
        interfaces=[],
        groups=deepcopy(layout.get("groups", [])),
        routing_strategy="authored-functional-lanes-v2",
    )
    from publications.ip_block_reference import text_width

    heading = view.get("boundary_title", view["title"].split(" / ")[0])
    scene["heading"] = dict(
        text=heading,
        x=layout.get("heading", [layout["boundary"][0] + 3, layout["boundary"][1] + 2])[0],
        y=layout.get("heading", [layout["boundary"][0] + 3, layout["boundary"][1] + 2])[1],
        w=text_width(heading, advances) * 1.08,
        h=3.7,
    )
    for item in graph["nodes"]:
        x, y, width, height = layout["nodes"][item["id"]]
        role = "internal"
        if item.get("pin_list"):
            role = "pin-list"
        elif item.get("context") or (item.get("boundary_members") and not item.get("ref")):
            role = "terminal"
        elif item.get("interface_refs"):
            role = "bus"
        elif item.get("ref") in view.get("buses", []):
            role = "bus"
        elif item.get("ref") in view.get("external", []):
            role = "external"
        if item.get("bus"):
            role = "bus"
        owner = originals[item["owner"]]
        shape = item.get("shape", "block")
        if item.get("instance_ref") and isinstance(item["instance_ref"], str):
            unit = next(u for u in owner["units"] if u["id"] == item["instance_ref"])
            shape = item.get("shape", unit["shape"])
        scene["nodes"].append(
            dict(
                id=item["id"],
                x=x,
                y=y,
                w=width,
                h=height,
                lines=wrap(item["title"], width - (0 if role == "terminal" else 4), advances),
                role=role,
                shape=shape,
                owner=item["owner"],
                condition=item.get("condition"),
                boundary_members=item.get("boundary_members", []),
                scope=item.get("scope"),
                ownership=item.get(
                    "ownership", "ip-internal" if role == "internal" else "external-context"
                ),
                title=item["title"],
                side=item.get("side", "left"),
                proof={k: item[k] for k in ("ref", "logic_source", "instance_ref") if k in item},
            )
        )
        if item.get("pin_list"):
            scene["nodes"][-1]["lines"] = []
            scene["nodes"][-1]["pin_list"] = item["pin_list"]
            scene["nodes"][-1]["pin_labels"] = [
                dict(text=name, lines=wrap(name, width - 2, advances), y=y + offset)
                for name, offset in item["pin_list"].items()
            ]
    nodes = {n["id"]: n for n in scene["nodes"]}
    for index, edge in enumerate(graph["edges"]):
        route = layout["routes"][edge["id"]]
        points = simplify(route["points"])
        if points != route["points"]:
            raise ValueError("IP explicit route contains duplicate/collinear points")
        for end, key in [(0, "from"), (-1, "to")]:
            port = route[key]
            if nodes[edge[key]]["role"] == "bus" and port["side"] != (
                "west" if nodes[edge[key]]["side"] == "right" else "east"
            ):
                raise ValueError("IP bus route does not meet its actual spine")
            if endpoint(nodes[edge[key]], port["side"], port["offset"]) != points[end]:
                raise ValueError("IP explicit route does not meet its selected functional port")
            if nodes[edge[key]].get("pin_list") and (
                edge["label"] not in nodes[edge[key]]["pin_list"]
                or port["side"] != "west"
                or port["offset"] != nodes[edge[key]]["pin_list"][edge["label"]]
            ):
                raise ValueError("IP route does not meet its named boundary pin")
        net = edge.get("net", "edge:" + edge["id"])
        wire = dict(
            index=index,
            id=edge["id"],
            points=points,
            kind=edge["kind"],
            label=edge["label"],
            from_node=edge["from"],
            to_node=edge["to"],
            source_key=net,
            target_key=net,
            both=edge.get("both", False),
            label_mode="direct",
            arrows=[triangle(points)],
            lengths=[round(math.dist(a, b), 6) for a, b in zip(points, points[1:])],
            bends=len(points) - 2,
        )
        if wire["both"]:
            wire["arrows"].append(triangle(points, True))
        scene["wires"].append(wire)
        if route.get("label"):
            label = route["label"]
            lines = wrap(edge["label"], label[2], advances)
            scene["labels"].append(
                dict(
                    x=label[0],
                    y=label[1],
                    w=label[2],
                    h=len(lines) * 3.7,
                    text=edge["label"],
                    lines=lines,
                    edge=index,
                )
            )
        elif not edge.get("label_in_node"):
            raise ValueError("IP explicit connection has no on-figure signal label")
    scene["crossings"], scene["junctions"] = intersections(scene["wires"])
    for node in scene["nodes"]:
        if node["role"] != "terminal" or len(node.get("boundary_members", [])) != 1:
            continue
        connected = [w for w in scene["wires"] if node["id"] in {w["from_node"], w["to_node"]}]
        if len(connected) != 1:
            continue
        wire = connected[0]
        end = "from" if wire["from_node"] == node["id"] else "to"
        edge = graph["edges"][wire["index"]]
        port = layout["routes"][edge["id"]][end]
        px, py = endpoint(node, port["side"], port["offset"])
        width = max((text_width(s, advances) for s in node["lines"]), default=0)
        height = len(node["lines"]) * 3.7
        if port["side"] == "west":
            x, y = px + 1.5, py - height / 2
        elif port["side"] == "east":
            x, y = px - 1.5 - width, py - height / 2
        elif port["side"] == "north":
            x, y = px - width / 2, py + 1.5
        else:
            x, y = px - width / 2, py - 1.5 - height
        node["signal_label"] = dict(
            x=x, y=y, w=width, h=height, lines=node["lines"], text=node["title"], owner=node["id"]
        )
    scene["segments"] = merged_segments(scene["wires"])
    scene["metrics"] = dict(
        min_segment=min((v for w in scene["wires"] for v in w["lengths"]), default=None),
        max_bends=max((w["bends"] for w in scene["wires"]), default=0),
        crossings=len(scene["crossings"]),
        functional_nodes=sum(n["role"] == "internal" for n in scene["nodes"]),
    )
    return scene


def intersection(a, b, c, d):
    if a[1] == b[1] and c[0] == d[0]:
        p = [c[0], a[1]]
        if min(a[0], b[0]) <= p[0] <= max(a[0], b[0]) and min(c[1], d[1]) <= p[1] <= max(
            c[1], d[1]
        ):
            return p
    if a[0] == b[0] and c[1] == d[1]:
        return intersection(c, d, a, b)
    return None


def intersections(wires):
    crossings, junctions = {}, set()
    for i, left in enumerate(wires):
        for right in wires[i + 1 :]:
            for a, b in zip(left["points"], left["points"][1:]):
                for c, d in zip(right["points"], right["points"][1:]):
                    p = intersection(a, b, c, d)
                    if p is None:
                        continue
                    if left["source_key"] == right["source_key"]:
                        if p in left["points"] or p in right["points"]:
                            junctions.add(tuple(p))
                    else:
                        h, v = (left, right) if a[1] == b[1] else (right, left)
                        crossings.setdefault(
                            (h["source_key"], v["source_key"], *p),
                            dict(
                                point=p,
                                horizontal=h["index"],
                                vertical=v["index"],
                                radius=BRIDGE_RADIUS,
                            ),
                        )
    return list(crossings.values()), [list(p) for p in sorted(junctions)]


def merged_segments(wires):
    channels = defaultdict(list)
    for wire in wires:
        for a, b in zip(wire["points"], wire["points"][1:]):
            horizontal = a[1] == b[1]
            axis = 0 if horizontal else 1
            channels[(wire["source_key"], horizontal, a[1 - axis])].append(
                sorted([a[axis], b[axis]])
            )
    result = []
    for (net, horizontal, fixed), ranges in sorted(channels.items()):
        intervals = []
        for low, high in sorted(ranges):
            if intervals and low <= intervals[-1][1]:
                intervals[-1][1] = max(high, intervals[-1][1])
            else:
                intervals.append([low, high])
        for low, high in intervals:
            result.append(
                dict(
                    points=[[low, fixed], [high, fixed]]
                    if horizontal
                    else [[fixed, low], [fixed, high]],
                    net=net,
                )
            )
    return result


def point_in_polygon(p, polygon):
    inside = False
    for a, b in zip(polygon, polygon[1:] + polygon[:1]):
        if (a[1] > p[1]) != (b[1] > p[1]) and p[0] < (b[0] - a[0]) * (p[1] - a[1]) / (
            b[1] - a[1]
        ) + a[0]:
            inside = not inside
    return inside


def polygon_distance(segment, polygon):
    from publications.soc_diagram_geometry import segment_distance

    a, b = segment
    if point_in_polygon(a, polygon) or point_in_polygon(b, polygon):
        return 0
    return min(segment_distance(a, b, c, d) for c, d in zip(polygon, polygon[1:] + polygon[:1]))


def geometry_issues(scene, advances):
    from publications.ip_block_reference import overlaps, text_width
    from publications.soc_diagram_geometry import segment_distance

    issues = []
    if not 0 < scene["width"] <= 172 or not 0 < scene["height"] <= 200:
        issues.append("canvas-size")
    nodes = {n["id"]: n for n in scene["nodes"]}
    boxes = {key: [n[k] for k in ("x", "y", "w", "h")] for key, n in nodes.items()}
    for key, n in nodes.items():
        x, y, w, h = boxes[key]
        if x < 1 or y < 1 or x + w > scene["width"] - 1 or y + h > scene["height"] - 1:
            issues.append("node-bounds:" + key)
        inset = 0 if n["role"] in {"terminal", "bus"} else 4
        if max((text_width(s, advances) for s in n["lines"]), default=0) > w - inset + 0.01:
            issues.append("text-width:" + key)
        if any(
            re.fullmatch(r"[A-Za-z]+", word) and text_width(word, advances) > w - inset + 0.01
            for word in n["title"].split()
        ):
            issues.append("ordinary-word-split:" + key)
        if len(n["lines"]) * 3.7 > h - (0 if not inset else 3) + 0.01:
            issues.append("text-height:" + key)
        for other in nodes:
            if other > key and overlaps(boxes[key], boxes[other], 0.2):
                issues.append("node-overlap:" + key + ":" + other)
    wires = scene["wires"]
    bx, by, bw, bh = scene["boundary"]
    for key, n in nodes.items():
        if n["role"] == "internal" and not (
            bx + 0.5 <= n["x"]
            and by + 0.5 <= n["y"]
            and n["x"] + n["w"] <= bx + bw - 0.5
            and n["y"] + n["h"] <= by + bh - 0.5
        ):
            issues.append("owned-node-outside:" + key)
    border = [
        ([bx, by], [bx + bw, by]),
        ([bx + bw, by], [bx + bw, by + bh]),
        ([bx, by + bh], [bx + bw, by + bh]),
        ([bx, by], [bx, by + bh]),
    ]
    for wire in wires:
        ident = wire["id"]
        points = wire["points"]
        if len(points) - 2 > MAX_BENDS:
            issues.append("route-bends:" + ident)
        for si, (a, b) in enumerate(zip(points, points[1:])):
            for c, d in border:
                if (
                    a[1] == b[1] == c[1] == d[1]
                    and max(min(a[0], b[0]), min(c[0], d[0]))
                    < min(max(a[0], b[0]), max(c[0], d[0]))
                ) or (
                    a[0] == b[0] == c[0] == d[0]
                    and max(min(a[1], b[1]), min(c[1], d[1]))
                    < min(max(a[1], b[1]), max(c[1], d[1]))
                ):
                    issues.append("wire-boundary-overlap:" + ident)
            if math.dist(a, b) < MIN_SEGMENT - 0.01:
                issues.append("route-short:" + ident)
            if a == b or (a[0] != b[0] and a[1] != b[1]):
                issues.append("route-diagonal:" + ident)
            if any(
                not (1 <= p[0] <= scene["width"] - 1 and 1 <= p[1] <= scene["height"] - 1)
                for p in (a, b)
            ):
                issues.append("route-bounds:" + ident)
            for key, n in nodes.items():
                if (key == wire["from_node"] and si == 0) or (
                    key == wire["to_node"] and si == len(points) - 2
                ):
                    continue
                x, y, w, h = boxes[key]
                halo = (
                    1
                    if n.get("condition") and n["role"] not in {"bus", "terminal", "pin-list"}
                    else 0
                )
                x, y, w, h = x - halo, y - halo, w + 2 * halo, h + 2 * halo
                polygon = [[x, y], [x + w, y], [x + w, y + h], [x, y + h]]
                if polygon_distance((a, b), polygon) < 1 + STROKE / 2 - 0.01:
                    issues.append("wire-node:" + ident + ":" + key)
        for arrow in wire["arrows"]:
            for key, n in nodes.items():
                if key in {wire["from_node"], wire["to_node"]}:
                    continue
                x, y, w, h = boxes[key]
                halo = (
                    1
                    if n.get("condition") and n["role"] not in {"bus", "terminal", "pin-list"}
                    else 0
                )
                polygon = [
                    [x - halo, y - halo],
                    [x + w + halo, y - halo],
                    [x + w + halo, y + h + halo],
                    [x - halo, y + h + halo],
                ]
                if any(
                    polygon_distance((a, b), polygon) < 1
                    for a, b in zip(arrow, arrow[1:] + arrow[:1])
                ):
                    issues.append("arrow-node:" + ident + ":" + key)
            for other in wires:
                if other["index"] == wire["index"] or other["source_key"] == wire["source_key"]:
                    continue
                if any(
                    polygon_distance((a, b), arrow) < STROKE / 2 + 0.1
                    for a, b in zip(other["points"], other["points"][1:])
                ):
                    issues.append("arrow-wire:" + ident + ":" + other["id"])
    for i, left in enumerate(wires):
        for right in wires[i + 1 :]:
            if left["source_key"] == right["source_key"]:
                continue
            for a, b in zip(left["points"], left["points"][1:]):
                for c, d in zip(right["points"], right["points"][1:]):
                    same = (a[1] == b[1] and c[1] == d[1]) or (a[0] == b[0] and c[0] == d[0])
                    if same and segment_distance(a, b, c, d) < PARALLEL_PITCH - 0.01:
                        issues.append("wire-spacing:" + left["id"] + ":" + right["id"])
                    p = intersection(a, b, c, d)
                    if (
                        p
                        and min(math.dist(p, q) for q in [*left["points"], *right["points"]])
                        < 4 - 0.01
                    ):
                        issues.append("crossing-access:" + left["id"] + ":" + right["id"])
    expected, _ = intersections(wires)
    if expected != scene.get("crossings", []):
        issues.append("crossing-record")
    for cross in scene.get("crossings", []):
        point = cross["point"]
        for wire in wires:
            if wire["source_key"] in {
                wires[cross["horizontal"]]["source_key"],
                wires[cross["vertical"]]["source_key"],
            }:
                continue
            if any(
                segment_distance([point[0] - 1, point[1] - 1], [point[0] + 1, point[1] - 1], a, b)
                < 1
                for a, b in zip(wire["points"], wire["points"][1:])
            ):
                issues.append("bridge-clearance:" + wire["id"])
    decorations = scene["labels"] + [scene["heading"]]
    for node in nodes.values():
        if node.get("signal_label"):
            decorations.append(node["signal_label"])
        for pin in node.get("pin_labels", []):
            decorations.append(
                dict(
                    text=pin["text"],
                    x=node["x"] + 2,
                    y=pin["y"] - len(pin["lines"]) * 3.7 / 2,
                    w=max((text_width(s, advances) for s in pin["lines"]), default=0),
                    h=len(pin["lines"]) * 3.7,
                    owner=node["id"],
                )
            )
    for label in decorations:
        x, y, w, h = [label[k] for k in ("x", "y", "w", "h")]
        polygon = [[x, y], [x + w, y], [x + w, y + h], [x, y + h]]
        if any(polygon_distance((a, b), polygon) < 1 + 0.9 * 25.4 / 144 - 0.01 for a, b in border):
            issues.append("label-boundary:" + label["text"])
        if x < 1 or y < 1 or x + w > scene["width"] - 1 or y + h > scene["height"] - 1:
            issues.append("label-bounds:" + label["text"])
        if any(
            overlaps([x, y, w, h], box, 1)
            for key, box in boxes.items()
            if key != label.get("owner")
        ):
            issues.append("label-node:" + label["text"])
        for wire in wires:
            if any(
                polygon_distance((a, b), polygon) < 1 + STROKE / 2 - 0.01
                for a, b in zip(wire["points"], wire["points"][1:])
            ):
                issues.append("label-wire:" + label["text"])
        for other in decorations:
            if other is not label and overlaps(
                [x, y, w, h], [other[k] for k in ("x", "y", "w", "h")], 0.5
            ):
                issues.append("label-overlap:" + label["text"])
        for cross in scene.get("crossings", []):
            cx, cy = cross["point"]
            if overlaps(
                [x, y, w, h], [cx - 1 - STROKE / 2, cy - 1 - STROKE / 2, 2 + STROKE, 1 + STROKE], 1
            ):
                issues.append("bridge-label:" + label["text"])
    for cross in scene.get("crossings", []):
        cx, cy = cross["point"]
        symbol = [cx - 1 - STROKE / 2, cy - 1 - STROKE / 2, 2 + STROKE, 1 + STROKE]
        if any(overlaps(symbol, box, 0.1) for box in boxes.values()):
            issues.append("bridge-node")
    return sorted(set(issues))
