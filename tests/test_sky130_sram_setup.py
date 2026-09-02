"""Tests for the locked SKY130 OpenRAM SRAM setup path."""

from __future__ import annotations

import hashlib
import io
import json
import tarfile
from pathlib import Path

import pytest

from physical.pdk.prepare_sky130_sram import (
    EXPECTED_CORNERS,
    EXPECTED_GEOMETRY,
    INPUT_CONFIG_SHA256,
    MACRO,
    OPENRAM_COMMIT,
    REQUIRED_FILES,
    SKY130_BUILDSPACE_REVISION,
    SKY130_CIEL_REVISION,
    prepare,
)


def make_archive(path: Path, *, corners: list[str] | None = None) -> str:
    payloads = {
        name: f"generated {name}\n".encode()
        for name in REQUIRED_FILES
        if name not in {"manifest.json", "SHA256SUMS"}
    }
    manifest = {
        "schema_version": 1,
        "macro": MACRO,
        "geometry": EXPECTED_GEOMETRY,
        "corners": EXPECTED_CORNERS if corners is None else corners,
        "openram_commit": OPENRAM_COMMIT,
        "input_config_sha256": INPUT_CONFIG_SHA256,
        "sky130_ciel_revision": SKY130_CIEL_REVISION,
        "sky130_buildspace_revision": SKY130_BUILDSPACE_REVISION,
        "analytical_characterization": True,
        "drc_lvs_checked": False,
        "files": {
            name: hashlib.sha256(content).hexdigest() for name, content in payloads.items()
        },
    }
    payloads["manifest.json"] = (json.dumps(manifest) + "\n").encode()
    payloads["SHA256SUMS"] = b"fixture checksums\n"
    with tarfile.open(path, "w:gz") as archive:
        for name, content in payloads.items():
            member = tarfile.TarInfo(name)
            member.size = len(content)
            archive.addfile(member, io.BytesIO(content))
    return hashlib.sha256(path.read_bytes()).hexdigest()


def test_prepare_sky130_sram_is_verified_and_idempotent(tmp_path: Path) -> None:
    archive = tmp_path / "sram.tar.gz"
    digest = make_archive(archive)
    output = tmp_path / "openram"

    prepare(archive, output, digest)
    first_mtime = (output / ".complete").stat().st_mtime_ns
    prepare(archive, output, digest)

    assert (output / f"{MACRO}.v").is_file()
    assert (output / ".complete").read_text(encoding="utf-8").strip() == digest
    assert (output / ".complete").stat().st_mtime_ns == first_mtime


def test_prepare_sky130_sram_rejects_wrong_corners(tmp_path: Path) -> None:
    archive = tmp_path / "sram.tar.gz"
    digest = make_archive(archive, corners=["TT_1p8V_25C"])

    with pytest.raises(RuntimeError, match="corners"):
        prepare(archive, tmp_path / "openram", digest)
