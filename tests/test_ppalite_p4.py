"""PPALITE-P4 descriptor display, independent checker, and image contracts."""
from __future__ import annotations

import json
from pathlib import Path
import subprocess
import sys
import tempfile

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from scripts.ppalite_p4 import (  # noqa: E402
    CASES,
    DMA_WINDOWS,
    MEASURE_BYTES,
    check_log,
    configuration_digest,
    fnv1a,
    model,
    wire_pixels,
)

BANNED = ("malloc", "free(", "strcpy", "strcat", "strncpy", "sprintf", "vsprintf", "atoi")


def test_descriptor_display_and_image_contract() -> None:
    board = (ROOT / "app/board/src/st7789vi.c").read_text()
    math = (ROOT / "app/board/src/st7789vi_math.c").read_text()
    header = (ROOT / "app/board/include/retrosoc/board/st7789vi.h").read_text()
    image = (ROOT / "app/apps/ci_smoke/tiny_ppalite_p4.c").read_text()
    for text in (board, math, header, image):
        assert not any(token in text for token in BANNED)
    assert "rs_st7789vi_frame_layout" in header and "rs_st7789vi_display_frame" in header
    assert "layout.frames_per_row" in board and "layout.transport_bytes_per_row" in board
    assert "(row + 1U) < (uint32_t)frame->height" in board
    assert "rs_st7789vi_display_buffer" in board
    assert "rs_ppa_run_capture" in image and "rs_ppalite_release" in image
    assert image.index("rs_ppalite_get_measurements(core)") < image.index("rs_ppalite_release(&session")
    assert image.index("rs_ppalite_release(&session") < image.index("rs_ppa_verify(config, &frame)")
    assert "rs_ppa_sd_export(7U, &gray_frame" in image
    assert "rs_ppa_sd_export(12U, &padded_frame" in image
    assert "RS_PPA_RAW_ADDR    UINT32_C(0x54060000)" in image
    assert "RS_PPA_RAW_ADDR    UINT32_C(0x54000000)" not in image
    assert "rs_ppa_display(8U, &rgb_frame" in image
    assert "rs_ppa_display(9U, &odd_frame" in image
    assert ".base = RS_PPA_" not in image
    assert "uint32_t rs_ppa_frame[" not in image
    assert image.index("rs_ppa_run_capture(4U") < image.index("!rs_ppa_sd_export")
    assert image.index("rs_ppa_run_capture(5U") < image.index("!rs_ppa_display(8U")
    assert image.index("rs_ppa_run_capture(6U") < image.index("!rs_ppa_display(9U")
    assert image.index("rs_sysctrl_write_test_status") < image.index("PPALITE_P4_RESULT")
    testbench = (ROOT / "rtl/tiny/dv/retrosoc_tiny_tb.sv").read_text()
    assert 'if ($test$plusargs("tiny_spi_p4")) s_done_limit = 65536;' in testbench
    mk = (ROOT / "app/apps/ci_smoke/tiny.mk").read_text()
    assert "tiny_ppalite_p4.c" in mk and "st7789vi.c" in mk and "app/board/include" in mk


def test_checker_rejects_joined_result_and_panel() -> None:
    log = golden_log()
    panel = next(line for line in log.splitlines() if line.startswith("SPI_P4_PANEL "))
    log = log.replace(panel + "\n", "", 1)
    result = "PPALITE_P4_RESULT code=0 frames=7 recovered=1"
    log = log.replace(result, result + panel, 1)
    problems = check_log(log)
    assert "missing panel summary" in problems
    assert any(problem.startswith("malformed P4 result:") for problem in problems)


def test_acceptance_image_is_explicit_and_isolated(tmp_path: Path) -> None:
    base = ["make", "--no-print-directory", "CONFIG=configs/ci/ics55-tiny.mk", "APP=ci_smoke",
            "TINY_PPALITE_P4_ACCEPTANCE=YES", "BUILD_TIMESTAMP=2026-11-02-23-05"]
    build = subprocess.run([*base, "-n", "firmware"], cwd=ROOT, text=True, capture_output=True,
                           check=False)
    assert build.returncode == 0, build.stdout + build.stderr
    assert "tiny_ppalite_p4.c" in build.stdout
    assert "st7789vi.c" in build.stdout and "st7789vi_math.c" in build.stdout
    assert "crt/src/hal/ppalite.c" in build.stdout
    for override in ("TINY_P7_ACCEPTANCE=YES", "TINY_P8_ACCEPTANCE=YES",
                     "TINY_P9_ACCEPTANCE=YES", "TINY_P10_ACCEPTANCE=YES",
                     "TINY_SPI_P3_ACCEPTANCE=YES", "TINY_SPI_P4_ACCEPTANCE=YES",
                     "TINY_PPALITE_P3_ACCEPTANCE=YES", "APP=bringup", "SOC=MINI"):
        result = subprocess.run([*base, override, "config"], cwd=ROOT, text=True,
                                capture_output=True, check=False)
        assert result.returncode != 0, override


def test_independent_layout_and_wire_models() -> None:
    for case_id, case in CASES.items():
        *_, width, height, row_bytes, stride, valid, transport = case
        _, rendered, shape = model(case_id)
        assert shape["output_width"] == width
        assert shape["output_height"] == height
        assert shape["row_bytes"] == row_bytes
        assert shape["stride_bytes"] == stride
        assert shape["valid_bytes"] == valid
        assert shape["transport_bytes"] == transport
        assert len(rendered) == transport
        assert len(wire_pixels(case_id)) == valid
    image = (ROOT / "app/apps/ci_smoke/tiny_ppalite_p4.c").read_text()
    assert "const uint32_t index = 2U * source_x;" in image
    assert "source_y * config->source.frame_width" not in image
    assert model(1)[1] == bytes((7, 11, 15, 0, 13, 17, 21, 0))
    assert len(wire_pixels(1)) == 6
    assert len(wire_pixels(6)) == 38160
    assert configuration_digest({"configuration": {"SOC": "TINY"}}) == configuration_digest(
        {"configuration": {"SOC": "TINY"}})


def test_observer_chronology() -> None:
    assert DMA_WINDOWS == {
        1: {"write": 8},
        3: {"write": 8},
        4: {"write": 19200},
        6: {"write": 38400},
        7: {"read": 38400, "write": 38400},
        8: {"write": 38400},
        9: {"read": 38400, "write": 38400},
        10: {"write": 76800},
        11: {"write": 19200},
        13: {"write": 153600},
    }
    image = (ROOT / "app/apps/ci_smoke/tiny_ppalite_p4.c").read_text()
    assert image.index("rs_ppa_sd_export(7U") < image.index("rs_ppa_run_capture(5U")
    assert image.index("rs_ppa_run_capture(5U") < image.index("rs_ppa_display(8U")
    assert image.index("rs_ppa_display(8U") < image.index("rs_ppa_run_capture(6U")
    assert image.index("rs_ppa_run_capture(6U") < image.index("rs_ppa_display(9U")


def _capture_lines() -> list[str]:
    lines = []
    sequences = {1: (1, 1), 3: (3, 2), 4: (4, 3), 5: (5, 4), 6: (6, 5), 10: (10, 6),
                 11: (11, 7)}
    for case_id, case in CASES.items():
        *_, width, height, row_bytes, stride, valid, transport = case
        job, source = sequences[case_id]
        lines.append(f"PPALITE_P4_CAPTURE id={case_id} pass=1 width={width} height={height} "
                     f"row={row_bytes} stride={stride} valid={valid} transport={transport} "
                     f"job={job} source={source}")
    return lines


def _panel_lines() -> list[str]:
    lines = []
    aggregate = 2166136261
    total = 0
    for index, (case_id, geometry) in enumerate(((5, (0, 0, 159, 119)), (6, (0, 0, 158, 119)))):
        pixels = wire_pixels(case_id)
        aggregate = fnv1a(pixels, aggregate)
        total += len(pixels) // 2
        lines.append(f"SPI_P4_WINDOW seq={index + 1:x} x0={geometry[0]:x} y0={geometry[1]:x} "
                     f"x1={geometry[2]:x} y1={geometry[3]:x} pixels={len(pixels) // 2:x} "
                     f"fnv1a={fnv1a(pixels):08x} aborted=0")
    lines.append(f"SPI_P4_PANEL commands=8 windows=2 pixels={total:x} fnv1a={aggregate:08x} "
                 "violations=0")
    return lines


def _bus_line(window: int, read_bytes: int = 0, write_bytes: int = 0) -> str:
    reads = read_bytes // 4
    writes = write_bytes // 4
    return (f"P10_BUS window={window} owner=1 reads={reads} read_initial=0 read_done={reads} "
            f"read_pending=0 read_bytes={read_bytes} read_latency_max={5 if reads else 0} "
            f"writes={writes} write_initial=0 write_done={writes} write_pending=0 "
            f"write_bytes={write_bytes} write_latency_max={5 if writes else 0} errors=0")


def _change_bus_fields(log: str, window: int, **changes: int) -> str:
    lines = []
    matched = False
    for line in log.splitlines():
        if line.startswith(f"P10_BUS window={window} "):
            matched = True
            fields = dict(field.split("=", 1) for field in line[len("P10_BUS "):].split())
            fields.update({name: str(value) for name, value in changes.items()})
            line = "P10_BUS " + " ".join(f"{name}={value}" for name, value in fields.items())
        lines.append(line)
    assert matched
    return "\n".join(lines) + "\n"


def golden_log() -> str:
    lines = _capture_lines()
    lines.append("PPALITE_P4_RECOVERY pass=1 wait=-4 abort=0 stopped=-4 resumed=0 owned=1 valid=0")
    for case_id, stride, row_bytes, valid, stripped in ((7, 160, 160, 19200, 0),
                                                        (12, 160, 159, 19080, 1)):
        lines.append(f"PPALITE_P4_SD id={case_id} pass=1 first_lba=16 last_lba=53 blocks=38 "
                     f"bytes={valid} row={row_bytes} stride={stride} stripped={stripped} readback=1")
    for case_id, pixels, payload, chunks, frame16 in ((8, 19200, 38400, 120, 1),
                                                      (9, 19080, 38160, 120, 0)):
        lines.append(f"PPALITE_P4_DISPLAY id={case_id} pass=1 pixels={pixels} payload={payload} "
                     f"transport=9600 chunks={chunks} frame16={frame16}")
    for case_id in (1, 2, 3, 4, 7, 5, 8, 6, 9, 10, 11, 12, 13):
        lines.append(f"PPALITE_P4_MEASURE id={case_id} bytes={MEASURE_BYTES[case_id]} "
                     f"cycles={1000 + case_id} instructions={900 + case_id}")
    for case_id, case in CASES.items():
        width, height = case[:2]
        transport = case[-1]
        lines.append(f"PPALITE_P4_CORE id={case_id} input_words={((width + 1) // 2) * height} "
                     f"input_pixels={width * height} input_lines={height} "
                     f"output_words={transport // 4} output_lines={case[11]} "
                     "input_stall=3 output_stall=5 high_water=4")
        lines.append(f"PPALITE_P4_TIMING id={case_id} arm={10 + case_id} start={20 + case_id} "
                     f"wait={100 + case_id} rows={case[11]}")
    lines.append("PPALITE_P4_RAW pass=1 pixels=76800 bytes=153600 words=38400 dma_bytes=153600")
    lines.extend(_panel_lines())
    expected_words = sum(((case[0] + 1) // 2) * case[1] for case in CASES.values()) + 38400
    lines.append(f"P9_OBSERVATION version=1 accepted_words={expected_words} "
                 f"delivered_words={expected_words} fifo_high_water=4 backpressure=0 pixel_half_ns=500")
    for window in range(1, 14):
        directions = DMA_WINDOWS.get(window, {})
        lines.append(_bus_line(window, directions.get("read", 0), directions.get("write", 0)))
    lines.append("PPALITE_P4_RESULT code=0 frames=7 recovered=1")
    lines.append("SIM_TEST_PASS Tiny cycles=123456")
    return "\n".join(lines) + "\n"


def test_checker_accepts_golden_log() -> None:
    assert check_log(golden_log()) == []


@pytest.mark.parametrize("corruption", (
    "capture", "recovery", "sd", "display", "measurement", "core", "timing", "timing_relation",
    "instructions", "negative_cycles", "negative_arm", "negative_start", "negative_wait", "raw",
    "panel", "p9", "budget", "budget_boundary", "bus", "latency", "axi_count", "pending",
    "opposite", "opposite_initial", "sd_dma5", "sd_dma12", "display_missing_read",
    "display_missing_write", "spi_beat_count", "result", "terminal", "zero_terminal",
    "valid_plus_zero_terminal", "valid_plus_malformed_terminal", "duplicate_valid_terminal", "forbidden",
))
def test_checker_rejects_corruption(corruption: str) -> None:
    log = golden_log()
    if corruption == "capture":
        log = log.replace("id=6 pass=1 width=159 height=120 row=318 stride=320",
                          "id=6 pass=1 width=159 height=120 row=318 stride=321")
    elif corruption == "recovery":
        log = log.replace("stopped=-4", "stopped=0")
    elif corruption == "sd":
        log = log.replace("blocks=38", "blocks=39")
    elif corruption == "display":
        log = log.replace("id=9 pass=1 pixels=19080 payload=38160 transport=9600 chunks=120",
                          "id=9 pass=1 pixels=19080 payload=38160 transport=9600 chunks=119")
    elif corruption == "measurement":
        log = log.replace("id=7 bytes=19200", "id=7 bytes=0")
    elif corruption == "core":
        log = log.replace("high_water=4", "high_water=9", 1)
    elif corruption == "timing":
        log = log.replace("id=1 arm=11 start=21 wait=101", "id=1 arm=11 start=21 wait=0")
    elif corruption == "timing_relation":
        log = log.replace("id=1 arm=11 start=21 wait=101", "id=1 arm=11 start=21 wait=1000")
    elif corruption == "instructions":
        log = log.replace("id=1 bytes=8 cycles=1001 instructions=901",
                          "id=1 bytes=8 cycles=1001 instructions=1002")
    elif corruption == "negative_cycles":
        log = log.replace("id=1 bytes=8 cycles=1001 instructions=901",
                          "id=1 bytes=8 cycles=1001 instructions=-1")
    elif corruption == "negative_arm":
        log = log.replace("id=1 arm=11", "id=1 arm=-1")
    elif corruption == "negative_start":
        log = log.replace("id=1 arm=11 start=21", "id=1 arm=11 start=-1")
    elif corruption == "negative_wait":
        log = log.replace("id=1 arm=11 start=21 wait=101", "id=1 arm=11 start=21 wait=-1")
    elif corruption == "raw":
        log = log.replace("PPALITE_P4_RAW pass=1", "PPALITE_P4_RAW pass=0")
    elif corruption == "panel":
        log = log.replace("SPI_P4_VIOLATION", "") + "SPI_P4_VIOLATION code=1\n"
    elif corruption == "p9":
        log = log.replace("accepted_words=230098", "accepted_words=230097")
    elif corruption == "budget":
        log = log.replace("backpressure=0", "backpressure=20000")
    elif corruption == "budget_boundary":
        log = log.replace("backpressure=0", "backpressure=11520")
    elif corruption == "bus":
        log = log.replace("read_pending=0", "read_pending=1", 1)
    elif corruption == "latency":
        log = log.replace("write_latency_max=5", "write_latency_max=0", 1)
    elif corruption == "axi_count":
        log = log.replace("writes=38400", "writes=2").replace("write_done=38400", "write_done=2")
    elif corruption == "pending":
        log = log.replace("write_done=2", "write_done=1", 1).replace("write_pending=0",
                                                                     "write_pending=1", 1)
    elif corruption == "opposite":
        log = log.replace("read_bytes=0 read_latency_max=0 writes=38400",
                          "read_bytes=4 read_latency_max=5 writes=38400")
    elif corruption == "opposite_initial":
        log = log.replace("read_initial=0", "read_initial=1", 1).replace("read_pending=0",
                                                                         "read_pending=1", 1)
    elif corruption in ("sd_dma5", "sd_dma12"):
        window = 5 if corruption == "sd_dma5" else 12
        log = _change_bus_fields(log, window, reads=1, read_done=1, read_bytes=4, read_latency_max=5)
    elif corruption == "display_missing_read":
        log = _change_bus_fields(log, 7, reads=0, read_done=0, read_bytes=0, read_latency_max=0)
    elif corruption == "display_missing_write":
        log = _change_bus_fields(log, 9, writes=0, write_done=0, write_bytes=0, write_latency_max=0)
    elif corruption == "spi_beat_count":
        log = _change_bus_fields(log, 7, reads=2, read_done=2)
    elif corruption == "result":
        log = log.replace("PPALITE_P4_RESULT code=0", "PPALITE_P4_RESULT code=1")
    elif corruption == "terminal":
        log = log.replace("SIM_TEST_PASS Tiny cycles=123456", "SIM_TEST_PASS Tiny cycles=0")
        log = log.replace("SIM_TEST_PASS Tiny cycles=0\n", "")
    elif corruption == "zero_terminal":
        log = log.replace("SIM_TEST_PASS Tiny cycles=123456", "SIM_TEST_PASS Tiny cycles=0")
    elif corruption == "valid_plus_zero_terminal":
        log += "SIM_TEST_PASS Tiny cycles=0\n"
    elif corruption == "valid_plus_malformed_terminal":
        log += "SIM_TEST_PASS Tiny cycles=malformed\n"
    elif corruption == "duplicate_valid_terminal":
        log += "SIM_TEST_PASS Tiny cycles=123456\n"
    else:
        log += "SIM_TEST_TIMEOUT Tiny cycles=123456\n"
    assert check_log(log), corruption


@pytest.mark.parametrize("window", (2, 5, 6, 12))
def test_checker_rejects_missing_central_dma_window(window: int) -> None:
    log = "\n".join(line for line in golden_log().splitlines()
                    if not line.startswith(f"P10_BUS window={window} ")) + "\n"
    assert "central DMA window sequence is incomplete, duplicated, or reordered" in check_log(log)


def test_checker_rejects_missing_records_and_bad_wire_checksum() -> None:
    log = golden_log()
    marker = "fnv1a="
    index = log.index(marker) + len(marker)
    log = log[:index] + ("0" if log[index] != "0" else "1") + log[index + 1:]
    assert check_log(log)
    for prefix in ("PPALITE_P4_RECOVERY", "PPALITE_P4_SD", "P10_BUS", "PPALITE_P4_RESULT"):
        reduced = "\n".join(line for line in golden_log().splitlines() if not line.startswith(prefix))
        assert check_log(reduced + "\n"), prefix


def test_checker_cli_help() -> None:
    result = subprocess.run([sys.executable, str(ROOT / "scripts/ppalite_p4.py"), "--help"],
                            cwd=ROOT, capture_output=True, text=True, check=False)
    assert result.returncode == 0


def test_checker_cli_writes_source_bound_record() -> None:
    with tempfile.TemporaryDirectory(dir=ROOT / "build") as directory:
        variant = Path(directory)
        (variant / "meta").mkdir()
        (variant / "sw").mkdir()
        (variant / "sim/verilator").mkdir(parents=True)
        (variant / "meta/manifest.json").write_text(json.dumps({
            "configuration": {"SOC": "TINY", "PDK": "ICS55", "TINY_PPALITE_P4_ACCEPTANCE": "YES"}
        }))
        (variant / "sw/retrosoc_fw.hex").write_text("firmware\n")
        (variant / "sim/verilator/emu").write_text("simulator\n")
        log = variant / "sim/verilator/sim.log"
        log.write_text(golden_log())
        (variant / "sim/verilator/result-sim-check.json").write_text('{"status":"passed"}\n')
        result = subprocess.run([
            sys.executable, str(ROOT / "scripts/ppalite_p4.py"), "check",
            "--variant-root", str(variant), "--pdk", "ICS55", "--simulator", "verilator",
            "--log", str(log),
        ], cwd=ROOT, capture_output=True, text=True, check=False)
        assert result.returncode == 0, result.stdout + result.stderr
        record = json.loads((variant / "meta/ppalite-p4/check/record.json").read_text())
        assert record["status"] == "passed" and record["problems"] == []
        assert record["phase_accepted"] is False
        assert record["configuration_digest"] == configuration_digest(
            json.loads((variant / "meta/manifest.json").read_text()))
        assert len(record["firmware_sha256"]) == 64
        assert len(record["simulator_sha256"]) == 64
        assert len(record["log_sha256"]) == 64
