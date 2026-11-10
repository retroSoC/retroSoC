"""Tiny hierarchy and source-bound figure contracts for the approved Mini alignment."""
from __future__ import annotations

import copy
import json
from pathlib import Path

import pytest

from publications import tiny_reference as tiny
from publications.tiny_diagram_reference import coverage, functional_routes, validate_circuit, validate_fields, validate_rendered
from publications.tiny_publication_reference import diagnostics, validate_navigation

ROOT = Path(__file__).resolve().parents[1]
BOOK = ROOT / tiny.BOOK


@pytest.fixture(scope="module")
def data():
    return tiny.collect(tiny.read(BOOK / "tiny.json"))


def test_reviewed_peripheral_hierarchy_and_inventory(data):
    index = data["chapter_index"]
    assert [r["id"] for r in index] == [
        "xpi", "sdio", "sram", "gpio", "dma", "timer", "rtc", "wdg", "pwm", "uart0",
        "i2c", "spi", "ws2812", "archinfo", "sysctrl", "rcu", "clint", "i2s", "dvp", "ppalite", "crypto", "crc", "rng"]
    assert {r["id"] for r in index if r["depth"] == 5} == {"xpi", "sdio", "sram", "uart0"}
    assert {r["id"] for r in index if r["depth"] == 3} == {"gpio", "dma"}
    assert len(data["register_index"]) == 1210
    assert sum(len(r["registers"]) for r in data["registers"].values()) == 626
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
