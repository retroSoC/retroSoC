#!/usr/bin/env python3
"""Generate frozen APU-P7 references and the APU-P9 coefficient image."""

from __future__ import annotations

import argparse
import hashlib
import json
import struct
import subprocess
import zlib
from decimal import Decimal, ROUND_HALF_EVEN, getcontext
from pathlib import Path

from apu_kws_coeff import (
    APUC_ABI,
    APUC_APUM_PAYLOAD_CRC,
    APUC_BANK_COUNT,
    APUC_BYTES,
    APUC_COEFFICIENT_ID,
    APUC_HEADER_BYTES,
    APUC_LAYOUT_ID,
    APUC_LOGICAL_SHA256,
    APUC_MAGIC,
    APUC_PAYLOAD_BYTES,
    APUC_PAYLOAD_CRC,
    APUC_PAYLOAD_SHA256,
    APUC_PROFILE,
    APUC_SHA256,
    APUC_TABLE_COUNT,
)

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


def _word_bytes(words: list[int]) -> bytes:
    return b"".join(struct.pack("<I", value & 0xFFFFFFFF) for value in words)


def _coefficient_tables(image: bytes) -> tuple[list[tuple[str, list[int]]], list[int], list[int]]:
    fixed_offsets, fixed_words = _fixed_apum_words(image)
    twiddle_real, twiddle_imag = _twiddle()
    tables = [
        ("hann", _hann()),
        ("twiddle_real", twiddle_real),
        ("twiddle_imag", twiddle_imag),
        ("mel", _mel_weights()),
        ("dct", _dct()),
        ("log", _log_rom()),
        ("fir3", _fir(3)),
        ("fir6", _fir(6)),
        ("softmax", _softmax_exp()),
        ("apum_profile", fixed_words),
    ]
    return tables, fixed_offsets, fixed_words


def _pack_coefficient_banks(image: bytes) -> tuple[list[list[int]], dict[str, list[tuple[int, int]]]]:
    tables, _fixed_offsets, fixed_words = _coefficient_tables(image)
    by_name = dict(tables)
    banks = [[0] * 1024 for _ in range(APUC_BANK_COUNT)]
    inverse: dict[str, list[tuple[int, int]]] = {name: [] for name, _values in tables}

    def place(name: str, index: int, bank: int, row: int) -> None:
        banks[bank][row] = by_name[name][index] & 0xFFFFFFFF
        inverse[name].append((bank, row))

    for index in range(480):
        place("hann", index, 0, index)
    for index in range(400):
        place("dct", index, 0, 480 + index)
    for index in range(63):
        place("fir3", index, 0, 880 + index)
        place("fir6", index, 0, 943 + index)
    for index in range(256):
        place("twiddle_real", index, 1, index)
        place("twiddle_imag", index, 2, index)
    for index in range(1025):
        bank = 1 + (index & 1)
        place("log", index, bank, 256 + (index >> 1))
    for index in range(10280):
        if index < 10240:
            place("mel", index, 3 + (index >> 10), index & 1023)
        else:
            place("mel", index, 13, index - 10240)
    for index in range(len(fixed_words)):
        if index < 984:
            place("apum_profile", index, 13, 40 + index)
        else:
            place("apum_profile", index, 14, index - 984)
    for index in range(125):
        place("softmax", index, 14, 512 + index)
    return banks, inverse


def build_apuc(image: bytes) -> tuple[bytes, dict[str, object]]:
    """Build the exact APUC 1.0 image and its reviewable layout manifest."""

    if len(image) != 32768:
        raise ValueError("APUM image must be exactly 32768 bytes")
    tables, fixed_offsets, _fixed_words = _coefficient_tables(image)
    banks, inverse = _pack_coefficient_banks(image)
    logical = b"".join(_word_bytes(values) for _name, values in tables)
    payload = b"".join(_word_bytes(bank) for bank in banks)
    payload_crc = zlib.crc32(payload) & 0xFFFFFFFF
    ln2_q24 = _rne(TWO.ln() * Decimal(1 << 24))
    header = struct.pack(
        "<16I",
        APUC_MAGIC,
        APUC_ABI,
        APUC_BYTES,
        APUC_HEADER_BYTES,
        APUC_PAYLOAD_BYTES,
        APUC_PROFILE,
        APUC_LAYOUT_ID,
        APUC_BANK_COUNT,
        APUC_TABLE_COUNT,
        payload_crc,
        APUC_COEFFICIENT_ID[0],
        APUC_COEFFICIENT_ID[1],
        APUC_APUM_PAYLOAD_CRC,
        ln2_q24,
        0,
        0,
    )
    apuc = header + payload
    logical_sha = hashlib.sha256(logical).hexdigest()
    payload_sha = hashlib.sha256(payload).hexdigest()
    apuc_sha = hashlib.sha256(apuc).hexdigest()
    if payload_crc != APUC_PAYLOAD_CRC:
        raise ValueError(f"APUC payload CRC drift: 0x{payload_crc:08x}")
    if logical_sha != APUC_LOGICAL_SHA256:
        raise ValueError(f"APUC logical SHA-256 drift: {logical_sha}")
    if payload_sha != APUC_PAYLOAD_SHA256:
        raise ValueError(f"APUC payload SHA-256 drift: {payload_sha}")
    if apuc_sha != APUC_SHA256:
        raise ValueError(f"APUC image SHA-256 drift: {apuc_sha}")

    populated = sum(len(locations) for locations in inverse.values())
    generator_path = Path(__file__).resolve()
    generator_sha = hashlib.sha256(generator_path.read_bytes()).hexdigest()
    revision = subprocess.run(
        ["git", "-C", str(generator_path.parents[1]), "rev-parse", "HEAD"],
        check=False,
        capture_output=True,
        text=True,
    )
    repository_commit = revision.stdout.strip() if revision.returncode == 0 else ""
    manifest: dict[str, object] = {
        "schema_version": 1,
        "generator": {
            "path": "scripts/generate_apu_kws_rtl_constants.py",
            "revision": f"sha256:{generator_sha}",
            "sha256": generator_sha,
            "repository_commit": repository_commit,
        },
        "container": {
            "magic": f"0x{APUC_MAGIC:08x}",
            "abi": f"0x{APUC_ABI:08x}",
            "bytes": len(apuc),
            "header_bytes": APUC_HEADER_BYTES,
            "payload_bytes": len(payload),
            "payload_crc32": f"0x{payload_crc:08x}",
            "coefficient_id": [f"0x{word:08x}" for word in APUC_COEFFICIENT_ID],
            "associated_apum_crc32": f"0x{APUC_APUM_PAYLOAD_CRC:08x}",
            "logical_sha256": logical_sha,
            "payload_sha256": payload_sha,
            "sha256": apuc_sha,
        },
        "layout": {
            "geometry": "tc_sram_1024x32",
            "banks": APUC_BANK_COUNT,
            "words_per_bank": 1024,
            "populated_words": populated,
            "zero_padding_words": APUC_BANK_COUNT * 1024 - populated,
        },
        "tables": {
            name: {
                "words": len(values),
                "sha256_le32": hashlib.sha256(_word_bytes(values)).hexdigest(),
                "locations": [[bank, row] for bank, row in inverse[name]],
            }
            for name, values in tables
        },
        "apum_profile_offsets": fixed_offsets,
    }
    return apuc, manifest


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


def generate(
    apum: Path,
    output: Path,
    profile_output: Path,
    apuc_output: Path | None = None,
    manifest_output: Path | None = None,
) -> None:
    image = apum.read_bytes()
    if len(image) != 32768:
        raise ValueError("APUM image must be exactly 32768 bytes")
    output.parent.mkdir(parents=True, exist_ok=True)
    profile_output.parent.mkdir(parents=True, exist_ok=True)
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
    if (apuc_output is None) != (manifest_output is None):
        raise ValueError("APUC output and manifest output must be requested together")
    if apuc_output is not None and manifest_output is not None:
        apuc, manifest = build_apuc(image)
        apuc_output.parent.mkdir(parents=True, exist_ok=True)
        manifest_output.parent.mkdir(parents=True, exist_ok=True)
        apuc_output.write_bytes(apuc)
        manifest_output.write_text(json.dumps(manifest, indent=2) + "\n", encoding="ascii")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apum", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--profile-output", type=Path)
    parser.add_argument("--apuc-output", type=Path)
    parser.add_argument("--manifest-output", type=Path)
    args = parser.parse_args()
    profile_output = args.profile_output
    if profile_output is None:
        profile_output = args.output.with_name("apu_kws_apum_profile.svh")
    generate(args.apum, args.output, profile_output, args.apuc_output, args.manifest_output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
