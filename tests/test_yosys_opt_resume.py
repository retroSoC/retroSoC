from __future__ import annotations

import json
import shutil
import subprocess
from pathlib import Path

import pytest

from scripts.yosys_opt_resume import backend_script, frontend_script, optimize, run_synthesis

pytestmark = pytest.mark.skipif(shutil.which("yosys") is None, reason="yosys is unavailable")


def prepare_input(root: Path) -> Path:
    source = root / "fixture.v"
    source.write_text(
        "module test(input clk, input rst, output reg [1:0] q);\n"
        "always @(posedge clk) begin\n"
        "  if (rst) q <= 2'b00;\n"
        "  else q <= 2'b00;\n"
        "end\n"
        "endmodule\n",
        encoding="utf-8",
    )
    checkpoint = root / "preloop.il"
    subprocess.run(
        [
            "yosys",
            "-Q",
            "-p",
            f"read_verilog {source}; hierarchy -check -top test; proc; opt_expr; opt_merge -nomux; write_rtlil {checkpoint}",
        ],
        cwd=root,
        check=True,
        capture_output=True,
        text=True,
    )
    return checkpoint


def canonicalize(root: Path, checkpoint: Path, name: str) -> Path:
    canonical = root / name
    subprocess.run(
        ["yosys", "-Q", "-p", f"read_rtlil {checkpoint}; write_rtlil -sort {canonical}"],
        cwd=root,
        check=True,
        capture_output=True,
        text=True,
    )
    return canonical


def test_plain_opt_converges_to_native_rtlil_and_reuses_state(tmp_path: Path) -> None:
    preloop = prepare_input(tmp_path)
    native = tmp_path / "native.il"
    subprocess.run(
        ["yosys", "-Q", "-p", f"read_rtlil {preloop}; opt; write_rtlil {native}"],
        cwd=tmp_path,
        check=True,
        capture_output=True,
        text=True,
    )
    checkpointed = tmp_path / "checkpointed.il"
    work = tmp_path / "work"

    summary = optimize(tmp_path, preloop, checkpointed, work, max_iterations=8, iteration_timeout=60)

    assert summary["status"] == "converged"
    assert summary["completed_iterations"] == 2
    assert summary["iterations"][0]["did_something"] is True
    assert summary["iterations"][1]["did_something"] is False
    native_canonical = canonicalize(tmp_path, native, "native-canonical.il")
    checkpointed_canonical = canonicalize(tmp_path, checkpointed, "checkpointed-canonical.il")
    assert native_canonical.read_bytes() == checkpointed_canonical.read_bytes()

    previous_mtime = checkpointed.stat().st_mtime_ns
    resumed = optimize(tmp_path, preloop, checkpointed, work, max_iterations=8, iteration_timeout=60)
    assert resumed["status"] == "converged"
    assert checkpointed.stat().st_mtime_ns == previous_mtime


def test_iteration_limit_fails_and_retains_evidence(tmp_path: Path) -> None:
    preloop = prepare_input(tmp_path)
    work = tmp_path / "work"
    with pytest.raises(RuntimeError, match="did not converge within 1 iterations"):
        optimize(tmp_path, preloop, tmp_path / "final.il", work, max_iterations=1, iteration_timeout=60)

    summary = json.loads((work / "summary.json").read_text(encoding="utf-8"))
    assert summary["status"] == "bound_reached"
    assert summary["completed_iterations"] == 1
    assert summary["output_sha256"] is None
    assert (work / "iterations/01/yosys.log").is_file()
    assert (work / "iterations/01/stat.rpt").is_file()


def test_resume_rejects_changed_input_and_invalid_state(tmp_path: Path) -> None:
    preloop = prepare_input(tmp_path)
    work = tmp_path / "work"
    output = tmp_path / "final.il"
    optimize(tmp_path, preloop, output, work, max_iterations=8, iteration_timeout=60)
    preloop.write_text(preloop.read_text(encoding="utf-8") + "\n# changed input\n", encoding="utf-8")
    with pytest.raises(ValueError, match="digest does not match"):
        optimize(tmp_path, preloop, output, work, max_iterations=8, iteration_timeout=60)

    (work / "state.json").write_text("{not-json\n", encoding="utf-8")
    with pytest.raises(ValueError, match="cannot read JSON"):
        optimize(tmp_path, preloop, output, work, max_iterations=8, iteration_timeout=60)


def test_synth_script_split_preserves_all_other_commands() -> None:
    text = (
        "set script_dir [file dirname [info script]]\n"
        "source $script_dir/common.tcl\n"
        "source $script_dir/init_tech.tcl\n"
        "yosys opt -full\n"
        "yosys opt\n"
        "yosys opt -fast\n"
        "yosys opt\n"
    )
    frontend = frontend_script(text)
    backend = backend_script(text)
    assert "set script_dir $::env(YOSYS_SCRIPT_DIR)" in frontend
    assert "set script_dir $::env(YOSYS_SCRIPT_DIR)" in backend
    assert "set script_dir [file dirname [info script]]" not in frontend
    assert "set script_dir [file dirname [info script]]" not in backend
    assert "yosys opt -full\n" in frontend
    assert "yosys opt_expr\nyosys opt_merge -nomux\nyosys write_rtlil $::env(OPT_PRELOOP)\n" in frontend
    assert "yosys opt\n" not in frontend
    assert "yosys opt -full\n" not in backend
    assert backend.startswith(
        "set script_dir $::env(YOSYS_SCRIPT_DIR)\n"
        "source $script_dir/common.tcl\n"
        "source $script_dir/init_tech.tcl\n"
        "yosys read_rtlil $::env(OPT_FINAL)\n"
    )
    assert backend.endswith("yosys opt -fast\nyosys opt\n")
    assert backend.count("yosys opt\n") == 1


def test_synthesis_driver_runs_frontend_optimizer_and_backend(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    source = tmp_path / "fixture.v"
    source.write_text(
        "module test(input clk, input rst, output reg [1:0] q);\n"
        "always @(posedge clk) begin\n"
        "  if (rst) q <= 2'b00;\n"
        "  else q <= 2'b00;\n"
        "end\n"
        "endmodule\n",
        encoding="utf-8",
    )
    (tmp_path / "common.tcl").write_text("set report_dir $::env(REPORTS)\n", encoding="utf-8")
    (tmp_path / "init_tech.tcl").write_text('set tech_loaded "yes"\n', encoding="utf-8")
    reports = tmp_path / "reports"
    reports.mkdir()
    script = tmp_path / "synth.tcl"
    script.write_text(
        "set script_dir [file dirname [info script]]\n"
        "source $script_dir/common.tcl\n"
        "source $script_dir/init_tech.tcl\n"
        f"yosys read_verilog {source}\n"
        "yosys hierarchy -check -top test\n"
        "yosys proc\n"
        "yosys opt\n"
        'if {$tech_loaded ne "yes"} {error "technology setup missing"}\n'
        'yosys tee -q -o "${report_dir}/backend.rpt" stat\n'
        "yosys write_verilog -norename $::env(NETLIST)\n",
        encoding="utf-8",
    )
    netlist = tmp_path / "netlist.v"
    monkeypatch.setenv("NETLIST", str(netlist))
    monkeypatch.setenv("REPORTS", str(reports))

    summary = run_synthesis(tmp_path, script, tmp_path / "work", max_iterations=8, iteration_timeout=60, frontend_timeout=60)

    assert summary["status"] == "passed"
    assert summary["opt"]["status"] == "converged"
    assert summary["opt"]["completed_iterations"] == 2
    assert summary["backend"]["status"] == "passed"
    assert netlist.is_file()
    assert (reports / "backend.rpt").is_file()
    assert (tmp_path / "work/synthesis-summary.json").is_file()


def test_makefile_defaults_to_native_synthesis() -> None:
    root = Path(__file__).resolve().parents[1]
    makefile = " ".join((root / "physical/smoke/syn/yosys/yosys.mk").read_text(encoding="utf-8").split())
    assert "YOSYS_OPT_RESUME ?= NO" not in makefile
    assert "YOSYS_OPT_ITERATION_TIMEOUT ?= 600" not in makefile
    assert "YOSYS_OPT_MAX_ITERATIONS ?= 64" not in makefile
    assert "--max-iterations $(if $(YOSYS_OPT_MAX_ITERATIONS),$(YOSYS_OPT_MAX_ITERATIONS),64)" in makefile
    assert "--iteration-timeout $(if $(YOSYS_OPT_ITERATION_TIMEOUT),$(YOSYS_OPT_ITERATION_TIMEOUT),600)" in makefile
    assert "YOSYS_TIMEOUT ?= 10800" in makefile
    assert "YOSYS_COMMAND = $(if $(filter YES,$(YOSYS_OPT_RESUME)),$(YOSYS_RESUME_COMMAND),$(YOSYS_NATIVE_COMMAND))" in makefile
    assert "yosys -t --perffile $(YOSYS_BUILD)/yosys-perf.json -c $(YOSYS_DIR)/script/synth.tcl" in makefile
