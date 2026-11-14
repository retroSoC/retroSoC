from __future__ import annotations

import json
import shutil
import subprocess
from pathlib import Path

import pytest

from scripts.yosys_opt_resume import (
    atomic_write,
    backend_script,
    frontend_script,
    optimize,
    run_synthesis,
    run_yosys,
)

pytestmark = pytest.mark.skipif(shutil.which("yosys") is None, reason="yosys is unavailable")


def prepare_input(root: Path, *, chained: bool = False) -> Path:
    source = root / "fixture.v"
    if chained:
        text = (
            "module test(input clk, input rst, output reg [1:0] q);\n"
            "reg [1:0] q0;\n"
            "always @(posedge clk) begin\n"
            "  if (rst) begin q0 <= 2'b00; q <= 2'b00; end\n"
            "  else begin q0 <= 2'b00; q <= q0; end\n"
            "end\n"
            "endmodule\n"
        )
    else:
        text = (
            "module test(input clk, input rst, output reg [1:0] q);\n"
            "always @(posedge clk) begin\n"
            "  if (rst) q <= 2'b00;\n"
            "  else q <= 2'b00;\n"
            "end\n"
            "endmodule\n"
        )
    source.write_text(text, encoding="utf-8")
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


def interrupt_after_iteration(
    root: Path,
    preloop: Path,
    output: Path,
    work: Path,
    monkeypatch: pytest.MonkeyPatch,
    completed_iteration: int,
) -> None:
    interrupted = False

    def interrupt(path: Path, content: str) -> bool:
        nonlocal interrupted
        if Path(path) == work / "state.json" and json.loads(content).get("next_iteration") == completed_iteration + 1 and not interrupted:
            interrupted = True
            raise RuntimeError("test interruption after iteration")
        return atomic_write(path, content)

    monkeypatch.setattr("scripts.yosys_opt_resume.atomic_write", interrupt)
    with pytest.raises(RuntimeError, match="test interruption after iteration"):
        optimize(root, preloop, output, work, max_iterations=8, iteration_timeout=60)
    monkeypatch.setattr("scripts.yosys_opt_resume.atomic_write", atomic_write)
    assert interrupted
    assert (work / "iterations" / f"{completed_iteration:02d}/identity.json").is_file()


def interrupt_after_first_iteration(root: Path, preloop: Path, output: Path, work: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    interrupt_after_iteration(root, preloop, output, work, monkeypatch, completed_iteration=1)


def test_iteration_cache_recovers_replaced_current(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    preloop = prepare_input(tmp_path, chained=True)
    output = tmp_path / "final.il"
    work = tmp_path / "work"
    interrupt_after_iteration(tmp_path, preloop, output, work, monkeypatch, completed_iteration=2)
    stages: list[str] = []

    def record_run(
        root: Path,
        command: list[str],
        *,
        log: Path,
        result: Path,
        timeout: int,
        environment: dict[str, str] | None = None,
    ) -> dict[str, object]:
        stages.append(log.parent.name)
        return run_yosys(root, command, log=log, result=result, timeout=timeout, environment=environment)

    monkeypatch.setattr("scripts.yosys_opt_resume.run_yosys", record_run)
    summary = optimize(tmp_path, preloop, output, work, max_iterations=8, iteration_timeout=60)

    assert summary["status"] == "converged"
    assert summary["completed_iterations"] == 3
    assert stages == ["03"]
    native = tmp_path / "native.il"
    subprocess.run(
        ["yosys", "-Q", "-p", f"read_rtlil {preloop}; opt; write_rtlil {native}"],
        cwd=tmp_path,
        check=True,
        capture_output=True,
        text=True,
    )
    native_canonical = canonicalize(tmp_path, native, "native-canonical.il")
    resumed_canonical = canonicalize(tmp_path, output, "resumed-canonical.il")
    assert native_canonical.read_bytes() == resumed_canonical.read_bytes()
    stages.clear()
    optimize(tmp_path, preloop, output, work, max_iterations=8, iteration_timeout=60)
    assert stages == []


@pytest.mark.parametrize("damage", ["current", "identity"])
def test_interrupted_current_requires_identity_chain(tmp_path: Path, monkeypatch: pytest.MonkeyPatch, damage: str) -> None:
    preloop = prepare_input(tmp_path, chained=True)
    output = tmp_path / "final.il"
    work = tmp_path / "work"
    interrupt_after_iteration(tmp_path, preloop, output, work, monkeypatch, completed_iteration=2)
    current = work / "current.il"
    if damage == "current":
        current.write_bytes(current.read_bytes() + b"\n# mutated current\n")
    else:
        (work / "iterations/02/identity.json").unlink()

    def unexpected_run(*args: object, **kwargs: object) -> None:
        raise AssertionError("an invalid current identity chain must not be reused")

    monkeypatch.setattr("scripts.yosys_opt_resume.run_yosys", unexpected_run)
    with pytest.raises(ValueError, match="current digest does not match"):
        optimize(tmp_path, preloop, output, work, max_iterations=8, iteration_timeout=60)


def test_iteration_cache_reuses_valid_completed_iteration(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    preloop = prepare_input(tmp_path)
    output = tmp_path / "final.il"
    work = tmp_path / "work"
    interrupt_after_first_iteration(tmp_path, preloop, output, work, monkeypatch)
    stages: list[str] = []

    def record_run(
        root: Path,
        command: list[str],
        *,
        log: Path,
        result: Path,
        timeout: int,
        environment: dict[str, str] | None = None,
    ) -> dict[str, object]:
        stages.append(log.parent.name)
        return run_yosys(root, command, log=log, result=result, timeout=timeout, environment=environment)

    monkeypatch.setattr("scripts.yosys_opt_resume.run_yosys", record_run)
    summary = optimize(tmp_path, preloop, output, work, max_iterations=8, iteration_timeout=60)

    assert summary["status"] == "converged"
    assert summary["completed_iterations"] == 2
    assert stages == ["02"]
    state = json.loads((work / "state.json").read_text(encoding="utf-8"))
    identity = json.loads((work / "iterations/01/identity.json").read_text(encoding="utf-8"))
    assert state["iterations"][0]["identity"] == identity
    assert set(identity) == {"schema_version", "iteration", "input", "script", "output", "did", "result"}

    native = tmp_path / "native.il"
    subprocess.run(
        ["yosys", "-Q", "-p", f"read_rtlil {preloop}; opt; write_rtlil {native}"],
        cwd=tmp_path,
        check=True,
        capture_output=True,
        text=True,
    )
    native_canonical = canonicalize(tmp_path, native, "native-canonical.il")
    resumed_canonical = canonicalize(tmp_path, output, "resumed-canonical.il")
    assert native_canonical.read_bytes() == resumed_canonical.read_bytes()
    stages.clear()
    optimize(tmp_path, preloop, output, work, max_iterations=8, iteration_timeout=60)
    assert stages == []


@pytest.mark.parametrize("artifact", ["next.il", "did-something.txt", "result.json"])
def test_iteration_cache_rejects_mutated_artifacts(tmp_path: Path, monkeypatch: pytest.MonkeyPatch, artifact: str) -> None:
    preloop = prepare_input(tmp_path)
    output = tmp_path / "final.il"
    work = tmp_path / "work"
    interrupt_after_first_iteration(tmp_path, preloop, output, work, monkeypatch)
    retained = work / "iterations/01" / artifact
    if artifact == "result.json":
        result = json.loads(retained.read_text(encoding="utf-8"))
        result["duration_seconds"] += 1
        retained.write_text(json.dumps(result), encoding="utf-8")
    elif artifact == "did-something.txt":
        retained.write_text(retained.read_text(encoding="utf-8") + "\ntrue\n", encoding="utf-8")
    else:
        retained.write_bytes(retained.read_bytes() + b"\n# mutated artifact\n")

    def unexpected_run(*args: object, **kwargs: object) -> None:
        raise AssertionError("corrupted iteration artifacts must not be reused")

    monkeypatch.setattr("scripts.yosys_opt_resume.run_yosys", unexpected_run)
    current = work / "current.il"
    current_bytes = current.read_bytes()
    with pytest.raises(ValueError, match="iteration identity mismatch"):
        optimize(tmp_path, preloop, output, work, max_iterations=8, iteration_timeout=60)
    assert current.read_bytes() == current_bytes


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


def prepare_synthesis(root: Path) -> Path:
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
    (root / "sources.fl").write_text(f"{source}\n", encoding="utf-8")
    (root / "common.tcl").write_text("set report_dir $::env(REPORTS)\n", encoding="utf-8")
    (root / "init_tech.tcl").write_text('set tech_loaded "yes"\n', encoding="utf-8")
    (root / "reports").mkdir()
    script = root / "synth.tcl"
    script.write_text(
        "set script_dir [file dirname [info script]]\n"
        "source $script_dir/common.tcl\n"
        "source $script_dir/init_tech.tcl\n"
        "yosys read_slang --top test -F $::env(SV_FLIST)\n"
        "yosys hierarchy -check -top test\n"
        "yosys proc\n"
        "yosys opt\n"
        'if {$tech_loaded ne "yes"} {error "technology setup missing"}\n'
        'yosys tee -q -o "${report_dir}/backend.rpt" stat\n'
        "yosys write_verilog -norename $::env(NETLIST)\n",
        encoding="utf-8",
    )
    return script


def run_synthesis_fixture(root: Path, script: Path) -> dict[str, object]:
    return run_synthesis(root, script, root / "work", max_iterations=8, iteration_timeout=60, frontend_timeout=60)


def test_synthesis_driver_runs_frontend_optimizer_and_backend(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    script = prepare_synthesis(tmp_path)
    netlist = tmp_path / "netlist.v"
    monkeypatch.setenv("NETLIST", str(netlist))
    monkeypatch.setenv("REPORTS", str(tmp_path / "reports"))
    monkeypatch.setenv("SV_FLIST", str(tmp_path / "sources.fl"))

    summary = run_synthesis_fixture(tmp_path, script)

    assert summary["status"] == "passed"
    assert summary["opt"]["status"] == "converged"
    assert summary["opt"]["completed_iterations"] == 2
    assert summary["backend"]["status"] == "passed"
    assert netlist.is_file()
    assert (tmp_path / "reports/backend.rpt").is_file()
    assert (tmp_path / "work/synthesis-summary.json").is_file()
    assert (tmp_path / "work/cache-frontend.json").is_file()
    assert (tmp_path / "work/cache-backend.json").is_file()


def test_synthesis_cache_revalidates_identity(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    script = prepare_synthesis(tmp_path)
    netlist = tmp_path / "netlist.v"
    monkeypatch.setenv("NETLIST", str(netlist))
    monkeypatch.setenv("REPORTS", str(tmp_path / "reports"))
    monkeypatch.setenv("SV_FLIST", str(tmp_path / "sources.fl"))
    run_synthesis_fixture(tmp_path, script)
    stages: list[str] = []

    def record_run(
        root: Path,
        command: list[str],
        *,
        log: Path,
        result: Path,
        timeout: int,
        environment: dict[str, str] | None = None,
    ) -> dict[str, object]:
        stages.append(log.name)
        return run_yosys(root, command, log=log, result=result, timeout=timeout, environment=environment)

    monkeypatch.setattr("scripts.yosys_opt_resume.run_yosys", record_run)
    run_synthesis_fixture(tmp_path, script)
    assert stages == []

    source = tmp_path / "fixture.v"
    original_source = source.read_bytes()
    source.write_text(source.read_text(encoding="utf-8").replace("else q <= 2'b00;", "else q <= 2'b01;"), encoding="utf-8")
    with pytest.raises(ValueError, match="input digest does not match"):
        run_synthesis_fixture(tmp_path, script)
    assert stages == ["frontend.log"]
    stages.clear()
    source.write_bytes(original_source)
    run_synthesis_fixture(tmp_path, script)
    assert stages == ["frontend.log"]
    stages.clear()

    script.write_text(
        script.read_text(encoding="utf-8").replace(
            "yosys write_verilog -norename $::env(NETLIST)\n",
            "yosys opt_clean\nyosys write_verilog -norename $::env(NETLIST)\n",
        ),
        encoding="utf-8",
    )
    run_synthesis_fixture(tmp_path, script)
    assert stages == ["frontend.log", "backend.log"]
    stages.clear()

    changed_reports = tmp_path / "reports-changed"
    changed_reports.mkdir()
    monkeypatch.setenv("REPORTS", str(changed_reports))
    run_synthesis_fixture(tmp_path, script)
    assert stages == ["frontend.log", "backend.log"]
    stages.clear()

    expected_netlist = netlist.read_bytes()
    netlist.write_bytes(expected_netlist + b"\n// stale netlist\n")
    run_synthesis_fixture(tmp_path, script)
    assert stages == ["backend.log"]
    assert netlist.read_bytes() == expected_netlist
    stages.clear()

    preloop = tmp_path / "work/preloop.il"
    preloop.write_text(preloop.read_text(encoding="utf-8") + "\n# stale preloop\n", encoding="utf-8")
    run_synthesis_fixture(tmp_path, script)
    assert stages == ["frontend.log"]


def test_synthesis_opt_resume_rejects_unclassified_environment_drift(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    script = prepare_synthesis(tmp_path)
    monkeypatch.setenv("NETLIST", str(tmp_path / "netlist.v"))
    monkeypatch.setenv("REPORTS", str(tmp_path / "reports"))
    monkeypatch.setenv("SV_FLIST", str(tmp_path / "sources.fl"))
    run_synthesis_fixture(tmp_path, script)

    monkeypatch.setenv("PPALITE_TEST_UNCLASSIFIED_ENV", "changed")
    with pytest.raises(ValueError, match="synthesis optimizer environment mismatch"):
        run_synthesis_fixture(tmp_path, script)


def test_synthesis_rejects_environment_drift_before_optimizer_state(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    script = prepare_synthesis(tmp_path)
    monkeypatch.setenv("NETLIST", str(tmp_path / "netlist.v"))
    monkeypatch.setenv("REPORTS", str(tmp_path / "reports"))
    monkeypatch.setenv("SV_FLIST", str(tmp_path / "sources.fl"))

    def interrupt_before_optimize(*args: object, **kwargs: object) -> None:
        raise RuntimeError("interrupted before optimizer state")

    monkeypatch.setattr("scripts.yosys_opt_resume.optimize", interrupt_before_optimize)
    with pytest.raises(RuntimeError, match="interrupted before optimizer state"):
        run_synthesis_fixture(tmp_path, script)
    assert not (tmp_path / "work/state.json").exists()
    monkeypatch.setattr("scripts.yosys_opt_resume.optimize", optimize)

    monkeypatch.setenv("PPALITE_TEST_UNCLASSIFIED_ENV", "changed")
    with pytest.raises(ValueError, match="synthesis optimizer environment mismatch"):
        run_synthesis_fixture(tmp_path, script)


def test_synthesis_rebuilds_classified_environment_in_real_git_worktree(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    script = prepare_synthesis(tmp_path)
    (tmp_path / ".gitignore").write_text("work/\nnetlist.v\nreports*/\n", encoding="utf-8")
    subprocess.run(["git", "init", "-q"], cwd=tmp_path, check=True, capture_output=True)
    subprocess.run(
        ["git", "add", "--", ".gitignore", "common.tcl", "fixture.v", "init_tech.tcl", "sources.fl", "synth.tcl"],
        cwd=tmp_path,
        check=True,
        capture_output=True,
    )
    subprocess.run(
        ["git", "-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid", "commit", "-qm", "fixture"],
        cwd=tmp_path,
        check=True,
        capture_output=True,
    )
    monkeypatch.setenv("NETLIST", str(tmp_path / "netlist.v"))
    monkeypatch.setenv("REPORTS", str(tmp_path / "reports"))
    monkeypatch.setenv("SV_FLIST", str(tmp_path / "sources.fl"))
    run_synthesis_fixture(tmp_path, script)

    stages: list[str] = []

    def record_run(
        root: Path,
        command: list[str],
        *,
        log: Path,
        result: Path,
        timeout: int,
        environment: dict[str, str] | None = None,
    ) -> dict[str, object]:
        stages.append(log.name)
        return run_yosys(root, command, log=log, result=result, timeout=timeout, environment=environment)

    monkeypatch.setattr("scripts.yosys_opt_resume.run_yosys", record_run)
    changed_reports = tmp_path / "reports-changed"
    changed_reports.mkdir()
    monkeypatch.setenv("REPORTS", str(changed_reports))
    run_synthesis_fixture(tmp_path, script)
    assert stages == ["frontend.log", "backend.log"]

    script.write_text(script.read_text(encoding="utf-8") + "# tracked drift\n", encoding="utf-8")
    with pytest.raises(ValueError, match="source_state_sha256"):
        run_synthesis_fixture(tmp_path, script)


def test_resume_rejects_changed_final_checkpoint(tmp_path: Path) -> None:
    preloop = prepare_input(tmp_path)
    work = tmp_path / "work"
    output = tmp_path / "final.il"
    optimize(tmp_path, preloop, output, work, max_iterations=8, iteration_timeout=60)
    final_bytes = output.read_bytes()
    output.write_bytes(final_bytes + b"\n# stale final\n")
    with pytest.raises(ValueError, match="output digest does not match"):
        optimize(tmp_path, preloop, output, work, max_iterations=8, iteration_timeout=60)

    output.write_bytes(final_bytes)
    current = work / "current.il"
    current.write_text(current.read_text(encoding="utf-8") + "\n# stale current\n", encoding="utf-8")
    with pytest.raises(ValueError, match="current digest does not match"):
        optimize(tmp_path, preloop, output, work, max_iterations=8, iteration_timeout=60)


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


def test_converged_state_still_rejects_corrupted_iteration(tmp_path: Path) -> None:
    preloop = prepare_input(tmp_path)
    work = tmp_path / "work"
    output = tmp_path / "final.il"
    optimize(tmp_path, preloop, output, work, max_iterations=8, iteration_timeout=60)
    checkpoint = work / "iterations/01/next.il"
    checkpoint.write_text(checkpoint.read_text(encoding="utf-8") + "\n# corrupted\n", encoding="utf-8")
    with pytest.raises(ValueError, match="checkpoint digest mismatch"):
        optimize(tmp_path, preloop, output, work, max_iterations=8, iteration_timeout=60)


def synthesis_fixture(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> tuple[Path, Path]:
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
        "yosys write_verilog -norename $::env(NETLIST)\n",
        encoding="utf-8",
    )
    netlist = tmp_path / "netlist.v"
    monkeypatch.setenv("NETLIST", str(netlist))
    monkeypatch.setenv("REPORTS", str(tmp_path / "reports"))
    return script, netlist


def test_synthesis_reuses_valid_outputs_and_rejects_drift(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    script, netlist = synthesis_fixture(tmp_path, monkeypatch)
    work = tmp_path / "work"
    first = run_synthesis(tmp_path, script, work, max_iterations=8, iteration_timeout=60, frontend_timeout=60)
    assert first["schema_version"] == 2
    assert first["fingerprint"]["script_sha256"]
    original_mtime = netlist.stat().st_mtime_ns

    resumed = run_synthesis(tmp_path, script, work, max_iterations=8, iteration_timeout=60, frontend_timeout=60)
    assert resumed["status"] == "passed"
    assert netlist.stat().st_mtime_ns == original_mtime

    netlist.write_text(netlist.read_text(encoding="utf-8") + "// drift\n", encoding="utf-8")
    with pytest.raises(ValueError, match="backend output digest"):
        run_synthesis(tmp_path, script, work, max_iterations=8, iteration_timeout=60, frontend_timeout=60)

    script.write_text(script.read_text(encoding="utf-8") + "# drift\n", encoding="utf-8")
    with pytest.raises(ValueError, match="synthesis fingerprint mismatch"):
        run_synthesis(tmp_path, script, work, max_iterations=8, iteration_timeout=60, frontend_timeout=60)


def test_optimize_rejects_an_active_work_directory_lease(tmp_path: Path) -> None:
    from scripts.flow_control import Lease

    work = tmp_path / "work"
    with Lease(work / "optimize.lock", {"task_id": "test-owner"}):
        with pytest.raises(RuntimeError, match="active lease"):
            optimize(tmp_path, tmp_path / "input.il", tmp_path / "output.il", work, max_iterations=1, iteration_timeout=1)
