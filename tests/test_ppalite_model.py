"""Independent frozen PPALite pixel and layout examples."""
from __future__ import annotations

from pathlib import Path
import sys

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

from ppalite_model import (  # noqa: E402
    Config,
    PPALiteError,
    ceil_div,
    gray_rgb565,
    input_words,
    layout,
    output_words,
    render,
)


def raster(config: Config) -> bytes:
    return bytes((index * 37 + 11) & 0xFF for index in range(config.width * config.height * 2))


def test_dvp_word_order_and_nonzero_ignored_tail() -> None:
    config = Config(width=3, height=1)
    sensor = bytes(range(6))
    words = input_words(config, sensor, ignored_tail=0xBEEF)
    assert words == [
        {"data": 0x02030001, "keep": 15, "strb": 15, "sof": 1, "last": 0},
        {"data": 0xEFBE0405, "keep": 3, "strb": 3, "sof": 0, "last": 1},
    ]


def test_all_yuv_orders_preserve_y_without_range_expansion() -> None:
    for value in (0, 16, 235, 255):
        for fmt, expected_first in ((2, True), (3, False), (4, True), (5, False)):
            config = Config(width=1, height=1, input_format=fmt, gray8=True)
            pair = (value, 0xA5) if expected_first else (0xA5, value)
            rendered, _ = render(config, bytes(pair))
            assert rendered == bytes((value, 0, 0, 0))


def test_gray_rgb565_and_rgb_channel_swap() -> None:
    for value in (0, 16, 235, 255):
        config = Config(width=1, height=1, input_format=2)
        rendered, _ = render(config, bytes((value, 0)))
        expected = gray_rgb565(value)
        assert int.from_bytes(rendered[:2], "little") == expected
    original = (31 << 11) | (17 << 5) | 9
    swapped = (9 << 11) | (17 << 5) | 31
    config = Config(width=1, height=1, rgb_swap=True)
    rendered, _ = render(config, original.to_bytes(2, "big"))
    assert int.from_bytes(rendered[:2], "little") == swapped


def test_rgb_byte_exchange_does_not_swap_pixel_or_row_order() -> None:
    config = Config(width=2, height=1, output_byte_swap=True)
    pixels = (0x1234, 0xABCD)
    sensor = b"".join(pixel.to_bytes(2, "big") for pixel in pixels)
    rendered, _ = render(config, sensor)
    assert rendered == bytes((0x12, 0x34, 0xAB, 0xCD))
    assert output_words(config, sensor) == [
        {"data": 0xCDAB3412, "keep": 15, "strb": 15, "sof": 1, "last": 1}
    ]


@pytest.mark.parametrize("step_x", (1, 2, 4))
@pytest.mark.parametrize("step_y", (1, 2, 4))
def test_geometry_and_dropped_rows_are_exact(step_x: int, step_y: int) -> None:
    for width, height in ((1, 1), (3, 5), (319, 239)):
        for phase_x in range(min(step_x, width)):
            for phase_y in range(min(step_y, height)):
                config = Config(width=width, height=height, gray8=True, step_x=step_x,
                                step_y=step_y, phase_x=phase_x, phase_y=phase_y,
                                input_format=2)
                shape = layout(config)
                assert shape["output_width"] == ceil_div(width - phase_x, step_x)
                assert shape["output_height"] == ceil_div(height - phase_y, step_y)
                if (width, height) == (3, 5):
                    rendered, rows = render(config, raster(config))
                    assert len(rows) == shape["output_height"]
                    assert len(rendered) == shape["transport_bytes"]
                    words = output_words(config, raster(config))
                    assert words[0]["sof"] == 1
                    assert sum(word["sof"] for word in words) == 1
                    assert sum(word["last"] for word in words) == shape["output_height"]


def test_frozen_arithmetic_examples() -> None:
    cases = (
        (Config(320, 240, gray8=True, input_format=2), (320, 320, 76800, 76800, 19200)),
        (Config(320, 240, gray8=True, input_format=2, step_x=2, step_y=2),
         (160, 160, 19200, 19200, 4800)),
        (Config(320, 240, input_format=2, step_x=2, step_y=2),
         (320, 320, 38400, 38400, 9600)),
        (Config(319, 239, gray8=True, input_format=2, step_x=2, step_y=2, phase_x=1),
         (159, 160, 19080, 19200, 4800)),
        (Config(5, 3, gray8=True, input_format=2, step_x=2, step_y=2),
         (3, 4, 6, 8, 2)),
    )
    for config, expected in cases:
        result = layout(config)
        actual = tuple(result[name] for name in
                       ("row_bytes", "stride_bytes", "valid_bytes", "transport_bytes", "expected_words"))
        assert actual == expected


def test_row_padding_is_zero_and_not_shared_across_rows() -> None:
    config = Config(5, 3, gray8=True, input_format=2, step_x=2, step_y=2)
    rendered, rows = render(config, raster(config))
    assert list(map(len, rows)) == [3, 3]
    assert rendered[3] == rendered[7] == 0
    assert len(rendered) == 8


@pytest.mark.parametrize("changes", (
    {"width": 0}, {"height": 0}, {"step_x": 3}, {"step_y": 0},
    {"phase_x": 1}, {"phase_y": 4}, {"input_format": 6},
    {"gray8": True}, {"input_format": 2, "rgb_swap": True},
    {"gray8": True, "input_format": 2, "output_byte_swap": True},
))
def test_invalid_configuration(changes: dict[str, int | bool]) -> None:
    values = {"width": 1, "height": 1}
    values.update(changes)
    with pytest.raises(PPALiteError):
        layout(Config(**values))


def test_overflow_capacity_and_alignment_are_rejected() -> None:
    with pytest.raises(PPALiteError):
        layout(Config(65535, 65535))
    with pytest.raises(PPALiteError):
        layout(Config(4, 4, destination=2))
    with pytest.raises(PPALiteError):
        layout(Config(4, 4, destination=-4))
    with pytest.raises(PPALiteError):
        layout(Config(4, 4, destination=1 << 32))
    with pytest.raises(PPALiteError):
        layout(Config(4, 4, destination=0xFFFFFFF0, capacity=32))
    with pytest.raises(PPALiteError):
        layout(Config(4, 4, capacity=15))
    assert layout(Config(2, 4, destination=0xFFFFFFF0, capacity=16))["transport_bytes"] == 16


def test_input_words_include_discarded_trailing_pixels_and_lines() -> None:
    config = Config(5, 5, input_format=2, gray8=True, step_x=4, step_y=4, phase_x=3, phase_y=3)
    sensor = raster(config)
    shape = layout(config)
    assert len(input_words(config, sensor)) == shape["input_words"] == 15
    assert len(output_words(config, sensor)) == 1
    assert len(render(config, sensor)[0]) == 4
