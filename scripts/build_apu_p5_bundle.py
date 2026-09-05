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
    high_water = {
        "instruction_words": len(assembly.instructions),
        "control_store_bytes": len(assembly.instructions) * 8,
        "table_bytes": len(coefficients),
        "maximum_scratch_end": max(
            entry.scratch_base + entry.scratch_bytes for entry in assembly.entries
        ),
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
