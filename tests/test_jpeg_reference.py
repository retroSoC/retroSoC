"""Tests for the deterministic baseline JPEG reference model."""

from __future__ import annotations

import io

import pytest

from jpeg_reference import (
    JpegModelError,
    Sampling,
    decode_rgb,
    encode_rgb,
    fdct,
    idct,
    scaled_quant_table,
    LUMA_QUANT,
)


def _pattern(width: int, height: int) -> bytes:
    data = bytearray()
    for y_pos in range(height):
        for x_pos in range(width):
            data.extend(
                (
                    (x_pos * 17 + y_pos * 3) & 0xFF,
                    (x_pos * 5 + y_pos * 19) & 0xFF,
                    (x_pos * 11 + y_pos * 7) & 0xFF,
                )
            )
    return bytes(data)


def test_constant_block_transform_round_trip() -> None:
    coefficients = fdct([1] * 64)
    assert coefficients[0] == 8
    assert coefficients[1:] == (0,) * 63
    assert idct(coefficients) == (1,) * 64


def test_quality_scaling_bounds() -> None:
    assert scaled_quant_table(LUMA_QUANT, 50) == LUMA_QUANT
    assert scaled_quant_table(LUMA_QUANT, 100) == (1,) * 64
    assert max(scaled_quant_table(LUMA_QUANT, 1)) == 255
    with pytest.raises(ValueError, match="1..100"):
        scaled_quant_table(LUMA_QUANT, 0)


@pytest.mark.parametrize(
    "sampling",
    [Sampling.GRAY, Sampling.YUV444, Sampling.YUV422, Sampling.YUV420],
)
@pytest.mark.parametrize("dimensions", [(1, 1), (8, 8), (17, 15), (31, 19)])
def test_baseline_round_trip(sampling: Sampling, dimensions: tuple[int, int]) -> None:
    width, height = dimensions
    encoded = encode_rgb(_pattern(width, height), width, height, quality=90, sampling=sampling)
    decoded = decode_rgb(encoded)
    assert decoded.width == width
    assert decoded.height == height
    assert decoded.sampling == sampling
    assert len(decoded.rgb) == width * height * 3
    assert encoded[:2] == b"\xff\xd8"
    assert encoded[-2:] == b"\xff\xd9"


def test_restart_markers_round_trip() -> None:
    encoded = encode_rgb(
        _pattern(33, 25),
        33,
        25,
        quality=80,
        sampling=Sampling.YUV420,
        restart_interval=1,
    )
    assert b"\xff\xd0" in encoded
    assert b"\xff\xd1" in encoded
    decoded = decode_rgb(encoded)
    assert (decoded.width, decoded.height) == (33, 25)


def test_dimension_and_process_rejections() -> None:
    encoded = encode_rgb(_pattern(8, 8), 8, 8)
    with pytest.raises(JpegModelError, match="dimension limit"):
        decode_rgb(encoded, max_dimension=7)
    progressive = encoded.replace(b"\xff\xc0", b"\xff\xc2", 1)
    with pytest.raises(JpegModelError, match="unsupported JPEG frame process"):
        decode_rgb(progressive)
    with pytest.raises(JpegModelError):
        decode_rgb(encoded[:-3])


def test_stream_is_accepted_by_pillow_when_available() -> None:
    pillow = pytest.importorskip("PIL.Image")
    encoded = encode_rgb(_pattern(19, 13), 19, 13, quality=85, sampling=Sampling.YUV420)
    image = pillow.open(io.BytesIO(encoded))
    image.load()
    assert image.size == (19, 13)
    assert image.mode == "RGB"
