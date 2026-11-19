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


def test_complete_product_inventory_keeps_66_primary_views_and_seven_legacy_systems(books):
    for product, count in [("tiny", 24), ("mini", 42)]:
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


def test_tiny_style_matches_collected_primary_count(books):
    views = blocks.records(books["tiny"])
    primary = {key: r for key, r in views.items() if "parent_id" not in r}
    detail_count = len(views) - len(primary)
    mini_primary = sum("parent_id" not in r for r in blocks.records(books["mini"]).values())
    style = (ROOT / "publications/datasheets/tiny/style.md").read_text(encoding="utf-8")
    standard = (ROOT / "publications/ip-block-diagrams.md").read_text(encoding="utf-8")
    revision = (ROOT / "publications/datasheets/tiny/sections/document-control.typ").read_text(
        encoding="utf-8"
    )
    assert f"all {len(primary)}\nTiny primary figures" in style
    assert f"Tiny's {len(primary)} and Mini's {mini_primary} primary IP figures" in standard
    assert f"{len(primary)} main and {detail_count} detail views" in revision


def test_rm0486_review_covers_collected_parents(books):
    from publications import review_ip_blocks as rm0486_review

    for product, data in books.items():
        views = blocks.records(data)
        parents = {r.get("parent_id", key) for key, r in views.items()}
        assert parents <= set(rm0486_review.LOOKUP), product
    refs, relation, principle = rm0486_review.LOOKUP["piolite"]
    assert refs == ((66, 784), (93, 941))
    assert relation == "结构类比"
    assert "不推断 RM0486 具有等价状态机" in principle


def test_every_drawn_unit_line_and_label_passes_geometric_checks(books):
    metrics = blocks.font_advances(
        ROOT / "publications/media/fonts/inter/Inter-VariableFont_opsz,wght.ttf"
    )
    for data in books.values():
        for identifier, view in blocks.records(data).items():
            assert not blocks.geometry_issues(view["scene"], metrics), identifier
            for wire in view["scene"]["wires"]:
                assert wire.get("label_mode") == "direct"
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
    # The source inventory includes both generate branches. Only the selected
    # functional projection is drawn in the IHP130 / HAVE_PLL=NO book.
    rcu = mini["rcu"]
    drawn = {
        name
        for node in rcu["block_diagram"]["functional"]["nodes"]
        for name in [*node.get("instance_refs", []), node.get("instance_ref")]
        if name is not None
    }
    assert not any(
        u["module"] == "tc_pll" and u["id"] in drawn
        for n in rcu["nodes"]
        for u in n.get("units", [])
    )
    assert "no PLL" in json.dumps(rcu["block_diagram"]["functional"])
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
    pins = blocks.wrap("mem_rst_n_o", 19, metrics)
    assert "".join(pins) == "mem_rst_n_o"
    assert all(line != "o" for line in pins)


def test_verification_only_modules_are_never_drawn_as_hardware(books):
    for data in books.values():
        for view in blocks.records(data).values():
            for node in view["nodes"]:
                assert "formal_props" not in node["title"]
                assert all(
                    not any(word in u["module"] for word in ("formal", "sva", "assert", "xchecker"))
                    for u in node.get("units", [])
                )
            if view["block_diagram"].get("scope") == "local-routes":
                projection = view["block_diagram"]["functional"]
                linked = {wire[end] for wire in view["scene"]["wires"]
                          for end in ("from_node", "to_node")}
                assert linked == {node["id"] for node in projection["nodes"]}
                assert all(edge.get("source") for edge in projection["edges"])
            elif "parent_id" in view:
                connected = {
                    edge[key].split(".")[0] for edge in view["edges"] for key in ("from", "to")
                }
                assert {n["id"] for n in view["nodes"]} <= connected


def test_applied_dvp_configuration_is_a_latch_not_a_verification_checker(books):
    for data in books.values():
        circuits = data.get(
            "illustrations", data.get("system_reference", {}).get("illustrations", {})
        )["circuits"]
        graph = circuits["dvp"]["block_diagram"]["functional"]
        node = next(n for n in graph["nodes"] if n["id"] == "applied-config-latch")
        assert node["ref"] == "applied"
        assert "128" in node["title"]
        assert not blocks.source_members(
            ROOT, "rtl/managed/clusterip/common/rtl/utils/register.sv", ("xchecker",), scope="dffer"
        )


def test_payload_cannot_move_to_an_unrelated_function_in_the_same_ip(books):
    c = deepcopy(books["tiny"]["illustrations"]["circuits"]["gpio"])
    graph = c["block_diagram"]["functional"]
    edge = next(e for e in graph["edges"] if e.get("parent_edge") == 1)
    assert edge["to"] == "core-pads"
    edge["to"] = "core-rx"
    with pytest.raises(ValueError, match="functional port"):
        blocks.validate_sources(ROOT, "tiny", {"gpio": c})


@pytest.mark.parametrize(
    "product,family,signal",
    [
        ("tiny", "gpio", "gpio.irq_o"),
        ("mini", "gpio", "gpio.irq_o"),
        ("tiny", "i2s", "i2s.irq_o"),
        ("mini", "i2s", "i2s.irq_o"),
        ("mini", "uart1", "uart.irq_o"),
    ],
)
def test_interface_irq_pass_throughs_remain_explicit(books, product, family, signal):
    data = books[product]
    circuits = data.get("illustrations", data.get("system_reference", {}).get("illustrations", {}))[
        "circuits"
    ]
    graph = circuits[family]["block_diagram"]["functional"]
    edge = next(e for e in graph["edges"] if e["kind"] == "irq" and e["label"] == signal)
    assert edge["source"]["module"] == "apb4_" + ("uart" if family == "uart1" else family)
    assert any("s_irq" in binding for binding in edge["source"]["bindings"])
    terminal = next(n for n in graph["nodes"] if n["id"] == edge["to"])
    assert any(signal in binding for binding in terminal["logic_source"]["bindings"])


@pytest.mark.parametrize(
    "family,signal",
    [
        ("i2s", "clk_aud_i"),
        ("i2s", "rst_aud_n_i"),
        ("jpeg", "resource_reset_i"),
        ("ga2d", "resource_reset_i"),
    ],
)
def test_audio_and_resource_domains_cannot_drive_the_apb_register_bank(books, family, signal):
    c = deepcopy(books["mini"]["system_reference"]["illustrations"]["circuits"][family])
    graph = c["block_diagram"]["functional"]
    edge = next(e for e in graph["edges"] if e.get("boundary") and e["label"] == signal)
    assert edge["to"] != "reg-registers"
    edge["to"] = "reg-registers"
    with pytest.raises(ValueError, match="clock/reset targets"):
        blocks.validate_sources(ROOT, "mini", {family: c})


def test_resource_stop_expression_retains_its_reset_dependency(books):
    unit = next(
        u
        for u in blocks.source_members(ROOT, "rtl/ip/multimedia/apb4_ga2d.sv", ("ga2d_core",))
        if u["id"] == "u_ga2d_core"
    )
    assert (
        unit["ports_raw"]["resource_stop_i"]
        == "resource_quiesce_i||resource_reset_i||source_stop_i"
    )
    c = books["mini"]["system_reference"]["illustrations"]["circuits"]["ga2d"]
    blocks.validate_sources(ROOT, "mini", {"ga2d": c})


@pytest.mark.parametrize("signal", ["clk_i", "rst_n_i"])
def test_combinational_size_helper_cannot_receive_dma_clock_or_reset(books, signal):
    c = deepcopy(books["mini"]["system_reference"]["illustrations"]["circuits"]["ga2d"])
    graph = c["block_diagram"]["details"][0]["functional"]
    edge = next(e for e in graph["edges"] if e.get("boundary") and e["label"] == signal)
    assert edge["to"] == "planner-controller"
    edge["to"] = "u_addr_gen-stage"
    with pytest.raises(ValueError, match="clock/reset targets"):
        blocks.validate_sources(ROOT, "mini", {"ga2d": c})


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
    bus = next(n for n in scene["nodes"] if n["role"] == "bus")
    terminal = next(n for n in scene["nodes"] if n["role"] == "terminal")
    bus["x"], bus["y"] = terminal["x"], terminal["y"]
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
        "rcu-detail-internal-feedback",
    }
    units = {u["id"] for n in rcu["nodes"] for u in n.get("units", [])}
    assert {"u_hp_div2", "u_hp_div4", "u_pclk_divider", "u_mem_clk_div2", "u_lp_clk_div4"} <= units
    specs = rcu["block_diagram"]["details"]
    members = [key for d in specs for key in d["members"]]
    assert len(members) == len(set(members)) and set(members) <= units
    # Detail scopes remain disjoint; main-view expansion also exposes buffers,
    # timebase and CDC logic that are not separate adjacent detail figures.
    main = rcu["block_diagram"]["functional"]
    drawn = {
        name
        for node in main["nodes"]
        for name in [*node.get("instance_refs", []), node.get("instance_ref")]
        if name is not None
    }
    assert set(members) <= drawn
    assert {"u_clint_timebase", "u_ref24_clk_buf", "u_pclk_cfg_cdc"} <= drawn
    assert len(mini["sdram"]["details"]) == 2
    assert len(mini["usb2"]["details"]) == 1
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
            for legacy in ("dashed links are control", "outlined arrows carry", "wide arrows carry"):
                assert legacy not in view["note"].lower()


def test_technical_inventory_defers_fonts_without_losing_sources(books, monkeypatch):
    def unavailable_font(path):
        raise FileNotFoundError("publication font not installed")

    monkeypatch.setattr(blocks, "font_advances", unavailable_font)
    config = tiny_reference.read(ROOT / tiny_reference.BOOK / "tiny.json")
    data = tiny_reference.collect(config, check_snapshot=False, layout=False)
    assert data["source_paths"] == books["tiny"]["source_paths"]
    assert data["illustrations"]["layout_prepared"] is False
    with pytest.raises(FileNotFoundError, match="publication font not installed"):
        tiny_reference.collect(config)
    with pytest.raises(ValueError, match="complete IP layout"):
        tiny_reference.collect(config, layout=False)


def test_font_independent_validation_still_checks_selected_widths(books):
    c = deepcopy(books["tiny"]["illustrations"]["circuits"]["xpi"])
    interface = next(i for i in c["block_diagram"]["interfaces"] if i["protocol"] == "AXI4")
    interface["width"] = 64
    with pytest.raises(ValueError, match="selected interface instance"):
        blocks.validate_sources(ROOT, "tiny", {"xpi": c})
