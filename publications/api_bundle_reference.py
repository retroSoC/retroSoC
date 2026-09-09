"""Publish reviewed API outcomes and the actual HP boot packager's byte layout."""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import re
import struct
import tempfile
import zlib
from pathlib import Path


API_NAMES = {
    "rs_wait_mask", "rs_wait_value", "rs_wait_not_value", "rs_uart_write", "rs_uart_read",
    "rs_dma_start", "rs_dma_abort", "rs_dma_abort_wait", "rs_dma_wait", "rs_timer_delay_ms",
}


def dependencies(spec: dict) -> set[str]:
    paths = set()
    for row in spec.get("api_semantics", []):
        paths.add(row["source"])
    bundle = spec.get("boot_bundle", {})
    paths.update(bundle.get("sources", []))
    for row in bundle.get("loader_bindings", []):
        paths.add(row["source"])
    if spec.get("api_semantics"):
        paths.add("crt/include/retrosoc/core/status.h")
    return paths


def body_digest(body: str) -> str:
    # Whitespace outside string literals is immaterial, but literal bytes matter.
    pieces = re.split(r'("(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\')', body)
    normalized = "".join(piece if index % 2 else re.sub(r"\s+", "", piece)
                         for index, piece in enumerate(pieces))
    return hashlib.sha256(normalized.encode()).hexdigest()


def validate_api(root: Path, rows: list[dict], function_body) -> dict:
    names = [row["name"] for row in rows]
    if len(names) != len(set(names)) or set(names) != API_NAMES:
        raise ValueError("API semantics coverage is incomplete or duplicated")
    for row in rows:
        source = (root / row["source"]).read_text(encoding="utf-8")
        if body_digest(function_body(source, row["name"])) != row["body_sha256"]:
            raise ValueError(f"review API semantics after source change: {row['name']}")
        if any(not row.get(key) for key in ("budget", "zero", "success", "failure", "next")):
            raise ValueError("API semantics record lacks an outcome or recovery boundary")
    header = (root / "crt/include/retrosoc/core/status.h").read_text(encoding="utf-8")
    if not re.search(r"typedef\s+uint32_t\s+rs_timeout_t\s*;", header):
        raise ValueError("timeout type changed")
    defaults = re.findall(r"^#define\s+RS_TIMEOUT_DEFAULT\s+\(\(rs_timeout_t\)(\d+)U\)", header, re.M)
    if len(defaults) != 1:
        raise ValueError("timeout default missing or ambiguous")
    return {"timeout_bits": 32, "default_budget": int(defaults[0]), "rows": rows}


def load_packager(root: Path):
    spec = importlib.util.spec_from_file_location("publication_hp_packager", root / "scripts/package_hp_boot.py")
    if spec is None or spec.loader is None:
        raise ValueError("cannot load reviewed HP packager")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def c_members(header: str, name: str) -> list[str]:
    records = re.findall(r"typedef\s+struct\s*\{([^}]+)\}\s*" + re.escape(name) + r"\s*;", header)
    if len(records) != 1:
        raise ValueError("bundle C structure missing or ambiguous")
    body = records[0]
    members = re.findall(r"uint32_t\s+(\w+)\s*;", body)
    shape = r"\s*(?:uint32_t\s+\w+\s*;\s*)+"
    if name == "rs_hp_boot_header_t":
        shape += r"rs_hp_boot_entry_t\s+entries\[RS_HP_BOOT_BUNDLE_ENTRY_COUNT\]\s*;\s*"
    if not re.fullmatch(shape, body):
        raise ValueError("unsupported bundle C member type or order")
    remainder = re.sub(r"uint32_t\s+\w+\s*;", "", body)
    if name == "rs_hp_boot_header_t":
        remainder = re.sub(r"rs_hp_boot_entry_t\s+entries\[RS_HP_BOOT_BUNDLE_ENTRY_COUNT\]\s*;", "", remainder)
    if remainder.strip():
        raise ValueError("unsupported bundle C member type or order")
    return members


def bundle_layout(root: Path, spec: dict, function_body) -> dict:
    module = load_packager(root)
    header = (root / "app/apps/hp_boot/hp_boot_bundle.h").read_text(encoding="utf-8")
    constants = {name: int(value, 0) for name, value in re.findall(
        r"^#define\s+(RS_HP_BOOT_\w+)\s+UINT32_C\((0x[0-9A-Fa-f]+|\d+)\)", header, re.M)}
    for attribute, suffix in (("MAGIC", "BUNDLE_MAGIC"), ("VERSION", "BUNDLE_VERSION"),
                              ("BUNDLE_OFFSET", "BUNDLE_OFFSET"), ("REQUIRED", "BUNDLE_REQUIRED")):
        if getattr(module, attribute) != constants["RS_HP_BOOT_" + suffix]:
            raise ValueError("packager/loader bundle constant mismatch")
    if module.HEADER.format != "<8I" or module.ENTRY.format != "<6I":
        raise ValueError("bundle word layout or byte order changed")
    fixed = c_members(header, "rs_hp_boot_header_t")
    entry = c_members(header, "rs_hp_boot_entry_t")
    if fixed != list(spec["header_fields"]) or entry != list(spec["entry_fields"]):
        raise ValueError("bundle C field order differs from reviewed publication")
    if (len(module.ARTIFACTS) != constants["RS_HP_BOOT_BUNDLE_ENTRY_COUNT"]
            or module.HEADER_SIZE != module.HEADER.size + len(module.ARTIFACTS) * module.ENTRY.size):
        raise ValueError("bundle header/entry count mismatch")
    for index, (kind, _, address, maximum) in enumerate(module.ARTIFACTS):
        tag = ("OPENSBI", "DTB", "LINUX", "INITRAMFS")[index]
        if (kind, address, maximum) != (constants["RS_HP_BOOT_TYPE_" + tag],
                                      constants["RS_HP_BOOT_" + tag + "_ADDRESS"],
                                      constants["RS_HP_BOOT_" + tag + "_MAX_SIZE"]):
            raise ValueError("bundle artifact order or destination bound mismatch")
    for row in spec["loader_bindings"]:
        source = (root / row["source"]).read_text(encoding="utf-8")
        if body_digest(function_body(source, row["function"])) != row["body_sha256"]:
            raise ValueError(f"review bundle acceptance after source change: {row['function']}")
    if module.PAYLOAD_ALIGNMENT < 4 or module.PAYLOAD_ALIGNMENT & (module.PAYLOAD_ALIGNMENT - 1):
        raise ValueError("packager payload alignment must be a word-aligned power of two")
    # Execute the existing packager only on temporary synthetic files. These bytes
    # are a reproducible serialization example, not executable firmware payloads.
    with tempfile.TemporaryDirectory(prefix="retrosoc-publication-bundle-") as directory:
        temp = Path(directory)
        images = temp / "images"
        images.mkdir()
        firmware = temp / "lp.bin"
        firmware.write_bytes(b"LP" * 32)
        for index, (_, name, _, _) in enumerate(module.ARTIFACTS, 1):
            (images / name).write_bytes(bytes([index]) * (31 + index))
        output, manifest = temp / "example.bin", temp / "example.json"
        module.package(argparse.Namespace(firmware=firmware, images=images, output=output, manifest=manifest))
        image = output.read_bytes()
        recorded = json.loads(manifest.read_text(encoding="utf-8"))
    values = module.HEADER.unpack_from(image, module.BUNDLE_OFFSET)
    raw_header = image[module.BUNDLE_OFFSET:module.BUNDLE_OFFSET + module.HEADER_SIZE]
    crc_input = bytearray(raw_header)
    struct.pack_into("<I", crc_input, fixed.index("header_crc32") * 4, 0)
    if zlib.crc32(crc_input) & 0xFFFFFFFF != values[fixed.index("header_crc32")]:
        raise ValueError("synthetic header CRC does not match actual packager output")
    entries = []
    for index, (_, name, _, _) in enumerate(module.ARTIFACTS):
        offset = module.HEADER.size + index * module.ENTRY.size
        fields = dict(zip(entry, module.ENTRY.unpack_from(raw_header, offset), strict=True))
        payload = image[fields["flash_offset"]:fields["flash_offset"] + fields["size"]]
        if (zlib.crc32(payload) & 0xFFFFFFFF != fields["crc32"]
                or fields["flash_offset"] % module.PAYLOAD_ALIGNMENT):
            raise ValueError("synthetic payload CRC or alignment mismatch")
        entries.append({"name": name, "descriptor_offset": offset, **fields})
    if values[fixed.index("total_size")] != len(image) - module.BUNDLE_OFFSET:
        raise ValueError("synthetic bundle total size does not match output length")
    return {"header_fields": [{"name": name, "offset": index * 4, "bytes": 4, "meaning": spec["header_fields"][name]}
                              for index, name in enumerate(fixed)],
            "entry_fields": [{"name": name, "offset": index * 4, "bytes": 4, "meaning": spec["entry_fields"][name]}
                             for index, name in enumerate(entry)],
            "fixed_header_bytes": module.HEADER.size, "entry_bytes": module.ENTRY.size,
            "header_bytes": module.HEADER_SIZE, "entry_count": len(module.ARTIFACTS),
            "bundle_offset": module.BUNDLE_OFFSET, "payload_alignment": module.PAYLOAD_ALIGNMENT,
            "flash_capacity": module.FLASH_SIZE, "magic": module.MAGIC, "version": module.VERSION,
            "example": {"header": dict(zip(fixed, values, strict=True)), "entries": entries,
                        "image_bytes": len(image), "image_sha256": recorded["image_sha256"],
                        "header_hex": raw_header.hex().upper(), "lp_bytes": 64},
            "rules": spec["rules"]}
