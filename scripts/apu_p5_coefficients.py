#!/usr/bin/env python3
"""Generate the frozen APU-P5 32-phase, 16-tap Q2.30 coefficient banks."""

from __future__ import annotations

import argparse
import hashlib
import json
import struct
from decimal import Decimal, ROUND_HALF_EVEN, localcontext
from pathlib import Path


def _pi(precision: int) -> Decimal:
    with localcontext() as context:
        context.prec = precision + 16
        multiplier = Decimal(1)
        linear = Decimal(13591409)
        exponent = Decimal(1)
        total = linear
        k_value = Decimal(6)
        terms = precision // 14 + 3
        for index in range(1, terms):
            divisor = Decimal(index) ** 3
            multiplier = multiplier * (k_value**3 - Decimal(16) * k_value) / divisor
            linear += Decimal(545140134)
            exponent *= Decimal(-262537412640768000)
            total += multiplier * linear / exponent
            k_value += Decimal(12)
        value = Decimal(426880) * Decimal(10005).sqrt() / total
        context.prec = precision
        return +value


def _sin(value: Decimal, pi_value: Decimal, precision: int) -> Decimal:
    with localcontext() as context:
        context.prec = precision + 12
        period = Decimal(2) * pi_value
        value %= period
        if value > pi_value:
            value -= period
        term = value
        total = value
        index = 1
        threshold = Decimal(10) ** Decimal(-(precision + 4))
        while abs(term) > threshold:
            term *= -(value * value) / Decimal((2 * index) * (2 * index + 1))
            total += term
            index += 1
        context.prec = precision
        return +total


def _cos(value: Decimal, pi_value: Decimal, precision: int) -> Decimal:
    return _sin(value + pi_value / Decimal(2), pi_value, precision)


def coefficient_words(precision: int = 112) -> list[int]:
    with localcontext() as context:
        context.prec = precision
        pi_value = _pi(precision)
        banks = (Decimal(1), Decimal(2) / Decimal(3), Decimal(1) / Decimal(2))
        words: list[int] = []
        for cutoff in banks:
            for phase in range(32):
                amplitudes: list[Decimal] = []
                for tap in range(16):
                    x_value = Decimal(tap - 7) - Decimal(phase) / Decimal(32)
                    argument = cutoff * x_value
                    sinc = (
                        Decimal(1)
                        if argument == 0
                        else _sin(pi_value * argument, pi_value, precision) /
                        (pi_value * argument)
                    )
                    window = (
                        Decimal(1) -
                        _cos(
                            Decimal(2) * pi_value * (Decimal(tap) + Decimal("0.5")) /
                            Decimal(16),
                            pi_value,
                            precision,
                        )
                    ) / Decimal(2)
                    amplitudes.append(cutoff * sinc * window)
                scale = sum(amplitudes)
                phase_words = [
                    int((Decimal(1 << 30) * value / scale).to_integral_value(
                        rounding=ROUND_HALF_EVEN
                    ))
                    for value in amplitudes
                ]
                phase_words[7] += (1 << 30) - sum(phase_words)
                words.extend(phase_words)
        return words


def coefficient_bytes() -> bytes:
    first = coefficient_words(112)
    independent = coefficient_words(160)
    if first != independent:
        raise RuntimeError("coefficient rounding did not converge across precision bounds")
    return b"".join(struct.pack("<i", word) for word in first)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--manifest", type=Path, required=True)
    args = parser.parse_args()
    payload = coefficient_bytes()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(payload)
    args.manifest.write_text(
        json.dumps(
            {
                "banks": 3,
                "phases": 32,
                "taps": 16,
                "words": len(payload) // 4,
                "bytes": len(payload),
                "sha256": hashlib.sha256(payload).hexdigest(),
            },
            indent=2,
            sort_keys=True,
        ) + "\n",
        encoding="utf-8",
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
