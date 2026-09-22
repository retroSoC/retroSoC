#!/usr/bin/env python3
"""Generate the committed NPU-P0 workload qualification manifests."""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from scripts.dependency_lock import archive, source  # noqa: E402
from scripts.setup_helpers import sha256  # noqa: E402
from scripts.setup_npu_reference import (  # noqa: E402
    KWS_FEATURE_COUNT,
    KWS_FEATURES,
    VWW_CLASS_DIRS,
    VWW_CORPUS_COUNT,
    vww_label_entries,
)

CONTRACT_REVISION = "npu-p0/1.0.0"

KWS_CORPUS_TSV = ROOT / "docs/ip/apu-kws-corpus.tsv"
KWS_MANIFEST_OUT = ROOT / "docs/ip/npu-kws-manifest.json"
VWW_MANIFEST_OUT = ROOT / "docs/ip/npu-vww-manifest.json"
VWW_CORPUS_TSV_OUT = ROOT / "docs/ip/npu-vww-corpus.tsv"

KWS_MODEL_REL = "benchmark/training/keyword_spotting/trained_models/kws_ref_model.tflite"
VWW_MODEL_REL = "benchmark/training/visual_wake_words/trained_models/vww_96_int8.tflite"
VWW_LABELS_REL = "benchmark/evaluation/datasets/vww01/y_labels.csv"

RTL_SAMPLE_COUNT = 10


def _tiny_root() -> Path:
    return ROOT / source("apu_mlperf_tiny")["destination"]


def _mfcc_root() -> Path:
    return ROOT / source("apu_kws_mfcc")["destination"]


def _vww_corpus_root() -> Path:
    return ROOT / ".cache/retrosoc/sources/npu-vww-corpus"


def _compiler_identity() -> dict[str, object]:
    return {"contract_revision": CONTRACT_REVISION}


def _aggregate(digests: list[str]) -> str:
    return hashlib.sha256("".join(digests).encode("ascii")).hexdigest()


def _rtl_samples(names: list[str]) -> list[str]:
    return sorted(names)[:RTL_SAMPLE_COUNT]


def kws_inputs() -> list[dict[str, object]]:
    mfcc = _mfcc_root() / KWS_FEATURES
    inputs = []
    for line in KWS_CORPUS_TSV.read_text(encoding="utf-8").splitlines():
        index, name, _wav, class_id, _wav_sha, _pcm_sha = line.split("\t")
        feature = mfcc / name
        if not feature.is_file():
            raise RuntimeError(f"missing KWS feature input: {feature}")
        inputs.append(
            {
                "index": int(index),
                "name": name,
                "class_id": int(class_id),
                "sha256": sha256(feature),
            }
        )
    if len(inputs) != KWS_FEATURE_COUNT or [item["index"] for item in inputs] != list(
        range(KWS_FEATURE_COUNT)
    ):
        raise RuntimeError("KWS corpus manifest must hold 1000 ordered inputs")
    return inputs


def build_kws_manifest() -> dict[str, object]:
    tiny = _tiny_root()
    model = tiny / KWS_MODEL_REL
    inputs = kws_inputs()
    return {
        "schema": 1,
        "workload": "kws",
        "model": {
            "path": KWS_MODEL_REL,
            "bytes": model.stat().st_size,
            "sha256": sha256(model),
        },
        "sources": {
            "apu_mlperf_tiny": source("apu_mlperf_tiny")["revision"],
            "apu_kws_mfcc": source("apu_kws_mfcc")["revision"],
        },
        "corpus": {
            "definition": "docs/ip/apu-kws-corpus.tsv",
            "definition_sha256": sha256(KWS_CORPUS_TSV),
            "count": len(inputs),
            "inputs_aggregate_sha256": _aggregate([item["sha256"] for item in inputs]),
        },
        "preprocessing": {
            "kind": "mfcc-49x10-int8",
            "note": "Locked APU-P7 MFCC frontend output reused unchanged; outside the NPU graph.",
        },
        "input_quantization": {"scale": 0.5847029089927673, "zero_point": 83},
        "compiler": _compiler_identity(),
        "rtl_sample_ids": _rtl_samples([item["name"] for item in inputs]),
        "inputs": inputs,
    }


def vww_rows() -> list[tuple[str, str, str, str, str, str]]:
    corpus = _vww_corpus_root()
    rows = []
    for index, (name, label) in enumerate(vww_label_entries(_tiny_root())):
        stem = name[:12]
        jpg_rel = f"{VWW_CLASS_DIRS[label]}/COCO_val2014_{stem}.jpg"
        jpg = corpus / jpg_rel
        raw = corpus / VWW_CLASS_DIRS[label] / name
        for candidate in (jpg, raw):
            if not candidate.is_file():
                raise RuntimeError(f"missing VWW corpus file: {candidate}")
        rows.append(
            (f"{index:06d}", name, jpg_rel, str(label), sha256(jpg), sha256(raw))
        )
    if len(rows) != VWW_CORPUS_COUNT:
        raise RuntimeError("VWW corpus must hold 1000 inputs")
    return rows


def vww_corpus_tsv_text() -> str:
    return "".join("\t".join(row) + "\n" for row in vww_rows())


def build_vww_manifest(corpus_tsv_sha256: str) -> dict[str, object]:
    tiny = _tiny_root()
    model = tiny / VWW_MODEL_REL
    rows = vww_rows()
    labels = tiny / VWW_LABELS_REL
    return {
        "schema": 1,
        "workload": "vww",
        "model": {
            "path": VWW_MODEL_REL,
            "bytes": model.stat().st_size,
            "sha256": sha256(model),
        },
        "sources": {"apu_mlperf_tiny": source("apu_mlperf_tiny")["revision"]},
        "archives": {"npu_vww_dataset": archive("npu_vww_dataset")["sha256"]},
        "corpus": {
            "definition": "docs/ip/npu-vww-corpus.tsv",
            "definition_sha256": corpus_tsv_sha256,
            "labels_index": VWW_LABELS_REL,
            "labels_index_sha256": sha256(labels),
            "count": len(rows),
            "class_counts": {"person": 500, "non_person": 500},
            "jpeg_aggregate_sha256": _aggregate([row[4] for row in rows]),
            "bin_aggregate_sha256": _aggregate([row[5] for row in rows]),
        },
        "preprocessing": {
            "kind": "jpeg-rgb-96x96-minus-128",
            "note": (
                "Decode COCO_val2014 96x96 RGB JPEG to U8C3 bytes ([0]=ulc, [9215]=lrc), "
                "then quantize input = pixel - 128; preprocessing is outside the NPU graph."
            ),
        },
        "input_quantization": {"scale": 1.0 / 255.0, "zero_point": -128},
        "compiler": _compiler_identity(),
        "rtl_sample_ids": _rtl_samples([row[1] for row in rows]),
    }


def _write(path: Path, content: str) -> bool:
    if path.is_file() and path.read_text(encoding="utf-8") == content:
        return False
    path.write_text(content, encoding="utf-8")
    return True


def _dump(manifest: dict[str, object]) -> str:
    return json.dumps(manifest, indent=2, sort_keys=True) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="verify committed manifests")
    args = parser.parse_args()

    kws = _dump(build_kws_manifest())
    tsv = vww_corpus_tsv_text()
    vww = _dump(build_vww_manifest(hashlib.sha256(tsv.encode("utf-8")).hexdigest()))

    outputs = ((KWS_MANIFEST_OUT, kws), (VWW_CORPUS_TSV_OUT, tsv), (VWW_MANIFEST_OUT, vww))
    if args.check:
        stale = [str(path) for path, content in outputs if path.read_text(
            encoding="utf-8"
        ) != content] if all(path.is_file() for path, _ in outputs) else [
            str(path) for path, _ in outputs if not path.is_file()
        ]
        if stale:
            raise SystemExit(f"stale or missing NPU manifests: {stale}")
        print("NPU-P0 manifests verified")
        return 0
    changed = [str(path) for path, content in outputs if _write(path, content)]
    print(f"NPU-P0 manifests written: {changed if changed else 'already up to date'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
