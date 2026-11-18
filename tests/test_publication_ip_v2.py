"""RCC IP routes must reject the short-jog/overlap failures of the old DMA view."""

from copy import deepcopy
import json
from pathlib import Path

import pytest

from publications import ip_block_layout as layout
from publications import ip_block_reference as blocks

ROOT = Path(__file__).resolve().parents[1]


@pytest.fixture(scope="module")
def dma():
    circuit = json.loads(
        (ROOT / "publications/datasheets/tiny/diagram-circuits.json").read_text(encoding="utf-8")
    )["dma"]
    assert circuit["block_diagram"]["style"] == layout.STYLE
    layout.validate_functional(ROOT, circuit, circuit["block_diagram"]["functional"])
    metrics = blocks.font_advances(
        ROOT / "publications/media/fonts/inter/Inter-VariableFont_opsz,wght.ttf"
    )
    scene = layout.make_scene(circuit, metrics)
    return circuit, metrics, scene


def test_dma_is_functionally_expanded_and_explicitly_routed(dma):
    circuit, metrics, scene = dma
    assert scene["metrics"]["functional_nodes"] >= 13
    assert scene["metrics"]["min_segment"] >= 4
    assert scene["metrics"]["max_bends"] <= 4
    assert not layout.geometry_issues(scene, metrics)
    assert "u_read_round_robin_arbiter" in json.dumps(circuit)
    assert "u_write_round_robin_arbiter" in json.dumps(circuit)
    assert {p["id"]: p["value"] for p in circuit["block_diagram"]["functional"]["parameters"]} == {
        "channels": 8,
        "fifo_words": 32,
        "word_bits": 32,
    }


def test_local_relationships_are_bound_to_their_module(dma):
    circuit, _, _ = dma
    damaged = deepcopy(circuit)
    graph = damaged["block_diagram"]["functional"]
    edge = next(e for e in graph["edges"] if e.get("source"))
    edge["source"]["module"] = "not_the_owning_module"
    with pytest.raises(ValueError, match="RTL module"):
        layout.validate_functional(ROOT, damaged, graph)


def test_same_physical_instance_is_not_drawn_twice(dma):
    circuit, _, _ = dma
    damaged = deepcopy(circuit)
    graph = damaged["block_diagram"]["functional"]
    node = deepcopy(next(n for n in graph["nodes"] if n.get("instance_ref")))
    node["id"] += "-duplicate"
    graph["nodes"].append(node)
    with pytest.raises(ValueError, match="same physical instance"):
        layout.validate_functional(ROOT, damaged, graph)


def test_selected_parameters_do_not_borrow_another_product(dma):
    circuit, _, _ = dma
    damaged = deepcopy(circuit)
    graph = damaged["block_diagram"]["functional"]
    graph["parameters"][0]["file"] = "rtl/mini/top/apb4_periph.sv"
    with pytest.raises(ValueError, match="crosses product boundaries"):
        layout.validate_functional(ROOT, damaged, graph)


def test_route_cannot_hide_along_the_ip_frame(dma):
    _, metrics, original = dma
    scene = deepcopy(original)
    x, y, _, _ = scene["boundary"]
    scene["wires"][0]["points"] = [[x, y + 8], [x, y + 20]]
    assert any("wire-boundary-overlap" in issue for issue in layout.geometry_issues(scene, metrics))


def test_ordinary_labels_cannot_be_split_into_fragments_to_fit(dma):
    _, metrics, original = dma
    scene = deepcopy(original)
    node = next(n for n in scene["nodes"] if n["role"] == "internal")
    node["title"] = "Unreasonablylongordinaryword"
    # Narrow manually supplied fragments must not hide the unbroken-word error.
    node["lines"] = ["Unreasonably", "longordinaryword"]
    node["w"] = 12
    assert any(
        "ordinary-word-split:" + node["id"] == issue
        for issue in layout.geometry_issues(scene, metrics)
    )


def test_ip_border_cannot_touch_a_signal_label(dma):
    _, metrics, original = dma
    scene = deepcopy(original)
    x, y, _, height = scene["boundary"]
    scene["labels"].append(dict(text="bottom signal", x=x + 10, y=y + height - 2, w=20, h=3.7))
    assert "label-boundary:bottom signal" in layout.geometry_issues(scene, metrics)


def test_owned_function_cannot_escape_the_gray_ip_boundary(dma):
    _, metrics, original = dma
    scene = deepcopy(original)
    node = next(n for n in scene["nodes"] if n["role"] == "internal")
    x, _, width, _ = scene["boundary"]
    node["x"] = x + width - 2
    assert "owned-node-outside:" + node["id"] in layout.geometry_issues(scene, metrics)


@pytest.mark.parametrize("value", [None, True, 0])
def test_unknown_or_wrong_numeric_parameter_is_not_coerced(dma, value):
    circuit, _, _ = dma
    damaged = deepcopy(circuit)
    graph = damaged["block_diagram"]["functional"]
    graph["parameters"][0]["value"] = value
    with pytest.raises(ValueError, match="parameter"):
        layout.validate_functional(ROOT, damaged, graph)


@pytest.mark.parametrize(
    "mutation", ["short-leg", "many-bends", "missing-bridge", "head-crossing", "node-crossing"]
)
def test_old_dma_route_failures_are_rejected(dma, mutation):
    _, metrics, original = dma
    scene = deepcopy(original)
    wire = scene["wires"][0]
    if mutation == "short-leg":
        # A one-millimetre jog was accepted by the previous centreline checker.
        wire["points"] = [[40, 40], [41, 40], [41, 50], [50, 50]]
    elif mutation == "many-bends":
        wire["points"] = [[30, 30], [40, 30], [40, 40], [50, 40], [50, 50], [60, 50], [60, 60]]
    elif mutation == "missing-bridge":
        assert scene["crossings"]
        scene["crossings"].pop()
    elif mutation == "head-crossing":
        arrow = wire["arrows"][0]
        x, y = arrow[0]
        scene["wires"][1]["points"] = [[x, y - 5], [x, y + 5]]
    else:
        node = next(
            n for n in scene["nodes"] if n["id"] not in {wire["from_node"], wire["to_node"]}
        )
        wire["points"] = [
            [node["x"] - 4, node["y"] + 4],
            [node["x"] + node["w"] + 4, node["y"] + 4],
        ]
    assert layout.geometry_issues(scene, metrics)


@pytest.mark.parametrize(
    "mutation",
    [
        "fake-unit",
        "fake-local-signal",
        "local-binding",
        "wrong-width",
        "wrong-direction",
        "wrong-parameter",
        "invisible-label",
    ],
)
def test_functional_detail_cannot_invent_hardware_or_connections(dma, mutation):
    original, _, _ = dma
    circuit = deepcopy(original)
    graph = circuit["block_diagram"]["functional"]
    node = next(n for n in graph["nodes"] if n.get("logic_source"))
    if mutation == "fake-unit":
        node["instance_ref"] = "u_not_hardware"
    elif mutation == "fake-local-signal":
        node["logic_source"]["symbols"][0] = "not_a_real_signal"
    elif mutation == "local-binding":
        node["logic_source"]["bindings"][0] = "assign imaginary_unit = 1'b1;"
    elif mutation == "wrong-parameter":
        graph["parameters"][0]["value"] = 4
    elif mutation == "invisible-label":
        graph["edges"][0]["label"] = "Missing on-figure signal name"
    else:
        edge = next(e for e in graph["edges"] if "parent_edge" in e)
        if mutation == "wrong-width":
            edge["width"] = 64
        else:
            edge["from"], edge["to"] = edge["to"], edge["from"]
    with pytest.raises(ValueError):
        layout.validate_functional(ROOT, circuit, graph)
