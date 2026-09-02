#!/usr/bin/env python3
"""Package LP firmware and the fixed HP Linux image set into one flash image."""

from __future__ import annotations

import argparse
import hashlib
import json
import struct
import zlib
from pathlib import Path


FLASH_SIZE = 16 * 1024 * 1024
BUNDLE_OFFSET = 1 * 1024 * 1024
PAYLOAD_ALIGNMENT = 4096
MAGIC = 0x50485352
VERSION = 1
REQUIRED = 1
HEADER = struct.Struct("<8I")
ENTRY = struct.Struct("<6I")
ARTIFACTS = (
    (1, "fw_jump.bin", 0x38000000, 512 * 1024),
    (2, "retrosoc_hp.dtb", 0x38080000, 64 * 1024),
    (3, "Image", 0x38400000, 12 * 1024 * 1024),
    (4, "rootfs.cpio.gz", 0x39000000, 8 * 1024 * 1024),
)
HEADER_SIZE = HEADER.size + (ENTRY.size * len(ARTIFACTS))


def align_up(value: int, alignment: int) -> int:
    return (value + alignment - 1) & ~(alignment - 1)


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def package(args: argparse.Namespace) -> None:
    firmware = args.firmware.read_bytes()
    if len(firmware) > BUNDLE_OFFSET:
        raise ValueError(
            f"LP firmware is {len(firmware)} bytes; bundle starts at {BUNDLE_OFFSET}"
        )

    payload_offset = align_up(BUNDLE_OFFSET + HEADER_SIZE, PAYLOAD_ALIGNMENT)
    entries: list[bytes] = []
    payloads: list[tuple[int, bytes]] = []
    artifact_manifest: dict[str, object] = {}
    cursor = payload_offset
    for kind, name, load_address, maximum in ARTIFACTS:
        data = (args.images / name).read_bytes()
        if not data or len(data) > maximum:
            raise ValueError(f"{name} size {len(data)} is outside 1..{maximum} bytes")
        crc32 = zlib.crc32(data) & 0xFFFFFFFF
        entries.append(ENTRY.pack(kind, cursor, load_address, len(data), crc32, REQUIRED))
        payloads.append((cursor, data))
        artifact_manifest[name] = {
            "crc32": f"0x{crc32:08X}",
            "flash_offset": f"0x{cursor:08X}",
            "load_address": f"0x{load_address:08X}",
            "sha256": sha256(data),
            "size_bytes": len(data),
        }
        cursor = align_up(cursor + len(data), PAYLOAD_ALIGNMENT)

    if cursor > FLASH_SIZE:
        raise ValueError(f"HP boot image needs {cursor} bytes; flash capacity is {FLASH_SIZE}")
    total_size = cursor - BUNDLE_OFFSET
    header = HEADER.pack(
        MAGIC,
        VERSION,
        HEADER_SIZE,
        len(entries),
        total_size,
        0,
        REQUIRED,
        0,
    ) + b"".join(entries)
    header_crc32 = zlib.crc32(header) & 0xFFFFFFFF
    header = HEADER.pack(
        MAGIC,
        VERSION,
        HEADER_SIZE,
        len(entries),
        total_size,
        header_crc32,
        REQUIRED,
        0,
    ) + b"".join(entries)

    image = bytearray(b"\xFF" * cursor)
    image[: len(firmware)] = firmware
    image[BUNDLE_OFFSET : BUNDLE_OFFSET + len(header)] = header
    for offset, data in payloads:
        image[offset : offset + len(data)] = data

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(image)
    manifest = {
        "schema_version": 1,
        "format": "retrosoc-hp-boot-bundle-v1",
        "bundle_offset": f"0x{BUNDLE_OFFSET:08X}",
        "flash_capacity_bytes": FLASH_SIZE,
        "header_crc32": f"0x{header_crc32:08X}",
        "image_sha256": sha256(image),
        "image_size_bytes": len(image),
        "lp_firmware_size_bytes": len(firmware),
        "artifacts": artifact_manifest,
    }
    args.manifest.parent.mkdir(parents=True, exist_ok=True)
    args.manifest.write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--firmware", type=Path, required=True)
    parser.add_argument("--images", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--manifest", type=Path, required=True)
    package(parser.parse_args())


if __name__ == "__main__":
    main()
