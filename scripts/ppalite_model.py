"""Independent scalar pixel, geometry and transport oracle for PPALite P1."""
from __future__ import annotations

from dataclasses import dataclass


class PPALiteError(ValueError):
    """A frozen PPALite configuration or transport constraint was violated."""


@dataclass(frozen=True)
class Config:
    width: int
    height: int
    input_format: int = 0
    gray8: bool = False
    rgb_swap: bool = False
    output_byte_swap: bool = False
    step_x: int = 1
    step_y: int = 1
    phase_x: int = 0
    phase_y: int = 0
    destination: int = 0
    capacity: int = 0xFFFFFFFF

    @property
    def register_config(self) -> int:
        return (self.input_format | (int(self.gray8) << 4) | (int(self.rgb_swap) << 5)
                | (int(self.output_byte_swap) << 6))

    @property
    def sampling(self) -> int:
        def code(step: int) -> int:
            return {1: 0, 2: 1, 4: 2}[step]
        return (code(self.step_x) | (code(self.step_y) << 2) | (self.phase_x << 8)
                | (self.phase_y << 16))

    def validate(self) -> None:
        if not 1 <= self.width <= 65535 or not 1 <= self.height <= 65535:
            raise PPALiteError("input dimensions must be in 1..65535")
        if self.input_format not in range(6):
            raise PPALiteError("unknown input format")
        for step, phase, dimension, axis in (
                (self.step_x, self.phase_x, self.width, "x"),
                (self.step_y, self.phase_y, self.height, "y")):
            if step not in (1, 2, 4):
                raise PPALiteError(f"{axis} step must be 1, 2 or 4")
            if not 0 <= phase < min(step, dimension):
                raise PPALiteError(f"invalid {axis} sampling phase")
        rgb_input = self.input_format < 2
        if rgb_input and self.gray8:
            raise PPALiteError("RGB to GRAY8 is not a supported color conversion")
        if self.rgb_swap and not rgb_input:
            raise PPALiteError("RGB_SWAP is only valid for RGB input")
        if self.output_byte_swap and self.gray8:
            raise PPALiteError("output byte exchange is only valid for RGB565 output")


def ceil_div(value: int, divisor: int) -> int:
    return (value + divisor - 1) // divisor


def layout(config: Config) -> dict[str, int]:
    config.validate()
    out_w = ceil_div(config.width - config.phase_x, config.step_x)
    out_h = ceil_div(config.height - config.phase_y, config.step_y)
    bytes_per_pixel = 1 if config.gray8 else 2
    row_bytes = out_w * bytes_per_pixel
    stride = 4 * ceil_div(row_bytes, 4)
    valid_bytes = row_bytes * out_h
    transport = stride * out_h
    expected_words = transport // 4
    input_words = ceil_div(config.width, 2) * config.height
    if transport > 0xFFFFFFFC:
        raise PPALiteError("DMA transport exceeds its 32-bit multiple-of-four range")
    if not 0 <= config.destination <= 0xFFFFFFFF:
        raise PPALiteError("destination is not a 32-bit address")
    if config.destination & 3:
        raise PPALiteError("destination is not word aligned")
    if config.destination + transport > 1 << 32:
        raise PPALiteError("destination address range overflows")
    if config.capacity > 0xFFFFFFFF or config.capacity < transport:
        raise PPALiteError("destination capacity is insufficient")
    if not 0 <= input_words <= 0xFFFFFFFF or not 0 <= config.width * config.height <= 0xFFFFFFFF:
        raise PPALiteError("input counter overflow")
    return {
        "output_width": out_w, "output_height": out_h, "row_bytes": row_bytes,
        "stride_bytes": stride, "valid_bytes": valid_bytes, "transport_bytes": transport,
        "expected_words": expected_words, "input_words": input_words,
        "bytes_per_pixel": bytes_per_pixel,
    }


def pixel_from_sensor(config: Config, first: int, second: int) -> int:
    if config.input_format in (2, 4):
        return first
    if config.input_format in (3, 5):
        return second
    pixel = ((first << 8) | second) if config.input_format == 0 else ((second << 8) | first)
    if config.rgb_swap:
        pixel = ((pixel & 0x1F) << 11) | (pixel & 0x07E0) | ((pixel >> 11) & 0x1F)
    return pixel


def gray_rgb565(y: int) -> int:
    if not 0 <= y <= 255:
        raise PPALiteError("Y is not an unsigned byte")
    return ((y >> 3) << 11) | ((y >> 2) << 5) | (y >> 3)


def render(config: Config, sensor: bytes) -> tuple[bytes, list[list[int]]]:
    if len(sensor) != config.width * config.height * 2:
        raise PPALiteError("sensor raster size does not match the active geometry")
    shape = layout(config)
    rows: list[list[int]] = []
    output = bytearray()
    for y in range(config.height):
        retained: list[int] = []
        if y >= config.phase_y and (y - config.phase_y) % config.step_y == 0:
            for x in range(config.phase_x, config.width, config.step_x):
                index = 2 * (y * config.width + x)
                pixel = pixel_from_sensor(config, sensor[index], sensor[index + 1])
                if config.gray8:
                    retained.append(pixel)
                else:
                    if config.input_format >= 2:
                        pixel = gray_rgb565(pixel)
                    if config.output_byte_swap:
                        pixel = ((pixel & 0xFF) << 8) | (pixel >> 8)
                    retained.extend((pixel & 0xFF, pixel >> 8))
            assert len(retained) == shape["row_bytes"]
            rows.append(retained)
            output.extend(retained)
            output.extend(bytes(shape["stride_bytes"] - len(retained)))
    assert len(output) == shape["transport_bytes"]
    return bytes(output), rows


def input_words(config: Config, sensor: bytes, ignored_tail: int = 0) -> list[dict[str, int]]:
    if len(sensor) != config.width * config.height * 2 or ignored_tail & ~0xFFFF:
        raise PPALiteError("invalid input raster or halfword tail")
    chronological = bytearray(sensor)
    result = []
    for y in range(config.height):
        row = chronological[y * config.width * 2:(y + 1) * config.width * 2]
        for word_index in range(ceil_div(config.width, 2)):
            offset = word_index * 4
            part = row[offset:offset + 4]
            halfword_tail = len(part) == 2
            if halfword_tail:
                part += ignored_tail.to_bytes(2, "little")
            data = int.from_bytes(part[2:4] + part[0:2], "big")
            result.append({"data": data, "keep": 3 if halfword_tail else 15,
                           "strb": 3 if halfword_tail else 15,
                           "sof": int(y == 0 and word_index == 0),
                           "last": int(word_index == ceil_div(config.width, 2) - 1)})
    assert len(result) == layout(config)["input_words"]
    return result


def output_words(config: Config, sensor: bytes) -> list[dict[str, int]]:
    rendered, _ = render(config, sensor)
    stride = layout(config)["stride_bytes"]
    result = []
    for row_start in range(0, len(rendered), stride):
        row = rendered[row_start:row_start + stride]
        for word_start in range(0, stride, 4):
            result.append({"data": int.from_bytes(row[word_start:word_start + 4], "little"),
                           "keep": 15, "strb": 15,
                           "sof": int(not result), "last": int(word_start + 4 == stride)})
    return result
