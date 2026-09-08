"""Software-derived publication claims and chapter freeze must fail on meaningful drift."""
from __future__ import annotations

import copy
import json
import shutil
from pathlib import Path

import pytest

from publications import software_reference as sr
from publications.structure_reference import content_text, structure_entries, validate_structure

ROOT = Path(__file__).resolve().parents[1]
RAW = json.loads((ROOT / "publications/datasheets/system-reference.json").read_text(encoding="utf-8"))
SPEC = RAW["software"]


@pytest.fixture
def source_tree(tmp_path):
    for relative in sr.dependencies(SPEC):
        target = tmp_path / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(ROOT / relative, target)
    return tmp_path


def replace(root: Path, relative: str, old: str, new: str) -> None:
    path = root / relative
    text = path.read_text(encoding="utf-8")
    assert old in text
    path.write_text(text.replace(old, new), encoding="utf-8")


def test_real_software_records_separate_startup_and_irq_selections():
    result = sr.collect_software(ROOT, SPEC)
    rows = {r["app"]: r for r in result["profiles"]}
    assert rows["bringup"]["have_csr"] == "NO"
    assert rows["hp_boot"]["have_csr"] == "YES"
    assert rows["hp_boot"]["startup"] == rows["bringup"]["startup"] == "crt/arch/riscv/startup.S"
    assert rows["debug"]["startup"] == "app/apps/debug/startup.S"
    assert rows["xpi_flash_loader"]["startup"] == "app/apps/xpi_flash_loader/startup.S"
    assert result["irq"]["enabled_core_causes"] == ["IRQ_M_SOFT", "IRQ_M_TIMER"]
    assert result["irq"]["counts"]["RS_EXTERNAL_IRQ_COUNT"] == 30
    assert sr.dependencies(result) == sr.dependencies(SPEC)


def test_function_extraction_ignores_calls_comments_and_string_braces():
    source = '''
    // int target(void) { return 5; }
    static int target(void) { log("}"); return 3; }
    int main(void) { if (!target()) { return 1; } return 0; }
    '''
    assert sr.function_body(source, "target").strip() == 'log("}"); return 3;'


@pytest.mark.parametrize("source", ["int main(void);", "int main(void) {", "int main(void) {} int main(void) {}\n"])
def test_function_extraction_rejects_unsupported_definitions(source):
    with pytest.raises(ValueError):
        sr.function_body(source, "main")


@pytest.mark.parametrize("relative,old,new", [
    ("rtl/mini/mk/software.mk", "CRT_SRCS := $(APP_CRT_SRCS)", "CRT_SRCS += $(APP_CRT_SRCS)"),
    ("crt/arch/riscv/startup.S", "beqz t1, PSRAM_READY_WAIT", "beqz t1, main_start"),
    ("crt/arch/riscv/startup.S", "call     _premain_init", "call     other_premain"),
    ("crt/arch/riscv/system_irq.S", "SAVE_CSR_CONTEXT\n", "SAVE_CHANGED_CONTEXT\n"),
    ("crt/src/core/system_irq_handler.c", "return RS_ENOTSUP;", "return RS_OK;"),
    ("app/ports/linux/linux/retrosoc_hp.config", "CONFIG_SMP=n", "CONFIG_SMP=y"),
    ("scripts/build_hp_linux.py", "rootfs_source.stat().st_size", "0"),
    ("crt/src/hal/crypto.c", "RS_CRYPTO_AES_ECB, false", "RS_CRYPTO_AES_CBC, false"),
])
def test_reviewed_behavior_drift_fails_source_bindings(source_tree, relative, old, new):
    replace(source_tree, relative, old, new)
    with pytest.raises(ValueError):
        sr.collect_software(source_tree, SPEC)


def test_changed_startup_requires_source_inventory(source_tree):
    replace(source_tree, "app/apps/debug/app.mk", "app/apps/debug/startup.S", "app/apps/debug/other.S")
    with pytest.raises(ValueError, match="startup or linker"):
        sr.runtime_profiles(source_tree, SPEC)


def test_profile_literal_is_required():
    with pytest.raises(ValueError, match="literal"):
        sr.assignment("APP := $(DEFAULT_APP)\n", "APP")
    with pytest.raises(ValueError, match="duplicate"):
        sr.assignment("APP := bringup\nAPP := shell\n", "APP")


def test_application_results_keep_early_return_and_repeated_stage_values():
    bringup, smoke = [sr.application_diagnostics(ROOT, row) for row in SPEC["applications"]]
    assert [(r["kind"], r["code"]) for r in bringup["stages"]] == [
        ("return", 1), ("test-fail", 1), ("test-fail", 2), ("test-fail", 3), ("test-pass", 0)]
    assert [r["id"] for r in smoke["stages"] if r["code"] == 12] == ["sram", "usb"]
    assert [r["id"] for r in smoke["stages"] if r["code"] == 13] == ["monitor-start", "monitor-check"]
    assert len(smoke["stages"]) == 17


@pytest.mark.parametrize("mutation", ["omit", "duplicate-stage", "value", "scope", "trigger"])
def test_application_inventory_cannot_hide_or_relabel_a_branch(mutation):
    app = copy.deepcopy(SPEC["applications"][1])
    if mutation == "omit":
        app["stages"].pop(6)
    elif mutation == "duplicate-stage":
        app["stages"][6]["id"] = app["stages"][4]["id"]
    elif mutation == "value":
        app["stages"][5]["code"] = 99
    elif mutation == "scope":
        app["stages"][0]["kind"] = "return"
    else:
        app["stages"][5]["trigger"] = "unrelated_check("
    with pytest.raises(ValueError):
        sr.application_diagnostics(ROOT, app)


def test_changed_application_return_is_not_reported_as_test_status(source_tree):
    replace(source_tree, "app/apps/bringup/main.c", "return 1;", "return 2;")
    with pytest.raises(ValueError, match="result branches"):
        sr.application_diagnostics(source_tree, SPEC["applications"][0])


def test_unreviewed_return_expression_is_not_silently_omitted(source_tree):
    replace(source_tree, "app/apps/bringup/main.c", "return 1;", "return dynamic_result;")
    with pytest.raises(ValueError, match="return expression"):
        sr.application_diagnostics(source_tree, SPEC["applications"][0])


def test_linux_platform_uses_source_values_and_order():
    data = sr.linux_platform(ROOT)
    assert (data["hart_id"], data["timebase_hz"], data["cbom_bytes"]) == (1, 1000000, 64)
    assert data["initrd_start"] == data["initrd_template_end"] == 0x39000000
    assert data["ready_writes"][-1] == {"address": "0x1001902C", "value": "0x00000001"}
    assert data["ready_writes"][1]["value"] == "0x4C4E5801"


@pytest.mark.parametrize("relative,old,new", [
    ("app/ports/linux/linux/retrosoc_hp.dts", "cpu@1", "cpu@0"),
    ("app/ports/linux/linux/retrosoc_hp.dts", "linux,initrd-end = <0x39000000>", "linux,initrd-end = <0x39100000>"),
    ("app/ports/linux/opensbi/retrosoc_hp/platform.c", ".mtime_freq = 1000000UL", ".mtime_freq = 2000000UL"),
    ("app/ports/linux/rootfs-overlay/etc/init.d/S99retrosoc-hp", "0x10019024 32 0x4C4E5801", "0x10019024 32 0x4C4E5802"),
])
def test_linux_consistency_and_ready_event_drift_fail(source_tree, relative, old, new):
    replace(source_tree, relative, old, new)
    with pytest.raises(ValueError):
        sr.linux_platform(source_tree)


def test_ready_request_cannot_move_before_payload(source_tree):
    path = source_tree / "app/ports/linux/rootfs-overlay/etc/init.d/S99retrosoc-hp"
    lines = path.read_text().splitlines()
    first = next(i for i, line in enumerate(lines) if "devmem" in line)
    lines[first], lines[first + 3] = lines[first + 3], lines[first]
    path.write_text("\n".join(lines))
    with pytest.raises(ValueError, match="sequence"):
        sr.linux_platform(source_tree)


def test_ready_text_order_cannot_be_silently_reversed(source_tree):
    path = source_tree / "app/ports/linux/rootfs-overlay/etc/init.d/S99retrosoc-hp"
    text = path.read_text()
    message = '        echo "retroSoC HP Linux ready"'
    lines = [line for line in text.splitlines() if 'echo "retroSoC HP Linux ready"' not in line]
    lines.append(message)
    path.write_text("\n".join(lines))
    with pytest.raises(ValueError, match="message/publication"):
        sr.linux_platform(source_tree)


@pytest.fixture
def structure():
    headings = [
        {"level": 1, "title": "System", "label": "<system>", "outlined": True, "page": 1},
        {"level": 2, "title": "Peripherals", "label": "none", "outlined": True, "page": 2},
        {"level": 4, "title": "UART", "label": "<uart>", "outlined": True, "page": 3},
        {"level": 3, "title": "Internal explanation", "label": "none", "outlined": True, "page": 4},
        {"level": 4, "title": "SPI", "label": "<spi>", "outlined": True, "page": 5},
    ]
    index = [{"id": "uart"}, {"id": "spi"}]
    contract = {"schema_version": 1, "state": "frozen", "ip_ids": ["uart", "spi"],
                "entries": structure_entries(headings, {"uart", "spi"})}
    return contract, headings, index


def test_structure_allows_page_changes_and_deeper_explanations(structure):
    contract, headings, index = structure
    headings[3]["title"] = "Expanded explanation"
    headings.insert(4, {"level": 3, "title": "New example", "label": "<new-example>", "outlined": True})
    for row in headings:
        row["page"] = 100
    validate_structure(contract, headings, index)


@pytest.mark.parametrize("mutation", ["rename", "delete", "add", "reorder", "level", "anchor", "ip-rename", "ip-move", "index"])
def test_structure_rejects_frozen_entry_changes(structure, mutation):
    contract, headings, index = structure
    if mutation == "rename":
        headings[0]["title"] = "Changed System"
    elif mutation == "delete":
        headings.pop(1)
    elif mutation == "add":
        headings.append({"level": 2, "title": "New section", "label": "none"})
    elif mutation == "reorder":
        headings[0], headings[1] = headings[1], headings[0]
    elif mutation == "level":
        headings[1]["level"] = 3
    elif mutation == "anchor":
        headings[0]["label"] = "<changed>"
    elif mutation == "ip-rename":
        headings[2]["title"] = "Different UART"
    elif mutation == "ip-move":
        headings[2], headings[4] = headings[4], headings[2]
    else:
        index.reverse()
    with pytest.raises(ValueError, match="frozen"):
        validate_structure(contract, headings, index)


def test_heading_formatting_does_not_change_visible_structure():
    value = {"func": "sequence", "children": [{"func": "text", "text": "UART"},
             {"func": "space"}, {"func": "strong", "body": {"func": "text", "text": "(UART0)"}}]}
    assert content_text(value) == "UART (UART0)"
