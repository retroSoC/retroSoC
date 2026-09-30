"""Frozen APUC 1.0 coefficient-container definitions and validator."""

from __future__ import annotations

import hashlib
import struct
import zlib
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Final


APUC_MAGIC: Final = 0x43555041
APUC_ABI: Final = 0x00010000
APUC_HEADER_BYTES: Final = 64
APUC_PAYLOAD_BYTES: Final = 15 * 1024 * 4
APUC_BYTES: Final = APUC_HEADER_BYTES + APUC_PAYLOAD_BYTES
APUC_PROFILE: Final = 1
APUC_LAYOUT_ID: Final = 1
APUC_BANK_COUNT: Final = 15
APUC_TABLE_COUNT: Final = 10
APUC_PAYLOAD_CRC: Final = 0x25E7C27D
APUC_COEFFICIENT_ID: Final = (0x8A0B038D, 0x806C780D)
APUC_APUM_PAYLOAD_CRC: Final = 0xB9034B22
APUC_LN2_Q24: Final = 11629080
APUC_LOGICAL_SHA256: Final = "f416585119e488c82e5cea1dabb17424e33a16dd8041393135903a613edced46"
APUC_PAYLOAD_SHA256: Final = "8d030b8a0d786c80a7fa072439700a4485711971d79a6a62e78fcafb1657d83a"
APUC_SHA256: Final = "d670688442ea6efe1e638108157f55fc55c75218c8edbee931aaca3497567818"

APUC_TABLES: Final = {
    "hann": (480, "5fb8748b60ff53c721d3f97c2516b9f77aebd8bb15103a072219505769d4af61"),
    "twiddle_real": (256, "49faa57826aa487032eef985d7d25f29b5346692f22ab9780209cb118c9c5b8a"),
    "twiddle_imag": (256, "3552f5ed86694388ee674dcb988509e1f8fec5c61c7435e289a27591a2c817ec"),
    "mel": (10280, "a13dc9eaf00e6e2be9710c4a1bd432239c0181b5d2ee9903250c667d906f16be"),
    "dct": (400, "93a71d890110064feb515cb7527740ce3ff0116451931e27925ac1c36339153e"),
    "log": (1025, "20b0b265de2c9e319dc70b2fa0ee136add8693937108c5f0c65ccc0ca146050a"),
    "fir3": (63, "77ccbd59d8346f709d299ce762c1976dd8abbba3263d47ed65ef394db570870a"),
    "fir6": (63, "a00ceab9105dddbed5e6d2426753dd5dbc99c9b0c166b1f19f43c530ceb9faac"),
    "softmax": (125, "410f11dd7f10d5516b41efdec861afe6a7f2a34dd116163f7758ac5110b65ae7"),
    "apum_profile": (
        1496,
        "4c30d9a5e054436bab5acfb4651ea361d0211956c9211e9d36d182b9fdc88991",
    ),
}


def _expected_locations() -> dict[str, list[tuple[int, int]]]:
    locations: dict[str, list[tuple[int, int]]] = {
        name: [] for name in APUC_TABLES
    }
    locations["hann"] = [(0, index) for index in range(480)]
    locations["dct"] = [(0, 480 + index) for index in range(400)]
    locations["fir3"] = [(0, 880 + index) for index in range(63)]
    locations["fir6"] = [(0, 943 + index) for index in range(63)]
    locations["twiddle_real"] = [(1, index) for index in range(256)]
    locations["twiddle_imag"] = [(2, index) for index in range(256)]
    locations["log"] = [(1 + (index & 1), 256 + (index >> 1)) for index in range(1025)]
    locations["mel"] = [
        (3 + (index >> 10), index & 1023) if index < 10240 else (13, index - 10240)
        for index in range(10280)
    ]
    locations["apum_profile"] = [
        (13, 40 + index) if index < 984 else (14, index - 984)
        for index in range(1496)
    ]
    locations["softmax"] = [(14, 512 + index) for index in range(125)]
    return locations


def _expected_profile_offsets() -> list[int]:
    offsets = list(range(0, 0x500, 4))
    for start in (0x1000, 0x1540, 0x2840, 0x2D80, 0x4080, 0x45C0, 0x58C0, 0x5E00, 0x7100):
        offsets.extend(range(start, start + 0x200, 4))
    offsets.extend(range(0x7630, 0x7690, 4))
    return offsets


def validate_layout_manifest(image: bytes, manifest: dict[str, Any]) -> None:
    """Validate the generated layout with a frozen oracle independent of its packer."""

    validate_apuc(image)
    if manifest.get("schema_version") != 1:
        raise ValueError("APUC layout manifest schema version is not 1")
    generator = manifest.get("generator")
    if not isinstance(generator, dict):
        raise ValueError("APUC layout manifest lacks generator identity")
    generator_path = generator.get("path")
    generator_sha = generator.get("sha256")
    generator_revision = generator.get("revision")
    repository_commit = generator.get("repository_commit")
    if generator_path != "scripts/generate_apu_kws_rtl_constants.py" or not isinstance(
        generator_sha, str
    ):
        raise ValueError("APUC generator path/SHA identity is incomplete")
    if generator_revision != f"sha256:{generator_sha}":
        raise ValueError("APUC generator revision does not match its source SHA")
    if (
        not isinstance(repository_commit, str)
        or len(repository_commit) != 40
        or any(character not in "0123456789abcdef" for character in repository_commit.lower())
    ):
        raise ValueError("APUC generator repository revision is not a full Git commit")
    source = Path(__file__).resolve().parents[1] / generator_path
    if not source.is_file() or hashlib.sha256(source.read_bytes()).hexdigest() != generator_sha:
        raise ValueError("APUC generator source does not match the recorded revision")

    expected_container = {
        "magic": f"0x{APUC_MAGIC:08x}",
        "abi": f"0x{APUC_ABI:08x}",
        "bytes": APUC_BYTES,
        "header_bytes": APUC_HEADER_BYTES,
        "payload_bytes": APUC_PAYLOAD_BYTES,
        "payload_crc32": f"0x{APUC_PAYLOAD_CRC:08x}",
        "coefficient_id": [f"0x{word:08x}" for word in APUC_COEFFICIENT_ID],
        "associated_apum_crc32": f"0x{APUC_APUM_PAYLOAD_CRC:08x}",
        "logical_sha256": APUC_LOGICAL_SHA256,
        "payload_sha256": APUC_PAYLOAD_SHA256,
        "sha256": APUC_SHA256,
    }
    if manifest.get("container") != expected_container:
        raise ValueError("APUC container manifest does not match the frozen identity")
    if manifest.get("layout") != {
        "geometry": "tc_sram_1024x32",
        "banks": APUC_BANK_COUNT,
        "words_per_bank": 1024,
        "populated_words": 14444,
        "zero_padding_words": 916,
    }:
        raise ValueError("APUC physical layout summary does not match the frozen geometry")
    if manifest.get("apum_profile_offsets") != _expected_profile_offsets():
        raise ValueError("APUC APUM-profile offsets do not match the independent oracle")

    table_records = manifest.get("tables")
    if not isinstance(table_records, dict) or set(table_records) != set(APUC_TABLES):
        raise ValueError("APUC layout manifest does not contain the exact ten tables")
    payload_words = struct.unpack(f"<{APUC_BANK_COUNT * 1024}I", image[APUC_HEADER_BYTES:])
    expected_locations = _expected_locations()
    occupied: set[tuple[int, int]] = set()
    for name, (word_count, frozen_sha) in APUC_TABLES.items():
        record = table_records.get(name)
        locations = expected_locations[name]
        expected_record = {
            "words": word_count,
            "sha256_le32": frozen_sha,
            "locations": [[bank, row] for bank, row in locations],
        }
        if record != expected_record:
            raise ValueError(f"APUC table {name} does not match the independent map/hash oracle")
        if any(location in occupied for location in locations):
            raise ValueError(f"APUC table {name} overlaps another table")
        occupied.update(locations)
        table_bytes = b"".join(
            struct.pack("<I", payload_words[(bank * 1024) + row]) for bank, row in locations
        )
        if hashlib.sha256(table_bytes).hexdigest() != frozen_sha:
            raise ValueError(f"APUC payload words for {name} do not match the frozen hash")
    if len(occupied) != 14444:
        raise ValueError("APUC independent populated-position count is not 14444")
    for bank in range(APUC_BANK_COUNT):
        for row in range(1024):
            if (bank, row) not in occupied and payload_words[(bank * 1024) + row] != 0:
                raise ValueError(f"APUC padding is nonzero at bank {bank} row {row}")


@dataclass(frozen=True)
class ApucHeader:
    magic: int
    abi: int
    total_bytes: int
    payload_offset: int
    payload_bytes: int
    profile: int
    layout_id: int
    bank_count: int
    table_count: int
    payload_crc: int
    coefficient_id: tuple[int, int]
    associated_apum_crc: int
    ln2_q24: int


def validate_apuc(image: bytes) -> ApucHeader:
    """Validate exact APUC 1.0 bytes and return the frozen header."""

    if len(image) != APUC_BYTES:
        raise ValueError(f"APUC image must be exactly {APUC_BYTES} bytes")
    words = struct.unpack_from("<16I", image)
    expected = (
        APUC_MAGIC,
        APUC_ABI,
        APUC_BYTES,
        APUC_HEADER_BYTES,
        APUC_PAYLOAD_BYTES,
        APUC_PROFILE,
        APUC_LAYOUT_ID,
        APUC_BANK_COUNT,
        APUC_TABLE_COUNT,
        APUC_PAYLOAD_CRC,
        *APUC_COEFFICIENT_ID,
        APUC_APUM_PAYLOAD_CRC,
        APUC_LN2_Q24,
        0,
        0,
    )
    if words != expected:
        raise ValueError("APUC header does not match the frozen profile")
    payload = image[APUC_HEADER_BYTES:]
    if zlib.crc32(payload) & 0xFFFFFFFF != APUC_PAYLOAD_CRC:
        raise ValueError("APUC payload CRC mismatch")
    if hashlib.sha256(payload).hexdigest() != APUC_PAYLOAD_SHA256:
        raise ValueError("APUC payload SHA-256 mismatch")
    if hashlib.sha256(image).hexdigest() != APUC_SHA256:
        raise ValueError("APUC image SHA-256 mismatch")
    return ApucHeader(
        magic=words[0],
        abi=words[1],
        total_bytes=words[2],
        payload_offset=words[3],
        payload_bytes=words[4],
        profile=words[5],
        layout_id=words[6],
        bank_count=words[7],
        table_count=words[8],
        payload_crc=words[9],
        coefficient_id=(words[10], words[11]),
        associated_apum_crc=words[12],
        ln2_q24=words[13],
    )
