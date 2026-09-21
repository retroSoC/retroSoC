#!/usr/bin/env python3
"""Run complete NPU-P6 corpora on the PRODUCT Verilator HP model."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import re
import shutil
import subprocess
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
CONFIG = ROOT / "configs/ci/ihp130.mk"
REJECTED = re.compile(
    r"(?:\bFAIL(?:ED)?\b|\bFATAL\b|assertion failed|%Error|SIM_TEST_FAIL|SIM_TEST_TIMEOUT)",
    re.IGNORECASE,
)
CASE_PREFIX = "NPU_P6_CASE "
INTEGER_FIELDS = {
    "shard",
    "index",
    "label",
    "reference_cycles",
    "npu_cycles",
    "input_copy_cycles",
    "npu_wait_cycles",
    "softmax_cycles",
    "active_cycles",
    "clock_pause_cycles",
    "useful_macs",
    "pack_cycles",
    "bank_stall_cycles",
    "dma_read_bytes",
    "dma_write_bytes",
    "dma_stall_cycles",
    "requant_stall_cycles",
    "retired_descriptors",
    "reference_class",
    "npu_class",
}
REQUIRED_FIELDS = INTEGER_FIELDS | {"workload", "cache", "contention", "status"}


def identity(path: Path) -> dict[str, object]:
    data = path.read_bytes()
    return {
        "path": str(path.resolve()),
        "bytes": len(data),
        "sha256": hashlib.sha256(data).hexdigest(),
    }


def run(command: list[str], *, timeout: int | None = None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        command,
        cwd=ROOT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=timeout,
        check=False,
        env={**os.environ, "CCACHE_DISABLE": "1"},
    )


def make_command(workload: str, timestamp: str, *targets: str) -> list[str]:
    return [
        "make",
        f"CONFIG={CONFIG}",
        "APP=hp_boot",
        "SIMU=VERILATOR",
        "NPU_P6_ACCEPTANCE=YES",
        f"NPU_P6_WORKLOAD={workload}",
        f"BUILD_TIMESTAMP={timestamp}",
        *targets,
    ]


def variant_root(workload: str, timestamp: str) -> Path:
    completed = run(make_command(workload, timestamp, "-s", "config"))
    if completed.returncode != 0:
        raise RuntimeError(f"failed to resolve P6 {workload} variant\n{completed.stdout}")
    match = re.search(r"(?m)^VARIANT_ROOT\s+(.+)$", completed.stdout)
    if match is None:
        raise ValueError(f"P6 {workload} config omitted VARIANT_ROOT")
    return Path(match.group(1)).resolve()


def build_variants(timestamp: str, log_dir: Path) -> dict[str, Path]:
    roots = {workload: variant_root(workload, timestamp) for workload in ("kws", "vww")}
    for workload in ("kws", "vww"):
        targets = ["manifest", "hp-smoke-bundle"]
        if workload == "kws":
            targets.append("comp")
        completed = run(make_command(workload, timestamp, *targets))
        log = log_dir / f"build-{workload}.log"
        log.parent.mkdir(parents=True, exist_ok=True)
        log.write_text(completed.stdout, encoding="utf-8")
        if completed.returncode != 0:
            raise RuntimeError(f"P6 {workload} build failed: {log}")
    return roots


def parse_case_line(line: str) -> dict[str, Any]:
    if not line.startswith(CASE_PREFIX):
        raise ValueError("not an NPU-P6 case record")
    fields: dict[str, Any] = {}
    for token in line[len(CASE_PREFIX) :].split():
        name, separator, value = token.partition("=")
        if not separator or not name or name in fields:
            raise ValueError(f"malformed NPU-P6 case token: {token}")
        fields[name] = int(value, 0) if name in INTEGER_FIELDS else value
    if set(fields) != REQUIRED_FIELDS:
        missing = sorted(REQUIRED_FIELDS - set(fields))
        extra = sorted(set(fields) - REQUIRED_FIELDS)
        raise ValueError(f"NPU-P6 case fields changed: missing={missing}, extra={extra}")
    if fields["status"] != "PASS":
        raise ValueError("NPU-P6 firmware reported a failed case")
    if fields["npu_cycles"] != fields["npu_wait_cycles"] + fields["softmax_cycles"]:
        raise ValueError("NPU-P6 total does not match wait plus Softmax cycles")
    return fields


def parse_log(path: Path, workload: str, shard_index: int) -> list[dict[str, Any]]:
    content = path.read_text(encoding="utf-8", errors="replace")
    required = (
        "SIM_TEST_PASS code=0",
        "HP_NPU_P6_PASS",
        f"NPU_P6_SHARD_PASS workload={workload} shard={shard_index} cases=100",
    )
    rejected = REJECTED.search(content)
    if any(marker not in content for marker in required) or rejected is not None:
        raise ValueError(f"P6 simulator markers failed: {path}")
    cases = [parse_case_line(line) for line in content.splitlines() if line.startswith(CASE_PREFIX)]
    expected = list(range(shard_index * 100, (shard_index + 1) * 100))
    if len(cases) != 100 or [case["index"] for case in cases] != expected:
        raise ValueError(f"P6 {workload} shard {shard_index} is incomplete or reordered")
    if any(case["workload"] != workload or case["shard"] != shard_index for case in cases):
        raise ValueError(f"P6 {workload} shard {shard_index} record identity changed")
    for offset, case in enumerate(cases):
        expected_cache = "cold" if offset == 0 else "steady"
        expected_contention = "ga2d-copy-32x32768-rgb565" if case["index"] < 10 else "none"
        if case["cache"] != expected_cache or case["contention"] != expected_contention:
            raise ValueError(f"P6 case policy changed: {workload}/{case['index']}")
        if case["reference_cycles"] <= 0 or case["npu_cycles"] <= 0:
            raise ValueError(f"P6 case has a nonpositive cycle interval: {workload}/{case['index']}")
        if case["reference_class"] != case["npu_class"]:
            raise ValueError(f"P6 classification mismatch: {workload}/{case['index']}")
    return cases


def package_shard(
    workload: str,
    shard: dict[str, Any],
    variant: Path,
    output: Path,
) -> tuple[Path, Path]:
    shard_index = int(shard["index"])
    shard_dir = output / workload / f"shard-{shard_index:03d}"
    images = shard_dir / "images"
    images.mkdir(parents=True, exist_ok=True)
    shutil.copy2(variant / "hp-smoke/images/fw_jump.bin", images / "fw_jump.bin")
    shutil.copy2(Path(shard["file"]["path"]), images / "Image")
    (images / "retrosoc_hp.dtb").write_bytes(b"SMOK")
    (images / "rootfs.cpio.gz").write_bytes(b"SMOK")
    bundle = shard_dir / "retrosoc_npu_p6.bin"
    manifest = shard_dir / "bundle.json"
    completed = run(
        [
            "python3",
            str(ROOT / "scripts/package_hp_boot.py"),
            "--firmware",
            str(variant / "sw/retrosoc_fw.bin"),
            "--images",
            str(images),
            "--output",
            str(bundle),
            "--manifest",
            str(manifest),
        ]
    )
    if completed.returncode != 0:
        raise RuntimeError(f"failed to package P6 {workload} shard {shard_index}\n{completed.stdout}")
    return bundle, manifest


def simulate_shard(
    workload: str,
    shard: dict[str, Any],
    variant: Path,
    emulator: Path,
    output: Path,
    sim_time: int,
    timeout: int,
) -> dict[str, Any]:
    shard_index = int(shard["index"])
    bundle, bundle_manifest = package_shard(workload, shard, variant, output)
    shard_dir = bundle.parent
    log = shard_dir / "sim.log"
    command = [str(emulator), "-i", str(bundle), "--fast-flash", "-t", str(sim_time)]
    started = time.monotonic()
    try:
        with log.open("w", encoding="utf-8") as stream:
            completed = subprocess.run(
                command,
                cwd=shard_dir,
                text=True,
                stdout=stream,
                stderr=subprocess.STDOUT,
                timeout=timeout,
                check=False,
            )
    except subprocess.TimeoutExpired as error:
        raise RuntimeError(f"P6 {workload} shard {shard_index} timed out: {log}") from error
    if completed.returncode != 0:
        raise RuntimeError(f"P6 {workload} shard {shard_index} failed: {log}")
    cases = parse_log(log, workload, shard_index)
    return {
        "index": shard_index,
        "first_case": int(shard["first_case"]),
        "case_count": int(shard["case_count"]),
        "command": command,
        "host_seconds": time.monotonic() - started,
        "bundle": identity(bundle),
        "bundle_manifest": identity(bundle_manifest),
        "log": identity(log),
        "cases": cases,
        "status": "PASS",
    }


def percentile(values: list[int], percentage: float) -> int:
    ordered = sorted(values)
    return ordered[max(0, math.ceil(len(ordered) * percentage) - 1)]


def load_compiler_estimate(variant: Path, workload: str) -> dict[str, Any]:
    manifest = variant / f"npu/p5/deployments/{workload}/npu.json"
    deployment = json.loads(manifest.read_text(encoding="utf-8"))
    compiler_report = deployment.get("report")
    if not isinstance(compiler_report, dict):
        raise ValueError(f"P6 {workload} deployment omits the compiler report")
    totals = compiler_report.get("totals")
    operators = compiler_report.get("operators")
    if not isinstance(totals, dict) or not isinstance(operators, list):
        raise ValueError(f"P6 {workload} compiler report is incomplete")
    values = {
        "active_cycles": totals.get("estimated_cycles"),
        "dma_read_bytes": totals.get("dma_read_bytes"),
        "dma_write_bytes": totals.get("dma_write_bytes"),
        "useful_macs": totals.get("useful_macs"),
        "pack_cycles": sum(
            operator.get("pack_cycles", 0)
            for operator in operators
            if isinstance(operator, dict) and operator.get("placement") == "npu"
        ),
        "retired_descriptors": totals.get("descriptors"),
    }
    if any(not isinstance(value, int) or value <= 0 for value in values.values()):
        raise ValueError(f"P6 {workload} compiler estimates must be positive integers")
    cycle_model = compiler_report.get("cycle_model")
    if not isinstance(cycle_model, str) or not cycle_model:
        raise ValueError(f"P6 {workload} compiler report omits its cycle model")
    return {
        "artifact": identity(manifest),
        "cycle_model": cycle_model,
        "per_inference": values,
    }


def compare_compiler_estimates(
    estimate: dict[str, Any], counter_totals: dict[str, int], case_count: int
) -> dict[str, Any]:
    comparisons = {}
    for name, expected_per_inference in estimate["per_inference"].items():
        measured_total = counter_totals[name]
        expected_total = expected_per_inference * case_count
        ratio = measured_total / expected_total
        material = abs(ratio - 1.0) > 0.10
        if not material:
            explanation = "measured value is within 10 percent of the compiler estimate"
        elif name == "active_cycles":
            explanation = (
                "the compiler uses an analytical no-overlap cycle model; measured active cycles "
                "include implemented scheduling, transfer handshakes, packing, requantization, "
                "and recorded RTL stalls"
            )
        elif name in {"dma_read_bytes", "dma_write_bytes"}:
            explanation = (
                "measured DMA traffic includes the implemented edge, reload, and descriptor "
                "transactions while the compiler estimate follows its static traffic model"
            )
        else:
            explanation = (
                "the measured hardware counter differs materially from the compiler's static "
                "operator accounting and requires review before a qualification claim"
            )
        comparisons[name] = {
            "estimated_per_inference": expected_per_inference,
            "expected_total": expected_total,
            "measured_total": measured_total,
            "measured_mean": measured_total / case_count,
            "measured_to_estimated_ratio": ratio,
            "material_difference": material,
            "explanation": explanation,
        }
    return {
        "artifact": estimate["artifact"],
        "cycle_model": estimate["cycle_model"],
        "material_threshold_percent": 10,
        "metrics": comparisons,
    }


def summarize_workload(
    workload: str, shards: list[dict[str, Any]], estimate: dict[str, Any]
) -> dict[str, Any]:
    ordered_shards = sorted(shards, key=lambda record: record["index"])
    cases = [case for shard in ordered_shards for case in shard["cases"]]
    if len(cases) != 1000 or [case["index"] for case in cases] != list(range(1000)):
        raise ValueError(f"P6 {workload} corpus is incomplete or reordered")
    reference = [case["reference_cycles"] for case in cases]
    npu = [case["npu_cycles"] for case in cases]
    speedup = sum(reference) / sum(npu)
    uncontended = [case for case in cases if case["contention"] == "none"]
    contended = [case for case in cases if case["contention"] != "none"]
    counter_totals = {
        name: sum(case[name] for case in cases)
        for name in (
            "active_cycles",
            "clock_pause_cycles",
            "useful_macs",
            "pack_cycles",
            "bank_stall_cycles",
            "dma_read_bytes",
            "dma_write_bytes",
            "dma_stall_cycles",
            "requant_stall_cycles",
            "retired_descriptors",
        )
    }
    return {
        "case_count": len(cases),
        "mismatches": 0,
        "skipped": 0,
        "reference_cycles": sum(reference),
        "npu_cycles": sum(npu),
        "speedup": speedup,
        "target_speedup": 2.0,
        "meets_target": speedup >= 2.0,
        "reference_median_cycles": percentile(reference, 0.5),
        "reference_p99_cycles": percentile(reference, 0.99),
        "npu_median_cycles": percentile(npu, 0.5),
        "npu_p99_cycles": percentile(npu, 0.99),
        "npu_median_latency_ms_72mhz": percentile(npu, 0.5) / 72_000.0,
        "npu_p99_latency_ms_72mhz": percentile(npu, 0.99) / 72_000.0,
        "cache_policy": {"cold_cases": 10, "steady_cases": 990},
        "contention": {
            "master": "GA2D private DMA, 32x32768 RGB565 copy",
            "cases": len(contended),
            "uncontended_cases": len(uncontended),
            "reference_cycles": sum(case["reference_cycles"] for case in contended),
            "npu_cycles": sum(case["npu_cycles"] for case in contended),
        },
        "counter_totals": counter_totals,
        "compiler_comparison": compare_compiler_estimates(estimate, counter_totals, len(cases)),
        "shards": [{key: value for key, value in shard.items() if key != "cases"} for shard in ordered_shards],
        "cases": cases,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--corpus-report", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--build-timestamp", default=datetime.now().astimezone().strftime("%Y-%m-%d-%H-%M"))
    parser.add_argument("--jobs", type=int, default=2)
    parser.add_argument("--timeout-seconds", type=int, default=86400)
    parser.add_argument("--sim-time", type=int, default=86400)
    args = parser.parse_args()
    if args.jobs <= 0 or args.timeout_seconds <= 0 or args.sim_time <= 0:
        parser.error("jobs, timeout and simulation time must be positive")
    corpus = json.loads(args.corpus_report.read_text(encoding="utf-8"))
    workloads = corpus.get("workloads")
    if corpus.get("verdict") != "PASS" or not isinstance(workloads, dict):
        raise ValueError("P6 corpus shard report did not pass")
    output = args.output_dir.resolve()
    output.mkdir(parents=True, exist_ok=True)
    variants = build_variants(args.build_timestamp, output / "build-logs")
    emulator = variants["kws"] / "sim/verilator/emu"
    if not emulator.is_file():
        raise ValueError("P6 PRODUCT Verilator emulator is missing")
    records: dict[str, list[dict[str, Any]]] = {"kws": [], "vww": []}
    futures = []
    with ThreadPoolExecutor(max_workers=args.jobs) as executor:
        for workload in ("kws", "vww"):
            workload_record = workloads.get(workload)
            shards = workload_record.get("shards") if isinstance(workload_record, dict) else None
            if not isinstance(shards, list) or len(shards) != 10:
                raise ValueError(f"P6 {workload} requires exactly ten shards")
            for shard in shards:
                futures.append(
                    executor.submit(
                        simulate_shard,
                        workload,
                        shard,
                        variants[workload],
                        emulator,
                        output / "runs",
                        args.sim_time,
                        args.timeout_seconds,
                    )
                )
        for future in as_completed(futures):
            record = future.result()
            workload = record["cases"][0]["workload"]
            records[workload].append(record)
    estimates = {
        workload: load_compiler_estimate(variants[workload], workload)
        for workload in ("kws", "vww")
    }
    summaries = {
        workload: summarize_workload(workload, records[workload], estimates[workload])
        for workload in ("kws", "vww")
    }
    passes = all(record["meets_target"] for record in summaries.values())
    report = {
        "schema": 1,
        "phase": "NPU-P6",
        "verification_ids": ["NPU-V016"],
        "git_revision": subprocess.check_output(
            ["git", "-C", str(ROOT), "rev-parse", "HEAD"], text=True
        ).strip(),
        "profile": "configs/ci/ihp130.mk",
        "configuration": {
            "MINI_MODE": "PRODUCT",
            "APP": "hp_boot",
            "SIMU": "VERILATOR",
            "HP_CONFIG": "rv32imafdc_zicbom_max",
            "EXT_CLK_HZ": 72_000_000,
        },
        "measurement": {
            "counter": "HP rdcycle",
            "reference": "portable INT8 C through CPU Softmax",
            "npu": "submit, production private DMA, synchronization, wait, CPU Softmax",
            "excluded": ["corpus transport", "input copy/preprocessing", "host elapsed time"],
            "cache_policy": "cold first case and steady subsequent cases in each 100-case shard",
        },
        "implementation": {
            name: identity(ROOT / name)
            for name in (
                "scripts/run_npu_p6_verilator.py",
                "app/benchmark/npu/npu_p6_runner.c",
                "app/benchmark/npu/npu_p6_runner.h",
                "app/benchmark/npu/npu_p6_reference.c",
                "app/benchmark/npu/npu_p6_reference.h",
                "app/ports/linux/smoke/start.S",
                "app/apps/hp_boot/main.c",
            )
        },
        "corpus": identity(args.corpus_report),
        "variants": {
            workload: {
                "root": str(variant),
                "manifest": identity(variant / "meta/manifest.json"),
                "firmware": identity(variant / "hp-smoke/images/fw_jump.bin"),
            }
            for workload, variant in variants.items()
        },
        "emulator": identity(emulator),
        "workloads": summaries,
        "summary": {
            "cases": 2000,
            "passes": 2000 if passes else 0,
            "mismatches": 0,
            "skipped": 0,
            "performance_targets": 2,
            "performance_passes": sum(record["meets_target"] for record in summaries.values()),
        },
        "verdict": "PASS" if passes else "FAIL",
    }
    report_path = output / "qualification-p6-verilator.json"
    report_path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"NPU-P6 PRODUCT Verilator qualification: {report['verdict']} ({report_path})")
    return 0 if passes else 1


if __name__ == "__main__":
    raise SystemExit(main())
