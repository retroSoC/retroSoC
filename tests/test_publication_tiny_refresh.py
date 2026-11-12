"""Tiny v0.2 rejects product leakage, missing interfaces and false evidence."""
from __future__ import annotations

import copy
from pathlib import Path
import shutil

import pytest

from publications import tiny_reference as tiny
from publications.build_tiny_datasheet import validate_rendered_registers
from publications.tiny_v02_reference import package_rows, validate_catalog

ROOT = Path(__file__).resolve().parents[1]


@pytest.fixture(scope="module")
def data():
    return tiny.collect(tiny.read(ROOT / tiny.BOOK / "tiny.json"))


def test_current_and_compatibility_profile_have_distinct_discovery(data):
    main, compatibility = data["facts"], data["compatibility"][0]
    assert main["profile"]["PDK"] == "ICS55"
    assert (main["archinfo"]["TECHNOLOGY"], main["archinfo"]["FEATURES0"]) == (0x02040037, 0x7FFF)
    assert (compatibility["archinfo"]["TECHNOLOGY"], compatibility["archinfo"]["FEATURES0"]) == (0x02010082, 0x7FFE)
    registers = tiny.collect_registers(compatibility)
    rcu = next(r for r in registers["rcu"]["registers"] if r["name"] == "CAPABILITY")
    assert tiny.registers.number(rcu["reset"]) == 0x1A03
    assert len(data["catalog"]) == 23
    assert not any(p.startswith("rtl/mini/") for p in data["source_paths"])


@pytest.fixture
def fact_tree(tmp_path):
    paths = [tiny.TOP, tiny.SRAM, tiny.CPU, tiny.CPU_MEM, tiny.RESET_TREE, tiny.ARCHINFO,
             tiny.SYSCTRL, tiny.MAP, tiny.TOPOLOGY, *tiny.PROFILES]
    for name in paths:
        target = tmp_path / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(ROOT / name, target)
    return tmp_path


@pytest.mark.parametrize("before,after", [
    (".NumChannels          (8)", ".NumChannels          (4)"),
    (".EnableStreams        (1'b1)", ".EnableStreams        (1'b0)"),
    (".EnableOriginQualifier(1'b1)", ".EnableOriginQualifier(1'b0)"),
    (".SupportedRequests    (32'h0003_39ff)", ".SupportedRequests    (32'h0000_3fff)"),
])
def test_dma_integration_drift_cannot_reuse_publication(fact_tree, before, after):
    path = fact_tree / tiny.TOP
    text = path.read_text(encoding="utf-8")
    assert before in text
    path.write_text(text.replace(before, after), encoding="utf-8")
    with pytest.raises(ValueError, match="DMA parameters"):
        tiny.facts(fact_tree)


def test_main_profile_cannot_silently_disable_pll(fact_tree):
    path = fact_tree / "configs/ci/ics55-tiny.mk"
    text = path.read_text(encoding="utf-8")
    path.write_text(text.replace("HAVE_PLL          := YES", "HAVE_PLL          := NO"), encoding="utf-8")
    with pytest.raises(ValueError, match="profile changed"):
        tiny.facts(fact_tree)


def test_ppalite_integration_cannot_fall_back_to_standalone_capability(fact_tree):
    path = fact_tree / tiny.TOP
    text = path.read_text(encoding="utf-8")
    before = ".CapabilityValue(32'h0000_03ff)"
    assert before in text
    path.write_text(text.replace(before, ".CapabilityValue(32'h0000_00ff)"), encoding="utf-8")
    with pytest.raises(ValueError, match="PPALite integration parameters"):
        tiny.facts(fact_tree)


def test_ppalite_uses_camera_transport_without_another_master(data):
    assert data["facts"]["ppalite"] == {"ExternalRoute": 1, "CapabilityValue": 0x3FF}
    assert data["facts"]["dma"]["EnablePpaliteGuard"] == 1
    assert data["facts"]["dma"]["RequestMask"] == 0x339FF
    assert data["facts"]["dma"]["NumChannels"] == 8
    pp = {r["name"]: r for r in data["registers"]["ppalite"]["registers"]}
    assert len(pp) == 40 and tiny.registers.number(pp["DMA_BINDING"]["reset"]) == 0x10B02
    assert pp["COMMAND"]["access"] == "WO"
    assert next(r for r in data["interrupts"] if r["name"] == "ppalite")["core_bit"] == 27
    cap = next(r for r in data["registers"]["rcu"]["registers"] if r["name"] == "TARGET_CAP")
    assert tiny.registers.number(cap["reset"]) == 0x37FFF


@pytest.mark.parametrize("path", ["configs/ci/ihp130.mk", "configs/ci/ics55.mk", "configs/cluster/mini-mpw.mk"])
def test_other_products_are_not_tiny_compatibility(path):
    with pytest.raises(ValueError, match="reviewed product"):
        tiny.facts(profile_path=path)


@pytest.mark.parametrize("mutation", ["missing_irq", "duplicate_irq", "rcu_window", "rcu_register", "retired_uart"])
def test_catalog_rejects_incomplete_or_ambiguous_ownership(data, mutation):
    catalog, reference = copy.deepcopy(data["catalog"]), copy.deepcopy(data["registers"])
    rcu = next(row for row in catalog if row["id"] == "rcu")
    if mutation == "missing_irq":
        rcu["irqs"] = []
    elif mutation == "duplicate_irq":
        catalog[0]["irqs"].append("rcu")
    elif mutation == "rcu_window":
        rcu["regions"] = ["APB4_SYSCTRL"]
    elif mutation == "rcu_register":
        reference["rcu"]["registers"][0]["offset"] = reference["sysctrl"]["registers"][0]["offset"]
    else:
        catalog[0]["id"] = "uart1"
    topology = tiny.read(ROOT / tiny.TOPOLOGY)
    with pytest.raises(ValueError, match="interrupt catalog|RCU|duplicate|absent peripheral"):
        validate_catalog(catalog, reference, data["regions"], topology)


def test_rcu_subregion_and_repeated_register_addresses_are_unique(data):
    records = data["register_index"]
    assert len({r["address"] for r in records}) == len(records)
    rcu = [int(r["address"], 16) for r in records if r["ip"] == "rcu"]
    assert rcu == list(range(0x1000B100, 0x1000B160, 4))
    assert {r["index"] for r in records if r["family"] == "dma" and r["key"].startswith("ch.")} == set("01234567")


def test_discovery_discrepancies_remain_visible(data):
    def reg(family, name):
        return next(r for r in data["registers"][family]["registers"] if r["name"] == name)
    assert tiny.registers.number(reg("dma", "IP_VERSION")["reset"]) == 0x20002
    assert tiny.registers.number(reg("dma", "SUPPORTED_REQUESTS")["reset"]) == 0x339FF
    assert "truncat" in reg("dma", "CAPABILITY")["description"]
    assert tiny.registers.number(reg("spi", "CAPABILITY")["reset"]) == 0x3F7F
    assert "discrepancy" in reg("spi", "CAPABILITY")["description"]
    gpio = reg("gpio", "PAD_CAPABILITY")
    assert tiny.registers.number(gpio["reset"]) == 7


def test_spi_extended_selector_binding_is_required(tmp_path):
    contract = tiny.read(ROOT / tiny.BOOK / "source-contract.json")
    binding = next(b for b in contract["bindings"] if b["file"] == "crt/include/retrosoc/hal/dma.h")
    target = tmp_path / binding["file"]
    target.parent.mkdir(parents=True)
    text = (ROOT / binding["file"]).read_text(encoding="utf-8")
    target.write_text(text.replace("0x02000000", "0x01000000"), encoding="utf-8")
    with pytest.raises(ValueError, match="behavior binding changed"):
        tiny.require_snippets(tmp_path, binding["file"], binding["text"])


def test_xpi_write_one_clear_is_not_erased_by_zero_readback(data):
    register = next(r for r in data["registers"]["xpi"]["registers"] if r["name"] == "PERF_CTRL")
    clear = next(f for f in register["fields"] if f["name"] == "CLEAR")
    assert (clear["lsb"], clear["msb"], clear["reset"]) == (1, 1, "0x0")
    assert "reads zero" in clear["description"]
    assert any("s_perf_clear" in b["text"] for b in register["source_bindings"])


def test_dma_consumer_widths_and_error_packing_are_documented(data):
    regs = {r["key"]: r for r in data["registers"]["dma"]["registers"]}
    for key, name, low, high in [("ch.CFG", "KIND", 0, 2),
                                 ("ch.REQUEST_SEL", "REQUEST", 0, 4),
                                 ("ch.BURST_CFG", "MAX_BEATS", 0, 4),
                                 ("ch.ERROR_STATUS", "AXI_RESPONSE", 4, 5),
                                 ("ch.ERROR_STATUS", "STREAM_LAST", 8, 8)]:
        field = next(f for f in regs[key]["fields"] if f["name"] == name)
        assert (field["lsb"], field["msb"]) == (low, high)
        assert regs[key]["source_bindings"]
    assert "reject" in regs["ch.REQUEST_SEL"]["fields"][1]["description"]


def test_tiny_runtime_clock_and_fifo_zero_bits_are_instance_bound(data):
    pwm = next(r for r in data["registers"]["pwm"]["registers"] if r["name"] == "CLOCK_HZ")
    assert "Dynamic" in pwm["reset"]
    assert any("UseRuntimeClockHz(1'b1)" in b["text"] for b in pwm["source_bindings"])
    for family, reserved in [("uart", [(7, 15), (23, 31)]), ("i2c", [(8, 15), (24, 31)])]:
        reg = next(r for r in data["registers"][family]["registers"] if r["name"] == "FIFO_LEVEL")
        assert [(f["lsb"], f["msb"]) for f in reg["fields"] if f["name"] == "Reserved"] == reserved


def test_rtc_and_archinfo_values_do_not_inherit_mini_defaults(data):
    rtc = next(r for r in data["registers"]["rtc"]["registers"] if r["name"] == "SECOND_CYCLES")
    assert tiny.registers.number(rtc["reset"]) == 24000000
    assert tiny.registers.number(rtc["fields"][0]["reset"]) == 24000000
    assert any("RTC_CLOCK_HZ(24_000_000)" in b["text"] for b in rtc["source_bindings"])
    info = {r["name"]: r for r in data["registers"]["archinfo"]["registers"]}
    assert info["CONFIG_ID"]["fields"][0]["name"] == "CONFIG_ID"
    assert [f["name"] for f in info["BUILD_STATUS"]["fields"]] == [
        "DIRTY", "LOCK_VALID", "RELEASE", "SOURCE_KNOWN", "Reserved"]
    assert info["BUILD_STATUS"]["fields"][-1]["reset"] == "0"
    assert tiny.registers.number(info["TECHNOLOGY"]["reset"]) == 0x02040037
    assert "ICS55" in info["TECHNOLOGY"]["fields"][1]["description"]
    assert tiny.registers.number(info["DEVICE_ID_STATUS"]["reset"]) == 0x1000
    assert all("APB error" in info[f"DEVICE_ID{i}"]["reset"] for i in range(4))


@pytest.mark.parametrize("duplicate", [False, True])
def test_pdf_cannot_omit_or_repeat_a_register(data, duplicate):
    rows = [dict(kind="tiny-register", family=n, key=r["key"])
            for n, ref in data["registers"].items() for r in ref["registers"]]
    if duplicate:
        rows.append(rows[0])
    else:
        rows.pop()
    with pytest.raises(ValueError, match="omitted or duplicated"):
        validate_rendered_registers(data, rows)


def test_historical_evidence_cannot_be_promoted_by_publication(data):
    evidence = copy.deepcopy(data["evidence"])
    evidence["current_commit_reports"].append({"passed": True})
    with pytest.raises(ValueError, match="matching independently reviewed reports"):
        tiny.validate_evidence(evidence)


def test_package_target_is_separate_from_current_pad_inventory(data):
    assert len(package_rows(ROOT)) == 32
    assert len(data["pads"]) == 52
    prose = "\n".join(path.read_text(encoding="utf-8") for path in (ROOT / tiny.BOOK).rglob("*.typ"))
    assert "not an implemented bond map" in prose
    assert "current ASIC compatibility wrapper" in prose
