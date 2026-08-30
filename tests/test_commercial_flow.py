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


def test_spef_checker_requires_every_named_corner(tmp_path: Path) -> None:
    checker = load_script("check_outputs")
    for corner in checker.SPEF_CORNERS:
        (tmp_path / f"retrosoc_asic.{corner}.spef.gz").write_bytes(b"spef")
    assert checker.apply_check("spef", str(tmp_path), 0, "retrosoc_asic") is None
    (tmp_path / "retrosoc_asic.TYP_25.spef.gz").unlink()
    assert "missing ICS55 SPEF corners" in checker.apply_check(
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
    with tarfile.open(archive_path, "w") as archive:
        member = tarfile.TarInfo("rtl/filelist.fl")
        member.size = len(payload)
        member.mtime = 1
        archive.addfile(member, io.BytesIO(payload))
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
    example = (FLOW / "config/ics55.example.mk").read_text(encoding="utf-8")
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
        "TOP": "retrosoc_asic",
        "TECHNOLOGY": "ICS55",
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
    local = FLOW / "local/ics55-production.mk"
    result = subprocess.run(
        ["git", "check-ignore", str(local.relative_to(ROOT))],
        cwd=ROOT,
        check=False,
    )
    assert result.returncode == 0
