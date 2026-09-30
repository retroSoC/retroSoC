#!/usr/bin/env python3
"""Pack CRYC1 and its compact firmware representation from public constants."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import struct
import zlib


LAYOUT_ID = 0x43525901
WORDS = 2048
CRC32 = 0x99CA52FE
SHA256 = "b662a0729bf85789aa9c9bd4a9f8a13ebe44e296deebda486bef2792b1e9d47f"


def pack(root: Path) -> bytes:
    source = json.loads((root / "scripts/data/crypto_constants.json").read_text())
    aes = source["aes_bytes"]
    sha = [int(word, 16) for word in source["sha_words"]]
    if (int(source["layout_id"], 16) != LAYOUT_ID or len(aes) != 528 or
            len(sha) != 80 or any(not 0 <= byte <= 255 for byte in aes)):
        raise ValueError("invalid CRYC1 public constant source")
    words = [0] * WORDS
    words[:528] = aes
    words[1024:1104] = sha
    return struct.pack("<2048I", *words)


def compact_header(payload: bytes) -> str:
    """Only 848 initialized bytes; the HAL emits the reserved zero rows."""
    validate(payload)
    words = struct.unpack("<2048I", payload)
    return ("/* Generated public CRYC1 constants; do not edit. */\n" +
            "static const uint8_t rs_crypto_aes_constants[528] = {\n" +
            "\n".join("    " + ", ".join(f"0x{x:02x}U" for x in words[i:i + 16]) + ","
                      for i in range(0, 528, 16)) + "\n};\n" +
            "static const uint32_t rs_crypto_sha_constants[80] = {\n" +
            "\n".join("    " + ", ".join(f"UINT32_C(0x{x:08x})" for x in words[i:i + 4]) + ","
                      for i in range(1024, 1104, 4)) + "\n};\n")


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
    (args.output / "crypto_constants.h").write_text(compact_header(payload))
    (args.output / "crypto_constants.inc").write_text(
        "/* Generated CRYC1 words; do not edit. */\n" +
        "\n".join(f"UINT32_C(0x{word:08x})," for (word,) in struct.iter_unpack("<I", payload)) + "\n"
    )
    (args.output / "constants.json").write_text(json.dumps(manifest, indent=2) + "\n")


if __name__ == "__main__":
    main()
