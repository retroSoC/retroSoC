"""Independent mathematical CRYC1 oracle and deterministic PUBLIC RSA fixtures.

No production table, image packing helper, or DUT intermediate is imported.
RSA fixtures are test material, never keys for real-world use.
"""

from __future__ import annotations

import hashlib
import math
import struct


def gf_multiply(left: int, right: int) -> int:
    result = 0
    for _ in range(8):
        if right & 1:
            result ^= left
        left = ((left << 1) ^ (0x11B if left & 128 else 0)) & 255
        right >>= 1
    return result


def sbox(value: int) -> int:
    inverse, power, exponent = 1, value, 254
    while exponent:
        if exponent & 1:
            inverse = gf_multiply(inverse, power)
        power = gf_multiply(power, power)
        exponent >>= 1
    if value == 0:
        inverse = 0
    result = inverse ^ 0x63
    for shift in range(1, 5):
        result ^= ((inverse << shift) | (inverse >> (8 - shift))) & 255
    return result


def integer_root(number: int, degree: int) -> int:
    low, high = 0, 1 << ((number.bit_length() + degree - 1) // degree)
    while low + 1 < high:
        mid = (low + high) // 2
        if mid ** degree <= number:
            low = mid
        else:
            high = mid
    return low


def constant_image() -> bytes:
    # Byte-oriented packing is independent of the production word-list packer.
    result = bytearray(8192)
    forward = [sbox(i) for i in range(256)]
    for index, value in enumerate(forward):
        result[index * 4] = value
        result[(256 + value) * 4] = index
    value = 1
    for index in range(1, 15):
        result[(512 + index) * 4] = value
        value = gf_multiply(value, 2)
    primes: list[int] = []
    candidate = 2
    while len(primes) < 64:
        if all(candidate % prime for prime in primes if prime * prime <= candidate):
            primes.append(candidate)
        candidate += 1
    for index, prime in enumerate(primes):
        struct.pack_into("<I", result, 4096 + index * 4,
                         integer_root(prime << 96, 3) & 0xFFFFFFFF)
    for index in range(8):
        struct.pack_into("<I", result, 4096 + (64 + index) * 4,
                         math.isqrt(primes[8 + index] << 128) & 0xFFFFFFFF)
        struct.pack_into("<I", result, 4096 + (72 + index) * 4,
                         math.isqrt(primes[index] << 64) & 0xFFFFFFFF)
    return bytes(result)


def probable_prime(value: int) -> bool:
    # Fixed bases for reproducible test construction, not a production key generator.
    bases = (2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37, 41, 43, 47, 53)
    if any(value % base == 0 for base in bases):
        return False
    odd, shift = value - 1, 0
    while odd % 2 == 0:
        odd //= 2
        shift += 1
    for base in bases:
        residue = pow(base, odd, value)
        if residue in (1, value - 1):
            continue
        for _ in range(shift - 1):
            residue = residue * residue % value
            if residue == value - 1:
                break
        else:
            return False
    return True


def rsa_fixture() -> dict[str, int]:
    primes = []
    for label in (b"retroSoC CRYPTO-P0 p", b"retroSoC CRYPTO-P0 q"):
        candidate = int.from_bytes(hashlib.shake_256(label).digest(128), "big")
        candidate |= (3 << 1022) | 1
        while not probable_prime(candidate) or math.gcd(candidate - 1, 65537) != 1:
            candidate += 2
        primes.append(candidate)
    p, q = primes
    modulus = p * q
    private = pow(65537, -1, math.lcm(p - 1, q - 1))
    message = int.from_bytes(hashlib.shake_256(b"CRYPTO-P0 message").digest(255), "big")
    ciphertext = pow(message, 65537, modulus)
    if modulus.bit_length() != 2048 or pow(ciphertext, private, modulus) != message:
        raise ValueError("invalid deterministic RSA-2048 fixture")
    radix = 1 << 2048
    return {"modulus": modulus, "private": private, "message": message,
            "ciphertext": ciphertext, "n0_prime": -pow(modulus, -1, 1 << 32) % (1 << 32),
            "montgomery": (modulus - 1) ** 2 * pow(radix, -1, modulus) % modulus}
