"""Publication data must not turn reference assumptions into product guarantees."""
from __future__ import annotations

from copy import deepcopy
import csv
import json
import math
from pathlib import Path

import pytest

from publications import specification_reference as s
from publications import tiny_reference

ROOT = Path(__file__).resolve().parents[1]


@pytest.fixture(scope="module")
def spec():
    return tiny_reference.collect(tiny_reference.read(ROOT / tiny_reference.BOOK / "tiny.json"))["specifications"]


@pytest.mark.parametrize("change", [
    "no-source", "no-condition", "no-assumption", "reference-confirmed", "reference-calculated",
    "wrong-product", "tbd-zero", "unknown-zero", "range", "source-id", "no-replacement",
])
def test_bad_data_is_rejected(spec, change):
    records = deepcopy(spec["records"])
    reference = next(r for r in records if r["id"] == "tiny.operating.vcore")
    if change == "no-source":
        reference["sources"] = []
    elif change == "no-condition":
        reference["conditions"] = ""
    elif change == "no-assumption":
        reference["assumptions"] = []
    elif change == "reference-confirmed":
        reference.update(status="confirmed", evidence="physical")
    elif change == "reference-calculated":
        reference["status"] = "calculated"
    elif change == "wrong-product":
        reference["product"] = "mini"
    elif change == "tbd-zero":
        next(r for r in records if r["status"] == "tbd")["value"] = 0
    elif change == "unknown-zero":
        reference.update(status="reference", value=None)
    elif change == "range":
        reference["value"] = {"min": 3, "typ": 2, "max": 1}
    elif change == "source-id":
        reference["sources"] = ["made-up"]
    else:
        reference["replacement"] = ""
    with pytest.raises(ValueError):
        s.validate_records(records, spec["sources"], "tiny")


@pytest.mark.parametrize("change", ["reference-input", "tbd-input", "unit", "cross-product", "cycle", "promotion"])
def test_dependency_status_and_units_are_enforced(spec, change):
    records = deepcopy(spec["records"])
    child = next(r for r in records if r["id"] == "tiny.relative.safe24")
    dep = child["dependencies"][0]
    if change == "reference-input":
        dep.update(id="tiny.operating.vcore", unit="V")
    elif change == "tbd-input":
        dep.update(id="tiny.dc.voh", unit="V")
    elif change == "unit":
        dep["unit"] = "MHz"
    elif change == "cross-product":
        dep["id"] = "mini.clock.ref"
    elif change == "cycle":
        dep.update(id=child["id"], unit="1")
    else:
        child.update(status="confirmed", evidence="physical")
    with pytest.raises(ValueError):
        s.validate_records(records, spec["sources"], "tiny")


def test_reference_derivation_cannot_hide_its_inputs(spec):
    rows = deepcopy(spec["records"])
    parent = next(r for r in rows if r["id"] == "tiny.operating.vcore")
    child = next(r for r in rows if r["id"] == "tiny.relative.safe24")
    child["dependencies"] = [{"id": parent["id"], "unit": parent["unit"]}]
    child.update(status="reference", assumptions=["Constructed input inherited."])
    s.validate_records(rows, spec["sources"], "tiny")
    child["status"] = "calculated"
    with pytest.raises(ValueError, match="reference input"):
        s.validate_records(rows, spec["sources"], "tiny")


@pytest.mark.parametrize(("divider", "valid"), [(0, False), (1, True), (65535, True), (65536, False), (-1, False)])
def test_half_period_boundaries(divider, valid):
    if valid:
        assert s.half_period_clock(24e6, divider) == 24e6 / (2 * divider)
    else:
        with pytest.raises(ValueError):
            s.half_period_clock(24e6, divider)
    if divider == 0:
        assert s.half_period_clock(24e6, 0, zero_clamps=True) == 12e6


def test_bandwidth_uses_bytes_and_decimal_megabytes():
    assert s.ideal_bandwidth(32, 24e6) == 96e6
    assert s.ideal_bandwidth(64, 36e6) == 288e6
    with pytest.raises(ValueError):
        s.ideal_bandwidth(7, 24e6)
    seconds, bps = s.transfer_model(1024, 24e6, 96e6, 16, .6)
    assert seconds == pytest.approx(16 / 24e6 + 1024 / (.6 * 96e6))
    assert bps == pytest.approx(1024 / seconds)


def test_fixed_models_and_csv_recompute(spec, tmp_path):
    assert s.reference_current(24, 1.2, 25, .05) == pytest.approx(1.4)
    for dataset in spec["datasets"]:
        path = tmp_path / (dataset["id"] + ".csv")
        s.export_csv(path, dataset)
        with path.open(encoding="utf-8", newline="") as f:
            rows = list(csv.DictReader(f))
        assert len(rows) == len(dataset["points"])
        for row, point in zip(rows, dataset["points"]):
            assert float(row["x"]) == pytest.approx(point["x"], rel=1e-11)
            assert float(row["y"]) == pytest.approx(point["y"], rel=1e-11)
            assert row["status"] == dataset["status"]
    gpio = next(d for d in spec["datasets"] if d["id"] == "gpio-load")
    assert next(p["y"] for p in gpio["points"] if p["series"] == "VOH" and p["x"] == 12) == pytest.approx(2.82)
    assert next(p["y"] for p in gpio["points"] if p["series"] == "VOL" and p["x"] == 12) == pytest.approx(.48)


def test_selected_fabric_clock_is_not_the_backend_clock(spec):
    values = {r["id"]: r["value"] for r in spec["records"]}
    for clock in spec["clocks"]:
        assert clock["bus_hz"] == clock["cpu_hz"]
        assert values[clock["bandwidth_id"]] == 4 * clock["cpu_hz"]
    from publications.build_datasheet import CONFIG, collect_data, read_json
    mini = collect_data(read_json(CONFIG), check_snapshot=False)["specifications"]
    values = {r["id"]: r["value"] for r in mini["records"]}
    assert values["mini.clock.hp"] == 72e6
    assert {c["bus_hz"] for c in mini["clocks"]} == {72e6}
    assert {values[c["bandwidth_id"]] for c in mini["clocks"]} == {576e6}
    assert {c["memory_hz"] for c in mini["clocks"]} == {36e6}


def test_qfn64_views_share_numbering_and_mirror(spec):
    qfn = spec["qfn"]
    assert len(qfn["pins"]) == 64
    assert len({p["pin"] for p in qfn["pins"]}) == 64
    assert qfn["ep"]["pin"] is None
    assert qfn["ep"]["name"] == "EP"
    for p in qfn["pins"]:
        assert p["bottom"] == [-p["top"][0], p["top"][1]]
        assert p["pcb"] == p["top"]
    for left, right in zip(qfn["pins"], qfn["pins"][1:]):
        if left["side"] == right["side"]:
            assert math.dist(left["top"], right["top"]) == pytest.approx(.5)
    assert qfn["pins"][0]["top"][0] < 0 < qfn["pins"][0]["bottom"][0]
    audio = next(p for p in spec["pins"] if p["gpio"] == 17 and p["mode"] == "ALT0")
    assert (audio["function"], audio["direction"]) == ("AUDIO.CLKIN", "I")
    assert audio["rtl"] == "s_audio_pad_clk"
    assert qfn["pins"][39]["name"] == "GPIO17"
    assert "ALT0 I" in qfn["pins"][39]["gpio_mode"]
    assert qfn["dimensions"]["pad_outer"] - qfn["dimensions"]["pad_inner"] == pytest.approx(2 * qfn["dimensions"]["pad_length"])
    assert spec["paste_coverage_percent"] == pytest.approx(16 * 1.4 ** 2 / 7.15 ** 2 * 100)


@pytest.mark.parametrize("change", ["duplicate-pin", "ep-collision", "pad-overlap", "span"])
def test_invalid_geometry_cannot_generate_views(spec, change):
    dims = deepcopy(spec["qfn"]["dimensions"])
    pins = deepcopy(spec["qfn"]["pins"])
    if change == "duplicate-pin":
        pins[-1]["pin"] = 1
    elif change == "ep-collision":
        dims["ep"] = 8.9
    elif change == "pad-overlap":
        dims["pad_width"] = .5
    else:
        dims["pad_outer"] = 10
    with pytest.raises(ValueError):
        s.qfn_geometry(dims, pins)


def test_rendered_usage_and_replacement_index_are_complete(spec, tmp_path):
    items = [dict(kind="specification-use", id=r["id"], status=r["status"], page=1) for r in spec["records"]]
    items += [dict(kind="specification-figure", id=d["id"], category="curve", page=1) for d in spec["datasets"]]
    hashes = s.export_audits(tmp_path, spec, items)
    s.verify_audits(tmp_path, hashes)
    replacement = s.read(tmp_path / "specification-replacement.json")
    assert len(replacement) == len(spec["records"])
    assert all(r["uses"] and r["replacement"] for r in replacement)
    with pytest.raises(ValueError, match="unpublished"):
        s.export_audits(tmp_path, spec, items[1:])
    (tmp_path / "specification-usage.json").write_text("{}\n", encoding="utf-8")
    with pytest.raises(ValueError, match="integrity"):
        s.verify_audits(tmp_path, hashes)


def test_models_are_centrally_fingerprinted_and_references_stay_separate(spec):
    s.validate_sources(spec["sources"], ROOT)
    assert {r["status"] for r in spec["records"]} == s.STATES
    assert all(d["status"] == "reference" for d in spec["datasets"] if d["id"] != "cpu-relative")
    assert not any("tiny" in p for p in s.source_inputs("mini"))
    assert "publications/datasheets/tiny/specifications/parameters.json" in s.source_inputs("tiny")
    params = json.loads((ROOT / s.BOOKS["mini"] / "parameters.json").read_text(encoding="utf-8"))
    assert not any(r["group"] == "mechanical" for r in params["records"])
