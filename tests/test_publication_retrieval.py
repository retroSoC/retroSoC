"""Lookup addresses and diagnostic scopes must remain faithful to their sources."""
from __future__ import annotations

import copy
import json
from pathlib import Path

import pytest

from publications import retrieval_reference as rr
from publications.build_datasheet import collect_data
from publications.report_changes import page_ranges, verified_pdf
from publications.system_reference import source_paths

ROOT = Path(__file__).resolve().parents[1]
RAW = json.loads((ROOT / "publications/datasheets/system-reference.json").read_text(encoding="utf-8"))
SPEC = RAW["retrieval"]
CONFIG = json.loads((ROOT / "publications/datasheets/mini.json").read_text(encoding="utf-8"))


@pytest.fixture(scope="module")
def data():
    if not (ROOT / "rtl/managed/clusterip/rtc/rtl/rtc_reg.sv").is_file():
        pytest.skip("publication setup is required")
    return collect_data(CONFIG, check_snapshot=False)


def index(data, *, instances=None, registers=None, regions=None):
    return rr.register_index(registers or data["registers"], regions or data["regions"],
                             data["catalog"], instances or SPEC["instances"], data["mpw"])


def bank(result, region):
    return next(b for b in result["instances"] if b["region"] == region)


def test_complete_index_preserves_shared_links_and_excludes_data_apertures(data):
    result = index(data)
    assert result["definitions"] == sum(len(v["registers"]) for v in data["registers"].values())
    for left, right in (("APB4_UART0", "APB4_UART1"), ("APB4_SDIO0", "APB4_SDIO1")):
        a, b = bank(result, left), bank(result, right)
        assert a["base"] != b["base"]
        assert [r["link"] for r in a["rows"]] == [r["link"] for r in b["rows"]]
    assert not {b["region"] for b in result["instances"]} & {"FLASH", "XPI", "SRAM", "SDRAM", "PSRAM", "OPIPSRAM"}


def test_array_addresses_include_group_base_exactly_once(data):
    result = index(data)
    dma = bank(result, "APB4_DMA")
    row = next(r for r in dma["rows"] if r["key"] == "ch.ERROR_STATUS")
    assert row["first"] == 0x1000A128
    assert row["last"] == 0x1000A4A8
    assert (row["stride"], row["count"], row["offset_hex"]) == (0x80, 8, "0x128")
    plic = bank(result, "HP_PLIC")
    claim = next(r for r in plic["rows"] if r["key"] == "context.CLAIM_COMPLETE")
    assert (claim["first"], claim["last"]) == (0x0C200004, 0x0C201004)


def test_gpio_common_discovery_decode_and_mpw_scope(data):
    result = index(data)
    user = {r["key"] for r in bank(result, "APB4_GPIO")["rows"]}
    admin = {r["key"] for r in bank(result, "APB4_GPIO_ADMIN")["rows"]}
    assert "common.PAD_CAPABILITY" not in user and "common.PAD_CAPABILITY" in admin
    assert {"common.IP_VERSION", "common.CAPABILITY"} <= user & admin
    legacy = [b for b in result["instances"] if b["mode"] == "MPW"]
    assert {b["slot"] for b in legacy} == {1, 2}
    assert len({b["base"] for b in legacy}) == 1


def test_ext_l_index_qualifies_shared_ext_h_values(data):
    result = index(data)
    low = {r["key"]: r for r in bank(result, "APB4_EXT_L")["rows"]}
    high = {r["key"]: r for r in bank(result, "APB4_EXT_H")["rows"]}
    assert low["main.Identification"]["reset"] == "0x4558544C"
    assert high["main.Identification"]["reset"] == "0x45585448"
    assert low["main.Capability"]["reset"] != high["main.Capability"]["reset"]
    assert "rejected" in low["main.DmaCommand"]["access"]
    assert low["main.DmaStatus"]["reset"] == "0x00000000"
    assert "can still change" in bank(result, "APB4_EXT_L")["qualification"]
    assert any(row["id"] == "ext-l-rejected-base-write" for row in RAW["limitations"])


@pytest.mark.parametrize("mutation,match", [
    ("omit_uart1", "omits an active"), ("omit_mpw", "coverage|MPW"),
    ("duplicate", "duplicate instance"), ("wrong_family", "unknown register family"),
    ("data_aperture", "active register window"), ("wrong_selection", "MPW selection"),
    ("wrong_owner", "does not belong"), ("no_override_binding", "require source bindings"),
])
def test_incomplete_or_wrong_instance_mappings_fail(data, mutation, match):
    rows = copy.deepcopy(SPEC["instances"])
    if mutation == "omit_uart1":
        rows = [r for r in rows if r["region"] != "APB4_UART1"]
    elif mutation == "omit_mpw":
        rows = [r for r in rows if r["id"] != "mpw-gpio"]
    elif mutation == "duplicate":
        rows.append(copy.deepcopy(rows[0]))
    elif mutation == "wrong_family":
        rows[0]["family"] = "missing"
    elif mutation == "data_aperture":
        rows[0]["region"] = "FLASH"
    elif mutation == "wrong_selection":
        next(r for r in rows if r["mode"] == "MPW")["slot"] = 7
    elif mutation == "wrong_owner":
        rows[0]["region"] = "APB4_UART0"
    else:
        next(r for r in rows if r["chapter"] == "ext-l")["bindings"] = []
    with pytest.raises(ValueError, match=match):
        index(data, instances=rows)


@pytest.mark.parametrize("mutation", ["overlap", "overrun", "unaligned", "empty_count"])
def test_expanded_array_geometry_is_checked(data, mutation):
    registers = copy.deepcopy(data["registers"])
    group = next(g for g in registers["dma"]["groups"] if g["id"] == "ch")
    if mutation == "overlap":
        group["stride"] = 4
    elif mutation == "overrun":
        group["count"] = 100
    elif mutation == "unaligned":
        group["base"] += 1
    else:
        group["count"] = 0
    with pytest.raises(ValueError, match="overlapping|out-of-window|geometry"):
        index(data, registers=registers)


def test_all_code_namespaces_and_boot_codes_are_source_checked():
    groups = [rr.code_group(ROOT, spec) for spec in SPEC["codes"]]
    assert next(g for g in groups if g["id"] == "rib-detail")["expected"]["RIB_RESP_BURSTERR"] == 6
    assert next(g for g in groups if g["id"] == "sdio-dma-mask")["kind"] == "mask"
    assert len(next(g for g in groups if g["id"] == "jpeg-error")["rows"]) == 19
    assert [r["value"] for r in rr.boot_status(ROOT, SPEC["boot"])["rows"]] == list(range(11))


@pytest.mark.parametrize("mutation", ["missing", "value", "meaning", "mask"])
def test_code_drift_and_wrong_numeric_interpretation_fail(mutation):
    spec = copy.deepcopy(next(r for r in SPEC["codes"] if r["id"] == "dma-error"))
    if mutation == "missing":
        spec["expected"].pop("DMA_ERROR_ABORT")
    elif mutation == "value":
        spec["expected"]["DMA_ERROR_ABORT"] = 9
    elif mutation == "meaning":
        spec["meanings"].pop("DMA_ERROR_ABORT")
    else:
        spec["kind"] = "mask"
    with pytest.raises(ValueError, match="coverage/value drift|individual bits"):
        rr.code_group(ROOT, spec)


def test_enum_extraction_ignores_comments_and_rejects_duplicates(tmp_path):
    (tmp_path / "codes.sv").write_text("// FOO = 4'd9\nFOO = 4'd1;", encoding="utf-8")
    spec = dict(id="x", source="codes.sv", pattern=r"(?P<name>FOO) = (?P<value>4'd\d)",
                expected={"FOO": 1}, meanings={"FOO": "One"}, kind="enum")
    assert rr.code_group(tmp_path, spec)["rows"][0]["value"] == 1
    (tmp_path / "codes.sv").write_text("FOO = 4'd1; FOO = 4'd1;", encoding="utf-8")
    with pytest.raises(ValueError, match="duplicate"):
        rr.code_group(tmp_path, spec)


def test_unknown_status_register_and_boot_scope_drift_fail(data):
    specs = copy.deepcopy(SPEC["status_registers"])
    specs[0]["registers"].append("main.INVENTED")
    with pytest.raises(ValueError, match="unknown diagnostic register"):
        rr.status_registers(specs, data["registers"])
    boot = copy.deepcopy(SPEC["boot"])
    boot["expected_entries"] = 5
    with pytest.raises(ValueError, match="branches changed"):
        rr.boot_status(ROOT, boot)


def test_changed_source_binding_is_rejected():
    row = {"id": "fake", "bindings": [{"file": "rtl/mini/top/extension_slot.sv", "text": "Fabricated constant"}]}
    with pytest.raises(ValueError, match="binding changed"):
        rr.validate_bindings(ROOT, row)


def test_packed_diagnostic_producers_have_readable_correct_field_boundaries(data):
    result = rr.status_registers(SPEC["status_registers"], data["registers"])
    clock = next(r for r in result if r["id"] == "clock-lifecycle")
    hp = next(r for r in clock["rows"] if r["name"] == "HP_STATUS")
    assert max(f["msb"] for f in hp["fields"]) == 5
    assert next(f for f in hp["fields"] if f["lsb"] == 2)["name"] == "REQUESTED_HOLD"
    dma = next(r for r in result if r["id"] == "central-dma-status")
    err = next(r for r in dma["rows"] if r["name"] == "ERROR_STATUS")
    assert [(f["lsb"], f["msb"]) for f in err["fields"]] == [(0, 3), (4, 5), (6, 6), (8, 8)]


@pytest.mark.parametrize("mutation", ["no_binding", "overlap", "out_of_bounds"])
def test_diagnostic_field_qualifications_require_evidence_and_valid_layout(data, mutation):
    specs = copy.deepcopy(SPEC["status_registers"])
    row = next(r for r in specs if r["id"] == "central-dma-status")
    if mutation == "no_binding":
        row["bindings"] = []
    elif mutation == "overlap":
        row["field_overrides"]["ch.ERROR_STATUS"][0]["msb"] = 4
    else:
        row["field_overrides"]["ch.ERROR_STATUS"][0]["msb"] = 32
    with pytest.raises(ValueError, match="qualification"):
        rr.status_registers(specs, data["registers"])


def test_derived_retrieval_preserves_all_manifest_dependencies(data):
    assert rr.dependencies(SPEC) == rr.dependencies(data["system_reference"]["retrieval"])
    assert source_paths(RAW) == source_paths(data["system_reference"])


def test_release_evidence_does_not_promote_test_availability():
    evidence = rr.release_evidence(ROOT, SPEC, RAW["source_revision"], RAW["support"])
    assert evidence["support_counts"]["Reported pass"] == 0
    assert evidence["readiness"][0]["status"] == "prototype"
    spec = copy.deepcopy(SPEC)
    spec["verification"][0]["status"] = "Reported pass"
    with pytest.raises(ValueError, match="requires a matching report"):
        rr.release_evidence(ROOT, spec, RAW["source_revision"], RAW["support"])


@pytest.mark.parametrize("field,value", [("revision", "b" * 40), ("profile", "wrong.mk"), ("stage", "silicon"), ("result", "fail")])
def test_release_report_context_must_match(tmp_path, field, value):
    report = dict(path="report.json", revision="a" * 40, profile="ref.mk", stage="simulation", result="pass")
    report[field] = value
    with pytest.raises(ValueError, match="does not match"):
        rr.validate_report(tmp_path, report, "a" * 40, ["ref.mk"], "simulation")


def test_release_report_file_must_substantiate_pass(tmp_path):
    report = dict(path="report.json", revision="a" * 40, profile="ref.mk", stage="simulation", result="pass")
    with pytest.raises(ValueError, match="missing"):
        rr.validate_report(tmp_path, report, "a" * 40, ["ref.mk"], "simulation")
    (tmp_path / report["path"]).write_text(json.dumps({**report, "result": "fail"}), encoding="utf-8")
    with pytest.raises(ValueError, match="contradicts"):
        rr.validate_report(tmp_path, report, "a" * 40, ["ref.mk"], "simulation")
    (tmp_path / report["path"]).write_text(json.dumps(report), encoding="utf-8")
    rr.validate_report(tmp_path, report, "a" * 40, ["ref.mk"], "simulation")


def markers():
    return [{"kind": "publication-change-start", "id": "a", "title": "Appendix", "category": "added", "page": 3},
            {"kind": "publication-change-end", "id": "a", "page": 5}]


def test_change_ranges_keep_navigation_and_substantive_categories():
    values = markers()
    values += [{"kind": "publication-change-start", "id": "toc", "title": "Contents", "category": "navigation", "page": 1},
               {"kind": "publication-change-end", "id": "toc", "page": 2}]
    result = page_ranges(values, 5)
    assert [(r["category"], r["start_page"], r["end_page"]) for r in result] == [("navigation", 1, 2), ("added", 3, 5)]


@pytest.mark.parametrize("mutation", ["unpaired", "duplicate", "reversed", "out_of_bounds"])
def test_change_ranges_reject_ambiguous_pages(mutation):
    values = markers()
    if mutation == "unpaired":
        values.pop()
    elif mutation == "duplicate":
        values += markers()
    elif mutation == "reversed":
        values[1]["page"] = 1
    else:
        values[1]["page"] = 6
    with pytest.raises(ValueError):
        page_ranges(values, 5)


def test_page_report_rejects_a_pdf_from_another_build(tmp_path):
    pytest.importorskip("pypdf")
    pdf = tmp_path / "x.pdf"
    pdf.write_bytes(b"not the expected PDF")
    (tmp_path / "manifest.json").write_text(json.dumps({"pdf_sha256": "0" * 64}), encoding="utf-8")
    with pytest.raises(ValueError, match="does not match"):
        verified_pdf(pdf)
