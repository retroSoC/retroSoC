"""Proof-of-lowering compiler for the locked NPU-P0 workload graphs.

Lowers the pinned MLPerf Tiny KWS and VWW INT8 graphs (scripts/npu_model.py)
into Mini NPU descriptor ABI 1.0 sequences (scripts/npu_descriptors.py) with
packed weights/params, a bounded 64-byte-aligned arena, region-relative
address words plus relocations, and the P0 lowering report. The normative
rules are docs/ip/npu.md "Private storage and packing", "Operator and
numerical profile 1", "Descriptor ABI 1.0" and "Compiler artifacts and C HAL".

Lowering map (anything else raises CompilerError -- never a silent skip):
  CONV_2D              -> opcode 1 CONV2D (dilation 1, stride 1/2, SAME/VALID)
  DEPTHWISE_CONV_2D    -> opcode 2 DEPTHWISE3X3 (3x3, multiplier 1)
  FULLY_CONNECTED      -> opcode 3 (per-tensor or per-channel weight scale)
  AVERAGE_POOL_2D      -> opcode 7 GLOBAL_AVERAGE_POOL (VALID whole-input pool)
  RESHAPE              -> no runtime work (storage-preserving alias)
  SOFTMAX              -> explicit terminal CPU step (pinned integer profile)

Weight packing: dense [ceil(Cout/8)][K][8] bytes in kh,kw,cin reduction order
(FC uses Kh=Kw=1); channel c sits at group c//8 lane c%8 with zero tail
lanes; depthwise is [ceil(Cin/8)][9][8] in kh/kw order with zero channel
tails. Params are per-output-channel 16-byte records {int32 bias, int32
multiplier, int32 shift, uint32 0}; multiplier/shift come from the pinned
TFLite QuantizeMultiplier semantics, so a denormal-magnitude scale flushes
to multiplier=0/shift=0 and yields a constant-zout channel (VWW carries such
channels; they lower cleanly).

Arena: one contiguous byte arena per model. The input image is pinned for
the whole job; layer outputs come from a 64-byte-aligned first-fit free list
and are freed once their last consumer has been emitted, so an operator's
input and output allocations are always disjoint. Arena peak bytes are
reported. Descriptor address words hold region-relative offsets; the
manifest carries {descriptor_index, word_index, region, offset} relocations
for every nonzero semantic pointer, exactly one per pointer.
"""

from __future__ import annotations

import hashlib
import json
import struct
import subprocess
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Final

from npu_descriptors import (
    ABI_VERSION,
    DESCRIPTOR_BYTES,
    MAX_K_SLICE,
    OP_CONV2D,
    OP_DEPTHWISE3X3,
    OP_FULLY_CONNECTED,
    OP_GLOBAL_AVERAGE_POOL,
    OPCODE_NAMES,
    Descriptor,
    DescriptorError,
    used_span,
    validate_descriptor,
)
from npu_model import (
    KWS_TFLITE_SHA256,
    REPO_ROOT,
    VWW_TFLITE_SHA256,
    GraphInfo,
    TensorInfo,
    load_kws_model,
    load_vww_model,
)
from npu_reference import (
    SOFTMAX_INPUT_LEFT_SHIFT,
    SOFTMAX_INPUT_MULTIPLIER,
    SOFTMAX_OUTPUT_SCALE,
    SOFTMAX_OUTPUT_ZERO_POINT,
    Tensor,
    conv2d,
    depthwise_conv2d,
    fully_connected,
    global_average_pool,
    quantize_multiplier,
    softmax_int8,
)

CONTRACT_REVISION: Final = "npu-p0/1.0.0"
NUMERIC_PROFILE: Final = 1
# CAPABILITY bit 1 EXECUTION_READY | bit 4 DOUBLE_ROUNDING (docs/ip/npu.md).
REQUIRED_CAPABILITY_MASK: Final = 0x12
REQUIRED_CAPABILITY_BITS: Final = ("EXECUTION_READY", "DOUBLE_ROUNDING")
ARENA_ALIGNMENT: Final = 64
MAX_BUFFER_HALF_BYTES: Final = 8192
PARAM_RECORD_BYTES: Final = 16

KWS_CORPUS_FIRST: Final = (
    REPO_ROOT / ".cache/retrosoc/sources/apu-kws-mfcc/datasets/kws01/tst_000000_Stop_7.bin"
)
VWW_CORPUS_FIRST: Final = (
    REPO_ROOT / ".cache/retrosoc/sources/npu-vww-corpus/person/000000343218.bin"
)

# The compiler self-check finalizes templates against the same documented
# region bases that npu_executor.DEFAULT_BASES defines (values duplicated on
# purpose so the two modules stay independently importable).
_SELF_CHECK_BASES: Final = {
    "arena": 0x1000_0000,
    "weights": 0x2000_0000,
    "params": 0x3000_0000,
    "descriptors": 0x4000_0000,
}

_CYCLE_MODEL: Final = (
    "estimate: ceil(useful_macs/8) compute + ceil(gather_bytes/8) pack + "
    "ceil((weight+param bytes)/8) load + ceil(output_write_bytes/8) store; an "
    "8-MAC/cycle dense array with no DMA/compute overlap credit; labeled "
    "estimate, not measured counters"
)

_OPCODE_FOR_KIND: Final = {
    "conv2d": OP_CONV2D,
    "depthwise3x3": OP_DEPTHWISE3X3,
    "fully_connected": OP_FULLY_CONNECTED,
    "global_average_pool": OP_GLOBAL_AVERAGE_POOL,
}


class CompilerError(ValueError):
    """A graph operator or option has no supported NPU-P0 placement."""


@dataclass
class CompiledJob:
    """One lowered model: descriptor templates plus packed constant regions.

    descriptors hold region-relative offsets in their address words (the
    emitted TEMPLATE); relocations record {descriptor_index, word_index,
    region, offset} for words 2/3/4/5/24 as applicable. The executor's
    finalize step adds caller-provided physical bases with checked arithmetic.
    """

    descriptors: list[Descriptor]
    weights: bytes
    params: bytes
    arena_bytes: int
    input_offset: int
    relocations: list[dict]
    steps: list[dict]
    report: dict


def _require(condition: bool, message: str) -> None:
    if not condition:
        raise CompilerError(message)


def _signed(data: bytes) -> list[int]:
    return [value - 256 if value >= 128 else value for value in data]


def _digest(tensor: Tensor) -> str:
    return hashlib.sha256(bytes(value & 0xFF for value in tensor.data)).hexdigest()


def _hwc(tensor: TensorInfo) -> tuple[int, int, int]:
    """Normalize a batch-one activation tensor to (H, W, C)."""
    shape = tensor.shape
    if len(shape) == 4 and shape[0] == 1:
        return shape[1], shape[2], shape[3]
    if len(shape) == 2 and shape[0] == 1:
        return 1, 1, shape[1]
    raise CompilerError(f"tensor {tensor.name!r} shape {shape} is not batch-one NHWC")


def _activation(options: dict, zero_point: int) -> tuple[int, int]:
    fused = options.get("fused_activation", "NONE")
    if fused == "RELU":
        return max(-128, zero_point), 127
    if fused == "NONE":
        return -128, 127
    raise CompilerError(f"fused activation {fused} has no supported NPU-P0 placement")


def _check_kernel_options(op_name: str, index: int, options: dict) -> None:
    _require(
        options.get("dilation_h", 1) == 1 and options.get("dilation_w", 1) == 1,
        f"operator {index} ({op_name}): dilation other than 1 is unsupported",
    )
    _require(
        options["stride_h"] in (1, 2) and options["stride_w"] in (1, 2),
        f"operator {index} ({op_name}): stride must be 1 or 2",
    )


def _same_axis(extent: int, kernel: int, stride: int, out_expected: int) -> tuple[int, int]:
    out = -(-extent // stride)
    _require(
        out == out_expected,
        f"SAME padding output {out_expected} does not match ceil({extent}/{stride})",
    )
    total = max((out - 1) * stride + kernel - extent, 0)
    return total // 2, total - total // 2


def _pads(options: dict, h: int, w: int, kh: int, kw: int, oh: int, ow: int) -> tuple[int, ...]:
    sh, sw = options["stride_h"], options["stride_w"]
    kind = options["padding"]
    if kind == "VALID":
        pads = (0, 0, 0, 0)
    elif kind == "SAME":
        pad_top, pad_bottom = _same_axis(h, kh, sh, oh)
        pad_left, pad_right = _same_axis(w, kw, sw, ow)
        pads = (pad_top, pad_bottom, pad_left, pad_right)
    else:
        raise CompilerError(f"padding mode {kind} has no supported NPU-P0 placement")
    pad_top, pad_bottom, pad_left, pad_right = pads
    expect_oh = (h + pad_top + pad_bottom - kh) // sh + 1
    expect_ow = (w + pad_left + pad_right - kw) // sw + 1
    _require(
        (expect_oh, expect_ow) == (oh, ow),
        f"output extent {oh}x{ow} does not match computed {expect_oh}x{expect_ow}",
    )
    _require(
        pad_top < kh and pad_bottom < kh and pad_left < kw and pad_right < kw,
        "padding must be strictly less than the kernel dimension",
    )
    return pads


def _activation_quant(tensor: TensorInfo, role: str) -> tuple[float, int]:
    _require(tensor.dtype == 9, f"{role} tensor {tensor.name!r} must be INT8")
    _require(
        len(tensor.scales) == 1 and len(tensor.zero_points) == 1,
        f"{role} tensor {tensor.name!r} must use per-tensor quantization",
    )
    return float(tensor.scales[0]), int(tensor.zero_points[0])


def _weight_values(tensor: TensorInfo, cout: int, quantized_dimension: int) -> list[int]:
    _require(tensor.dtype == 9, f"weight tensor {tensor.name!r} must be INT8")
    _require(
        tensor.quantized_dimension == quantized_dimension,
        f"weight tensor {tensor.name!r} quantized dimension is not {quantized_dimension}",
    )
    _require(
        len(tensor.scales) == cout and len(tensor.zero_points) == cout,
        f"weight tensor {tensor.name!r} must carry per-channel scales",
    )
    _require(
        all(zero == 0 for zero in tensor.zero_points),
        f"weight tensor {tensor.name!r} must be symmetric (zero point 0)",
    )
    _require(tensor.data is not None, f"weight tensor {tensor.name!r} has no data")
    values = _signed(tensor.data)
    for value in values:
        _require(
            value != -128,
            f"weight tensor {tensor.name!r} holds -128, which packed weights forbid",
        )
    return values


def _bias_values(tensor: TensorInfo, cout: int) -> list[int]:
    _require(tensor.dtype == 2, f"bias tensor {tensor.name!r} must be INT32")
    _require(tensor.data is not None, f"bias tensor {tensor.name!r} has no data")
    _require(
        len(tensor.data) == 4 * cout,
        f"bias tensor {tensor.name!r} must hold {cout} INT32 values",
    )
    return list(struct.unpack(f"<{cout}i", tensor.data))


def _channel_quant(
    input_scale: float, weight_scales: tuple[float, ...], output_scale: float, cout: int
) -> tuple[list[int], list[int]]:
    """Per-channel Q31 multiplier/shift pairs; denormal scales flush to (0, 0)."""
    _require(
        len(weight_scales) in (1, cout),
        "weight scales must be per-tensor or per-output-channel",
    )
    multipliers: list[int] = []
    shifts: list[int] = []
    for channel in range(cout):
        weight_scale = weight_scales[0] if len(weight_scales) == 1 else weight_scales[channel]
        multiplier, shift = quantize_multiplier(input_scale * weight_scale / output_scale)
        multipliers.append(multiplier)
        shifts.append(shift)
    return multipliers, shifts


def _pack_dense_weights(values: list[int], cout: int, full_k: int) -> bytes:
    """[ceil(Cout/8)][K][8] in kh,kw,cin order; channel c -> group c//8 lane c%8."""
    _require(
        len(values) == cout * full_k,
        f"dense weights hold {len(values)} values, expected {cout * full_k}",
    )
    packed = bytearray(((cout + 7) // 8) * full_k * 8)
    for channel in range(cout):
        base = (channel // 8) * full_k * 8 + channel % 8
        source = channel * full_k
        for k in range(full_k):
            packed[base + k * 8] = values[source + k] & 0xFF
    return bytes(packed)


def _pack_depthwise_weights(values: list[int], cin: int) -> bytes:
    """[ceil(Cin/8)][9][8] in kh,kw order with zero channel tails."""
    _require(
        len(values) == 9 * cin,
        f"depthwise weights hold {len(values)} values, expected {9 * cin}",
    )
    packed = bytearray(((cin + 7) // 8) * 72)
    for channel in range(cin):
        base = (channel // 8) * 72 + channel % 8
        for k in range(9):
            packed[base + k * 8] = values[k * cin + channel] & 0xFF
    return bytes(packed)


def _pack_params(bias: list[int], multipliers: list[int], shifts: list[int]) -> bytes:
    return b"".join(
        struct.pack("<iiiI", bias[c], multipliers[c], shifts[c], 0)
        for c in range(len(bias))
    )


def _tile(oh: int, ow: int) -> tuple[int, int]:
    return min(2, oh), min(4, ow)


def _k_sizes(full_k: int, k_slice: int) -> list[int]:
    return [min(k_slice, full_k - start) for start in range(0, full_k, k_slice)]


@dataclass
class _Plan:
    op_index: int
    op_name: str
    kind: str
    input_tensor: int
    output_tensor: int
    h: int = 0
    w: int = 0
    cin: int = 0
    cout: int = 0
    oh: int = 0
    ow: int = 0
    kh: int = 0
    kw: int = 0
    sh: int = 0
    sw: int = 0
    pads: tuple[int, ...] = (0, 0, 0, 0)
    act_min: int = -128
    act_max: int = 127
    in_scale: float = 1.0
    in_zp: int = 0
    out_scale: float = 1.0
    out_zp: int = 0
    full_k: int = 1
    k_slice: int = 1
    weights: bytes | None = None
    params: bytes | None = None


def _lower_conv2d(graph: GraphInfo, index: int) -> _Plan:
    op = graph.operators[index]
    options = op.options
    _check_kernel_options(op.op_name, index, options)
    _require(len(op.inputs) == 3, f"operator {index} (CONV_2D) needs input/weights/bias")
    src, weight_t, bias_t = (graph.tensors[t] for t in op.inputs)
    out_t = graph.tensors[op.outputs[0]]
    h, w, cin = _hwc(src)
    oh, ow, cout = _hwc(out_t)
    _require(len(weight_t.shape) == 4, f"operator {index}: conv weights must be 4-D")
    wcout, kh, kw, wcin = weight_t.shape
    _require(
        (wcout, wcin) == (cout, cin),
        f"operator {index}: weight shape {weight_t.shape} mismatches {cin}->{cout}",
    )
    in_scale, in_zp = _activation_quant(src, "input")
    out_scale, out_zp = _activation_quant(out_t, "output")
    values = _weight_values(weight_t, cout, 0)
    bias = _bias_values(bias_t, cout)
    multipliers, shifts = _channel_quant(in_scale, weight_t.scales, out_scale, cout)
    full_k = kh * kw * cin
    return _Plan(
        op_index=index,
        op_name=op.op_name,
        kind="conv2d",
        input_tensor=op.inputs[0],
        output_tensor=op.outputs[0],
        h=h,
        w=w,
        cin=cin,
        cout=cout,
        oh=oh,
        ow=ow,
        kh=kh,
        kw=kw,
        sh=options["stride_h"],
        sw=options["stride_w"],
        pads=_pads(options, h, w, kh, kw, oh, ow),
        act_min=_activation(options, out_zp)[0],
        act_max=_activation(options, out_zp)[1],
        in_scale=in_scale,
        in_zp=in_zp,
        out_scale=out_scale,
        out_zp=out_zp,
        full_k=full_k,
        k_slice=min(MAX_K_SLICE, full_k),
        weights=_pack_dense_weights(values, cout, full_k),
        params=_pack_params(bias, multipliers, shifts),
    )


def _lower_depthwise(graph: GraphInfo, index: int) -> _Plan:
    op = graph.operators[index]
    options = op.options
    _check_kernel_options(op.op_name, index, options)
    _require(
        options.get("depth_multiplier", 1) == 1,
        f"operator {index} (DEPTHWISE_CONV_2D): depth multiplier must be 1",
    )
    _require(len(op.inputs) == 3, f"operator {index} (DEPTHWISE_CONV_2D) needs 3 inputs")
    src, weight_t, bias_t = (graph.tensors[t] for t in op.inputs)
    out_t = graph.tensors[op.outputs[0]]
    h, w, cin = _hwc(src)
    oh, ow, cout = _hwc(out_t)
    _require(len(weight_t.shape) == 4, f"operator {index}: depthwise weights must be 4-D")
    _, kh, kw, wchannels = weight_t.shape
    _require(
        (kh, kw) == (3, 3),
        f"operator {index}: DEPTHWISE3X3 requires a 3x3 kernel, got {kh}x{kw}",
    )
    _require(
        wchannels == cin and cout == cin,
        f"operator {index}: depthwise multiplier 1 requires Cout == Cin",
    )
    in_scale, in_zp = _activation_quant(src, "input")
    out_scale, out_zp = _activation_quant(out_t, "output")
    values = _weight_values(weight_t, cin, 3)
    bias = _bias_values(bias_t, cout)
    multipliers, shifts = _channel_quant(in_scale, weight_t.scales, out_scale, cout)
    return _Plan(
        op_index=index,
        op_name=op.op_name,
        kind="depthwise3x3",
        input_tensor=op.inputs[0],
        output_tensor=op.outputs[0],
        h=h,
        w=w,
        cin=cin,
        cout=cout,
        oh=oh,
        ow=ow,
        kh=3,
        kw=3,
        sh=options["stride_h"],
        sw=options["stride_w"],
        pads=_pads(options, h, w, 3, 3, oh, ow),
        act_min=_activation(options, out_zp)[0],
        act_max=_activation(options, out_zp)[1],
        in_scale=in_scale,
        in_zp=in_zp,
        out_scale=out_scale,
        out_zp=out_zp,
        full_k=9,
        k_slice=9,
        weights=_pack_depthwise_weights(values, cin),
        params=_pack_params(bias, multipliers, shifts),
    )


def _lower_fully_connected(graph: GraphInfo, index: int) -> _Plan:
    op = graph.operators[index]
    options = op.options
    _require(len(op.inputs) == 3, f"operator {index} (FULLY_CONNECTED) needs 3 inputs")
    src, weight_t, bias_t = (graph.tensors[t] for t in op.inputs)
    out_t = graph.tensors[op.outputs[0]]
    h, w, cin = _hwc(src)
    oh, ow, cout = _hwc(out_t)
    _require(
        (h, w, oh, ow) == (1, 1, 1, 1),
        f"operator {index} (FULLY_CONNECTED) requires H=W=OH=OW=1",
    )
    _require(len(weight_t.shape) == 2, f"operator {index}: FC weights must be 2-D")
    wcout, wcin = weight_t.shape
    _require(
        (wcout, wcin) == (cout, cin),
        f"operator {index}: FC weight shape {weight_t.shape} mismatches {cin}->{cout}",
    )
    in_scale, in_zp = _activation_quant(src, "input")
    out_scale, out_zp = _activation_quant(out_t, "output")
    _require(weight_t.dtype == 9, f"operator {index}: FC weights must be INT8")
    _require(
        all(zero == 0 for zero in weight_t.zero_points),
        f"operator {index}: FC weights must be symmetric (zero point 0)",
    )
    _require(weight_t.data is not None, f"operator {index}: FC weights have no data")
    values = _signed(weight_t.data)
    for value in values:
        _require(value != -128, f"operator {index}: FC weights hold -128")
    bias = _bias_values(bias_t, cout)
    multipliers, shifts = _channel_quant(in_scale, weight_t.scales, out_scale, cout)
    return _Plan(
        op_index=index,
        op_name=op.op_name,
        kind="fully_connected",
        input_tensor=op.inputs[0],
        output_tensor=op.outputs[0],
        h=1,
        w=1,
        cin=cin,
        cout=cout,
        oh=1,
        ow=1,
        kh=1,
        kw=1,
        sh=1,
        sw=1,
        pads=(0, 0, 0, 0),
        act_min=_activation(options, out_zp)[0],
        act_max=_activation(options, out_zp)[1],
        in_scale=in_scale,
        in_zp=in_zp,
        out_scale=out_scale,
        out_zp=out_zp,
        full_k=cin,
        k_slice=min(MAX_K_SLICE, cin),
        weights=_pack_dense_weights(values, cout, cin),
        params=_pack_params(bias, multipliers, shifts),
    )


def _lower_global_average_pool(graph: GraphInfo, index: int) -> _Plan:
    op = graph.operators[index]
    options = op.options
    _require(
        options.get("padding") == "VALID",
        f"operator {index} (AVERAGE_POOL_2D): P0 lowers VALID whole-input pools only",
    )
    _require(len(op.inputs) == 1, f"operator {index} (AVERAGE_POOL_2D) needs 1 input")
    src = graph.tensors[op.inputs[0]]
    out_t = graph.tensors[op.outputs[0]]
    h, w, cin = _hwc(src)
    oh, ow, cout = _hwc(out_t)
    _require(
        (oh, ow, cout) == (1, 1, cin),
        f"operator {index}: whole-input pool must produce 1x1x{cin}",
    )
    _require(
        options["filter_height"] == h
        and options["filter_width"] == w
        and options["stride_h"] == h
        and options["stride_w"] == w,
        f"operator {index}: pool filter/stride must equal the whole {h}x{w} input",
    )
    in_scale, in_zp = _activation_quant(src, "input")
    out_scale, out_zp = _activation_quant(out_t, "output")
    _require(
        in_scale == out_scale and in_zp == out_zp,
        f"operator {index}: GLOBAL_AVERAGE_POOL requires equal input/output quantization",
    )
    full_k = h * w
    return _Plan(
        op_index=index,
        op_name=op.op_name,
        kind="global_average_pool",
        input_tensor=op.inputs[0],
        output_tensor=op.outputs[0],
        h=h,
        w=w,
        cin=cin,
        cout=cout,
        oh=1,
        ow=1,
        kh=0,
        kw=0,
        sh=0,
        sw=0,
        pads=(0, 0, 0, 0),
        act_min=_activation(options, out_zp)[0],
        act_max=_activation(options, out_zp)[1],
        in_scale=in_scale,
        in_zp=in_zp,
        out_scale=out_scale,
        out_zp=out_zp,
        full_k=full_k,
        k_slice=min(MAX_K_SLICE, full_k),
    )


def _lower_operator(graph: GraphInfo, index: int) -> _Plan:
    op = graph.operators[index]
    if op.op_name == "CONV_2D":
        return _lower_conv2d(graph, index)
    if op.op_name == "DEPTHWISE_CONV_2D":
        return _lower_depthwise(graph, index)
    if op.op_name == "FULLY_CONNECTED":
        return _lower_fully_connected(graph, index)
    if op.op_name == "AVERAGE_POOL_2D":
        return _lower_global_average_pool(graph, index)
    if op.op_name == "RESHAPE":
        src = graph.tensors[op.inputs[0]]
        out_t = graph.tensors[op.outputs[0]]
        in_count = 1
        for dim in src.shape[1:]:
            in_count *= dim
        out_count = 1
        for dim in out_t.shape[1:]:
            out_count *= dim
        _require(
            in_count == out_count,
            f"operator {index} (RESHAPE) must preserve the element count",
        )
        _require(
            _activation_quant(src, "reshape input") == _activation_quant(out_t, "reshape output"),
            f"operator {index} (RESHAPE) must preserve quantization",
        )
        return _Plan(
            op_index=index,
            op_name=op.op_name,
            kind="reshape",
            input_tensor=op.inputs[0],
            output_tensor=op.outputs[0],
        )
    if op.op_name == "SOFTMAX":
        src = graph.tensors[op.inputs[0]]
        out_t = graph.tensors[op.outputs[0]]
        in_scale, in_zp = _activation_quant(src, "softmax input")
        out_scale, out_zp = _activation_quant(out_t, "softmax output")
        return _Plan(
            op_index=index,
            op_name=op.op_name,
            kind="softmax",
            input_tensor=op.inputs[0],
            output_tensor=op.outputs[0],
            in_scale=in_scale,
            in_zp=in_zp,
            out_scale=out_scale,
            out_zp=out_zp,
        )
    raise CompilerError(
        f"operator {index} ({op.op_name}) has no supported NPU-P0 placement"
    )


class _Arena:
    """Bump allocator with a first-fit free list; every allocation 64-byte aligned."""

    def __init__(self) -> None:
        self._free: list[list[int]] = []
        self._high = 0
        self.peak = 0

    @staticmethod
    def _aligned(size: int) -> int:
        return (size + ARENA_ALIGNMENT - 1) & ~(ARENA_ALIGNMENT - 1)

    def alloc(self, size: int) -> int:
        size = self._aligned(size)
        for block in self._free:
            if block[1] >= size:
                offset = block[0]
                if block[1] == size:
                    self._free.remove(block)
                else:
                    block[0] += size
                    block[1] -= size
                return offset
        offset = self._high
        self._high += size
        self.peak = max(self.peak, self._high)
        return offset

    def free(self, offset: int, size: int) -> None:
        self._free.append([offset, self._aligned(size)])
        self._free.sort(key=lambda block: block[0])
        merged: list[list[int]] = []
        for block in self._free:
            if merged and merged[-1][0] + merged[-1][1] == block[0]:
                merged[-1][1] += block[1]
            else:
                merged.append(block)
        self._free = merged


def _append_aligned(region: bytearray, payload: bytes) -> int:
    pad = (-len(region)) % ARENA_ALIGNMENT
    region.extend(b"\x00" * pad)
    offset = len(region)
    region.extend(payload)
    return offset


def _git_identity() -> dict[str, Any]:
    try:
        revision = subprocess.check_output(
            ["git", "-C", str(REPO_ROOT), "rev-parse", "HEAD"],
            text=True,
            stderr=subprocess.DEVNULL,
        ).strip()
        dirty = bool(
            subprocess.check_output(
                ["git", "-C", str(REPO_ROOT), "status", "--porcelain"],
                text=True,
                stderr=subprocess.DEVNULL,
            ).strip()
        )
    except (OSError, subprocess.CalledProcessError):
        revision, dirty = "unknown", True
    return {
        "contract": CONTRACT_REVISION,
        "git_revision": revision,
        "git_dirty": dirty,
    }


def _buffer_report(plan: _Plan, positions: int) -> dict[str, int]:
    """Raw-gather/packed half-buffer footprints with the 8192-byte bound checked."""
    if plan.kind == "depthwise3x3":
        gather_slice = 9 * 8  # 9 kernel positions x 8 channel lanes per spatial lane
        packed_a = positions * 72
        packed_w = 72
    elif plan.kind == "global_average_pool":
        gather_slice = plan.k_slice * 8  # positions x 8 channel lanes
        packed_a = plan.k_slice * 8
        packed_w = 0
    else:
        gather_slice = plan.k_slice
        packed_a = plan.k_slice * 8
        packed_w = plan.k_slice * 8
    raw_gather = positions * gather_slice
    _require(
        raw_gather <= MAX_BUFFER_HALF_BYTES,
        f"operator {plan.op_index}: raw gather half {raw_gather} exceeds 8192",
    )
    _require(
        packed_a <= MAX_BUFFER_HALF_BYTES and packed_w <= MAX_BUFFER_HALF_BYTES,
        f"operator {plan.op_index}: packed A/W half exceeds 8192",
    )
    return {
        "raw_gather_half_bytes": raw_gather,
        "packed_a_bytes": packed_a,
        "packed_w_bytes": packed_w,
        "limit_bytes": MAX_BUFFER_HALF_BYTES,
    }


def _dma_report(plan: _Plan) -> dict[str, int]:
    weight_bytes = len(plan.weights) if plan.weights is not None else 0
    param_bytes = len(plan.params) if plan.params is not None else 0
    if plan.kind == "depthwise3x3":
        gather = plan.oh * plan.ow * ((plan.cin + 7) // 8) * 72
        macs = plan.oh * plan.ow * plan.cin * 9
    elif plan.kind == "global_average_pool":
        gather = plan.h * plan.w * plan.cin
        macs = plan.h * plan.w * plan.cin
    else:
        # Every output position gathers its full receptive field; redundant
        # reads of overlapping windows are included on purpose.
        gather = plan.oh * plan.ow * plan.full_k
        macs = plan.oh * plan.ow * plan.cout * plan.full_k
    write = plan.oh * plan.ow * plan.cout
    pack_cycles = -(-gather // 8)
    estimated = -(-macs // 8) + pack_cycles + -(-(weight_bytes + param_bytes) // 8) + -(-write // 8)
    return {
        "gather_read_bytes": gather,
        "weight_read_bytes": weight_bytes,
        "param_read_bytes": param_bytes,
        "read_bytes": gather + weight_bytes + param_bytes,
        "write_bytes": write,
        "useful_macs": macs,
        "pack_cycles": pack_cycles,
        "estimated_cycles": estimated,
    }


def _operator_report(plan: _Plan, descriptor_index: int | None) -> dict[str, Any]:
    entry: dict[str, Any] = {
        "index": plan.op_index,
        "operator": plan.op_name,
        "descriptor_index": descriptor_index,
    }
    if plan.kind == "reshape":
        entry["placement"] = "none"
        entry["note"] = "storage-preserving reshape; emits no runtime work"
        return entry
    if plan.kind == "softmax":
        entry["placement"] = "cpu-softmax"
        entry["pinned"] = {
            "input_multiplier": SOFTMAX_INPUT_MULTIPLIER,
            "input_left_shift": SOFTMAX_INPUT_LEFT_SHIFT,
            "diff_min": -124,
            "output_scale": SOFTMAX_OUTPUT_SCALE,
            "output_zero_point": SOFTMAX_OUTPUT_ZERO_POINT,
        }
        entry["quantization"] = {
            "input_scale": plan.in_scale,
            "input_zero_point": plan.in_zp,
            "output_scale": plan.out_scale,
            "output_zero_point": plan.out_zp,
        }
        return entry
    opcode = _OPCODE_FOR_KIND[plan.kind]
    tile_h, tile_w = _tile(plan.oh, plan.ow)
    sizes = _k_sizes(plan.full_k, plan.k_slice)
    dma = _dma_report(plan)
    entry.update(
        {
            "placement": "npu",
            "opcode": opcode,
            "opcode_name": OPCODE_NAMES[opcode],
            "geometry": {
                "h": plan.h,
                "w": plan.w,
                "cin": plan.cin,
                "cout": plan.cout,
                "oh": plan.oh,
                "ow": plan.ow,
                "kh": plan.kh,
                "kw": plan.kw,
                "stride_h": plan.sh,
                "stride_w": plan.sw,
                "pads": list(plan.pads),
            },
            "quantization": {
                "input_scale": plan.in_scale,
                "input_zero_point": plan.in_zp,
                "output_scale": plan.out_scale,
                "output_zero_point": plan.out_zp,
                "act_min": plan.act_min,
                "act_max": plan.act_max,
            },
            "full_k": plan.full_k,
            "k_slice": plan.k_slice,
            "k_slices": {"count": len(sizes), "sizes": sizes},
            "single_slice": len(sizes) == 1,
            "tile": {
                "tile_h": tile_h,
                "tile_w": tile_w,
                "positions": tile_h * tile_w,
                "tiles": -(-plan.oh // tile_h) * -(-plan.ow // tile_w),
            },
            "lane_tails": {
                "cout_mod8": plan.cout % 8,
                "oh_mod_tile": plan.oh % tile_h,
                "ow_mod_tile": plan.ow % tile_w,
            },
            "buffers": _buffer_report(plan, tile_h * tile_w),
            "weights": (
                {"bytes": len(plan.weights)} if plan.weights is not None else None
            ),
            "params": ({"bytes": len(plan.params)} if plan.params is not None else None),
            "dma": dma,
            "useful_macs": dma["useful_macs"],
            "pack_cycles": dma["pack_cycles"],
            "estimated_cycles": dma["estimated_cycles"],
        }
    )
    return entry


def _emit_descriptor(
    plan: _Plan,
    input_offset: int,
    output_offset: int,
    weight_offset: int,
    param_offset: int,
) -> Descriptor:
    opcode = _OPCODE_FOR_KIND[plan.kind]
    tile_h, tile_w = _tile(plan.oh, plan.ow)
    weighted = plan.weights is not None
    pad_top, pad_bottom, pad_left, pad_right = plan.pads
    return Descriptor(
        version_opcode=(ABI_VERSION << 16) | opcode,
        input0_base=input_offset,
        output_base=output_offset,
        param_base=param_offset if weighted else 0,
        input_hw=plan.h | (plan.w << 16),
        channels=plan.cin | (plan.cout << 16),
        output_hw=plan.oh | (plan.ow << 16),
        input0_row_bytes=plan.w * plan.cin,
        output_row_bytes=plan.ow * plan.cout,
        kernel_stride=plan.kh | (plan.kw << 8) | (plan.sh << 16) | (plan.sw << 24),
        padding=pad_top | (pad_bottom << 8) | (pad_left << 16) | (pad_right << 24),
        tile_hw=tile_h | (tile_w << 8),
        k_slice=plan.k_slice,
        input0_bytes=used_span(plan.h, plan.w, plan.cin, plan.w * plan.cin),
        output_bytes=used_span(plan.oh, plan.ow, plan.cout, plan.ow * plan.cout),
        param_bytes=len(plan.params) if weighted else 0,
        input0_zero=plan.in_zp,
        output_zero=plan.out_zp,
        act_min=plan.act_min,
        act_max=plan.act_max,
        weight_base=weight_offset if weighted else 0,
        weight_bytes=len(plan.weights) if weighted else 0,
    )


def _self_check(job: CompiledJob) -> None:
    """Finalize templates against documented bases and run the ABI validator."""
    region = (_SELF_CHECK_BASES["descriptors"], len(job.descriptors) * DESCRIPTOR_BYTES)
    finalized = [Descriptor(**vars(desc)) for desc in job.descriptors]
    word_fields = {2: "input0_base", 3: "input1_base", 4: "output_base", 5: "param_base", 24: "weight_base"}
    for relocation in job.relocations:
        desc = finalized[relocation["descriptor_index"]]
        field = word_fields[relocation["word_index"]]
        if getattr(desc, field) != relocation["offset"]:
            raise CompilerError("internal: relocation offset mismatches the template word")
        setattr(desc, field, _SELF_CHECK_BASES[relocation["region"]] + relocation["offset"])
    for index, desc in enumerate(finalized):
        try:
            validate_descriptor(desc, descriptor_region=region)
        except DescriptorError as error:
            raise CompilerError(
                f"internal: emitted descriptor {index} fails ABI validation: {error}"
            ) from error


def compile_model(
    graph: GraphInfo,
    *,
    workload: str,
    reference_input: bytes | None = None,
    source_model_sha256: str | None = None,
) -> CompiledJob:
    """Lower one batch-one INT8 graph into a descriptor ABI 1.0 CompiledJob.

    reference_input, when given, is the raw model input byte image; the P0
    report then carries per-layer SHA-256 digests of a direct npu_reference
    evaluation of the whole graph (including the CPU softmax).
    """
    _require(len(graph.operators) > 0, "graph holds no operators")
    _require(len(graph.inputs) == 1, "graph must have exactly one input")
    plans = [_lower_operator(graph, index) for index in range(len(graph.operators))]
    for index, plan in enumerate(plans):
        _require(
            plan.kind != "softmax" or index == len(plans) - 1,
            f"operator {index} (SOFTMAX): only a terminal CPU softmax is supported",
        )
    last_use: dict[int, int] = {}
    for index, op in enumerate(graph.operators):
        for tensor_index in op.inputs:
            last_use[tensor_index] = index

    arena = _Arena()
    alloc: dict[int, tuple[int, int, int]] = {}
    descriptors: list[Descriptor] = []
    relocations: list[dict] = []
    weights_region = bytearray()
    params_region = bytearray()
    report_ops: list[dict[str, Any]] = []

    in_index = graph.inputs[0]
    in_h, in_w, in_c = _hwc(graph.tensors[in_index])
    in_scale, in_zp = _activation_quant(graph.tensors[in_index], "graph input")
    in_bytes = in_h * in_w * in_c
    input_offset = arena.alloc(in_bytes)
    pinned = len(graph.operators) + 1  # the input image stays live for the whole job
    alloc[in_index] = (input_offset, in_bytes, pinned)

    def free_consumed(tensor_index: int, at: int) -> None:
        entry = alloc.get(tensor_index)
        if entry is not None and entry[2] <= at:
            arena.free(entry[0], entry[1])
            del alloc[tensor_index]

    for index, plan in enumerate(plans):
        if plan.kind == "reshape":
            src_offset, src_size, src_last = alloc[plan.input_tensor]
            out_last = last_use.get(plan.output_tensor, len(plans))
            alloc[plan.output_tensor] = (src_offset, src_size, max(src_last, out_last))
            if plan.input_tensor != in_index:
                del alloc[plan.input_tensor]
            report_ops.append(_operator_report(plan, None))
            continue
        if plan.kind == "softmax":
            free_consumed(plan.input_tensor, index)
            report_ops.append(_operator_report(plan, None))
            continue
        in_off, _, _ = alloc[plan.input_tensor]
        out_bytes = plan.oh * plan.ow * plan.cout
        out_off = arena.alloc(out_bytes)
        alloc[plan.output_tensor] = (
            out_off,
            out_bytes,
            last_use.get(plan.output_tensor, len(plans)),
        )
        weight_offset = 0
        param_offset = 0
        if plan.weights is not None:
            weight_offset = _append_aligned(weights_region, plan.weights)
            param_offset = _append_aligned(params_region, plan.params or b"")
        descriptor = _emit_descriptor(plan, in_off, out_off, weight_offset, param_offset)
        descriptor_index = len(descriptors)
        descriptors.append(descriptor)
        relocations.append(
            {
                "descriptor_index": descriptor_index,
                "word_index": 2,
                "region": "arena",
                "offset": in_off,
            }
        )
        relocations.append(
            {
                "descriptor_index": descriptor_index,
                "word_index": 4,
                "region": "arena",
                "offset": out_off,
            }
        )
        if plan.weights is not None:
            relocations.append(
                {
                    "descriptor_index": descriptor_index,
                    "word_index": 5,
                    "region": "params",
                    "offset": param_offset,
                }
            )
            relocations.append(
                {
                    "descriptor_index": descriptor_index,
                    "word_index": 24,
                    "region": "weights",
                    "offset": weight_offset,
                }
            )
        entry = _operator_report(plan, descriptor_index)
        entry["arena"] = {
            "input_offset": in_off,
            "output_offset": out_off,
            "output_bytes": out_bytes,
        }
        if plan.weights is not None:
            entry["weights"]["offset"] = weight_offset
            entry["params"]["offset"] = param_offset
        report_ops.append(entry)
        free_consumed(plan.input_tensor, index)

    steps: list[dict[str, Any]] = []
    if descriptors:
        steps.append({"kind": "npu", "first_descriptor": 0, "count": len(descriptors)})
    if plans[-1].kind == "softmax":
        steps.append(
            {
                "kind": "cpu",
                "op": "softmax",
                "source_descriptor": len(descriptors) - 1,
                "note": "pinned integer softmax (numerical profile 1)",
            }
        )

    if reference_input is not None:
        reference_layers = evaluate_reference(graph, reference_input)
        produced = [entry for entry, plan in zip(report_ops, plans) if plan.kind != "reshape"]
        _require(
            len(produced) == len(reference_layers),
            "internal: reference evaluation layer count mismatch",
        )
        for entry, tensor in zip(produced, reference_layers):
            entry["reference_sha256"] = _digest(tensor)
            entry["reference_shape"] = list(tensor.shape)

    totals = {
        "descriptors": len(descriptors),
        "weights_bytes": len(weights_region),
        "params_bytes": len(params_region),
        "useful_macs": sum(entry.get("useful_macs", 0) for entry in report_ops),
        "dma_read_bytes": sum(
            entry.get("dma", {}).get("read_bytes", 0) for entry in report_ops
        ),
        "dma_write_bytes": sum(
            entry.get("dma", {}).get("write_bytes", 0) for entry in report_ops
        ),
        "estimated_cycles": sum(
            entry.get("estimated_cycles", 0) for entry in report_ops
        ),
    }
    report: dict[str, Any] = {
        "workload": workload,
        "source_model_sha256": source_model_sha256,
        "numeric_profile": NUMERIC_PROFILE,
        "compiler": _git_identity(),
        "input": {
            "tensor_index": in_index,
            "shape": [in_h, in_w, in_c],
            "scale": in_scale,
            "zero_point": in_zp,
            "bytes": in_bytes,
            "offset": input_offset,
        },
        "arena_bytes": arena.peak,
        "arena_note": (
            "single contiguous arena; input image pinned for the whole job; "
            "layer outputs use a 64-byte-aligned first-fit free list freed "
            "after their last consumer; input/output allocations are disjoint"
        ),
        "cycle_model": _CYCLE_MODEL,
        "operators": report_ops,
        "totals": totals,
    }
    job = CompiledJob(
        descriptors=descriptors,
        weights=bytes(weights_region),
        params=bytes(params_region),
        arena_bytes=arena.peak,
        input_offset=input_offset,
        relocations=relocations,
        steps=steps,
        report=report,
    )
    _self_check(job)
    return job


def _nest(values: list[int], shape: tuple[int, ...]) -> Any:
    if len(shape) == 1:
        return tuple(values[: shape[0]])
    step = 1
    for dim in shape[1:]:
        step *= dim
    return tuple(
        _nest(values[index * step : (index + 1) * step], shape[1:])
        for index in range(shape[0])
    )


def evaluate_reference(graph: GraphInfo, input_bytes: bytes) -> list[Tensor]:
    """Run npu_reference layer functions over the whole graph (incl. softmax).

    RESHAPE is storage-preserving and produces no layer entry; every other
    operator appends exactly one tensor, in graph order.
    """
    in_index = graph.inputs[0]
    src_t = graph.tensors[in_index]
    h, w, cin = _hwc(src_t)
    _require(
        len(input_bytes) == h * w * cin,
        f"reference input is {len(input_bytes)} bytes, expected {h * w * cin}",
    )
    in_scale, in_zp = _activation_quant(src_t, "graph input")
    current = Tensor((h, w, cin), tuple(_signed(bytes(input_bytes))), in_scale, in_zp)
    layers: list[Tensor] = []
    for index, op in enumerate(graph.operators):
        options = op.options
        out_t = graph.tensors[op.outputs[0]]
        if op.op_name in ("CONV_2D", "DEPTHWISE_CONV_2D", "FULLY_CONNECTED"):
            weight_t = graph.tensors[op.inputs[1]]
            bias_t = graph.tensors[op.inputs[2]]
            out_scale, out_zp = _activation_quant(out_t, "output")
            act_min, act_max = _activation(options, out_zp)
            cout = out_t.shape[-1]
            bias = _bias_values(bias_t, cout)
            multipliers, shifts = _channel_quant(
                current.scale, weight_t.scales, out_scale, cout
            )
            values = _signed(weight_t.data or b"")
        if op.op_name == "CONV_2D":
            wcout, kh, kw, wcin = weight_t.shape
            pads = _pads(
                options, current.height, current.width, kh, kw, out_t.shape[1], out_t.shape[2]
            )
            current = conv2d(
                current,
                _nest(values, (wcout, kh, kw, wcin)),
                bias,
                multipliers,
                shifts,
                stride_h=options["stride_h"],
                stride_w=options["stride_w"],
                pad_top=pads[0],
                pad_bottom=pads[1],
                pad_left=pads[2],
                pad_right=pads[3],
                output_scale=out_scale,
                output_zero_point=out_zp,
                act_min=act_min,
                act_max=act_max,
            )
        elif op.op_name == "DEPTHWISE_CONV_2D":
            _, kh, kw, _ = weight_t.shape
            pads = _pads(
                options, current.height, current.width, kh, kw, out_t.shape[1], out_t.shape[2]
            )
            current = depthwise_conv2d(
                current,
                _nest(values, (kh, kw, current.channels)),
                bias,
                multipliers,
                shifts,
                stride_h=options["stride_h"],
                stride_w=options["stride_w"],
                pad_top=pads[0],
                pad_bottom=pads[1],
                pad_left=pads[2],
                pad_right=pads[3],
                output_scale=out_scale,
                output_zero_point=out_zp,
                act_min=act_min,
                act_max=act_max,
            )
        elif op.op_name == "FULLY_CONNECTED":
            current = fully_connected(
                current,
                _nest(values, weight_t.shape),
                bias,
                multipliers,
                shifts,
                output_scale=out_scale,
                output_zero_point=out_zp,
                act_min=act_min,
                act_max=act_max,
            )
        elif op.op_name == "AVERAGE_POOL_2D":
            out_scale, out_zp = _activation_quant(out_t, "output")
            act_min, act_max = _activation(options, out_zp)
            current = global_average_pool(current, act_min=act_min, act_max=act_max)
        elif op.op_name == "RESHAPE":
            oh, ow, oc = _hwc(out_t)
            current = Tensor((oh, ow, oc), current.data, current.scale, current.zero_point)
            continue
        elif op.op_name == "SOFTMAX":
            current = softmax_int8(current)
        else:
            raise CompilerError(
                f"operator {index} ({op.op_name}) has no supported NPU-P0 placement"
            )
        layers.append(current)
    return layers


def vww_input_bytes(raw: bytes) -> bytes:
    """Map U8 VWW corpus bytes to raw INT8 two's-complement model input bytes."""
    return bytes(value ^ 0x80 for value in raw)


def compile_kws() -> CompiledJob:
    """Compile the locked KWS graph; the report hashes use the first corpus input."""
    model = load_kws_model()
    return compile_model(
        model.main_graph(),
        workload="kws",
        reference_input=KWS_CORPUS_FIRST.read_bytes(),
        source_model_sha256=KWS_TFLITE_SHA256,
    )


def compile_vww() -> CompiledJob:
    """Compile the locked VWW graph; the report hashes use the first corpus input."""
    model = load_vww_model()
    return compile_model(
        model.main_graph(),
        workload="vww",
        reference_input=vww_input_bytes(VWW_CORPUS_FIRST.read_bytes()),
        source_model_sha256=VWW_TFLITE_SHA256,
    )


def serialize_descriptors(job: CompiledJob) -> bytes:
    """Encode the descriptor templates as the N x 128-byte descriptors.bin image."""
    return b"".join(descriptor.to_bytes() for descriptor in job.descriptors)


def write_artifacts(job: CompiledJob, out_dir: str | Path) -> dict[str, Any]:
    """Write npu.json, descriptors.bin, weights.bin and params.bin; return the manifest."""
    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)
    descriptors_bin = serialize_descriptors(job)
    files = {
        "descriptors.bin": descriptors_bin,
        "weights.bin": job.weights,
        "params.bin": job.params,
    }
    opcode_mask = 0
    for descriptor in job.descriptors:
        opcode_mask |= 1 << descriptor.opcode
    layers_meta = [
        {
            "descriptor_index": entry["descriptor_index"],
            "output_scale": entry["quantization"]["output_scale"],
            "output_zero_point": entry["quantization"]["output_zero_point"],
        }
        for entry in job.report["operators"]
        if entry.get("descriptor_index") is not None
    ]
    final_entry = job.report["operators"][-1]
    manifest: dict[str, Any] = {
        "schema": 1,
        "workload": job.report["workload"],
        "source_model_sha256": job.report["source_model_sha256"],
        "compiler": job.report["compiler"],
        "numeric_profile": NUMERIC_PROFILE,
        "required_capability_mask": REQUIRED_CAPABILITY_MASK,
        "required_capability_bits": list(REQUIRED_CAPABILITY_BITS),
        "required_opcode_mask": opcode_mask,
        "files": {
            name: {"bytes": len(payload), "sha256": hashlib.sha256(payload).hexdigest()}
            for name, payload in files.items()
        },
        "arena_bytes": job.arena_bytes,
        "input_offset": job.input_offset,
        "steps": job.steps,
        "relocations": job.relocations,
        "tensors": {
            "input": job.report["input"],
            "layers": layers_meta,
            "output": final_entry.get("quantization"),
        },
        "report": job.report,
    }
    for name, payload in files.items():
        (out / name).write_bytes(payload)
    (out / "npu.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    return manifest
