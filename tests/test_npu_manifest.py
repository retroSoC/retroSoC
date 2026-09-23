"""NPU-P0 workload manifest schema and lock-agreement tests."""

from __future__ import annotations

import hashlib
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

from npu_model import KWS_TFLITE_SHA256, VWW_TFLITE_SHA256  # noqa: E402

KWS_MANIFEST = ROOT / "docs/ip/npu-kws-manifest.json"
VWW_MANIFEST = ROOT / "docs/ip/npu-vww-manifest.json"
VWW_TSV = ROOT / "docs/ip/npu-vww-corpus.tsv"
KWS_APU_TSV = ROOT / "docs/ip/apu-kws-corpus.tsv"
LOCK = ROOT / "dependencies/dependencies.lock.json"

MLCOMMONS_TINY_REVISION = "4addd0fa08d216e20637637874e084895f289da4"
VWW_DATASET_SHA256 = "f8746b9e44f8a7a4293f73be9ba6e8da9239fe69798d42364aae62b915cfab58"


def _load(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def test_kws_manifest_schema_and_model_identity() -> None:
    manifest = _load(KWS_MANIFEST)
    assert manifest["schema"] == 1
    assert manifest["workload"] == "kws"
    model = manifest["model"]
    assert model["bytes"] == 53936
    assert model["sha256"] == KWS_TFLITE_SHA256
    assert manifest["sources"]["apu_mlperf_tiny"] == MLCOMMONS_TINY_REVISION
    assert manifest["input_quantization"]["zero_point"] == 83


def test_kws_manifest_inputs_and_aggregates() -> None:
    manifest = _load(KWS_MANIFEST)
    inputs = manifest["inputs"]
    assert len(inputs) == 1000
    assert [item["index"] for item in inputs] == list(range(1000))
    assert len({item["name"] for item in inputs}) == 1000
    assert all(len(item["sha256"]) == 64 for item in inputs)
    aggregate = hashlib.sha256(
        "".join(item["sha256"] for item in inputs).encode("ascii")
    ).hexdigest()
    assert manifest["corpus"]["inputs_aggregate_sha256"] == aggregate
    assert manifest["corpus"]["count"] == 1000
    assert manifest["corpus"]["definition"] == "docs/ip/apu-kws-corpus.tsv"
    assert manifest["corpus"]["definition_sha256"] == hashlib.sha256(
        KWS_APU_TSV.read_bytes()
    ).hexdigest()
    names = [item["name"] for item in inputs]
    assert manifest["rtl_sample_ids"] == sorted(names)[:10]


def test_kws_manifest_matches_apu_corpus_order() -> None:
    manifest = _load(KWS_MANIFEST)
    rows = [line.split("\t") for line in KWS_APU_TSV.read_text(encoding="utf-8").splitlines()]
    assert len(rows) == 1000
    for item, row in zip(manifest["inputs"], rows):
        assert item["name"] == row[1]
        assert item["class_id"] == int(row[3])


def test_vww_manifest_schema_and_model_identity() -> None:
    manifest = _load(VWW_MANIFEST)
    assert manifest["schema"] == 1
    assert manifest["workload"] == "vww"
    model = manifest["model"]
    assert model["bytes"] == 333288
    assert model["sha256"] == VWW_TFLITE_SHA256
    assert manifest["sources"]["apu_mlperf_tiny"] == MLCOMMONS_TINY_REVISION
    assert manifest["archives"]["npu_vww_dataset"] == VWW_DATASET_SHA256
    assert manifest["input_quantization"]["zero_point"] == -128
    assert manifest["corpus"]["class_counts"] == {"non_person": 500, "person": 500}


def test_vww_corpus_tsv_self_consistency() -> None:
    manifest = _load(VWW_MANIFEST)
    text = VWW_TSV.read_text(encoding="utf-8")
    rows = [line.split("\t") for line in text.splitlines()]
    assert len(rows) == 1000
    assert [row[0] for row in rows] == [f"{index:06d}" for index in range(1000)]
    assert manifest["corpus"]["definition_sha256"] == hashlib.sha256(
        text.encode("utf-8")
    ).hexdigest()
    jpeg_aggregate = hashlib.sha256("".join(row[4] for row in rows).encode("ascii")).hexdigest()
    bin_aggregate = hashlib.sha256("".join(row[5] for row in rows).encode("ascii")).hexdigest()
    assert manifest["corpus"]["jpeg_aggregate_sha256"] == jpeg_aggregate
    assert manifest["corpus"]["bin_aggregate_sha256"] == bin_aggregate
    person = [row for row in rows if row[3] == "1"]
    assert len(person) == 500
    assert all(row[2].startswith("person/") for row in person)
    assert all(row[2].startswith("non_person/") for row in rows if row[3] == "0")
    names = [row[1] for row in rows]
    assert len(set(names)) == 1000
    assert manifest["rtl_sample_ids"] == sorted(names)[:10]


def test_manifest_lock_agreement() -> None:
    lock = _load(LOCK)
    assert lock["sources"]["apu_mlperf_tiny"]["revision"] == MLCOMMONS_TINY_REVISION
    dataset = lock["archives"]["npu_vww_dataset"]
    assert dataset["sha256"] == VWW_DATASET_SHA256
    assert dataset["destination"].startswith(".cache/retrosoc/downloads/")
    vww = _load(VWW_MANIFEST)
    kws = _load(KWS_MANIFEST)
    assert vww["archives"]["npu_vww_dataset"] == dataset["sha256"]
    assert kws["sources"]["apu_mlperf_tiny"] == lock["sources"]["apu_mlperf_tiny"]["revision"]


def test_manifest_check_command_is_clean() -> None:
    completed = subprocess.run(
        [sys.executable, str(ROOT / "scripts/npu_manifest.py"), "--check"],
        capture_output=True,
        text=True,
    )
    if "missing" in completed.stderr.lower() or "missing" in completed.stdout.lower():
        import pytest

        pytest.skip("locked NPU workload assets were not installed")
    assert completed.returncode == 0, completed.stderr
