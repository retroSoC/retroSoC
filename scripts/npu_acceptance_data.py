#!/usr/bin/env python3
"""Emit the pinned first KWS input/output as build-local C acceptance data."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

from npu_compiler_p0 import KWS_CORPUS_FIRST, compile_kws
from npu_executor import execute_job


def values(data: bytes) -> str:
    return ",".join(f"INT8_C({value - 256 if value >= 128 else value})" for value in data)


def emit(output: Path) -> None:
    input_data = KWS_CORPUS_FIRST.read_bytes()
    result = execute_job(compile_kws(), input_data)
    output_data = bytes(value & 0xFF for value in result.output.data)
    output.mkdir(parents=True, exist_ok=True)
    header = output / "npu_acceptance_data.h"
    source = output / "npu_acceptance_data.c"
    header.write_text("""#ifndef RETROSOC_NPU_ACCEPTANCE_DATA_H
#define RETROSOC_NPU_ACCEPTANCE_DATA_H
#include <stdint.h>
#define RS_NPU_ACCEPTANCE_INPUT_BYTES UINT32_C(490)
#define RS_NPU_ACCEPTANCE_OUTPUT_BYTES UINT32_C(12)
extern const int8_t rs_npu_acceptance_input[490];
extern const int8_t rs_npu_acceptance_output[12];
#endif
""", encoding="ascii")
    source.write_text(f"""#include <stdint.h>
#include "npu_acceptance_data.h"
_Alignas(64) const int8_t rs_npu_acceptance_input[490] = {{{values(input_data)}}};
_Alignas(64) const int8_t rs_npu_acceptance_output[12] = {{{values(output_data)}}};
""", encoding="ascii")
    manifest = {
        "schema": 1,
        "workload": "kws",
        "input": KWS_CORPUS_FIRST.name,
        "input_sha256": hashlib.sha256(input_data).hexdigest(),
        "output_sha256": hashlib.sha256(output_data).hexdigest(),
        "output": list(result.output.data),
    }
    (output / "manifest.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path, required=True)
    emit(parser.parse_args().output_dir.resolve())


if __name__ == "__main__":
    main()
