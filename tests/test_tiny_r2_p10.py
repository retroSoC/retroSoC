"""P10 single-run acceptance, observer conservation and configuration isolation."""
from __future__ import annotations

from copy import deepcopy
from pathlib import Path
import os
import subprocess

import pytest

from scripts import tiny_r2_p10 as p10
from scripts.check_simulation import DEFAULT_FAILURE

ROOT = Path(__file__).resolve().parents[1]


def configuration(*extra):
    return subprocess.run(["make", "--no-print-directory", "CONFIG=configs/ci/ics55-tiny.mk",
                           "APP=ci_smoke", "BUILD_TIMESTAMP=2026-10-17-00-00", *extra, "config"],
                          cwd=ROOT, text=True, capture_output=True, check=False)


def test_acceptance_configuration_is_separate():
    baseline = configuration()
    selected = configuration("TINY_P10_ACCEPTANCE=YES")
    assert baseline.returncode == selected.returncode == 0
    assert baseline.stdout != selected.stdout
    base_values = dict(line.split(None, 1) for line in baseline.stdout.splitlines() if line.strip())
    new_values = dict(line.split(None, 1) for line in selected.stdout.splitlines() if line.strip())
    assert base_values["VARIANT_ROOT"] != new_values["VARIANT_ROOT"]
    for extra in ("TINY_P7_ACCEPTANCE=YES", "TINY_P8_ACCEPTANCE=YES", "TINY_P9_ACCEPTANCE=YES",
                  "APP=bringup", "SOC=MINI", "TINY_P9_QUICK=YES", "TINY_P10_ACCEPTANCE=maybe"):
        assert configuration("TINY_P10_ACCEPTANCE=YES", extra).returncode != 0


@pytest.mark.parametrize("simulator", ["iverilog", "verilator"])
def test_observer_preserves_boundary_transactions(tmp_path, simulator):
    sources = [ROOT / "rtl/tiny/dv/tiny_p10_observer.sv", ROOT / "tests/rtl/tiny_p10_observer_tb.sv"]
    model = tmp_path / "sim"
    if simulator == "iverilog":
        compile_command = ["iverilog", "-g2012", "-s", "tiny_p10_observer_tb", "-o", str(model)]
        launch = ["vvp", str(model)]
    else:
        compile_command = ["verilator", "--binary", "--timing", "--assert", "-Wno-fatal", "-j", "4",
                           "--top-module", "tiny_p10_observer_tb", "--Mdir", str(tmp_path / "obj"),
                           "-o", str(model)]
        launch = [str(model)]
    compiled = subprocess.run([*compile_command, *map(str, sources)], capture_output=True, text=True,
                              timeout=120, check=False, env={**os.environ, "CCACHE_DISABLE": "1"})
    assert compiled.returncode == 0, compiled.stdout + compiled.stderr
    good = subprocess.run(launch, capture_output=True, text=True, timeout=30, check=False)
    content = good.stdout + good.stderr
    p10.require_terminal(content, {"exit_code": good.returncode, "status": "passed"})
    result = p10.check_observations(content, 2, 28)
    first, writer, _, _, _, last = result["bus"]
    assert (first["reads"], first["read_initial"], first["read_done"], first["read_pending"]) == (0, 1, 1, 0)
    assert first["read_bytes"] == 4 and first["ar_max"] == 2 and first["read_latency_max"] == 2
    assert writer["writes"] == writer["write_done"] == 1 and writer["write_bytes"] == 4
    assert last["reads"] == last["read_pending"] == 1 and last["read_done"] == 0
    assert result["concurrency"][0]["bank_overlap"] == 3
    bad = subprocess.run([*launch, "+orphan"], capture_output=True, text=True, timeout=30, check=False)
    assert DEFAULT_FAILURE.search(bad.stdout + bad.stderr)


def camera_log():
    histogram, checksum = p10.golden()
    content = [f"P10_RESULT code=0 pixels=76800 bytes=153600 sectors=300 checksum={checksum}"]
    content += [f"P10_HIST bin={index} pixels={value}" for index, value in enumerate(histogram)]
    content += [f"P10_PHASE id={index} calls={1 if index < 2 else 150} bytes=153600 cycles=100 instructions=50"
                for index in range(5)]
    for window in range(1, 453):
        for owner in range(3):
            row = dict.fromkeys(p10.BUS_FIELDS, 0)
            row.update(window=window, owner=owner)
            if window == 1 and owner == 1:
                row["write_bytes"] = 153600
                row["writes"] = row["write_done"] = 9600
            if window >= 4 and (window - 4) % 3 == 0 and owner == 2:
                row["read_bytes"], row["write_bytes"] = 1040, 4
                row["reads"] = row["read_done"] = 17
                row["writes"] = row["write_done"] = 1
            if window > 2 and (window - 2) % 3 == 0 and owner == 2:
                row["read_bytes"], row["write_bytes"] = 16, 1028
                row["reads"] = row["read_done"] = 1
                row["writes"] = row["write_done"] = 17
            content.append("P10_BUS " + " ".join(f"{k}={v}" for k, v in sorted(row.items())))
        content.append(f"P10_CONCURRENCY window={window} active_targets_max=2 bank_overlap=1 dma_beat_overlap=0")
    content += ["P9_OBSERVATION version=1 accepted_words=38400 delivered_words=38400 "
                "fifo_high_water=4 backpressure=308 pixel_half_ns=500", "SIM_TEST_PASS Tiny cycles=100"]
    return "\n".join(content)


def test_camera_oracle_and_complete_pipeline():
    histogram, checksum = p10.golden()
    assert sum(histogram) == 76800 and checksum == 2323003269
    assert histogram[:10] == [2368] * 10 and histogram[-1] == 2371
    result = p10.camera_measurements(camera_log(), {"exit_code": 0, "status": "passed"}, 28)
    assert result["phases"][4]["calls"] == 150
    assert result["sdio_bytes"]["observed_write"] == 154800
    assert result["sdio_bytes"]["observed_read"] == 158400


@pytest.mark.parametrize("old,new", [
    ("code=0", "code=1"), ("sectors=300", "sectors=299"),
    ("bin=31 pixels=2371", "bin=31 pixels=2370"), ("calls=150", "calls=149"),
    ("read_pending=0", "read_pending=1"), ("errors=0", "errors=1"),
    ("active_targets_max=2", "active_targets_max=29"),
    ("fifo_high_water=4", "fifo_high_water=128"), ("backpressure=308", "backpressure=11904"),
    ("pixel_half_ns=500", "pixel_half_ns=250"), ("SIM_TEST_PASS", "SIM_TEST_FAIL"),
    ("write_bytes=1028", "write_bytes=1024"), ("read_bytes=1040", "read_bytes=1024"),
    ("write_bytes=1028", "write_bytes=1027"), ("read_bytes=1040", "read_bytes=1044"),
])
def test_pipeline_rejects_incomplete_or_corrupt_evidence(old, new):
    with pytest.raises(ValueError):
        p10.camera_measurements(camera_log().replace(old, new, 1), {"exit_code": 0, "status": "passed"}, 28)


@pytest.mark.parametrize("flow", [{"exit_code": 1, "status": "passed"},
                                  {"exit_code": 0, "status": "failed"}])
def test_terminal_text_never_overrides_command_failure(flow):
    with pytest.raises(ValueError):
        p10.require_terminal("SIM_TEST_PASS Tiny cycles=100\n", flow)


def test_resume_rejects_missing_or_changed_source(tmp_path):
    record = {"phase": p10.PHASE, "status": "passed", "source_inputs": {"a": "one"},
              "source_after": {"a": "one"}, "artifacts": {}, "source": {}}
    path = tmp_path / "record.json"
    p10.b.dump(path, record)
    with pytest.raises(ValueError):
        p10.checked_record(path, {"a": "two"})
    failed = deepcopy(record)
    failed["status"] = "running"
    p10.b.dump(path, failed)
    with pytest.raises(ValueError):
        p10.checked_record(path, {"a": "one"})


def test_matched_comparison_rejects_different_work():
    row = dict(name="memory", payload_bytes=16384, checksum=7, kernel_calls=0,
               cycles=200, instructions=100)
    other = {**row, "cycles": 150}
    compared = p10.compare_samples({"cases": [row]}, {"cases": [other]})
    assert compared[0]["cycle_ratio"] == 200 / 150
    other["payload_bytes"] = 65536
    with pytest.raises(ValueError):
        p10.compare_samples({"cases": [row]}, {"cases": [other]})


def test_collector_update_preserves_original_source_identity():
    source = {"scripts/tiny_r2_p10.py": "old", "rtl/tiny/top/retrosoc_tiny.sv": "rtl"}
    record = {"source_inputs": deepcopy(source), "source_after": deepcopy(source)}
    current = {**source, "scripts/tiny_r2_p10.py": "new"}
    with pytest.raises(ValueError):
        p10.source_delta(record, current)
    assert p10.source_delta(record, current, True) == {
        "scripts/tiny_r2_p10.py": {"before": "old", "after": "new"}}
    assert record["source_inputs"] == record["source_after"] == source
    for path in ("rtl/tiny/top/retrosoc_tiny.sv", "app/apps/ci_smoke/tiny_r2_p10.c",
                 "Makefile", "dependencies/dependencies.lock.json", "tests/unreviewed.py"):
        with pytest.raises(ValueError):
            p10.source_delta(record, {**current, path: "changed"}, True)
    record["source_after"] = current
    with pytest.raises(ValueError):
        p10.source_delta(record, current, True)


def test_retained_section_sizes_are_not_elf_file_size(tmp_path):
    log = tmp_path / "size.log"
    log.write_text("firmware:\nsection size addr\n.init 204 0\n.text 9936 805306368\n"
                   ".bss 23116 805316352\n.comment 15 0\nTotal 33271\n")
    image = tmp_path / "image.json"
    p10.b.dump(image, {"artifacts": {"size.log": p10.b.artifact(log)},
                      "layout": {"stack_headroom": 4096}})
    result = p10.retained_footprint(p10.b.artifact(image))
    assert result["sections"][".text"] == 9936 and result["stack_headroom"] == 4096
    log.write_text("modified")
    with pytest.raises(ValueError):
        p10.retained_footprint(p10.b.artifact(image))
