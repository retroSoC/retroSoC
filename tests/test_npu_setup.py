"""NPU-P0 reference setup flow tests."""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

import setup_npu_reference as setup_npu  # noqa: E402

TINY = ROOT / ".cache/retrosoc/sources/apu-mlperf-tiny"


def test_lock_carries_npu_vww_dataset_entry() -> None:
    dataset = setup_npu.archive("npu_vww_dataset")
    assert (
        dataset["sha256"]
        == "f8746b9e44f8a7a4293f73be9ba6e8da9239fe69798d42364aae62b915cfab58"
    )
    assert dataset["url"].endswith("vw_coco2014_96.tar.gz")


def test_model_hash_constants_match_extraction_module() -> None:
    import npu_model

    assert setup_npu.KWS_MODEL_SHA256 == npu_model.KWS_TFLITE_SHA256
    assert setup_npu.VWW_MODEL_SHA256 == npu_model.VWW_TFLITE_SHA256


@pytest.mark.skipif(not (TINY / ".git").is_dir(), reason="locked Tiny source was not installed")
def test_vww_label_entries_shape() -> None:
    entries = setup_npu.vww_label_entries(TINY)
    assert len(entries) == 1000
    assert len({name for name, _ in entries}) == 1000
    assert sum(1 for _, label in entries if label == 1) == 500
    assert all(name.endswith(".bin") for name, _ in entries)


@pytest.mark.skipif(not (TINY / ".git").is_dir(), reason="locked Tiny source was not installed")
def test_setup_doctor_passes(tmp_path: Path) -> None:
    completed = subprocess.run(
        [
            sys.executable,
            str(ROOT / "scripts/setup_npu_reference.py"),
            "--build-dir",
            str(tmp_path),
            "--doctor",
        ],
        capture_output=True,
        text=True,
    )
    assert completed.returncode == 0, completed.stderr


def test_setup_doctor_reports_missing_assets(tmp_path: Path, monkeypatch: "pytest.MonkeyPatch") -> None:
    monkeypatch.setattr(setup_npu, "tiny_root", lambda: tmp_path / "absent-tiny")
    monkeypatch.setattr(setup_npu, "mfcc_root", lambda: tmp_path / "absent-mfcc")
    with pytest.raises(RuntimeError, match="missing NPU managed source"):
        setup_npu.doctor()
