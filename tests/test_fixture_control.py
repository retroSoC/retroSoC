from __future__ import annotations

import json
import subprocess
from pathlib import Path

import pytest

from scripts.fixture_control import (
    HOSTED_PYTEST_TOOLS,
    doctor,
    fixture_profile,
    restore,
    restore_archive,
)
from scripts.setup_helpers import sha256

ROOT = Path(__file__).resolve().parents[1]


def git(root: Path, *arguments: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(["git", "-C", str(root), *arguments], check=True, capture_output=True, text=True)


def test_hosted_profile_preserves_the_real_fixture_setup() -> None:
    profile = fixture_profile(ROOT, ROOT)
    source_names = {source["name"] for source in profile["sources"]}
    archive_names = {archive["name"] for archive in profile["archives"]}
    assert {"pdk_ihp130", "pdk_ics55", "pdk_ics55_pll", "publication_media"} <= source_names
    assert {"apu_mlperf_tiny", "apu_kws_mfcc", "apu_tfds", "apu_tensorflow", "apu_gemmlowp"} <= source_names
    assert "pdk_gf180" not in source_names and "pdk_sky130" not in source_names
    assert {"apu_libflac", "apu_flac_corpus", "apu_kws_pcm", "npu_vww_dataset"} <= archive_names
    assert {f"toolchain:{name}" for name in HOSTED_PYTEST_TOOLS} <= archive_names
    assert any(name.startswith("publication:") for name in archive_names)
    assert ["make", "CONFIG=configs/ci/ihp130.mk", "setup-pdk"] in profile["commands"]
    assert ["make", "setup-apu-reference", "setup-apu-kws-reference", "setup-npu-reference"] in profile["commands"]
    assert profile["commands"][-1][-10:] == [
        item for name in HOSTED_PYTEST_TOOLS for item in ("--tool", name)
    ]


def test_archive_restore_is_local_checksum_bound_and_non_destructive(tmp_path: Path) -> None:
    reference_root = tmp_path / "reference"
    target = tmp_path / "target"
    reference = reference_root / "archive.tar.gz"
    reference.parent.mkdir(parents=True)
    reference.write_bytes(b"locked archive\n")
    spec = {
        "name": "example",
        "kind": "archive",
        "destination": "archive.tar.gz",
        "reference": str(reference),
        "sha256": sha256(reference),
    }
    result = restore_archive(target, spec)
    destination = target / "archive.tar.gz"
    assert result["status"] == "VERIFIED"
    assert result["restore_mode"] == "locked-copy"
    assert destination.read_bytes() == b"locked archive\n"
    destination.write_bytes(b"preserve mismatch\n")
    with pytest.raises(RuntimeError, match="existing archive differs"):
        restore_archive(target, spec)
    assert destination.read_bytes() == b"preserve mismatch\n"


def test_restore_rejects_a_shared_writable_reference_root(tmp_path: Path) -> None:
    with pytest.raises(ValueError, match="distinct target and reference"):
        restore(tmp_path, tmp_path, tmp_path / "result.json")
    assert not (tmp_path / "result.json").exists()


def test_doctor_reports_missing_inputs_instead_of_skipping_them(tmp_path: Path) -> None:
    profile = {
        "profile": "hosted-pytest",
        "sources": [{"name": "missing", "destination": "missing", "revision": "a" * 40}],
        "archives": [],
        "tools": [],
        "tool_paths": [],
    }
    result = doctor(tmp_path, profile)
    assert result["status"] == "BLOCKED"
    assert result["issue_count"] == 3
    assert any("missing" in issue for issue in result["issues"])
    assert any("dependency lock" in issue for issue in result["issues"])


def test_doctor_accepts_exact_locked_inputs(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    git(tmp_path, "init", "-q")
    source = tmp_path / "source"
    source.mkdir()
    git(source, "init", "-q")
    git(source, "config", "user.email", "fixture@example.invalid")
    git(source, "config", "user.name", "Fixture")
    (source / "value.txt").write_text("locked\n", encoding="utf-8")
    git(source, "add", "value.txt")
    git(source, "commit", "-qm", "locked")
    revision = git(source, "rev-parse", "HEAD").stdout.strip()
    archive = tmp_path / "archive.tar.gz"
    archive.write_bytes(b"archive\n")
    marker = tmp_path / ".cache/retrosoc/sources/apu-kws-pcm/.retrosoc-archive-sha256"
    marker.parent.mkdir(parents=True)
    marker.write_text("b" * 64 + "\n", encoding="utf-8")
    monkeypatch.setattr(
        "scripts.fixture_control.load_lock",
        lambda path: {"toolchains": {}, "archives": {"apu_kws_pcm": {"sha256": "b" * 64}}},
    )
    profile = {
        "profile": "hosted-pytest",
        "sources": [{"name": "example", "destination": "source", "revision": revision}],
        "archives": [{"name": "archive", "destination": "archive.tar.gz", "sha256": sha256(archive)}],
        "tools": [],
        "tool_paths": [],
    }
    result = doctor(tmp_path, profile)
    assert result["status"] == "READY"
    assert result["issues"] == []
    assert "source_dirty" in result


def test_cli_plan_rejects_invalid_lock_without_output(tmp_path: Path) -> None:
    root = tmp_path / "repo"
    root.mkdir()
    git(root, "init", "-q")
    lock = {"sources": {}, "archives": {}, "toolchains": {"ubuntu-22.04": {}}}
    (root / "dependencies").mkdir()
    (root / "dependencies/dependencies.lock.json").write_text(json.dumps(lock), encoding="utf-8")
    completed = subprocess.run(
        [
            "python3",
            str(ROOT / "scripts/fixture_control.py"),
            "plan",
            "--root",
            str(root),
            "--reference-root",
            str(tmp_path / "reference"),
            "--output",
            str(tmp_path / "plan.json"),
        ],
        text=True,
        capture_output=True,
        check=False,
    )
    assert completed.returncode == 2
    assert "dependency lock" in completed.stderr
    assert not (tmp_path / "plan.json").exists()


def test_make_fixture_entrypoints_preserve_explicit_restore() -> None:
    plan = subprocess.run(
        [
            "make",
            "--no-print-directory",
            "-n",
            "-C",
            str(ROOT),
            "fixture-plan",
            "REFERENCE_ROOT=/tmp/reference",
        ],
        text=True,
        capture_output=True,
        check=False,
    )
    assert plan.returncode == 0
    assert "fixture_control.py plan" in plan.stdout
    assert "fixture_control.py restore" not in plan.stdout
    restore_result = subprocess.run(
        [
            "make",
            "--no-print-directory",
            "-n",
            "-C",
            str(ROOT),
            "fixture-restore",
            "REFERENCE_ROOT=/tmp/reference",
        ],
        text=True,
        capture_output=True,
        check=False,
    )
    assert restore_result.returncode == 0
    assert "fixture_control.py restore" in restore_result.stdout
