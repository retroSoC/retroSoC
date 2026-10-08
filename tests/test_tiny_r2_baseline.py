"""Independent workload expectations and fail-closed Tiny baseline evidence."""

from __future__ import annotations

import argparse
import copy
import json
import os
from pathlib import Path
import subprocess

import pytest

from scripts import tiny_r2_baseline as baseline


def log_fixture() -> str:
    """Small protocol records, not a mocked hardware qualification result."""
    lines = ["R2_HEADER version=1 cpu_hz=24000000 words=1024 jobs=16 iterations=4096 seed=0x12345678"]
    for index, name in enumerate(("empty", "cpu", "memory", "dma1", "dma16", "contention", "tcd")):
        calls = 1 if index == 1 else 16 if index >= 5 else 0
        checksum = 0 if index == 0 else 0xF6E37410 if index == 1 else 0xBC5F5DC5
        lines.append(
            f"R2_CASE id={index} name={name} cycles=1000000 instructions=100000 "
            f"kernel_cycles={calls * 1000} kernel_calls={calls} "
            f"payload_bytes={65536 if index >= 2 else 0} checksum={checksum} "
            "cpu_wait=11 dma_wait=7 sram_reads=30 sram_writes=20 sram_rbeats=32 "
            "sram_wbeats=24 sram_stalls=8 sram_errors=0"
        )
        for owner in range(2):
            payload = 65536 if owner == 1 and index >= 3 else 0
            descriptors = 4096 if owner == 1 and index == 6 else 0
            lines.append(
                f"R2_AXI window={index + 1} owner={owner} cycles=1000100 reads=2 writes=2 "
                f"read_done=2 write_done=2 read_bytes={payload} write_bytes={payload} "
                f"descriptor_bytes={descriptors} read_latency_max=9 write_latency_max=10 "
                "aw_stall_max=1 w_stall_max=2 b_stall_max=3 ar_stall_max=4 r_stall_max=5 "
                "pending_reads=0 pending_writes=0"
            )
            lines.append(f"R2_AHB window={index + 1} kind={owner} accepted=5 completed=5 latency_max=8")
    lines += ["R2_COMPLETE version=1 cases=7", "SIM_TEST_PASS Tiny cycles=1234567"]
    return "\n".join(lines)


PASS = {"status": "passed", "exit_code": 0}


def test_cpu_oracle_matches_a_bit_vector_reference() -> None:
    # A shift-register bit-vector formulation independent of the firmware's
    # integer shift expressions; checks every bit at the final iteration.
    bits = [(0x12345678 >> position) & 1 for position in range(32)]
    for _ in range(4096):
        bits = [bit ^ (bits[i - 13] if i >= 13 else 0) for i, bit in enumerate(bits)]
        bits = [bit ^ (bits[i + 17] if i < 15 else 0) for i, bit in enumerate(bits)]
        bits = [bit ^ (bits[i - 5] if i >= 5 else 0) for i, bit in enumerate(bits)]
    expected = sum(bit << index for index, bit in enumerate(bits))
    assert expected == 0xF6E37410 == baseline.cpu_checksum()


def test_complete_log_includes_both_monitors_and_dma_descriptor_bytes() -> None:
    parsed = baseline.parse_log(log_fixture(), PASS)
    assert len(parsed["case"]) == 7
    assert parsed["case"][5]["cpi"] == 10
    assert parsed["case"][6]["payload_bytes_per_cycle"] == 0.065536


@pytest.mark.parametrize("marker", ["FAILED", "FATAL", "assertion failed", "%Error",
                                    "SIM_TEST_FAIL", "SIM_TEST_TIMEOUT", "R2_ERROR"])
def test_a_later_pass_cannot_hide_an_error(marker: str) -> None:
    with pytest.raises(ValueError, match="failure marker"):
        baseline.parse_log(marker + "\n" + log_fixture(), PASS)


@pytest.mark.parametrize("result", [{"status": "passed", "exit_code": 1},
                                    {"status": "running", "exit_code": 0},
                                    {"status": "interrupted", "exit_code": 130}])
def test_terminal_marker_cannot_override_command_failure(result: dict) -> None:
    with pytest.raises(ValueError, match="command"):
        baseline.parse_log(log_fixture(), result)


def test_uart_records_do_not_replace_terminal_status() -> None:
    with pytest.raises(ValueError, match="terminal"):
        baseline.parse_log(log_fixture().replace("SIM_TEST_PASS Tiny", "Hello retroSoC!"), PASS)


@pytest.mark.parametrize("prefix", ["R2_HEADER", "R2_CASE", "R2_AXI", "R2_AHB", "R2_COMPLETE"])
@pytest.mark.parametrize("duplicate", [False, True])
def test_incomplete_or_duplicate_measurements_fail(prefix: str, duplicate: bool) -> None:
    lines = log_fixture().splitlines()
    index = next(i for i, line in enumerate(lines) if line.startswith(prefix))
    if duplicate:
        lines.append(lines[index])
    else:
        lines.pop(index)
    with pytest.raises(ValueError):
        baseline.parse_log("\n".join(lines), PASS)


@pytest.mark.parametrize("old,new", [
    ("cpu_hz=24000000", "cpu_hz=96000000"),
    ("checksum=4142101520", "checksum=1"),
    ("descriptor_bytes=4096", "descriptor_bytes=0"),
    ("read_bytes=65536", "read_bytes=69632"),
    ("write_bytes=65536", "write_bytes=65532"),
    ("sram_errors=0", "sram_errors=1"),
    ("completed=5", "completed=6"),
    ("read_done=2", "read_done=1"),
    ("instructions=100000", "instructions=0"),
    ("cycles=1000000", "cycles=-1"),
])
def test_wrong_data_clock_and_accounting_fail(old: str, new: str) -> None:
    content = log_fixture()
    assert old in content
    with pytest.raises(ValueError):
        baseline.parse_log(content.replace(old, new, 1), PASS)


def test_cpu_boundary_transaction_is_reported_as_pending() -> None:
    content = log_fixture().replace("write_done=2", "write_done=1", 1)
    content = content.replace("pending_writes=0", "pending_writes=1", 1)
    baseline.parse_log(content, PASS)


def test_observer_print_order_is_not_a_cycle_difference() -> None:
    lines = log_fixture().splitlines()
    observations = [line for line in lines if line.startswith(("R2_AXI", "R2_AHB"))]
    rest = [line for line in lines if not line.startswith(("R2_AXI", "R2_AHB"))]
    assert baseline.parse_log("\n".join(rest + observations[::-1]), PASS) == baseline.parse_log(
        log_fixture(), PASS)


def test_changed_artifact_cannot_keep_its_identity(tmp_path: Path) -> None:
    path = tmp_path / "sim.log"
    path.write_text(log_fixture())
    identity = baseline.artifact(path)
    assert baseline.check_artifact(identity) == path
    path.write_text(path.read_text() + "\nSIM_TEST_FAIL\n")
    with pytest.raises(ValueError, match="changed artifact"):
        baseline.check_artifact(identity)


def test_retained_image_keeps_original_source_identity(tmp_path: Path) -> None:
    evidence = tmp_path / "evidence"
    directory = evidence / "binaries/original"
    directory.mkdir(parents=True)
    image = directory / "tiny_baseline.hex"
    image.write_text("@0\n00\n")
    source = directory / "source.json"
    source.write_text("{}\n")
    value = {"status": "passed", "phase": baseline.PHASE, "parameters": baseline.PARAMETERS,
             "artifacts": {"tiny_baseline.hex": baseline.artifact(image)},
             "source": {"repository": {"commit": "original-revision"},
                        **{key: baseline.artifact(source) for key in ("inputs", "snapshot", "patch")}}}
    (directory / "image.json").write_text(json.dumps(value))
    baseline.dump(evidence / "binaries/latest.json", {"path": str(directory / "image.json")})
    _, retained = baseline.retained_image(evidence, None)
    assert retained["source"]["repository"]["commit"] == "original-revision"
    bad = copy.deepcopy(value)
    bad["status"] = "failed"
    (directory / "image.json").write_text(json.dumps(bad))
    with pytest.raises(ValueError, match="provenance"):
        baseline.retained_image(evidence, image)
    (directory / "image.json").write_text(json.dumps(value))
    image.write_text("@0\nff\n")
    with pytest.raises(ValueError, match="changed artifact"):
        baseline.retained_image(evidence, image)


def retained_runs(directory: Path, *, differing: bool = False) -> list[dict]:
    runs = []
    for repetition in range(1, 4):
        log = directory / f"run-{repetition}.log"
        content = log_fixture()
        if differing and repetition == 2:
            content = content.replace("cycles=1000000", "cycles=1000001", 1)
        log.write_text(content)
        flow = directory / f"run-{repetition}.json"
        flow.write_text(json.dumps({**PASS, "command": ["fixture"], "log": str(log)}))
        verdict = directory / f"verdict-{repetition}.json"
        verdict.write_text(json.dumps({"status": "passed", "log": str(log)}))
        runs.append({"repetition": repetition, "samples": baseline.parse_log(content, PASS),
                     "log": baseline.artifact(log), "flow": baseline.artifact(flow),
                     "verdict": baseline.artifact(verdict)})
    return runs


def test_aggregate_rechecks_repetitions_instead_of_trusting_pass_labels(tmp_path: Path) -> None:
    baseline.validate_runs(retained_runs(tmp_path))
    with pytest.raises(ValueError, match="not deterministic"):
        baseline.validate_runs(retained_runs(tmp_path, differing=True))


def test_aggregate_rejects_reused_repetition_and_mismatched_verdict_log(tmp_path: Path) -> None:
    runs = retained_runs(tmp_path)
    with pytest.raises(ValueError, match="three distinct"):
        baseline.validate_runs([runs[0], runs[0], runs[2]])
    verdict = Path(runs[0]["verdict"]["path"])
    verdict.write_text(json.dumps({"status": "passed", "log": "another-simulation.log"}))
    runs[0]["verdict"] = baseline.artifact(verdict)
    with pytest.raises(ValueError, match="simulation verdict"):
        baseline.validate_runs(runs)


def test_report_without_runs_is_incomplete(tmp_path: Path) -> None:
    import argparse

    variant = tmp_path / "build/ihp130-tiny-test"
    assert baseline.report(argparse.Namespace(root=tmp_path, variant_root=variant)) == 1
    assert baseline.read_json(variant / "meta/tiny-r2-p1/baseline-report.json")["status"] == "incomplete"


def test_make_dry_run_does_not_execute_baseline_driver() -> None:
    stamp = "2000-01-01-00-01"
    build = baseline.ROOT / "build"
    before = set(build.glob(f"ihp130-tiny-{stamp}-*"))
    result = subprocess.run(["make", "--dry-run", "CONFIG=configs/ci/ihp130-tiny.mk",
                             f"BUILD_TIMESTAMP={stamp}", "tiny-r2-baseline-sim"],
                            cwd=baseline.ROOT, text=True, capture_output=True, check=True)
    assert "--simulator verilator" in result.stdout
    assert "SOC=TINY" in result.stdout and "PDK=IHP130" in result.stdout
    assert "--always-make" not in result.stdout  # The explicit -B is passed to the child only.
    assert "-j1 -B CONFIG=" in result.stdout
    assert set(build.glob(f"ihp130-tiny-{stamp}-*")) == before


@pytest.fixture
def locked_icarus(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> tuple[Path, Path]:
    cache = tmp_path / "cache"
    installed = cache / "toolchains/iverilog-test"
    binaries = installed / "bin"
    binaries.mkdir(parents=True)
    archive = cache / "downloads/icarus.tar.gz"
    archive.parent.mkdir()
    archive.write_bytes(b"locked test archive")
    spec = {"version": "test", "archive": archive.name, "sha256": baseline.sha256(archive), "path": "bin"}
    baseline.dump(tmp_path / "dependencies/dependencies.lock.json",
                  {"toolchains": {"ubuntu-22.04": {"iverilog": spec}}})
    (installed / ".complete").write_text(spec["sha256"])
    for name in ("iverilog", "vvp"):
        program = binaries / name
        program.write_text("#!/bin/sh\nprintf 'Icarus fixture version\\n'\n")
        program.chmod(0o755)
    monkeypatch.setenv("RETROSOC_DEVELOPMENT_CACHE", str(cache))
    monkeypatch.setenv("PATH", str(binaries) + os.pathsep + os.defpath)
    monkeypatch.setattr(baseline, "TOOL_PROGRAMS", {"iverilog": "iverilog"})
    return tmp_path, binaries / "vvp"


@pytest.mark.parametrize("selection", ["name", "absolute", "alias"])
def test_selected_vvp_resolves_to_locked_executable(locked_icarus, selection: str) -> None:
    root, program = locked_icarus
    selected = "vvp" if selection == "name" else str(program)
    if selection == "alias":
        alias = root / "runtime-alias"
        alias.symlink_to(program)
        selected = str(alias)
    compiler = baseline.tools_identity(root)["iverilog"]
    identity = baseline.vvp_identity(selected, compiler)
    assert identity["executable"] == baseline.artifact(program)
    assert identity["archive"] == compiler["archive"]
    assert identity["version"] == "Icarus fixture version"


@pytest.mark.parametrize("failure", ["external", "missing", "bad-marker", "missing-marker"])
def test_invalid_runtime_fails_before_compilation_or_simulation(locked_icarus, monkeypatch, failure: str) -> None:
    root, program = locked_icarus
    selected = str(program)
    if failure == "external":
        external = root / "external-vvp"
        external.write_bytes(program.read_bytes())
        external.chmod(0o755)
        selected = str(external)
    elif failure == "missing":
        selected = str(root / "missing-vvp")
    elif failure == "bad-marker":
        (program.parent.parent / ".complete").write_text("wrong archive")
    else:
        (program.parent.parent / ".complete").unlink()
    image_path = root / "image.json"
    image_path.write_text("{}")
    image = {"source": {}, "artifacts": {"tiny_baseline.hex": {"sha256": "fixture"}}}
    monkeypatch.setattr(baseline, "retained_image", lambda *_: (image_path, image))
    monkeypatch.setattr(baseline, "configuration", lambda *_: {"configuration": {"PDK": "IHP130"}})
    monkeypatch.setattr(baseline, "execute", lambda *_args, **_kwargs: pytest.fail("tool execution preceded rejection"))
    args = argparse.Namespace(root=root, variant_root=root / "build/variant", simulator="iverilog",
                              hex=None, vvp=selected, command=["unexpected-build"])
    with pytest.raises((ValueError, OSError)):
        baseline.simulate(args)
    pointer = baseline.read_json(args.variant_root / "meta/tiny-r2-p1/workloads/iverilog/latest.json")
    attempt = baseline.read_json(Path(pointer["path"]))
    assert attempt["status"] == "failed" and not attempt["runs"]


@pytest.mark.parametrize("mutation", ["none", "missing", "executable", "archive", "launch", "flow"])
def test_runtime_retention_and_actual_launch_are_rechecked(locked_icarus, mutation: str) -> None:
    root, program = locked_icarus
    tools = baseline.tools_identity(root)
    runtime = baseline.vvp_identity(str(program), tools["iverilog"])
    launch = [str(program), "model", "+firmware=retained.hex"]
    flow_path = root / "run.json"
    baseline.dump(flow_path, {"command": ["timeout", "--foreground", "10s", *launch]})
    attempt = {"simulator": "iverilog", "tools": tools, "runtime_tool": runtime,
               "command": launch, "timeout_seconds": 10, "runs": [{"flow": baseline.artifact(flow_path)}]}
    if mutation == "missing":
        del attempt["runtime_tool"]
    elif mutation == "executable":
        program.write_bytes(b"changed executable")
    elif mutation == "archive":
        Path(runtime["archive"]["path"]).write_bytes(b"changed archive")
    elif mutation == "launch":
        attempt["command"][0] = "/unlocked/vvp"
    elif mutation == "flow":
        baseline.dump(flow_path, {"command": ["timeout", "--foreground", "10s", "/unlocked/vvp", "model"]})
        attempt["runs"][0]["flow"] = baseline.artifact(flow_path)
    if mutation == "none":
        baseline.validate_runtime_tool(root, attempt)
    else:
        with pytest.raises(ValueError):
            baseline.validate_runtime_tool(root, attempt)


def test_image_retains_compiler_command_after_postprocessing(tmp_path: Path, monkeypatch) -> None:
    variant = tmp_path / "build/variant"
    monkeypatch.setattr(baseline, "configuration", lambda *_: {"configuration": {"PDK": "IHP130"}})
    monkeypatch.setattr(baseline, "tools_identity", lambda *_: {})
    monkeypatch.setattr(baseline, "source_inputs", lambda *_: {})
    monkeypatch.setattr(baseline, "snapshot", lambda *_: {})
    commands = {}

    def execute(_root, directory, label, command, **_kwargs):
        commands[label] = list(command)
        baseline.dump(directory / f"{label}.json", {"command": command, **PASS})
        if label == "compile":
            Path(command[-1]).write_bytes(b"ELF fixture")
        elif label.startswith("objcopy-"):
            Path(command[-1]).write_bytes(b"image fixture")
        elif label == "symbols":
            (directory / "symbols.log").write_text("30001000 00001000 b rs_baseline_tcds\n30004000 B _ebss\n")
        return PASS

    monkeypatch.setattr(baseline, "execute", execute)
    original = ["--", "gcc-fixture", "-Os", "input.c"]
    args = argparse.Namespace(root=tmp_path, variant_root=variant, command=original,
                              objcopy="objcopy-fixture", objdump="objdump-fixture",
                              nm="nm-fixture", size="size-fixture")
    assert baseline.build_image(args) == 0
    manifest = Path(baseline.read_json(variant / "meta/tiny-r2-p1/binaries/latest.json")["path"])
    image = baseline.read_json(manifest)
    compile_result = baseline.read_json(manifest.parent / "compile.json")
    assert image["compiler_command"] == compile_result["command"] == commands["compile"]
    assert commands["size"][0] == "size-fixture"
    assert image["compiler_command"][0] == "gcc-fixture"
    assert original == ["--", "gcc-fixture", "-Os", "input.c"]
