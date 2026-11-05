"""A core migration must not silently retain the previous integration or evidence."""
from __future__ import annotations

import copy
import json
import re
import shutil
from pathlib import Path

import pytest

from publications import c906_reference as c906
from publications import implementation_reference as implementation
from publications import system_reference as system
from publications.chapter_reference import apply_prose_corrections, section_text
from publications.boot_acceptance_reference import (
    BOOT_SOURCE, SOURCES as BOOT_SOURCES, collect_boot_acceptance, split_npu_conditions,
)
from publications.mini_integration_reference import collect_mini_bindings, selected_profile
from publications.software_reference import function_body

ROOT = Path(__file__).resolve().parents[1]
REFERENCE = json.loads((ROOT / "publications/datasheets/system-reference.json").read_text(encoding="utf-8"))
IDS = {row["id"] for row in REFERENCE["support"]}
LIMITS = {row["id"] for row in REFERENCE["limitations"]}


@pytest.fixture
def c906_tree(tmp_path):
    paths = set(c906.SOURCES)
    vendor = c906.vendor_root(ROOT).relative_to(ROOT)
    paths.update((vendor / path).as_posix() for path in c906.VENDOR_INPUTS)
    for relative in paths:
        target = tmp_path / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(ROOT / relative, target)
    return tmp_path


def test_selected_core_and_source_set_keep_the_real_integration():
    facts = c906.collect_c906(ROOT)
    assert (facts["master_slot"], facts["retired_slot"], facts["plic_offset"]) == (0, 1, 16)
    assert (facts["core_address_bits"], facts["physical_address_bits"]) == (40, 32)
    paths = c906.source_paths(ROOT, validate=True)
    assert set(c906.SOURCES) <= paths
    assert len([path for path in paths if path.startswith("rtl/mini/ip_overrides/")]) == 14
    assert not any("vexiiriscv" in path.lower() for path in paths)


@pytest.mark.parametrize("value", ["rv64imafdc_zicbom_max", "rv32imafdc_zicbom_max"])
def test_retired_mini_generator_selector_is_rejected_even_for_rv64(value):
    with pytest.raises(ValueError, match="profile changed"):
        collect_mini_bindings(ROOT, selected_profile(ROOT) | {"HP_CONFIG": value})


@pytest.mark.parametrize("kind", ["retired-read", "retired-write", "old-master", "old-window"])
def test_retired_ports_and_windows_cannot_be_restored_by_metadata(c906_tree, kind):
    relative = "rtl/mini/address_map/memory_map.json" if kind == "old-window" else "rtl/mini/integration/soc_topology.json"
    path = c906_tree / relative
    data = json.loads(path.read_text(encoding="utf-8"))
    if kind == "old-window":
        next(row for row in data["regions"] if row["symbol"] == "HP_C906_SYS")["symbol"] = "HP_ACLINT"
    elif kind == "old-master":
        data["data_master_policies"][0]["name"] = "hp_icache"
    else:
        data["data_master_policies"][1]["read_targets" if kind == "retired-read" else "write_targets"] = ["sram"]
    path.write_text(json.dumps(data), encoding="utf-8")
    with pytest.raises(ValueError, match="OpenC906.*changed"):
        c906.collect_c906(c906_tree)


@pytest.mark.parametrize("relative,before,after,error", [
    ("app/ports/linux/linux/retrosoc_hp.dts", '"rv64i"', '"rv32i"', "ISA/MMU"),
    ("app/ports/linux/linux/retrosoc_hp.dts", '"zicsr", "zifencei"', '"zicsr", "zifencei", "zicbom"', "ISA/MMU"),
    ("rtl/mini/top/hp_core_wrapper.sv", ".DATA_WIDTH(128)", ".DATA_WIDTH(64)", "identity"),
    ("rtl/mini/top/hp_core_wrapper.sv", ".pad_cpu_sys_cnt       (time_i)", ".pad_cpu_sys_cnt       (64'd0)", "binding"),
    ("rtl/mini/top/soc_data_plane.sv", "axi4_master_idle u_hp_retired_idle", "axi4_master_idle u_other_idle", "binding"),
    ("app/ports/linux/opensbi/retrosoc_hp/platform.c", "csr_clear(RETROSOC_HP_CSR_MXSTATUS, RETROSOC_HP_MXSTATUS_MAEE);", "", "initialization order"),
    ("app/ports/linux/opensbi/retrosoc_hp/platform.c", ".irqchip_init = fdt_irqchip_init,", "", "PLIC initialization"),
    ("app/ports/linux/opensbi/retrosoc_hp/platform.c", "0x0C000000UL", "0x08000000UL", "timer address map"),
    ("app/ports/linux/opensbi/retrosoc_hp/platform.c", "0x4000UL", "0x4008UL", "timer address map"),
    ("app/ports/linux/linux/retrosoc_hp.dts", "<0x0c000000 0x00010000>", "<0x08000000 0x00010000>", "interrupt address map"),
    ("app/ports/linux/linux/retrosoc_hp.dts", "<0x08000000 0x04000000>", "<0x0c000000 0x04000000>", "interrupt address map"),
])
def test_c906_source_drift_is_rejected(c906_tree, relative, before, after, error):
    path = c906_tree / relative
    text = path.read_text(encoding="utf-8")
    assert before in text
    path.write_text(text.replace(before, after), encoding="utf-8")
    with pytest.raises(ValueError, match=error):
        c906.collect_c906(c906_tree)


def test_plic_offset_comes_from_vendored_packing(c906_tree):
    path = c906.vendor_root(c906_tree) / c906.VENDOR_INPUTS[1]
    text = path.read_text(encoding="utf-8")
    assert "14'b0,l2c_plic_ecc_int_vld,1'b0" in text
    path.write_text(text.replace("14'b0,l2c_plic_ecc_int_vld,1'b0", "13'b0,l2c_plic_ecc_int_vld,1'b0"), encoding="utf-8")
    with pytest.raises(ValueError, match="PLIC source-to-ID"):
        c906.plic_offset(c906_tree)


def test_cache_default_is_checked_against_the_locked_header(c906_tree):
    path = c906.vendor_root(c906_tree) / c906.VENDOR_INPUTS[0]
    text = path.read_text(encoding="utf-8")
    path.write_text(text.replace("`define ICACHE_32K", "`define ICACHE_16K"), encoding="utf-8")
    with pytest.raises(ValueError, match="default configuration"):
        c906.collect_c906(c906_tree)


@pytest.fixture
def boot_tree(tmp_path):
    for relative in BOOT_SOURCES:
        target = tmp_path / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(ROOT / relative, target)
    return tmp_path


def test_debug_branch_is_optional_but_checked_before_release():
    facts = collect_boot_acceptance(ROOT, function_body)
    assert facts["jtag_debug_before_release"] and facts["jtag_debug_failure_code"] == 20
    source = (ROOT / BOOT_SOURCE).read_text(encoding="utf-8")
    normal, blocks = split_npu_conditions(function_body(source, "main"))
    assert "rs_sysctrl_select_hp_debug(true)" not in normal
    assert any(condition == "defined(RS_HP_JTAG_DEBUG)" for condition, _ in blocks)


@pytest.mark.parametrize("mutation", ["missing", "after-release", "wrong-result"])
def test_jtag_branch_cannot_be_ignored_or_moved(boot_tree, mutation):
    path = boot_tree / BOOT_SOURCE
    text = path.read_text(encoding="utf-8")
    block = re.search(r"#if defined\(RS_HP_JTAG_DEBUG\).*?#endif", text, re.S)[0]
    if mutation == "wrong-result":
        text = text.replace(block, block.replace("UINT8_C(20)", "UINT8_C(19)"))
    else:
        text = text.replace(block, "")
        if mutation == "after-release":
            position = text.rfind("    rs_test_finish(RS_TEST_PASSED, UINT8_C(0));")
            assert position > 0
            text = text[:position] + block + "\n" + text[position:]
    path.write_text(text, encoding="utf-8")
    with pytest.raises(ValueError, match="HP JTAG debug"):
        collect_boot_acceptance(boot_tree, function_body)


def test_old_core_pass_cannot_qualify_the_current_snapshot():
    reference = copy.deepcopy(REFERENCE)
    row = next(row for row in reference["support"] if row["id"] == "hp-plic")
    row["verification"] = "Reported pass"
    row["reports"] = [{"path": "docs/hp-rv64-validation.md", "profile": "configs/ci/ihp130-hp.mk",
                       "revision": "95c243b7095547f2ada5166a1cc8e8a3a9345fed",
                       "stage": "simulation", "result": "pass"}]
    with pytest.raises(ValueError, match="does not cover the reviewed snapshot"):
        system.validate_reference(reference, IDS, ROOT)


def test_macro_model_selection_is_not_physical_qualification():
    spec = copy.deepcopy(REFERENCE["product_details"])
    spec["c906_technology"][0]["evidence"] = "Silicon qualified"
    with pytest.raises(ValueError, match="C906 macro qualification"):
        implementation.validate_details(spec, IDS, ROOT, LIMITS)


@pytest.mark.parametrize("mutation", [None, "missing-header", "ambiguous-header", "missing-binding",
                                      "missing-cell", "ambiguous-cell"])
def test_imported_resource_table_distinguishes_soc_sources_from_plic_ids(mutation):
    content = json.loads((ROOT / "publications/datasheets/ip-content.json").read_text(encoding="utf-8"))
    sections = section_text(ROOT / "docs/ip/resource-controller.md", ["Scope"])
    corrections = copy.deepcopy(content["resource"]["prose_corrections"])
    table = next(block for block in sections[0]["blocks"] if block["kind"] == "table")
    if mutation == "missing-header":
        table["headers"][-1] = "Unknown interrupt index"
    elif mutation == "ambiguous-header":
        sections[0]["blocks"].append(copy.deepcopy(table))
    elif mutation == "missing-binding":
        corrections[0]["bindings"] = []
    elif mutation == "missing-cell":
        table["rows"][-1][1] = "Unknown resource"
    elif mutation == "ambiguous-cell":
        table["rows"].append(copy.deepcopy(table["rows"][-1]))
    if mutation:
        with pytest.raises(ValueError, match="prose correction"):
            apply_prose_corrections(sections, corrections, ROOT)
    else:
        apply_prose_corrections(sections, corrections, ROOT)
        assert table["headers"][-1] == "HP SoC source (PLIC ID = source + 16)"
        assert table["rows"][-1][1] == "NPU execution engine"
        assert table["rows"][-2][-1] == "11" and table["rows"][-1][-1] == "12"
        prose = json.dumps(sections)
        assert "PLIC ID 27" in prose and "PLIC ID 28" in prose
