#!/usr/bin/env python3
"""Install and verify the locked NPU-P0 workload reference assets."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import tarfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from scripts.dependency_lock import archive, source  # noqa: E402
from scripts.setup_helpers import atomic_write, download_file, ensure_git_repo, sha256  # noqa: E402

MLCOMMONS_TINY = "apu_mlperf_tiny"
KWS_MFCC = "apu_kws_mfcc"
VWW_DATASET = "npu_vww_dataset"
ORACLE_SOURCES = ("apu_tensorflow", "apu_gemmlowp")

KWS_MODEL = Path("benchmark/training/keyword_spotting/trained_models/kws_ref_model.tflite")
KWS_MODEL_SHA256 = "aeea436800704fce17b17292e4412630ad856e9d777c044c64ef748a880bd0ae"
VWW_MODEL = Path("benchmark/training/visual_wake_words/trained_models/vww_96_int8.tflite")
VWW_MODEL_SHA256 = "597a384c8c2c8a1276f04702f25013b7838f2f814f1ca7c174d295b73e3d6b7b"
VWW_LABELS = Path("benchmark/evaluation/datasets/vww01/y_labels.csv")
KWS_FEATURES = Path("datasets/kws01")
KWS_FEATURE_COUNT = 1000
VWW_CORPUS_COUNT = 1000
VWW_IMAGE_BYTES = 96 * 96 * 3
VWW_CLASS_DIRS = {1: "person", 0: "non_person"}

VWW_CORPUS_TSV = ROOT / "docs/ip/npu-vww-corpus.tsv"
KWS_MANIFEST = ROOT / "docs/ip/npu-kws-manifest.json"


def tiny_root() -> Path:
    return ROOT / source(MLCOMMONS_TINY)["destination"]


def mfcc_root() -> Path:
    return ROOT / source(KWS_MFCC)["destination"]


def vww_corpus_root() -> Path:
    return ROOT / ".cache/retrosoc/sources/npu-vww-corpus"


def vww_label_entries(tiny: Path) -> list[tuple[str, int]]:
    labels_path = tiny / VWW_LABELS
    if not labels_path.is_file():
        raise RuntimeError(f"missing locked VWW label index: {labels_path}")
    entries: list[tuple[str, int]] = []
    for line in labels_path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line:
            continue
        name, _classes, label = [part.strip() for part in line.split(",")]
        if not name.endswith(".bin") or len(name) != 16 or not name[:12].isdigit():
            raise RuntimeError(f"unexpected VWW label entry name: {name}")
        entries.append((name, int(label)))
    if len(entries) != VWW_CORPUS_COUNT:
        raise RuntimeError(f"VWW label index must list {VWW_CORPUS_COUNT} entries: {len(entries)}")
    if len({name for name, _ in entries}) != VWW_CORPUS_COUNT:
        raise RuntimeError("VWW label index contains duplicate entries")
    person = sum(1 for _, label in entries if label == 1)
    if person != VWW_CORPUS_COUNT // 2:
        raise RuntimeError(f"VWW label index must be 500/500 balanced: person={person}")
    if any(label not in VWW_CLASS_DIRS for _, label in entries):
        raise RuntimeError("VWW label index carries a label outside {0, 1}")
    return entries


def verify_models(tiny: Path) -> dict[str, str]:
    records = {}
    for relative, expected in ((KWS_MODEL, KWS_MODEL_SHA256), (VWW_MODEL, VWW_MODEL_SHA256)):
        model = tiny / relative
        if not model.is_file() or sha256(model) != expected:
            raise RuntimeError(f"NPU locked model hash mismatch: {model}")
        records[relative.as_posix()] = expected
    return records


def verify_kws_features(mfcc: Path) -> list[str]:
    features = mfcc / KWS_FEATURES
    names = sorted(path.name for path in features.glob("tst_*.bin"))
    if len(names) != KWS_FEATURE_COUNT:
        raise RuntimeError(f"KWS feature set must hold {KWS_FEATURE_COUNT} bins: {len(names)}")
    return names


def _extract_vww_jpegs(archive_path: Path, corpus: Path, entries: list[tuple[str, int]]) -> None:
    wanted = {}
    for name, label in entries:
        stem = name[:12]
        member = f"vw_coco2014_96/{VWW_CLASS_DIRS[label]}/COCO_val2014_{stem}.jpg"
        wanted[member] = corpus / VWW_CLASS_DIRS[label] / f"COCO_val2014_{stem}.jpg"
    remaining = dict(wanted)
    with tarfile.open(archive_path, "r:gz") as bundle:
        for item in bundle:
            target = remaining.pop(item.name, None)
            if target is None:
                continue
            if not item.isfile():
                raise RuntimeError(f"unexpected non-file member: {item.name}")
            payload = bundle.extractfile(item)
            if payload is None:
                raise RuntimeError(f"unreadable member: {item.name}")
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(payload.read())
            if not remaining:
                break
    if remaining:
        missing = sorted(remaining)[:5]
        raise RuntimeError(f"VWW dataset misses {len(remaining)} inputs, first: {missing}")


def _decode_vww_bins(corpus: Path, entries: list[tuple[str, int]]) -> str:
    try:
        from PIL import Image
    except ImportError as error:
        raise RuntimeError("Pillow is required to decode the VWW corpus") from error
    for name, label in entries:
        stem = name[:12]
        source_jpg = corpus / VWW_CLASS_DIRS[label] / f"COCO_val2014_{stem}.jpg"
        target = corpus / VWW_CLASS_DIRS[label] / name
        if target.is_file() and target.stat().st_size == VWW_IMAGE_BYTES:
            continue
        with Image.open(source_jpg) as image:
            if image.size != (96, 96) or image.mode != "RGB":
                raise RuntimeError(f"unexpected VWW image geometry: {source_jpg}")
            target.write_bytes(image.tobytes())
    import PIL

    return PIL.__version__


def _git_revision(path: Path) -> str:
    return subprocess.check_output(
        ["git", "-C", str(path), "rev-parse", "HEAD"], text=True
    ).strip()


def install(build_dir: Path, *, update: bool) -> dict[str, object]:
    tiny = tiny_root()
    mfcc = mfcc_root()
    for name in (MLCOMMONS_TINY, KWS_MFCC, *ORACLE_SOURCES):
        spec = source(name)
        ensure_git_repo(spec["url"], ROOT / spec["destination"], spec["revision"], update=update)
    dataset = archive(VWW_DATASET)
    archive_path = ROOT / dataset["destination"]
    download_file(dataset["url"], archive_path, dataset["sha256"], update=update, timeout=600)

    models = verify_models(tiny)
    kws_names = verify_kws_features(mfcc)
    entries = vww_label_entries(tiny)
    corpus = vww_corpus_root()
    jpegs = [
        corpus / VWW_CLASS_DIRS[label] / f"COCO_val2014_{name[:12]}.jpg" for name, label in entries
    ]
    if update or not all(path.is_file() for path in jpegs):
        _extract_vww_jpegs(archive_path, corpus, entries)
    pillow_version = _decode_vww_bins(corpus, entries)

    records: dict[str, object] = {
        "target": "npu-p0",
        "sources": {
            name: {"revision": source(name)["revision"], "destination": source(name)["destination"]}
            for name in (MLCOMMONS_TINY, KWS_MFCC, *ORACLE_SOURCES)
        },
        "archives": {VWW_DATASET: dataset["sha256"]},
        "models": models,
        "kws_feature_count": len(kws_names),
        "vww_corpus_count": len(entries),
        "pillow_version": pillow_version,
    }
    build_dir.mkdir(parents=True, exist_ok=True)
    atomic_write(build_dir / "provenance.json", json.dumps(records, indent=2, sort_keys=True) + "\n")
    return records


def doctor() -> None:
    tiny = tiny_root()
    mfcc = mfcc_root()
    for name, path in ((MLCOMMONS_TINY, tiny), (KWS_MFCC, mfcc)):
        if not (path / ".git").is_dir():
            raise RuntimeError(f"missing NPU managed source: {path}")
        revision = _git_revision(path)
        if revision != source(name)["revision"]:
            raise RuntimeError(f"NPU source revision mismatch for {name}: {revision}")
    for name in ORACLE_SOURCES:
        path = ROOT / source(name)["destination"]
        if not (path / ".git").is_dir() or _git_revision(path) != source(name)["revision"]:
            raise RuntimeError(f"missing or stale NPU oracle source: {name}")
        if subprocess.check_output(["git", "-C", str(path), "status", "--porcelain"], text=True).strip():
            raise RuntimeError(f"dirty NPU oracle source: {name}")
    dataset = archive(VWW_DATASET)
    archive_path = ROOT / dataset["destination"]
    if not archive_path.is_file() or sha256(archive_path) != dataset["sha256"]:
        raise RuntimeError(f"NPU VWW dataset archive mismatch: {archive_path}")
    verify_models(tiny)
    verify_kws_features(mfcc)
    entries = vww_label_entries(tiny)
    corpus = vww_corpus_root()
    for name, label in entries:
        stem = name[:12]
        for candidate in (
            corpus / VWW_CLASS_DIRS[label] / f"COCO_val2014_{stem}.jpg",
            corpus / VWW_CLASS_DIRS[label] / name,
        ):
            if not candidate.is_file():
                raise RuntimeError(f"missing VWW corpus file: {candidate}")
    if KWS_MANIFEST.is_file():
        manifest = json.loads(KWS_MANIFEST.read_text(encoding="utf-8"))
        inputs = manifest.get("inputs", {})
        if len(inputs) != KWS_FEATURE_COUNT:
            raise RuntimeError("NPU KWS manifest input count mismatch")
        for item in inputs:
            feature = mfcc / KWS_FEATURES / item["name"]
            if sha256(feature) != item["sha256"]:
                raise RuntimeError(f"NPU KWS feature hash mismatch: {item['name']}")
    if VWW_CORPUS_TSV.is_file():
        for line in VWW_CORPUS_TSV.read_text(encoding="utf-8").splitlines():
            index, name, jpg, _label, jpg_sha256, bin_sha256 = line.split("\t")
            del index
            jpg_path = corpus / jpg
            bin_path = jpg_path.parent / name
            if sha256(jpg_path) != jpg_sha256:
                raise RuntimeError(f"NPU VWW JPEG hash mismatch: {jpg}")
            if sha256(bin_path) != bin_sha256:
                raise RuntimeError(f"NPU VWW bin hash mismatch: {name}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build-dir", type=Path, required=True)
    parser.add_argument("--doctor", action="store_true")
    parser.add_argument("--update", action="store_true")
    args = parser.parse_args()

    if args.doctor:
        doctor()
        print("NPU-P0 locked references verified")
        return 0
    records = install(args.build_dir.resolve(), update=args.update)
    print(f"NPU-P0 KWS/VWW references: {args.build_dir.resolve() / 'provenance.json'}")
    print(f"KWS features: {records['kws_feature_count']}, VWW corpus: {records['vww_corpus_count']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
