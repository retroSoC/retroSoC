"""Publication data must not turn reference assumptions into product guarantees."""
from __future__ import annotations

from copy import deepcopy
import csv
import json
import math
from pathlib import Path
from subprocess import CompletedProcess

import pytest

from publications import specification_reference as s
from publications import specification_vectors
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
    tiny_voltage = next(d for d in spec["datasets"] if d["id"] == "current-voltage")
    mini_voltage = next(d for d in mini["datasets"] if d["id"] == "current-voltage")
    assert (tiny_voltage["title"], tiny_voltage["x_label"]) == (
        "Core current versus power-rail voltage", "Model core power-rail voltage (V)",
    )
    assert (mini_voltage["title"], mini_voltage["x_label"]) == (
        "Core current versus supply", "Model core supply (V)",
    )


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
    assert qfn["dimensions"]["pad_outer"] - qfn["dimensions"]["pad_inner"] == pytest.approx(2 * qfn["dimensions"]["pad_length"])
    assert spec["paste_coverage_percent"] == pytest.approx(16 * 1.4 ** 2 / 7.15 ** 2 * 100)


@pytest.mark.parametrize("product", ["tiny", "mini"])
def test_package_marking_exports_are_tiny_only(tmp_path, monkeypatch, product):
    def compile_view(command, **kwargs):
        Path(command[3]).write_text(command[-1], encoding="utf-8")
        return CompletedProcess(command, 0, stdout="", stderr="")

    monkeypatch.setattr(specification_vectors.subprocess, "run", compile_view)
    files = specification_vectors.render(ROOT, tmp_path, {"product": product}, "typst", [])
    for suffix in ("svg", "pdf"):
        relative = f"engineering/qfn-marking.{suffix}"
        if product == "tiny":
            assert (tmp_path / relative).read_text(encoding="utf-8") == "figure=qfn-marking"
            assert files[relative] == s.digest(tmp_path / relative)
        else:
            assert relative not in files and not (tmp_path / relative).exists()


def test_tiny_pin_descriptions_keep_roles_and_electrical_status(spec):
    pins = {p["name"]: p for p in spec["qfn"]["pins"]}
    for pin in pins.values():
        if pin["name"].startswith(("VDD", "AVDD")):
            assert (pin["function"], pin["direction"], pin["reset"], pin["bias"]) == ("Power", "-", "N/A", "N/A")
        elif pin["name"].startswith(("VSS", "AVSS")):
            assert (pin["function"], pin["direction"], pin["reset"], pin["bias"]) == ("Ground", "-", "N/A", "N/A")
    for name in ("GPIO6", "GPIO7", "GPIO17"):
        pin = pins[name]
        assert (pin["function"], pin["direction"], pin["reset"], pin["bias"]) == (
            "General-purpose I/O", "I/O", "Input, OE off", "Pulls off",
        )
    for name in ("XOUT", "BOOT_MODE", "TEST_MODE"):
        pin = pins[name]
        assert pin["unbound_target"]
        assert (pin["function"], pin["direction"], pin["reset"], pin["bias"]) == ("Unbound target", "TBD", "TBD", "TBD")
    assert pins["XPI_D0"]["direction"] == "I/O"
    assert "Direction changes by phase" in pins["XPI_D0"]["limitation"]


def test_tiny_target_pinout_numbering_and_callouts(spec):
    qfn = spec["qfn"]
    pins = qfn["pins"]
    assert len({p["name"] for p in pins}) == 64
    for side in range(4):
        edge = pins[side * 16:(side + 1) * 16]
        axis = 1 - side % 2
        coordinates = [p["top"][axis] for p in edge]
        assert [p["side"] for p in edge] == [side] * 16
        assert coordinates == sorted(coordinates, reverse=side in {0, 3})
    assert {p["name"] for p in pins if p["unbound_target"]} == {"XOUT", "BOOT_MODE", "TEST_MODE"}
    aliases = qfn["pinout_aliases"]
    pin_numbers = {p["name"]: p["pin"] for p in pins}
    expected = sorted(
        (pin_numbers[f"GPIO{r['gpio']}"], r["gpio"], r["mode"], r["function"])
        for r in spec["pins"] if r["function"] != "Not routed"
    )
    assert [(a["pin"], a["gpio"], a["mode"], a["function"]) for a in aliases] == expected
    assert [sum(a["mode"] == mode for a in aliases) for mode in ("ALT0", "ALT1")] == [30, 19]
    assert [sum(pins[a["pin"] - 1]["side"] == side for a in aliases) for side in range(4)] == [9, 14, 24, 2]
    assert {a["gpio"] for a in aliases} == set(range(32)) - {6, 7}


@pytest.mark.parametrize("change, error", [
    ("missing-mode", r"Missing QFN64 mux mapping for GPIO20 ALT1"),
    ("duplicate-mode", r"Duplicate QFN64 mux mapping for GPIO20 ALT1"),
    ("unknown-route", r"Unknown QFN64 mux mapping for GPIO32 ALT1"),
    ("unknown-target", r"Unknown QFN64 GPIO target GPIO32"),
    ("duplicate-target", r"Duplicate QFN64 GPIO target GPIO17"),
])
def test_tiny_target_pinout_rejects_bad_mapping(spec, change, error):
    pins = deepcopy(spec["qfn"]["pins"])
    routes = deepcopy(spec["pins"])
    route = next(r for r in routes if (r["gpio"], r["mode"]) == (20, "ALT1"))
    if change == "missing-mode":
        routes.remove(route)
    elif change == "duplicate-mode":
        routes.append(route.copy())
    elif change == "unknown-route":
        route["gpio"] = 32
    else:
        pin = next(p for p in pins if p["name"] == "GPIO20")
        pin["name"] = "GPIO32" if change == "unknown-target" else "GPIO17"
    with pytest.raises(ValueError, match=error):
        s.qfn_pinout_aliases(pins, routes)


def test_qfn_reference_dimensions_and_contact_edges(spec):
    qfn = spec["qfn"]
    pins = qfn["pins"]
    assert [sum(p["side"] == side for p in pins) for side in range(4)] == [16] * 4
    assert pins[0]["top"] == [-4.5, 3.75]
    assert pins[0]["bottom"] == [4.5, 3.75]
    for pin in pins:
        x, y, width, height = pin["top_terminal"]
        assert abs(x) + width / 2 <= 4.5 + 1e-9
        assert abs(y) + height / 2 <= 4.5 + 1e-9
        assert pin["bottom_terminal"] == [-x, y, width, height]
    west = pins[0]["land"]
    east = pins[32]["land"]
    assert east[0] + east[2] / 2 - (west[0] - west[2] / 2) == pytest.approx(9.50)
    assert east[0] - east[2] / 2 - (west[0] + west[2] / 2) == pytest.approx(8.10)
    assert qfn["land_row_span"] == "7.50"

    measures = qfn["measurements"]
    assert measures["standoff"]["nom"] is None
    assert (measures["standoff"]["min"], measures["standoff"]["max"]) == ("0.00", "0.05")
    assert measures["lead_height"]["nom"] == "0.200 REF"
    assert measures["ep"]["label"] == "7.15 ± 0.10"
    assert measures["pad_ep"]["label"] == "7.15 ± 0.05"
    assert qfn["assembly"]["mask_web_mm"] == pytest.approx(0.15)
    assert qfn["assembly"]["mask_ep_gap_mm"] == pytest.approx(0.375)
    assert qfn["assembly"]["via_span_mm"] == pytest.approx(4.45)


@pytest.mark.parametrize(("group", "field", "value", "error"), [
    ("pcb", "mask_expansion_mm", 0.13, "solder mask openings overlap"),
    ("paste", "aperture_mm", 1.7, "paste windows do not fit"),
    ("pcb", "via_grid", 8, "thermal vias do not fit"),
])
def test_qfn_assembly_overlays_must_fit(spec, group, field, value, error):
    models = deepcopy(spec["models"])
    models[group][field] = value
    with pytest.raises(ValueError, match=error):
        s.qfn_assembly(spec["qfn"]["dimensions"], models)


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


def test_tiny_tape_and_reel_match_one_ti_orderable_device(spec):
    records = {r["id"].removeprefix("tiny."): r for r in spec["records"]}
    expected = {
        "carrier-tape.pocket-width": (9.30, "mm"), "carrier-tape.pocket-length": (9.30, "mm"),
        "carrier-tape.pocket-depth": (1.10, "mm"), "carrier-tape.pocket-pitch": (12.00, "mm"),
        "carrier-tape.width": (16.00, "mm"), "carrier-tape.orientation": ("Q2", "1"),
        "reel.diameter": (330, "mm"), "reel.width": (16.4, "mm"), "reel.quantity": (2000, "devices/reel"),
    }
    for key, pair in expected.items():
        record = records[key]
        assert (record["value"], record["unit"]) == pair
        assert record["status"] == "reference" and record["sources"] == ["ti-tusb8041-tape-reel"]
        assert "TUSB8041IRGCR" in record["conditions"]
    for key in ("carrier-tape.supplier-drawing", "reel.supplier-drawing", "reel.hub", "reel.pack-quantity"):
        assert records[key]["status"] == "tbd" and records[key]["value"] is None
    assert f"{s.BOOKS['tiny']}/sources.json" in s.source_inputs("tiny")


def test_tiny_reel_box_reference_uses_the_same_orderable_device(spec):
    records = {r["id"]: r for r in spec["records"]}
    sources = {source["id"]: source for source in spec["sources"]}
    carton = sources["ti-tusb8041-reel-box"]
    reel = sources["ti-tusb8041-tape-reel"]
    assert carton["sha256"] == reel["sha256"] and carton["version"] == reel["version"]
    assert carton["url"].endswith("#page=48") and "TUSB8041IRGCR" in carton["locator"]
    for key, symbol, nominal in (("length", "L", 367.0), ("width", "W", 367.0), ("height", "H", 38.0)):
        record = records[f"tiny.reel-box.{key}"]
        assert (record["unit"], record["value"], record["decimals"], record["symbols"]) == ("mm", nominal, 1, [symbol])
        assert record["group"] == "reel-box" and record["status"] == "reference"
        assert record["sources"] == [carton["id"]] and "TUSB8041IRGCR" in record["conditions"]
    pending = records["tiny.reel-box.supplier-drawing"]
    assert (pending["group"], pending["status"], pending["value"]) == ("reel-box", "tbd", None)
    assert "contents per carton" in pending["meaning"]
    quantity = records["tiny.reel.quantity"]
    assert (quantity["value"], quantity["unit"], quantity["status"]) == (2000, "devices/reel", "reference")
    assert "TUSB8041IRGCR" in quantity["conditions"]


def test_tiny_reflow_classification_values_are_separate_from_product_limits(spec):
    records = {r["id"].removeprefix("tiny."): r for r in spec["records"]}
    values = {
        "start-temperature": 25, "liquidus-temperature": 217, "peak-temperature": 260, "peak-band": 5,
    }
    bounds = {
        "soak-temperature": (150, 200), "soak-time": (60, 120), "liquidus-time": (60, 150),
        "peak-time": (None, 30), "ramp-up": (None, 3), "ramp-down": (None, 6), "time-to-peak": (None, 8),
    }
    for key, expected in (values | {k: dict(min=lo, typ=None, max=hi) for k, (lo, hi) in bounds.items()}).items():
        record = records["reflow." + key]
        assert record["value"] == expected
        assert record["status"] == "reference" and record["sources"] == ["adi-smp-reflow"]
    assert "< 1.6 mm" in records["reflow.peak-temperature"]["conditions"]
    for key in ("reflow.product-limits", "reflow.board-profile", "assembly.msl"):
        assert records[key]["status"] == "tbd" and records[key]["value"] is None
