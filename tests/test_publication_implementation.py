"""Explicit CPU/reset evidence and tool execution state must survive publication."""
import copy
import json
from pathlib import Path
from types import SimpleNamespace

import pytest

from publications import implementation_reference as ir
from scripts import program_xpi_flash as flash

ROOT = Path(__file__).resolve().parents[1]
REFERENCE = json.loads((ROOT / "publications/datasheets/system-reference.json").read_text(encoding="utf-8"))
IDS = {row["id"] for row in REFERENCE["support"]}
LIMITS = {row["id"] for row in REFERENCE["limitations"]}


@pytest.fixture
def spec():
    return copy.deepcopy(REFERENCE["product_details"])


def test_cpu_configuration_does_not_substitute_firmware_flags(spec):
    result = ir.collect_details(ROOT, spec, IDS, LIMITS)["cpu"]
    assert result["lp"]["EXTENSION_C"] == "1"
    assert result["lp"]["CSR_M_MANDATORY"] == "1"
    assert result["build"]["ISA"] == "RV32IM" and result["build"]["HAVE_CSR"] == "NO"
    assert result["lp"]["PMP_REGIONS"] == "0"
    assert result["hp"]["pmpParam.pmpSize"] == "16"
    assert result["hp"]["fetchL1Sets"] == "64" and result["hp"]["fetchL1Ways"] == "4"
    assert result["hp_cache_capacity"].startswith("Unconfirmed")
    sram_pma = next(row for row in result["pma"] if row["base"] == "0x30000000")
    assert sram_pma["bytes"] == 128 * 1024  # Attribute envelope, not fitted SRAM capacity.


@pytest.mark.parametrize("text", [
    "module unrelated; endmodule",
    "hazard3_cpu_1port #(.A(1), .A(0)) u_hazard3_cpu_1port ();",
    "hazard3_cpu_1port #(.A(1)) u_hazard3_cpu_1port ();" * 2,
])
def test_missing_or_ambiguous_cpu_instance_is_rejected(text):
    with pytest.raises(ValueError, match="missing|ambiguous|duplicate"):
        ir.lp_parameters(text)


def test_lp_parameters_ignore_commented_out_instance():
    text = "// hazard3_cpu_1port #(.A(0)) u_hazard3_cpu_1port ();\n"
    text += "hazard3_cpu_1port #(.A(1), .RESET_VECTOR(`SOC_CPU_RESET_ADDR)) u_hazard3_cpu_1port ();"
    assert ir.lp_parameters(text) == {"A": "1", "RESET_VECTOR": "`SOC_CPU_RESET_ADDR"}


def test_duplicate_hp_assignment_is_rejected():
    with pytest.raises(ValueError, match="duplicate HP"):
        ir.hp_parameters('param.xlen = 32\nparam.xlen = 64\nparam.addISA("m")')


def test_required_processor_parameter_cannot_disappear(spec):
    spec["cpu"]["hp_fields"].append("unreviewedCacheDefault")
    with pytest.raises(ValueError, match="missing or duplicate requested HP"):
        ir.collect_details(ROOT, spec, IDS, LIMITS)


def test_reset_proof_requires_the_reset_branch():
    with pytest.raises(ValueError, match="reset branch"):
        ir.reset_assignments("always_ff @(posedge clk) value <= '0;", "rst_n_i")
    source = "module a; if (!rst_n_i) begin value <= '0; end else value <= '1; endmodule"
    assert ir.reset_assignments(source, "rst_n_i", "a")["value"] == "'0"


def test_changed_reset_literal_is_rejected(spec):
    row = next(r for r in spec["reset"] if r["id"] == "resource-owner")
    row["bindings"][0]["value"] = "'1"
    with pytest.raises(ValueError, match="untraceable reset value"):
        ir.validate_details(spec, IDS, ROOT, LIMITS)


def test_fixed_reset_without_binding_is_rejected(spec):
    row = next(r for r in spec["reset"] if r["id"] == "dma-initial")
    row["bindings"] = []
    with pytest.raises(ValueError, match="untraceable reset"):
        ir.validate_details(spec, IDS, ROOT, LIMITS)


@pytest.mark.parametrize("mutation", ["unknown_ip", "no_proof", "qualification"])
def test_interface_claims_require_correct_scope_and_evidence(spec, mutation):
    row = spec["interfaces"][0]
    if mutation == "unknown_ip":
        row["ips"] = ["invented"]
    elif mutation == "no_proof":
        row["bindings"] = []
    else:
        row["evidence"] = "Certified"
    with pytest.raises(ValueError, match="unknown|lacks binding|qualification"):
        ir.validate_details(spec, IDS, ROOT, LIMITS)


def test_same_format_does_not_remove_jpeg_integration_block(spec):
    spec["interoperability"][0]["classification"] = "Format-compatible"
    with pytest.raises(ValueError, match="ignores active blocker"):
        ir.validate_details(spec, IDS, ROOT, LIMITS)


def test_interoperability_without_source_binding_is_rejected(spec):
    spec["interoperability"][2]["bindings"] = []
    with pytest.raises(ValueError, match="lacks binding"):
        ir.validate_details(spec, IDS, ROOT, LIMITS)


@pytest.mark.parametrize("record", [{"passed": True}, {"executed": "false", "passed": True}])
def test_result_requires_boolean_execution_state(record):
    with pytest.raises(ValueError, match="boolean executed"):
        ir.programming_result(record)


@pytest.mark.parametrize("executed,passed,expected", [
    (False, True, "Script generated; device not programmed"),
    (False, False, "Preparation failed; no execution recorded"),
    (True, False, "Execution failed or success marker absent"),
    (True, True, "Tool reported execution success"),
])
def test_programming_result_semantics(executed, passed, expected):
    assert ir.programming_result({"executed": executed, "passed": passed}) == expected


def test_real_tool_dry_run_never_invokes_gdb_and_is_not_device_pass(tmp_path, monkeypatch):
    loader, image = tmp_path / "loader.elf", tmp_path / "image.bin"
    loader.write_bytes(b"fixture")
    image.write_bytes(b"fixture")

    def only_nm(command, **kwargs):
        assert command[0] == "fixture-nm", "dry run must not launch GDB"
        return SimpleNamespace(stdout="30001000 B rs_xpi_flash_staging\n")

    monkeypatch.setattr(flash.subprocess, "run", only_nm)
    args = SimpleNamespace(execute=False, gdb_script=tmp_path / "program.gdb", loader=loader,
                           image=image, address=0, nm="fixture-nm", gdb="must-not-run",
                           target="unused:3333", result=tmp_path / "result.json")
    assert flash.run(args) == 0
    result = json.loads(args.result.read_text())
    assert result["passed"] is True and result["executed"] is False
    assert ir.programming_result(result) == "Script generated; device not programmed"
    assert "XPI_FLASH_PROGRAM_PASS" in args.gdb_script.read_text()
