"""Independent byte-accurate GA2D P5 reference-model coverage."""

from __future__ import annotations

import random
from itertools import product
from pathlib import Path

import pytest

from test_ga2d import _run_iverilog_test, _run_verilator_test

from ga2d_reference import (
    A8,
    ARGB8888,
    BLEND,
    COLOR_FORMATS,
    CONVERT,
    COPY,
    FILL,
    RGB565,
    RGB888,
    XRGB8888,
    Plane,
    blend,
    blend_channel,
    blend_pixel,
    bytes_per_pixel,
    convert,
    convert_pixel,
    copy,
    effective_alpha,
    extent,
    fill,
    pack_color,
    pixel_alignment,
    unpack_pixel,
)

P5_DMA_SUCCESS_MARKER = (
    "GA2D P5 DMA test passed with independent AXI delay and validation-precedence coverage"
)


def test_p5_dma_rtl_verilator(tmp_path: Path) -> None:
    _run_verilator_test(
        tmp_path,
        "ga2d_dma_tb",
        "ga2d_dma_tb.sv",
        P5_DMA_SUCCESS_MARKER,
    )


def test_p5_dma_rtl_iverilog(tmp_path: Path) -> None:
    _run_iverilog_test(
        tmp_path,
        "ga2d_dma_tb",
        "ga2d_dma_tb.sv",
        P5_DMA_SUCCESS_MARKER,
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
def test_p5_fill_color_packing_is_byte_accurate(fmt: int, expected: bytes) -> None:
    assert pack_color(0x80123456, fmt) == expected


def test_p5_rgb565_expansion_and_repacking_cover_every_encoded_pixel() -> None:
    for packed in range(1 << 16):
        source = packed.to_bytes(2, byteorder="little")
        red, green, blue, alpha = unpack_pixel(source, RGB565)

        assert red == (((packed >> 11) & 0x1F) << 3) | (((packed >> 11) & 0x1F) >> 2)
        assert green == (((packed >> 5) & 0x3F) << 2) | (((packed >> 5) & 0x3F) >> 4)
        assert blue == ((packed & 0x1F) << 3) | ((packed & 0x1F) >> 2)
        assert alpha == 0xFF
        assert convert_pixel(source, RGB565, RGB565) == source


def test_p5_convert_preserves_only_argb_to_argb_alpha_and_normalizes_x() -> None:
    argb = bytes((0x56, 0x34, 0x12, 0x80))
    xrgb = bytes((0x56, 0x34, 0x12, 0xA5))
    rgb = bytes((0x12, 0x34, 0x56))

    assert convert_pixel(argb, ARGB8888, ARGB8888) == argb
    assert convert_pixel(argb, ARGB8888, XRGB8888) == bytes((0x56, 0x34, 0x12, 0xFF))
    assert convert_pixel(xrgb, XRGB8888, ARGB8888) == bytes((0x56, 0x34, 0x12, 0xFF))
    assert convert_pixel(rgb, RGB888, ARGB8888) == bytes((0x56, 0x34, 0x12, 0xFF))


@pytest.mark.parametrize(("source_format", "destination_format"), product(COLOR_FORMATS, repeat=2))
def test_p5_convert_accepts_every_color_format_pair(
    source_format: int, destination_format: int
) -> None:
    memory = bytearray([0xD3] * 1024)
    source = Plane(64, 32, source_format)
    destination = Plane(512, 32, destination_format)
    source_pixel = pack_color(0x80123456, source_format)

    memory[source.base : source.base + len(source_pixel)] = source_pixel
    convert(memory, source, destination, width=1, height=1)

    assert memory[
        destination.base : destination.base + bytes_per_pixel(destination_format)
    ] == convert_pixel(source_pixel, source_format, destination_format)


def test_p5_blend_uses_two_rounded_alpha_stages_and_opaque_destination_alpha() -> None:
    memory = bytearray([0xD3] * 512)
    foreground = Plane(32, 4, ARGB8888)
    background = Plane(96, 3, RGB888)
    destination = Plane(192, 4, ARGB8888)
    foreground_pixel = bytes((0x20, 0x40, 0x80, 0x7F))
    background_pixel = bytes((0x60, 0x30, 0x10))
    alpha = (0x7F * 0x80 + 127) // 255
    expected = bytes(
        (
            (0x20 * alpha + 0x10 * (255 - alpha) + 127) // 255,
            (0x40 * alpha + 0x30 * (255 - alpha) + 127) // 255,
            (0x80 * alpha + 0x60 * (255 - alpha) + 127) // 255,
            0xFF,
        )
    )

    memory[foreground.base : foreground.base + len(foreground_pixel)] = foreground_pixel
    memory[background.base : background.base + len(background_pixel)] = background_pixel
    blend(memory, foreground, background, destination, 1, 1, 0x80, 0xA5123456)

    assert memory[destination.base : destination.base + 4] == expected


def test_p5_a8_blend_uses_fixed_color_and_ignores_color_alpha() -> None:
    memory = bytearray([0xD3] * 512)
    foreground = Plane(17, 1, A8)
    background = Plane(96, 4, XRGB8888)
    destination = Plane(192, 4, XRGB8888)
    foreground_pixel = bytes((0x80,))
    background_pixel = bytes((0x06, 0x05, 0x04, 0x77))
    color = 0xA5123456
    alpha = (0x80 * 0x40 + 127) // 255
    expected = bytes(
        (
            (0x56 * alpha + 0x06 * (255 - alpha) + 127) // 255,
            (0x34 * alpha + 0x05 * (255 - alpha) + 127) // 255,
            (0x12 * alpha + 0x04 * (255 - alpha) + 127) // 255,
            0xFF,
        )
    )

    memory[foreground.base : foreground.base + len(foreground_pixel)] = foreground_pixel
    memory[background.base : background.base + len(background_pixel)] = background_pixel
    blend(memory, foreground, background, destination, 1, 1, 0x40, color)

    assert memory[destination.base : destination.base + 4] == expected


def test_p5_effective_alpha_covers_every_plane_and_global_alpha_pair() -> None:
    for plane_alpha in range(256):
        for global_alpha in range(256):
            assert effective_alpha(plane_alpha, global_alpha) == (
                plane_alpha * global_alpha + 127
            ) // 255


@pytest.mark.parametrize("alpha", (0, 1, 127, 128, 254, 255))
def test_p5_blend_channel_rounding_boundary_and_diagnostic_ramps(alpha: int) -> None:
    for foreground in range(0, 256, 17):
        for background in range(0, 256, 19):
            assert blend_channel(foreground, background, alpha) == (
                foreground * alpha + background * (255 - alpha) + 127
            ) // 255


def test_p5_blend_inplace_background_reads_before_overwriting_each_pixel() -> None:
    memory = bytearray([0xD3] * 1024)
    foreground = Plane(17, 5, A8)
    background_and_destination = Plane(128, 16, RGB888)
    original_background = (
        bytes((0x10, 0x20, 0x30, 0x40, 0x50, 0x60, 0x70, 0x80, 0x90))
        + bytes((0xAA,) * 7)
    )
    coverages = bytes((0x00, 0x80, 0xFF))
    expected = []

    memory[foreground.base : foreground.base + 3] = coverages
    memory[
        background_and_destination.base : background_and_destination.base + len(original_background)
    ] = original_background
    for pixel in range(3):
        source = original_background[pixel * 3 : (pixel + 1) * 3]
        expected.extend(
            blend_pixel(
                coverages[pixel : pixel + 1],
                A8,
                source,
                RGB888,
                RGB888,
                0xFF,
                0x00123456,
            )
        )

    blend(
        memory,
        foreground,
        background_and_destination,
        background_and_destination,
        3,
        1,
        0xFF,
        0x00123456,
    )

    assert memory[128:137] == bytes(expected)
    assert memory[137:144] == bytes((0xAA,) * 7)


def test_p5_fill_writes_logical_rows_without_touching_guards_or_padding() -> None:
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


def test_p5_copy_preserves_bytes_and_leaves_row_padding_and_guards_untouched() -> None:
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
def test_p5_copy_and_convert_reject_all_foreground_destination_overlap(
    foreground: Plane, destination: Plane
) -> None:
    memory = bytearray(256)
    with pytest.raises(ValueError, match="overlap"):
        copy(memory, foreground, destination, width=4, height=2)
    with pytest.raises(ValueError, match="overlap"):
        convert(memory, foreground, destination, width=4, height=2)


def test_p5_blend_rejects_invalid_a8_roles_and_nonexact_destination_overlap() -> None:
    memory = bytearray(512)
    foreground = Plane(16, 4, A8)
    background = Plane(96, 16, RGB565)
    destination = Plane(96, 18, RGB565)

    with pytest.raises(ValueError, match="only when exactly in-place"):
        blend(memory, foreground, background, destination, 4, 2, 0xFF, 0)
    with pytest.raises(ValueError, match="background requires a color"):
        blend(memory, foreground, Plane(192, 4, A8), Plane(256, 4, XRGB8888), 1, 1, 0xFF, 0)
    with pytest.raises(ValueError, match="destination requires a color"):
        blend(memory, foreground, Plane(192, 4, XRGB8888), Plane(256, 4, A8), 1, 1, 0xFF, 0)


def test_p5_extent_allows_byte_aligned_rgb888_and_32_bit_limit() -> None:
    assert extent(Plane(base=1, pitch=5, fmt=RGB888), width=1, height=1) == (1, 4)
    edge = Plane(base=0xFFFFFFFC, pitch=4, fmt=XRGB8888)
    assert extent(edge, width=1, height=1) == (0xFFFFFFFC, 1 << 32)
    with pytest.raises(ValueError, match="overflows"):
        extent(Plane(base=0xFFFFFFFC, pitch=8, fmt=XRGB8888), width=1, height=2)


def _aligned_plane(base: int, width: int, fmt: int, extra_pixels: int) -> Plane:
    alignment = pixel_alignment(fmt)
    aligned_base = (base + alignment - 1) & ~(alignment - 1)
    return Plane(
        aligned_base,
        width * bytes_per_pixel(fmt) + extra_pixels * alignment,
        fmt,
    )


def _randomize_logical_rows(
    memory: bytearray, plane: Plane, width: int, height: int, random_source: random.Random
) -> None:
    logical_bytes = width * bytes_per_pixel(plane.fmt)
    for line in range(height):
        row = plane.base + line * plane.pitch
        memory[row : row + logical_bytes] = random_source.randbytes(logical_bytes)


def _assert_destination_padding(
    memory: bytearray, destination: Plane, width: int, height: int, sentinel: int
) -> None:
    logical_bytes = width * bytes_per_pixel(destination.fmt)
    assert memory[destination.base - 1] == sentinel
    for line in range(height):
        row = destination.base + line * destination.pitch
        assert memory[row + logical_bytes : row + destination.pitch] == bytes(
            [sentinel] * (destination.pitch - logical_bytes)
        )
    assert memory[destination.base + (height - 1) * destination.pitch + logical_bytes] == sentinel


def _p5_legal_cases() -> tuple[tuple[int, int | None, int | None, int], ...]:
    return (
        *((FILL, None, None, destination_format) for destination_format in COLOR_FORMATS),
        *((COPY, source_format, None, source_format) for source_format in COLOR_FORMATS),
        *(
            (CONVERT, source_format, None, destination_format)
            for source_format, destination_format in product(COLOR_FORMATS, repeat=2)
        ),
        *(
            (BLEND, foreground_format, background_format, destination_format)
            for foreground_format in (*COLOR_FORMATS, A8)
            for background_format, destination_format in product(COLOR_FORMATS, repeat=2)
        ),
    )


def test_p5_reference_campaign_is_deterministic_for_ten_thousand_mixed_jobs() -> None:
    legal_cases = _p5_legal_cases()
    seen_cases: set[tuple[int, int | None, int | None, int]] = set()
    seen_source_offsets = {fmt: set() for fmt in (*COLOR_FORMATS, A8)}
    seen_destination_offsets = {fmt: set() for fmt in COLOR_FORMATS}
    saw_inplace_background = False
    completed = 0

    for seed in range(10):
        random_source = random.Random(seed)
        for job_index in range(1000):
            operation, foreground_format, background_format, destination_format = legal_cases[
                (seed * 1000 + job_index) % len(legal_cases)
            ]
            offset_epoch = (seed * 1000 + job_index) // len(legal_cases)
            width = random_source.randint(1, 15)
            height = random_source.randint(1, 7)
            destination = _aligned_plane(
                8192 + (offset_epoch % 8),
                width,
                destination_format,
                random_source.randrange(4),
            )
            seen_destination_offsets[destination_format].add(destination.base % 8)
            memory = bytearray([0xA5] * 16384)
            for line in range(height):
                row = destination.base + line * destination.pitch
                memory[
                    row
                    + width * bytes_per_pixel(destination_format) : row
                    + destination.pitch
                ] = bytes([0xD3] * (destination.pitch - width * bytes_per_pixel(destination_format)))
            memory[destination.base - 1] = 0xD3
            memory[
                destination.base
                + (height - 1) * destination.pitch
                + width * bytes_per_pixel(destination_format)
            ] = 0xD3

            if operation == FILL:
                fill(memory, destination, width, height, random_source.getrandbits(32))
            else:
                assert foreground_format is not None
                foreground = _aligned_plane(
                    1024 + ((offset_epoch * 3) % 8),
                    width,
                    foreground_format,
                    random_source.randrange(4),
                )
                seen_source_offsets[foreground_format].add(foreground.base % 8)
                _randomize_logical_rows(memory, foreground, width, height, random_source)
                if operation == COPY:
                    copy(memory, foreground, destination, width, height)
                elif operation == CONVERT:
                    convert(memory, foreground, destination, width, height)
                else:
                    assert background_format is not None
                    if (
                        background_format == destination_format
                        and (job_index % 4) == 0
                    ):
                        background = destination
                        saw_inplace_background = True
                    else:
                        background = _aligned_plane(
                            4096 + ((offset_epoch * 5) % 8),
                            width,
                            background_format,
                            random_source.randrange(4),
                        )
                    seen_source_offsets[background_format].add(background.base % 8)
                    _randomize_logical_rows(memory, background, width, height, random_source)
                    blend(
                        memory,
                        foreground,
                        background,
                        destination,
                        width,
                        height,
                        random_source.randrange(256),
                        random_source.getrandbits(32),
                    )
            _assert_destination_padding(memory, destination, width, height, 0xD3)
            seen_cases.add((operation, foreground_format, background_format, destination_format))
            completed += 1

    assert completed == 10000
    assert seen_cases == set(legal_cases)
    assert saw_inplace_background
    for fmt, offsets in seen_source_offsets.items():
        assert offsets == {offset for offset in range(8) if offset % pixel_alignment(fmt) == 0}
    for fmt, offsets in seen_destination_offsets.items():
        assert offsets == {offset for offset in range(8) if offset % pixel_alignment(fmt) == 0}
