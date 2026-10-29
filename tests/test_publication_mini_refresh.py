"""Reject silent prose loss and reusable/Tiny defaults in the Mini reference."""
from __future__ import annotations

import copy
import json
import shutil
from pathlib import Path

import pytest

from publications.chapter_reference import apply_prose_corrections, section_text
from publications.mini_integration_reference import (
    SOURCES, collect_mini_bindings, selected_profile, validate_register_bindings,
)
from publications.register_reference import (
    annotation_sources, collect_registers, number, refine_fields, reset_of, select_conditionals, source_model,
    validate_reference,
)

ROOT = Path(__file__).resolve().parents[1]


@pytest.mark.parametrize("text,titles", [
    ("## Renamed\nBody\n", ["Old title"]),
    ("## ABI\nFirst\n## ABI\nSecond\n", ["ABI"]),
    ("## ABI\nBody\n", ["ABI", "ABI"]),
])
def test_explicit_source_sections_cannot_silently_disappear_or_duplicate(tmp_path, text, titles):
    path = tmp_path / "contract.md"
    path.write_text(text, encoding="utf-8")
    with pytest.raises(ValueError, match="publication section"):
        section_text(path, titles)


def test_source_section_keeps_children_but_not_next_peer(tmp_path):
    path = tmp_path / "contract.md"
    path.write_text("## ABI\nKeep.\n### Fields\nKeep too.\n## Other\nExclude.\n", encoding="utf-8")
    sections = section_text(path, ["ABI"])
    assert len(sections) == 1
    assert [b.get("text") for b in sections[0]["blocks"]] == ["Keep.", "Fields", "Keep too."]
    assert section_text(path, []) == []


@pytest.mark.parametrize("mutation", ["missing", "duplicate", "binding", "unbound"])
def test_prose_corrections_require_exact_text_and_current_executable_evidence(tmp_path, mutation):
    (tmp_path / "profile.mk").write_text("HAVE_SRAM_IF := YES\n", encoding="utf-8")
    sections = [{"blocks": [{"kind": "paragraph", "text": "Old profile."}]}]
    correction = {"before": "Old profile.", "after": "Current profile.",
                  "bindings": [{"file": "profile.mk", "text": "HAVE_SRAM_IF := YES"}]}
    good = copy.deepcopy(sections)
    apply_prose_corrections(good, [correction], tmp_path)
    assert good[0]["blocks"][0]["text"] == "Current profile."
    if mutation == "missing":
        sections[0]["blocks"][0]["text"] = "Renamed source."
    elif mutation == "duplicate":
        sections[0]["blocks"] *= 2
    elif mutation == "binding":
        (tmp_path / "profile.mk").write_text("HAVE_SRAM_IF := NO\n", encoding="utf-8")
    else:
        correction["bindings"] = []
    with pytest.raises(ValueError, match="prose correction"):
        apply_prose_corrections(sections, [correction], tmp_path)


def test_boolean_parameters_are_parsed_without_execution():
    assert number("(EnableP5 || EnableP7) ? 32'h01827020 : 32'h01827010", {"EnableP5": 1, "EnableP7": 0}) == 0x01827020
    assert number("!A && B", {"A": 0, "B": 1}) == 1
    assert number("A || B", {"A": 0, "B": 0}) == 0
    with pytest.raises(ValueError):
        number("__import__('os').getcwd()")


def test_concat_initializer_operands_do_not_redeclare_narrow_constants():
    source = "logic [7:0] RX = 16; logic [7:0] CMD = 16; logic [31:0] CAP = {9'd0, 7'h7F, RX, CMD};"
    model = source_model(source, {"RX": 16, "CMD": 16})
    assert (model["widths"]["RX"], model["widths"]["CMD"]) == (8, 8)
    assert reset_of("{9'd0, 7'h7F, RX, CMD}", model) == 0x007F1010


def test_preprocessor_branch_selection_preserves_line_numbers():
    source = "`ifdef MACRO\nmacro\n`elsif OTHER\nother\n`else\nfallback\n`endif\n"
    enabled = select_conditionals(source, {"MACRO": True, "OTHER": False})
    fallback = select_conditionals(source, {"MACRO": False, "OTHER": False})
    assert enabled.splitlines()[1] == "macro" and "fallback" not in enabled
    assert fallback.splitlines()[5] == "fallback" and "macro" not in fallback
    assert enabled.count("\n") == source.count("\n")
    nested = "`ifndef A\n`ifdef B\nyes\n`endif\n`endif\n"
    assert "yes" in select_conditionals(nested, {"A": False, "B": True})


@pytest.mark.parametrize("source,definitions", [
    ("`ifdef UNKNOWN\nx\n`endif\n", {}),
    ("`ifdef A\nx\n", {"A": True}),
    ("`else\nx\n", {}),
    ("`ifdef A\nx\n`else\ny\n`else\nz\n`endif\n", {"A": True}),
])
def test_unknown_or_malformed_guard_cannot_choose_a_capability_branch(source, definitions):
    with pytest.raises(ValueError, match="preprocessor"):
        select_conditionals(source, definitions)


@pytest.mark.parametrize("key,value", [
    ("SOC", "TINY"), ("SRAM_SIZE_KIB", "128"), ("HP_CONFIG", "rv32imafdc_zicbom_max"),
    ("ISA", "RV64IMAFDC"), ("HAVE_SRAM_MACRO", "NO"),
])
def test_wrong_product_capacity_and_hardware_firmware_isa_are_rejected(key, value):
    profile = selected_profile(ROOT) | {key: value}
    with pytest.raises(ValueError, match="profile changed"):
        collect_mini_bindings(ROOT, profile)


@pytest.fixture
def binding_tree(tmp_path):
    from publications.dev_reference import APU_CONFIGURATION_SOURCES

    for relative in set(SOURCES) | set(APU_CONFIGURATION_SOURCES):
        target = tmp_path / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(ROOT / relative, target)
    return tmp_path


@pytest.mark.parametrize("old,new", [(".NumChannels(8)", ".NumChannels(4)"),
                                      (".FifoDepth  (32)", ".FifoDepth  (32), .EnableSpi(1'b1)")])
def test_changed_dma_integration_does_not_reuse_mini_publication(binding_tree, old, new):
    path = binding_tree / "rtl/mini/top/apb4_periph.sv"
    text = path.read_text(encoding="utf-8")
    assert old in text
    path.write_text(text.replace(old, new), encoding="utf-8")
    with pytest.raises(ValueError, match="Mini DMA integration changed"):
        collect_mini_bindings(binding_tree, selected_profile(ROOT))


def test_mapped_xpi_writes_cannot_be_inferred_from_shared_tiny_support(binding_tree):
    path = binding_tree / "rtl/mini/integration/soc_topology.json"
    topology = json.loads(path.read_text(encoding="utf-8"))
    topology["data_master_policies"][0]["write_targets"].append("xpi")
    path.write_text(json.dumps(topology), encoding="utf-8")
    with pytest.raises(ValueError, match="mapped-write permission"):
        collect_mini_bindings(binding_tree, selected_profile(ROOT))


@pytest.fixture(scope="module")
def registers():
    return collect_registers()


@pytest.mark.parametrize("mutation", ["changed", "missing", "empty"])
def test_reviewed_register_fields_require_their_source_binding(tmp_path, mutation):
    source = tmp_path / "register.sv"
    source.write_text("assign status = {8'd0, count};\n", encoding="utf-8")
    annotations = {"main.STATUS": {"source_bindings": [
        {"file": "register.sv", "text": "assign status = {8'd0, count};"},
    ]}}
    assert annotation_sources(annotations, tmp_path) == ["register.sv"]
    if mutation == "changed":
        source.write_text("assign status = {16'd0, count};\n", encoding="utf-8")
    elif mutation == "missing":
        source.unlink()
    else:
        annotations["main.STATUS"]["source_bindings"] = []
    with pytest.raises(ValueError, match="register annotation"):
        annotation_sources(annotations, tmp_path)


@pytest.mark.parametrize("family,key,name,low,high", [
    ("apu", "CAPABILITY1", "MAX_RATE_KHZ", 18, 25),
    ("apu", "STREAM_STATUS", "RX_COUNT", 16, 23),
    ("apu", "OWNER_STATUS", "OWNER", 0, 1),
    ("apu", "STREAM_WATERMARK", "TX_LOW", 8, 15),
    ("apu", "RING_STATUS", "LAST_INDEX", 16, 23),
    ("apu", "JOB_STATUS", "AXI_RESPONSE", 18, 19),
    ("apu", "KWS_COEFF_STATUS", "LOCKED", 2, 2),
    ("apu", "KWS_INPUT_CONFIG", "CHANNELS", 17, 18),
    ("apu", "KWS_INPUT_CONFIG", "SAMPLE_BITS", 20, 25),
    ("crc", "CONFIG", "WIDTH", 0, 1),
    ("rng", "CONFIG", "WATERMARK", 0, 7),
    ("crypto", "RSA_CFG", "EXPONENT_BITS", 0, 11),
    ("i2s", "CLK_DIV", "MCLK", 16, 23),
    ("i2s", "FIFO_TH", "LOWBOUND", 8, 15),
    ("sysctrl", "TEST_STATUS", "CODE", 8, 15),
    ("psram", "COMMAND", "CHIP", 8, 9),
    ("sdio", "CLOCK_CTRL", "ENABLE", 0, 0),
    ("jpeg", "JOB_CONFIG", "METADATA", 3, 3),
    ("jpeg", "JOB_CONFIG", "TABLE", 8, 9),
])
def test_published_field_bounds_follow_producers_not_neighboring_macro_names(registers, family, key, name, low, high):
    register = next(r for r in registers[family]["registers"] if r["key"] == "main." + key)
    field = next(f for f in register["fields"] if f["name"] == name)
    assert (field["lsb"], field["msb"]) == (low, high)
    assert register["source_bindings"]
    if family in {"crc", "rng"}:
        assert "LOCK" not in {f["name"] for f in register["fields"]}


def test_explicit_bit_and_lsb_msb_pairs_do_not_invent_gap_fields():
    values = {"TEST_CONFIG_COUNT_LSB": 2, "TEST_CONFIG_COUNT_MSB": 9,
              "TEST_CONFIG_READY_BIT": 12, "TEST_CONFIG_ACTIVE_BIT": 15}
    definitions = {key: {"expression": str(value)} for key, value in values.items()}
    record = {"symbol": "TEST_CONFIG_OFFSET", "name": "CONFIG", "fields": [
        {"lsb": 0, "msb": 31, "name": "WORD", "expression": "word", "reset": "0"},
    ]}
    fields = refine_fields(record, {}, definitions, {"constants": values, "text": ""})
    named = {f["name"]: (f["lsb"], f["msb"]) for f in fields if f["name"] != "WORD"}
    assert named == {"COUNT": (2, 9), "READY": (12, 12), "ACTIVE": (15, 15)}


def test_mini_read_write_views_and_consumer_widths_are_qualified(registers):
    def reg(family, key):
        return next(r for r in registers[family]["registers"] if r["key"] == key)
    def bounds(family, key, name):
        field = next(f for f in reg(family, key)["fields"] if f["name"] == name)
        return field["lsb"], field["msb"]
    assert bounds("usb2", "endpoint.CFG", "TYPE") == (4, 5)
    assert bounds("usb2", "channel.CFG", "PING_ENABLE") == (6, 6)
    assert bounds("usb2", "channel.TARGET", "ADDR") == (0, 6)
    assert bounds("rtc", "main.STATUS", "LINK_READY") == (6, 6)
    assert bounds("opipsram", "main.OPI_TIMING", "DUMMY") == (2, 9)
    assert bounds("opipsram", "main.OPI_TIMING", "LATENCY") == (10, 14)
    assert not any("VIEWPORT" in f["name"] for f in reg("usb2", "main.PHY_CTRL")["fields"])
    assert "different write and readback layouts" in reg("sdio", "main.CMD_CFG")["description"]
    assert "[21:16]" in reg("usb2", "main.ULPI_VIEWPORT")["notes"]
    assert "[29:24]" in reg("usb2", "main.ULPI_VIEWPORT")["notes"]


@pytest.mark.parametrize("family,key,name,low,high", [
    ("rtc", "main.COMMAND", "OPCODE", 0, 2),
    ("wdg", "main.CONFIG", "WINDOW_ENABLE", 0, 0),
    ("wdg", "main.COMMAND_STATUS", "DONE", 0, 0),
    ("pwm", "main.COMMAND", "STOP_ALL", 3, 3),
    ("pwm", "channel.FADE_CTRL", "START", 0, 0),
    ("pwm", "channel.FADE_CTRL", "STOP", 3, 3),
    ("usb2", "main.PERF_CTRL", "CLEAR", 0, 0),
    ("usb2", "main.RAM_BIST", "REQUEST", 0, 0),
    ("sysctrl", "clock.CLK_HP_REQ", "APPLY", 31, 31),
    ("sysctrl", "clock.CLK_HP_REQ", "FORCE_SAFE", 30, 30),
    ("monitor", "main.Control", "CLEAR", 2, 2),
    ("monitor", "main.Control", "SNAPSHOT", 3, 3),
    ("apu", "main.RING_DOORBELL", "KICK", 0, 0),
    ("apu", "main.KWS_COEFF_COMMAND", "LOAD", 0, 0),
    ("extensions", "main.Command", "CLEAR_FAULT", 2, 2),
    ("extensions", "main.DmaCommand", "ABORT", 1, 1),
])
def test_write_commands_are_not_hidden_by_zero_readback(registers, family, key, name, low, high):
    reg = next(r for r in registers[family]["registers"] if r["key"] == key)
    field = next(f for f in reg["fields"] if f["name"] == name)
    assert (field["lsb"], field["msb"]) == (low, high)
    assert reg["source_bindings"]
    if family == "wdg" and key == "main.CONFIG":
        assert "LOCK" not in {f["name"] for f in reg["fields"]}
    if family == "rtc":
        assert {f["name"] for f in reg["fields"]} == {"OPCODE", "Reserved"}
        assert "not independent mask bits" in reg["description"]


@pytest.mark.parametrize("family,key", [
    ("apu", "main.RING_DOORBELL"), ("apu", "main.KWS_COEFF_COMMAND"),
    ("usb2", "main.PERF_CTRL"), ("usb2", "main.RAM_BIST"),
    ("extensions", "main.DmaCommand"),
])
def test_zero_readback_cannot_erase_a_writable_port_from_the_reference(registers, family, key):
    specimen = copy.deepcopy(registers)
    reg = next(r for r in specimen[family]["registers"] if r["key"] == key)
    reg["fields"] = [{"lsb": 0, "msb": 31, "name": "Reserved", "reset": "0"}]
    with pytest.raises(ValueError, match="no documented data or command field"):
        validate_reference(specimen)


def test_reserved_measurements_and_overlapping_status_remain_explicit(registers):
    def reg(family, key):
        return next(r for r in registers[family]["registers"] if r["key"] == key)
    for stem in ("PERF_DECODED_FRAMES", "PERF_KWS_CYCLES"):
        for half in ("LO", "HI"):
            counter = reg("apu", f"main.{stem}_{half}")
            assert "reads zero" in counter["description"]
            assert "not an implemented measurement" in counter["description"]
            assert all(f["name"] == "Reserved" for f in counter["fields"])
    assert "No memory self-test" in reg("usb2", "main.RAM_BIST")["description"]
    status = reg("pwm", "main.STATUS")
    assert "overlaps the channel-enable bitmap" in status["notes"]
    assert "Raw, dead-time" not in status["description"]
    default = next(f for f in reg("jpeg", "main.TABLE_COMMAND")["fields"] if f["name"] == "DEFAULT")
    assert "sets the selected context error" in default["description"]


def test_diagnostic_and_smoke_text_matches_current_sources(registers):
    monitor = next(r for r in registers["monitor"]["registers"] if r["key"] == "main.Status")
    assert "23:16" in monitor["description"] and "31:24" in monitor["description"]
    master = next(r for r in registers["sysctrl"]["registers"] if r["key"] == "main.FAULT_MASTER")
    assert "IDs 0..9" in master["description"] and "NPU" in master["description"]
    reference = json.loads((ROOT / "publications/datasheets/system-reference.json").read_text(encoding="utf-8"))
    stage = next(s for app in reference["software"]["applications"] for s in app["stages"]
                 if s["trigger"] == "rs_ci_smoke_npu_irq(")
    assert "RS_NPU_P5_ACCEPTANCE" in stage["boundary"]
    assert "private master is tied idle" not in stage["boundary"]
    assert "LP vector bit 33" in stage["coverage"]


def test_rendered_values_follow_reference_instance_not_reusable_defaults(registers):
    def value(family, key):
        return next(x for x in registers[family]["registers"] if x["key"] == key)
    assert value("apu", "main.IP_VERSION")["reset"] == "0x00010001"
    assert value("apu", "main.CAPABILITY0")["reset"] == "0x000001BD"
    assert value("apu", "main.CAPABILITY1")["reset"] == "0x01827020"
    assert value("crypto", "main.CAPABILITY0")["reset"] == "0x03FFFFFF"
    assert value("gpio", "common.PAD_CAPABILITY")["reset"] == "0x00000000"
    assert value("dma", "main.IP_VERSION")["reset"] == "0x00020000"
    assert value("dma", "main.SUPPORTED_REQUESTS")["reset"] == "0x00003FFF"
    assert value("i2c", "main.CAPABILITY")["reset"] == "0x007F1010"
    assert value("pwm", "main.CAPTURE1_CTRL")["access"] == "RW"
    assert value("pwm", "main.CAPTURE1_STATUS")["access"] == "RO"
    assert value("archinfo", "main.TOPOLOGY")["reset"] == "0x40200001"
    assert value("archinfo", "main.FEATURES0")["reset"] == "0x0002FFFE"
    assert value("archinfo", "main.TECHNOLOGY")["reset"] == "0x02010082"
    for key in ("BUILD_ID_LO", "BUILD_ID_HI", "CONFIG_ID", "BUILD_STATUS"):
        reg = value("archinfo", "main." + key)
        assert reg["reset"] == "Build-dependent" and "rtl_reset" not in reg
        assert all(f["reset"] == ("0" if f["name"] == "Reserved" else "Build-dependent") for f in reg["fields"])
    capability = value("dma", "main.CAPABILITY")
    burst = next(x for x in capability["fields"] if x["name"] == "MAX_BURST_FIELD")
    assert number(burst["reset"]) == 0 and "truncat" in capability["description"]


def test_crypto_macro_and_fallback_are_explicit_selections():
    source = (ROOT / "rtl/ip/security/apb4_crypto.sv").read_text(encoding="utf-8")
    assert "32'h03ffffff" in select_conditionals(source, {"HAVE_SRAM_MACRO": True})
    assert "32'h03ffffff" not in select_conditionals(source, {"HAVE_SRAM_MACRO": False})


def test_imported_prose_cannot_reintroduce_retired_mini_integration_claims(registers):
    from publications.chapter_reference import collect_chapters

    chapters = collect_chapters(registers)
    def prose(family):
        item = chapters[family]
        return json.dumps(item["functional"] + item["software"])
    assert "ICS55 keeps the SRAM absent" not in prose("sram")
    assert "profiles keep the macro disabled" not in prose("sram")
    assert "current Mini ICS55 CI profile" in prose("sram")
    assert "I/O gateway A" in prose("sdio") and "LP memory gateway uses master 5" in prose("sdio")
    assert "Mini actually clocks both controllers from PCLK" in prose("sdio")
    assert "Mini supplies PCLK" in prose("spisd")
    assert "nominal external CK is 18 MHz" in prose("opipsram")
    assert "nominal 18 MHz external SDRAM clock" in prose("sdram")


@pytest.mark.parametrize("family,group", [("resource", "resource"), ("monitor", "master")])
def test_repeated_register_banks_cannot_omit_npu_index_nine(registers, family, group):
    bindings = collect_mini_bindings(ROOT, selected_profile(ROOT))
    item = next(g for g in registers[family]["groups"] if g["id"] == group)
    assert item["count"] == 10
    specimen = copy.deepcopy(registers)
    next(g for g in specimen[family]["groups"] if g["id"] == group)["count"] = 9
    with pytest.raises(ValueError, match="instance coverage"):
        validate_register_bindings(specimen, bindings)


def test_archinfo_generated_identity_cannot_fall_back_to_zero(binding_tree):
    path = binding_tree / "rtl/mini/top/apb4_system.sv"
    text = path.read_text(encoding="utf-8")
    path.write_text(text.replace(".BUILD_ID          (`ARCHINFO_INTEGRATION_BUILD_ID)",
                                 ".BUILD_ID          (64'd0)"), encoding="utf-8")
    with pytest.raises(ValueError, match="generated build identity"):
        collect_mini_bindings(binding_tree, selected_profile(ROOT))


def test_archinfo_feature_word_tracks_the_selected_rtl_branch(binding_tree):
    path = binding_tree / "rtl/mini/top/apb4_system.sv"
    text = path.read_text(encoding="utf-8")
    path.write_text(text.replace("ARCHINFO_HAVE_SRAM_MACRO = 1'b1", "ARCHINFO_HAVE_SRAM_MACRO = 1'b0"), encoding="utf-8")
    with pytest.raises(ValueError, match="selected feature flags"):
        collect_mini_bindings(binding_tree, selected_profile(ROOT))


def test_crypto_example_initializes_before_key_and_documents_completion():
    source = (ROOT / "publications/examples/crypto.c").read_text(encoding="utf-8")
    assert source.index("rs_crypto_init(timeout)") < source.index("rs_crypto_aes_set_key(")
    assert "if (result != RS_OK)" in source
    content = json.loads((ROOT / "publications/datasheets/ip-content.json").read_text(encoding="utf-8"))["crypto"]
    assert "Implemented MVP" not in content["function_sections"]
    assert section_text(ROOT / "docs/ip/crypto.md", content["function_sections"])
    assert {"rs_crypto_init", "rs_crypto_zeroize_wait"} <= {x["name"] for x in content["api"]}


def test_current_ci_cannot_claim_completion_from_running_state():
    from publications.dev_reference import validate_ci_snapshot

    reference = json.loads((ROOT / "publications/datasheets/system-reference.json").read_text(encoding="utf-8"))
    snapshot = copy.deepcopy(reference["ci_snapshot"])
    snapshot["runs"][0].update(status="in_progress", conclusion="success")
    with pytest.raises(ValueError, match="unfinished"):
        validate_ci_snapshot(snapshot, reference["source_revision"])


@pytest.mark.parametrize("mutation", ["missing_npu", "crypto_irq", "duplicate_route"])
def test_dma_route_tables_cannot_omit_implemented_completion_sources(mutation):
    from publications.programming_reference import collect_programming

    reference = json.loads((ROOT / "publications/datasheets/system-reference.json").read_text(encoding="utf-8"))
    spec = copy.deepcopy(reference["programming"])
    ids = {row["id"] for row in reference["support"]}
    result = collect_programming(ROOT, spec, ids, reference["source_revision"])
    npu = next(row for row in result["engines"] if row["id"] == "npu")
    assert (npu["lp_irq"], npu["hp_irq"]) == (33, 12)
    assert {row["lp_irq"] for row in result["dma_routes"] if row["id"].startswith("crypto_")} == {"23"}
    if mutation == "missing_npu":
        spec["engines"] = [row for row in spec["engines"] if row["id"] != "npu"]
    elif mutation == "duplicate_route":
        next(row for row in spec["engines"] if row["id"] == "npu")["hp_signal"] = "resource_irq_hp_i[7]"
    else:
        next(row for row in spec["dma_routes"] if row["id"] == "crypto_in")["irq"] = None
    with pytest.raises(ValueError, match="interrupt coverage|interrupt omitted"):
        collect_programming(ROOT, spec, ids, reference["source_revision"])
