#!/usr/bin/env python3
"""Pack the frozen CRYC1 image from the revision-qualified V1 RTL tables."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import struct
import zlib


LAYOUT_ID = 0x43525901
WORDS = 2048
CRC32 = 0x99CA52FE
SHA256 = "b662a0729bf85789aa9c9bd4a9f8a13ebe44e296deebda486bef2792b1e9d47f"


def lookup(source: str, name: str, size: int, base: int) -> list[int]:
    match = re.search(r"function automatic[^\n]*\b" + name + r"\(.*?endfunction", source, re.S)
    if match is None:
        raise ValueError(f"missing {name}")
    body = match.group()
    entries: dict[int, int] = {}
    for key, value in re.findall(
        r"(?:8'h|6'd)([0-9a-f]+):\s*" + name + r"\s*=\s*(?:8|32)'h([0-9a-f]+)", body
    ):
        index = int(key, base)
        if index in entries:
            raise ValueError(f"duplicate {name}[{index}]")
        entries[index] = int(value, 16)
    default = re.search(r"default:\s*" + name + r"\s*=\s*(?:8|32)'h([0-9a-f]+)", body)
    if default is None or set(entries) != set(range(size - 1)):
        raise ValueError(f"incomplete {name}")
    return [entries[i] for i in range(size - 1)] + [int(default[1], 16)]


def pack(root: Path) -> bytes:
    package = (root / "rtl/ip/security/crypto_pkg.sv").read_text()
    engine = (root / "rtl/ip/security/crypto_sha2_engine.sv").read_text()
    words = [0] * WORDS
    words[:256] = lookup(package, "aes_sbox", 256, 16)
    words[256:512] = lookup(package, "aes_inverse_sbox", 256, 16)
    # Rcon is algorithmic in V1; preserve its defined zero at indices 0 and 15.
    rcon = 1
    for index in range(1, 15):
        words[512 + index] = rcon
        rcon = ((rcon << 1) ^ (0x11B if rcon & 0x80 else 0)) & 0xFF
    words[1024:1088] = lookup(package, "sha2_k", 64, 10)
    initial = re.findall(r"s_hash_state_q <= 256'h([0-9a-f]{64});", engine)
    if len(initial) != 2:
        raise ValueError("expected SHA-256 then SHA-224 initialization")
    for start, value in ((1088, initial[1]), (1096, initial[0])):
        words[start:start + 8] = [int(value[i:i + 8], 16) for i in range(0, 64, 8)]
    return struct.pack("<2048I", *words)


def validate(payload: bytes) -> dict[str, object]:
    digest = hashlib.sha256(payload).hexdigest()
    crc = zlib.crc32(payload)
    if len(payload) != 8192 or digest != SHA256 or crc != CRC32:
        raise ValueError("CRYC1 payload does not match the frozen identity")
    return {"layout_id": f"0x{LAYOUT_ID:08x}", "bytes": len(payload),
            "words": WORDS, "crc32": f"0x{crc:08x}", "sha256": digest}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    payload = pack(args.root)
    manifest = validate(payload)
    args.output.mkdir(parents=True, exist_ok=True)
    (args.output / "crypto.cryc").write_bytes(payload)
    (args.output / "crypto_constants.inc").write_text(
        "/* Generated CRYC1 words; do not edit. */\n" +
        "\n".join(f"UINT32_C(0x{word:08x})," for (word,) in struct.iter_unpack("<I", payload)) + "\n"
    )
    (args.output / "constants.json").write_text(json.dumps(manifest, indent=2) + "\n")


if __name__ == "__main__":
    main()
