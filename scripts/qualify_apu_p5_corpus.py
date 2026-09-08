#!/usr/bin/env python3
"""Classify the pinned FLAC corpus and record independent PCM truth."""

from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

from apu_codecs import CodecError, decode_flac, process_pcm  # noqa: E402


def _sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def _decode_hash(flac: Path, source: Path) -> tuple[int, str, str]:
    command = [
        str(flac),
        "--decode",
        "--stdout",
        "--force-raw-format",
        "--endian=little",
        "--sign=signed",
        "--silent",
        str(source),
    ]
    process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if process.stdout is None or process.stderr is None:
        raise RuntimeError("libFLAC subprocess pipes are unavailable")
    digest = hashlib.sha256()
    for block in iter(lambda: process.stdout.read(1024 * 1024), b""):
        digest.update(block)
    stderr = process.stderr.read().decode("utf-8", errors="replace")
    return process.wait(), digest.hexdigest(), stderr


def _classify(flac: Path, corpus: Path, path: Path) -> dict[str, object]:
    payload = path.read_bytes()
    relative = path.relative_to(corpus).as_posix()
    profile = "supported"
    reason = 0
    geometry: dict[str, int | None] | None = None
    model_pcm_hash: str | None = None
    production_pcm_hash = hashlib.sha256(b"").hexdigest()
    production_input_used = 0
    production_output_bytes = 0
    production_frames = 0
    production_source_info = 0
    model_error: CodecError | None = None
    try:
        decoded = decode_flac(payload, strict=True)
    except CodecError as error:
        profile = "unsupported" if error.code == 3 else "malformed"
        reason = error.reason
        model_error = error
        decoded = error.partial_audio

    if decoded is not None:
        info = decoded.info
        geometry = {
            "rate": info.rate,
            "channels": info.channels,
            "bits": info.bits,
            "samples": info.samples,
        }
        pcm = hashlib.sha256()
        sample_bytes = info.bits // 8
        for frame in decoded.samples:
            for sample in frame:
                pcm.update(sample.to_bytes(sample_bytes, "little", signed=True))
        model_pcm_hash = pcm.hexdigest()
        production_pcm = process_pcm(
            decoded,
            output_rate=info.rate,
            output_channels=info.channels,
            output_bits=info.bits,
        )
        production_pcm_hash = hashlib.sha256(production_pcm.payload).hexdigest()
        production_input_used = info.input_used
        production_output_bytes = len(production_pcm.payload)
        production_frames = production_pcm.frames
        production_source_info = info.rate | (info.channels << 17) | (info.bits << 19)

    if model_error is not None:
        production_input_used = model_error.input_used
    production_truth = {
        "status": "success" if model_error is None else "error",
        "code": 0 if model_error is None else model_error.code,
        "stage": 0 if model_error is None else model_error.stage,
        "warnings": decoded.info.warnings if model_error is None else (model_error.warnings | 1),
        "reason": 0 if model_error is None else model_error.reason,
        "error_offset": 0 if model_error is None else model_error.offset,
        "input_used": production_input_used,
        "output_bytes": production_output_bytes,
        "frames": production_frames,
        "source_info": production_source_info,
        "pcm_sha256": production_pcm_hash,
        "input_used_policy": "exact",
    }

    model_result = profile
    return_code, pcm_hash, stderr = _decode_hash(flac, path)
    lower_error = stderr.lower()
    md5_mismatch = "md5" in lower_error and "mismatch" in lower_error
    reference_valid = return_code == 0 or md5_mismatch
    if not reference_valid:
        profile = "malformed"
        if reason == 0:
            reason = 0x0030 if "crc" in lower_error else 0x0017
    agreement = not (model_result == "supported" and not reference_valid)
    if model_result == "supported" and reference_valid and model_pcm_hash != pcm_hash:
        agreement = False
    if relative.startswith("subset/") and reference_valid and model_result == "malformed":
        agreement = False
    return {
        "path": relative,
        "sha256": hashlib.sha256(payload).hexdigest(),
        "expected": profile,
        "model_result": model_result,
        "reference_valid": reference_valid,
        "model_reference_agreement": agreement,
        "profile_reason": reason,
        "geometry": geometry,
        "reference_pcm_sha256": pcm_hash,
        "model_pcm_sha256": model_pcm_hash,
        "production_truth": production_truth,
        "reference_integrity": "md5_mismatch"
        if md5_mismatch
        else ("passed" if return_code == 0 else "decode_failed"),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--flac", type=Path, required=True)
    parser.add_argument("--corpus", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    flac = args.flac.resolve()
    corpus = args.corpus.resolve()
    output = args.output.resolve()
    if not flac.is_file():
        raise SystemExit(f"libFLAC executable not found: {flac}")
    if not corpus.is_dir():
        raise SystemExit(f"FLAC corpus not found: {corpus}")

    files = sorted(corpus.rglob("*.flac"))
    if not files:
        raise SystemExit("pinned FLAC corpus contains no .flac files")
    records = [_classify(flac, corpus, path) for path in files]
    lock = json.loads((ROOT / "dependencies/dependencies.lock.json").read_text(encoding="utf-8"))
    counts = {
        category: sum(record["expected"] == category for record in records)
        for category in ("supported", "unsupported", "malformed")
    }
    manifest = {
        "schema_version": 1,
        "source_revision": lock["sources"]["apu_flac_corpus"]["revision"],
        "archive_sha256": lock["archives"]["apu_flac_corpus"]["sha256"],
        "corpus_root_sha256": _sha256_file(corpus / "LICENSE.txt"),
        "file_count": len(records),
        "counts": counts,
        "files": records,
    }
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"APU-P5 FLAC corpus: {len(records)} files -> {output}")
    disagreements = [
        record["path"] for record in records if not record["model_reference_agreement"]
    ]
    if disagreements:
        print(f"APU-P5 model/libFLAC disagreements: {len(disagreements)}", file=sys.stderr)
        for path in disagreements[:20]:
            print(f"  {path}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
