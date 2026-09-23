"""NPU-P5 production compiler, complete placement and generated-C tests."""
from __future__ import annotations

import dataclasses
import hashlib
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
sys.path.insert(0, str(ROOT / "tests"))

from npu_compiler import compile_package, emit_header, emit_source  # noqa: E402
from npu_compiler_p0 import compile_model, evaluate_reference  # noqa: E402
from npu_executor import execute_job  # noqa: E402
from npu_model import (  # noqa: E402
    KWS_TFLITE_PATH, KWS_TFLITE_SHA256, VWW_TFLITE_PATH, VWW_TFLITE_SHA256,
    GraphInfo, OperatorInfo,
)
from npu_reference import Tensor, add, quantize_multiplier  # noqa: E402
from test_npu_executor import _conv_graph, _raw, _tensor, _values  # noqa: E402


def _pool_graph(opcode: int, name: str) -> GraphInfo:
    cin = 4
    tensors = (
        _tensor("input", (1, 4, 4, cin), scales=(0.25,), zps=(-3,)),
        _tensor("output", (1, 2, 2, cin), scales=(0.25,), zps=(-3,)),
    )
    op = OperatorInfo(opcode, name, (0,), (1,), {
        "padding": "VALID", "stride_w": 2, "stride_h": 2,
        "filter_width": 2, "filter_height": 2, "fused_activation": "NONE",
    })
    return GraphInfo(tensors, (op,), (0,), (1,))


@pytest.mark.parametrize("opcode,name,abi", [
    (17, "MAX_POOL_2D", 5), (1, "AVERAGE_POOL_2D", 6),
])
def test_local_pool_placement_and_execution(opcode, name, abi):
    graph = _pool_graph(opcode, name)
    job = compile_model(graph, workload="pool")
    assert job.descriptors[0].opcode == abi
    assert execute_job(job, _raw(_values(64))).output.shape == (2, 2, 4)


def test_maximum_local_pool_uses_one_resident_position():
    tensors = (
        _tensor("input", (1, 17, 20, 8), scales=(0.25,), zps=(0,)),
        _tensor("output", (1, 2, 5, 8), scales=(0.25,), zps=(0,)),
    )
    op = OperatorInfo(17, "MAX_POOL_2D", (0,), (1,), {
        "padding": "VALID", "stride_w": 1, "stride_h": 1,
        "filter_width": 16, "filter_height": 16, "fused_activation": "NONE",
    })
    job = compile_model(GraphInfo(tensors, (op,), (0,), (1,)), workload="max-pool-16")
    buffers = job.report["operators"][0]["buffers"]
    assert buffers["raw_gather_half_bytes"] == 16 * 16 * 8
    assert buffers["packed_a_bytes"] == 0
    assert execute_job(job, _raw(_values(17 * 20 * 8))).output.shape == (2, 5, 8)


def test_dma_report_accounts_for_reload_boundaries():
    params = compile_model(
        _conv_graph(1, 3, 4, 4096, 1, 1), workload="param-window-reload"
    ).report["operators"][0]["dma"]
    assert params["param_tensor_fetches"] == 2
    assert params["param_read_bytes"] == 2 * 65536
    assert params["read_bytes"] == 147468
    assert params["estimated_cycles"] == 26114

    reduction = compile_model(
        _conv_graph(1, 1, 1025, 16, 1, 1), workload="input-reload"
    ).report["operators"][0]["dma"]
    assert reduction["input_tensor_fetches"] == 2
    assert reduction["gather_read_bytes"] == 2 * 1025

    tensors = (
        _tensor("input", (1, 3, 3, 1), scales=(0.25,), zps=(0,)),
        _tensor("output", (1, 3, 3, 1), scales=(0.25,), zps=(0,)),
    )
    pool = OperatorInfo(17, "MAX_POOL_2D", (0,), (1,), {
        "padding": "SAME", "stride_w": 1, "stride_h": 1,
        "filter_width": 3, "filter_height": 3, "fused_activation": "NONE",
    })
    pooling = compile_model(
        GraphInfo(tensors, (pool,), (0,), (1,)), workload="valid-pool-reads"
    ).report["operators"][0]["dma"]
    assert pooling["gather_read_bytes"] == 49


def test_clamp_and_branched_add_placement():
    tensors = (
        _tensor("input", (1, 2, 2, 4), scales=(0.4,), zps=(0,)),
        _tensor("left", (1, 2, 2, 4), scales=(0.4,), zps=(0,)),
        _tensor("right", (1, 2, 2, 4), scales=(0.4,), zps=(0,)),
        _tensor("sum", (1, 2, 2, 4), scales=(0.2,), zps=(-4,)),
    )
    ops = (
        OperatorInfo(19, "RELU", (0,), (1,), {}),
        OperatorInfo(21, "RELU6", (0,), (2,), {}),
        OperatorInfo(0, "ADD", (1, 2), (3,), {"fused_activation": "NONE"}),
    )
    graph = GraphInfo(tensors, ops, (0,), (3,))
    job = compile_model(graph, workload="branched-add")
    assert [desc.opcode for desc in job.descriptors] == [8, 8, 4]
    assert any(item["word_index"] == 3 for item in job.relocations)
    values = _values(16)
    result = execute_job(job, _raw(values)).output
    left = Tensor((2, 2, 4), tuple(max(0, value) for value in values), 0.4, 0)
    right = Tensor((2, 2, 4), tuple(max(0, min(15, value)) for value in values), 0.4, 0)
    m0, s0 = quantize_multiplier(0.5)
    m1, s1 = quantize_multiplier(0.5)
    mout, sout = quantize_multiplier(0.8 / ((1 << 20) * 0.2))
    expected = add(left, right, input0_multiplier=m0, input0_shift=s0,
                   input1_multiplier=m1, input1_shift=s1,
                   output_multiplier=mout, output_shift=sout,
                   output_scale=0.2, output_zero_point=-4,
                   act_min=-128, act_max=127)
    assert result == expected


def test_terminal_softmax_uses_its_actual_tensor_producer():
    tensors = (
        _tensor("input", (1, 1, 1, 2), scales=(0.25,), zps=(0,)),
        _tensor("relu", (1, 1, 1, 2), scales=(0.25,), zps=(0,)),
        _tensor("relu6", (1, 1, 1, 2), scales=(0.25,), zps=(0,)),
        _tensor("softmax", (1, 1, 1, 2), scales=(1.0 / 256.0,), zps=(-128,)),
    )
    operators = (
        OperatorInfo(19, "RELU", (0,), (1,), {}),
        OperatorInfo(21, "RELU6", (0,), (2,), {}),
        OperatorInfo(25, "SOFTMAX", (1,), (3,), {"beta": 1.0}),
    )
    graph = GraphInfo(tensors, operators, (0,), (3,))
    job = compile_model(graph, workload="branched-softmax")
    result = execute_job(job, _raw((100, -50)))

    assert job.steps[-1]["source_descriptor"] == 0
    assert job.report["output"]["source_descriptor"] == 0
    assert result.output == evaluate_reference(graph, _raw((100, -50)))[-1]
    first = job.report["operators"][0]["arena"]["output_offset"]
    second = job.report["operators"][1]["arena"]["output_offset"]
    assert first != second
    job.report["required_capability_mask"] = 0x12
    job.report["required_opcode_mask"] = sum(1 << desc.opcode for desc in job.descriptors)
    source = emit_source(job, "branch", "branch_npu.h")
    header = emit_header(job, "branch")
    assert f"#define RS_BRANCH_NPU_LOGITS_OFFSET UINT32_C({first})" in source
    assert "#define RS_BRANCH_NPU_OUTPUT_BYTES UINT32_C(2)" in header

    with pytest.raises(ValueError, match="exactly one output"):
        compile_model(
            GraphInfo(tensors[:3], operators[:2], (0,), (1, 2)), workload="multi-output"
        )


def test_broadcast_and_quantization_rejections():
    graph = _pool_graph(17, "MAX_POOL_2D")
    broken = dataclasses.replace(graph, tensors=(graph.tensors[0],
        dataclasses.replace(graph.tensors[1], scales=(0.5,))))
    with pytest.raises(ValueError, match="equal quantization"):
        compile_model(broken, workload="bad-pool")
    tensors = (
        _tensor("a", (1, 2, 2, 4)), _tensor("b", (1, 1, 1, 4)),
        _tensor("out", (1, 2, 2, 4)),
    )
    add_op = OperatorInfo(0, "ADD", (0, 1), (2,), {"fused_activation": "NONE"})
    with pytest.raises(ValueError, match="broadcasting"):
        compile_model(GraphInfo(tensors, (add_op,), (0,), (2,)), workload="bad-add")


def _generated_headers(root: Path) -> Path:
    include = root / "include/retrosoc/generated"
    include.mkdir(parents=True)
    (include / "memory_map.h").write_text(
        "#ifndef RS_MM\n#define RS_MM\n#define RS_SOC_APB4_NPU_BASE 0x1001B000U\n#endif\n"
    )
    (include / "user_extensions.h").write_text(
        "#ifndef RS_UE\n#define RS_UE\n#endif\n"
    )
    return root / "include"


def _hal_stubs(prefix: str, logits: tuple[int, ...], expected: tuple[int, ...]) -> str:
    logits_c = ",".join(str(value) for value in logits)
    expected_c = ",".join(str(value) for value in expected)
    return f"""
#include <stdint.h>
#include <retrosoc/hal/npu.h>
#include "{prefix}_npu.h"
rs_status_t rs_npu_get_capability(rs_npu_capability_t *p) {{ (void)p; return RS_ENOTSUP; }}
rs_status_t rs_npu_submit(const rs_npu_job_t *p) {{ (void)p; return RS_ENOTSUP; }}
rs_status_t rs_npu_wait(uint32_t a, rs_timeout_t b, rs_npu_status_t *c) {{ (void)a;(void)b;(void)c;return RS_ENOTSUP; }}
rs_status_t rs_npu_abort_wait(uint32_t a, rs_timeout_t b, rs_npu_status_t *c) {{ (void)a;(void)b;(void)c;return RS_ENOTSUP; }}
rs_status_t rs_npu_reset(rs_timeout_t a) {{ (void)a; return RS_ENOTSUP; }}
rs_status_t rs_npu_get_status(rs_npu_status_t *p) {{ (void)p; return RS_ENOTSUP; }}
rs_status_t rs_npu_get_error(rs_npu_error_t *p) {{ (void)p; return RS_ENOTSUP; }}
rs_status_t rs_npu_snapshot_counters(rs_timeout_t a, rs_npu_counters_t *b) {{ (void)a;(void)b;return RS_ENOTSUP; }}
rs_status_t rs_npu_irq_enable(uint32_t a) {{ (void)a; return RS_ENOTSUP; }}
rs_status_t rs_npu_irq_pending(uint32_t *a) {{ (void)a; return RS_ENOTSUP; }}
rs_status_t rs_npu_irq_ack(uint32_t a) {{ (void)a; return RS_ENOTSUP; }}
int main(void) {{
    const int8_t input[] = {{{logits_c}}};
    const int8_t expected[] = {{{expected_c}}};
    int8_t output[sizeof(input)]; uint32_t i;
    static rs_{prefix}_npu_workspace_t workspace;
    static int8_t model_input[RS_{prefix.upper()}_NPU_INPUT_BYTES];
    static int8_t model_output[RS_{prefix.upper()}_NPU_OUTPUT_BYTES];
    rs_{prefix}_npu_regions_t regions;
    rs_{prefix}_npu_profile_t profile;
    if (rs_{prefix}_npu_test_softmax(input, output) != RS_OK) return 1;
    for (i = 0; i < sizeof(input); ++i) if (output[i] != expected[i]) return 2;
    if (rs_{prefix}_npu_default_regions(&workspace, &regions) != RS_OK) return 3;
    if (rs_{prefix}_npu_prepare(&workspace, &regions, model_input,
                                RS_{prefix.upper()}_NPU_INPUT_BYTES) != RS_OK) return 4;
    if (rs_{prefix}_npu_prepare(&workspace, &regions, model_input,
                                RS_{prefix.upper()}_NPU_INPUT_BYTES - 1U) != RS_EINVAL) return 5;
    if (rs_{prefix}_npu_execute(&workspace, 1U, 0U, model_output,
                                RS_{prefix.upper()}_NPU_OUTPUT_BYTES, &profile) != RS_EINVAL) return 6;
    return 0;
}}
"""


@pytest.mark.parametrize("name,model,digest,logits,expected", [
    ("kws", KWS_TFLITE_PATH, KWS_TFLITE_SHA256,
     (12, -3, 15, -20, 7, 25, -31, 13, -9, 5, -17, 30),
     (-118, -127, -112, -128, -123, -60, -128, -116, -128, -124, -128, 11)),
    ("vww", VWW_TFLITE_PATH, VWW_TFLITE_SHA256, (-114, 115), (-119, 119)),
])
def test_reproducible_package_and_generated_c(tmp_path, name, model, digest, logits, expected):
    if not model.is_file():
        pytest.fail(f"missing locked model: {model}")
    first, second = tmp_path / "first", tmp_path / "second"
    a = compile_package(model, name, name, first, digest, "test-input")
    b = compile_package(model, name, name, second, digest, "test-input")
    assert a == b
    assert {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in first.iterdir()} == {
        p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in second.iterdir()
    }
    assert a["schema"] == 1 and a["compiler"]["contract"] == "npu-p5/1.0.1"
    assert {"descriptors.bin", "weights.bin", "params.bin", f"{name}_npu.c",
            f"{name}_npu.h"} <= set(a["files"])
    if name == "vww":
        streamed = [entry for entry in a["report"]["operators"]
                    if entry.get("weights") is not None and
                    entry["weights"]["bytes"] > 16384]
        assert [entry["dma"]["weight_tensor_fetches"] for entry in streamed] == [2, 2]
        assert [entry["reloads"]["weight_tensors"] for entry in streamed] == [2, 2]
    descriptor_bytes = a["report"]["totals"]["descriptors"] * 128
    operator_reads = sum(entry.get("dma", {}).get("read_bytes", 0)
                         for entry in a["report"]["operators"])
    assert a["report"]["totals"]["descriptor_read_bytes"] == descriptor_bytes
    assert a["report"]["totals"]["dma_read_bytes"] == descriptor_bytes + operator_reads
    compiler = shutil.which("cc")
    if compiler is None:
        pytest.fail("host C compiler is required")
    include = _generated_headers(tmp_path / "generated")
    harness = tmp_path / "harness.c"
    harness.write_text(_hal_stubs(name, logits, expected))
    executable = tmp_path / "plan-test"
    subprocess.run([
        compiler, "-std=c11", "-Wall", "-Wextra", "-Werror", "-Wmissing-prototypes", "-no-pie",
        "-DRS_NPU_PLAN_TEST", f"-I{include}", f"-I{ROOT / 'crt/include'}", f"-I{first}",
        str(first / f"{name}_npu.c"), str(harness), "-o", str(executable),
    ], check=True)
    subprocess.run([str(executable)], check=True)


def test_malformed_model_and_hash_diagnostics(tmp_path):
    malformed = tmp_path / "bad.tflite"
    malformed.write_bytes(b"not tflite")
    with pytest.raises(ValueError):
        compile_package(malformed, "bad", "bad", tmp_path / "out", None, "none")
    with pytest.raises(ValueError, match="SHA-256"):
        compile_package(KWS_TFLITE_PATH, "kws", "kws", tmp_path / "wrong", "0" * 64, "none")
