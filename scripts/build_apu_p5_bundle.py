#!/usr/bin/env python3
"""Build the deterministic APU-P5 codec bundle and evidence reports."""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

from apu_mcasm import _artifact_data, assemble  # noqa: E402
from apu_isa import abi_manifest, control_flow_report  # noqa: E402
from apu_p5_coefficients import coefficient_bytes  # noqa: E402


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()
    output = args.output_dir.resolve()
    output.mkdir(parents=True, exist_ok=True)
    coefficients = coefficient_bytes()
    source = ROOT / "rtl/ip/multimedia/apu_p5_codecs.apus"
    assembly = assemble(source.read_text(encoding="utf-8"), "p5", coefficients)
    bundle_path = output / "apu-p5.apumc"
    coefficient_path = output / "apu-p5-coefficients.bin"
    bundle_path.write_bytes(assembly.bundle)
    coefficient_path.write_bytes(coefficients)
    (output / "symbols.json").write_text(
        json.dumps(assembly.symbols, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    reports = {
        "cfg-report.json": {
            **_artifact_data(assembly),
            "entries": [entry.__dict__ for entry in assembly.entries],
            "control_flow": [
                control_flow_report(
                    assembly.instructions,
                    entry,
                    assembly.target,
                    assembly.mc_abi,
                )
                for entry in assembly.entries
            ],
        },
        "primitive-manifest.json": {
            "target": "p5",
            "implemented_mask": 0x001FFFFF,
            "required_mask": __import__("functools").reduce(
                int.__or__, (entry.primitive_mask for entry in assembly.entries), 0
            ),
            "entry_masks": [entry.primitive_mask for entry in assembly.entries],
        },
        "trace-input.json": {
            "entries": [entry.entry_pc for entry in assembly.entries],
            "instructions": [f"0x{item.encode():016x}" for item in assembly.instructions],
        },
        "abi-input-manifest.json": {
            **_artifact_data(assembly),
            "canonical_abi": abi_manifest(),
        },
    }
    for name, report in reports.items():
        (output / name).write_text(
            json.dumps(report, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
    high_water = {
        "apumc_version": f"0x{assembly.mc_abi:08x}",
        "instruction_words": len(assembly.instructions),
        "maximum_instruction_words": 4096,
        "free_instruction_words": 4096 - len(assembly.instructions),
        "control_store_bytes": len(assembly.instructions) * 8,
        "table_bytes": len(coefficients),
        "maximum_scratch_end": max(
            entry.scratch_base + entry.scratch_bytes for entry in assembly.entries
        ),
        "loader_proof_workspace": {
            "pending_record_bits": 64,
            "pending_path_records_v1": 2048,
            "pending_path_records_v2": 4096,
            "pending_storage_bytes_v1": 2048 * 8,
            "pending_storage_bytes_v2": 4096 * 8,
            "memo_entries": 8192,
            "memo_entry_bits": 65,
            "memo_storage_bytes_ceiling": (8192 * 65 + 7) // 8,
            "traversal_limit_v1": 131072,
            "traversal_limit_v2": 262144,
        },
        "entries": [
            {
                "format_id": entry.format_id,
                "first_pc": entry.first_pc,
                "last_pc": entry.last_pc,
                "instruction_span": entry.last_pc - entry.first_pc + 1,
                "scratch_end": entry.scratch_base + entry.scratch_bytes,
                "maximum_loop_count": entry.max_loop_count,
                "maximum_retired": entry.max_retired,
            }
            for entry in assembly.entries
        ],
    }
    (output / "high-water.json").write_text(
        json.dumps(high_water, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    (output / "manifest.json").write_text(
        json.dumps(
            {
                **_artifact_data(assembly),
                "target": "p5",
                "coefficient_words": len(coefficients) // 4,
                "entries": [entry.__dict__ for entry in assembly.entries],
                "sha256": {
                    "bundle": hashlib.sha256(assembly.bundle).hexdigest(),
                    "coefficients": hashlib.sha256(coefficients).hexdigest(),
                    "source": hashlib.sha256(source.read_bytes()).hexdigest(),
                    "reports": {
                        name: hashlib.sha256(
                            (output / name).read_bytes()
                        ).hexdigest()
                        for name in reports
                    },
                },
                "high_water": high_water,
            },
            indent=2,
            sort_keys=True,
        )
        + "\n",
        encoding="utf-8",
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
