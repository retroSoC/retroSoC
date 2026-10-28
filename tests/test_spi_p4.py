"""SPI-P4 display adapter, acceptance image, and panel-checker contracts."""
from __future__ import annotations

from pathlib import Path
import subprocess
import sys

import pytest
from test_tiny_r2_p7 import run_rtl

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from scripts.spi_p4 import (  # noqa: E402
    camera_pixel, camera_stream, check_log, fnv1a, fnv1a_continue, golden_pixel, window_stream,
)

BANNED = ("malloc", "free(", "strcpy", "strcat", "strncpy", "sprintf", "vsprintf", "atoi")


def test_adapter_and_math_are_bounded() -> None:
    adapter = (ROOT / "app/board/src/st7789vi.c").read_text()
    math = (ROOT / "app/board/src/st7789vi_math.c").read_text()
    header = (ROOT / "app/board/include/retrosoc/board/st7789vi.h").read_text()
    for text in (adapter, math, header):
        assert not any(token in text for token in BANNED)
    assert "rs_status_t" in adapter and "rs_spi_transfer_cpu" in adapter
    assert "rs_st7789vi_begin_pixels" in header and "rs_st7789vi_fill_window" in header
    assert "RS_ST7789VI_WIDTH" in header and "UINT16_C(320)" in header
    assert math.count("case RS_ST7789VI_STAGE_") == 8


def test_image_composition_and_guard() -> None:
    mk = (ROOT / "app/apps/ci_smoke/tiny.mk").read_text()
    assert "tiny_spi_p4.c" in mk and "st7789vi.c" in mk and "app/board/include" in mk
    top = (ROOT / "Makefile").read_text()
    assert "TINY_SPI_P4_ACCEPTANCE" in top
    assert "$(TINY_SPI_P4_ACCEPTANCE),YES" in top
    image = (ROOT / "app/apps/ci_smoke/tiny_spi_p4.c").read_text()
    assert "rs_sysctrl_write_test_status" in image
    assert image.index("rs_sysctrl_write_test_status") < image.index("SPI_P4_RESULT")
    assert "rs_spi_release" in image and "rs_spi_abort" in image and "rs_spi_recover" in image
    assert "rs_dvp_capture_dma" in image and "rs_xpi_psram_initialize" in image
    assert "rs_sd_memory_write_blocks" in image and "rs_spi_abort_dma" in image
    assert "rs_p4_dma_workspace[RS_P4_DMA_WORDS]" in image
    assert "uint32_t rs_p4_frame[" not in image
    assert image.index("rs_p4_capture(&") < image.index("rs_p4_verify(&")
    assert image.index("rs_p4_verify(&") < image.index("rs_p4_run_display(NULL")
    assert image.index("rs_p4_run_display(NULL") < image.index("rs_p4_run_display(rs_p4_dma_workspace")
    assert image.index("rs_p4_run_display(rs_p4_dma_workspace") < image.index("rs_p4_save(&")
    assert image.index("rs_p4_save(&") < image.index("rs_p4_dma_abort_case(&")
    assert not any(token in image for token in BANNED)
    testbench = (ROOT / "rtl/tiny/dv/retrosoc_tiny_tb.sv").read_text()
    assert "s_done_limit" in testbench and "65536" in testbench


def _render_log(corrupt: str | None = None, quick: bool = False) -> str:
    full = (0, 0, 39, 23) if quick else (0, 0, 319, 239)
    lines = []
    commands = [("01", 0), ("11", 0), ("3a", 1), ("36", 1), ("21", 0), ("13", 0), ("29", 0)]
    for code, params in commands:
        lines.append(f"SPI_P4_CMD code={code} params={params} madctl=00")
    total_fnv = 2166136261
    total_pixels = 0

    def add_window(seq: int, stage: int, geometry: tuple[int, int, int, int],
                   pixels: int | None, aborted: int) -> None:
        nonlocal total_fnv, total_pixels
        lines.append("SPI_P4_CMD code=2a params=4 madctl=00")
        lines.append("SPI_P4_CMD code=2b params=4 madctl=00")
        lines.append("SPI_P4_CMD code=2c params=0 madctl=00")
        stream = window_stream(stage, *geometry)
        if pixels is None:
            pixels = len(stream) // 2
        stream = stream[: pixels * 2]
        digest = fnv1a(stream)
        for byte in stream:
            total_fnv = ((total_fnv ^ byte) * 16777619) & 0xFFFFFFFF
        total_pixels += pixels
        lines.append(
            f"SPI_P4_WINDOW seq={seq:x} x0={geometry[0]:x} y0={geometry[1]:x} "
            f"x1={geometry[2]:x} y1={geometry[3]:x} pixels={pixels:x} fnv1a={digest:08x} "
            f"aborted={aborted:x}"
        )

    add_window(1, 1, full, None, 0)
    add_window(2, 2, full, None, 0)
    add_window(3, 3, (13, 17, 45, 29), None, 0)
    add_window(4, 4, (319, 0, 319, 239), None, 0)
    add_window(5, 5, (200, 239, 260, 239), None, 0)
    lines.append("SPI_P4_CMD code=36 params=1 madctl=60")
    add_window(6, 6, (5, 7, 45, 29), None, 0)
    lines.append("SPI_P4_CMD code=36 params=1 madctl=00")
    add_window(7, 4, full, 544, 1)
    add_window(8, 7, (100, 100, 116, 108), None, 0)
    lines.append(
        f"SPI_P4_PANEL commands={len(lines) + 1:x} windows=8 pixels={total_pixels:x} "
        f"fnv1a={total_fnv:08x} violations=0"
    )
    log = "\n".join(lines)
    if corrupt == "checksum":
        marker = log.index("fnv1a=") + len("fnv1a=")
        digit = log[marker]
        log = log[:marker] + ("0" if digit != "0" else "1") + log[marker + 1:]
    elif corrupt == "geometry":
        log = log.replace("x1=13f", "x1=140", 1)
    elif corrupt == "violation":
        log += "\nSPI_P4_VIOLATION code=2"
    elif corrupt == "missing_window":
        log = "\n".join(lines[:-2])
    return log


def test_panel_checker_accepts_golden_log() -> None:
    assert check_log(_render_log()) == []
    assert check_log(_render_log(quick=True), quick=True) == []
    assert check_log(_render_log(quick=True), quick=True, version="a") == []


def test_panel_checker_rejects_corruption() -> None:
    for corrupt in ("checksum", "geometry", "violation", "missing_window"):
        assert check_log(_render_log(corrupt)), corrupt
    raw = subprocess.run(
        [sys.executable, str(ROOT / "scripts/spi_p4.py"), "--help"],
        capture_output=True, text=True, check=False,
    )
    assert raw.returncode == 0


def test_checker_golden_vectors_are_stable() -> None:
    assert golden_pixel(1, 0, 0) == 0xFFFF
    assert golden_pixel(2, 239, 319) == 0xFF7F
    assert golden_pixel(6, 1, 1) == 0x0820
    assert fnv1a(window_stream(7, 100, 100, 116, 108)) == fnv1a(b"\xff\xff" * 153)
    assert len(window_stream(1, 0, 0, 319, 239)) == 153600


def _p10_bus_line(window: int, owner: int) -> str:
    fields = {name: 0 for name in (
        "reads", "writes", "read_done", "write_done", "read_initial", "write_initial",
        "read_pending", "write_pending", "read_bytes", "write_bytes", "errors",
        "read_latency_max", "write_latency_max", "ar_max", "r_max", "aw_max", "w_max", "b_max",
    )}
    if owner == 1:
        fields.update(reads=38400, writes=38400, read_done=38400, write_done=38400,
                      read_bytes=153600, write_bytes=153600, read_latency_max=20,
                      write_latency_max=2)
    return "P10_BUS " + " ".join(
        [f"window={window}", f"owner={owner}"] + [f"{k}={v}" for k, v in fields.items()])


def _replace_field(log: str, marker: str, field: str, value: str) -> str:
    start = log.index(marker)
    start = log.index(field + "=", start) + len(field) + 1
    end = start
    while end < len(log) and log[end] not in " \n":
        end += 1
    return log[:start] + value + log[end:]


def _render_b_log(corrupt: str | None = None) -> str:
    lines = _render_log().splitlines()
    panel = dict(field.split("=", 1) for field in lines.pop()[len("SPI_P4_PANEL "):].split())
    total_fnv = int(panel["fnv1a"], 16)
    total_pixels = int(panel["pixels"], 16)
    commands = int(panel["commands"], 16)
    golden_fnv = fnv1a(camera_stream())
    lines.append(f"SPI_P4_CAPTURE pixels=76800 bytes=153600 words=38400 dma_bytes=153600 "
                 f"fnv1a=0x{golden_fnv:08x} guards=1 camera_active=0 dma2_busy=0")

    def add_camera(seq: int, pixels: int, aborted: int) -> None:
        nonlocal total_fnv, total_pixels, commands
        for code in ("2a", "2b", "2c"):
            lines.append(f"SPI_P4_CMD code={code} params=0 madctl=00")
            commands += 1
        stream = camera_stream()[:pixels * 2]
        total_fnv = fnv1a_continue(total_fnv, stream)
        total_pixels += pixels
        lines.append(f"SPI_P4_WINDOW seq={seq:x} x0=0 y0=0 x1=13f y1=ef pixels={pixels:x} "
                     f"fnv1a={fnv1a(stream):08x} aborted={aborted:x}")

    def add_measurement(source: str, window: int, cycles: int, instructions: int,
                        chunks: int) -> None:
        utilization = 153600 * 16 * 1000000 // cycles
        lines.append(f"SPI_P4_V22 source={source} bus_window={window} pclk_hz=24000000 divider=1 "
                     f"sck_hz=12000000 pixels=76800 payload_bytes=153600 transport_words=38400 "
                     f"chunks={chunks} frame_cycles={cycles} cpu_cycles={cycles} "
                     f"instructions={instructions} frame_time_ns={cycles * 1000000000 // 24000000} "
                     f"utilization_ppm={utilization}")
        lines.append(f"SPI_P4_V22_STALL source={source} tx_stall=1000 rx_stall=0 "
                     f"longest_tx_wait=40 longest_rx_wait=0 dma_stall=2000 fifo_min=0 "
                     f"fifo_max=8 fifo_final=0")
        for owner in range(3):
            lines.append(_p10_bus_line(window, owner))
        lines.append(f"P10_CONCURRENCY window={window} active_targets_max=2 bank_overlap=0 "
                     f"dma_beat_overlap=0")

    add_camera(9, 76800, 0)
    add_measurement("psram", 1, 4000000, 1000000, 1)
    add_camera(10, 76800, 0)
    add_measurement("sram", 2, 3000000, 900000, 150)
    lines.append(f"SPI_P4_SD first_lba=16 last_lba=315 blocks=300 chunks=150 bytes=153600 "
                 f"readback=1 fnv1a=0x{golden_fnv:08x}")
    add_camera(11, 143, 1)
    lines.append("SPI_P4_RESULT id=53504930 version=00010000 capability=00003f7f code=0")
    lines.append(f"SPI_P4_PANEL commands={commands:x} windows=b pixels={total_pixels:x} "
                 f"fnv1a={total_fnv:08x} violations=0")
    lines.append("P9_OBSERVATION version=1 accepted_words=38400 delivered_words=38400 "
                 "fifo_high_water=4 backpressure=308 pixel_half_ns=500")
    log = "\n".join(lines)
    if corrupt == "camera_checksum":
        log = _replace_field(log, "SPI_P4_WINDOW seq=9 ", "fnv1a", "00000000")
    elif corrupt == "capture_checksum":
        log = _replace_field(log, "SPI_P4_CAPTURE ", "fnv1a", "0x00000000")
    elif corrupt == "sd_checksum":
        log = _replace_field(log, "SPI_P4_SD ", "fnv1a", "0x00000000")
    elif corrupt == "measurement":
        log = _replace_field(log, "SPI_P4_V22 source=psram ", "utilization_ppm", "0")
    elif corrupt == "missing_sd":
        log = "\n".join(line for line in lines if not line.startswith("SPI_P4_SD "))
    elif corrupt == "bus":
        log = _replace_field(log, "P10_BUS window=1 owner=1 ", "read_bytes", "0")
    elif corrupt == "abort":
        log = _replace_field(log, "SPI_P4_WINDOW seq=b ", "pixels", "0")
    elif corrupt == "unexpected_abort":
        log = _replace_field(log, "SPI_P4_WINDOW seq=a ", "aborted", "1")
    elif corrupt == "source":
        log = log.replace("source=psram", "source=sram", 1)
    elif corrupt == "result":
        log = _replace_field(log, "SPI_P4_RESULT ", "code", "1")
    return log


def test_b_checker_accepts_golden_log() -> None:
    assert check_log(_render_b_log()) == []
    assert check_log(_render_b_log(), version="b") == []
    assert check_log(_render_b_log(), version="a")
    assert check_log(_render_b_log().replace("fifo_max=8", "fifo_max=0")) == []


def test_b_checker_rejects_corruption() -> None:
    for corrupt in ("camera_checksum", "capture_checksum", "sd_checksum", "measurement",
                    "missing_sd", "bus", "abort", "unexpected_abort", "source", "result"):
        assert check_log(_render_b_log(corrupt)), corrupt


def test_checker_enforces_exact_abort_prefix_lengths() -> None:
    for seq, marker, expected in ((7, "SPI_P4_WINDOW seq=7 ", 544),
                                  (11, "SPI_P4_WINDOW seq=b ", 143)):
        for pixels in (0, 1, 400, 1024):
            log = _replace_field(_render_b_log(), marker, "pixels", f"{pixels:x}")
            assert f"window {seq}: abort pixels {pixels} != {expected}" in check_log(log)
        log = _replace_field(_render_b_log(), marker, "aborted", "0")
        assert f"window {seq}: expected abort" in check_log(log)


_PROGRESS_RECORD = (
    "P9_TB_PROGRESS cycle=53650000 cpu_boot=1 core_rst=1 boot_release=1 fabric=1 "
    "dma_ready=1 apb_ready=1 i_trans=1 i_ready=1 d_trans=0 d_ready=1 slow_req=0 "
    "slow_state=3 slow_htrans=00 slow_hready=1 xpi_ar=0/1 xpi_r=0/1\n"
)


def _with_progress(log: str) -> str:
    markers = (
        "SPI_P4_CMD code=11", "SPI_P4_CAPTURE ", "SPI_P4_WINDOW seq=9 ",
        "P10_BUS window=1 owner=1 ", "SPI_P4_V22 source=psram ",
        "SPI_P4_V22_STALL source=psram ", "SPI_P4_V22 source=sram ",
        "SPI_P4_V22_STALL source=sram ", "SPI_P4_SD ", "SPI_P4_RESULT ",
        "SPI_P4_PANEL ", "P9_OBSERVATION ",
    )
    for marker in markers:
        if marker in log:
            split = log.index(marker) + 5
            log = log[:split] + _PROGRESS_RECORD + log[split:]
    return log


def test_progress_interruptions_are_reassembled_without_relaxing_checks() -> None:
    assert check_log(_with_progress(_render_b_log())) == []
    for corrupt in ("camera_checksum", "capture_checksum", "sd_checksum", "measurement",
                    "missing_sd", "bus", "abort", "unexpected_abort", "source", "result"):
        assert check_log(_with_progress(_render_b_log(corrupt))), corrupt


def test_progress_reassembly_rejects_malformed_observer_and_truncated_records() -> None:
    malformed = _with_progress(_render_b_log()).replace("cycle=53650000", "cycle=broken", 1)
    assert check_log(malformed) == ["malformed P9_TB_PROGRESS record"]
    truncated = _with_progress(
        _render_b_log().replace("SPI_P4_SD first_lba=16", "SPI_P4_SD first_lba", 1))
    assert "malformed SPI_P4_SD record" in check_log(truncated)


@pytest.mark.parametrize("simulator", ["verilator", "iverilog"])
def test_panel_oracle_distinguishes_partial_abort(tmp_path: Path, simulator: str) -> None:
    log = run_rtl(tmp_path, simulator, "tiny_st7789_panel_tb",
                  [ROOT / "rtl/tiny/dv/tiny_st7789_panel.sv"], plusargs=["+tiny_spi_p4"])
    assert "SIM_TEST_PASS ST7789_ORACLE partial_abort=2 residual_rejected=2 odd_pixel_rejected=1" in log


def test_camera_normalization_is_explicit() -> None:
    assert camera_pixel(0, 0) == 0x0001
    assert camera_pixel(0, 1) == 0x0203
    assert camera_pixel(1, 0) == 0x0304
    assert camera_stream()[:8] == bytes((0, 1, 2, 3, 4, 5, 6, 7))
    assert len(camera_stream()) == 153600
    word_fnv = 2166136261
    for index in range(0, 76800, 2):
        row, col = divmod(index, 320)
        word = camera_pixel(row, col) | (camera_pixel(row, col + 1) << 16)
        word_fnv = ((word_fnv ^ word) * 16777619) & 0xFFFFFFFF
    assert word_fnv != fnv1a(camera_stream())


def test_hal_dma_binding_abort_and_measurement_contracts() -> None:
    source = (ROOT / "crt/src/hal/spi.c").read_text()
    assert ".burst_beats = 1U" in source
    for name in ("CLOCK_HZ", "DIV", "TX_STALL_CYCLES", "RX_STALL_CYCLES", "FIFO_LEVELS"):
        assert f"RS_SPI_ABI_{name}" in source
    body = source.split("rs_status_t rs_spi_abort_dma", 1)[1].split(
        "rs_status_t rs_spi_recover", 1)[0]
    assert body.index("rs_spi_abort(timeout)") < body.index("rs_spi_dma_abort_one(tx_job")
    assert body.index("rs_spi_dma_abort_one(tx_job") < body.index("RS_SPI_ABI_STATUS_TRANSPORT_IDLE")
    assert "rs_dma_reset" not in body
    adapter = (ROOT / "app/board/src/st7789vi.c").read_text()
    body = adapter.split("static rs_status_t rs_st7789vi_start_segment", 1)[1].split(
        "rs_status_t rs_st7789vi_start_buffer", 1)[0]
    assert body.index("rs_spi_dma_bind") < body.index("rs_spi_arm")
    assert body.index("rs_spi_arm") < body.index("rs_spi_start")
    assert body.index("rs_spi_start") < body.index("rs_spi_dma_start")
