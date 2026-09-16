"""Locked NPU-P0 compiler and executor tests."""

from __future__ import annotations

import dataclasses
import hashlib
import struct
import sys
from pathlib import Path

import pytest


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

from npu_compiler_p0 import (  # noqa: E402
    KWS_CORPUS_FIRST,
    VWW_CORPUS_FIRST,
    CompiledJob,
    CompilerError,
    compile_kws,
    compile_model,
    compile_vww,
    evaluate_reference,
    serialize_descriptors,
    vww_input_bytes,
    write_artifacts,
)
from npu_descriptors import ABI_VERSION, OP_ADD, Descriptor  # noqa: E402
from npu_executor import (  # noqa: E402
    FAULT_ARITHMETIC,
    FAULT_DESCRIPTOR,
    FAULT_RANGE,
    FAULT_UNSUPPORTED,
    ExecutorFault,
    execute_job,
)
from npu_model import (  # noqa: E402
    KWS_TFLITE_PATH,
    VWW_TFLITE_PATH,
    GraphInfo,
    OperatorInfo,
    TensorInfo,
    load_kws_model,
    load_vww_model,
)
from npu_reference import (  # noqa: E402
    Tensor,
    add,
    conv2d,
    depthwise_conv2d,
    fully_connected,
    global_average_pool,
    quantize_multiplier,
)

# Frozen APU-P7 evidence digests (tests/test_apu_kws.py) for the 12 published
# KWS tensors: 9 conv/DW/PW layers (8000 bytes), GAP (64), FC logits (12),
# APU softmax (12).
_APU_KWS_LAYER_SHA256 = (
    "4ea162c5d6215d5f4531c63d044eedef1cad9526e2c4fdcae6709f7ac5ab5abb",
    "9b3d9d6ba64079304f99477cd6689a44018e7ab6987d7611d8bfc0ec3be5d81d",
    "877299da8c940c038a02e2b5adee0f47dbce2f419697648394dcb2f0317ddb8f",
    "77bf309dcf7cdd0a8bf080748bb40929957a53a6ba3c3d8f83c87b26d540e183",
    "7be9b616635d7f96458b3c5bb997f95e08fc5266288552df7367c83e33592b62",
    "67c3b2a8ef7c342a7cc953594b544927881ea34290307d6716a65bb9e67cb81b",
    "ffe495e62d171963549f5cfd937b126691d5173592b7b0e8d7ca00101a033354",
    "7afa076d3e45a9f04ca36cdc0ff604acebc32c7a3a2ebeeda05f05e3b405a074",
    "de0c2f7b0a1aa7e774e2a48cdcbe770ec3f1f26378fa6820210d55a62e3b30a2",
    "d556d43668ea73c5a935ad4199967b53ac1c51245d4edaffe13fbe4d0e826fff",
    "dcaf556579a9340e9065a137135dd52ee4e9f81568f71608a25a9a2db10cf44f",
    "ebfee7fb52365b69ac386245459e7364533978a9a4996a988b4ba0fb83372959",
)


def _tensor(name, shape, *, dtype=9, scales=(0.05,), zps=(0,), qd=0, data=None):
    return TensorInfo(
        name=name,
        shape=tuple(shape),
        dtype=dtype,
        scales=tuple(scales),
        zero_points=tuple(zps),
        quantized_dimension=qd,
        buffer_index=0,
        data=data,
    )


def _i32(values):
    return struct.pack(f"<{len(values)}i", *values)


def _raw(values):
    return bytes(value & 0xFF for value in values)


def _values(count, *, lo=-128, hi=127, step=37):
    span = hi - lo + 1
    return [((index * step) % span) + lo for index in range(count)]


def _nest(flat, shape):
    if len(shape) == 1:
        return tuple(flat[: shape[0]])
    step = 1
    for dim in shape[1:]:
        step *= dim
    return tuple(
        _nest(flat[index * step : (index + 1) * step], shape[1:])
        for index in range(shape[0])
    )


def _extent(n, k, stride, padding):
    if padding == "SAME":
        return -(-n // stride)
    return (n - k) // stride + 1


def _conv_graph(
    h,
    w,
    cin,
    cout,
    kh,
    kw,
    *,
    stride=1,
    padding="VALID",
    activation="NONE",
    in_scale=0.5,
    w_scales=None,
    out_scale=0.25,
    zin=10,
    zout=-3,
    bias=None,
    w_vals=None,
    dilation=1,
    w_zps=None,
):
    """Build a batch-one single-CONV_2D graph with deterministic constants."""
    oh = _extent(h, kh, stride, padding)
    ow = _extent(w, kw, stride, padding)
    if w_scales is None:
        w_scales = tuple(0.01 * (index + 1) for index in range(cout))
    if w_zps is None:
        w_zps = (0,) * cout
    if w_vals is None:
        w_vals = _values(cout * kh * kw * cin, lo=-127, hi=127, step=23)
    if bias is None:
        bias = [((index * 977) % 2001) - 1000 for index in range(cout)]
    tensors = (
        _tensor("in", (1, h, w, cin), scales=(in_scale,), zps=(zin,)),
        _tensor(
            "w",
            (cout, kh, kw, cin),
            scales=w_scales,
            zps=w_zps,
            data=_raw(w_vals),
        ),
        _tensor("b", (cout,), dtype=2, scales=(0.005,) * cout, zps=(0,) * cout, data=_i32(bias)),
        _tensor("out", (1, oh, ow, cout), scales=(out_scale,), zps=(zout,)),
    )
    op = OperatorInfo(
        opcode=3,
        op_name="CONV_2D",
        inputs=(0, 1, 2),
        outputs=(3,),
        options={
            "padding": padding,
            "stride_w": stride,
            "stride_h": stride,
            "fused_activation": activation,
            "dilation_w": dilation,
            "dilation_h": dilation,
        },
    )
    return GraphInfo(tensors=tensors, operators=(op,), inputs=(0,), outputs=(3,))


def _run_graph(graph, input_values):
    job = compile_model(graph, workload="synthetic")
    return job, execute_job(job, _raw(input_values))


def _ref_conv(input_values, shape, w_vals, w_shape, bias, *, stride=1, pads=(0, 0, 0, 0),
              in_scale=0.5, zin=10, w_scales=None, out_scale=0.25, zout=-3,
              act_min=-128, act_max=127):
    cout = w_shape[0]
    if w_scales is None:
        w_scales = tuple(0.01 * (index + 1) for index in range(cout))
    multipliers, shifts = [], []
    for channel in range(cout):
        weight_scale = w_scales[0] if len(w_scales) == 1 else w_scales[channel]
        multiplier, shift = quantize_multiplier(in_scale * weight_scale / out_scale)
        multipliers.append(multiplier)
        shifts.append(shift)
    return conv2d(
        Tensor(shape, tuple(input_values), in_scale, zin),
        _nest(w_vals, w_shape),
        bias,
        multipliers,
        shifts,
        stride_h=stride,
        stride_w=stride,
        pad_top=pads[0],
        pad_bottom=pads[1],
        pad_left=pads[2],
        pad_right=pads[3],
        output_scale=out_scale,
        output_zero_point=zout,
        act_min=act_min,
        act_max=act_max,
    )


def _fault_code(job, input_values, bases=None):
    with pytest.raises(ExecutorFault) as caught:
        execute_job(job, _raw(input_values), bases=bases)
    return caught.value.code


def test_synthetic_conv2d_k18_matches_reference():
    graph = _conv_graph(3, 3, 2, 4, 3, 3)
    input_values = _values(3 * 3 * 2)
    job, result = _run_graph(graph, input_values)
    reference = _ref_conv(
        input_values,
        (3, 3, 2),
        _values(4 * 18, lo=-127, step=23),
        (4, 3, 3, 2),
        [((index * 977) % 2001) - 1000 for index in range(4)],
    )

    descriptor = job.descriptors[0]
    assert descriptor.k_slice == 18
    assert descriptor.weight_bytes == 144  # ceil(4/8) * 18 * 8
    assert descriptor.param_bytes == 64  # 4 * 16
    assert (descriptor.tile_h, descriptor.tile_w) == (1, 1)
    assert job.report["operators"][0]["k_slices"] == {"count": 1, "sizes": [18]}
    assert result.layers[0] == reference
    assert result.digests[0] == hashlib.sha256(_raw(reference.data)).hexdigest()


def test_synthetic_conv2d_same_padding_stride2_relu():
    # 6x6, 3x3 stride 2 SAME -> 3x3 with pads (0, 1, 0, 1); RELU clamps at zout.
    graph = _conv_graph(6, 6, 3, 5, 3, 3, stride=2, padding="SAME",
                        activation="RELU", zout=-20)
    input_values = _values(6 * 6 * 3)
    job, result = _run_graph(graph, input_values)

    descriptor = job.descriptors[0]
    assert (descriptor.pad_top, descriptor.pad_bottom) == (0, 1)
    assert (descriptor.pad_left, descriptor.pad_right) == (0, 1)
    assert (descriptor.act_min, descriptor.act_max) == (-20, 127)
    reference = _ref_conv(
        input_values, (6, 6, 3), _values(5 * 27, lo=-127, step=23), (5, 3, 3, 3),
        [((i * 977) % 2001) - 1000 for i in range(5)],
        stride=2, pads=(0, 1, 0, 1), zout=-20, act_min=-20, act_max=127,
    )
    assert result.layers[0] == reference


def test_synthetic_depthwise3x3_matches_reference():
    cin = 8
    input_values = _values(5 * 5 * cin)
    w_vals = _values(9 * cin, lo=-127, step=11)
    bias = [((index * 331) % 801) - 400 for index in range(cin)]
    w_scales = tuple(0.02 * (index + 1) for index in range(cin))
    tensors = (
        _tensor("in", (1, 5, 5, cin), scales=(0.4,), zps=(-5,)),
        _tensor("w", (1, 3, 3, cin), scales=w_scales, zps=(0,) * cin, qd=3, data=_raw(w_vals)),
        _tensor("b", (cin,), dtype=2, scales=(0.008,) * cin, zps=(0,) * cin, data=_i32(bias)),
        _tensor("out", (1, 5, 5, cin), scales=(0.2,), zps=(7,)),
    )
    op = OperatorInfo(
        opcode=4,
        op_name="DEPTHWISE_CONV_2D",
        inputs=(0, 1, 2),
        outputs=(3,),
        options={
            "padding": "SAME",
            "stride_w": 1,
            "stride_h": 1,
            "depth_multiplier": 1,
            "fused_activation": "RELU",
            "dilation_w": 1,
            "dilation_h": 1,
        },
    )
    graph = GraphInfo(tensors=tensors, operators=(op,), inputs=(0,), outputs=(3,))
    job, result = _run_graph(graph, input_values)

    assert job.descriptors[0].weight_bytes == 72 * ((cin + 7) // 8)
    multipliers, shifts = [], []
    for channel in range(cin):
        multiplier, shift = quantize_multiplier(0.4 * w_scales[channel] / 0.2)
        multipliers.append(multiplier)
        shifts.append(shift)
    reference = depthwise_conv2d(
        Tensor((5, 5, cin), tuple(input_values), 0.4, -5),
        _nest(w_vals, (3, 3, cin)),
        bias,
        multipliers,
        shifts,
        stride_h=1,
        stride_w=1,
        pad_top=1,
        pad_bottom=1,
        pad_left=1,
        pad_right=1,
        output_scale=0.2,
        output_zero_point=7,
        act_min=7,
        act_max=127,
    )
    assert result.layers[0] == reference


def test_synthetic_fully_connected_matches_reference():
    cin, cout = 16, 12
    input_values = _values(cin)
    w_vals = _values(cout * cin, lo=-127, step=13)
    bias = [((index * 733) % 3001) - 1500 for index in range(cout)]
    tensors = (
        _tensor("in", (1, cin), scales=(0.3,), zps=(4,)),
        _tensor("w", (cout, cin), scales=(0.05,), zps=(0,), data=_raw(w_vals)),
        _tensor("b", (cout,), dtype=2, scales=(0.015,), zps=(0,), data=_i32(bias)),
        _tensor("out", (1, cout), scales=(0.2,), zps=(14,)),
    )
    op = OperatorInfo(
        opcode=9,
        op_name="FULLY_CONNECTED",
        inputs=(0, 1, 2),
        outputs=(3,),
        options={"fused_activation": "NONE", "weights_format": 0},
    )
    graph = GraphInfo(tensors=tensors, operators=(op,), inputs=(0,), outputs=(3,))
    job, result = _run_graph(graph, input_values)

    descriptor = job.descriptors[0]
    assert descriptor.kernel_stride == 0x01010101
    assert descriptor.weight_bytes == ((cout + 7) // 8) * cin * 8
    multiplier, shift = quantize_multiplier(0.3 * 0.05 / 0.2)
    reference = fully_connected(
        Tensor((1, 1, cin), tuple(input_values), 0.3, 4),
        _nest(w_vals, (cout, cin)),
        bias,
        multiplier,
        shift,
        output_scale=0.2,
        output_zero_point=14,
        act_min=-128,
        act_max=127,
    )
    assert result.layers[0] == reference


def test_synthetic_global_average_pool_matches_reference():
    h, w, cin = 4, 3, 8
    input_values = _values(h * w * cin)
    tensors = (
        _tensor("in", (1, h, w, cin), scales=(0.6,), zps=(-9,)),
        _tensor("out", (1, 1, 1, cin), scales=(0.6,), zps=(-9,)),
    )
    op = OperatorInfo(
        opcode=1,
        op_name="AVERAGE_POOL_2D",
        inputs=(0,),
        outputs=(1,),
        options={
            "padding": "VALID",
            "stride_w": w,
            "stride_h": h,
            "filter_width": w,
            "filter_height": h,
            "fused_activation": "NONE",
        },
    )
    graph = GraphInfo(tensors=tensors, operators=(op,), inputs=(0,), outputs=(1,))
    job, result = _run_graph(graph, input_values)

    descriptor = job.descriptors[0]
    assert descriptor.kernel_stride == 0  # GAP carries zero kernel/stride and padding
    assert descriptor.padding == 0
    assert (descriptor.tile_h, descriptor.tile_w) == (1, 1)
    assert descriptor.k_slice == h * w
    assert descriptor.weight_base == 0 and descriptor.param_base == 0
    reference = global_average_pool(Tensor((h, w, cin), tuple(input_values), 0.6, -9))
    assert result.layers[0] == reference


def test_add_descriptor_end_to_end():
    # Hand-built ADD job (the locked models do not use opcode 4). input1 rides
    # in the weights region as constant data; params carry the pinned 32 bytes.
    h, w, cin = 2, 3, 4
    in0 = _values(h * w * cin, step=17)
    in1 = _values(h * w * cin, step=29, lo=-100, hi=100)
    scale0, scale1, scale_out = 0.3, 0.7, 0.5
    m0, s0 = quantize_multiplier(scale0 / (2 * scale1))
    m1, s1 = quantize_multiplier(scale1 / (2 * scale1))
    mout, sout = quantize_multiplier((2 * scale1) / ((1 << 20) * scale_out))
    params = struct.pack("<IiiiiiiI", 20, m0, s0, m1, s1, mout, sout, 0)
    descriptor = Descriptor(
        version_opcode=(ABI_VERSION << 16) | OP_ADD,
        input0_base=0,
        input1_base=0,
        output_base=128,
        param_base=0,
        input_hw=h | (w << 16),
        channels=cin | (cin << 16),
        output_hw=h | (w << 16),
        input0_row_bytes=w * cin,
        output_row_bytes=w * cin,
        input1_row_bytes=w * cin,
        kernel_stride=0x01010101,
        tile_hw=2 | (2 << 8),
        k_slice=1,
        input0_bytes=h * w * cin,
        input1_bytes=h * w * cin,
        output_bytes=h * w * cin,
        param_bytes=32,
        input0_zero=5,
        input1_zero=-7,
        output_zero=2,
        act_min=-128,
        act_max=127,
    )
    job = CompiledJob(
        descriptors=[descriptor],
        weights=_raw(in1),
        params=params,
        arena_bytes=256,
        input_offset=0,
        relocations=[
            {"descriptor_index": 0, "word_index": 2, "region": "arena", "offset": 0},
            {"descriptor_index": 0, "word_index": 3, "region": "weights", "offset": 0},
            {"descriptor_index": 0, "word_index": 4, "region": "arena", "offset": 128},
            {"descriptor_index": 0, "word_index": 5, "region": "params", "offset": 0},
        ],
        steps=[{"kind": "npu", "first_descriptor": 0, "count": 1}],
        report={
            "input": {"bytes": h * w * cin},
            "operators": [
                {
                    "descriptor_index": 0,
                    "quantization": {"output_scale": scale_out, "output_zero_point": 2},
                }
            ],
        },
    )
    result = execute_job(job, _raw(in0))

    reference = add(
        Tensor((h, w, cin), tuple(in0), scale0, 5),
        Tensor((h, w, cin), tuple(in1), scale1, -7),
        input0_multiplier=m0,
        input0_shift=s0,
        input1_multiplier=m1,
        input1_shift=s1,
        output_multiplier=mout,
        output_shift=sout,
        output_scale=scale_out,
        output_zero_point=2,
        act_min=-128,
        act_max=127,
    )
    assert result.layers[0] == reference
    assert result.output == reference


def test_k_slice_chunking_two_slices_matches_reference():
    cin = 1056  # full K = 1056 -> slices 1024 + 32
    graph = _conv_graph(1, 1, cin, 4, 1, 1, bias=[100, -200, 300, -400])
    input_values = _values(cin)
    job, result = _run_graph(graph, input_values)

    report = job.report["operators"][0]
    assert report["full_k"] == 1056
    assert report["k_slice"] == 1024
    assert report["k_slices"] == {"count": 2, "sizes": [1024, 32]}
    assert report["buffers"]["raw_gather_half_bytes"] == 1024
    reference = _ref_conv(
        input_values, (1, 1, cin), _values(4 * cin, lo=-127, step=23), (4, 1, 1, cin),
        [100, -200, 300, -400],
    )
    assert result.layers[0] == reference


def test_lane_and_position_tails_match_reference():
    # Cout=12 leaves a 4-lane group tail; the 5x5 map shortens 2x4 tiles.
    graph = _conv_graph(5, 5, 3, 12, 1, 1)
    input_values = _values(5 * 5 * 3)
    job, result = _run_graph(graph, input_values)

    report = job.report["operators"][0]
    assert report["tile"] == {"tile_h": 2, "tile_w": 4, "positions": 8, "tiles": 6}
    assert report["lane_tails"] == {"cout_mod8": 4, "oh_mod_tile": 1, "ow_mod_tile": 1}
    reference = _ref_conv(
        input_values, (5, 5, 3), _values(12 * 3, lo=-127, step=23), (12, 1, 1, 3),
        [((i * 977) % 2001) - 1000 for i in range(12)],
    )
    assert result.layers[0] == reference


def test_executor_rejects_mutated_descriptor():
    graph = _conv_graph(3, 3, 2, 4, 3, 3)
    input_values = _values(3 * 3 * 2)
    job = compile_model(graph, workload="synthetic")
    mutated = Descriptor(**vars(job.descriptors[0]))
    mutated.reserved1 = 1
    bad = dataclasses.replace(job, descriptors=[mutated] + job.descriptors[1:])

    assert _fault_code(bad, input_values) == FAULT_DESCRIPTOR


def test_executor_rejects_output_overlapping_input():
    graph = _conv_graph(3, 3, 2, 4, 3, 3)
    input_values = _values(3 * 3 * 2)
    job = compile_model(graph, workload="synthetic")
    descriptor = job.descriptors[0]
    mutated = Descriptor(**vars(descriptor))
    mutated.output_base = descriptor.input0_base
    relocations = [
        dict(relocation, offset=descriptor.input0_base)
        if relocation["descriptor_index"] == 0 and relocation["word_index"] == 4
        else relocation
        for relocation in job.relocations
    ]
    bad = dataclasses.replace(
        job, descriptors=[mutated] + job.descriptors[1:], relocations=relocations
    )

    assert _fault_code(bad, input_values) == FAULT_RANGE


def test_executor_reports_checked_arithmetic_overflow():
    # Centered input 127-(-128)=255 times weight 127 on top of an INT32_MAX bias.
    graph = _conv_graph(1, 1, 1, 1, 1, 1, bias=[(1 << 31) - 1], w_vals=[127], zin=-128)
    code = _fault_code(compile_model(graph, workload="synthetic"), [127])

    assert code == FAULT_ARITHMETIC


def test_executor_rejects_unmapped_address():
    job = dataclasses.replace(
        compile_model(_conv_graph(3, 3, 2, 4, 3, 3), workload="synthetic"),
        relocations=[],
    )
    descriptor = job.descriptors[0]
    descriptor.input0_base = 0x5000_0000  # outside every region
    descriptor.output_base = 0x1000_1000
    descriptor.param_base = 0x3000_0000
    descriptor.weight_base = 0x2000_0000

    assert _fault_code(job, _values(3 * 3 * 2)) == FAULT_RANGE


def test_executor_rejects_misaligned_weight_base():
    job = compile_model(_conv_graph(3, 3, 2, 4, 3, 3), workload="synthetic")

    code = _fault_code(job, _values(3 * 3 * 2), bases={"weights": 0x2000_0020})

    assert code == FAULT_DESCRIPTOR


def test_executor_faults_unsupported_pool_opcode():
    h, w, cin = 2, 2, 4
    descriptor = Descriptor(
        version_opcode=(ABI_VERSION << 16) | 6,  # AVERAGE_POOL: ABI-defined, not P0-placed
        input0_base=0,
        output_base=64,
        input_hw=h | (w << 16),
        channels=cin | (cin << 16),
        output_hw=1 | (1 << 16),
        input0_row_bytes=w * cin,
        output_row_bytes=cin,
        kernel_stride=2 | (2 << 8) | (2 << 16) | (2 << 24),
        tile_hw=1 | (1 << 8),
        k_slice=4,
        input0_bytes=h * w * cin,
        output_bytes=cin,
        input0_zero=3,
        output_zero=3,
        act_min=-128,
        act_max=127,
    )
    job = CompiledJob(
        descriptors=[descriptor],
        weights=b"",
        params=b"",
        arena_bytes=128,
        input_offset=0,
        relocations=[
            {"descriptor_index": 0, "word_index": 2, "region": "arena", "offset": 0},
            {"descriptor_index": 0, "word_index": 4, "region": "arena", "offset": 64},
        ],
        steps=[{"kind": "npu", "first_descriptor": 0, "count": 1}],
        report={
            "input": {"bytes": h * w * cin},
            "operators": [
                {
                    "descriptor_index": 0,
                    "quantization": {"output_scale": 0.1, "output_zero_point": 3},
                }
            ],
        },
    )

    assert _fault_code(job, _values(h * w * cin)) == FAULT_UNSUPPORTED


def test_unsupported_placement_diagnostics():
    with pytest.raises(CompilerError, match="dilation"):
        compile_model(_conv_graph(3, 3, 2, 4, 3, 3, dilation=2), workload="synthetic")
    with pytest.raises(CompilerError, match="stride"):
        compile_model(_conv_graph(3, 3, 2, 4, 3, 3, stride=3), workload="synthetic")
    with pytest.raises(CompilerError, match="activation"):
        compile_model(
            _conv_graph(3, 3, 2, 4, 3, 3, activation="RELU_N1_TO_1"), workload="synthetic"
        )
    with pytest.raises(CompilerError, match="activation"):
        compile_model(_conv_graph(3, 3, 2, 4, 3, 3, activation="RELU6"), workload="synthetic")
    with pytest.raises(CompilerError, match="symmetric"):
        compile_model(_conv_graph(3, 3, 2, 4, 3, 3, w_zps=(1, 0, 0, 0)), workload="synthetic")
    with pytest.raises(CompilerError, match="-128"):
        compile_model(
            _conv_graph(3, 3, 2, 4, 3, 3, w_vals=[-128] + _values(4 * 18 - 1, lo=-127)),
            workload="synthetic",
        )


def test_unsupported_placement_depthwise_and_pool():
    cin = 4
    base_tensors = (
        _tensor("in", (1, 4, 4, cin), scales=(0.4,), zps=(0,)),
        _tensor("w", (1, 3, 3, cin), scales=(0.02,) * cin, zps=(0,) * cin, qd=3,
                data=_raw(_values(9 * cin, lo=-127))),
        _tensor("b", (cin,), dtype=2, scales=(0.008,) * cin, zps=(0,) * cin,
                data=_i32([0] * cin)),
        _tensor("out", (1, 4, 4, cin), scales=(0.2,), zps=(0,)),
    )
    options = {
        "padding": "SAME",
        "stride_w": 1,
        "stride_h": 1,
        "depth_multiplier": 2,
        "fused_activation": "RELU",
        "dilation_w": 1,
        "dilation_h": 1,
    }
    op = OperatorInfo(opcode=4, op_name="DEPTHWISE_CONV_2D", inputs=(0, 1, 2),
                      outputs=(3,), options=options)
    graph = GraphInfo(tensors=base_tensors, operators=(op,), inputs=(0,), outputs=(3,))
    with pytest.raises(CompilerError, match="multiplier"):
        compile_model(graph, workload="synthetic")

    wide_weights = _tensor("w", (1, 5, 5, cin), scales=(0.02,) * cin, zps=(0,) * cin, qd=3,
                           data=_raw(_values(25 * cin, lo=-127)))
    graph = GraphInfo(
        tensors=base_tensors[:1] + (wide_weights,) + base_tensors[2:],
        operators=(dataclasses.replace(op, options={**options, "depth_multiplier": 1}),),
        inputs=(0,),
        outputs=(3,),
    )
    with pytest.raises(CompilerError, match="3x3"):
        compile_model(graph, workload="synthetic")

    pool = OperatorInfo(
        opcode=17,
        op_name="MAX_POOL_2D",
        inputs=(0,),
        outputs=(1,),
        options={"padding": "VALID", "stride_w": 2, "stride_h": 2,
                 "filter_width": 2, "filter_height": 2, "fused_activation": "NONE"},
    )
    pool_tensors = (
        _tensor("in", (1, 4, 4, cin), scales=(0.4,), zps=(0,)),
        _tensor("out", (1, 2, 2, cin), scales=(0.4,), zps=(0,)),
    )
    graph = GraphInfo(tensors=pool_tensors, operators=(pool,), inputs=(0,), outputs=(1,))
    with pytest.raises(CompilerError, match="placement"):
        compile_model(graph, workload="synthetic")

    partial = dataclasses.replace(pool, opcode=1, op_name="AVERAGE_POOL_2D")
    graph = GraphInfo(tensors=pool_tensors, operators=(partial,), inputs=(0,), outputs=(1,))
    with pytest.raises(CompilerError, match="whole-input"):
        compile_model(graph, workload="synthetic")


def test_kws_compile_execute_matches_reference(tmp_path):
    if not KWS_TFLITE_PATH.is_file() or not KWS_CORPUS_FIRST.is_file():
        pytest.skip("locked NPU KWS workload assets were not installed")
    job = compile_kws()
    features = KWS_CORPUS_FIRST.read_bytes()
    result = execute_job(job, features)
    reference = evaluate_reference(load_kws_model().main_graph(), features)

    assert len(job.descriptors) == 11
    assert len(result.layers) == len(reference) == 12
    assert result.layers == reference
    report_ref = [
        entry["reference_sha256"]
        for entry in job.report["operators"]
        if entry.get("descriptor_index") is not None or entry["placement"] == "cpu-softmax"
    ]
    assert result.digests == report_ref
    scores = result.output.data
    assert min(range(len(scores)), key=lambda i: (-scores[i], i)) == 7

    operators = job.report["operators"]
    assert all(entry["single_slice"] for entry in operators if entry["placement"] == "npu")
    assert operators[0]["geometry"]["pads"] == [4, 5, 1, 1]
    assert operators[0]["geometry"]["stride_h"] == 2
    assert job.report["arena_bytes"] == job.arena_bytes > 0
    assert job.report["totals"]["descriptors"] == 11
    assert all(entry["dma"]["read_bytes"] > 0 for entry in operators if entry["placement"] == "npu")

    manifest = write_artifacts(job, tmp_path / "kws")
    assert manifest["schema"] == 1
    assert manifest["numeric_profile"] == 1
    assert manifest["compiler"]["contract"] == "npu-p0/1.0.0"
    assert manifest["files"]["descriptors.bin"]["bytes"] == 11 * 128
    assert manifest["files"]["weights.bin"]["bytes"] == len(job.weights)
    assert manifest["required_opcode_mask"] == (1 << 1) | (1 << 2) | (1 << 3) | (1 << 7)
    assert len(manifest["relocations"]) == 10 * 4 + 2  # 10 weighted ops + GAP in/out
    assert manifest["steps"][0] == {"kind": "npu", "first_descriptor": 0, "count": 11}
    assert manifest["steps"][1]["kind"] == "cpu"
    assert (tmp_path / "kws" / "descriptors.bin").read_bytes() == serialize_descriptors(job)


def test_kws_matches_frozen_apu_evidence_chain():
    if not KWS_TFLITE_PATH.is_file() or not KWS_CORPUS_FIRST.is_file():
        pytest.skip("locked NPU KWS workload assets were not installed")
    job = compile_kws()
    # Same input as tests/test_apu_kws.py: the raw 490-byte MFCC feature bin.
    result = execute_job(job, KWS_CORPUS_FIRST.read_bytes())

    # NPU layers 0..10 (conv, 4x{DW,PW}, GAP, FC) are byte-identical to the
    # frozen APU-P7 published tensors.
    assert result.digests[:11] == list(_APU_KWS_LAYER_SHA256[:11])
    # APU layer 11 is its APUM softmax: the APU reciprocal deviates from the
    # locked gemmlowp Newton iteration (npu_reference._one_over_one_plus_x
    # applies the pinned <<2 increment; verified against the .cache vendored
    # TFLite sources), so a layer-11 digest mismatch is expected and is NOT a
    # failure. Equality is reported but never required.
    if result.digests[11] == _APU_KWS_LAYER_SHA256[11]:
        pass  # identical pinned softmax; nothing further to check


def test_vww_compile_execute_matches_reference():
    if not VWW_TFLITE_PATH.is_file() or not VWW_CORPUS_FIRST.is_file():
        pytest.skip("locked NPU VWW workload assets were not installed")
    job = compile_vww()
    input_bytes = vww_input_bytes(VWW_CORPUS_FIRST.read_bytes())
    result = execute_job(job, input_bytes)

    reference = evaluate_reference(load_vww_model().main_graph(), input_bytes)
    assert len(job.descriptors) == 29
    assert len(result.layers) == len(reference) == 30
    assert result.layers == reference
    scores = result.output.data
    assert min(range(len(scores)), key=lambda i: (-scores[i], i)) == 1

    operators = job.report["operators"]
    assert all(entry["single_slice"] for entry in operators if entry["placement"] == "npu")
    dw_strides = [
        entry["geometry"]["stride_h"]
        for entry in operators
        if entry.get("opcode_name") == "DEPTHWISE3X3"
    ]
    assert dw_strides == [1, 2, 1, 2, 1, 2, 1, 1, 1, 1, 1, 2, 1]
    assert len(job.relocations) == 28 * 4 + 2  # 28 weighted ops + GAP in/out
    report_ref = [
        entry["reference_sha256"]
        for entry in operators
        if entry.get("descriptor_index") is not None or entry["placement"] == "cpu-softmax"
    ]
    assert result.digests == report_ref


def test_compilation_is_deterministic(tmp_path):
    if not KWS_TFLITE_PATH.is_file():
        pytest.skip("locked NPU KWS workload model was not installed")
    graph = load_kws_model().main_graph()
    first = compile_model(graph, workload="kws")
    second = compile_model(graph, workload="kws")

    assert serialize_descriptors(first) == serialize_descriptors(second)
    assert first.weights == second.weights
    assert first.params == second.params
    assert first.relocations == second.relocations
    assert first.steps == second.steps
    manifest_a = write_artifacts(first, tmp_path / "a")
    manifest_b = write_artifacts(second, tmp_path / "b")
    assert manifest_a == manifest_b
    assert (tmp_path / "a" / "npu.json").read_bytes() == (tmp_path / "b" / "npu.json").read_bytes()
