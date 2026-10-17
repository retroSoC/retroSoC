"""Fail-closed P9 evidence parser tests."""

import pytest
import hashlib
import json
import os
from argparse import Namespace
from copy import deepcopy
from pathlib import Path
from subprocess import CompletedProcess

from scripts.tiny_r2_p9 import capture_build, measurements, prepare_build, validate_run
from scripts import tiny_r2_p9 as p9, tiny_r2_baseline as baseline


CONFIG = {"SOC": "TINY", "PDK": "IHP130"}


@pytest.fixture
def valid_log() -> str:
    return ("P9_FRAME format=0 width=320 height=240 bytes=153600 dma_bytes=153600 "
            "dma_channel=2 request=11 guards=1 readback=1\n"
            "P9_PIO width=7 height=3 valid_bytes=42 storage_bytes=48 readback=1 guards=1\n"
            "P9_OBSERVATION version=1 accepted_words=38412 delivered_words=38412 "
            "fifo_high_water=64 backpressure=12 pixel_half_ns=500\n"
            "P9_RESULT code=0 frames=1 bytes=153600\n"
            "SIM_TEST_PASS Tiny cycles=100000\n")


def test_p9_measurement_record(valid_log: str) -> None:
    assert measurements(valid_log, CONFIG)["frames"][0]["dma_channel"] == 2


@pytest.mark.parametrize("replacement", [
    ("SIM_TEST_PASS Tiny", "Hello retroSoC!"),
    ("code=0", "code=2"),
    ("dma_bytes=153600", "dma_bytes=153596"),
    ("dma_channel=2", "dma_channel=3"),
    ("guards=1", "guards=0"),
    ("frames=1", "frames=999"),
    ("width=320", "width=1"),
    ("SIM_TEST_PASS Tiny cycles=100000", "prefixSIM_TEST_PASS Tiny diagnostic"),
    ("readback=1", "readback=0"),
    ("fifo_high_water=64", "fifo_high_water=0"),
    ("delivered_words=38412", "delivered_words=38411"),
    ("format=0", "format=0 format=1"),
])
def test_p9_rejects_incomplete_evidence(valid_log: str, replacement: tuple[str, str]) -> None:
    with pytest.raises(ValueError):
        measurements(valid_log.replace(*replacement), CONFIG)


def test_p9_rejects_forbidden_markers(valid_log: str) -> None:
    with pytest.raises(ValueError):
        measurements(valid_log + "\nSIM_TEST_FAIL", CONFIG)


@pytest.mark.parametrize("defect", ["none", "exit", "hash", "source", "config", "elf", "hex",
                                   "simulator", "build_source", "missing_build", "launch"])
def test_run_provenance(valid_log: str, defect: str, tmp_path) -> None:
    config = {**CONFIG, "APP": "ci_smoke", "TINY_P9_ACCEPTANCE": "YES"}
    source = {"fixture": "a" * 64}
    outputs = {name: tmp_path / name for name in ("elf", "hex", "simulator")}
    prepared = prepare_build(config, source, outputs)
    for name, path in outputs.items():
        path.write_bytes(name.encode())
    build = capture_build(config, source, source, [{"status": "passed", "exit_code": 0}],
                          outputs, prepared=prepared)
    flow = {"status": "passed", "exit_code": 0,
            "command": [str(outputs["simulator"]), f"+firmware={outputs['hex']}"],
            "log_sha256": hashlib.sha256(valid_log.encode()).hexdigest(),
            "source_inputs": source, "configuration": config,
            "artifacts": deepcopy(build["artifacts"])}
    current = source.copy()
    if defect == "exit":
        flow["exit_code"] = 1
    elif defect == "hash":
        flow["log_sha256"] = "b" * 64
    elif defect == "source":
        current["fixture"] = "c" * 64
    elif defect == "config":
        flow["configuration"] = {"SOC": "MINI"}
    elif defect in outputs:
        outputs[defect].write_bytes(b"stale build artifact")
    elif defect == "build_source":
        build["source_before"] = {"fixture": "b" * 64}
    elif defect == "missing_build":
        build = None
    elif defect == "launch":
        flow["command"] = ["old-emu", f"+firmware={outputs['hex']}"]
    if defect == "none":
        assert validate_run(valid_log, config, flow, source, current, build=build)
    else:
        with pytest.raises(ValueError):
            validate_run(valid_log, config, flow, source, current, build=build)


def test_reject_changed_sources_during_build() -> None:
    with pytest.raises(ValueError):
        capture_build(CONFIG, {"a": "a" * 64}, {"a": "b" * 64},
                      [{"status": "passed", "exit_code": 0}], {}, prepared={})


def test_reject_existing_build_outputs(tmp_path) -> None:
    outputs = {name: tmp_path / name for name in ("elf", "hex", "simulator")}
    outputs["elf"].write_bytes(b"old ELF")
    with pytest.raises(ValueError):
        prepare_build(CONFIG, {"a": "a" * 64}, outputs)


@pytest.fixture
def vga_log(valid_log: str) -> str:
    return (valid_log.replace("format=0 width=320 height=240", "format=1 width=640 height=480")
            .replace("153600", "614400").replace("38412", "153612") +
            "P9_COUNTS words=153600 pixels=307200 xpi_error=0\n")


@pytest.mark.parametrize("defect", ["none", "qvga", "format", "words", "pixels", "xpi",
                                   "missing_counts", "duplicate_counts", "quick", "small",
                                   "camera", "period", "diagnostic", "stopped", "duplicate_vga"])
def test_vga_workload_binding(vga_log, valid_log, defect, tmp_path):
    config = {**CONFIG, "APP": "ci_smoke", "TINY_P9_ACCEPTANCE": "YES",
              "TINY_P9_WORKLOAD": "VGA_YUV422"}
    content = vga_log
    launch = ["+tiny_psram", "+tiny_p9_camera", "+tiny_p9_vga", "+tiny_p9_half_ns=500"]
    if defect == "qvga":
        content = valid_log
    elif defect == "format":
        content = content.replace("format=1", "format=0")
    elif defect == "words":
        content = content.replace("words=153600", "words=22528")
    elif defect == "pixels":
        content = content.replace("pixels=307200", "pixels=76800")
    elif defect == "xpi":
        content = content.replace("xpi_error=0", "xpi_error=1")
    elif defect == "missing_counts":
        content = content[:content.index("P9_COUNTS")]
    elif defect == "duplicate_counts":
        content += "P9_COUNTS words=153600 pixels=307200 xpi_error=0\n"
    elif defect == "quick":
        config["TINY_P9_QUICK"] = "YES"
    elif defect == "small":
        launch.append("+tiny_p9_small")
    elif defect == "camera":
        launch.remove("+tiny_p9_vga")
    elif defect == "period":
        launch[-1] = "+tiny_p9_half_ns=250"
    elif defect == "diagnostic":
        launch.append("+tiny_p9_diag_long")
    elif defect == "stopped":
        launch.append("+tiny_p9_no_pixclk")
    elif defect == "duplicate_vga":
        launch.append("+tiny_p9_vga")
    source = {"fixture": "a" * 64}
    outputs = {name: tmp_path / name for name in ("elf", "hex", "simulator")}
    prepared = prepare_build(config, source, outputs)
    for name, path in outputs.items():
        path.write_bytes(name.encode())
    build = capture_build(config, source, source, [{"status": "passed", "exit_code": 0}],
                          outputs, prepared=prepared)
    flow = {"status": "passed", "exit_code": 0, "configuration": config,
            "source_inputs": source, "artifacts": build["artifacts"],
            "log_sha256": hashlib.sha256(content.encode()).hexdigest(),
            "command": [str(outputs["simulator"]), f"+firmware={outputs['hex']}", *launch]}
    if defect == "none":
        assert validate_run(content, config, flow, source, source, build=build)["counts"][0]["words"] == 153600
    else:
        with pytest.raises(ValueError):
            validate_run(content, config, flow, source, source, build=build)


@pytest.fixture(params=["ICS55", "IHP130"])
def campaign_fixture(request, tmp_path, monkeypatch, vga_log):
    """Exercise real orchestration/filesystem guards with fake external tools."""
    root = tmp_path / "repository"
    variant = root / "build" / "test-variant"
    evidence = variant / "meta/tiny-r2-p9/full-frame"
    for name in ("dependencies/dependencies.lock.json", "docs/ip/tiny-soc.md",
                 "docs/ip/tiny-soc-r2-dvp.md", "tests/test_tiny_r2_p9.py",
                 "tests/test_tiny_r2_p9_evidence.py", "tests/c/test_runtime.c", "tool"):
        path = root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("test input\n")
    args = Namespace(pdk=request.param, workload="VGA_YUV422", timestamp="2026-10-16-00-00",
                     jobs=4, pixel_half_ns=500, max_cycles=160000000, wall_timeout=43200)
    config = {"SOC": "TINY", "PDK": args.pdk, "APP": "ci_smoke",
              "TINY_P9_ACCEPTANCE": "YES", "TINY_P9_WORKLOAD": args.workload}
    calls = []
    monkeypatch.setattr(p9, "ROOT", root)
    monkeypatch.setattr(p9.shutil, "which", lambda _: str(root / "tool"))
    monkeypatch.setattr(baseline, "configuration", lambda _: {"configuration": config})
    monkeypatch.setattr(baseline, "source_inputs", lambda *_: {"tool": baseline.sha256(root / "tool")})
    monkeypatch.setattr(baseline, "runtime_inputs", lambda *_: {})
    monkeypatch.setattr(baseline, "snapshot", lambda *_: {})

    def execute(_root, _directory, label, command, **_kwargs):
        calls.append(label)
        if label == "generate":
            assert command[-2:] == ["generate_filelist", "manifest"]
            (variant / "meta/manifest.json").write_text(json.dumps({"configuration": config}))
        elif label == "build":
            for name in ("sw/firmware", "sw/retrosoc_fw.hex", "sim/verilator/emu"):
                path = variant / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text("fresh test artifact\n")
        else:
            pytest.fail(f"unexpected flow {label}")
        return {"status": "passed", "exit_code": 0, "command": command}

    def subprocess_run(command, **_kwargs):
        if command[0] == "make" and command[-1] == "config":
            calls.append("config")
            return CompletedProcess(command, 0, stdout=f"VARIANT_ROOT {variant}\n")
        if Path(command[1]).name == "run_flow.py":
            calls.append("simulate")
            launch = command[command.index("--") + 1:]
            baseline.dump(evidence / "result-sim.json", {
                "status": "passed", "exit_code": 0, "command": launch, "cwd": str(root)})
            (evidence / "console.log").write_text(vga_log)
        elif Path(command[1]).name == "check_simulation.py":
            calls.append("check")
        else:
            pytest.fail(f"unexpected subprocess {command}")
        return CompletedProcess(command, 0)

    monkeypatch.setattr(baseline, "execute", execute)
    monkeypatch.setattr(p9.subprocess, "run", subprocess_run)
    return args, variant, evidence, calls


@pytest.mark.parametrize("existing", ["sw/firmware", "sw/retrosoc_fw.hex", "sim/verilator/emu",
                                      "meta/tiny-r2-p9/full-frame/assessment.json", "dangling-elf"])
def test_campaign_rejection_preserves_old_variant(campaign_fixture, existing):
    args, variant, evidence, calls = campaign_fixture
    for name in ("meta/manifest.json", "sim/verilator/filelists/top.fl"):
        path = variant / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(b"previous evidence\n")
        os.utime(path, ns=(1600000000000000000, 1600000000000000000))
    path = variant / ("sw/firmware" if existing == "dangling-elf" else existing)
    path.parent.mkdir(parents=True, exist_ok=True)
    if existing == "dangling-elf":
        path.symlink_to("missing-old-artifact")
    else:
        path.write_bytes(b"previous artifact\n")
        os.utime(path, ns=(1600000000000000000, 1600000000000000000))

    def snapshot():
        result = {}
        for item in (variant, *variant.rglob("*")):
            stat = item.lstat()
            data = os.readlink(item) if item.is_symlink() else item.read_bytes() if item.is_file() else None
            result[str(item.relative_to(variant))] = (stat.st_mode, stat.st_mtime_ns, data)
        return result

    before = snapshot()
    assert p9.run_campaign(args) == 1
    assert calls == ["config"]  # No generation, build, simulation or tool probing.
    assert snapshot() == before
    if not existing.startswith("meta/"):
        assert not evidence.exists()


def test_campaign_fresh_variant_runs_once(campaign_fixture):
    args, variant, evidence, calls = campaign_fixture
    assert not variant.exists()
    assert p9.run_campaign(args) == 0
    assert calls == ["config", "generate", "build", "simulate", "check"]
    report = json.loads((evidence / "assessment.json").read_text())
    assert report["status"] == "workload_passed" and report["phase_accepted"] is False
    assert report["pdk"] == args.pdk
    assert report["measurements"]["counts"][0]["words"] == 153600


@pytest.mark.parametrize("defect", ["none", "missing_case", "failed_case", "duplicate_case",
                                   "irq", "frame", "reset", "missing_diag", "board", "marker"])
def test_recovery_matrix_verdict(defect):
    content = "".join(f"P9_RECOVERY_CASE id={i} pass=1\n" for i in range(1, 8))
    content += "P9_RECOVERY_RESULT code=0 cases=7 frames=6 irqs=6\n"
    content += "P9_RECOVERY_DIAG high=0 reset_status=4294967292 fault=2 dvp_error=0 words=0\n"
    content += "P9_RECOVERY_DIAG high=1 reset_status=4294967292 fault=2 dvp_error=0 words=0\n"
    content += "P9_RECOVERY_BOARD controls=8 audio_cases=2\nSIM_TEST_PASS Tiny cycles=100\n"
    replacements = {
        "missing_case": ("P9_RECOVERY_CASE id=3 pass=1\n", ""),
        "failed_case": ("id=3 pass=1", "id=3 pass=0"),
        "duplicate_case": ("id=3 pass=1", "id=2 pass=1"),
        "irq": ("irqs=6", "irqs=5"), "frame": ("frames=6", "frames=5"),
        "reset": ("reset_status=4294967292", "reset_status=0"),
        "missing_diag": ("P9_RECOVERY_DIAG high=1", "OTHER high=1"),
        "board": ("controls=8", "controls=0"),
        "marker": ("SIM_TEST_PASS Tiny cycles=100", "Hello retroSoC!"),
    }
    config = {**CONFIG, "TINY_P9_WORKLOAD": "RECOVERY"}
    if defect == "none":
        assert measurements(content, config)["terminal"] == ("0", "7", "6", "6")
    else:
        with pytest.raises(ValueError):
            measurements(content.replace(*replacements[defect]), config)
