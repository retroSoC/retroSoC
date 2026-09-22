"""Bit-accurate model (BAM) of the frozen APU-P7 frontend numerical profile 1.

Implements docs/ip/apu.md "P7 frontend numerical profile 1" (lines 2322-2398)
exactly, mirroring the RTL arithmetic in rtl/ip/multimedia/apu_kws_engine.sv
operation by operation:

  PCM 16000 x S16 -> positive peak P=max(1,max(x[0..15999]))
  -> 49 frames of 480 samples (hop 320; the last 160 samples only feed P)
  -> Hann Q2.30, real FFT input RNE(x*H/2^15), imaginary zero, zero-pad 512
  -> bit-reversed radix-2 DIT FFT (Q2.30 cos/-sin twiddles, one RNE/2^30 per
     complex multiply, RNE/2 per butterfly sum/diff; components = DFT*64,
     signed-32 with fault on overflow)
  -> bins 0..256, nearest-integer sqrt of the unsigned-64 component squares
     (ties even)
  -> 40 mel triangles Q2.30 (DC bin zeroed), M=RNE(sum/2^32) unsigned UQ28.4
  -> exact rational z=(1000000*M+16*P)/(16000000*P), exact 2^e*m
     normalization, log ROM interpolation with f=65536 allowed
  -> DCT Q2.30, C[j]=RNE(sum(log*D)/2^30) signed Q8.24
  -> q=TZ(C[j]/(2^24*S)+83) with the exact binary32 scale S=0x3f15af17
     (2^24*S == 9809687 == 0x95AF17), low-8-bit wrap to the INT8 feature byte.

All arithmetic is exact Python integer arithmetic. ROM constants are imported
from scripts/generate_apu_kws_rtl_constants.py (the same generators that emit
rtl/ip/multimedia/apu_kws_rom.svh), never duplicated. Where the RTL faults
(FFT signed-32 component overflow) or wraps (log output truncation to
signed-32), this model does the same; :class:`FrontendFault` marks the fault
cases, which valid S16 audio never reaches.
"""

from __future__ import annotations

import math
import struct
import sys
from dataclasses import dataclass
from decimal import Decimal
from functools import lru_cache
from pathlib import Path
from typing import Final

sys.path.insert(0, str(Path(__file__).resolve().parent))

import generate_apu_kws_rtl_constants as gen  # noqa: E402

WINDOW_SAMPLES: Final = 16000
WINDOW_BYTES: Final = 32000
FRAME_COUNT: Final = 49
FRAME_SAMPLES: Final = 480
FRAME_HOP: Final = 320
FFT_POINTS: Final = 512
FFT_BINS: Final = 257
MEL_BANDS: Final = 40
MFCC_COEFFICIENTS: Final = 10
FEATURE_BYTES: Final = FRAME_COUNT * MFCC_COEFFICIENTS
QUANT_SCALE_BITS: Final = 0x3F15AF17
QUANT_DIVISOR: Final = 0x0095AF17
QUANT_BIAS: Final = 83
_S32_MIN: Final = -(1 << 31)
_S32_MAX: Final = (1 << 31) - 1


class FrontendFault(RuntimeError):
    """The input drives an RTL checked-arithmetic fault range."""


@lru_cache(maxsize=1)
def hann_q30() -> tuple[int, ...]:
    """Hann window coefficients H[n]=RNE(2^30*(1-cos(2*pi*n/480))/2)."""
    return tuple(gen._hann())


@lru_cache(maxsize=1)
def twiddle_q30() -> tuple[tuple[int, ...], tuple[int, ...]]:
    """FFT twiddles: RNE-quantized Q2.30 cos and negative sin of 2*pi*k/512."""
    real, imag = gen._twiddle()
    return tuple(real), tuple(imag)


@lru_cache(maxsize=1)
def mel_q30() -> tuple[int, ...]:
    """Forty mel triangle weight rows, 257 bins each, Q2.30, DC zeroed (flat)."""
    return tuple(gen._mel_weights())


@lru_cache(maxsize=1)
def dct_q30() -> tuple[int, ...]:
    """DCT coefficients D[j,b]=RNE(2^30*sqrt(2/40)*cos(pi*(b+1/2)*j/40)) (flat)."""
    return tuple(gen._dct())


@lru_cache(maxsize=1)
def log_q24() -> tuple[int, ...]:
    """Log ROM L[i]=RNE(2^24*ln(1+i/1024)) for i=0..1024, signed Q8.24."""
    return tuple(gen._log_rom())


@lru_cache(maxsize=1)
def ln2_q24() -> int:
    """LN2=RNE(2^24*ln(2)) signed Q8.24, the ROM localparam ApuKwsLn2Q24."""
    return gen._rne(gen.TWO.ln() * Decimal(1 << 24))


@lru_cache(maxsize=1)
def _bit_reverse9() -> tuple[int, ...]:
    return tuple(int(f"{index:09b}"[::-1], 2) for index in range(FFT_POINTS))


def _s32(value: int) -> int:
    """Truncate to signed 32 bits, mirroring the RTL 32'(...) conversion."""
    value &= 0xFFFFFFFF
    return value - (1 << 32) if value > _S32_MAX else value


def _trunc_div(numerator: int, denominator: int) -> int:
    """TZ(numerator/denominator): truncation toward zero."""
    return numerator // denominator if numerator >= 0 else -((-numerator) // denominator)


def rne_shift(value: int, shift: int) -> int:
    """RNE(value / 2^shift) with ties to even, sign symmetric (RTL rne_shift)."""
    if shift == 0:
        return value
    magnitude = -value if value < 0 else value
    quotient = magnitude >> shift
    remainder = magnitude & ((1 << shift) - 1)
    half = 1 << (shift - 1)
    if remainder > half or (remainder == half and (quotient & 1) != 0):
        quotient += 1
    return -quotient if value < 0 else quotient


def rne_uq32(value: int) -> int:
    """Unsigned RNE(value / 2^32) with ties to even (RTL rne_uq32)."""
    if value < 0 or value >= 1 << 64:
        raise FrontendFault(f"mel reduction outside u64: {value}")
    quotient = value >> 32
    remainder = value & 0xFFFFFFFF
    if remainder > 0x80000000 or (remainder == 0x80000000 and (quotient & 1) != 0):
        quotient += 1
    return quotient


def nearest_isqrt(value: int) -> int:
    """Nearest-integer square root of an unsigned-64 value, ties even."""
    if value < 0 or value >= 1 << 64:
        raise FrontendFault(f"magnitude square outside u64: {value}")
    root = math.isqrt(value)
    lower = value - root * root
    upper = (root + 1) * (root + 1) - value
    if upper < lower or (upper == lower and (root & 1) != 0):
        root += 1
    return root


def log_mel_q24(mel: int, peak: int) -> int:
    """Exact rational log stage: Q8.24 ln(M/(16*P)+1e-6) (RTL log_mel_q24)."""
    if not 0 <= mel <= 0xFFFFFFFF:
        raise FrontendFault(f"mel value outside UQ28.4 word: {mel}")
    if not 1 <= peak <= 0xFFFF:
        raise FrontendFault(f"window peak outside u16: {peak}")
    numerator = 1_000_000 * mel + 16 * peak
    denominator = 16_000_000 * peak
    exponent = 0
    if numerator >= denominator:
        normalized = denominator
        while numerator >= normalized << 1:
            normalized <<= 1
            exponent += 1
    else:
        normalized = denominator
        while numerator < normalized:
            numerator <<= 1
            exponent -= 1
    scaled = (numerator - normalized) * 1024
    index = scaled // normalized
    remainder = scaled - index * normalized
    fraction_scaled = remainder * 65536
    fraction = fraction_scaled // normalized
    fraction_remainder = fraction_scaled - fraction * normalized
    if 2 * fraction_remainder > normalized or (
        2 * fraction_remainder == normalized and (fraction & 1) != 0
    ):
        fraction += 1  # fraction may be 65536 (spec step 5)
    table = log_q24()
    interpolation = rne_shift((table[index + 1] - table[index]) * fraction, 16)
    return _s32(exponent * ln2_q24() + table[index] + interpolation)


def quantize_coefficient(coefficient: int) -> int:
    """Frozen step-7 quantizer: q=TZ(C/(2^24*S)+83) with S=0x3f15af17.

    C/(2^24*S)+83 == (C + 83*9809687)/9809687 as an exact rational; truncating
    the integer division matches both the frozen formula and the RTL
    expression (s_dct_coefficient + 64'sh3087_c475) / 64'sh0095_af17.
    """
    return _trunc_div(coefficient + QUANT_BIAS * QUANT_DIVISOR, QUANT_DIVISOR)


def wrap_int8(value: int) -> int:
    """Low-8-bit wrap of a quantized coefficient, interpreted signed INT8."""
    wrapped = value & 0xFF
    return wrapped - 256 if wrapped >= 128 else wrapped


def samples_from_pcm(pcm: bytes) -> tuple[int, ...]:
    """Decode one 32000-byte little-endian S16 window into 16000 samples."""
    if len(pcm) != WINDOW_BYTES:
        raise ValueError(f"profile-1 window must be {WINDOW_BYTES} bytes, got {len(pcm)}")
    return struct.unpack(f"<{WINDOW_SAMPLES}h", pcm)


def _fft_frame(windowed: list[int], real: list[int], imag: list[int]) -> None:
    """One 512-point profile-1 FFT in place; windowed holds 480 FFT inputs."""
    twiddle_real, twiddle_imag = twiddle_q30()
    bit_reverse = _bit_reverse9()
    for index in range(FFT_POINTS):
        real[index] = 0
        imag[index] = 0
    for index in range(FRAME_SAMPLES):
        real[bit_reverse[index]] = windowed[index]
    length = 2
    while length <= FFT_POINTS:
        half = length // 2
        step = FFT_POINTS // length
        for group in range(0, FFT_POINTS, length):
            for j in range(half):
                left = group + j
                right = left + half
                wr = twiddle_real[step * j]
                wi = twiddle_imag[step * j]
                right_r = real[right]
                right_i = imag[right]
                tw_r = _s32(rne_shift(right_r * wr - right_i * wi, 30))
                tw_i = _s32(rne_shift(right_r * wi + right_i * wr, 30))
                left_r = real[left]
                left_i = imag[left]
                sum_r = rne_shift(left_r + tw_r, 1)
                sum_i = rne_shift(left_i + tw_i, 1)
                dif_r = rne_shift(left_r - tw_r, 1)
                dif_i = rne_shift(left_i - tw_i, 1)
                for component in (sum_r, sum_i, dif_r, dif_i):
                    if component < _S32_MIN or component > _S32_MAX:
                        raise FrontendFault(f"FFT component overflow: {component}")
                real[left] = sum_r
                imag[left] = sum_i
                real[right] = dif_r
                imag[right] = dif_i
        length *= 2


@dataclass(frozen=True)
class FrontendStages:
    """Every observable profile-1 stage for one 16000-sample window."""

    samples: tuple[int, ...]
    peak: int
    windowed: tuple[tuple[int, ...], ...]  # 49 x 480, RNE(x*H/2^15)
    fft_real: tuple[tuple[int, ...], ...]  # 49 x 512 signed-32, unscaled DFT*64
    fft_imag: tuple[tuple[int, ...], ...]
    magnitude: tuple[tuple[int, ...], ...]  # 49 x 257
    mel: tuple[tuple[int, ...], ...]  # 49 x 40 unsigned UQ28.4
    logs: tuple[tuple[int, ...], ...]  # 49 x 40 signed Q8.24
    coeffs: tuple[tuple[int, ...], ...]  # 49 x 10 signed Q8.24
    quantized: tuple[tuple[int, ...], ...]  # 49 x 10 pre-wrap q
    features: bytes  # 490 wrapped INT8 feature bytes


def frontend_stages(samples: tuple[int, ...] | list[int]) -> FrontendStages:
    """Run profile 1 on one 16000-sample S16 window and return every stage."""
    if len(samples) != WINDOW_SAMPLES:
        raise ValueError(f"profile-1 window must be {WINDOW_SAMPLES} samples")
    samples = tuple(int(value) for value in samples)
    if any(value < -32768 or value > 32767 for value in samples):
        raise ValueError("profile-1 input must be signed S16")
    hann = hann_q30()
    mel_weights = mel_q30()
    dct = dct_q30()
    peak = max(1, max(samples))

    windowed_rows: list[tuple[int, ...]] = []
    fft_real_rows: list[tuple[int, ...]] = []
    fft_imag_rows: list[tuple[int, ...]] = []
    magnitude_rows: list[tuple[int, ...]] = []
    mel_rows: list[tuple[int, ...]] = []
    real = [0] * FFT_POINTS
    imag = [0] * FFT_POINTS
    for row in range(FRAME_COUNT):
        frame = samples[FRAME_HOP * row : FRAME_HOP * row + FRAME_SAMPLES]
        windowed = [rne_shift(value * coefficient, 15) for value, coefficient in zip(frame, hann)]
        _fft_frame(windowed, real, imag)
        windowed_rows.append(tuple(windowed))
        fft_real_rows.append(tuple(real))
        fft_imag_rows.append(tuple(imag))
        magnitude = tuple(
            nearest_isqrt(real[bin_index] * real[bin_index] + imag[bin_index] * imag[bin_index])
            for bin_index in range(FFT_BINS)
        )
        magnitude_rows.append(magnitude)
        mel_rows.append(
            tuple(
                rne_uq32(
                    sum(
                        magnitude[bin_index] * mel_weights[band * FFT_BINS + bin_index]
                        for bin_index in range(FFT_BINS)
                    )
                )
                for band in range(MEL_BANDS)
            )
        )

    logs_rows = tuple(
        tuple(log_mel_q24(mel_rows[row][band], peak) for band in range(MEL_BANDS))
        for row in range(FRAME_COUNT)
    )
    coeffs_rows: list[tuple[int, ...]] = []
    for row in range(FRAME_COUNT):
        coeffs = []
        for coefficient in range(MFCC_COEFFICIENTS):
            total = sum(
                logs_rows[row][band] * dct[coefficient * MEL_BANDS + band]
                for band in range(MEL_BANDS)
            )
            if total < -(1 << 63) or total >= 1 << 63:
                raise FrontendFault(f"DCT reduction outside s64: {total}")
            coeffs.append(rne_shift(total, 30))
        coeffs_rows.append(tuple(coeffs))
    quantized_rows = tuple(
        tuple(quantize_coefficient(coeffs_rows[row][j]) for j in range(MFCC_COEFFICIENTS))
        for row in range(FRAME_COUNT)
    )
    features = bytes(value & 0xFF for row in quantized_rows for value in row)
    return FrontendStages(
        samples=samples,
        peak=peak,
        windowed=tuple(windowed_rows),
        fft_real=tuple(fft_real_rows),
        fft_imag=tuple(fft_imag_rows),
        magnitude=tuple(magnitude_rows),
        mel=tuple(mel_rows),
        logs=logs_rows,
        coeffs=tuple(coeffs_rows),
        quantized=quantized_rows,
        features=features,
    )


def mfcc_profile1(pcm: bytes) -> bytes:
    """Map one 32000-byte padded PCM window to its 490 profile-1 MFCC bytes."""
    return frontend_stages(samples_from_pcm(pcm)).features
