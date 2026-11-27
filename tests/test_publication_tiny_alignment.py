"""Tiny hierarchy and source-bound figure contracts for the approved Mini alignment."""
from __future__ import annotations

import copy
import json
from pathlib import Path

import pytest

from publications import tiny_reference as tiny
from publications.ip_block_reference import records as ip_views
from publications.tiny_clock_tree import prepare as prepare_clock_tree
from publications.tiny_diagram_reference import coverage, functional_routes, validate_circuit, validate_fields, validate_rendered
from publications.tiny_fabric_reference import prepare as prepare_fabric
from publications.tiny_publication_reference import diagnostics, smartwatch_reference, validate_navigation

ROOT = Path(__file__).resolve().parents[1]
BOOK = ROOT / tiny.BOOK


@pytest.fixture(scope="module")
def data():
    return tiny.collect(tiny.read(BOOK / "tiny.json"))


def test_smartwatch_reference_exposes_separate_clock_and_chip_selects(data):
    watch = data["smartwatch"]
    links = watch["links"]
    assert (watch["hardware_isa"], watch["sram_kib"], watch["dma_channels"]) == ("RV32IMC", 128, 8)
    assert links["power"]["clock"] == "24 MHz"
    assert (links["memory"]["boot_cs"], links["memory"]["ram_cs"]) == ("NSS0", "NSS1")
    gpio = watch["profiles"]["watch"]
    assert gpio[29] == dict(pin=29, mode="ALT0", signal="NSS1", direction="out")
    assert gpio[30] == dict(pin=30, mode="GPIO", signal="D/C", direction="out")
    assert [gpio[i]["direction"] for i in range(12, 18)] == ["out", "out", "out", "in", "out", "in"]
    assert [gpio[i]["signal"] for i in range(14, 18)] == ["DACDAT", "ADCDAT", "MCLK", "AUDIO.CLKIN"]


def test_smartwatch_uses_disjoint_radio_storage_and_camera_routes(data):
    watch = data["smartwatch"]
    main, camera = (watch["profiles"][name] for name in ("watch", "camera"))
    assert [pin["pin"] for pin in main] == [pin["pin"] for pin in camera] == list(range(32))
    assert [i for i in range(32) if main[i] != camera[i]] == list(range(12, 24))
    assert [(p["mode"], p["direction"]) for p in camera[12:24]] == [("ALT1", "in")] * 11 + [("ALT1", "out")]
    assert [p["signal"] for p in camera[20:24]] == ["PCLK", "HREF", "VSYNC", "CAM_XCLK"]
    assert [p["signal"] for p in main[:8]] == ["CLK", "CMD", "DAT0", "DAT1", "DAT2", "DAT3", "SD_CD_N", "SD_PWR_EN"]
    assert [p["direction"] for p in main[:8]] == ["out", *(["I/O"] * 5), "in", "out"]
    assert [(p["signal"], p["direction"]) for p in main[8:10]] == [("TX", "out"), ("RX", "in")]
    assert watch["links"]["serial"]["options"] == {"ble": "BLE", "wifi": "Wi-Fi", "service": "USB-UART"}
    assert watch["links"]["serial"]["selection"] == "Fit one"


@pytest.mark.parametrize(("pin", "mode", "field", "wrong"), [
    (28, "alt1", "do", "s_clkout"),
    (10, "alt0", "inputs", []),
    (17, "alt0", "oe", "1'b1"),
    (4, "alt0", "inputs", []),
    (20, "alt1", "inputs", ["u_dvp_if.href_i"]),
    (23, "alt1", "oe", "1'b0"),
])
def test_smartwatch_reference_rejects_route_or_direction_drift(data, pin, mode, field, wrong):
    gpio = copy.deepcopy(data["gpio"])
    next(row for row in gpio if row["pin"] == pin)[mode][field] = wrong
    with pytest.raises(ValueError, match=f"GPIO{pin} {mode.upper()} does not route"):
        smartwatch_reference(gpio, data["facts"])


def test_reviewed_peripheral_hierarchy_and_inventory(data):
    index = data["chapter_index"]
    assert [r["id"] for r in index] == [
        "xpi", "sdio", "sram", "gpio", "dma", "timer", "rtc", "wdg", "pwm", "uart0",
        "i2c", "spi", "piolite", "ws2812", "archinfo", "sysctrl", "rcu", "clint", "i2s", "dvp", "ppalite", "crypto", "crc", "rng"]
    assert {r["id"] for r in index if r["depth"] == 5} == {"xpi", "sdio", "sram", "uart0"}
    assert {r["id"] for r in index if r["depth"] == 3} == {"gpio", "dma"}
    assert len(data["register_index"]) == 1329
    assert sum(len(r["registers"]) for r in data["registers"].values()) == 682
    assert "#contents(depth:5)" in (BOOK / "datasheet.typ").read_text(encoding="utf-8")


@pytest.mark.parametrize("mutation", ["omit", "reorder", "flatten", "unknown"])
def test_navigation_rejects_unreviewed_structure(mutation):
    contract = tiny.read(BOOK / "navigation-contract.json")
    rows = [{**r, "outlined": True, "label": "none" if not r["anchor"] else "<" + r["anchor"] + ">"}
            for r in contract["entries"]]
    validate_navigation(contract, rows)
    if mutation == "omit":
        rows.pop()
    elif mutation == "reorder":
        rows[0], rows[1] = rows[1], rows[0]
    elif mutation == "flatten":
        next(r for r in rows if r["label"] == "<xpi>")["level"] = 3
    else:
        rows.append(dict(level=3, title="Unsupported extra IP", label="<piolite>", outlined=True))
    with pytest.raises(ValueError, match="navigation differs"):
        validate_navigation(contract, rows)


def test_all_current_ips_have_source_bound_circuits(data):
    figures = data["illustrations"]
    assert set(figures["circuits"]) == {r["id"] for r in data["catalog"]} | {
        "system-fabric", "system-clocks", "system-media"}
    assert not any(p.startswith("rtl/mini/") for p in figures["source_paths"])
    assert "docs/ip/piolite-verification.md" in data["source_paths"]
    assert "scripts/program_xpi_flash.py" in data["source_paths"]
    assert all(e["bindings"] for c in figures["circuits"].values() for e in c["edges"])


def test_tiny_clock_tree_retains_separate_clock_paths_and_system_ownership(data):
    figures = data["illustrations"]
    clock = figures["circuits"]["system-clocks"]
    links = {(e["from"], e["to"], e["kind"]) for e in clock["edges"]}
    assert {
        ("ref.out", "sys.safe", "clock"), ("xin.out", "fast.xin", "clock"),
        ("pll.out", "fast.pll", "clock"), ("fast.out", "sys.fast", "clock"),
        ("sys.out", "cpu_gate.in", "clock"), ("sys.out", "sys_leaves.in", "clock"),
        ("div2.out", "mem.div2", "clock"), ("sys.out", "mem.div1", "clock"),
        ("div2.out", "pclk_first.div2", "clock"), ("sys.out", "pclk_first.div1", "clock"),
        ("pclk_first.out", "pclk.div1_2", "clock"), ("div4.out", "pclk.div4", "clock"),
        ("pclk.out", "pclk_gate.in", "clock"), ("audio.out", "i2s.in", "clock"),
        ("pixel.out", "dvp.in", "clock"), ("tck.out", "dtm.in", "clock"),
        ("trst.out", "jtag_reset.in", "reset"),
    } <= links
    assert {n["source_port"] for n in clock["nodes"] if n["shape"] == "tap"} == {
        "ref.out", "sys.out", "mem.out", "pclk.out"}
    assert {d["name"] for d in data["clocks"]} == {n["domain"] for n in clock["nodes"] if "domain" in n}
    assert {"point": (141, 39), "kind": "clock"} in clock["clock_tree"]["junctions"]
    assert {"id": "circuit-system-clocks", "source_id": "system-clocks", "package": "cetz"} in figures["inventory"]
    assert "system-clocks" not in ip_views(data)


def test_tiny_clock_tree_rejects_diagonal_shaft(data):
    clock = copy.deepcopy(data["illustrations"]["circuits"]["system-clocks"])
    next(e for e in clock["edges"] if e["to"] == "ref.in")["via"][0][1] += 1
    with pytest.raises(ValueError, match="non-orthogonal"):
        prepare_clock_tree(clock, data["clocks"])


def test_tiny_fabric_plate_covers_actual_owner_routes_and_targets(data):
    illustrations = data["illustrations"]
    circuit = illustrations["circuits"]["system-fabric"]
    plate = circuit["fabric_matrix"]
    assert [(c["owner"], c["name"]) for c in plate["columns"]] == [(0, "cpu_slow"), (1, "central_dma"), (2, "sdio")]
    assert (plate["data_width"], plate["id_width"], plate["sram_kib"], plate["group_kib"]) == (32, 1, 128, 32)
    assert len(plate["rows"]) == 11
    assert sorted(n for r in plate["rows"] for n in r["targets"]) == list(range(31))
    assert {r["port"]: len(r["members"]) for r in plate["rows"] if "members" in r} == {
        "apb-system": 3, "apb-aon": 2, "apb-peripheral": 18, "apb-memory": 1,
    }
    assert plate["crosspoints"] == [[c["x"], r["y"]] for r in plate["rows"] for c in plate["columns"]]
    assert {(e["from"], e["to"]) for e in circuit["edges"] if e.get("local")} == {
        ("i-decode.local", "sram.i"), ("d-decode.local", "sram.d"),
    }
    edges = {(e["from"], e["to"]) for e in circuit["edges"]}
    assert {(f"fabric.b{n}", f"sram.b{n}") for n in range(4)} <= edges
    assert {("xpi-cdc.out", "xpi.memory"), ("apb-memory.apb", "xpi.registers")} <= edges
    assert {"id": "circuit-system-fabric", "source_id": "system-fabric", "package": "cetz"} in illustrations["inventory"]
    assert "system-fabric" not in ip_views(data)


def test_tiny_fabric_plate_rejects_misaligned_local_route(data):
    circuit = copy.deepcopy(data["illustrations"]["circuits"]["system-fabric"])
    topology = tiny.read(ROOT / "rtl/tiny/integration/soc_topology.json")
    domains = tiny.read(ROOT / "rtl/tiny/integration/clock_reset_domains.json")["generated_apb_crossings"]
    apb_domains = {name: d for d, names in domains["destinations"].items() for name in names}
    apb_domains.update(dict.fromkeys(domains["native_system"] + domains["same_clock_isolation"], "system"))
    next(e for e in circuit["edges"] if e["from"] == "i-decode.local")["via"][0][1] += 1
    with pytest.raises(ValueError, match="non-orthogonal"):
        prepare_fabric(ROOT, circuit, topology, apb_domains)


@pytest.mark.parametrize(("mutation", "reason"), [
    ("local-through-fabric", "path differs: cpu-local"),
    ("spi-domain", "APB route or domain differs: spi"),
    ("dma-crossing", "crossing differs: xpi_mem_axi"),
])
def test_functional_architecture_rejects_incorrect_topology(data, mutation, reason):
    clocks = tiny.read(ROOT / "rtl/tiny/integration/clock_reset_domains.json")
    branches = clocks["generated_apb_crossings"]
    domains = {target: domain for domain, targets in branches["destinations"].items() for target in targets}
    domains.update(dict.fromkeys(branches["native_system"] + branches["same_clock_isolation"], "system"))
    diagram = copy.deepcopy(data["illustrations"]["functional"])
    edges = {edge["id"]: edge for edge in diagram["edges"]}
    if mutation == "local-through-fabric":
        edges["cpu-local"]["to"] = "fabric"
    elif mutation == "spi-domain":
        next(n for n in diagram["nodes"] if n["id"] == "spi")["domain"] = "system"
    else:
        edges["dma-axi"]["crossing"] = "xpi_mem_axi"
    with pytest.raises(ValueError, match=reason):
        functional_routes(diagram, {r["id"] for r in data["catalog"]}, data["facts"]["fabric"], clocks, domains)


def test_tcd_has_one_primary_drawing_and_a_shared_appendix_reference(data):
    rows = coverage(data["illustrations"], tiny.read(BOOK / "navigation-contract.json"))
    tcd = [(row["key"], item["shared"]) for row in rows
           for item in row["categories"]["bytefield"]["diagrams"] if item["id"] == "format-dma-tcd"]
    assert tcd == [("dma", False), ("tiny-dma-format", True)]


@pytest.mark.parametrize("mutation", ["direction", "width", "binding", "selection"])
def test_circuit_cannot_disagree_with_its_source(data, mutation):
    circuit = copy.deepcopy(data["illustrations"]["circuits"]["sram"])
    edge = circuit["edges"][1]
    node_id, port_id = edge["from"].split(".")
    port = next(p for n in circuit["nodes"] if n["id"] == node_id for p in n["ports"] if p["id"] == port_id)
    if mutation == "direction":
        port["direction"] = "in"
    elif mutation == "width":
        port["width"] = 64
    elif mutation == "binding":
        edge["bindings"][0]["text"] = "missing_reviewed_connection"
    else:
        edge["signals"][0]["select"] = "[99]"
    with pytest.raises(ValueError):
        validate_circuit(ROOT, circuit)


@pytest.mark.parametrize("mutation", ["omit", "repeat", "unknown"])
def test_missing_or_duplicate_figure_cannot_pass(data, mutation):
    rows = [dict(kind="tiny-diagram", **r) for r in [*data["illustrations"]["inventory"], *data["illustrations"]["native_inventory"]]]
    validate_rendered(data["illustrations"], rows)
    if mutation == "omit":
        rows.pop()
    elif mutation == "repeat":
        rows.append(rows[0])
    else:
        rows.append(dict(kind="tiny-diagram", package="circuiteria", id="unreviewed"))
    with pytest.raises(ValueError, match="omitted, duplicated or unknown"):
        validate_rendered(data["illustrations"], rows)


def test_binary_fields_are_complete_and_storage_uses_tiny_geometry(data):
    figures = data["illustrations"]
    for record in figures["layouts"].values():
        for row in record.get("rows", [record]):
            validate_fields(row["fields"], row["bits"])
    bad = copy.deepcopy(figures["layouts"]["dma-tcd"])
    bad["fields"].pop()
    with pytest.raises(ValueError, match="omits"):
        validate_fields(bad["fields"], bad["bits"])
    stores = figures["storage"]
    assert [(r["depth"], r["bits"]) for r in stores["spi-fifos"]["stores"]] == [(8, 32), (8, 32)]
    assert stores["dma-channel-fifos"]["stores"][0]["depth"] == 32
    assert [r["bytes"] for r in stores["tiny-sram-groups"]["ranges"]] == [32768] * 4
    assert stores["tiny-linker"]["profile"] == "configs/ci/ics55-tiny.mk"
    assert sum(r["storage_bytes"] for r in stores["tiny-buffer-budgets"]["budgets"][:1]) == 153600


def test_diagnostic_namespaces_are_explicit_and_extracted(data):
    result = diagnostics(ROOT, data["registers"])
    assert [r["value"] for r in result["sdk"]] == list(range(0, -9, -1))
    assert [r["value"] for r in result["spi"]] == list(range(6))
    assert {r["family"] for r in result["registers"]} == {"sysctrl", "rcu", "dma", "spi", "sdio", "dvp"}


def test_old_stable_anchors_remain_and_product_paths_are_separate():
    contract = json.loads((BOOK / "navigation-contract.json").read_text(encoding="utf-8"))
    anchors = {r["anchor"] for r in contract["entries"]}
    assert {"tiny-core", "tiny-clock", "tiny-bus", "tiny-addresses", "tiny-irq", "tiny-boot",
            "tiny-diagnostics", "tiny-evidence", "tiny-dma-format", "tiny-migration", "publication-provenance"} <= anchors
    prose = "\n".join(p.read_text(encoding="utf-8") for p in (BOOK / "sections").glob("*.typ"))
    assert "<uart1>" in prose
    assert "0x10011000" in prose
    assert "== Linux and Driver Status" not in prose
    assert "= Appendix: MPW Compatibility" not in prose
