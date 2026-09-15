"""Publication register data must retain real ABI values and complete bit layouts."""

from __future__ import annotations

import copy
import re
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from publications.register_reference import (  # noqa: E402
    collect_registers,
    number,
    refine_fields,
    source_model,
    validate_reference,
)


@pytest.fixture(scope="module")
def reference():
    if not (ROOT / "rtl/managed/clusterip/rtc/rtl/rtc_reg.sv").exists():
        pytest.skip("publication setup is required for managed IP documentation")
    return collect_registers()


def test_current_apu_interface_advertises_the_expanded_p5_profile(reference):
    registers = {r["name"]: r for r in reference["apu"]["registers"]}
    constants = (ROOT / "crt/include/retrosoc/hal/apu_regs.h").read_text(
        encoding="utf-8"
    )
    assert re.search(r"RS_APU_IP_VERSION_VALUE\s+UINT32_C\(0x00010001\)", constants)
    assert re.search(r"RS_APU_CAPABILITY0_IMPLEMENTED\s+UINT32_C\(0x000001BD\)", constants)
    assert re.search(r"RS_APU_CAPABILITY1_IMPLEMENTED\s+UINT32_C\(0x01827020\)", constants)
    assert "V1.1" in registers["IP_VERSION"]["description"]
    assert "32 KiB" in registers["CAPABILITY1"]["description"]


def test_repeated_banks_keep_their_real_instance_ranges(reference):
    usb = {g["id"]: g for g in reference["usb2"]["groups"]}
    assert (usb["endpoint"]["base"], usb["endpoint"]["stride"], usb["endpoint"]["count"]) == (
        0x200,
        0x40,
        8,
    )
    assert (usb["channel"]["base"], usb["channel"]["stride"], usb["channel"]["count"]) == (
        0x500,
        0x40,
        16,
    )
    clint = {g["id"]: g for g in reference["aclint"]["groups"]}
    assert clint["compare"]["count"] == 2
    assert clint["compare"]["stride"] == 8


def test_gpio_windows_are_not_collapsed_into_one_register_table(reference):
    values = {r["key"]: r for r in reference["gpio"]["registers"]}
    assert values["user.INTR_STATE"]["offset"] == 0x14
    assert values["admin.INTR_STATE"]["offset"] == 0x60


def test_field_overlap_and_missing_bits_are_rejected(reference):
    specimen = {"uart": copy.deepcopy(reference["uart"])}
    specimen["uart"]["registers"][0]["fields"][0]["msb"] = 32
    with pytest.raises(ValueError, match="bit layout"):
        validate_reference(specimen)
    specimen = {"uart": copy.deepcopy(reference["uart"])}
    specimen["uart"]["registers"][0]["fields"].pop()
    with pytest.raises(ValueError, match="bit layout"):
        validate_reference(specimen)


def test_duplicate_offsets_are_rejected_inside_a_bank(reference):
    specimen = {"uart": copy.deepcopy(reference["uart"])}
    specimen["uart"]["registers"][1]["offset"] = specimen["uart"]["registers"][0]["offset"]
    with pytest.raises(ValueError, match="duplicate or unaligned"):
        validate_reference(specimen)


def test_reset_disagreement_and_field_overflow_are_rejected(reference):
    specimen = {"uart": copy.deepcopy(reference["uart"])}
    register = specimen["uart"]["registers"][0]
    register["reset"] = "0x100000000"
    with pytest.raises(ValueError, match="reset outside"):
        validate_reference(specimen)
    register["reset"] = register["rtl_reset"]
    register["fields"][0]["reset"] = "0x100000000"
    with pytest.raises(ValueError, match="reset outside"):
        validate_reference(specimen)


def test_constant_reader_does_not_execute_source_text():
    assert number("8'(DEPTH / 2)", {"DEPTH": 16}) == 8
    assert number("(DEPTH > 4) ? 32'd4 : DEPTH - 1", {"DEPTH": 16}) == 4
    assert number("(32'd1 << 0) |\n (32'd1 << 8)") == 0x101
    with pytest.raises(ValueError):
        number("__import__('os').system('echo forbidden')")


def test_composite_fields_and_multiline_capability_keep_the_real_layout(reference):
    usb = {r["key"]: r for r in reference["usb2"]["registers"]}
    assert usb["main.CAPABILITY0"]["rtl_reset"] == "0x0F071FFF"
    fields = {f["name"]: (f["lsb"], f["msb"]) for f in usb["endpoint.STATUS"]["fields"]}
    assert fields["RESULT"] == (4, 7)
    assert fields["IN_TOGGLE"] == (8, 8)
    apu = next(r for r in reference["apu"]["registers"] if r["key"] == "main.ERROR_STATUS")
    assert next(f for f in apu["fields"] if f["name"] == "CODE")["msb"] == 6
    for item in reference.values():
        for register in item["registers"]:
            assert all(
                "BEGIN" not in f["name"] and ";" not in f["name"] for f in register["fields"]
            )


def test_read_predicate_is_not_mistaken_for_a_field_assignment():
    model = source_model("logic [31:0] state; if (state[3:0] == 4'd2) begin error = 1'b1; end", {})
    field = dict(lsb=0, msb=31, name="STATE", expression="state", reset="0", description="State.")
    record = dict(symbol="CTRL", name="CTRL", fields=[field])
    assert refine_fields(record, {}, {}, model) == [field]


def test_secret_apertures_do_not_claim_readback(reference):
    for entry in reference["crypto"]["registers"]:
        if entry["group"] in {"aes_key", "rsa_exponent"}:
            assert entry["access"].startswith("WO")
            assert "PSLVERR" in entry["description"]


def test_exact_register_description_wins_over_grouped_name_fragments(reference):
    status = next(r for r in reference["xpi"]["registers"] if r["key"] == "main.STATUS")
    assert "enable/busy/FIFO" in status["description"]
    assert "W1C state" not in status["description"]


def test_api_listing_contains_declarations_not_inline_function_bodies():
    import json

    content = json.loads((ROOT / "publications/datasheets/ip-content.json").read_text())
    for chapter in content.values():
        for api in chapter.get("api", []):
            assert "{" not in api["signature"]
            assert "#if" not in api["signature"]
            assert api["signature"].endswith(");")


def test_ip_page_validation_rejects_a_shared_start_page():
    from publications.build_datasheet import validate_page_map

    items = [
        {"id": "a", "kind": "ip-start", "page": 1},
        {"id": "a", "kind": "ip-end", "page": 1},
        {"id": "b", "kind": "ip-start", "page": 1},
        {"id": "b", "kind": "ip-end", "page": 2},
    ]
    with pytest.raises(ValueError, match="new page"):
        validate_page_map(items, [{"id": "a"}, {"id": "b"}])
