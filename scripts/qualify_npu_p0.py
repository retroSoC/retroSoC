#!/usr/bin/env python3
"""NPU-P0 full-corpus qualification against dependency-locked TFLite kernels."""

from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
import sys
import time
from concurrent.futures import ProcessPoolExecutor
from contextlib import nullcontext
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

import npu_compiler_p0  # noqa: E402
import npu_executor  # noqa: E402
import npu_model  # noqa: E402
import setup_npu_reference as setup_npu  # noqa: E402
from npu_framework_reference import FrameworkOracle, OracleError, build_oracle  # noqa: E402

KWS_FEATURES = ROOT / ".cache/retrosoc/sources/apu-kws-mfcc/datasets/kws01"
VWW_CORPUS = ROOT / ".cache/retrosoc/sources/npu-vww-corpus"
KWS_MANIFEST = ROOT / "docs/ip/npu-kws-manifest.json"
VWW_MANIFEST = ROOT / "docs/ip/npu-vww-manifest.json"
VWW_TSV = ROOT / "docs/ip/npu-vww-corpus.tsv"
LOCK = ROOT / "dependencies/dependencies.lock.json"


class QualificationBlocked(RuntimeError):
    pass


def _require(condition: bool, message: str) -> None:
    if not condition:
        raise QualificationBlocked(message)


def _git_revision() -> str:
    return subprocess.check_output(
        ["git", "-C", str(ROOT), "rev-parse", "HEAD"], text=True
    ).strip()


def _argmax(data: tuple[int, ...] | list[int]) -> int:
    best = 0
    for index, value in enumerate(data):
        if value > data[best]:
            best = index
    return best


def _check_assets() -> None:
    try:
        setup_npu.doctor()
    except RuntimeError as error:
        raise QualificationBlocked(str(error)) from error
    for path in (KWS_MANIFEST, VWW_MANIFEST, VWW_TSV):
        _require(path.is_file(), f"missing committed NPU manifest: {path}")
    completed = subprocess.run(
        [sys.executable, str(ROOT / "scripts/npu_manifest.py"), "--check"],
        capture_output=True,
        text=True,
    )
    _require(completed.returncode == 0, f"manifest check failed: {completed.stderr.strip()}")


def _load_kws_corpus() -> list[tuple[str, int, Path]]:
    manifest = json.loads(KWS_MANIFEST.read_text(encoding="utf-8"))
    rows = []
    for item in manifest["inputs"]:
        feature = KWS_FEATURES / item["name"]
        _require(feature.is_file(), f"missing KWS feature input: {feature}")
        rows.append((item["name"], int(item["class_id"]), feature))
    _require(len(rows) == 1000, f"KWS corpus must hold 1000 inputs: {len(rows)}")
    return rows


def _load_vww_corpus() -> list[tuple[str, int, Path]]:
    rows = []
    for line in VWW_TSV.read_text(encoding="utf-8").splitlines():
        _index, name, jpg_rel, label, _jpg_sha, _bin_sha = line.split("\t")
        raw = VWW_CORPUS / Path(jpg_rel).parent / name
        _require(raw.is_file(), f"missing VWW corpus input: {raw}")
        rows.append((name, int(label), raw))
    _require(len(rows) == 1000, f"VWW corpus must hold 1000 inputs: {len(rows)}")
    return rows


def compare_layers(executed: list[bytes], reference: list[bytes],
                   framework: list[bytes]) -> list[dict]:
    """Neither Python path may certify the other; both must match the oracle."""
    if not framework or len(executed) != len(framework) or len(reference) != len(framework):
        raise RuntimeError("framework/reference/executor layer count mismatch")
    mismatches = []
    for index, expected in enumerate(framework):
        for name, layers in (("executor", executed), ("reference", reference)):
            got = layers[index]
            if got == expected:
                continue
            first = next((i for i, (a, b) in enumerate(zip(got, expected)) if a != b),
                         min(len(got), len(expected)))
            mismatches.append({"layer": index, "path": name, "first_byte": first,
                               "expected_bytes": len(expected), "actual_bytes": len(got),
                               "expected": expected[first] if first < len(expected) else None,
                               "actual": got[first] if first < len(got) else None})
    return mismatches


_WORKER_CONTEXT = None


def _worker_init(graph, job, oracle, prepare_input):
    global _WORKER_CONTEXT
    _WORKER_CONTEXT = graph, job, oracle, prepare_input


def _qualify_input(item):
    graph, job, oracle, prepare_input = _WORKER_CONTEXT
    name, label, path = item
    input_bytes = prepare_input(path.read_bytes())
    result = npu_executor.execute_job(job, input_bytes)
    reference_layers = npu_compiler_p0.evaluate_reference(graph, input_bytes)
    framework_layers = oracle.evaluate(input_bytes, name)
    executed = [bytes(v & 255 for v in tensor.data) for tensor in result.layers]
    reference = [bytes(v & 255 for v in tensor.data) for tensor in reference_layers]
    differences = compare_layers(executed, reference, framework_layers)
    record = {
        "input": name, "input_sha256": hashlib.sha256(input_bytes).hexdigest(),
        "layers": [
            {"layer": i, "bytes": len(golden),
             "framework_sha256": hashlib.sha256(golden).hexdigest(),
             "reference_sha256": hashlib.sha256(reference[i]).hexdigest(),
             "executor_sha256": hashlib.sha256(executed[i]).hexdigest()}
            for i, golden in enumerate(framework_layers)
        ],
        "mismatches": differences,
        "correct": _argmax(list(result.output.data)) == label,
    }
    (oracle.directory / name / "comparison.json").write_text(
        json.dumps(record, indent=2, sort_keys=True) + "\n"
    )
    return record


def _qualify_model(
    workload: str,
    graph: "npu_model.GraphInfo",
    job: "npu_compiler_p0.CompiledJob",
    corpus: list[tuple[str, int, Path]],
    prepare_input,
    *,
    limit: int | None,
    oracle: FrameworkOracle,
    jobs: int = 1,
) -> dict[str, object]:
    selected = corpus if limit is None else corpus[:limit]
    mismatches: list[dict[str, object]] = []
    correct = 0
    started = time.monotonic()
    records = []
    context = (graph, job, oracle, prepare_input)
    _worker_init(*context)
    pool = (ProcessPoolExecutor(max_workers=jobs, initializer=_worker_init, initargs=context)
            if jobs > 1 else nullcontext())
    with pool as executor:
        results = executor.map(_qualify_input, selected) if executor else map(_qualify_input, selected)
        for index, record in enumerate(results):
            records.append(record)
            mismatches.extend({"input": record["input"], **item} for item in record["mismatches"])
            correct += int(record["correct"])
            if (index + 1) % 10 == 0:
                print(f"[{workload}] {index + 1}/{len(selected)} inputs compared", flush=True)
    total = len(selected)
    (oracle.directory / "index.json").write_text(json.dumps(records, indent=2, sort_keys=True) + "\n")
    return {
        "workload": workload,
        "inputs": total,
        "full_corpus": limit is None,
        "layer_mismatches": len(mismatches),
        "first_mismatches": mismatches[:8],
        "tensor_comparisons": sum(len(item["layers"]) for item in records),
        "index": str(oracle.directory / "index.json"),
        "accuracy": {"correct": correct, "total": total, "ratio": correct / total},
        "duration_seconds": round(time.monotonic() - started, 3),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--cxx", default="g++")
    parser.add_argument("--profile", default="host")
    parser.add_argument("--config-digest", default="not-supplied")
    parser.add_argument("--jobs", type=int, default=1)
    parser.add_argument(
        "--limit",
        type=int,
        default=None,
        help="debug-only input cap per model; a limited run is NOT an acceptance run",
    )
    args = parser.parse_args()
    if not 1 <= args.jobs <= 16:
        parser.error("--jobs must be within 1..16")
    if args.limit is not None and not 1 <= args.limit <= 1000:
        parser.error("--limit must be within 1..1000; limited runs are never acceptance")
    args.output_dir = args.output_dir.resolve()
    args.output_dir.mkdir(parents=True, exist_ok=True)
    report = {
        "schema": 1,
        "phase": "NPU-P0",
        "verification_ids": ["NPU-V001"],
        "git_revision": _git_revision(),
        "lock_sha256": hashlib.sha256(LOCK.read_bytes()).hexdigest(),
        "command": " ".join([sys.executable, *sys.argv]),
        "acceptance_run": args.limit is None,
        "profile": args.profile,
        "config_digest": args.config_digest,
        "jobs": args.jobs,
        "compiler_contract": npu_compiler_p0.CONTRACT_REVISION,
        "implementation_sha256": {
            name: hashlib.sha256((ROOT / name).read_bytes()).hexdigest()
            for name in (
                "scripts/qualify_npu_p0.py", "scripts/npu_framework_reference.py",
                "scripts/npu_model.py", "scripts/npu_reference.py",
                "scripts/npu_compiler_p0.py", "scripts/npu_executor.py",
                "scripts/setup_npu_reference.py", "tests/cpp/npu_framework_reference.cc",
            )
        },
        "git_dirty": bool(subprocess.check_output(
            ["git", "-C", str(ROOT), "status", "--porcelain"], text=True).strip()),
        "method": "TFLite integer kernels vs Python graph reference vs compiled executor",
        "supersedes": "build/npu-p0-qualification/qualification-p0.json (shared-arithmetic comparison only)",
        "skipped": 0,
        "results": [],
        "verdict": "BLOCKED",
    }
    report_path = args.output_dir / "qualification-p0.json"
    def save():
        report_path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    save()
    try:
        _check_assets()
        executable, evidence = build_oracle(args.output_dir / "oracle", args.cxx)
        report["oracle"] = evidence
        cases = [
            ("kws", npu_model.load_kws_model, npu_compiler_p0.compile_kws,
             _load_kws_corpus(), bytes),
            ("vww", npu_model.load_vww_model, npu_compiler_p0.compile_vww,
             _load_vww_corpus(), npu_compiler_p0.vww_input_bytes),
        ]
        report["verdict"] = "INCOMPLETE"
        save()
        for name, load, compile_model, corpus, prepare in cases:
            graph = load().main_graph()
            job = compile_model()
            npu_compiler_p0.write_artifacts(job, args.output_dir / "deployments" / name)
            oracle = FrameworkOracle(graph, executable, args.output_dir / "oracle" / name)
            report["results"].append(_qualify_model(
                name, graph, job, corpus, prepare, limit=args.limit, oracle=oracle, jobs=args.jobs,
            ))
            save()
        passed = all(item["layer_mismatches"] == 0 for item in report["results"])
        report["verdict"] = ("PASS" if args.limit is None else "SMOKE-ONLY") if passed else "FAIL"
    except (QualificationBlocked, OracleError, OSError, ValueError, RuntimeError,
            ArithmeticError, npu_executor.ExecutorFault) as error:
        if report["verdict"] != "BLOCKED":
            report["verdict"] = "FAIL"
        report["error"] = str(error)
    except KeyboardInterrupt:
        report["verdict"] = "INCOMPLETE"
        report["error"] = "interrupted before qualification completed"
    report_path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    for item in report["results"]:
        accuracy = item["accuracy"]
        print(
            f"[{item['workload']}] inputs={item['inputs']} "
            f"layer_mismatches={item['layer_mismatches']} "
            f"accuracy={accuracy['correct']}/{accuracy['total']} ({accuracy['ratio']:.4f})"
        )
    print(f"NPU-P0 qualification verdict: {report['verdict']} ({report_path})")
    return 0 if report["verdict"] == "PASS" else (2 if report["verdict"] == "BLOCKED" else 1)


if __name__ == "__main__":
    raise SystemExit(main())
