"""SPI-P4 display adapter, acceptance image, and panel-checker contracts."""
from __future__ import annotations

from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from scripts.spi_p4 import check_log, fnv1a, golden_pixel, window_stream  # noqa: E402

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
    assert not any(token in image for token in BANNED)


def _render_log(corrupt: str | None = None) -> str:
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

    add_window(1, 1, (0, 0, 319, 239), None, 0)
    add_window(2, 2, (0, 0, 319, 239), None, 0)
    add_window(3, 3, (13, 17, 45, 29), None, 0)
    add_window(4, 4, (319, 0, 319, 239), None, 0)
    add_window(5, 5, (200, 239, 260, 239), None, 0)
    lines.append("SPI_P4_CMD code=36 params=1 madctl=60")
    add_window(6, 6, (5, 7, 45, 29), None, 0)
    lines.append("SPI_P4_CMD code=36 params=1 madctl=00")
    add_window(7, 8, (0, 0, 319, 239), 544, 1)
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
