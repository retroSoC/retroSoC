#!/usr/bin/env python3
"""NPU-P0 full-corpus qualification: reference vs compiled-job executor."""

from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

import npu_compiler_p0  # noqa: E402
import npu_executor  # noqa: E402
import npu_model  # noqa: E402
import setup_npu_reference as setup_npu  # noqa: E402

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


def _qualify_model(
    workload: str,
    graph: "npu_model.GraphInfo",
    job: "npu_compiler_p0.CompiledJob",
    corpus: list[tuple[str, int, Path]],
    prepare_input,
    *,
    limit: int | None,
) -> dict[str, object]:
    selected = corpus if limit is None else corpus[:limit]
    mismatches: list[dict[str, object]] = []
    correct = 0
    started = time.monotonic()
    for index, (name, label, path) in enumerate(selected):
        input_bytes = prepare_input(path.read_bytes())
        result = npu_executor.execute_job(job, input_bytes)
        reference_layers = npu_compiler_p0.evaluate_reference(graph, input_bytes)
        if len(result.layers) != len(reference_layers):
            raise RuntimeError(f"{workload} layer count drift on {name}")
        for layer_index, (got, expected) in enumerate(zip(result.layers, reference_layers)):
            if tuple(got.data) != tuple(expected.data):
                mismatches.append(
                    {"input": name, "layer": layer_index, "input_sha256": hashlib.sha256(
                        input_bytes
                    ).hexdigest()}
                )
                break
        if _argmax(list(result.output.data)) == label:
            correct += 1
        if (index + 1) % 100 == 0:
            print(f"[{workload}] {index + 1}/{len(selected)} inputs compared", flush=True)
    total = len(selected)
    return {
        "workload": workload,
        "inputs": total,
        "full_corpus": limit is None,
        "layer_mismatches": len(mismatches),
        "first_mismatches": mismatches[:8],
        "accuracy": {"correct": correct, "total": total, "ratio": correct / total},
        "duration_seconds": round(time.monotonic() - started, 3),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument(
        "--limit",
        type=int,
        default=None,
        help="debug-only input cap per model; a limited run is NOT an acceptance run",
    )
    args = parser.parse_args()

    try:
        _check_assets()
    except QualificationBlocked as error:
        print(f"NPU-P0 qualification BLOCKED: {error}")
        return 2

    kws_corpus = _load_kws_corpus()
    vww_corpus = _load_vww_corpus()
    kws_graph = npu_model.load_kws_model().main_graph()
    vww_graph = npu_model.load_vww_model().main_graph()
    kws_job = npu_compiler_p0.compile_kws()
    vww_job = npu_compiler_p0.compile_vww()

    results = [
        _qualify_model(
            "kws",
            kws_graph,
            kws_job,
            kws_corpus,
            lambda raw: raw,
            limit=args.limit,
        ),
        _qualify_model(
            "vww",
            vww_graph,
            vww_job,
            vww_corpus,
            npu_compiler_p0.vww_input_bytes,
            limit=args.limit,
        ),
    ]

    acceptance = args.limit is None and all(item["layer_mismatches"] == 0 for item in results)
    report = {
        "phase": "NPU-P0",
        "verification_ids": ["NPU-V001"],
        "git_revision": _git_revision(),
        "lock_sha256": hashlib.sha256(LOCK.read_bytes()).hexdigest(),
        "command": " ".join([sys.executable, *sys.argv]),
        "acceptance_run": args.limit is None,
        "results": results,
        "verdict": "PASS" if acceptance else ("FAIL" if args.limit is None else "SMOKE-ONLY"),
    }
    args.output_dir.mkdir(parents=True, exist_ok=True)
    report_path = args.output_dir / "qualification-p0.json"
    report_path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    for item in results:
        accuracy = item["accuracy"]
        print(
            f"[{item['workload']}] inputs={item['inputs']} "
            f"layer_mismatches={item['layer_mismatches']} "
            f"accuracy={accuracy['correct']}/{accuracy['total']} ({accuracy['ratio']:.4f})"
        )
    print(f"NPU-P0 qualification verdict: {report['verdict']} ({report_path})")
    return 0 if acceptance else 1


if __name__ == "__main__":
    raise SystemExit(main())
