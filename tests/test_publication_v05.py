"""v0.5 keeps executable configuration, published scope and evidence distinct."""
import copy
from pathlib import Path

import pytest

from publications.build_datasheet import CONFIG, collect_data, read_json
from publications.dev_reference import validate_accelerator_claims, validate_ci_snapshot

ROOT = Path(__file__).resolve().parents[1]


@pytest.fixture(scope="module")
def data():
    return collect_data(read_json(CONFIG), check_snapshot=False)


def test_npu_deployed_geometry_dma_and_wire_layout(data):
    reference = data["system_reference"]
    npu = reference["npu_implementation"]
    assert (npu["capability"], npu["op_mask"], npu["dense_macs"], npu["depthwise_macs"]) == (0x7F, 0x1FE, 64, 8)
    assert (npu["local_bytes"], npu["accumulator_contexts"], npu["accumulator_bytes"], npu["max_burst_beats"]) == (65536, 2, 256, 8)
    diagrams = reference["illustrations"]
    assert diagrams["layouts"]["npu-descriptor"]["bits"] == 1024
    assert [r["bytes"] for r in diagrams["storage"]["npu-local"]["ranges"]] == [16384, 16384, 16384, 8192, 8192]
    assert {"npu", "npu-exception"} <= data["waveforms"].keys()
    model = diagrams["soc_architecture"]["soc-functional"]
    node = next(n for n in model["nodes"] if n["id"] == "npu")
    assert node["ips"] == ["npu"] and node["domain"] == "hp"
    assert any(r["domain"] == "hp" and r["x"] <= node["x"] and r["y"] <= node["y"]
               and r["x"] + r["w"] >= node["x"] + node["w"]
               and r["y"] + r["h"] >= node["y"] + node["h"] for r in model["regions"])


def test_apu_capability_and_digest_remain_profile_specific(data):
    rows = data["system_reference"]["apu_implementation"]["profiles"]
    assert [(r["enabled"], r["capability"], r["digest"]) for r in rows] == [(False, 0x1BD, 0), (True, 0x1FD, 0xF5005D7C)]
    assert all(r["capability"] & 2 == 0 for r in rows)  # MP3 remains clear.


@pytest.mark.parametrize("kind", ["npu-shell", "apu-blanket", "npu-counter", "npu-qualified", "npu-profile"])
def test_stale_live_accelerator_prose_is_not_accepted(data, kind):
    catalog, features, content, annotations, profiles = [
        read_json(ROOT / "publications/datasheets" / f) for f in
        ["ip-catalog.json", "features.json", "ip-content.json", "register-annotations.json", "register-profiles.json"]]
    if kind == "npu-shell":
        next(r for r in catalog if r["id"] == "npu")["summary"] = "Phase 2 integrates the NPU control shell only."
    elif kind == "apu-blanket":
        features["apu"] = ["MP3/KWS are not advertised."]
    elif kind == "npu-counter":
        annotations["npu"]["main.PERF_ACTIVE_CYCLES_LO"]["description"] = "P2 never runs a job, so it stays zero."
    elif kind == "npu-qualified":
        annotations["npu"]["main.CAPABILITY"]["description"] = "All operators are implemented and verified."
    else:
        profiles["npu"]["groups"][0]["title"] = "Phase 2 control shell and lifecycle endpoint"
    reference = copy.deepcopy(data["system_reference"])
    reference["retrieval"] = read_json(ROOT / "publications/datasheets/system-reference.json")["retrieval"]
    with pytest.raises(ValueError, match="NPU live|APU publication"):
        validate_accelerator_claims(reference, catalog, features, content, annotations, profiles)


def test_ci_nonterminal_status_never_becomes_pass_or_failure(data):
    snapshot = copy.deepcopy(data["system_reference"]["ci_snapshot"])
    run = snapshot["runs"][0]
    run.update(status="in_progress", conclusion=None)
    validate_ci_snapshot(snapshot, snapshot["revision"])
    run["conclusion"] = "success"
    with pytest.raises(ValueError, match="unfinished"):
        validate_ci_snapshot(snapshot, snapshot["revision"])
    run.update(status="completed", conclusion=None)
    with pytest.raises(ValueError, match="completed"):
        validate_ci_snapshot(snapshot, snapshot["revision"])


def test_historical_or_absent_evidence_is_not_promoted(data):
    for row in data["system_reference"]["support"]:
        if row["id"] in {"npu", "apu", "ga2d"}:
            assert row["verification"] == "Tests available" and row["reports"] == []
