#!/usr/bin/env python3
"""Deterministic Mini NPU ABI-1 compiler and static bare-metal plan emitter."""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

from npu_compiler_p0 import compile_model, write_artifacts  # noqa: E402
from npu_model import parse_tflite  # noqa: E402

COMPILER_REVISION = "npu-p5/1.0.1"
SYMBOL = re.compile(r"^[a-z][a-z0-9_]*$")


def _c_bytes(name: str, data: bytes, *, align: bool = True) -> str:
    payload = data or b"\x00"
    values = ",".join(f"0x{value:02x}U" for value in payload)
    alignment = "_Alignas(64) " if align else ""
    return f"{alignment}const uint8_t {name}[{len(payload)}] = {{{values}}};\n"


def _c_words(name: str, data: bytes) -> str:
    words = struct.unpack(f"<{len(data) // 4}I", data)
    values = ",".join(f"UINT32_C(0x{value:08x})" for value in words)
    return f"static const uint32_t {name}[{len(words)}] = {{{values}}};\n"


def _guard(prefix: str) -> str:
    return f"RETROSOC_GENERATED_{prefix.upper()}_NPU_H"


def emit_header(job, prefix: str) -> str:
    upper = prefix.upper()
    guard = _guard(prefix)
    output_bytes = job.report["output"]["bytes"]
    return f"""#ifndef {guard}
#define {guard}

#include <stdint.h>
#include <retrosoc/hal/npu.h>

#define RS_{upper}_NPU_ARENA_BYTES UINT32_C({job.arena_bytes})
#define RS_{upper}_NPU_INPUT_BYTES UINT32_C({job.report['input']['bytes']})
#define RS_{upper}_NPU_OUTPUT_BYTES UINT32_C({output_bytes})
#define RS_{upper}_NPU_DESCRIPTOR_COUNT UINT32_C({len(job.descriptors)})
#define RS_{upper}_NPU_REQUIRED_CAPABILITY UINT32_C(0x{job.report['required_capability_mask']:08X})
#define RS_{upper}_NPU_REQUIRED_OPCODES UINT32_C(0x{job.report['required_opcode_mask']:08X})

typedef struct {{
    uint32_t descriptor_base;
    uint32_t arena_base;
    uint32_t weights_base;
    uint32_t params_base;
}} rs_{prefix}_npu_regions_t;

typedef struct {{
    _Alignas(64) uint32_t descriptors[{len(job.descriptors)}][RS_NPU_DESCRIPTOR_WORDS];
    _Alignas(64) uint8_t arena[{job.arena_bytes}];
    rs_{prefix}_npu_regions_t regions;
    uint64_t input_copy_cycles;
    uint32_t prepared;
}} rs_{prefix}_npu_workspace_t;

typedef struct {{
    uint64_t input_copy_cycles;
    uint64_t npu_wait_cycles;
    uint64_t softmax_cycles;
    rs_npu_counters_t counters;
}} rs_{prefix}_npu_profile_t;

extern const uint8_t rs_{prefix}_npu_weights[{max(1, len(job.weights))}];
extern const uint8_t rs_{prefix}_npu_params[{max(1, len(job.params))}];

rs_status_t rs_{prefix}_npu_default_regions(rs_{prefix}_npu_workspace_t *workspace,
                                            rs_{prefix}_npu_regions_t *regions);
rs_status_t rs_{prefix}_npu_prepare(rs_{prefix}_npu_workspace_t *workspace,
                                    const rs_{prefix}_npu_regions_t *regions,
                                    const int8_t *input, uint32_t input_bytes);
rs_status_t rs_{prefix}_npu_execute(rs_{prefix}_npu_workspace_t *workspace,
                                    uint32_t job_id, rs_timeout_t timeout,
                                    int8_t *output, uint32_t output_bytes,
                                    rs_{prefix}_npu_profile_t *profile);
#if defined(RS_NPU_PLAN_TEST)
rs_status_t rs_{prefix}_npu_test_softmax(const int8_t *logits, int8_t *output);
#endif

#endif
"""


def _finalizer_c(prefix: str, params: dict | None, source_offset: int, output_bytes: int) -> str:
    if params is None:
        return f"""
static rs_status_t rs_{prefix}_finalize(const int8_t *logits, int8_t *output) {{
    uint32_t index;
    for (index = 0U; index < UINT32_C({output_bytes}); ++index) {{ output[index] = logits[index]; }}
    return RS_OK;
}}
#if defined(RS_NPU_PLAN_TEST)
rs_status_t rs_{prefix}_npu_test_softmax(const int8_t *logits, int8_t *output) {{
    if ((logits == NULL) || (output == NULL)) {{ return RS_EINVAL; }}
    return rs_{prefix}_finalize(logits, output);
}}
#endif
#define RS_{prefix.upper()}_NPU_LOGITS_OFFSET UINT32_C({source_offset})
"""
    barrel = ((-2, 1672461947), (-1, 1302514674), (0, 790015084),
              (1, 290630308), (2, 39332535), (3, 720401), (4, 242))
    conditions = "\n".join(
        f"    if ((remainder & (UINT32_C(1) << {26 + exponent}U)) != 0U) {{ result = rs_{prefix}_mul_high(result, INT32_C({value})); }}"
        for exponent, value in barrel
    )
    return f"""
static int32_t rs_{prefix}_trunc_div(int64_t numerator, int64_t denominator) {{
    int64_t value = numerator < 0 ? -numerator : numerator;
    value /= denominator;
    return (int32_t)(numerator < 0 ? -value : value);
}}
static int32_t rs_{prefix}_mul_high(int32_t a, int32_t b) {{
    int64_t product;
    int64_t nudge;
    if ((a == INT32_MIN) && (b == INT32_MIN)) {{ return INT32_MAX; }}
    product = (int64_t)a * (int64_t)b;
    nudge = product >= 0 ? INT64_C(1073741824) : -INT64_C(1073741823);
    return rs_{prefix}_trunc_div(product + nudge, INT64_C(2147483648));
}}
static int32_t rs_{prefix}_round_pot(int32_t value, uint32_t exponent) {{
    uint32_t mask;
    uint32_t remainder;
    uint32_t threshold;
    if (exponent == 0U) {{ return value; }}
    mask = (UINT32_C(1) << exponent) - UINT32_C(1);
    remainder = ((uint32_t)value) & mask;
    threshold = (mask >> 1U) + (value < 0 ? UINT32_C(1) : UINT32_C(0));
    return (value >> exponent) + (remainder > threshold ? 1 : 0);
}}
static int32_t rs_{prefix}_sat_shift(int32_t value, uint32_t exponent) {{
    int64_t shifted = (int64_t)value * ((int64_t)UINT32_C(1) << exponent);
    if (shifted > INT32_MAX) {{ return INT32_MAX; }}
    if (shifted < INT32_MIN) {{ return INT32_MIN; }}
    return (int32_t)shifted;
}}
static int32_t rs_{prefix}_exp_interval(int32_t value) {{
    int32_t x = value + INT32_C(268435456);
    int32_t x2 = rs_{prefix}_mul_high(x, x);
    int32_t x3 = rs_{prefix}_mul_high(x2, x);
    int32_t x4 = rs_{prefix}_mul_high(x2, x2);
    int32_t series = rs_{prefix}_round_pot(
        rs_{prefix}_mul_high(rs_{prefix}_round_pot(x4, 2U) + x3, INT32_C(715827883)) + x2, 1U);
    return INT32_C(1895147668) + rs_{prefix}_mul_high(INT32_C(1895147668), x + series);
}}
static int32_t rs_{prefix}_exp_negative(int32_t value) {{
    int32_t mod = (int32_t)(((uint32_t)value & UINT32_C(16777215)) - UINT32_C(16777216));
    uint32_t remainder = (uint32_t)(mod - value);
    int32_t result = rs_{prefix}_exp_interval(mod * 32);
{conditions}
    return value == 0 ? INT32_MAX : result;
}}
static int32_t rs_{prefix}_reciprocal(int32_t value) {{
    int64_t total = (int64_t)value + INT32_MAX;
    int32_t half = rs_{prefix}_trunc_div(total + (total >= 0 ? 1 : -1), 2);
    int32_t estimate = INT32_C(1515870810) + rs_{prefix}_mul_high(half, -INT32_C(1010580540));
    uint32_t iteration;
    for (iteration = 0U; iteration < 3U; ++iteration) {{
        int32_t product = rs_{prefix}_mul_high(half, estimate);
        int32_t increment = rs_{prefix}_mul_high(estimate, INT32_C(536870912) - product);
        estimate += rs_{prefix}_sat_shift(increment, 2U);
    }}
    return rs_{prefix}_sat_shift(estimate, 1U);
}}
static uint32_t rs_{prefix}_clz(uint32_t value) {{
    uint32_t count = 0U;
    while ((value & UINT32_C(0x80000000)) == 0U) {{ ++count; value <<= 1U; }}
    return count;
}}
static rs_status_t rs_{prefix}_finalize(const int8_t *logits, int8_t *output) {{
    int8_t maximum = INT8_MIN;
    int32_t exponentials[{output_bytes}];
    int64_t accumulation = 0;
    uint32_t index;
    uint32_t headroom;
    int32_t scale;
    int32_t shifted_sum;
    int32_t num_bits_over_unit;
    for (index = 0U; index < UINT32_C({output_bytes}); ++index) {{
        if (logits[index] > maximum) {{ maximum = logits[index]; }}
    }}
    for (index = 0U; index < UINT32_C({output_bytes}); ++index) {{
        int32_t difference = (int32_t)logits[index] - (int32_t)maximum;
        exponentials[index] = 0;
        if (difference >= INT32_C({params['diff_min']})) {{
            int64_t shifted = (int64_t)difference * ((int64_t)UINT32_C(1) << {params['input_left_shift']}U);
            int32_t scaled = rs_{prefix}_mul_high((int32_t)shifted, INT32_C({params['input_multiplier']}));
            exponentials[index] = rs_{prefix}_exp_negative(scaled);
            accumulation += rs_{prefix}_round_pot(exponentials[index], 12U);
        }}
    }}
    if ((accumulation <= 0) || (accumulation >= INT64_C(2147483648))) {{ return RS_EIO; }}
    headroom = rs_{prefix}_clz((uint32_t)accumulation);
    num_bits_over_unit = 12 - (int32_t)headroom;
    shifted_sum = (int32_t)(((uint32_t)accumulation << headroom) - UINT32_C(0x80000000));
    scale = rs_{prefix}_reciprocal(shifted_sum);
    for (index = 0U; index < UINT32_C({output_bytes}); ++index) {{
        int32_t quantized = -128;
        if (exponentials[index] != 0) {{
            int32_t value = rs_{prefix}_mul_high(scale, exponentials[index]);
            value = rs_{prefix}_round_pot(value, (uint32_t)(num_bits_over_unit + 23));
            quantized = value - 128;
            if (quantized > 127) {{ quantized = 127; }}
            if (quantized < -128) {{ quantized = -128; }}
        }}
        output[index] = (int8_t)quantized;
    }}
    return RS_OK;
}}
#if defined(RS_NPU_PLAN_TEST)
rs_status_t rs_{prefix}_npu_test_softmax(const int8_t *logits, int8_t *output) {{
    if ((logits == NULL) || (output == NULL)) {{ return RS_EINVAL; }}
    return rs_{prefix}_finalize(logits, output);
}}
#endif
#define RS_{prefix.upper()}_NPU_LOGITS_OFFSET UINT32_C({source_offset})
"""


def emit_source(job, prefix: str, header_name: str) -> str:
    descriptors = b"".join(item.to_bytes() for item in job.descriptors)
    relocations = ",".join(
        "{" + f"{item['descriptor_index']}U,{item['word_index']}U,"
        f"{ {'arena': 0, 'weights': 1, 'params': 2}[item['region']] }U,"
        f"UINT32_C({item['offset']})" + "}"
        for item in job.relocations
    )
    output = job.report["output"]
    source_descriptor = output["source_descriptor"]
    final = next(entry for entry in job.report["operators"]
                 if entry.get("descriptor_index") == source_descriptor)
    source_offset = final["arena"]["output_offset"]
    output_bytes = output["bytes"]
    softmax = job.steps[-1] if job.steps[-1].get("op") == "softmax" else None
    if softmax is not None and softmax["source_descriptor"] != source_descriptor:
        raise ValueError("internal: Softmax source descriptor disagrees with graph output")
    return f"""#include <limits.h>
#include <stddef.h>
#include <stdint.h>

#include "{header_name}"

typedef struct {{ uint16_t descriptor; uint8_t word; uint8_t region; uint32_t offset; }} rs_{prefix}_reloc_t;
{_c_words(f'rs_{prefix}_npu_templates', descriptors)}
static const rs_{prefix}_reloc_t rs_{prefix}_npu_relocations[{len(job.relocations)}] = {{{relocations}}};
{_c_bytes(f'rs_{prefix}_npu_weights', job.weights)}
{_c_bytes(f'rs_{prefix}_npu_params', job.params)}

static uint64_t rs_{prefix}_cycles(void) {{
#if defined(__riscv)
    uint32_t high0; uint32_t low; uint32_t high1;
    do {{ __asm__ volatile("rdcycleh %0" : "=r"(high0));
         __asm__ volatile("rdcycle %0" : "=r"(low));
         __asm__ volatile("rdcycleh %0" : "=r"(high1)); }} while (high0 != high1);
    return ((uint64_t)high0 << 32U) | low;
#else
    return UINT64_C(0);
#endif
}}
static void rs_{prefix}_fence(void) {{
#if defined(__riscv)
    __asm__ volatile("fence rw, rw" ::: "memory");
#else
    __asm__ volatile("" ::: "memory");
#endif
}}
static void rs_{prefix}_cache_clean(const void *pointer, uint32_t bytes) {{
#if defined(__riscv_zicbom)
    uintptr_t cursor = (uintptr_t)pointer & ~(uintptr_t)UINT32_C(63);
    uintptr_t end = ((uintptr_t)pointer + bytes + UINT32_C(63)) & ~(uintptr_t)UINT32_C(63);
    while (cursor < end) {{ __asm__ volatile("cbo.clean 0(%0)" :: "r"(cursor) : "memory"); cursor += 64U; }}
#else
    (void)pointer; (void)bytes;
#endif
    rs_{prefix}_fence();
}}
static void rs_{prefix}_cache_invalidate(const void *pointer, uint32_t bytes) {{
#if defined(__riscv_zicbom)
    uintptr_t cursor = (uintptr_t)pointer & ~(uintptr_t)UINT32_C(63);
    uintptr_t end = ((uintptr_t)pointer + bytes + UINT32_C(63)) & ~(uintptr_t)UINT32_C(63);
    while (cursor < end) {{ __asm__ volatile("cbo.inval 0(%0)" :: "r"(cursor) : "memory"); cursor += 64U; }}
#else
    (void)pointer; (void)bytes;
#endif
    rs_{prefix}_fence();
}}
{_finalizer_c(prefix, softmax, source_offset, output_bytes)}

static rs_status_t rs_{prefix}_address(const void *pointer, uint32_t *address) {{
    uintptr_t value;
    if ((pointer == NULL) || (address == NULL)) {{ return RS_EINVAL; }}
    value = (uintptr_t)pointer;
    if (value > UINT32_MAX) {{ return RS_EINVAL; }}
    *address = (uint32_t)value;
    return RS_OK;
}}
rs_status_t rs_{prefix}_npu_default_regions(rs_{prefix}_npu_workspace_t *workspace,
                                            rs_{prefix}_npu_regions_t *regions) {{
    if ((workspace == NULL) || (regions == NULL)) {{ return RS_EINVAL; }}
    if ((rs_{prefix}_address(workspace->descriptors, &regions->descriptor_base) != RS_OK) ||
        (rs_{prefix}_address(workspace->arena, &regions->arena_base) != RS_OK) ||
        (rs_{prefix}_address(rs_{prefix}_npu_weights, &regions->weights_base) != RS_OK) ||
        (rs_{prefix}_address(rs_{prefix}_npu_params, &regions->params_base) != RS_OK)) {{ return RS_EINVAL; }}
    return RS_OK;
}}
rs_status_t rs_{prefix}_npu_prepare(rs_{prefix}_npu_workspace_t *workspace,
                                    const rs_{prefix}_npu_regions_t *regions,
                                    const int8_t *input, uint32_t input_bytes) {{
    uint32_t expected[4]; uint32_t index; uint64_t start;
    if (workspace == NULL) {{ return RS_EINVAL; }}
    workspace->prepared = 0U;
    if ((regions == NULL) || (input == NULL) ||
        (input_bytes != RS_{prefix.upper()}_NPU_INPUT_BYTES)) {{ return RS_EINVAL; }}
    if ((rs_{prefix}_address(workspace->descriptors, &expected[0]) != RS_OK) ||
        (rs_{prefix}_address(workspace->arena, &expected[1]) != RS_OK) ||
        (rs_{prefix}_address(rs_{prefix}_npu_weights, &expected[2]) != RS_OK) ||
        (rs_{prefix}_address(rs_{prefix}_npu_params, &expected[3]) != RS_OK) ||
        (regions->descriptor_base != expected[0]) || (regions->arena_base != expected[1]) ||
        (regions->weights_base != expected[2]) || (regions->params_base != expected[3]) ||
        ((regions->descriptor_base | regions->arena_base | regions->weights_base |
          regions->params_base) & UINT32_C(63)) != 0U) {{ return RS_EINVAL; }}
    start = rs_{prefix}_cycles();
    for (index = 0U; index < UINT32_C({len(descriptors) // 4}); ++index) {{
        ((uint32_t *)workspace->descriptors)[index] = rs_{prefix}_npu_templates[index];
    }}
    for (index = 0U; index < RS_{prefix.upper()}_NPU_ARENA_BYTES; ++index) {{ workspace->arena[index] = 0U; }}
    for (index = 0U; index < input_bytes; ++index) {{ workspace->arena[UINT32_C({job.input_offset}) + index] = (uint8_t)input[index]; }}
    for (index = 0U; index < UINT32_C({len(job.relocations)}); ++index) {{
        const rs_{prefix}_reloc_t *reloc = &rs_{prefix}_npu_relocations[index];
        uint32_t base = reloc->region == 0U ? regions->arena_base :
                        (reloc->region == 1U ? regions->weights_base : regions->params_base);
        uint64_t value = (uint64_t)base + reloc->offset;
        uint32_t *word = &workspace->descriptors[reloc->descriptor][reloc->word];
        if ((value > UINT32_MAX) || (*word != reloc->offset)) {{ return RS_EFORMAT; }}
        *word = (uint32_t)value;
    }}
    workspace->regions = *regions;
    workspace->input_copy_cycles = rs_{prefix}_cycles() - start;
    workspace->prepared = UINT32_C(0x4E505531);
    return RS_OK;
}}
rs_status_t rs_{prefix}_npu_execute(rs_{prefix}_npu_workspace_t *workspace,
                                    uint32_t job_id, rs_timeout_t timeout,
                                    int8_t *output, uint32_t output_bytes,
                                    rs_{prefix}_npu_profile_t *profile) {{
    rs_npu_capability_t capability; rs_npu_status_t state; rs_npu_job_t job;
    rs_status_t result; uint64_t started;
    if ((workspace == NULL) || (output == NULL) || (profile == NULL) ||
        (workspace->prepared != UINT32_C(0x4E505531)) ||
        (output_bytes != RS_{prefix.upper()}_NPU_OUTPUT_BYTES)) {{ return RS_EINVAL; }}
    result = rs_npu_get_capability(&capability);
    if (result != RS_OK) {{ return result; }}
    if (((capability.flags & RS_{prefix.upper()}_NPU_REQUIRED_CAPABILITY) != RS_{prefix.upper()}_NPU_REQUIRED_CAPABILITY) ||
        ((capability.op_mask & RS_{prefix.upper()}_NPU_REQUIRED_OPCODES) != RS_{prefix.upper()}_NPU_REQUIRED_OPCODES) ||
        (capability.numeric_profile != RS_NPU_NUMERIC_PROFILE_VALUE)) {{ return RS_ENOTSUP; }}
    rs_{prefix}_cache_clean(workspace->descriptors, sizeof(workspace->descriptors));
    rs_{prefix}_cache_clean(workspace->arena, sizeof(workspace->arena));
    rs_{prefix}_cache_clean(rs_{prefix}_npu_weights, UINT32_C({len(job.weights)}));
    rs_{prefix}_cache_clean(rs_{prefix}_npu_params, UINT32_C({len(job.params)}));
    rs_{prefix}_cache_invalidate(&workspace->arena[RS_{prefix.upper()}_NPU_LOGITS_OFFSET], output_bytes);
    job.descriptor_address = workspace->regions.descriptor_base;
    job.descriptor_count = RS_{prefix.upper()}_NPU_DESCRIPTOR_COUNT;
    job.job_id = job_id; job.timeout_cycles = UINT32_C(72000000);
    started = rs_{prefix}_cycles(); result = rs_npu_submit(&job);
    if (result == RS_OK) {{ result = rs_npu_wait(job_id, timeout, &state); }}
    profile->npu_wait_cycles = rs_{prefix}_cycles() - started;
    if (result != RS_OK) {{ return result; }}
    rs_{prefix}_cache_invalidate(&workspace->arena[RS_{prefix.upper()}_NPU_LOGITS_OFFSET], output_bytes);
    started = rs_{prefix}_cycles();
    result = rs_{prefix}_finalize((const int8_t *)&workspace->arena[RS_{prefix.upper()}_NPU_LOGITS_OFFSET], output);
    profile->softmax_cycles = rs_{prefix}_cycles() - started;
    profile->input_copy_cycles = workspace->input_copy_cycles;
    if (result == RS_OK) {{ result = rs_npu_snapshot_counters(timeout, &profile->counters); }}
    return result;
}}
"""


def compile_package(model: Path, workload: str, prefix: str, output: Path,
                    expected_sha256: str | None, preprocessing: str) -> dict:
    payload = model.read_bytes()
    digest = hashlib.sha256(payload).hexdigest()
    if expected_sha256 is not None and digest != expected_sha256:
        raise ValueError(f"source model SHA-256 {digest} does not match {expected_sha256}")
    parsed = parse_tflite(payload)
    if parsed.version != 3 or len(parsed.subgraphs) != 1:
        raise ValueError("compiler accepts one TFLite v3 subgraph")
    job = compile_model(parsed.main_graph(), workload=workload, source_model_sha256=digest)
    job.report["compiler"]["contract"] = COMPILER_REVISION
    manifest = write_artifacts(job, output)
    manifest["compiler"]["contract"] = COMPILER_REVISION
    manifest["preprocessing"] = {"kind": preprocessing, "placement": "application"}
    manifest["required_capability_mask"] = manifest["required_capability_mask"]
    job.report["required_capability_mask"] = manifest["required_capability_mask"]
    job.report["required_opcode_mask"] = manifest["required_opcode_mask"]
    header = output / f"{prefix}_npu.h"
    source = output / f"{prefix}_npu.c"
    header.write_text(emit_header(job, prefix), encoding="ascii")
    source.write_text(emit_source(job, prefix, header.name), encoding="ascii")
    for path in (header, source):
        data = path.read_bytes()
        manifest["files"][path.name] = {
            "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()
        }
    manifest["report"]["compiler"]["contract"] = COMPILER_REVISION
    (output / "npu.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    return manifest


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--model", type=Path, required=True)
    parser.add_argument("--workload", required=True)
    parser.add_argument("--symbol-prefix", required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--expected-sha256")
    parser.add_argument("--preprocessing", default="application-defined")
    args = parser.parse_args()
    if not SYMBOL.fullmatch(args.symbol_prefix):
        parser.error("--symbol-prefix must be lowercase C snake_case")
    try:
        compile_package(args.model, args.workload, args.symbol_prefix,
                        args.output_dir.resolve(), args.expected_sha256, args.preprocessing)
    except (OSError, ValueError) as error:
        parser.exit(2, f"NPU compiler error: {error}\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
