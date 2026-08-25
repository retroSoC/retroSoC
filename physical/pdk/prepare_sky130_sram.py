#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import os
import shutil
import sys
import tempfile
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from scripts.install_toolchain import safe_extract  # noqa: E402
from scripts.setup_helpers import atomic_write, sha256  # noqa: E402


MACRO = "sky130_sram_4kbyte_1rw_32x1024_8"
OPENRAM_COMMIT = "b2b069ce119d1488cbe6883b2240bceb5c7ce29a"
INPUT_CONFIG_SHA256 = "24dfd2f0371c6007015ccd825d13f5227a5cc7ffb158bc0ce35d4a62aa2fc646"
SKY130_CIEL_REVISION = "e8294524e5f67c533c5d0c3afa0bcc5b2a5fa066"
SKY130_BUILDSPACE_REVISION = "dd64256961317205343a3fd446908b42bafba388"
EXPECTED_GEOMETRY = {
    "words": 1024,
    "data_bits": 32,
    "write_granularity_bits": 8,
    "read_write_ports": 1,
    "spare_rows": 1,
    "spare_columns": 1,
}
EXPECTED_CORNERS = ["TT_1p8V_25C", "SS_1p4V_100C"]
REQUIRED_FILES = (
    f"{MACRO}.v",
    f"{MACRO}.lef",
    f"{MACRO}.gds",
    f"{MACRO}.sp",
    f"{MACRO}.lvs.sp",
    f"{MACRO}.html",
    f"{MACRO}.py",
    f"{MACRO}_TT_1p8V_25C.lib",
    f"{MACRO}_SS_1p4V_100C.lib",
    "INPUT_CONFIG.py",
    "LICENSE.OpenRAM-BSD-3-Clause",
    "LICENSE.SkyWater-Apache-2.0",
    "SHA256SUMS",
    "manifest.json",
)


def load_manifest(source: Path) -> dict[str, Any]:
    manifest_path = source / "manifest.json"
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise RuntimeError(f"cannot read SKY130 SRAM manifest: {error}") from error
    if not isinstance(manifest, dict):
        raise RuntimeError("SKY130 SRAM manifest must be an object")
    return manifest


def validate_generated_sram(source: Path) -> None:
    missing = [name for name in REQUIRED_FILES if not (source / name).is_file()]
    if missing:
        raise RuntimeError("SKY130 SRAM archive is missing: " + ", ".join(missing))

    manifest = load_manifest(source)
    expected = {
        "schema_version": 1,
        "macro": MACRO,
        "geometry": EXPECTED_GEOMETRY,
        "corners": EXPECTED_CORNERS,
        "openram_commit": OPENRAM_COMMIT,
        "input_config_sha256": INPUT_CONFIG_SHA256,
        "sky130_ciel_revision": SKY130_CIEL_REVISION,
        "sky130_buildspace_revision": SKY130_BUILDSPACE_REVISION,
        "analytical_characterization": True,
        "drc_lvs_checked": False,
    }
    for key, value in expected.items():
        if manifest.get(key) != value:
            raise RuntimeError(
                f"SKY130 SRAM manifest {key}={manifest.get(key)!r}, expected {value!r}"
            )

    file_hashes = manifest.get("files")
    if not isinstance(file_hashes, dict) or not file_hashes:
        raise RuntimeError("SKY130 SRAM manifest has no generated-file hashes")
    for name, expected_hash in file_hashes.items():
        path = source / name
        if not isinstance(name, str) or not isinstance(expected_hash, str) or not path.is_file():
            raise RuntimeError(f"invalid SKY130 SRAM manifest file entry: {name!r}")
        actual_hash = sha256(path)
        if actual_hash != expected_hash:
            raise RuntimeError(
                f"SKY130 SRAM generated-file checksum mismatch for {name}: "
                f"{actual_hash}, expected {expected_hash}"
            )


def prepare(archive: Path, output_dir: Path, archive_sha256: str) -> None:
    complete = output_dir / ".complete"
    if complete.is_file() and complete.read_text(encoding="utf-8").strip() == archive_sha256:
        validate_generated_sram(output_dir)
        print(f"SKY130 OpenRAM SRAM is ready: {output_dir}")
        return

    output_dir.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="sky130-openram-", dir=output_dir.parent) as temp:
        extracted = Path(temp) / "extracted"
        extracted.mkdir()
        safe_extract(archive, extracted)
        validate_generated_sram(extracted)
        atomic_write(extracted / ".complete", archive_sha256 + "\n")
        candidate = Path(temp) / "candidate"
        os.replace(extracted, candidate)
        if output_dir.exists():
            shutil.rmtree(output_dir)
        os.replace(candidate, output_dir)
    print(f"SKY130 OpenRAM SRAM is ready: {output_dir}")


def main() -> int:
    parser = argparse.ArgumentParser(description="Prepare the locked SKY130 OpenRAM SRAM views")
    parser.add_argument("--archive", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--archive-sha256", required=True)
    args = parser.parse_args()
    prepare(args.archive.resolve(), args.output_dir.resolve(), args.archive_sha256)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
