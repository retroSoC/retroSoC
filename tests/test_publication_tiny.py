"""Tiny publication is parameter-bound, complete and isolated from Mini inputs."""
from __future__ import annotations

import copy
import json
from pathlib import Path
import shutil

import pytest

from publications import tiny_reference as tiny
from publications.register_reference import parse_definitions

ROOT = Path(__file__).resolve().parents[1]


@pytest.fixture(scope="module")
def data():
    return tiny.collect(tiny.read(ROOT / tiny.BOOK / "tiny.json"), check_snapshot=False)


def test_tiny_configuration_and_inventory_are_derived(data):
    assert (data["facts"]["hardware_isa"], data["facts"]["firmware_isa"]) == ("RV32IMC", "RV32IM")
    assert data["facts"]["sram"] == {"CapacityKiB": 128, "DataWidth": 32, "IdWidth": 1}
    assert data["facts"]["dma"]["NumChannels"] == 4
    assert data["facts"]["dma"]["RequestMask"] == 0x7F9
    assert data["facts"]["dma"]["EnableStreams"] == 0
    assert len(data["catalog"]) == 14 and len(data["regions"]) == 20 and len(data["pads"]) == 52
    assert len(data["interrupts"]) == 14 and len(data["gpio"]) == 32
    assert not any(p.startswith("rtl/mini/") for p in data["source_paths"])
    assert "mpw" not in {s["destination"].split("/")[-1] for s in data["managed_sources"]}


def test_tiny_collection_does_not_open_mini_files(monkeypatch):
    original = Path.read_text
    def read(path, *args, **kwargs):
        name = path.as_posix()
        if "/rtl/mini/" in name or ("/publications/datasheets/" in name and "/tiny/" not in name):
            raise AssertionError("Tiny opened a Mini product input: " + name)
        return original(path, *args, **kwargs)
    monkeypatch.setattr(Path, "read_text", read)
    tiny.collect(tiny.read(ROOT / tiny.BOOK / "tiny.json"), check_snapshot=False)


def test_common_register_default_remains_mini_compatible():
    paths = ["rtl/ip/serial/apb4_uart_define.svh"]
    assert parse_definitions(paths, {}) == parse_definitions(paths, {}, "rtl/mini/address_map/memory_map.json")
    _, constants = parse_definitions(paths, {}, tiny.MAP)
    assert "SOC_SYSCTRL_TEST_STATUS_OFFSET" in constants


@pytest.fixture
def source_tree(tmp_path):
    sources = [tiny.TOP, tiny.ARCHINFO, tiny.SYSCTRL, "rtl/ip/core/mgmt_core_wrapper.sv", "configs/ci/ihp130-tiny.mk",
               tiny.MAP, tiny.TOPOLOGY, (tiny.BOOK / "source-contract.json").as_posix()]
    for relative in sources:
        target = tmp_path / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(ROOT / relative, target)
    return tmp_path


@pytest.mark.parametrize("path,before,after", [
    (tiny.TOP, ".CapacityKiB(128)", ".CapacityKiB(32)"),
    (tiny.TOP, ".DataWidth  (32)", ".DataWidth  (64)"),
    (tiny.TOP, ".NumChannels  (4)", ".NumChannels  (8)"),
    (tiny.TOP, ".EnableStreams(1'b0)", ".EnableStreams(1'b1)"),
    (tiny.TOP, ".EnableAtomics    (1'b0)", ".EnableAtomics    (1'b1)"),
    ("configs/ci/ihp130-tiny.mk", "ISA               := RV32IM", "ISA               := RV32IMC"),
    (tiny.ARCHINFO, "32'h5449_4e59", "32'h4d49_4e49"),
    (tiny.SYSCTRL, "!s_test_q[31] && apb4.pwdata[31]", "s_test_q[31] && apb4.pwdata[31]"),
])
def test_changed_hardware_or_isa_cannot_retain_publication_claim(source_tree, path, before, after):
    file = source_tree / path
    text = file.read_text(encoding="utf-8")
    assert before in text
    file.write_text(text.replace(before, after, 1), encoding="utf-8")
    with pytest.raises(ValueError):
        tiny.facts(source_tree)


@pytest.mark.parametrize("change", ["irq_missing", "irq_number", "region_address", "region_missing"])
def test_missing_or_wrong_maps_fail(source_tree, change):
    path = source_tree / (tiny.TOPOLOGY if change.startswith("irq") else tiny.MAP)
    document = tiny.read(path)
    if change == "irq_missing":
        document["interrupts"].pop()
    elif change == "irq_number":
        document["interrupts"][-1]["core_bit"] = 27
    elif change == "region_address":
        next(r for r in document["regions"] if r["symbol"] == "SRAM")["base"] = "0x31000000"
    else:
        document["regions"].pop()
    path.write_text(json.dumps(document), encoding="utf-8")
    with pytest.raises(ValueError):
        tiny.validate_maps(source_tree, tiny.facts(source_tree))


def test_tiny_sysctrl_and_discovery_do_not_inherit_mini_controls(data):
    control = data["registers"]["sysctrl"]["registers"]
    assert {r["name"] for r in control} == tiny.SUPPORTED_SYSCTRL
    assert not any(r["name"] in {"HP_CTRL", "PLL_CFG", "DEBUG_SELECT"} for r in control)
    test = next(r for r in control if r["name"] == "TEST_STATUS")
    assert [(f["name"], f["lsb"], f["msb"]) for f in test["fields"] if f["name"] != "Reserved"] == [
        ("PASS", 0, 0), ("CODE", 8, 15), ("VALID", 31, 31)]
    info = data["registers"]["archinfo"]["registers"]
    assert next(r for r in info if r["name"] == "SOC_ID")["reset"] == "0x54494E59"
    assert next(r for r in info if r["name"] == "SRAM_BYTES")["reset"] == "0x00020000"
    assert data["registers"]["dma"]["groups"][1]["count"] == 4


def test_tcd_layout_is_complete_and_bounded(data):
    assert len(data["tcd"]) == 17
    assert sum(f["bytes"] for f in data["tcd"]) == 64
    assert data["tcd"][-1]["offset"] == 60


def test_local_capabilities_keep_fabric_and_encoding_restrictions(data):
    capability = next(r for r in data["registers"]["dma"]["registers"] if r["name"] == "CAPABILITY")
    assert capability["reset"] == "0x00200401"
    burst = next(f for f in capability["fields"] if f["name"] == "MAX_BURST_FIELD")
    assert (burst["lsb"], burst["msb"], burst["reset"]) == (24, 27, "0x0")
    assert "encoding limitation" in burst["description"]
    sram = next(r for r in data["registers"]["sram"]["registers"] if r["name"] == "CAPABILITY")
    assert "rejects WRAP" in next(f for f in sram["fields"] if f["name"] == "WRAP")["description"]


@pytest.mark.parametrize("key,value", [("document_id", "RS-MINI-DS"), ("profile", "configs/ci/ihp130.mk"), ("status", "RELEASE")])
def test_wrong_product_configuration_cannot_enter_tiny_pipeline(key, value):
    config = tiny.read(ROOT / tiny.BOOK / "tiny.json")
    config[key] = value
    with pytest.raises(ValueError, match="configuration"):
        tiny.validate_configuration(config)


def test_existing_mini_output_is_never_overwritten(tmp_path, monkeypatch):
    from publications import build_tiny_datasheet as builder
    folder = tmp_path / "build/mini-existing"
    folder.mkdir(parents=True)
    manifest = folder / "manifest.json"
    manifest.write_text('{"document":{"document_id":"RS-MINI-DS"}}')
    before = manifest.read_bytes()
    monkeypatch.setattr(builder, "ROOT", tmp_path)
    with pytest.raises(ValueError, match="another product"):
        builder.validate_output(folder, {"document_id": "RS-TINY-DS"})
    assert manifest.read_bytes() == before


@pytest.mark.parametrize("change", ["missing", "offset"])
def test_register_inventory_cannot_silently_drop_or_move_a_definition(data, change):
    refs = copy.deepcopy(data["registers"])
    if change == "missing":
        refs["uart"]["registers"].pop()
    else:
        refs["uart"]["registers"][0]["offset"] += 4
    with pytest.raises(ValueError, match="register inventory"):
        tiny.validate_register_inventory(refs, tiny.read(ROOT / tiny.BOOK / "register-contract.json"))


@pytest.mark.parametrize("change", ["missing", "duplicate"])
def test_pdf_must_render_each_extracted_register_once(data, change):
    from publications.build_tiny_datasheet import validate_rendered_registers
    items = [dict(kind="tiny-register", family=family, key=r["key"], page=1)
             for family, value in data["registers"].items() for r in value["registers"]]
    assert validate_rendered_registers(data, items) == 337
    if change == "missing":
        items.pop()
    else:
        items.append(items[0])
    with pytest.raises(ValueError, match="omitted or duplicated"):
        validate_rendered_registers(data, items)


@pytest.mark.parametrize("key,value", [("status", "qualified"), ("current_commit_reports", [{"passed": True}])])
def test_unmatched_qualification_claim_is_rejected(data, key, value):
    evidence = copy.deepcopy(data["evidence"])
    evidence[key] = value
    with pytest.raises(ValueError, match="qualification"):
        tiny.validate_evidence(evidence)
