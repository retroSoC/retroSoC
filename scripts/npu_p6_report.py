#!/usr/bin/env python3
"""Validate and assemble fail-closed NPU-P6 V015..V018 evidence."""

from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
REJECTED = ("FAILED", "FATAL", "assertion failed", "%Error", "SIM_TEST_FAIL", "SIM_TEST_TIMEOUT")


def load(path: Path) -> dict[str, Any]:
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise ValueError(f"evidence is not an object: {path}")
    return data


def identity(path: Path) -> dict[str, object]:
    payload = path.read_bytes()
    return {
        "path": str(path.resolve()),
        "bytes": len(payload),
        "sha256": hashlib.sha256(payload).hexdigest(),
    }


def require_pass(path: Path, *, phase: str | None = None) -> dict[str, Any]:
    data = load(path)
    status = data.get("verdict", data.get("status"))
    if status not in ("PASS", "passed"):
        raise ValueError(f"required evidence did not pass: {path}")
    if phase is not None and data.get("phase") != phase:
        raise ValueError(f"required evidence has wrong phase: {path}")
    summary = data.get("summary", {})
    if data.get("skipped", 0) or (isinstance(summary, dict) and summary.get("skipped", 0)):
        raise ValueError(f"required evidence contains skipped cases: {path}")
    return data


def validate_identity(record: dict[str, Any]) -> None:
    path = Path(record.get("path", ""))
    if not path.is_file():
        raise ValueError(f"missing retained P6 artifact: {path}")
    actual = identity(path)
    if actual["bytes"] != record.get("bytes") or actual["sha256"] != record.get("sha256"):
        raise ValueError(f"retained P6 artifact identity changed: {path}")


def validate_implementation(data: dict[str, Any], label: str) -> None:
    implementation = data.get("implementation")
    if not isinstance(implementation, dict) or not implementation:
        raise ValueError(f"{label} evidence lacks implementation identities")
    for name, record in implementation.items():
        relative = Path(name)
        if relative.is_absolute() or ".." in relative.parts:
            raise ValueError(f"{label} implementation path is not repository-relative: {name}")
        expected = (ROOT / relative).resolve()
        if Path(record.get("path", "")).resolve() != expected:
            raise ValueError(f"{label} implementation path changed: {name}")
        validate_identity(record)


def validate_corpus(path: Path) -> dict[str, Any]:
    data = require_pass(path, phase="NPU-P6")
    workloads = data.get("workloads")
    if data.get("schema") != 2 or not isinstance(workloads, dict) or set(workloads) != {"kws", "vww"}:
        raise ValueError("P6 corpus report has the wrong schema or workload set")
    for workload, record in workloads.items():
        shards = record.get("shards") if isinstance(record, dict) else None
        if (
            record.get("case_count") != 1000
            or record.get("cases_per_shard") != 100
            or record.get("shard_count") != 10
            or not isinstance(shards, list)
            or len(shards) != 10
        ):
            raise ValueError(f"{workload} corpus report is incomplete")
        for shard_index, shard in enumerate(shards):
            cases = shard.get("cases")
            expected = list(range(shard_index * 100, (shard_index + 1) * 100))
            if (
                shard.get("index") != shard_index
                or shard.get("first_case") != expected[0]
                or shard.get("case_count") != 100
                or not isinstance(cases, list)
                or [case.get("index") for case in cases] != expected
            ):
                raise ValueError(f"{workload} corpus shard {shard_index} changed")
            validate_identity(shard["file"])
            if any(
                set(case) != {
                    "index",
                    "name",
                    "label",
                    "input_sha256",
                    "terminal_sha256",
                    "softmax_sha256",
                }
                for case in cases
            ):
                raise ValueError(f"{workload} corpus shard {shard_index} case schema changed")
    return data


def validate_performance(path: Path) -> dict[str, Any]:
    data = require_pass(path, phase="NPU-P6")
    if data.get("verification_ids") != ["NPU-V016"]:
        raise ValueError("P6 performance verification IDs changed")
    workloads = data.get("workloads")
    if not isinstance(workloads, dict) or set(workloads) != {"kws", "vww"}:
        raise ValueError("P6 performance report must contain KWS and VWW")
    for name, record in workloads.items():
        cases = record.get("cases") if isinstance(record, dict) else None
        if not isinstance(cases, list) or len(cases) != 1000:
            raise ValueError(f"{name} performance report must contain 1000 cases")
        if [case.get("index") for case in cases] != list(range(1000)):
            raise ValueError(f"{name} performance cases are incomplete or reordered")
        for case in cases:
            index = case.get("index")
            expected_cache = "cold" if index % 100 == 0 else "steady"
            expected_contention = "ga2d-copy-32x32768-rgb565" if index < 10 else "none"
            if (
                case.get("status") != "PASS"
                or case.get("reference_cycles", 0) <= 0
                or case.get("npu_cycles", 0) <= 0
                or case.get("npu_cycles")
                != case.get("npu_wait_cycles", -1) + case.get("softmax_cycles", -1)
                or case.get("reference_class") != case.get("npu_class")
                or case.get("cache") != expected_cache
                or case.get("contention") != expected_contention
            ):
                raise ValueError(f"{name} performance case failed or has invalid cycles")
        reference = sum(case["reference_cycles"] for case in cases)
        npu = sum(case["npu_cycles"] for case in cases)
        speedup = reference / npu
        if abs(float(record.get("speedup", 0.0)) - speedup) > 1e-9 or speedup < 2.0:
            raise ValueError(f"{name} does not satisfy the 2.0-times P6 target")
        if record.get("skipped", 0) or record.get("mismatches", 0):
            raise ValueError(f"{name} contains skipped or mismatching cases")
        comparison = record.get("compiler_comparison")
        metrics = comparison.get("metrics") if isinstance(comparison, dict) else None
        counter_names = {
            "active_cycles",
            "dma_read_bytes",
            "dma_write_bytes",
            "useful_macs",
            "pack_cycles",
            "retired_descriptors",
        }
        if (
            not isinstance(comparison, dict)
            or comparison.get("material_threshold_percent") != 10
            or not isinstance(comparison.get("cycle_model"), str)
            or not comparison["cycle_model"]
            or not isinstance(metrics, dict)
            or set(metrics) != counter_names
        ):
            raise ValueError(f"{name} compiler comparison is incomplete")
        validate_identity(comparison["artifact"])
        for counter_name in counter_names:
            metric = metrics[counter_name]
            expected_per_inference = metric.get("estimated_per_inference", 0)
            expected_total = expected_per_inference * len(cases)
            measured_total = sum(case[counter_name] for case in cases)
            ratio = measured_total / expected_total if expected_total > 0 else 0.0
            material = abs(ratio - 1.0) > 0.10
            if (
                not isinstance(expected_per_inference, int)
                or expected_per_inference <= 0
                or metric.get("expected_total") != expected_total
                or metric.get("measured_total") != measured_total
                or abs(float(metric.get("measured_mean", 0.0)) - (measured_total / len(cases)))
                > 1e-9
                or abs(float(metric.get("measured_to_estimated_ratio", 0.0)) - ratio) > 1e-9
                or metric.get("material_difference") is not material
                or not isinstance(metric.get("explanation"), str)
                or not metric["explanation"]
            ):
                raise ValueError(f"{name} compiler comparison changed for {counter_name}")
    return data


def validate_log(path: Path, required: tuple[str, ...]) -> None:
    text = path.read_text(encoding="utf-8", errors="replace")
    if any(marker not in text for marker in required) or any(marker in text for marker in REJECTED):
        raise ValueError(f"P6 log markers failed: {path}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--p0-report", type=Path, required=True)
    parser.add_argument("--p5-report", type=Path, required=True)
    parser.add_argument("--corpus-report", type=Path, required=True)
    parser.add_argument("--performance-report", type=Path, required=True)
    parser.add_argument("--formal-report", type=Path, required=True)
    parser.add_argument("--netlist-report", type=Path, required=True)
    parser.add_argument("--physical-report", type=Path, required=True)
    parser.add_argument("--regression-report", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    revision = subprocess.check_output(["git", "-C", str(ROOT), "rev-parse", "HEAD"], text=True).strip()
    p0 = require_pass(args.p0_report, phase="NPU-P0")
    p5 = require_pass(args.p5_report, phase="NPU-P5")
    corpus = validate_corpus(args.corpus_report)
    performance = validate_performance(args.performance_report)
    formal = require_pass(args.formal_report, phase="NPU-P6")
    netlist = require_pass(args.netlist_report, phase="NPU-P6")
    physical = require_pass(args.physical_report, phase="NPU-P6")
    regression = require_pass(args.regression_report, phase="NPU-P6")
    expected_ids = {
        "formal": ["NPU-V015"],
        "netlist": ["NPU-V017", "NPU-V018"],
        "physical": ["NPU-V017"],
        "regression": ["NPU-V018"],
    }
    for name, data in (
        ("formal", formal),
        ("netlist", netlist),
        ("physical", physical),
        ("regression", regression),
    ):
        if data.get("verification_ids") != expected_ids[name]:
            raise ValueError(f"{name} evidence has the wrong verification IDs")
    if netlist.get("physical_reused") or physical.get("product_reused"):
        raise ValueError("P6 aggregate report requires fresh physical and netlist flows")
    for name, data in (
        ("p0", p0),
        ("p5", p5),
        ("corpus", corpus),
        ("performance", performance),
        ("formal", formal),
        ("netlist", netlist),
        ("physical", physical),
        ("regression", regression),
    ):
        evidence_revision = data.get("git_revision", data.get("provenance", {}).get("git_revision"))
        if evidence_revision != revision:
            raise ValueError(f"{name} evidence revision {evidence_revision!r} != {revision}")
        if name not in {"p0", "p5"}:
            validate_implementation(data, name)
    if corpus.get("summary") != {"cases": 2000, "skipped": 0}:
        raise ValueError("P6 corpus report is incomplete")
    report = {
        "schema": 1,
        "phase": "NPU-P6",
        "verification_ids": ["NPU-V015", "NPU-V016", "NPU-V017", "NPU-V018"],
        "git_revision": revision,
        "evidence": {
            name: identity(path)
            for name, path in (
                ("p0", args.p0_report), ("p5", args.p5_report),
                ("corpus", args.corpus_report), ("performance", args.performance_report),
                ("formal", args.formal_report), ("netlist", args.netlist_report),
                ("physical", args.physical_report), ("regression", args.regression_report),
            )
        },
        "performance": performance["workloads"],
        "implementation": {
            "scripts/npu_p6_report.py": identity(ROOT / "scripts/npu_p6_report.py")
        },
        "maturity": {
            "functional": "qualified",
            "performance": "qualified",
            "physical_integration": "qualified",
            "rtl_readiness": "prototype_metadata_verified",
            "fpga": "NOT_RUN_OPTIONAL",
            "silicon": "NOT_RUN",
        },
        "remaining_commercial_gaps": [
            "post-layout extracted MMMC/PVT closure",
            "qualified CDC/RDC signoff",
            "DFT, scan, MBIST and SRAM repair",
            "power and activity characterization",
            "optional FPGA/board characterization",
            "silicon characterization",
        ],
        "summary": {"required_checks": 8, "passes": 8, "failures": 0, "skipped": 0},
        "verdict": "PASS",
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"NPU-P6 qualification: PASS ({args.output})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
