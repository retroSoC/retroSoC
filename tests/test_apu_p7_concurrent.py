"""APU-P7 concurrent decode + continuous KWS zero-xrun smoke qualification."""

from __future__ import annotations

import json
import shutil
import subprocess
import sys
from pathlib import Path

import pytest


ROOT = Path(__file__).resolve().parents[1]
RUNNER = ROOT / "scripts" / "run_apu_p7_concurrent_rtl.py"
TFLITE = (
    ROOT
    / ".cache/retrosoc/sources/apu-mlperf-tiny/benchmark/training/keyword_spotting"
    / "trained_models/kws_ref_model.tflite"
)

REQUIRED_REPORT_KEYS = {
    "schema_version",
    "phase",
    "report",
    "status",
    "success",
    "git_revision",
    "git_dirty",
    "command",
    "seed",
    "profile",
    "inputs",
    "converter",
    "bam",
    "rtl_revision",
    "verification_sources",
    "simulator",
    "tools",
    "matrix",
    "scenarios",
    "aggregate_counts",
    "full_gate_projection",
    "artifacts",
    "errors",
}


def _apumc_bundle() -> Path | None:
    candidates = sorted(ROOT.glob("build/*/apu/p5/apu-p5.apumc"), key=lambda path: path.stat().st_mtime)
    return candidates[-1] if candidates else None


def test_apu_p7_concurrent_smoke(tmp_path: Path) -> None:
    missing_tools = [tool for tool in ("iverilog", "vvp", "sv2v") if shutil.which(tool) is None]
    if missing_tools:
        pytest.skip(f"APU-P7 concurrent smoke requires tools: {', '.join(missing_tools)}")
    if _apumc_bundle() is None:
        pytest.skip("APU-P5 bundle was not built (make CONFIG=configs/ci/ihp130.mk apu-p5-bundle)")
    if not TFLITE.is_file():
        pytest.skip("locked P7 model was not installed")

    build_dir = tmp_path / "concurrent"
    report = build_dir / "concurrent.json"
    completed = subprocess.run(
        [
            sys.executable,
            str(RUNNER),
            "--build-dir",
            str(build_dir),
            "--smoke",
            "--output",
            str(report),
        ],
        check=False,
        capture_output=True,
        text=True,
        timeout=1800,
    )
    assert completed.returncode == 0, (
        f"concurrent smoke failed:\n{completed.stdout[-2000:]}\n{completed.stderr[-2000:]}"
    )
    data = json.loads(report.read_text(encoding="utf-8"))
    assert REQUIRED_REPORT_KEYS <= set(data)
    assert data["status"] == "passed"
    assert data["success"] is True
    assert data["errors"] == []
    assert data["report"] == "concurrent"
    assert data["phase"] == "APU-P7"
    assert data["pclk_hz"] == 48_000_000
    assert data["inputs"]["apum"]["matches_locked_freeze"] is True
    assert len(data["scenarios"]) == len(data["matrix"]) >= 1
    for scenario in data["scenarios"]:
        assert scenario["status"] == "passed"
        result = scenario["result"]
        assert result["underrun"] == 0
        assert result["rx_overrun"] == 0
        assert result["kws_overrun"] == 0
        assert result["scoreboard"] == "match"
        assert result["wav_jobs"] >= 1
        assert result["flac_jobs"] >= 1
        assert result["tx_words"] == result["consumed"]
