#!/usr/bin/env python3
"""Build deterministic NPU-P6 corpus shards from retained P0 oracle output."""

from __future__ import annotations

import argparse
import hashlib
import json
import struct
import subprocess
import zlib
from dataclasses import dataclass
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MAGIC = b"NP6S"
SCHEMA = 2
HEADER_BYTES = 128
HEADER = struct.Struct("<4s10I32s")
CASE_HEADER = struct.Struct("<II")
WORKLOAD_IDS = {"kws": 1, "vww": 2}
INPUT_BYTES = {"kws": 490, "vww": 27648}
OUTPUT_BYTES = {"kws": 12, "vww": 2}


@dataclass(frozen=True)
class CorpusCase:
    index: int
    name: str
    label: int
    input_data: bytes
    terminal_data: bytes
    softmax_data: bytes
    input_sha256: str
    terminal_sha256: str
    softmax_sha256: str


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def file_identity(path: Path) -> dict[str, object]:
    data = path.read_bytes()
    return {"path": str(path.resolve()), "bytes": len(data), "sha256": sha256(data)}


def _tsv_rows(path: Path) -> list[list[str]]:
    return [line.split("\t") for line in path.read_text(encoding="utf-8").splitlines() if line]


def _decode_layers(data: bytes, metadata: list[dict[str, object]]) -> list[bytes]:
    if (
        len(data) < CASE_HEADER.size
        or data[:4] != b"NPO1"
        or struct.unpack_from("<I", data, 4)[0] != len(metadata)
    ):
        raise ValueError("invalid P0 layer file header")
    cursor = CASE_HEADER.size
    layers = []
    for position, record in enumerate(metadata):
        if cursor + CASE_HEADER.size > len(data):
            raise ValueError(f"truncated P0 layer header at {position}")
        _tensor_id, size = CASE_HEADER.unpack_from(data, cursor)
        cursor += CASE_HEADER.size
        if size != record.get("bytes") or cursor + size > len(data):
            raise ValueError(f"P0 layer size changed at {position}")
        payload = data[cursor : cursor + size]
        cursor += size
        if sha256(payload) != record.get("framework_sha256"):
            raise ValueError(f"P0 layer hash changed at {position}")
        layers.append(payload)
    if cursor != len(data):
        raise ValueError("P0 layers contain trailing data")
    return layers


def _load_cases(p0_dir: Path, workload: str) -> list[CorpusCase]:
    oracle = p0_dir / "oracle" / workload
    index = json.loads((oracle / "index.json").read_text(encoding="utf-8"))
    tsv = ROOT / ("docs/ip/apu-kws-corpus.tsv" if workload == "kws" else "docs/ip/npu-vww-corpus.tsv")
    rows = _tsv_rows(tsv)
    if len(index) != 1000 or len(rows) != 1000:
        raise ValueError(f"{workload} P6 qualification requires exactly 1000 cases")
    cases: list[CorpusCase] = []
    for position, (record, row) in enumerate(zip(index, rows, strict=True)):
        case_index = int(row[0])
        name = row[1]
        label = int(row[3])
        if case_index != position or record.get("input") != name:
            raise ValueError(f"{workload} oracle index does not match frozen corpus at {position}")
        case_dir = oracle / name
        input_data = (case_dir / "input.bin").read_bytes()
        layers = record.get("layers", [])
        if not isinstance(layers, list):
            raise ValueError(f"{workload} case {position} layer metadata changed")
        output_bytes = OUTPUT_BYTES[workload]
        if len(input_data) != INPUT_BYTES[workload]:
            raise ValueError(f"{workload} case {position} input byte count changed")
        if len(layers) < 2 or any(layer.get("bytes") != output_bytes for layer in layers[-2:]):
            raise ValueError(f"{workload} case {position} terminal layer metadata changed")
        decoded_layers = _decode_layers((case_dir / "layers.bin").read_bytes(), layers)
        terminal_data = decoded_layers[-2]
        softmax_data = decoded_layers[-1]
        input_digest = sha256(input_data)
        terminal_digest = sha256(terminal_data)
        softmax_digest = sha256(softmax_data)
        if input_digest != record.get("input_sha256"):
            raise ValueError(f"{workload} case {position} input hash mismatch")
        if terminal_digest != layers[-2].get("framework_sha256"):
            raise ValueError(f"{workload} case {position} terminal hash mismatch")
        if softmax_digest != layers[-1].get("framework_sha256"):
            raise ValueError(f"{workload} case {position} Softmax hash mismatch")
        cases.append(
            CorpusCase(
                index=position,
                name=name,
                label=label,
                input_data=input_data,
                terminal_data=terminal_data,
                softmax_data=softmax_data,
                input_sha256=input_digest,
                terminal_sha256=terminal_digest,
                softmax_sha256=softmax_digest,
            )
        )
    return cases


def encode_shard(
    workload: str, shard_index: int, shard_count: int, cases: list[CorpusCase], manifest_sha256: str
) -> bytes:
    if workload not in WORKLOAD_IDS or not cases:
        raise ValueError("P6 shard requires a known workload and at least one case")
    first = cases[0].index
    if [case.index for case in cases] != list(range(first, first + len(cases))):
        raise ValueError("P6 shard cases must be contiguous and ordered")
    raw_record_bytes = CASE_HEADER.size + INPUT_BYTES[workload] + (2 * OUTPUT_BYTES[workload])
    record_bytes = (raw_record_bytes + 3) & ~3
    payload = b"".join(
        CASE_HEADER.pack(case.index, case.label)
        + case.input_data
        + case.terminal_data
        + case.softmax_data
        + bytes(record_bytes - raw_record_bytes)
        for case in cases
    )
    header = HEADER.pack(
        MAGIC,
        SCHEMA,
        WORKLOAD_IDS[workload],
        shard_index,
        shard_count,
        first,
        len(cases),
        INPUT_BYTES[workload],
        OUTPUT_BYTES[workload],
        record_bytes,
        zlib.crc32(payload) & 0xFFFFFFFF,
        bytes.fromhex(manifest_sha256),
    )
    return header + bytes(HEADER_BYTES - len(header)) + payload


def build_workload(
    p0_dir: Path, output_dir: Path, workload: str, cases_per_shard: int
) -> dict[str, object]:
    if cases_per_shard <= 0:
        raise ValueError("cases per shard must be positive")
    manifest_path = ROOT / f"docs/ip/npu-{workload}-manifest.json"
    manifest_digest = sha256(manifest_path.read_bytes())
    cases = _load_cases(p0_dir, workload)
    chunks = [cases[index : index + cases_per_shard] for index in range(0, len(cases), cases_per_shard)]
    workload_dir = output_dir / workload
    workload_dir.mkdir(parents=True, exist_ok=True)
    shards = []
    for shard_index, chunk in enumerate(chunks):
        path = workload_dir / f"shard-{shard_index:03d}.bin"
        path.write_bytes(encode_shard(workload, shard_index, len(chunks), chunk, manifest_digest))
        shards.append(
            {
                "index": shard_index,
                "first_case": chunk[0].index,
                "case_count": len(chunk),
                "cases": [
                    {
                        "index": case.index,
                        "name": case.name,
                        "label": case.label,
                        "input_sha256": case.input_sha256,
                        "terminal_sha256": case.terminal_sha256,
                        "softmax_sha256": case.softmax_sha256,
                    }
                    for case in chunk
                ],
                "file": file_identity(path),
            }
        )
    return {
        "workload": workload,
        "manifest": file_identity(manifest_path),
        "case_count": len(cases),
        "cases_per_shard": cases_per_shard,
        "shard_count": len(shards),
        "input_bytes": INPUT_BYTES[workload],
        "output_bytes": OUTPUT_BYTES[workload],
        "shards": shards,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--p0-dir", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--cases-per-shard", type=int, default=100)
    args = parser.parse_args()
    output_dir = args.output_dir.resolve()
    output_dir.mkdir(parents=True, exist_ok=True)
    report = {
        "schema": SCHEMA,
        "phase": "NPU-P6",
        "verification_ids": ["NPU-V016", "NPU-V018"],
        "git_revision": subprocess.check_output(
            ["git", "-C", str(ROOT), "rev-parse", "HEAD"], text=True
        ).strip(),
        "implementation": {
            "scripts/npu_p6_corpus.py": file_identity(ROOT / "scripts/npu_p6_corpus.py")
        },
        "p0_dir": str(args.p0_dir.resolve()),
        "workloads": {
            workload: build_workload(
                args.p0_dir.resolve(), output_dir, workload, args.cases_per_shard
            )
            for workload in ("kws", "vww")
        },
        "summary": {"cases": 2000, "skipped": 0},
        "verdict": "PASS",
    }
    report_path = output_dir / "corpus-shards.json"
    report_path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"NPU-P6 corpus shards: PASS ({report_path})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
