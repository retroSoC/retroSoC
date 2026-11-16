"""Functional IP drawings must remain source-bound, complete and legible."""

from copy import deepcopy
from pathlib import Path
import json
import subprocess

import pytest

from publications import ip_block_reference as blocks
from publications import tiny_reference
from publications.build_datasheet import CONFIG, collect_data, read_json
from publications.diagram_coverage import inventory

ROOT = Path(__file__).resolve().parents[1]


@pytest.fixture(scope="module")
def books():
    return {
        "tiny": tiny_reference.collect(
            tiny_reference.read(ROOT / tiny_reference.BOOK / "tiny.json")
        ),
        "mini": collect_data(read_json(CONFIG)),
    }


def test_complete_product_inventory_keeps_65_primary_views_and_seven_legacy_systems(books):
    for product, count in [("tiny", 23), ("mini", 42)]:
        data = books[product]
        views = blocks.records(data)
        primary = {key: r for key, r in views.items() if "parent_id" not in r}
        assert len(primary) == count
        circuits = (
            data["illustrations"]["circuits"]
            if product == "tiny"
            else data["system_reference"]["illustrations"]["circuits"]
        )
        assert len([r for r in circuits.values() if r.get("renderer") != "cetz"]) == (
            3 if product == "tiny" else 4
        )
        assert all(
            r["product"] == product and r["block_diagram"]["style"] == blocks.STYLE
            for r in views.values()
        )
        assert all(r.get("parent_id", key) in primary for key, r in views.items())
        assert all(r["scene"]["height"] <= 200 for r in views.values())
    assert len(inventory(books["mini"]["system_reference"]["illustrations"])) > 142


def test_every_drawn_unit_line_and_label_passes_geometric_checks(books):
    metrics = blocks.font_advances(
        ROOT / "publications/media/fonts/inter/Inter-VariableFont_opsz,wght.ttf"
    )
    for data in books.values():
        for identifier, view in blocks.records(data).items():
            assert not blocks.geometry_issues(view["scene"], metrics), identifier
            for wire in view["scene"]["wires"]:
                assert wire.get("label_mode") in {None, "endpoint", "interface", "source", "legend"}
                assert wire["label"]


def test_system_circuit_fact_records_are_retained_without_restyling(books):
    for product, path in [
        ("tiny", "publications/datasheets/tiny/diagram-circuits.json"),
        ("mini", "publications/datasheets/diagram-circuits.json"),
    ]:
        original = json.loads(
            subprocess.check_output(
                ["git", "show", "4315f7d7:" + path], cwd=ROOT, text=True, encoding="utf-8"
            )
        )
        current = json.loads((ROOT / path).read_text(encoding="utf-8"))
        for name, record in original.items():
            if name.startswith("system-"):
                assert current[name] == record
                assert "block_diagram" not in current[name]


@pytest.mark.parametrize(
    "change",
    [
        "missing-node",
        "duplicate-node",
        "outside-owned",
        "wrong-product",
        "unknown-symbol",
        "wrong-clock-direction",
        "wrong-clock-scope",
        "invalid-interface-width",
        "duplicate-interface",
        "unknown-member",
        "changed-member-port",
        "changed-member-parameter",
        "wrapper-escape",
    ],
)
def test_invalid_source_or_boundary_cannot_enter_the_publication(books, change):
    c = deepcopy(books["tiny"]["illustrations"]["circuits"]["spi"])
    c.pop("scene", None)
    c.pop("details", None)
    v = c["block_diagram"]
    if change == "missing-node":
        v["rows"][0].pop()
    elif change == "duplicate-node":
        v["rows"][1].append(v["rows"][0][0])
    elif change == "outside-owned":
        v["rows"][0].remove("reg")
        v["external"].append("reg")
    elif change == "wrong-product":
        v["product"] = "mini"
    elif change == "unknown-symbol":
        v["shapes"] = {"reg": "unreviewed-shape"}
    elif change == "wrong-clock-direction":
        v["ports"][0]["direction"] = "output"
    elif change == "wrong-clock-scope":
        v["ports"][0]["file"] = "rtl/ip/serial/apb4_uart.sv"
    elif change == "invalid-interface-width":
        v["interfaces"][0]["width"] = 64
    elif change == "duplicate-interface":
        v["interfaces"].append(deepcopy(v["interfaces"][0]))
    elif change == "unknown-member":
        v["details"][0]["members"].append("u_fictitious_unit")
    elif change in {"changed-member-port", "changed-member-parameter"}:
        unit = next(u for n in c["nodes"] for u in n.get("units", []))
        if change == "changed-member-port":
            unit["ports"][next(iter(unit["ports"]))] = "unrelated_signal"
        else:
            unit["parameters_raw"]["FictitiousParameter"] = "1"
    else:
        v["wrapper"] = ["../outside.sv"]
    with pytest.raises(ValueError):
        blocks.prepare(ROOT, "tiny", {"spi": c})


@pytest.mark.parametrize(
    "change",
    ["canvas", "outside-box", "overwide-text", "diagonal", "wire-through-node", "label-on-wire"],
)
def test_geometry_rejects_unreadable_or_inconsistent_drawings(books, change):
    scene = deepcopy(books["tiny"]["illustrations"]["circuits"]["spi"]["scene"])
    metrics = blocks.font_advances(
        ROOT / "publications/media/fonts/inter/Inter-VariableFont_opsz,wght.ttf"
    )
    if change == "canvas":
        scene["width"] = 190
    elif change == "outside-box":
        scene["nodes"][0]["x"] = -2
    elif change == "overwide-text":
        scene["nodes"][0]["lines"] = ["M" * 200]
    elif change == "diagonal":
        scene["wires"][0]["points"] = [[20, 20], [30, 30]]
    elif change == "wire-through-node":
        w = scene["wires"][0]
        node = next(
            n
            for n in scene["nodes"]
            if n["id"] not in {w["from_node"], w["to_node"]} and n["role"] != "bus"
        )
        y = node["y"] + node["h"] / 2
        w["points"] = [[node["x"] - 3, y], [node["x"] + node["w"] + 3, y]]
    else:
        a, b = scene["wires"][0]["points"][:2]
        scene["labels"].append(
            dict(text="BAD", x=min(a[0], b[0]), y=min(a[1], b[1]), w=12, h=5, edge=0)
        )
    assert blocks.geometry_issues(scene, metrics)


def test_reference_hardware_is_not_transferred_to_retro_diagrams(books):
    mini = books["mini"]["system_reference"]["illustrations"]["circuits"]
    assert not any(
        u["module"] == "tc_pll" for n in mini["rcu"]["nodes"] for u in n.get("units", [])
    )
    assert not any(
        word in json.dumps(mini["ga2d"]["block_diagram"]).lower()
        for word in ["rasterizer", "texture map", "fragment shader"]
    )
    # Private DMA and the APU stream router are owned logic, not external devices.
    assert "memory" not in mini["sdio0"]["block_diagram"]["external"]
    assert "stream" not in mini["apu"]["block_diagram"]["external"]
    tiny = books["tiny"]["illustrations"]["circuits"]
    pll = next(
        u for n in tiny["rcu"]["nodes"] for u in n.get("units", []) if u["module"] == "tc_pll"
    )
    assert "HAVE_PLL" in pll["condition"]


def test_junction_dots_require_the_same_actual_source_port():
    wires = [
        dict(index=0, source_key="a.out:net", points=[[0, 0], [4, 0], [4, 4]]),
        dict(index=1, source_key="b.out:other", points=[[0, 2], [6, 2]]),
    ]
    assert blocks.junctions(wires) == []
    wires[1].update(source_key="a.out:net", points=[[0, 0], [4, 0], [8, 0]])
    assert blocks.junctions(wires) == [[4, 0]]


def test_font_metrics_and_wrapping_preserve_literal_spelling():
    metrics = blocks.font_advances(
        ROOT / "publications/media/fonts/inter/Inter-VariableFont_opsz,wght.ttf"
    )
    assert blocks.text_width("MMMM", metrics) > blocks.text_width("iiii", metrics)
    lines = blocks.wrap("resource_reset_n_i", 18, metrics)
    assert "".join(lines) == "resource_reset_n_i"
    assert max(blocks.text_width(line, metrics) for line in lines) <= 18


def test_verification_only_modules_are_never_drawn_as_hardware(books):
    for data in books.values():
        for view in blocks.records(data).values():
            for node in view["nodes"]:
                assert "formal_props" not in node["title"]
                assert all(
                    not any(word in u["module"] for word in ("formal", "sva", "assert"))
                    for u in node.get("units", [])
                )
            if "parent_id" in view:
                connected = {
                    edge[key].split(".")[0] for edge in view["edges"] for key in ("from", "to")
                }
                assert {n["id"] for n in view["nodes"]} <= connected


@pytest.mark.parametrize("mutation", ["direction", "omit"])
def test_stream_boundaries_reject_wrong_direction_or_omission(books, mutation):
    c = deepcopy(books["mini"]["system_reference"]["illustrations"]["circuits"]["apu"])
    interface = next(i for i in c["block_diagram"]["interfaces"] if i.get("port") == "dma_tx_axis")
    if mutation == "direction":
        interface["direction"] = "output"
    else:
        c["block_diagram"]["interfaces"].remove(interface)
    with pytest.raises(ValueError):
        blocks.prepare(ROOT, "mini", {"apu": c})


def test_clock_boundary_omission_and_overlapping_bus_labels_are_rejected(books):
    c = deepcopy(books["tiny"]["illustrations"]["circuits"]["spi"])
    c["block_diagram"]["ports"].pop()
    with pytest.raises(ValueError, match="boundary is incomplete"):
        blocks.prepare(ROOT, "tiny", {"spi": c})
    metrics = blocks.font_advances(
        ROOT / "publications/media/fonts/inter/Inter-VariableFont_opsz,wght.ttf"
    )
    scene = deepcopy(books["tiny"]["illustrations"]["circuits"]["spi"]["scene"])
    scene["interfaces"][0]["y"] = scene["ports"][0]["y"]
    assert blocks.geometry_issues(scene, metrics)


def test_source_and_geometry_audits_are_checked_against_fresh_data(books, tmp_path):
    data = books["tiny"]
    rows = [
        dict(kind="tiny-diagram", package="cetz", id="circuit-" + key, page=i + 1)
        for i, key in enumerate(blocks.records(data))
    ]
    blocks.export_audits(ROOT, tmp_path, data, rows)
    blocks.verify_audit(ROOT, tmp_path, data)
    path = tmp_path / "ip-block-sources.json"
    audit = json.loads(path.read_text())
    audit["spi"]["interfaces"][0]["width"] = 64
    path.write_text(json.dumps(audit))
    with pytest.raises(ValueError, match="differs from current source"):
        blocks.verify_audit(ROOT, tmp_path, data)


def test_selected_xpi_bus_width_never_inherits_the_byte_path_width(books):
    for product in ["tiny", "mini"]:
        data = books[product]
        circuits = data.get(
            "illustrations", data.get("system_reference", {}).get("illustrations", {})
        )["circuits"]
        c = deepcopy(circuits["xpi"])
        interface = next(i for i in c["block_diagram"]["interfaces"] if i["protocol"] == "AXI4")
        assert interface["width"] == 32
        interface["width"] = 64
        with pytest.raises(ValueError, match="selected interface instance"):
            blocks.prepare(ROOT, product, {"xpi": c})


def test_stale_standalone_views_cannot_silently_ship(books, tmp_path):
    (tmp_path / "ip-blocks").mkdir()
    (tmp_path / "ip-blocks/obsolete.svg").write_text("<svg/>")
    with pytest.raises(ValueError, match="stale views"):
        blocks.export_vectors(ROOT, tmp_path, books["tiny"], "not-a-compiler", [])


def test_complex_views_use_reviewed_functional_groups(books):
    mini = books["mini"]["system_reference"]["illustrations"]["circuits"]
    rcu = mini["rcu"]
    assert {d["detail_id"] for d in rcu["details"]} == {
        "rcu-detail-clock-tree",
        "rcu-detail-derived-clocks",
        "rcu-detail-clock-monitoring",
        "rcu-detail-clock-control",
        "rcu-detail-reset-control",
    }
    units = {u["id"] for n in rcu["nodes"] for u in n.get("units", [])}
    assert {"u_hp_div2", "u_hp_div4", "u_pclk_divider", "u_mem_clk_div2", "u_lp_clk_div4"} <= units
    specs = rcu["block_diagram"]["details"]
    members = [key for d in specs for key in d["members"]]
    assert len(members) == len(set(members)) and set(members) == units
    assert len(mini["sdram"]["details"]) == len(mini["usb2"]["details"]) == 1
    assert not any("-part-" in key for data in books.values() for key in blocks.records(data))


def test_non_ip_sources_do_not_acquire_the_ip_renderer_dependency():
    assert blocks.trace_paths({}) == set()
    assert blocks.trace_paths({"system-fabric": {"nodes": [], "edges": []}}) == set()


def test_unrelated_wires_cannot_merge_or_form_a_false_junction():
    a = dict(index=0, kind="control", source_key="a.signal", points=[[0, 5], [10, 5]])
    cross = dict(index=1, kind="control", source_key="b.signal", points=[[5, 0], [5, 10]])
    assert blocks.wire_collisions([a, cross]) == []
    shared = dict(cross, points=[[5, 5], [12, 5]])
    assert blocks.wire_collisions([a, shared])
    assert blocks.wire_collisions([a, dict(cross, points=[[5, 5], [5, 10]])])
    assert blocks.wire_collisions([a, dict(shared, source_key="a.signal")]) == []
    assert blocks.wire_collisions(
        [dict(a, kind="data"), dict(shared, kind="data", points=[[0, 7], [10, 7]])]
    )


def test_mini_sram_uses_the_live_hp_target_not_the_retired_lp_interface(books):
    c = deepcopy(books["mini"]["system_reference"]["illustrations"]["circuits"]["sram"])
    interface = next(i for i in c["block_diagram"]["interfaces"] if i["protocol"] == "AXI4")
    assert interface["width"] == 64
    assert interface["width_binding"]["instance"] == "u_data_sram_axi4_if"
    assert ".IdWidth(7)" in str(interface["width_binding"]["connections"])
    interface["width"] = 32
    with pytest.raises(ValueError, match="selected interface instance"):
        blocks.prepare(ROOT, "mini", {"sram": c})


def test_ip_notes_do_not_retain_the_legacy_dashed_control_convention(books):
    for data in books.values():
        for view in blocks.records(data).values():
            assert "dashed links are control" not in view["note"].lower()
