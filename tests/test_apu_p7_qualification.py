"""Smoke test for the APU-P7 KWS through-hardware accuracy qualification runner."""

from __future__ import annotations

import json
import shutil
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
RUNNER = ROOT / "scripts/run_apu_p7_kws_rtl.py"
CACHE_INPUTS = (
    ROOT / ".cache/retrosoc/sources/apu-kws-pcm",
    ROOT / ".cache/retrosoc/sources/apu-kws-mfcc/datasets/kws01/y_labels.csv",
    ROOT
    / ".cache/retrosoc/sources/apu-mlperf-tiny/benchmark/training/keyword_spotting"
    / "trained_models/kws_ref_model.tflite",
)
# Icarus needs ~7 minutes per window on this engine; keep the smoke short there.
SMOKE_WINDOWS = 4 if shutil.which("verilator") is not None else 1
REQUIRED_KEYS = (
    "schema_version",
    "report",
    "target",
    "profile",
    "success",
    "gate",
    "seed",
    "command",
    "counts",
    "per_class",
    "incorrect_indices",
    "predictions",
    "inputs",
    "converter",
    "reference",
    "rtl",
    "model",
    "rom",
    "tools",
    "simulation",
    "artifacts",
)


def test_apu_p7_accuracy_runner_smoke(tmp_path: Path) -> None:
    if any(shutil.which(tool) is None for tool in ("iverilog", "vvp", "sv2v")):
        return
    if any(not path.exists() for path in CACHE_INPUTS):
        return
    build_dir = tmp_path / "apu-kws"
    result = subprocess.run(
        [
            sys.executable,
            str(RUNNER),
            "--build-dir",
            str(build_dir),
            "--max-windows",
            str(SMOKE_WINDOWS),
        ],
        check=False,
        capture_output=True,
        text=True,
        timeout=1800,
    )
    assert result.returncode == 0, result.stdout + result.stderr
    report_path = build_dir / "accuracy.json"
    assert report_path.is_file()
    report = json.loads(report_path.read_text(encoding="utf-8"))
    for key in REQUIRED_KEYS:
        assert key in report, f"accuracy.json is missing required key {key}"
    assert report["report"] == "accuracy"
    assert report["target"] == "p7"
    assert report["success"] is True
    assert report["gate"]["applies"] is False
    assert report["counts"]["windows_requested"] == SMOKE_WINDOWS
    assert report["counts"]["windows_completed"] == SMOKE_WINDOWS
    assert len(report["per_class"]) == 12
    assert sum(item["total"] for item in report["per_class"]) == SMOKE_WINDOWS
    predictions = report["predictions"]
    assert [item["index"] for item in predictions] == list(range(SMOKE_WINDOWS))
    assert all(0 <= item["predicted"] < 12 for item in predictions)
    assert all(0 <= item["score"] <= 255 for item in predictions)
    assert all(item["hit"] in (0, 1) for item in predictions)
    assert report["model"]["apum_sha256"] == report["model"]["frozen_sha256"]
