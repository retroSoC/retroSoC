"""Independent P4 FILL/COPY reference-model coverage."""

from __future__ import annotations

import random
from pathlib import Path

import pytest

from test_ga2d import _run_iverilog_test, _run_verilator_test

from ga2d_reference import (
    ARGB8888,
    RGB565,
    RGB888,
    XRGB8888,
    Plane,
    copy,
    extent,
    fill,
    pack_color,
)


def test_p4_dma_rtl_verilator(tmp_path: Path) -> None:
    _run_verilator_test(
        tmp_path,
        "ga2d_dma_tb",
        "ga2d_dma_tb.sv",
        "GA2D P4 DMA test passed with independent AXI delay coverage",
    )


def test_p4_dma_rtl_iverilog(tmp_path: Path) -> None:
    _run_iverilog_test(
        tmp_path,
        "ga2d_dma_tb",
        "ga2d_dma_tb.sv",
        "GA2D P4 DMA test passed with independent AXI delay coverage",
    )


@pytest.mark.parametrize(
    ("fmt", "expected"),
    [
        (RGB565, bytes((0xAA, 0x11))),
        (RGB888, bytes((0x12, 0x34, 0x56))),
        (XRGB8888, bytes((0x56, 0x34, 0x12, 0xFF))),
        (ARGB8888, bytes((0x56, 0x34, 0x12, 0x80))),
    ],
)
def test_p4_fill_color_packing_is_byte_accurate(fmt: int, expected: bytes) -> None:
    assert pack_color(0x80123456, fmt) == expected


def test_p4_fill_writes_logical_rows_without_touching_guards_or_padding() -> None:
    memory = bytearray([0xD3] * 256)
    destination = Plane(base=18, pitch=18, fmt=RGB888)

    fill(memory, destination, width=3, height=3, color=0xAA102030)

    expected = bytes((0x10, 0x20, 0x30)) * 3
    for line in range(3):
        row = destination.base + line * destination.pitch
        assert memory[row : row + len(expected)] == expected
        assert memory[row - 1] == 0xD3
        assert memory[row + len(expected) : row + destination.pitch] == bytes(
            [0xD3] * (destination.pitch - len(expected))
        )


def test_p4_copy_preserves_bytes_and_leaves_row_padding_and_guards_untouched() -> None:
    memory = bytearray([0xC7] * 512)
    foreground = Plane(base=20, pitch=24, fmt=ARGB8888)
    destination = Plane(base=292, pitch=32, fmt=ARGB8888)
    logical_bytes = 5 * 4
    for line in range(3):
        source = foreground.base + line * foreground.pitch
        memory[source : source + logical_bytes] = bytes(
            (line * 31 + offset for offset in range(logical_bytes))
        )

    copy(memory, foreground, destination, width=5, height=3)

    for line in range(3):
        source = foreground.base + line * foreground.pitch
        target = destination.base + line * destination.pitch
        assert memory[target : target + logical_bytes] == memory[source : source + logical_bytes]
        assert memory[target - 1] == 0xC7
        assert memory[target + logical_bytes : target + destination.pitch] == bytes(
            [0xC7] * (destination.pitch - logical_bytes)
        )


@pytest.mark.parametrize(
    ("foreground", "destination"),
    [
        (Plane(32, 16, RGB565), Plane(32, 16, RGB565)),
        (Plane(32, 16, RGB565), Plane(40, 16, RGB565)),
        (Plane(32, 16, RGB565), Plane(48, 16, RGB565)),
    ],
)
def test_p4_copy_rejects_all_foreground_destination_overlap(
    foreground: Plane, destination: Plane
) -> None:
    memory = bytearray(256)
    with pytest.raises(ValueError, match="overlap"):
        copy(memory, foreground, destination, width=4, height=2)


def test_p4_extent_allows_end_at_32_bit_limit_and_rejects_overflow() -> None:
    edge = Plane(base=0xFFFFFFFC, pitch=4, fmt=XRGB8888)
    assert extent(edge, width=1, height=1) == (0xFFFFFFFC, 1 << 32)
    with pytest.raises(ValueError, match="overflows"):
        extent(Plane(base=0xFFFFFFFC, pitch=8, fmt=XRGB8888), width=1, height=2)


def test_p4_reference_campaign_is_deterministic_for_ten_thousand_small_jobs() -> None:
    formats = (RGB565, RGB888, XRGB8888, ARGB8888)
    completed = 0
    for seed in range(10):
        random_source = random.Random(seed)
        for _ in range(1000):
            fmt = random_source.choice(formats)
            bytes_per_pixel = len(pack_color(0, fmt))
            width = random_source.randint(1, 15)
            height = random_source.randint(1, 7)
            logical_bytes = width * bytes_per_pixel
            foreground = Plane(
                base=120,
                pitch=logical_bytes + bytes_per_pixel * random_source.randint(0, 3),
                fmt=fmt,
            )
            destination = Plane(
                base=2064,
                pitch=logical_bytes + bytes_per_pixel * random_source.randint(0, 3),
                fmt=fmt,
            )
            memory = bytearray([0xA5] * 4096)
            for line in range(height):
                source = foreground.base + line * foreground.pitch
                memory[source : source + logical_bytes] = random_source.randbytes(logical_bytes)
            if random_source.randrange(2) == 0:
                copy(memory, foreground, destination, width, height)
                for line in range(height):
                    source = foreground.base + line * foreground.pitch
                    target = destination.base + line * destination.pitch
                    assert memory[target : target + logical_bytes] == memory[
                        source : source + logical_bytes
                    ]
            else:
                color = random_source.getrandbits(32)
                fill(memory, destination, width, height, color)
                expected = pack_color(color, fmt) * width
                for line in range(height):
                    target = destination.base + line * destination.pitch
                    assert memory[target : target + logical_bytes] == expected
            completed += 1
    assert completed == 10000
