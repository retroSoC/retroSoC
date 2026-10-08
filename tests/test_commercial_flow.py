# Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
# retroSoC is licensed under Mulan PSL v2.
# You can use this software according to the terms and conditions of the Mulan PSL v2.
# You may obtain a copy of Mulan PSL v2 at:
#             http://license.coscl.org.cn/MulanPSL2
# THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
# EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
# MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
# See the Mulan PSL v2 for more details.

from __future__ import annotations

import importlib.util
import io
import os
import shutil
import subprocess
import sys
import tarfile
from pathlib import Path

import pytest


ROOT = Path(__file__).resolve().parents[1]
FLOW = ROOT / "physical/commercial"


def load_script(name: str):
    path = FLOW / "scripts" / f"{name}.py"
    spec = importlib.util.spec_from_file_location(f"commercial_{name}", path)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_translate_eco_accepts_only_reviewed_operations(tmp_path: Path) -> None:
    translator = load_script("translate_eco")
    supported = tmp_path / "supported.tcl"
    supported.write_text(
        "current_instance {u_core}\n"
        "size_cell {u_reg} {DFFQX2H7R}\n"
        "insert_buffer [get_pins {u_src/Q}] BUFX2H7R "
        "-new_net_names {eco_net} -new_cell_names {eco_buf}\n",
        encoding="utf-8",
    )
    assert translator.translate([str(supported)]) == [
        "ecoChangeCell -inst {u_core/u_reg} -cell {DFFQX2H7R}",
        "ecoAddRepeater -term {u_core/u_src/Q} -cell {BUFX2H7R} "
        "-newNetName {eco_net} -name {eco_buf}",
    ]

    unsupported = tmp_path / "unsupported.tcl"
    unsupported.write_text("disconnect_net old [get_pins u/A]\n", encoding="utf-8")
    with pytest.raises(ValueError, match="unsupported PrimeTime ECO command"):
        translator.translate([str(unsupported)])


def test_translate_eco_merges_scenarios_and_drops_duplicates(tmp_path: Path) -> None:
    translator = load_script("translate_eco")
    first = tmp_path / "func_TYP_TYP_25.icc2.tcl"
    first.write_text(
        "current_instance {u_core}\n"
        "size_cell {u_reg} {DFFQX2H7R}\n"
        "insert_buffer [get_pins {u_src/Q}] BUFX2H7R "
        "-new_net_names {eco_net} -new_cell_names {eco_buf}\n",
        encoding="utf-8",
    )
    second = tmp_path / "func_MIN_Cworst_m40.icc2.tcl"
    second.write_text(
        "current_instance {u_core}\n"
        "size_cell {u_reg} {DFFQX2H7R}\n"
        "size_cell {u_hold} {DFFQX1H7R}\n",
        encoding="utf-8",
    )
    assert translator.translate([str(first), str(second)]) == [
        "ecoChangeCell -inst {u_core/u_reg} -cell {DFFQX2H7R}",
        "ecoAddRepeater -term {u_core/u_src/Q} -cell {BUFX2H7R} "
        "-newNetName {eco_net} -name {eco_buf}",
        "ecoChangeCell -inst {u_core/u_hold} -cell {DFFQX1H7R}",
    ]


def test_translate_eco_supports_removal_and_placed_insert(tmp_path: Path) -> None:
    translator = load_script("translate_eco")
    source = tmp_path / "changes.icc2.tcl"
    source.write_text(
        "current_instance {u_core}\n"
        "remove_buffer [get_cells {u_buf}]\n"
        "insert_buffer [get_pins {u_src/Q}] BUFX2H7R -new_net_names {eco_net} "
        "-new_cell_names {eco_buf} -location {10.5 20.25}\n",
        encoding="utf-8",
    )
    assert translator.translate([str(source)]) == [
        "ecoDeleteRepeater -inst {u_core/u_buf}",
        "ecoAddRepeater -term {u_core/u_src/Q} -cell {BUFX2H7R} "
        "-newNetName {eco_net} -name {eco_buf} -loc {10.5 20.25}",
    ]

    ambiguous = tmp_path / "ambiguous.icc2.tcl"
    ambiguous.write_text("remove_buffer [get_cells {u_a u_b}]\n", encoding="utf-8")
    with pytest.raises(ValueError, match="unsupported PrimeTime ECO command"):
        translator.translate([str(ambiguous)])


def test_spef_checker_requires_every_named_corner(tmp_path: Path) -> None:
    checker = load_script("check_outputs")
    for corner in checker.spef_corners():
        (tmp_path / f"retrosoc_asic.{corner}.spef.gz").write_bytes(b"spef")
    assert checker.apply_check("spef", str(tmp_path), 0, "retrosoc_asic") is None
    (tmp_path / "retrosoc_asic.TYP_25.spef.gz").unlink()
    assert "missing SPEF corners" in checker.apply_check(
        "spef", str(tmp_path), 0, "retrosoc_asic"
    )


def test_calibre_checkers_accept_actual_clean_report_format(tmp_path: Path) -> None:
    checker = load_script("check_outputs")
    (tmp_path / "retrosoc_asic.drc.summary").write_text(
        "TOTAL DRC Results Generated:     0 (0)\n",
        encoding="utf-8",
    )
    assert checker.apply_check("calibre-drc", str(tmp_path), 0) is None

    (tmp_path / "retrosoc_asic.drc.summary").unlink()
    (tmp_path / "retrosoc_asic.lvs.rpt").write_text(
        "OVERALL COMPARISON RESULTS\n\n"
        "        ###################\n"
        "        #     CORRECT     #\n"
        "        ###################\n",
        encoding="utf-8",
    )
    assert checker.apply_check("calibre-lvs", str(tmp_path), 0) is None


def test_prepare_input_rejects_archive_escape(tmp_path: Path) -> None:
    archive_path = tmp_path / "escape.tar"
    payload = tmp_path / "payload"
    payload.write_text("not allowed\n", encoding="utf-8")
    with tarfile.open(archive_path, "w") as archive:
        archive.add(payload, arcname="../escape")
    output = tmp_path / "output"
    result = subprocess.run(
        [
            sys.executable,
            str(FLOW / "scripts/prepare_input.py"),
            "--archive",
            str(archive_path),
            "--output-dir",
            str(output),
            "--manifest",
            str(tmp_path / "manifest.json"),
        ],
        text=True,
        capture_output=True,
        check=False,
    )
    assert result.returncode != 0
    assert "escapes destination" in result.stderr


def test_prepare_input_refreshes_archived_filelist(tmp_path: Path) -> None:
    archive_path = tmp_path / "rtl.tar"
    payload = b"rtl/top.sv\n"
    contract = b"# contract\n"
    with tarfile.open(archive_path, "w") as archive:
        member = tarfile.TarInfo("rtl/filelist.fl")
        member.size = len(payload)
        member.mtime = 1
        archive.addfile(member, io.BytesIO(payload))
        member = tarfile.TarInfo("rtl/contracts/commercial_timing_contract.tcl")
        member.size = len(contract)
        member.mtime = 1
        archive.addfile(member, io.BytesIO(contract))
    output = tmp_path / "output"
    manifest = tmp_path / "manifest.json"
    started = archive_path.stat().st_mtime
    subprocess.run(
        [
            sys.executable,
            str(FLOW / "scripts/prepare_input.py"),
            "--archive",
            str(archive_path),
            "--output-dir",
            str(output),
            "--manifest",
            str(manifest),
        ],
        check=True,
    )
    assert (output / "rtl/filelist.fl").stat().st_mtime >= started


def test_stage_runner_forwards_environment_and_requires_outputs(tmp_path: Path) -> None:
    expected = tmp_path / "expected"
    stamp = tmp_path / "stage.stamp"
    command = [
        sys.executable,
        str(FLOW / "scripts/run_stage.py"),
        "--stage",
        "unit",
        "--cwd",
        str(tmp_path),
        "--log",
        str(tmp_path / "stage.log"),
        "--result",
        str(tmp_path / "result.json"),
        "--stamp",
        str(stamp),
        "--expect",
        str(expected),
        "--",
        "COMMERCIAL_TEST_VALUE=forwarded",
        sys.executable,
        "-c",
        (
            "import os, pathlib; "
            "pathlib.Path(r'{0}').write_text(os.environ['COMMERCIAL_TEST_VALUE'])"
        ).format(expected),
    ]
    subprocess.run(command, check=True)
    assert expected.read_text(encoding="utf-8") == "forwarded"
    assert stamp.is_file()

    expected.unlink()
    failed = subprocess.run(command[:-3] + [sys.executable, "-c", "pass"], check=False)
    assert failed.returncode != 0
    assert not stamp.exists()


def test_lsf_submission_modes_preserve_blocking_and_logs(tmp_path: Path) -> None:
    submitter = load_script("submit_job")
    tool = ["dc_shell", "-64", "-f", "main.tcl"]
    tool_log = str(tmp_path / "tool.log")

    batch = submitter.build_submission(
        "batch", "bsub", '-q normal -R "span[hosts=1]"', tool_log, tool
    )
    assert batch[:4] == ["bsub", "-K", "-q", "normal"]
    assert batch[-len(tool) :] == tool
    assert batch.count(tool_log) == 2

    interactive = submitter.build_submission(
        "interactive", "bsub", '-q m-q -R "span[hosts=1]"', tool_log, tool
    )
    assert interactive[:4] == ["bsub", "-I", "-q", "m-q"]
    assert "-K" not in interactive
    assert "-oo" not in interactive
    assert interactive[-len(tool) :] == tool
    assert "run_logged.py" in " ".join(interactive)


def test_remote_logger_propagates_output_and_status(tmp_path: Path) -> None:
    log = tmp_path / "tool.log"
    result = subprocess.run(
        [
            sys.executable,
            str(FLOW / "scripts/run_logged.py"),
            "--log",
            str(log),
            "--",
            sys.executable,
            "-c",
            "import sys; print('tool output'); sys.exit(7)",
        ],
        text=True,
        capture_output=True,
        check=False,
    )
    assert result.returncode == 7
    assert "tool output" in result.stdout
    assert "tool output" in log.read_text(encoding="utf-8")


def test_pt_runner_consumes_every_common_scenario(tmp_path: Path) -> None:
    fake_pt = tmp_path / "fake_pt.py"
    fake_pt.write_text(
        "import os\n"
        "from pathlib import Path\n"
        "base = Path(os.environ['RUN_ROOT']) / 'sta' / os.environ['STA_TAG']\n"
        "scenario = os.environ['STA_SCENARIO']\n"
        "(base / 'output').mkdir(parents=True, exist_ok=True)\n"
        "(base / 'output' / (scenario + '.pass')).write_text('PASS\\n')\n"
        "(base / 'output' / (scenario + '.summary.tsv')).write_text(\n"
        "    scenario + '\\t0\\t0\\t0\\n')\n"
        "(base / 'work' / 'sessions' / scenario).mkdir(parents=True)\n",
        encoding="utf-8",
    )
    run_root = tmp_path / "run"
    for name in ("work", "log", "reports", "output"):
        (run_root / "sta/route" / name).mkdir(parents=True)
    environment = dict(**os.environ, RUN_ROOT=str(run_root))
    subprocess.run(
        [
            sys.executable,
            str(FLOW / "scripts/run_pt_scenarios.py"),
            "--pt-command",
            f"{sys.executable} {fake_pt}",
            "--tcl-command",
            "tclsh",
            "--scenario-script",
            str(FLOW / "tcl/common/list_scenarios.tcl"),
            "--main",
            str(FLOW / "tcl/sta/main.tcl"),
            "--tag",
            "route",
        ],
        check=True,
        env=environment,
    )
    summary = (run_root / "sta/route/output/summary.tsv").read_text(
        encoding="utf-8"
    )
    assert len(summary.splitlines()) == 14
    assert (run_root / "sta/route/output/verdict.pass").is_file()


def test_boundary_audit_scans_untracked_candidates(tmp_path: Path) -> None:
    audit = load_script("audit_boundary")
    tracked = tmp_path / "physical/commercial/config/example.mk"
    tracked.parent.mkdir(parents=True)
    tracked.write_text("LIB := /site/lib/example.db\n", encoding="utf-8")
    errors = audit.violations(tmp_path, [tracked])
    assert any("site-specific absolute path" in error for error in errors)


def test_commercial_makefile_is_posix_and_make_382_compatible() -> None:
    makefile = (FLOW / "Makefile").read_text(encoding="utf-8")
    assert "SHELL := /bin/sh" in makefile
    assert "{work," not in makefile
    assert ".ONESHELL" not in makefile
    assert "$(file " not in makefile


def test_dc_analyze_receives_one_source_list_argument() -> None:
    synthesis = (FLOW / "tcl/syn/main.tcl").read_text(encoding="utf-8")
    assert "lappend analyze_command [dict get $rtl sources]" in synthesis
    assert "concat $analyze_command [dict get $rtl sources]" not in synthesis


def test_dc_check_timing_uses_supported_options() -> None:
    synthesis = (FLOW / "tcl/syn/main.tcl").read_text(encoding="utf-8")
    assert synthesis.count("check_timing\n") == 2
    assert "check_timing -verbose" not in synthesis
    assert synthesis.count(
        "check_timing -include {unconstrained_endpoints}"
    ) == 2
    assert "no_clock" not in synthesis


def test_commercial_timing_contract_covers_canonical_domains(tmp_path: Path) -> None:
    output = tmp_path / "commercial_timing_contract.tcl"
    subprocess.run(
        [
            sys.executable,
            str(FLOW / "scripts/generate_timing_contract.py"),
            "--soc",
            "MINI",
            "--domains",
            str(ROOT / "rtl/mini/integration/clock_reset_domains.json"),
            "--pin-map",
            str(ROOT / "rtl/mini/pin_map/pin_map.json"),
            "--output",
            str(output),
        ],
        check=True,
    )
    script = (
        "namespace eval flow {}\n"
        f"source {{{output}}}\n"
        "puts [join [lsort [dict keys $flow::canonical_clock_domains]] ,]\n"
        "puts [join $flow::canonical_reset_ports ,]\n"
    )
    result = subprocess.run(
        ["tclsh"],
        input=script,
        text=True,
        capture_output=True,
        check=True,
    )
    assert result.stdout.splitlines() == [
        "aon,audio,dvp,hp,jtag,lp,memory,pclk,usb2_ulpi",
        "ext_rst_n_i_pad,jtag_trst_n_i_pad",
    ]
    assert "u_retrosoc/u_apb4_periph/u_axi4_dvp" in output.read_text(
        encoding="utf-8"
    )
    assert "object_type {net_driver}" in output.read_text(encoding="utf-8")
    assert "observation {s_sys_clk}" in output.read_text(encoding="utf-8")


def test_commercial_timing_contract_supports_tiny(tmp_path: Path) -> None:
    output = tmp_path / "commercial_timing_contract.tcl"
    subprocess.run(
        [
            sys.executable,
            str(FLOW / "scripts/generate_timing_contract.py"),
            "--soc",
            "TINY",
            "--domains",
            str(ROOT / "rtl/tiny/integration/clock_reset_domains.json"),
            "--pin-map",
            str(ROOT / "rtl/tiny/pin_map/pin_map.json"),
            "--output",
            str(output),
        ],
        check=True,
    )
    script = (
        "namespace eval flow {}\n"
        f"source {{{output}}}\n"
        "puts [join [lsort [dict keys $flow::canonical_clock_domains]] ,]\n"
        "puts [join $flow::canonical_reset_ports ,]\n"
    )
    result = subprocess.run(
        ["tclsh"],
        input=script,
        text=True,
        capture_output=True,
        check=True,
    )
    assert result.stdout.splitlines() == [
        "jtag,system",
        "ext_rst_n_i_pad,jtag_trst_n_i_pad",
    ]
    assert "observation {u_clock_buffer/clk_o}" in output.read_text(
        encoding="utf-8"
    )


def test_commercial_timing_contract_rejects_domain_drift(tmp_path: Path) -> None:
    result = subprocess.run(
        [
            sys.executable,
            str(FLOW / "scripts/generate_timing_contract.py"),
            "--soc",
            "TINY",
            "--domains",
            str(ROOT / "rtl/mini/integration/clock_reset_domains.json"),
            "--pin-map",
            str(ROOT / "rtl/mini/pin_map/pin_map.json"),
            "--output",
            str(tmp_path / "drift.tcl"),
        ],
        text=True,
        capture_output=True,
        check=False,
    )
    assert result.returncode != 0
    assert "differ from the canonical set" in result.stderr


def test_commercial_constraints_do_not_apply_global_io_delays() -> None:
    constraints = "\n".join(
        path.read_text(encoding="utf-8")
        for path in (FLOW / "tcl/common").glob("*constraints.tcl")
    )
    assert "set_input_delay" in constraints
    assert "set_output_delay" in constraints
    assert "set_input_delay" + " -clock clk_external" not in constraints
    assert "set_output_delay" + " -clock clk_external" not in constraints
    assert "set_input_delay" + " -clock $clock" in constraints
    assert "set_output_delay" + " -clock $clock" in constraints


def test_dc_uses_typ_link_set_and_svt_lvt_target_subset() -> None:
    synthesis = (FLOW / "tcl/syn/main.tcl").read_text(encoding="utf-8")
    common = (FLOW / "tcl/common/common.tcl").read_text(encoding="utf-8")
    example = (FLOW / "config/ics55-mini.example.mk").read_text(encoding="utf-8")
    assert "flow::synthesis_library_files" in synthesis
    assert "flow::all_library_files" not in synthesis
    assert "return [flow::library_files TYP]" in common
    assert "SYN_STD_DB_TYP" in example
    assert "H7CR (SVT) and H7CL (LVT)" in example


def test_synthesis_summary_separates_flow_and_qor_status() -> None:
    reporting = (FLOW / "tcl/syn/reporting.tcl").read_text(encoding="utf-8")
    for metric in (
        "flow_pass",
        "constraints_complete",
        "io_qualified",
        "timing_met",
        "drv_met",
    ):
        assert f'"{metric}\\t' in reporting
    assert "lvt_area_percent" not in reporting
    assert "[string tolower $group]_area_percent" in reporting


def test_doctor_normalizes_h7c_nldm_liberty_names() -> None:
    doctor = load_script("doctor")
    db = "/local/ics55_LLSC_H7CR_typ_tt_1p2_25.db"
    lib = "/local/ics55_LLSC_H7CR_typ_tt_1p2_25_nldm.lib"
    assert doctor.normalized_library_stem(db) == doctor.normalized_library_stem(lib)
    assert doctor.h7c_variants([db, lib]) == {"H7CR"}


def test_internal_qor_doctor_does_not_require_backend_collateral(
    tmp_path: Path,
) -> None:
    def touch(name: str) -> str:
        path = tmp_path / name
        path.write_bytes(b"view")
        return str(path)

    h7ch = touch("ics55_LLSC_H7CH_typ_tt_1p2_25.db")
    h7cl = touch("ics55_LLSC_H7CL_typ_tt_1p2_25.db")
    h7cr = touch("ics55_LLSC_H7CR_typ_tt_1p2_25.db")
    archive = touch("rtl.tar.gz")
    environment = {
        "PATH": os.environ["PATH"],
        "SOC": "MINI",
        "TOP": "retrosoc_asic",
        "TECHNOLOGY": "ICS55",
        "PRODUCT_PLL_MODE": "qualified",
        "RTL_ARCHIVE": archive,
        "LSF_MODE": "batch",
        "LSF_SYN_ARGS": "-q synth",
        "LSF_FM_ARGS": "-q formal",
        "SYN_DONT_USE": "none",
        "SYN_OPERATING_CONDITION_LIBRARY": (
            "ics55_LLSC_H7CR_typ_tt_1p2_25"
        ),
        "SYN_OPERATING_CONDITION": "typical",
        "STD_DB_TYP": f"{h7ch} {h7cl} {h7cr}",
        "SYN_STD_DB_TYP": f"{h7cl} {h7cr}",
        "IO_DB_TYP": touch("io_typ.db"),
        "SRAM_DB_TYP": touch("sram_typ.db"),
        "PLL_DB": touch("pll_typ.db"),
        "ICS55_PLL_SUPPORTED_SEL": "0",
        "ICS55_PLL_N": "2",
        "ICS55_PLL_OD": "2",
        "IO_TIMING_QUALIFIED": "NO",
    }
    result = subprocess.run(
        [
            sys.executable,
            str(FLOW / "scripts/doctor.py"),
            "--dev",
            "--allow-internal-qor",
            "--output",
            str(tmp_path / "doctor.json"),
        ],
        env=environment,
        text=True,
        capture_output=True,
        check=False,
    )
    assert result.returncode == 0, result.stderr


def test_ics55_pll_wrapper(tmp_path: Path) -> None:
    iverilog = shutil.which("iverilog")
    vvp = shutil.which("vvp")
    if iverilog is None or vvp is None:
        pytest.skip("iverilog and vvp are not installed")

    output = tmp_path / "tc_pll"
    subprocess.run(
        [
            iverilog,
            "-g2012",
            "-DPDK_ICS55",
            "-DHAVE_PLL",
            "-s",
            "tc_pll_ics55_tb",
            "-o",
            str(output),
            str(ROOT / "rtl/tech/tc_pll.sv"),
            str(ROOT / "tests/rtl/tc_pll_ics55_tb.sv"),
        ],
        check=True,
        cwd=ROOT,
    )
    result = subprocess.run(
        [vvp, str(output)],
        text=True,
        capture_output=True,
        check=True,
        cwd=ROOT,
    )
    assert "TC_PLL_ICS55_PASS" in result.stdout


def test_local_production_configuration_is_ignored() -> None:
    for name in ("ics55-production.mk", "ics55-mini.mk", "ics55-tiny.mk"):
        local = FLOW / "local" / name
        result = subprocess.run(
            ["git", "check-ignore", str(local.relative_to(ROOT))],
            cwd=ROOT,
            check=False,
        )
        assert result.returncode == 0


CONSTRAINT_SMOKE_TCL = r"""
set soc [lindex $argv 0]
set ::env(SOC) $soc
set ::env(TOP) [expr {$soc eq "TINY" ? "retrosoc_tiny_asic" : "retrosoc_asic"}]
set ::env(RUN_ROOT) [lindex $argv 1]
set ::env(CLOCK_SETUP_UNCERTAINTY_NS) 0.2
set ::env(CLOCK_HOLD_UNCERTAINTY_NS) 0.1
set ::env(CLOCK_TRANSITION_NS) 0.1
set ::env(IO_TIMING_QUALIFIED) NO
set ::env(MAX_TRANSITION_NS) 0.5
set ::env(MAX_FANOUT) 32
if {$soc eq "MINI"} { set ::env(PLL_OUTPUT_PERIOD_NS) 13.888888889 }

set ::created_clocks_named {}
set ::generated_clocks {}
set ::clock_groups {}
set ::false_paths 0

proc get_ports {args} { return [lindex $args end] }
proc get_pins {args} { return [list pin_[string map {/ _} [lindex $args end]]] }
proc get_nets {args} { return [list net_[lindex $args end]] }
proc filter_collection {args} { return [list driver] }
proc sizeof_collection {c} { return [llength $c] }
proc get_clocks {args} { return [lindex $args end] }
proc create_clock {args} {
    lappend ::created_clocks_named [lindex $args [expr {[lsearch $args -name] + 1}]]
}
proc create_generated_clock {args} {
    lappend ::generated_clocks [lindex $args [expr {[lsearch $args -name] + 1}]]
}
proc set_clock_groups {args} { lappend ::clock_groups $args }
proc set_clock_uncertainty {args} {}
proc set_clock_transition {args} {}
proc set_false_path {args} { incr ::false_paths }
proc all_inputs {} { return {} }
proc all_outputs {} { return {} }
proc current_design {args} { return {} }
proc set_max_transition {args} {}
proc set_max_fanout {args} {}

source [file join $::env(FLOW_ROOT) tcl common common.tcl]
source [file join $::env(FLOW_ROOT) tcl common constraints.tcl]
flow::apply_constraints
puts "masters=$::created_clocks_named"
puts "generated=$::generated_clocks"
puts "groups=[llength $::clock_groups]"
puts "false_paths=$::false_paths"
flow::require_commercial_clock_inventory
puts "inventory-ok"
"""

CONSTRAINT_SMOKE_CASES = {
    "MINI": {
        "domains": "rtl/mini/integration/clock_reset_domains.json",
        "pin_map": "rtl/mini/pin_map/pin_map.json",
        "masters": (
            "clk_aon clk_hp clk_memory clk_audio clk_jtag clk_dvp "
            "clk_usb2_ulpi clk_pll"
        ),
        "generated": "clk_lp_ext clk_lp_pll clk_pclk_ext clk_pclk_pll",
        "groups": "2",
    },
    "TINY": {
        "domains": "rtl/tiny/integration/clock_reset_domains.json",
        "pin_map": "rtl/tiny/pin_map/pin_map.json",
        "masters": "clk_system clk_jtag",
        "generated": "",
        "groups": "1",
    },
}


@pytest.mark.parametrize("soc", sorted(CONSTRAINT_SMOKE_CASES))
def test_constraint_stack_models_product_clocks(tmp_path: Path, soc: str) -> None:
    case = CONSTRAINT_SMOKE_CASES[soc]
    run_root = tmp_path / soc.lower()
    contract = run_root / "input/rtl/contracts/commercial_timing_contract.tcl"
    contract.parent.mkdir(parents=True)
    subprocess.run(
        [
            sys.executable,
            str(FLOW / "scripts/generate_timing_contract.py"),
            "--soc",
            soc,
            "--domains",
            str(ROOT / case["domains"]),
            "--pin-map",
            str(ROOT / case["pin_map"]),
            "--output",
            str(contract),
        ],
        check=True,
    )
    environment = dict(os.environ)
    environment["FLOW_ROOT"] = str(FLOW)
    script = CONSTRAINT_SMOKE_TCL.replace(
        "set soc [lindex $argv 0]", f"set soc {soc}"
    ).replace(
        "set ::env(RUN_ROOT) [lindex $argv 1]", f"set ::env(RUN_ROOT) {run_root}"
    )
    result = subprocess.run(
        ["tclsh"],
        input=script,
        text=True,
        capture_output=True,
        check=False,
        env=environment,
    )
    assert result.returncode == 0, result.stderr
    lines = dict(
        line.split("=", 1)
        for line in result.stdout.strip().splitlines()
        if "=" in line
    )
    assert lines["masters"] == case["masters"]
    assert lines["generated"].strip("-") == case["generated"]
    assert lines["groups"] == case["groups"]
    assert "inventory-ok" in result.stdout


def test_commercial_make_graph_covers_both_products(tmp_path: Path) -> None:
    stub = tmp_path / "local.mk"
    stub.write_text("", encoding="utf-8")
    for soc in ("MINI", "TINY"):
        result = subprocess.run(
            [
                "make",
                "-C",
                str(FLOW),
                "-n",
                "signoff",
                f"SOC={soc}",
                f"LOCAL_CONFIG={stub}",
                "RUN_ID=pytest",
            ],
            text=True,
            capture_output=True,
            check=False,
        )
        assert result.returncode == 0, result.stderr
        assert f"build/commercial/ics55/{soc.lower()}/pytest" in result.stdout
        for stage in ("syn", "apr-route", "extract", "sta", "pv-lvs", "pv-macro-lvs"):
            assert f"--stage {stage} " in result.stdout or f"--stage {stage}\n" in (
                result.stdout + "\n"
            )
