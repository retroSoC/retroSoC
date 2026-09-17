"""Approved dev publication refreeze and mixed CI outcomes retain their boundaries."""
from __future__ import annotations

import copy
from pathlib import Path

import pytest

from publications.build_datasheet import CONFIG, collect_data, read_json, source_hashes
from publications.dev_reference import validate_ci_snapshot
from publications.diagram_coverage import inventory
from publications.diagram_reference import validate_circuit

ROOT = Path(__file__).resolve().parents[1]


@pytest.fixture(scope="module")
def data():
    return collect_data(read_json(CONFIG), check_snapshot=False)


def test_refrozen_structure_covers_ga2d_without_duplicate_register_ownership(data):
    contract = read_json(ROOT / "publications/datasheets/structure-contract.json")
    assert len(contract["entries"]) == 108
    assert len(contract["ip_ids"]) == 41
    assert contract["ip_ids"].index("ga2d") == contract["ip_ids"].index("jpeg") + 1
    assert contract["ip_ids"].index("apu") == contract["ip_ids"].index("ga2d") + 1
    assert sum(len(group["items"]) for group in data["overview_groups"]) == 44
    ga2d = next(row for row in data["regions"] if row["symbol"] == "APB4_GA2D")
    assert (ga2d["base"], ga2d["size"], ga2d["kind"]) == (0x10012000, 4096, "active")
    assert len(data["policies"]) == 9
    route = next(row for row in data["system_reference"]["programming"]["engines"] if row["id"] == "ga2d")
    assert (route["master"], route["lp_irq"], route["hp_irq"]) == ("8", 32, 11)


def test_current_apu_image_fits_v2_without_enabling_kws_or_mp3(data):
    implementation = data["system_reference"]["apu_implementation"]
    assert implementation["abi"] == 0x00020000
    assert 2048 < implementation["instruction_words"] <= implementation["maximum_instruction_words"] == 4096
    assert implementation["free_instruction_words"] == 4096 - implementation["instruction_words"]
    assert implementation["entry_formats"] == [0, 1, 2]
    assert implementation["p7_default_enabled"] is False
    assert (implementation["kws_model_bytes"], implementation["kws_header_bytes"], implementation["kws_operators"], implementation["kws_tensors"]) == (32768, 64, 12, 13)
    diagrams = data["system_reference"]["illustrations"]
    assert diagrams["apu"]["image_limits"] == {"v1": 2048, "v2": 4096}
    assert sum(len(family["operations"]) for family in diagrams["apu"]["families"]) == 62
    assert diagrams["layouts"]["apu-descriptor"]["bits"] == 128 * 8


def test_new_drawings_keep_geometry_and_manifest_sources(data):
    diagrams = data["system_reference"]["illustrations"]
    records = inventory(diagrams)
    assert {"circuiteria:ga2d", "bytefield:ga2d-pixels", "blockcell:ga2d-fifos", "blockcell:ga2d-pitched-buffer"} <= records.keys()
    fifo = diagrams["storage"]["ga2d-fifos"]["stores"]
    assert [(row["depth"], row["bits"]) for row in fifo] == [(32, 64), (32, 64), (32, 64), (32, 8)]
    rgb888 = diagrams["layouts"]["ga2d-pixels"]["rows"][1]
    assert [(field["name"], field["lsb"]) for field in rgb888["fields"]] == [("R", 0), ("G", 8), ("B", 16)]
    sources = source_hashes(read_json(CONFIG), data["catalog"], data["registers"])
    assert all(set(record["sources"]) <= sources.keys() for record in records.values())
    broken = copy.deepcopy(diagrams["circuits"]["monitor"])
    broken["edges"][0]["label"] = "Accept / 8"
    with pytest.raises(ValueError, match="label width"):
        validate_circuit(ROOT, broken)


def test_ci_failures_do_not_become_per_ip_reported_pass(data):
    reference = data["system_reference"]
    snapshot = reference["ci_snapshot"]
    validate_ci_snapshot(snapshot, reference["source_revision"])
    runs = {run["name"]: run for run in snapshot["runs"]}
    assert runs["quality"]["result"] == runs["regression-sky130"]["result"] == "failure"
    assert runs["regression-ihp130"]["result"] == "success"
    assert all(row["verification"] != "Reported pass" for row in reference["support"])


@pytest.mark.parametrize("mutation", ["revision", "url", "duplicate", "outcome"])
def test_ci_snapshot_rejects_mismatched_or_unscoped_results(data, mutation):
    reference = data["system_reference"]
    snapshot = copy.deepcopy(reference["ci_snapshot"])
    if mutation == "revision":
        snapshot["revision"] = "0" * 40
    elif mutation == "url":
        snapshot["runs"][0]["url"] += "0"
    elif mutation == "duplicate":
        snapshot["runs"].append(copy.deepcopy(snapshot["runs"][0]))
    else:
        snapshot["runs"][0]["result"] = "silicon-qualified"
    with pytest.raises(ValueError):
        validate_ci_snapshot(snapshot, reference["source_revision"])
