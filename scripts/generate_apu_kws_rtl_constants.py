#!/usr/bin/env python3
"""Generate the frozen APU-P7 frontend ROM and APUM validation constants."""

from __future__ import annotations

import argparse
import struct
from decimal import Decimal, ROUND_HALF_EVEN, getcontext
from pathlib import Path

getcontext().prec = 100

ZERO = Decimal(0)
ONE = Decimal(1)
TWO = Decimal(2)


def _atan(value: Decimal) -> Decimal:
    square = value * value
    term = value
    result = term
    denominator = 3
    negative = True
    while abs(term) > Decimal(1).scaleb(-105):
        term *= square
        addend = term / Decimal(denominator)
        result = result - addend if negative else result + addend
        denominator += 2
        negative = not negative
    return result


PI = Decimal(16) * _atan(ONE / Decimal(5)) - Decimal(4) * _atan(ONE / Decimal(239))


def _sin(value: Decimal) -> Decimal:
    value %= TWO * PI
    if value > PI:
        value -= TWO * PI
    term = value
    result = value
    index = 1
    while abs(term) > Decimal(1).scaleb(-105):
        term *= -(value * value) / Decimal((2 * index) * (2 * index + 1))
        result += term
        index += 1
    return result


def _cos(value: Decimal) -> Decimal:
    return _sin(value + PI / TWO)


def _rne(value: Decimal) -> int:
    return int(value.to_integral_value(rounding=ROUND_HALF_EVEN))


def _hann() -> list[int]:
    return [
        _rne((ONE - _cos(TWO * PI * Decimal(index) / Decimal(480))) * Decimal(1 << 29))
        for index in range(480)
    ]


def _twiddle() -> tuple[list[int], list[int]]:
    real = []
    imag = []
    for index in range(256):
        angle = TWO * PI * Decimal(index) / Decimal(512)
        real.append(_rne(_cos(angle) * Decimal(1 << 30)))
        imag.append(_rne(-_sin(angle) * Decimal(1 << 30)))
    return real, imag


def _mel_weights() -> list[int]:
    mel_low = Decimal(1127) * (ONE + Decimal(20) / Decimal(700)).ln()
    mel_high = Decimal(1127) * (ONE + Decimal(4000) / Decimal(700)).ln()
    edges = []
    for index in range(42):
        mel = mel_low + (mel_high - mel_low) * Decimal(index) / Decimal(41)
        edges.append(Decimal(700) * ((mel / Decimal(1127)).exp() - ONE))
    result = []
    for band in range(40):
        low, center, high = edges[band : band + 3]
        for bin_index in range(257):
            frequency = Decimal(16000 * bin_index) / Decimal(512)
            if bin_index == 0 or frequency <= low or frequency >= high:
                weight = ZERO
            elif frequency <= center:
                weight = (frequency - low) / (center - low)
            else:
                weight = (high - frequency) / (high - center)
            result.append(_rne(max(ZERO, min(ONE, weight)) * Decimal(1 << 30)))
    return result


def _dct() -> list[int]:
    scale = (TWO / Decimal(40)).sqrt()
    return [
        _rne(
            scale
            * _cos(PI * (Decimal(band) + Decimal("0.5")) * Decimal(coefficient) / Decimal(40))
            * Decimal(1 << 30)
        )
        for coefficient in range(10)
        for band in range(40)
    ]


def _log_rom() -> list[int]:
    return [
        _rne((ONE + Decimal(index) / Decimal(1024)).ln() * Decimal(1 << 24))
        for index in range(1025)
    ]


def _fir(decimation: int) -> list[int]:
    coefficients = []
    cutoff = ONE / Decimal(decimation)
    for tap in range(63):
        offset = Decimal(tap - 31)
        window = (ONE - _cos(TWO * PI * Decimal(tap) / Decimal(62))) / TWO
        sinc = ONE if offset == ZERO else _sin(PI * cutoff * offset) / (PI * cutoff * offset)
        coefficients.append(cutoff * sinc * window)
    total = sum(coefficients)
    quantized = [_rne(value / total * Decimal(1 << 30)) for value in coefficients]
    quantized[31] += (1 << 30) - sum(quantized)
    return quantized


def _trunc_div(numerator: int, denominator: int) -> int:
    return numerator // denominator if numerator >= 0 else -((-numerator) // denominator)


def _srdhm(a: int, b: int) -> int:
    if a == -(1 << 31) and b == -(1 << 31):
        return (1 << 31) - 1
    product = a * b
    nudge = (1 << 30) if product >= 0 else 1 - (1 << 30)
    return _trunc_div(product + nudge, 1 << 31)


def _rdbpot(value: int, exponent: int) -> int:
    if exponent == 0:
        return value
    mask = (1 << exponent) - 1
    remainder = value & mask
    threshold = (mask >> 1) + (1 if value < 0 else 0)
    return (value >> exponent) + (1 if remainder > threshold else 0)


def _sat_left(value: int, exponent: int) -> int:
    result = value << exponent
    return max(-(1 << 31), min((1 << 31) - 1, result))


def _exp_interval(raw: int) -> int:
    x = raw + (1 << 28)
    x2 = _srdhm(x, x)
    x3 = _srdhm(x2, x)
    x4 = _srdhm(x2, x2)
    x4_over_4 = _rdbpot(x4, 2)
    series = _rdbpot(_srdhm(x4_over_4 + x3, 715827883) + x2, 1)
    return 1895147668 + _srdhm(1895147668, x + series)


def _exp_negative_q5_26(raw: int) -> int:
    quarter = 1 << 24
    mask = quarter - 1
    reduced = (raw & mask) - quarter
    result = _exp_interval(_sat_left(reduced, 5))
    remainder = reduced - raw
    for exponent, multiplier in (
        (-2, 1672461947),
        (-1, 1302514674),
        (0, 790015084),
        (1, 290630308),
        (2, 39332535),
        (3, 720401),
        (4, 242),
    ):
        bit = 26 + exponent
        if (remainder & (1 << bit)) != 0:
            result = _srdhm(result, multiplier)
    return (1 << 31) - 1 if raw == 0 else result


def _softmax_exp() -> list[int]:
    values = []
    for difference in range(125):
        scaled = _srdhm((-difference) << 24, 1242899200)
        values.append(_exp_negative_q5_26(scaled))
    return values


def _emit_function(name: str, width: int, values: list[int], *, signed: bool = True) -> str:
    index_width = max(1, (len(values) - 1).bit_length())
    qualifier = " signed" if signed else ""
    lines = [
        f"function automatic logic{qualifier} [{width - 1}:0] {name}(",
        f"    input logic [{index_width - 1}:0] index_i);",
        "  case (index_i)",
    ]
    for index, value in enumerate(values):
        if signed:
            literal = f"{width}'sd{value}" if value >= 0 else f"-{width}'sd{-value}"
        else:
            literal = f"{width}'d{value}"
        lines.append(f"    {index_width}'d{index}: {name} = {literal};")
    lines.extend((f"    default: {name} = '0;", "  endcase", "endfunction", ""))
    return "\n".join(lines)


def _fixed_apum_words(image: bytes) -> tuple[list[int], list[int]]:
    offsets = list(range(0, 0x500, 4))
    for operator in range(12):
        record = 0x40 + operator * 64
        for field in (0x10, 0x14):
            offset = struct.unpack_from("<I", image, record + field)[0]
            channels = struct.unpack_from("<I", image, record + 0x1C)[0]
            if offset != 0:
                offsets.extend(range(offset, offset + channels * 4, 4))
    offsets = sorted(set(offsets))
    return offsets, [struct.unpack_from("<I", image, offset)[0] for offset in offsets]


def _emit_profile_words(offsets: list[int], values: list[int]) -> str:
    ranges: list[tuple[int, int, int]] = []
    range_start = offsets[0]
    range_index = 0
    previous = offsets[0]
    for index, offset in enumerate(offsets[1:], start=1):
        if offset != previous + 4:
            ranges.append((range_start, previous, range_index))
            range_start = offset
            range_index = index
        previous = offset
    ranges.append((range_start, previous, range_index))

    lines = [
        "function automatic logic [31:0] apu_kws_apum_fixed_word(",
        "    input logic [10:0] index_i);",
        "  case (index_i)",
    ]
    for index, value in enumerate(values):
        lines.append(f"    11'd{index}: apu_kws_apum_fixed_word = 32'h{value:08x};")
    lines.extend(
        (
            "    default: apu_kws_apum_fixed_word = 32'd0;",
            "  endcase",
            "endfunction",
            "",
            "function automatic logic [1:0] apu_kws_apum_fixed_word_check(",
            "    input logic [14:0] offset_i, input logic [31:0] data_i);",
            "  logic valid;",
            "  logic [10:0] index;",
            "  begin",
            "    valid = 1'b0;",
            "    index = 11'd0;",
        )
    )
    for start, end, index in ranges:
        keyword = "if" if index == 0 else "else if"
        lower_bound = "" if start == 0 else f"(offset_i >= 15'h{start:04x}) && "
        lines.extend(
            (
                f"    {keyword} ({lower_bound}(offset_i <= 15'h{end:04x}) && "
                "(offset_i[1:0] == 2'd0)) begin",
                "      valid = 1'b1;",
                f"      index = 11'd{index} + "
                f"11'((offset_i - 15'h{start:04x}) >> 2);",
                "    end",
            )
        )
    lines.extend(
        (
            "    apu_kws_apum_fixed_word_check =",
            "        valid ? {1'b1, data_i == apu_kws_apum_fixed_word(index)} : 2'b00;",
            "  end",
            "endfunction",
            "",
        )
    )
    return "\n".join(lines)


def generate(apum: Path, output: Path, profile_output: Path) -> None:
    image = apum.read_bytes()
    if len(image) != 32768:
        raise ValueError("APUM image must be exactly 32768 bytes")
    fixed_offsets, fixed_words = _fixed_apum_words(image)
    text = [
        "// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>",
        "// SPDX-License-Identifier: MulanPSL-2.0",
        "",
        "// Generated by scripts/generate_apu_kws_rtl_constants.py.",
        "// Do not edit: regenerate from the frozen APUM and numerical profile.",
        "",
        _emit_function("apu_kws_hann_q30", 32, _hann()),
    ]
    twiddle_real, twiddle_imag = _twiddle()
    text.extend(
        (
            _emit_function("apu_kws_twiddle_real_q30", 32, twiddle_real),
            _emit_function("apu_kws_twiddle_imag_q30", 32, twiddle_imag),
            _emit_function("apu_kws_mel_q30", 32, _mel_weights(), signed=False),
            _emit_function("apu_kws_dct_q30", 32, _dct()),
            _emit_function("apu_kws_log_q24", 32, _log_rom()),
            _emit_function("apu_kws_fir3_q30", 32, _fir(3)),
            _emit_function("apu_kws_fir6_q30", 32, _fir(6)),
            _emit_function("apu_kws_softmax_exp_q31", 32, _softmax_exp()),
            f"localparam logic signed [31:0] ApuKwsLn2Q24 = 32'sd{_rne(TWO.ln() * Decimal(1 << 24))};",
            "",
        )
    )
    output.write_text("\n".join(text), encoding="ascii")
    profile_output.write_text(
        "\n".join(
            (
                "// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>",
                "// SPDX-License-Identifier: MulanPSL-2.0",
                "",
                "// Generated by scripts/generate_apu_kws_rtl_constants.py.",
                "// Do not edit: regenerate from the frozen APUM.",
                "",
                _emit_profile_words(fixed_offsets, fixed_words),
            )
        ),
        encoding="ascii",
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apum", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--profile-output", type=Path)
    args = parser.parse_args()
    profile_output = args.profile_output
    if profile_output is None:
        profile_output = args.output.with_name("apu_kws_apum_profile.svh")
    generate(args.apum, args.output, profile_output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
