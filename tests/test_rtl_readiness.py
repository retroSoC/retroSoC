from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts/check_rtl_readiness.py"


def run_readiness(tmp_path: Path, document: dict[str, object]) -> subprocess.CompletedProcess[str]:
    (tmp_path / "rtl/ip").mkdir(parents=True)
    (tmp_path / "rtl/mini/top").mkdir(parents=True)
    (tmp_path / "rtl/ip/readiness.sv").write_text("module readiness; endmodule\n", encoding="utf-8")
    (tmp_path / "rtl/rtl_readiness.json").write_text(
        json.dumps(document), encoding="utf-8"
    )
    return subprocess.run(
        [sys.executable, str(SCRIPT), "--root", str(tmp_path)],
        text=True,
        capture_output=True,
        check=False,
    )


def target(status: str = "prototype") -> dict[str, object]:
    return {
        "name": "test",
        "paths": ["rtl/ip"],
        "status": status,
        "configuration_profiles": ["test"],
        "required_evidence": [],
        "synthesis_intent": {
            "registers": "common register",
            "reset": "active low",
            "clock_enable": "explicit",
            "memory": "infer",
            "pipeline": "documented",
        },
        "waivers": [],
    }


def test_prototype_record_is_valid(tmp_path: Path) -> None:
    result = run_readiness(tmp_path, {"schema_version": 1, "targets": [target()]})
    assert result.returncode == 0, result.stderr


def test_rtl_freeze_requires_baseline_and_digest(tmp_path: Path) -> None:
    result = run_readiness(tmp_path, {"schema_version": 1, "targets": [target("rtl-freeze")]})
    assert result.returncode == 1
    assert "baseline_revision" in result.stderr
    assert "configuration_digest" in result.stderr
    assert "equivalence" in result.stderr


def test_tapeout_requires_all_signoff_evidence(tmp_path: Path) -> None:
    result = run_readiness(tmp_path, {"schema_version": 1, "targets": [target("tapeout-ready")]})
    assert result.returncode == 1
    assert "cdc" in result.stderr
    assert "release" in result.stderr
    assert "warning" in result.stderr


def test_verified_accepts_existing_evidence(tmp_path: Path) -> None:
    evidence = tmp_path / "evidence.json"
    evidence.write_text("{}\n", encoding="utf-8")
    record = target("verified")
    record["required_evidence"] = [
        {"kind": kind, "path": "evidence.json"}
        for kind in ("format", "lint", "simulation", "synthesis")
    ]
    result = run_readiness(tmp_path, {"schema_version": 1, "targets": [record]})
    assert result.returncode == 0, result.stderr


def test_target_selection_rejects_unknown_target(tmp_path: Path) -> None:
    document = {"schema_version": 1, "targets": [target()]}
    (tmp_path / "rtl/ip").mkdir(parents=True)
    (tmp_path / "rtl/mini/top").mkdir(parents=True)
    (tmp_path / "rtl/ip/readiness.sv").write_text("module readiness; endmodule\n", encoding="utf-8")
    (tmp_path / "rtl/rtl_readiness.json").write_text(
        json.dumps(document), encoding="utf-8"
    )
    result = subprocess.run(
        [sys.executable, str(SCRIPT), "--root", str(tmp_path), "--target", "missing"],
        text=True,
        capture_output=True,
        check=False,
    )
    assert result.returncode == 1
    assert "target not found" in result.stderr
