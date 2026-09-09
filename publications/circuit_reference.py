"""Verify the named RTL instance ports used by the publication's circuit drawings."""
from __future__ import annotations

import re
from pathlib import Path

from publications.waveform_reference import DECLARATION, declaration, selected_width, uncomment
from publications.register_reference import split_top


def closing_parenthesis(text: str, start: int) -> int:
    depth = 0
    for index in range(start, len(text)):
        if text[index] == "(":
            depth += 1
        elif text[index] == ")":
            depth -= 1
            if depth == 0:
                return index
    raise ValueError("unbalanced circuit source instance")


def instance_ports(root: Path, source: dict) -> dict[str, set[str]]:
    text = uncomment((root / source["file"]).read_text(encoding="utf-8"))
    matches = list(re.finditer(r"\b" + re.escape(source["name"]) + r"\s*\(", text))
    if len(matches) != 1:
        raise ValueError("circuit source instance missing or ambiguous")
    match = matches[0]
    prefix = text[text.rfind(";", 0, match.start()) + 1:match.start()]
    if re.search(re.escape(source["module"]) + r"\b", prefix) is None:
        raise ValueError("circuit source instance module changed")
    end = closing_parenthesis(text, match.end() - 1)
    body = text[match.end():end]
    ports: dict[str, set[str]] = {}
    for port in re.finditer(r"\.(\w+)\s*\(", body):
        stop = closing_parenthesis(body, port.end() - 1)
        ports.setdefault(port[1], set()).add(re.sub(r"\s+", "", body[port.end():stop]))
    return ports


def validate_instance_connections(root: Path, circuit: dict) -> None:
    nodes = {node["id"]: node for node in circuit["nodes"]}
    ports = {key: instance_ports(root, node["instance_source"])
             for key, node in nodes.items() if "instance_source" in node}
    for edge in circuit["edges"]:
        endpoints = {edge["from"].split(".")[0], edge["to"].split(".")[0]}
        for bound in edge.get("instance_ports", []):
            if bound["node"] not in endpoints or bound["node"] not in ports:
                raise ValueError("circuit instance binding is not an edge endpoint")
            expressions = ports[bound["node"]].get(bound["port"], set())
            if re.sub(r"\s+", "", bound["expression"]) not in expressions:
                raise ValueError("circuit instance port binding changed")
            expected_direction = "output" if bound["node"] == edge["from"].split(".")[0] else "input"
            if (bound["port"].endswith("_o") and expected_direction != "output") or (
                bound["port"].endswith("_i") and expected_direction != "input"):
                raise ValueError("circuit endpoint direction contradicts the bound RTL port")
            source = nodes[bound["node"]]["instance_source"]
            if source.get("declaration_file"):
                text = uncomment((root / source["declaration_file"]).read_text(encoding="utf-8"))
                header = text[:text.find(");") + 2]
                for declared in DECLARATION.finditer(header):
                    names = [re.match(r"\s*(\w+)", item) for item in split_top(declared[3])]
                    if any(name and name[1] == bound["port"] for name in names):
                        if declared[1] not in {None, "inout", expected_direction}:
                            raise ValueError("circuit port direction differs from its module declaration")
        for signal in edge.get("signals", []):
            model = declaration(root, signal, signal.get("parameters", {}))
            if selected_width(model, "") != signal["bits"]:
                raise ValueError("circuit signal width changed")
            for endpoint in (edge["from"], edge["to"]):
                node, port = endpoint.split(".")
                width = next(p["width"] for p in nodes[node]["ports"] if p["id"] == port)
                if width != signal["bits"]:
                    raise ValueError("circuit label width differs from its source declaration")
