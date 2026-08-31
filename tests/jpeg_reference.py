"""Deterministic 8-bit baseline JPEG reference used by the RTL tests.

The model intentionally implements only the JPEG profile supported by the
retroSoC hardware: sequential DCT, Huffman entropy coding, one or three color
components, and the common 4:4:4, 4:2:2, and 4:2:0 sampling modes.  It uses a
fixed integer cosine matrix so RTL and software tests share exact rounding.
"""

from __future__ import annotations

import math
from dataclasses import dataclass
from enum import IntEnum


class JpegModelError(ValueError):
    """Raised for malformed or unsupported JPEG input."""


class Sampling(IntEnum):
    GRAY = 0
    YUV444 = 1
    YUV422 = 2
    YUV420 = 3


@dataclass(frozen=True)
class DecodedImage:
    width: int
    height: int
    sampling: Sampling
    rgb: bytes


ZIGZAG = (
    0,
    1,
    8,
    16,
    9,
    2,
    3,
    10,
    17,
    24,
    32,
    25,
    18,
    11,
    4,
    5,
    12,
    19,
    26,
    33,
    40,
    48,
    41,
    34,
    27,
    20,
    13,
    6,
    7,
    14,
    21,
    28,
    35,
    42,
    49,
    56,
    57,
    50,
    43,
    36,
    29,
    22,
    15,
    23,
    30,
    37,
    44,
    51,
    58,
    59,
    52,
    45,
    38,
    31,
    39,
    46,
    53,
    60,
    61,
    54,
    47,
    55,
    62,
    63,
)

LUMA_QUANT = (
    16,
    11,
    10,
    16,
    24,
    40,
    51,
    61,
    12,
    12,
    14,
    19,
    26,
    58,
    60,
    55,
    14,
    13,
    16,
    24,
    40,
    57,
    69,
    56,
    14,
    17,
    22,
    29,
    51,
    87,
    80,
    62,
    18,
    22,
    37,
    56,
    68,
    109,
    103,
    77,
    24,
    35,
    55,
    64,
    81,
    104,
    113,
    92,
    49,
    64,
    78,
    87,
    103,
    121,
    120,
    101,
    72,
    92,
    95,
    98,
    112,
    100,
    103,
    99,
)

CHROMA_QUANT = (
    17,
    18,
    24,
    47,
    99,
    99,
    99,
    99,
    18,
    21,
    26,
    66,
    99,
    99,
    99,
    99,
    24,
    26,
    56,
    99,
    99,
    99,
    99,
    99,
    47,
    66,
    99,
    99,
    99,
    99,
    99,
    99,
    99,
    99,
    99,
    99,
    99,
    99,
    99,
    99,
    99,
    99,
    99,
    99,
    99,
    99,
    99,
    99,
    99,
    99,
    99,
    99,
    99,
    99,
    99,
    99,
    99,
    99,
    99,
    99,
    99,
    99,
    99,
    99,
)

DC_LUMA_BITS = (0, 1, 5, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0)
DC_CHROMA_BITS = (0, 3, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0)
DC_VALUES = tuple(range(12))

AC_LUMA_BITS = (0, 2, 1, 3, 3, 2, 4, 3, 5, 5, 4, 4, 0, 0, 1, 125)
AC_LUMA_VALUES = (
    0x01, 0x02, 0x03, 0x00, 0x04, 0x11, 0x05, 0x12, 0x21, 0x31, 0x41, 0x06,
    0x13, 0x51, 0x61, 0x07, 0x22, 0x71, 0x14, 0x32, 0x81, 0x91, 0xA1, 0x08,
    0x23, 0x42, 0xB1, 0xC1, 0x15, 0x52, 0xD1, 0xF0, 0x24, 0x33, 0x62, 0x72,
    0x82, 0x09, 0x0A, 0x16, 0x17, 0x18, 0x19, 0x1A, 0x25, 0x26, 0x27, 0x28,
    0x29, 0x2A, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39, 0x3A, 0x43, 0x44, 0x45,
    0x46, 0x47, 0x48, 0x49, 0x4A, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58, 0x59,
    0x5A, 0x63, 0x64, 0x65, 0x66, 0x67, 0x68, 0x69, 0x6A, 0x73, 0x74, 0x75,
    0x76, 0x77, 0x78, 0x79, 0x7A, 0x83, 0x84, 0x85, 0x86, 0x87, 0x88, 0x89,
    0x8A, 0x92, 0x93, 0x94, 0x95, 0x96, 0x97, 0x98, 0x99, 0x9A, 0xA2, 0xA3,
    0xA4, 0xA5, 0xA6, 0xA7, 0xA8, 0xA9, 0xAA, 0xB2, 0xB3, 0xB4, 0xB5, 0xB6,
    0xB7, 0xB8, 0xB9, 0xBA, 0xC2, 0xC3, 0xC4, 0xC5, 0xC6, 0xC7, 0xC8, 0xC9,
    0xCA, 0xD2, 0xD3, 0xD4, 0xD5, 0xD6, 0xD7, 0xD8, 0xD9, 0xDA, 0xE1, 0xE2,
    0xE3, 0xE4, 0xE5, 0xE6, 0xE7, 0xE8, 0xE9, 0xEA, 0xF1, 0xF2, 0xF3, 0xF4,
    0xF5, 0xF6, 0xF7, 0xF8, 0xF9, 0xFA,
)

AC_CHROMA_BITS = (0, 2, 1, 2, 4, 4, 3, 4, 7, 5, 4, 4, 0, 1, 2, 119)
AC_CHROMA_VALUES = (
    0x00, 0x01, 0x02, 0x03, 0x11, 0x04, 0x05, 0x21, 0x31, 0x06, 0x12, 0x41,
    0x51, 0x07, 0x61, 0x71, 0x13, 0x22, 0x32, 0x81, 0x08, 0x14, 0x42, 0x91,
    0xA1, 0xB1, 0xC1, 0x09, 0x23, 0x33, 0x52, 0xF0, 0x15, 0x62, 0x72, 0xD1,
    0x0A, 0x16, 0x24, 0x34, 0xE1, 0x25, 0xF1, 0x17, 0x18, 0x19, 0x1A, 0x26,
    0x27, 0x28, 0x29, 0x2A, 0x35, 0x36, 0x37, 0x38, 0x39, 0x3A, 0x43, 0x44,
    0x45, 0x46, 0x47, 0x48, 0x49, 0x4A, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58,
    0x59, 0x5A, 0x63, 0x64, 0x65, 0x66, 0x67, 0x68, 0x69, 0x6A, 0x73, 0x74,
    0x75, 0x76, 0x77, 0x78, 0x79, 0x7A, 0x82, 0x83, 0x84, 0x85, 0x86, 0x87,
    0x88, 0x89, 0x8A, 0x92, 0x93, 0x94, 0x95, 0x96, 0x97, 0x98, 0x99, 0x9A,
    0xA2, 0xA3, 0xA4, 0xA5, 0xA6, 0xA7, 0xA8, 0xA9, 0xAA, 0xB2, 0xB3, 0xB4,
    0xB5, 0xB6, 0xB7, 0xB8, 0xB9, 0xBA, 0xC2, 0xC3, 0xC4, 0xC5, 0xC6, 0xC7,
    0xC8, 0xC9, 0xCA, 0xD2, 0xD3, 0xD4, 0xD5, 0xD6, 0xD7, 0xD8, 0xD9, 0xDA,
    0xE2, 0xE3, 0xE4, 0xE5, 0xE6, 0xE7, 0xE8, 0xE9, 0xEA, 0xF2, 0xF3, 0xF4,
    0xF5, 0xF6, 0xF7, 0xF8, 0xF9, 0xFA,
)

COS_SCALE = 1 << 14
COSINE = tuple(
    tuple(
        round(
            (1.0 / math.sqrt(2.0) if frequency == 0 else 1.0)
            * math.cos(((2 * sample + 1) * frequency * math.pi) / 16.0)
            * COS_SCALE
        )
        for sample in range(8)
    )
    for frequency in range(8)
)


def _round_div(value: int, divisor: int) -> int:
    if divisor <= 0:
        raise ValueError("divisor must be positive")
    if value < 0:
        return -((-value + (divisor // 2)) // divisor)
    return (value + (divisor // 2)) // divisor


def fdct(block: list[int] | tuple[int, ...]) -> tuple[int, ...]:
    """Return natural-order coefficients for one 8x8 level-shifted block."""
    if len(block) != 64:
        raise ValueError("an 8x8 block must contain 64 samples")
    intermediate = [0] * 64
    result = [0] * 64
    divisor = 2 * COS_SCALE
    for y_pos in range(8):
        for u in range(8):
            total = sum(block[(y_pos * 8) + x_pos] * COSINE[u][x_pos] for x_pos in range(8))
            intermediate[(y_pos * 8) + u] = _round_div(total, divisor)
    for v in range(8):
        for u in range(8):
            total = sum(intermediate[(y_pos * 8) + u] * COSINE[v][y_pos] for y_pos in range(8))
            result[(v * 8) + u] = _round_div(total, divisor)
    return tuple(result)


def idct(coefficients: list[int] | tuple[int, ...]) -> tuple[int, ...]:
    """Return natural-order level-shifted samples for one 8x8 coefficient block."""
    if len(coefficients) != 64:
        raise ValueError("an 8x8 block must contain 64 coefficients")
    intermediate = [0] * 64
    result = [0] * 64
    divisor = 2 * COS_SCALE
    for v in range(8):
        for x_pos in range(8):
            total = sum(coefficients[(v * 8) + u] * COSINE[u][x_pos] for u in range(8))
            intermediate[(v * 8) + x_pos] = _round_div(total, divisor)
    for y in range(8):
        for x in range(8):
            total = sum(intermediate[(v * 8) + x] * COSINE[v][y] for v in range(8))
            result[(y * 8) + x] = _round_div(total, divisor)
    return tuple(result)


def scaled_quant_table(base: tuple[int, ...], quality: int) -> tuple[int, ...]:
    if not 1 <= quality <= 100:
        raise ValueError("JPEG quality must be in the range 1..100")
    scale = 5000 // quality if quality < 50 else 200 - (quality * 2)
    return tuple(max(1, min(255, ((value * scale) + 50) // 100)) for value in base)


def _huffman_codes(bits: tuple[int, ...], values: tuple[int, ...]) -> dict[int, tuple[int, int]]:
    if len(bits) != 16 or sum(bits) != len(values):
        raise ValueError("invalid canonical Huffman table")
    result: dict[int, tuple[int, int]] = {}
    code = 0
    index = 0
    for length, count in enumerate(bits, start=1):
        for _ in range(count):
            result[values[index]] = (code, length)
            code += 1
            index += 1
        code <<= 1
    return result


def _huffman_decode_table(
    bits: tuple[int, ...], values: tuple[int, ...]
) -> dict[tuple[int, int], int]:
    return {(code, length): symbol for symbol, (code, length) in _huffman_codes(bits, values).items()}


def _category(value: int) -> int:
    return abs(value).bit_length()


def _amplitude(value: int, size: int) -> int:
    if size == 0:
        return 0
    return value if value >= 0 else value + ((1 << size) - 1)


def _extend(value: int, size: int) -> int:
    if size == 0:
        return 0
    threshold = 1 << (size - 1)
    return value if value >= threshold else value - ((1 << size) - 1)


class _BitWriter:
    def __init__(self) -> None:
        self.data = bytearray()
        self.accumulator = 0
        self.count = 0

    def emit(self, value: int, count: int) -> None:
        if count < 0 or value < 0 or value >= (1 << count):
            raise ValueError("invalid bit emission")
        self.accumulator = (self.accumulator << count) | value
        self.count += count
        while self.count >= 8:
            shift = self.count - 8
            byte = (self.accumulator >> shift) & 0xFF
            self.count -= 8
            self.accumulator &= (1 << self.count) - 1 if self.count != 0 else 0
            self.data.append(byte)
            if byte == 0xFF:
                self.data.append(0)

    def align(self) -> None:
        if self.count != 0:
            self.emit((1 << (8 - self.count)) - 1, 8 - self.count)

    def marker(self, value: int) -> None:
        self.align()
        self.data.extend((0xFF, value))


class _BitReader:
    def __init__(self, data: bytes, offset: int) -> None:
        self.data = data
        self.offset = offset
        self.accumulator = 0
        self.count = 0

    def _byte(self) -> int:
        if self.offset >= len(self.data):
            raise JpegModelError("truncated entropy-coded segment")
        value = self.data[self.offset]
        self.offset += 1
        if value == 0xFF:
            if self.offset >= len(self.data):
                raise JpegModelError("truncated marker in entropy-coded segment")
            following = self.data[self.offset]
            if following != 0:
                raise JpegModelError(f"unexpected marker 0xff{following:02x} in entropy data")
            self.offset += 1
        return value

    def read(self, count: int) -> int:
        while self.count < count:
            self.accumulator = (self.accumulator << 8) | self._byte()
            self.count += 8
        shift = self.count - count
        result = (self.accumulator >> shift) & ((1 << count) - 1)
        self.count -= count
        self.accumulator &= (1 << self.count) - 1 if self.count != 0 else 0
        return result

    def align(self) -> None:
        self.accumulator = 0
        self.count = 0

    def restart(self, expected: int) -> None:
        self.align()
        if self.offset + 2 > len(self.data) or self.data[self.offset] != 0xFF:
            raise JpegModelError("missing restart marker")
        marker = self.data[self.offset + 1]
        if marker != 0xD0 + expected:
            raise JpegModelError("restart marker sequence mismatch")
        self.offset += 2


def _emit_huffman(writer: _BitWriter, table: dict[int, tuple[int, int]], symbol: int) -> None:
    try:
        code, length = table[symbol]
    except KeyError as error:
        raise JpegModelError(f"symbol 0x{symbol:02x} is absent from Huffman table") from error
    writer.emit(code, length)


def _decode_huffman(reader: _BitReader, table: dict[tuple[int, int], int]) -> int:
    code = 0
    for length in range(1, 17):
        code = (code << 1) | reader.read(1)
        symbol = table.get((code, length))
        if symbol is not None:
            return symbol
    raise JpegModelError("invalid Huffman code")


def _marker(marker: int, payload: bytes = b"") -> bytes:
    if payload:
        length = len(payload) + 2
        if length > 0xFFFF:
            raise ValueError("JPEG marker payload is too large")
        return bytes((0xFF, marker, length >> 8, length & 0xFF)) + payload
    return bytes((0xFF, marker))


def _rgb_planes(rgb: bytes, width: int, height: int) -> tuple[list[int], list[int], list[int]]:
    if width <= 0 or height <= 0 or len(rgb) != width * height * 3:
        raise ValueError("RGB888 buffer size does not match the image dimensions")
    y_plane: list[int] = []
    cb_plane: list[int] = []
    cr_plane: list[int] = []
    for index in range(0, len(rgb), 3):
        red, green, blue = rgb[index : index + 3]
        y_plane.append(max(0, min(255, (77 * red + 150 * green + 29 * blue + 128) >> 8)))
        cb_plane.append(
            max(0, min(255, ((-43 * red - 85 * green + 128 * blue + 128) >> 8) + 128))
        )
        cr_plane.append(
            max(0, min(255, ((128 * red - 107 * green - 21 * blue + 128) >> 8) + 128))
        )
    return y_plane, cb_plane, cr_plane


def _downsample(
    source: list[int], width: int, height: int, horizontal: int, vertical: int
) -> tuple[list[int], int, int]:
    output_width = (width + horizontal - 1) // horizontal
    output_height = (height + vertical - 1) // vertical
    output: list[int] = []
    for y_pos in range(output_height):
        for x_pos in range(output_width):
            total = 0
            count = 0
            for y_offset in range(vertical):
                source_y = min(height - 1, (y_pos * vertical) + y_offset)
                for x_offset in range(horizontal):
                    source_x = min(width - 1, (x_pos * horizontal) + x_offset)
                    total += source[(source_y * width) + source_x]
                    count += 1
            output.append((total + (count // 2)) // count)
    return output, output_width, output_height


def _extract_block(plane: list[int], width: int, height: int, x_pos: int, y_pos: int) -> list[int]:
    result: list[int] = []
    for y_offset in range(8):
        source_y = min(height - 1, y_pos + y_offset)
        for x_offset in range(8):
            source_x = min(width - 1, x_pos + x_offset)
            result.append(plane[(source_y * width) + source_x] - 128)
    return result


def _encode_block(
    writer: _BitWriter,
    block: list[int],
    quant: tuple[int, ...],
    previous_dc: int,
    dc_table: dict[int, tuple[int, int]],
    ac_table: dict[int, tuple[int, int]],
) -> int:
    transformed = fdct(block)
    quantized = tuple(_round_div(value, quant[index]) for index, value in enumerate(transformed))
    dc_value = quantized[0]
    difference = dc_value - previous_dc
    size = _category(difference)
    if size > 11:
        raise JpegModelError("baseline DC category exceeds 11 bits")
    _emit_huffman(writer, dc_table, size)
    writer.emit(_amplitude(difference, size), size)

    run = 0
    for zigzag_index in range(1, 64):
        coefficient = quantized[ZIGZAG[zigzag_index]]
        if coefficient == 0:
            run += 1
            continue
        while run >= 16:
            _emit_huffman(writer, ac_table, 0xF0)
            run -= 16
        size = _category(coefficient)
        if size > 10:
            raise JpegModelError("baseline AC category exceeds 10 bits")
        _emit_huffman(writer, ac_table, (run << 4) | size)
        writer.emit(_amplitude(coefficient, size), size)
        run = 0
    if run != 0:
        _emit_huffman(writer, ac_table, 0)
    return dc_value


def encode_rgb(
    rgb: bytes,
    width: int,
    height: int,
    *,
    quality: int = 75,
    sampling: Sampling = Sampling.YUV420,
    restart_interval: int = 0,
) -> bytes:
    """Encode RGB888 pixels into a deterministic baseline JPEG stream."""
    if width > 0xFFFF or height > 0xFFFF:
        raise ValueError("JPEG dimensions exceed the baseline header fields")
    if restart_interval < 0 or restart_interval > 0xFFFF:
        raise ValueError("restart interval must fit in 16 bits")
    y_full, cb_full, cr_full = _rgb_planes(rgb, width, height)
    if sampling == Sampling.GRAY:
        component_spec = ((1, 1, 0, 0),)
        components = ((y_full, width, height),)
        max_h = max_v = 1
    else:
        if sampling == Sampling.YUV444:
            max_h, max_v = 1, 1
        elif sampling == Sampling.YUV422:
            max_h, max_v = 2, 1
        elif sampling == Sampling.YUV420:
            max_h, max_v = 2, 2
        else:
            raise ValueError("unsupported sampling mode")
        cb_plane, cb_width, cb_height = _downsample(cb_full, width, height, max_h, max_v)
        cr_plane, cr_width, cr_height = _downsample(cr_full, width, height, max_h, max_v)
        component_spec = ((max_h, max_v, 0, 0), (1, 1, 1, 1), (1, 1, 1, 1))
        components = (
            (y_full, width, height),
            (cb_plane, cb_width, cb_height),
            (cr_plane, cr_width, cr_height),
        )

    quant_tables = (
        scaled_quant_table(LUMA_QUANT, quality),
        scaled_quant_table(CHROMA_QUANT, quality),
    )
    dc_tables = (
        _huffman_codes(DC_LUMA_BITS, DC_VALUES),
        _huffman_codes(DC_CHROMA_BITS, DC_VALUES),
    )
    ac_tables = (
        _huffman_codes(AC_LUMA_BITS, AC_LUMA_VALUES),
        _huffman_codes(AC_CHROMA_BITS, AC_CHROMA_VALUES),
    )

    output = bytearray(_marker(0xD8))
    output.extend(_marker(0xE0, b"JFIF\x00\x01\x02\x00\x00\x01\x00\x01\x00\x00"))
    dqt = bytearray()
    for table_id, table in enumerate(quant_tables):
        if table_id > 0 and sampling == Sampling.GRAY:
            break
        dqt.append(table_id)
        dqt.extend(table[index] for index in ZIGZAG)
    output.extend(_marker(0xDB, bytes(dqt)))

    sof = bytearray((8, height >> 8, height & 0xFF, width >> 8, width & 0xFF, len(components)))
    for component_id, (h_factor, v_factor, quant_id, _) in enumerate(component_spec, start=1):
        sof.extend((component_id, (h_factor << 4) | v_factor, quant_id))
    output.extend(_marker(0xC0, bytes(sof)))

    dht = bytearray()
    table_count = 1 if sampling == Sampling.GRAY else 2
    for table_id in range(table_count):
        dc_bits = DC_LUMA_BITS if table_id == 0 else DC_CHROMA_BITS
        dht.extend((table_id, *dc_bits, *DC_VALUES))
        ac_bits = AC_LUMA_BITS if table_id == 0 else AC_CHROMA_BITS
        ac_values = AC_LUMA_VALUES if table_id == 0 else AC_CHROMA_VALUES
        dht.extend((0x10 | table_id, *ac_bits, *ac_values))
    output.extend(_marker(0xC4, bytes(dht)))
    if restart_interval != 0:
        output.extend(_marker(0xDD, bytes((restart_interval >> 8, restart_interval & 0xFF))))

    sos = bytearray((len(components),))
    for component_id, (_, _, _, entropy_id) in enumerate(component_spec, start=1):
        sos.extend((component_id, (entropy_id << 4) | entropy_id))
    sos.extend((0, 63, 0))
    output.extend(_marker(0xDA, bytes(sos)))

    writer = _BitWriter()
    dc_predictors = [0] * len(components)
    mcu_width = max_h * 8
    mcu_height = max_v * 8
    mcu_columns = (width + mcu_width - 1) // mcu_width
    mcu_rows = (height + mcu_height - 1) // mcu_height
    restart_index = 0
    mcu_index = 0
    for mcu_y in range(mcu_rows):
        for mcu_x in range(mcu_columns):
            for component_index, ((h_factor, v_factor, quant_id, entropy_id), plane_info) in enumerate(
                zip(component_spec, components, strict=True)
            ):
                plane, plane_width, plane_height = plane_info
                component_x = mcu_x * h_factor * 8
                component_y = mcu_y * v_factor * 8
                for block_y in range(v_factor):
                    for block_x in range(h_factor):
                        block = _extract_block(
                            plane,
                            plane_width,
                            plane_height,
                            component_x + (block_x * 8),
                            component_y + (block_y * 8),
                        )
                        dc_predictors[component_index] = _encode_block(
                            writer,
                            block,
                            quant_tables[quant_id],
                            dc_predictors[component_index],
                            dc_tables[entropy_id],
                            ac_tables[entropy_id],
                        )
            mcu_index += 1
            if restart_interval != 0 and mcu_index != (mcu_columns * mcu_rows):
                if (mcu_index % restart_interval) == 0:
                    writer.marker(0xD0 + restart_index)
                    restart_index = (restart_index + 1) & 7
                    dc_predictors = [0] * len(components)
    writer.align()
    output.extend(writer.data)
    output.extend(_marker(0xD9))
    return bytes(output)


@dataclass
class _Component:
    component_id: int
    h_factor: int
    v_factor: int
    quant_id: int
    dc_id: int = 0
    ac_id: int = 0
    previous_dc: int = 0
    plane: list[int] | None = None
    plane_width: int = 0
    plane_height: int = 0


@dataclass
class _ParsedHeader:
    width: int
    height: int
    components: list[_Component]
    quant_tables: dict[int, tuple[int, ...]]
    dc_tables: dict[int, dict[tuple[int, int], int]]
    ac_tables: dict[int, dict[tuple[int, int], int]]
    restart_interval: int
    entropy_offset: int


def _segment(data: bytes, offset: int) -> tuple[bytes, int]:
    if offset + 2 > len(data):
        raise JpegModelError("truncated JPEG marker length")
    length = (data[offset] << 8) | data[offset + 1]
    if length < 2 or offset + length > len(data):
        raise JpegModelError("invalid JPEG marker length")
    return data[offset + 2 : offset + length], offset + length


def _parse_dqt(payload: bytes, tables: dict[int, tuple[int, ...]]) -> None:
    offset = 0
    while offset < len(payload):
        control = payload[offset]
        offset += 1
        precision = control >> 4
        table_id = control & 0x0F
        if precision != 0 or table_id > 3:
            raise JpegModelError("only 8-bit quantization tables 0..3 are supported")
        if offset + 64 > len(payload):
            raise JpegModelError("truncated quantization table")
        natural = [0] * 64
        for zigzag_index, natural_index in enumerate(ZIGZAG):
            value = payload[offset + zigzag_index]
            if value == 0:
                raise JpegModelError("zero quantization value")
            natural[natural_index] = value
        tables[table_id] = tuple(natural)
        offset += 64


def _parse_dht(
    payload: bytes,
    dc_tables: dict[int, dict[tuple[int, int], int]],
    ac_tables: dict[int, dict[tuple[int, int], int]],
) -> None:
    offset = 0
    while offset < len(payload):
        control = payload[offset]
        offset += 1
        table_class = control >> 4
        table_id = control & 0x0F
        if table_class > 1 or table_id > 3 or offset + 16 > len(payload):
            raise JpegModelError("invalid Huffman table selector")
        bits = tuple(payload[offset : offset + 16])
        offset += 16
        value_count = sum(bits)
        if value_count == 0 or value_count > 256 or offset + value_count > len(payload):
            raise JpegModelError("invalid Huffman table length")
        values = tuple(payload[offset : offset + value_count])
        offset += value_count
        try:
            table = _huffman_decode_table(bits, values)
        except ValueError as error:
            raise JpegModelError(str(error)) from error
        if table_class == 0:
            dc_tables[table_id] = table
        else:
            ac_tables[table_id] = table


def _parse_sof0(payload: bytes) -> tuple[int, int, list[_Component]]:
    if len(payload) < 6 or payload[0] != 8:
        raise JpegModelError("only 8-bit baseline frames are supported")
    height = (payload[1] << 8) | payload[2]
    width = (payload[3] << 8) | payload[4]
    component_count = payload[5]
    if width == 0 or height == 0 or component_count not in (1, 3):
        raise JpegModelError("unsupported frame dimensions or component count")
    if len(payload) != 6 + (3 * component_count):
        raise JpegModelError("invalid SOF0 component list")
    components: list[_Component] = []
    seen: set[int] = set()
    for index in range(component_count):
        base = 6 + (index * 3)
        component_id = payload[base]
        factors = payload[base + 1]
        h_factor = factors >> 4
        v_factor = factors & 0x0F
        quant_id = payload[base + 2]
        if (
            component_id in seen
            or h_factor not in (1, 2)
            or v_factor not in (1, 2)
            or quant_id > 3
        ):
            raise JpegModelError("unsupported SOF0 component parameters")
        seen.add(component_id)
        components.append(_Component(component_id, h_factor, v_factor, quant_id))
    max_h = max(component.h_factor for component in components)
    max_v = max(component.v_factor for component in components)
    if component_count == 1:
        if max_h != 1 or max_v != 1:
            raise JpegModelError("grayscale sampling factors must be 1x1")
    elif (max_h, max_v) not in ((1, 1), (2, 1), (2, 2)):
        raise JpegModelError("unsupported chroma sampling factors")
    if component_count == 3 and any(
        component.h_factor != 1 or component.v_factor != 1 for component in components[1:]
    ):
        raise JpegModelError("chroma sampling factors must be 1x1")
    return width, height, components


def _parse_sos(payload: bytes, components: list[_Component]) -> None:
    if not payload:
        raise JpegModelError("empty SOS marker")
    count = payload[0]
    if count != len(components) or len(payload) != 1 + (2 * count) + 3:
        raise JpegModelError("only one interleaved baseline scan is supported")
    by_id = {component.component_id: component for component in components}
    seen: set[int] = set()
    for index in range(count):
        component_id = payload[1 + (index * 2)]
        selectors = payload[2 + (index * 2)]
        if component_id not in by_id or component_id in seen:
            raise JpegModelError("invalid SOS component selector")
        seen.add(component_id)
        component = by_id[component_id]
        component.dc_id = selectors >> 4
        component.ac_id = selectors & 0x0F
        if component.dc_id > 3 or component.ac_id > 3:
            raise JpegModelError("invalid SOS Huffman selector")
    tail = payload[-3:]
    if tail != bytes((0, 63, 0)):
        raise JpegModelError("progressive or non-sequential scan is unsupported")


def _parse_header(data: bytes) -> _ParsedHeader:
    if len(data) < 4 or data[:2] != bytes((0xFF, 0xD8)):
        raise JpegModelError("missing SOI marker")
    offset = 2
    width = height = 0
    components: list[_Component] = []
    quant_tables: dict[int, tuple[int, ...]] = {}
    dc_tables: dict[int, dict[tuple[int, int], int]] = {}
    ac_tables: dict[int, dict[tuple[int, int], int]] = {}
    restart_interval = 0
    while offset < len(data):
        if data[offset] != 0xFF:
            raise JpegModelError("expected JPEG marker prefix")
        while offset < len(data) and data[offset] == 0xFF:
            offset += 1
        if offset >= len(data):
            raise JpegModelError("truncated JPEG marker")
        marker = data[offset]
        offset += 1
        if marker in (0xD8, 0xD9) or 0xD0 <= marker <= 0xD7:
            raise JpegModelError(f"unexpected standalone marker 0xff{marker:02x}")
        payload, offset = _segment(data, offset)
        if marker == 0xDB:
            _parse_dqt(payload, quant_tables)
        elif marker == 0xC4:
            _parse_dht(payload, dc_tables, ac_tables)
        elif marker == 0xC0:
            if components:
                raise JpegModelError("multiple SOF0 markers")
            width, height, components = _parse_sof0(payload)
        elif marker == 0xDD:
            if len(payload) != 2:
                raise JpegModelError("invalid DRI marker")
            restart_interval = (payload[0] << 8) | payload[1]
        elif marker == 0xDA:
            if not components:
                raise JpegModelError("SOS precedes SOF0")
            _parse_sos(payload, components)
            for component in components:
                if component.quant_id not in quant_tables:
                    raise JpegModelError("missing quantization table")
                if component.dc_id not in dc_tables or component.ac_id not in ac_tables:
                    raise JpegModelError("missing Huffman table")
            return _ParsedHeader(
                width,
                height,
                components,
                quant_tables,
                dc_tables,
                ac_tables,
                restart_interval,
                offset,
            )
        elif marker in (0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7, 0xC9, 0xCA, 0xCB):
            raise JpegModelError("unsupported JPEG frame process")
        elif marker == 0xDC:
            raise JpegModelError("DNL is unsupported")
        elif not (0xE0 <= marker <= 0xEF or marker == 0xFE):
            raise JpegModelError(f"unsupported marker 0xff{marker:02x}")
    raise JpegModelError("missing SOS marker")


def _decode_block(
    reader: _BitReader,
    quant: tuple[int, ...],
    previous_dc: int,
    dc_table: dict[tuple[int, int], int],
    ac_table: dict[tuple[int, int], int],
) -> tuple[tuple[int, ...], int]:
    dc_size = _decode_huffman(reader, dc_table)
    if dc_size > 11:
        raise JpegModelError("baseline DC category exceeds 11 bits")
    dc_value = previous_dc + _extend(reader.read(dc_size), dc_size)
    quantized = [0] * 64
    quantized[0] = dc_value
    zigzag_index = 1
    while zigzag_index < 64:
        symbol = _decode_huffman(reader, ac_table)
        run = symbol >> 4
        size = symbol & 0x0F
        if size == 0:
            if run == 0:
                break
            if run != 15:
                raise JpegModelError("invalid zero-size AC symbol")
            zigzag_index += 16
            continue
        if size > 10:
            raise JpegModelError("baseline AC category exceeds 10 bits")
        zigzag_index += run
        if zigzag_index >= 64:
            raise JpegModelError("AC run exceeds block boundary")
        quantized[ZIGZAG[zigzag_index]] = _extend(reader.read(size), size)
        zigzag_index += 1
    coefficients = tuple(value * quant[index] for index, value in enumerate(quantized))
    samples = tuple(max(0, min(255, value + 128)) for value in idct(coefficients))
    return samples, dc_value


def _store_block(component: _Component, samples: tuple[int, ...], x_pos: int, y_pos: int) -> None:
    assert component.plane is not None
    for y_offset in range(8):
        destination = (y_pos + y_offset) * component.plane_width + x_pos
        source = y_offset * 8
        component.plane[destination : destination + 8] = samples[source : source + 8]


def decode_rgb(data: bytes, *, max_dimension: int = 2048) -> DecodedImage:
    """Decode the supported baseline profile into tightly packed RGB888 pixels."""
    header = _parse_header(data)
    if header.width > max_dimension or header.height > max_dimension:
        raise JpegModelError("image exceeds the configured dimension limit")
    max_h = max(component.h_factor for component in header.components)
    max_v = max(component.v_factor for component in header.components)
    mcu_columns = (header.width + (max_h * 8) - 1) // (max_h * 8)
    mcu_rows = (header.height + (max_v * 8) - 1) // (max_v * 8)
    for component in header.components:
        component.plane_width = mcu_columns * component.h_factor * 8
        component.plane_height = mcu_rows * component.v_factor * 8
        component.plane = [0] * (component.plane_width * component.plane_height)

    reader = _BitReader(data, header.entropy_offset)
    restart_index = 0
    mcu_index = 0
    total_mcus = mcu_columns * mcu_rows
    for mcu_y in range(mcu_rows):
        for mcu_x in range(mcu_columns):
            for component in header.components:
                for block_y in range(component.v_factor):
                    for block_x in range(component.h_factor):
                        samples, component.previous_dc = _decode_block(
                            reader,
                            header.quant_tables[component.quant_id],
                            component.previous_dc,
                            header.dc_tables[component.dc_id],
                            header.ac_tables[component.ac_id],
                        )
                        _store_block(
                            component,
                            samples,
                            (mcu_x * component.h_factor * 8) + (block_x * 8),
                            (mcu_y * component.v_factor * 8) + (block_y * 8),
                        )
            mcu_index += 1
            if (
                header.restart_interval != 0
                and mcu_index != total_mcus
                and (mcu_index % header.restart_interval) == 0
            ):
                reader.restart(restart_index)
                restart_index = (restart_index + 1) & 7
                for component in header.components:
                    component.previous_dc = 0

    reader.align()
    if reader.offset + 2 > len(data) or data[reader.offset : reader.offset + 2] != bytes(
        (0xFF, 0xD9)
    ):
        raise JpegModelError("missing EOI marker")

    if len(header.components) == 1:
        sampling = Sampling.GRAY
    elif (max_h, max_v) == (1, 1):
        sampling = Sampling.YUV444
    elif (max_h, max_v) == (2, 1):
        sampling = Sampling.YUV422
    else:
        sampling = Sampling.YUV420

    rgb = bytearray()
    y_component = header.components[0]
    assert y_component.plane is not None
    cb_component = header.components[1] if len(header.components) == 3 else None
    cr_component = header.components[2] if len(header.components) == 3 else None
    for y_pos in range(header.height):
        for x_pos in range(header.width):
            y_value = y_component.plane[(y_pos * y_component.plane_width) + x_pos]
            if cb_component is None or cr_component is None:
                rgb.extend((y_value, y_value, y_value))
                continue
            assert cb_component.plane is not None and cr_component.plane is not None
            chroma_x = x_pos * cb_component.h_factor // max_h
            chroma_y = y_pos * cb_component.v_factor // max_v
            cb_value = cb_component.plane[(chroma_y * cb_component.plane_width) + chroma_x] - 128
            cr_value = cr_component.plane[(chroma_y * cr_component.plane_width) + chroma_x] - 128
            red = y_value + ((359 * cr_value + 128) >> 8)
            green = y_value - ((88 * cb_value + 183 * cr_value + 128) >> 8)
            blue = y_value + ((454 * cb_value + 128) >> 8)
            rgb.extend(
                (
                    max(0, min(255, red)),
                    max(0, min(255, green)),
                    max(0, min(255, blue)),
                )
            )
    return DecodedImage(header.width, header.height, sampling, bytes(rgb))
