"""Fail-closed APU-P9 evidence assembly and synthesis A/B coverage."""

from __future__ import annotations

import json
import subprocess
import sys
from copy import deepcopy
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))

import generate_apu_kws_rtl_constants as coefficient_generator  # noqa: E402
from apu_kws_convert import import_tflite  # noqa: E402


ROOT = Path(__file__).resolve().parents[1]
TFLITE = (
    ROOT
    / ".cache/retrosoc/sources/apu-mlperf-tiny/benchmark/training/keyword_spotting"
    / "trained_models/kws_ref_model.tflite"
)


def _write_json(path: Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value) + "\n", encoding="ascii")


def _variant(root: Path, *, baseline: bool) -> None:
    apu_path = "retrosoc_asic.u_retrosoc.u_apb4_periph.u_apb4_apu."
    modules = {
        f"\\fifo${apu_path}u_stream_fifo": {"num_memories": 1, "num_memory_bits": 60000},
    }
    if baseline:
        modules.update(
            {
                f"\\apu_kws_engine${apu_path}u_kws_engine": {
                    "num_memories": 18,
                    "num_memory_bits": 799680,
                },
                f"\\apu_microcode_loader${apu_path}u_microcode_loader": {
                    "num_memories": 2,
                    "num_memory_bits": 532480,
                },
            }
        )
    _write_json(root / "syn/yosys/rpt/retrosoc_asic_pre_memory.json", {"modules": modules})
    _write_json(
        root / "syn/yosys/rpt/retrosoc_asic_pre_tech.json",
        {
            "design": {
                "num_cells": 1200 if baseline else 600,
                "num_cells_by_type": {"$_DFF_P_": 400 if baseline else 180, "$_MUX_": 300 if baseline else 90},
            }
        },
    )
    _write_json(
        root / "syn/yosys/yosys-perf.json",
        {
            "generator": "Yosys 0.67",
            "total_ns": 100_000_000_000 if baseline else 60_000_000_000,
            "passes": {
                "memory": {"runtime_ns": 10_000_000_000 if baseline else 5_000_000_000},
                "opt_dff": {"runtime_ns": 70_000_000_000 if baseline else 10_000_000_000},
                **({} if baseline else {"abc": {"runtime_ns": 20_000_000_000}}),
            },
        },
    )
    _write_json(
        root / "syn/yosys/result-synth.json",
        {
            "status": "timed_out" if baseline else "passed",
            "exit_code": 124 if baseline else 0,
            "duration_seconds": 100 if baseline else 60,
            "peak_rss_kib": 1000 if baseline else 500,
        },
    )
    configuration = {"PDK": "IHP130", "APU_ENABLE_P7": "YES", "SYNTH": "YOSYS"}
    configuration["HAVE_SRAM_MACRO"] = "YES"
    revision = (
        "0b73994772068e5fac00fb1a98f87f88ed121cdf"
        if baseline
        else "1111111111111111111111111111111111111111"
    )
    _write_json(
        root / "meta/manifest.json",
        {
            "configuration": configuration,
            "dependency_lock": {"sha256": "abc"},
            "tools": {"yosys": "0.67"},
            "profile": "ihp130",
            "repository": {"commit": revision, "dirty": False},
        },
    )
    groups = {
        "u_control_store": 8,
        "u_local_sram": 12,
        "u_kws_sram_client": 16,
        "u_microcode_loader": 8,
        **({} if baseline else {"u_proof_memo": 17, "u_kws_coeff_store": 15}),
    }
    lines: list[str] = []
    for group, count in groups.items():
        for index in range(count):
            if group == "u_proof_memo":
                path = f"{apu_path}u_microcode_loader.{group}.u_mem_{index}"
            else:
                path = f"{apu_path}{group}.u_mem_{index}"
            lines.append(path)
    macro_path = root / "syn/yosys/rpt/retrosoc_asic_macros.rpt"
    macro_path.parent.mkdir(parents=True, exist_ok=True)
    macro_path.write_text("\n".join(lines) + "\n", encoding="ascii")


def test_apu_p9_memory_ab_requires_all_frozen_checks(tmp_path: Path) -> None:
    baseline = tmp_path / "baseline"
    candidate = tmp_path / "candidate"
    output = tmp_path / "memory-synthesis-ab.json"
    _variant(baseline, baseline=True)
    _variant(candidate, baseline=False)
    subprocess.run(
        [
            sys.executable,
            str(ROOT / "scripts/apu_p9_memory_ab.py"),
            "--baseline-root",
            str(baseline),
            "--candidate-root",
            str(candidate),
            "--output",
            str(output),
        ],
        check=True,
    )
    report = json.loads(output.read_text(encoding="ascii"))
    assert report["status"] == "passed"
    assert report["candidate"]["memory"]["target_bits"] == 0
    assert report["candidate"]["macros"]["apu_wrappers"] == 76
    assert all(report["checks"].values())

    assembled = tmp_path / "assembled"
    report_arguments: list[str] = []
    for name in (
        "coefficient-layout.json",
        "coefficient-lifecycle.json",
        "memo-equivalence.json",
        "numerical-latency.json",
        "memory-synthesis-ab.json",
        "physical.json",
    ):
        source = output if name == "memory-synthesis-ab.json" else tmp_path / name
        if source != output:
            _write_json(source, {"status": "unrun", "reason": "fixture intentionally unrun"})
        report_arguments.extend(("--report", f"{name}={source}"))
    subprocess.run(
        [
            sys.executable,
            str(ROOT / "scripts/apu_p9_evidence.py"),
            "assemble",
            *report_arguments,
            "--output-dir",
            str(assembled),
        ],
        check=True,
    )
    assert json.loads((assembled / "memory-synthesis-ab.json").read_text())["status"] == "passed"


def test_apu_p9_memory_ab_rejects_unqualified_revisions(tmp_path: Path) -> None:
    baseline = tmp_path / "baseline"
    candidate = tmp_path / "candidate"
    output = tmp_path / "memory-synthesis-ab.json"
    _variant(baseline, baseline=True)
    _variant(candidate, baseline=False)
    manifest = json.loads((candidate / "meta/manifest.json").read_text())
    manifest["repository"] = {"commit": "0b73994772068e5fac00fb1a98f87f88ed121cdf", "dirty": False}
    _write_json(candidate / "meta/manifest.json", manifest)
    result = subprocess.run(
        [
            sys.executable,
            str(ROOT / "scripts/apu_p9_memory_ab.py"),
            "--baseline-root",
            str(baseline),
            "--candidate-root",
            str(candidate),
            "--output",
            str(output),
        ],
        check=False,
    )
    assert result.returncode != 0
    assert json.loads(output.read_text())["checks"]["revision_qualified"] is False


def test_apu_p9_memory_ab_counts_new_storage_modules_as_targets(tmp_path: Path) -> None:
    baseline = tmp_path / "baseline"
    candidate = tmp_path / "candidate"
    output = tmp_path / "memory-synthesis-ab.json"
    _variant(baseline, baseline=True)
    _variant(candidate, baseline=False)
    inventory_path = candidate / "syn/yosys/rpt/retrosoc_asic_pre_memory.json"
    inventory = json.loads(inventory_path.read_text())
    apu_path = "retrosoc_asic.u_retrosoc.u_apb4_periph.u_apb4_apu."
    inventory["modules"][f"\\apu_proof_memo${apu_path}u_microcode_loader.u_proof_memo"] = {
        "num_memories": 1,
        "num_memory_bits": 32,
    }
    _write_json(inventory_path, inventory)
    result = subprocess.run(
        [
            sys.executable,
            str(ROOT / "scripts/apu_p9_memory_ab.py"),
            "--baseline-root",
            str(baseline),
            "--candidate-root",
            str(candidate),
            "--output",
            str(output),
        ],
        check=False,
    )
    assert result.returncode != 0
    report = json.loads(output.read_text())
    assert report["candidate"]["memory"]["target_bits"] == 32
    assert report["checks"]["target_inferred_bits_zero"] is False


def test_apu_p9_evidence_initialization_keeps_missing_runs_unrun(tmp_path: Path) -> None:
    layout = tmp_path / "layout.json"
    apuc_path = tmp_path / "apu-p9.apuc"
    output = tmp_path / "evidence"
    apuc, manifest = coefficient_generator.build_apuc(import_tflite(TFLITE))
    apuc_path.write_bytes(apuc)
    _write_json(layout, manifest)
    subprocess.run(
        [
            sys.executable,
            str(ROOT / "scripts/apu_p9_evidence.py"),
            "initialize",
            "--layout",
            str(layout),
            "--apuc",
            str(apuc_path),
            "--profile",
            str(ROOT / "configs/ci/ihp130.mk"),
            "--output-dir",
            str(output),
        ],
        check=True,
    )
    assert json.loads((output / "coefficient-layout.json").read_text())["status"] == "passed"
    assert json.loads((output / "memory-synthesis-ab.json").read_text())["status"] == "unrun"


def test_apu_p9_evidence_rejects_incomplete_passed_reports(tmp_path: Path) -> None:
    reports = tmp_path / "reports"
    output = tmp_path / "evidence"
    sources: list[str] = []
    for name in (
        "coefficient-layout.json",
        "coefficient-lifecycle.json",
        "memo-equivalence.json",
        "numerical-latency.json",
        "memory-synthesis-ab.json",
        "physical.json",
    ):
        source = reports / name
        _write_json(source, {"status": "passed"})
        sources.extend(("--report", f"{name}={source}"))
    result = subprocess.run(
        [
            sys.executable,
            str(ROOT / "scripts/apu_p9_evidence.py"),
            "assemble",
            *sources,
            "--output-dir",
            str(output),
        ],
        text=True,
        capture_output=True,
        check=False,
    )
    assert result.returncode != 0
    assert "coefficient-layout.json" in result.stderr


def test_apu_p9_evidence_rejects_stale_layout_mapping(tmp_path: Path) -> None:
    layout = tmp_path / "layout.json"
    apuc_path = tmp_path / "apu-p9.apuc"
    output = tmp_path / "evidence"
    apuc, manifest = coefficient_generator.build_apuc(import_tflite(TFLITE))
    stale = deepcopy(manifest)
    stale["tables"]["log"]["locations"][1024] = [0, 0]
    apuc_path.write_bytes(apuc)
    _write_json(layout, stale)
    result = subprocess.run(
        [
            sys.executable,
            str(ROOT / "scripts/apu_p9_evidence.py"),
            "initialize",
            "--layout",
            str(layout),
            "--apuc",
            str(apuc_path),
            "--profile",
            str(ROOT / "configs/ci/ihp130.mk"),
            "--output-dir",
            str(output),
        ],
        text=True,
        capture_output=True,
        check=False,
    )
    assert result.returncode != 0
    assert "independent map/hash oracle" in result.stderr
