"""Independent scalar numerical reference for the Mini NPU numerical profile 1."""

from __future__ import annotations

import math
from collections.abc import Sequence
from dataclasses import dataclass
from fractions import Fraction
from typing import Final

INT32_MIN: Final = -(1 << 31)
INT32_MAX: Final = (1 << 31) - 1
INT8_MIN: Final = -128
INT8_MAX: Final = 127

# Pinned TFLite reference Softmax parameters (docs/ip/apu.md, quantization profile 1).
SOFTMAX_INPUT_MULTIPLIER: Final = 1242899200
SOFTMAX_INPUT_LEFT_SHIFT: Final = 24
SOFTMAX_DIFF_MIN: Final = -124
SOFTMAX_OUTPUT_SCALE: Final = 1.0 / 256.0
SOFTMAX_OUTPUT_ZERO_POINT: Final = -128

# Pinned gemmlowp fixed-point constants, Q31 unless noted.
_EXP_CONSTANT_TERM: Final = 1895147668  # exp(-1/8)
_EXP_ONE_OVER_THREE: Final = 715827883
_EXP_BARREL_MULTIPLIERS: Final = (
    (-2, 1672461947),  # exp(-1/4)
    (-1, 1302514674),  # exp(-1/2)
    (0, 790015084),  # exp(-1)
    (1, 290630308),  # exp(-2)
    (2, 39332535),  # exp(-4)
    (3, 720401),  # exp(-8)
    (4, 242),  # exp(-16)
)
_RECIPROCAL_48_OVER_17: Final = 1515870810  # Q2.29 fixed point
_RECIPROCAL_NEG_32_OVER_17: Final = -1010580540  # Q2.29 fixed point


class ArithmeticFault(ArithmeticError):
    """Checked INT32 arithmetic overflow in a numerical profile 1 operation."""


@dataclass(frozen=True)
class Tensor:
    """Immutable batch-one NHWC INT8 activation tensor with quantization metadata."""

    shape: tuple[int, int, int]
    data: tuple[int, ...]
    scale: float
    zero_point: int

    def __post_init__(self) -> None:
        shape = tuple(self.shape)
        if len(shape) != 3 or any(not isinstance(dim, int) for dim in shape):
            raise ValueError("tensor shape must be an (H, W, C) integer triple")
        if any(dim < 1 or dim > 4096 for dim in shape):
            raise ValueError("tensor dimensions must each be within 1..4096")
        data = tuple(self.data)
        if len(data) != shape[0] * shape[1] * shape[2]:
            raise ValueError("tensor data length does not match the (H, W, C) shape")
        if any(not isinstance(value, int) for value in data):
            raise ValueError("tensor data must contain integers")
        if any(value < INT8_MIN or value > INT8_MAX for value in data):
            raise ValueError("tensor data must contain INT8 values in -128..127")
        scale = self.scale
        if isinstance(scale, bool) or not isinstance(scale, (int, float)):
            raise ValueError("tensor scale must be a positive finite float")
        scale = float(scale)
        if not math.isfinite(scale) or scale <= 0.0:
            raise ValueError("tensor scale must be a positive finite float")
        if not isinstance(self.zero_point, int) or isinstance(self.zero_point, bool):
            raise ValueError("tensor zero point must be an INT8 integer")
        if self.zero_point < INT8_MIN or self.zero_point > INT8_MAX:
            raise ValueError("tensor zero point must be an INT8 integer")
        object.__setattr__(self, "shape", shape)
        object.__setattr__(self, "data", data)
        object.__setattr__(self, "scale", scale)

    @property
    def height(self) -> int:
        return self.shape[0]

    @property
    def width(self) -> int:
        return self.shape[1]

    @property
    def channels(self) -> int:
        return self.shape[2]

    def value_at(self, h: int, w: int, c: int) -> int:
        """Return the raw INT8 value at NHWC coordinate (h, w, c)."""
        return self.data[(h * self.width + w) * self.channels + c]


def _trunc_div(numerator: int, denominator: int) -> int:
    quotient = abs(numerator) // denominator
    return quotient if numerator >= 0 else -quotient


def _require_int(value: int, name: str) -> int:
    if not isinstance(value, int) or isinstance(value, bool):
        raise ValueError(f"{name} must be an integer")
    return value


def _require_int32(value: int, name: str) -> int:
    _require_int(value, name)
    if value < INT32_MIN or value > INT32_MAX:
        raise ValueError(f"{name} must be within signed INT32")
    return value


def _require_int8(value: int, name: str) -> int:
    _require_int(value, name)
    if value < INT8_MIN or value > INT8_MAX:
        raise ValueError(f"{name} must be within -128..127")
    return value


def _require_scale(value: float, name: str) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise ValueError(f"{name} must be a positive finite float")
    scale = float(value)
    if not math.isfinite(scale) or scale <= 0.0:
        raise ValueError(f"{name} must be a positive finite float")
    return scale


def _require_weight(value: int, name: str) -> int:
    _require_int(value, name)
    if value < -127 or value > 127:
        raise ValueError(f"{name} must be a symmetric INT8 weight in -127..127; -128 is illegal")
    return value


def _require_multiplier(value: int, name: str) -> int:
    _require_int(value, name)
    if value < 0 or value > INT32_MAX:
        raise ValueError(f"{name} must be a nonnegative INT32 value")
    return value


def _require_shift(value: int, name: str) -> int:
    _require_int(value, name)
    if value < -31 or value > 30:
        raise ValueError(f"{name} must be within -31..30")
    return value


def _checked_accumulate(accumulator: int, term: int, context: str) -> int:
    total = accumulator + term
    if total < INT32_MIN or total > INT32_MAX:
        raise ArithmeticFault(f"checked INT32 overflow in {context}")
    return total


def _validate_act_bounds(act_min: int, act_max: int) -> tuple[int, int]:
    _require_int8(act_min, "ACT_MIN")
    _require_int8(act_max, "ACT_MAX")
    if act_min > act_max:
        raise ValueError("ACT_MIN must not exceed ACT_MAX")
    return act_min, act_max


def _validate_strides(stride_h: int, stride_w: int) -> None:
    _require_int(stride_h, "stride_h")
    _require_int(stride_w, "stride_w")
    if stride_h not in (1, 2) or stride_w not in (1, 2):
        raise ValueError("strides must be 1 or 2")


def _validate_pads(pads: Sequence[int], kernel_h: int, kernel_w: int) -> None:
    names = ("pad_top", "pad_bottom", "pad_left", "pad_right")
    limits = (kernel_h, kernel_h, kernel_w, kernel_w)
    for name, pad, limit in zip(names, pads, limits, strict=True):
        _require_int(pad, name)
        if pad < 0 or pad >= limit:
            raise ValueError(f"{name} must be nonnegative and strictly less than the kernel")


def _output_extent(input_size: int, pad_before: int, pad_after: int, kernel: int, stride: int) -> int:
    extent = (input_size + pad_before + pad_after - kernel) // stride + 1
    if extent < 1:
        raise ValueError("output extent must be at least one in-range input position")
    return extent


def _level_length(node: object, name: str) -> int:
    if not isinstance(node, Sequence) or isinstance(node, (str, bytes)) or len(node) == 0:
        raise ValueError(f"{name} must be a nonempty nested sequence of integers")
    return len(node)


def _flatten_weights(weights: Sequence, shape: tuple[int, ...], name: str) -> tuple[int, ...]:
    flat: list[int] = []

    def visit(node: object, depth: int) -> None:
        if depth == len(shape):
            flat.append(_require_weight(node, name))
            return
        if not isinstance(node, Sequence) or isinstance(node, (str, bytes)):
            raise ValueError(f"{name} must be a rectangular nested sequence of shape {shape}")
        if len(node) != shape[depth]:
            raise ValueError(f"{name} must be a rectangular nested sequence of shape {shape}")
        for child in node:
            visit(child, depth + 1)

    visit(weights, 0)
    return tuple(flat)


def _validate_channel_words(values: Sequence[int], cout: int, name: str) -> tuple[int, ...]:
    if not isinstance(values, Sequence) or isinstance(values, (str, bytes)):
        raise ValueError(f"{name} array must be a sequence with one word per output channel")
    if len(values) != cout:
        raise ValueError(f"{name} array must provide exactly one word per output channel")
    return tuple(values)


def _validate_bias(bias: Sequence[int], cout: int) -> tuple[int, ...]:
    return tuple(
        _require_int32(value, "bias") for value in _validate_channel_words(bias, cout, "bias")
    )


def _validate_multipliers(multipliers: Sequence[int], cout: int) -> tuple[int, ...]:
    return tuple(
        _require_multiplier(value, "multiplier")
        for value in _validate_channel_words(multipliers, cout, "multiplier")
    )


def _validate_shifts(shifts: Sequence[int], cout: int) -> tuple[int, ...]:
    return tuple(
        _require_shift(value, "shift")
        for value in _validate_channel_words(shifts, cout, "shift")
    )


def _validate_conv_weights(
    weights: Sequence[Sequence[Sequence[Sequence[int]]]], cin: int
) -> tuple[int, int, int, tuple[int, ...]]:
    cout = _level_length(weights, "weights")
    kh = _level_length(weights[0], "weights")
    kw = _level_length(weights[0][0], "weights")
    if kh > 16 or kw > 16:
        raise ValueError("kernel dimensions must be within 1..16")
    flat = _flatten_weights(weights, (cout, kh, kw, cin), "weights")
    return cout, kh, kw, flat


def _validate_depthwise_weights(weights: Sequence[Sequence[Sequence[int]]], cin: int) -> tuple[int, int, tuple[int, ...]]:
    kh = _level_length(weights, "weights")
    kw = _level_length(weights[0], "weights")
    if kh > 16 or kw > 16:
        raise ValueError("kernel dimensions must be within 1..16")
    flat = _flatten_weights(weights, (kh, kw, cin), "weights")
    return kh, kw, flat


def _validate_fc_weights(weights: Sequence[Sequence[int]], cin: int) -> tuple[int, tuple[int, ...]]:
    cout = _level_length(weights, "weights")
    flat = _flatten_weights(weights, (cout, cin), "weights")
    return cout, flat


def quantize_multiplier(real_multiplier: float) -> tuple[int, int]:
    """Convert a nonnegative real multiplier with pinned TFLite QuantizeMultiplier semantics."""
    if isinstance(real_multiplier, bool) or not isinstance(real_multiplier, (int, float)):
        raise ValueError("real multiplier must be a nonnegative finite number")
    value = float(real_multiplier)
    if not math.isfinite(value) or value < 0.0:
        raise ValueError("real multiplier must be a nonnegative finite number")
    if value == 0.0:
        return (0, 0)
    fraction, shift = math.frexp(value)
    q31 = Fraction(fraction) * (1 << 31)
    q_fixed = (2 * q31.numerator + q31.denominator) // (2 * q31.denominator)
    if q_fixed == 1 << 31:
        q_fixed >>= 1
        shift += 1
    if shift < -31:
        return (0, 0)
    return (int(q_fixed), shift)


def saturating_rounding_doubling_high_mul(a: int, b: int) -> int:
    """Pinned Q31 product with the INT32_MIN-times-INT32_MIN saturation special case."""
    _require_int32(a, "left operand")
    _require_int32(b, "right operand")
    if a == INT32_MIN and b == INT32_MIN:
        return INT32_MAX
    product = a * b
    nudge = (1 << 30) if product >= 0 else 1 - (1 << 30)
    return _trunc_div(product + nudge, 1 << 31)


def rounding_divide_by_pot(x: int, r: int) -> int:
    """Pinned correctly rounded division by 2^r using an arithmetic right shift."""
    _require_int32(x, "dividend")
    _require_int(r, "exponent")
    if r < 0 or r > 31:
        raise ValueError("exponent must be within 0..31")
    if r == 0:
        return x
    mask = (1 << r) - 1
    remainder = x & mask
    threshold = (mask >> 1) + (1 if x < 0 else 0)
    return (x >> r) + (1 if remainder > threshold else 0)


def multiply_by_quantized_multiplier(x: int, multiplier: int, shift: int) -> int:
    """Pinned double-rounding QM(x, m, s) requantization from numerical profile 1."""
    _require_int32(x, "input")
    _require_multiplier(multiplier, "multiplier")
    _require_shift(shift, "shift")
    shifted = x << max(shift, 0)
    if shifted < INT32_MIN or shifted > INT32_MAX:
        raise ArithmeticFault("checked left shift overflow in requantization")
    product = saturating_rounding_doubling_high_mul(shifted, multiplier)
    return rounding_divide_by_pot(product, max(-shift, 0))


def _requantize(
    accumulator: int,
    multiplier: int,
    shift: int,
    zero_point: int,
    act_min: int,
    act_max: int,
) -> int:
    quantized = multiply_by_quantized_multiplier(accumulator, multiplier, shift) + zero_point
    return max(act_min, min(act_max, quantized))


def _validate_output_quantization(
    output_scale: float, output_zero_point: int
) -> tuple[float, int]:
    scale = _require_scale(output_scale, "output scale")
    zero_point = _require_int8(output_zero_point, "output zero point")
    return scale, zero_point


def conv2d(
    inputs: Tensor,
    weights: Sequence[Sequence[Sequence[Sequence[int]]]],
    bias: Sequence[int],
    multipliers: Sequence[int],
    shifts: Sequence[int],
    *,
    stride_h: int,
    stride_w: int,
    pad_top: int,
    pad_bottom: int,
    pad_left: int,
    pad_right: int,
    output_scale: float,
    output_zero_point: int,
    act_min: int,
    act_max: int,
) -> Tensor:
    """Execute profile-1 CONV2D with checked INT32 accumulation over (Cout, Kh, Kw, Cin) weights."""
    if not isinstance(inputs, Tensor):
        raise ValueError("inputs must be a Tensor")
    cout, kh, kw, flat_weights = _validate_conv_weights(weights, inputs.channels)
    bias_values = _validate_bias(bias, cout)
    multiplier_values = _validate_multipliers(multipliers, cout)
    shift_values = _validate_shifts(shifts, cout)
    act_low, act_high = _validate_act_bounds(act_min, act_max)
    scale, zout = _validate_output_quantization(output_scale, output_zero_point)
    _validate_strides(stride_h, stride_w)
    _validate_pads((pad_top, pad_bottom, pad_left, pad_right), kh, kw)
    oh_extent = _output_extent(inputs.height, pad_top, pad_bottom, kh, stride_h)
    ow_extent = _output_extent(inputs.width, pad_left, pad_right, kw, stride_w)
    cin = inputs.channels
    zin = inputs.zero_point
    output: list[int] = []
    for oh in range(oh_extent):
        for ow in range(ow_extent):
            for c in range(cout):
                accumulator = bias_values[c]
                weight_base = c * kh * kw * cin
                for kernel_h in range(kh):
                    ih = oh * stride_h + kernel_h - pad_top
                    if ih < 0 or ih >= inputs.height:
                        continue
                    for kernel_w in range(kw):
                        iw = ow * stride_w + kernel_w - pad_left
                        if iw < 0 or iw >= inputs.width:
                            continue
                        weight_index = weight_base + (kernel_h * kw + kernel_w) * cin
                        for ci in range(cin):
                            centered = inputs.value_at(ih, iw, ci) - zin
                            product = centered * flat_weights[weight_index + ci]
                            accumulator = _checked_accumulate(
                                accumulator, product, "conv2d accumulation"
                            )
                output.append(
                    _requantize(
                        accumulator,
                        multiplier_values[c],
                        shift_values[c],
                        zout,
                        act_low,
                        act_high,
                    )
                )
    return Tensor((oh_extent, ow_extent, cout), tuple(output), scale, zout)


def depthwise_conv2d(
    inputs: Tensor,
    weights: Sequence[Sequence[Sequence[int]]],
    bias: Sequence[int],
    multipliers: Sequence[int],
    shifts: Sequence[int],
    *,
    stride_h: int,
    stride_w: int,
    pad_top: int,
    pad_bottom: int,
    pad_left: int,
    pad_right: int,
    output_scale: float,
    output_zero_point: int,
    act_min: int,
    act_max: int,
) -> Tensor:
    """Execute profile-1 depthwise convolution (multiplier one) with (Kh, Kw, C) weights."""
    if not isinstance(inputs, Tensor):
        raise ValueError("inputs must be a Tensor")
    kh, kw, flat_weights = _validate_depthwise_weights(weights, inputs.channels)
    cout = inputs.channels
    bias_values = _validate_bias(bias, cout)
    multiplier_values = _validate_multipliers(multipliers, cout)
    shift_values = _validate_shifts(shifts, cout)
    act_low, act_high = _validate_act_bounds(act_min, act_max)
    scale, zout = _validate_output_quantization(output_scale, output_zero_point)
    _validate_strides(stride_h, stride_w)
    _validate_pads((pad_top, pad_bottom, pad_left, pad_right), kh, kw)
    oh_extent = _output_extent(inputs.height, pad_top, pad_bottom, kh, stride_h)
    ow_extent = _output_extent(inputs.width, pad_left, pad_right, kw, stride_w)
    zin = inputs.zero_point
    output: list[int] = []
    for oh in range(oh_extent):
        for ow in range(ow_extent):
            for c in range(cout):
                accumulator = bias_values[c]
                for kernel_h in range(kh):
                    ih = oh * stride_h + kernel_h - pad_top
                    if ih < 0 or ih >= inputs.height:
                        continue
                    for kernel_w in range(kw):
                        iw = ow * stride_w + kernel_w - pad_left
                        if iw < 0 or iw >= inputs.width:
                            continue
                        centered = inputs.value_at(ih, iw, c) - zin
                        product = centered * flat_weights[(kernel_h * kw + kernel_w) * cout + c]
                        accumulator = _checked_accumulate(
                            accumulator, product, "depthwise accumulation"
                        )
                output.append(
                    _requantize(
                        accumulator,
                        multiplier_values[c],
                        shift_values[c],
                        zout,
                        act_low,
                        act_high,
                    )
                )
    return Tensor((oh_extent, ow_extent, cout), tuple(output), scale, zout)


def fully_connected(
    inputs: Tensor,
    weights: Sequence[Sequence[int]],
    bias: Sequence[int],
    multipliers: Sequence[int] | int,
    shifts: Sequence[int] | int,
    *,
    output_scale: float,
    output_zero_point: int,
    act_min: int,
    act_max: int,
) -> Tensor:
    """Execute profile-1 FULLY_CONNECTED with (Cout, Cin) weights and per-channel scales."""
    if not isinstance(inputs, Tensor):
        raise ValueError("inputs must be a Tensor")
    if inputs.height != 1 or inputs.width != 1:
        raise ValueError("FULLY_CONNECTED requires a H=W=1 input tensor")
    cin = inputs.channels
    cout, flat_weights = _validate_fc_weights(weights, cin)
    bias_values = _validate_bias(bias, cout)
    if isinstance(multipliers, int):
        multipliers = [multipliers] * cout
    if isinstance(shifts, int):
        shifts = [shifts] * cout
    multiplier_values = _validate_multipliers(multipliers, cout)
    shift_values = _validate_shifts(shifts, cout)
    act_low, act_high = _validate_act_bounds(act_min, act_max)
    scale, zout = _validate_output_quantization(output_scale, output_zero_point)
    zin = inputs.zero_point
    output: list[int] = []
    for c in range(cout):
        accumulator = bias_values[c]
        for ci in range(cin):
            centered = inputs.data[ci] - zin
            product = centered * flat_weights[c * cin + ci]
            accumulator = _checked_accumulate(accumulator, product, "fc accumulation")
        output.append(
            _requantize(
                accumulator, multiplier_values[c], shift_values[c], zout, act_low, act_high
            )
        )
    return Tensor((1, 1, cout), tuple(output), scale, zout)


def add(
    input0: Tensor,
    input1: Tensor,
    *,
    input0_multiplier: int,
    input0_shift: int,
    input1_multiplier: int,
    input1_shift: int,
    output_multiplier: int,
    output_shift: int,
    output_scale: float,
    output_zero_point: int,
    act_min: int,
    act_max: int,
) -> Tensor:
    """Execute the pinned INT8 ADD path with the 2^20 input pre-scaling and checked sum."""
    if not isinstance(input0, Tensor) or not isinstance(input1, Tensor):
        raise ValueError("ADD inputs must be Tensors")
    if input0.shape != input1.shape:
        raise ValueError("ADD inputs must have identical shapes")
    _require_multiplier(input0_multiplier, "input0 multiplier")
    _require_multiplier(input1_multiplier, "input1 multiplier")
    _require_multiplier(output_multiplier, "output multiplier")
    _require_shift(input0_shift, "input0 shift")
    _require_shift(input1_shift, "input1 shift")
    _require_shift(output_shift, "output shift")
    act_low, act_high = _validate_act_bounds(act_min, act_max)
    scale, zout = _validate_output_quantization(output_scale, output_zero_point)
    output: list[int] = []
    for raw0, raw1 in zip(input0.data, input1.data, strict=True):
        x0 = (raw0 - input0.zero_point) * (1 << 20)
        x1 = (raw1 - input1.zero_point) * (1 << 20)
        term0 = multiply_by_quantized_multiplier(x0, input0_multiplier, input0_shift)
        term1 = multiply_by_quantized_multiplier(x1, input1_multiplier, input1_shift)
        total = term0 + term1
        if total < INT32_MIN or total > INT32_MAX:
            raise ArithmeticFault("checked INT32 overflow in ADD sum")
        output.append(
            _requantize(total, output_multiplier, output_shift, zout, act_low, act_high)
        )
    return Tensor(input0.shape, tuple(output), scale, zout)


def _pool_geometry(
    inputs: Tensor,
    kernel_h: int,
    kernel_w: int,
    stride_h: int,
    stride_w: int,
    pads: Sequence[int],
) -> tuple[int, int]:
    _require_int(kernel_h, "kernel_h")
    _require_int(kernel_w, "kernel_w")
    if kernel_h < 1 or kernel_h > 16 or kernel_w < 1 or kernel_w > 16:
        raise ValueError("pool kernel dimensions must be within 1..16")
    _validate_strides(stride_h, stride_w)
    _validate_pads(pads, kernel_h, kernel_w)
    oh_extent = _output_extent(inputs.height, pads[0], pads[1], kernel_h, stride_h)
    ow_extent = _output_extent(inputs.width, pads[2], pads[3], kernel_w, stride_w)
    return oh_extent, ow_extent


def max_pool(
    inputs: Tensor,
    *,
    kernel_h: int,
    kernel_w: int,
    stride_h: int,
    stride_w: int,
    pad_top: int = 0,
    pad_bottom: int = 0,
    pad_left: int = 0,
    pad_right: int = 0,
    act_min: int = INT8_MIN,
    act_max: int = INT8_MAX,
) -> Tensor:
    """Execute profile-1 MAX_POOL over valid raw positions only, starting from -128."""
    if not isinstance(inputs, Tensor):
        raise ValueError("inputs must be a Tensor")
    act_low, act_high = _validate_act_bounds(act_min, act_max)
    oh_extent, ow_extent = _pool_geometry(
        inputs,
        kernel_h,
        kernel_w,
        stride_h,
        stride_w,
        (pad_top, pad_bottom, pad_left, pad_right),
    )
    output: list[int] = []
    for oh in range(oh_extent):
        for ow in range(ow_extent):
            for c in range(inputs.channels):
                best = INT8_MIN
                for offset_h in range(kernel_h):
                    ih = oh * stride_h + offset_h - pad_top
                    if ih < 0 or ih >= inputs.height:
                        continue
                    for offset_w in range(kernel_w):
                        iw = ow * stride_w + offset_w - pad_left
                        if iw < 0 or iw >= inputs.width:
                            continue
                        best = max(best, inputs.value_at(ih, iw, c))
                output.append(max(act_low, min(act_high, best)))
    return Tensor(
        (oh_extent, ow_extent, inputs.channels), tuple(output), inputs.scale, inputs.zero_point
    )


def _round_ties_away(total: int, count: int) -> int:
    quotient = (abs(total) + count // 2) // count
    return quotient if total >= 0 else -quotient


def average_pool(
    inputs: Tensor,
    *,
    kernel_h: int,
    kernel_w: int,
    stride_h: int,
    stride_w: int,
    pad_top: int = 0,
    pad_bottom: int = 0,
    pad_left: int = 0,
    pad_right: int = 0,
    act_min: int = INT8_MIN,
    act_max: int = INT8_MAX,
) -> Tensor:
    """Execute profile-1 AVERAGE_POOL with ties-away division by the valid-position count."""
    if not isinstance(inputs, Tensor):
        raise ValueError("inputs must be a Tensor")
    act_low, act_high = _validate_act_bounds(act_min, act_max)
    oh_extent, ow_extent = _pool_geometry(
        inputs,
        kernel_h,
        kernel_w,
        stride_h,
        stride_w,
        (pad_top, pad_bottom, pad_left, pad_right),
    )
    output: list[int] = []
    for oh in range(oh_extent):
        for ow in range(ow_extent):
            for c in range(inputs.channels):
                total = 0
                count = 0
                for offset_h in range(kernel_h):
                    ih = oh * stride_h + offset_h - pad_top
                    if ih < 0 or ih >= inputs.height:
                        continue
                    for offset_w in range(kernel_w):
                        iw = ow * stride_w + offset_w - pad_left
                        if iw < 0 or iw >= inputs.width:
                            continue
                        total = _checked_accumulate(
                            total, inputs.value_at(ih, iw, c), "average pool sum"
                        )
                        count += 1
                averaged = _round_ties_away(total, count)
                output.append(max(act_low, min(act_high, averaged)))
    return Tensor(
        (oh_extent, ow_extent, inputs.channels), tuple(output), inputs.scale, inputs.zero_point
    )


def global_average_pool(
    inputs: Tensor,
    *,
    act_min: int = INT8_MIN,
    act_max: int = INT8_MAX,
) -> Tensor:
    """Execute profile-1 GLOBAL_AVERAGE_POOL over the whole HxW input per channel."""
    if not isinstance(inputs, Tensor):
        raise ValueError("inputs must be a Tensor")
    act_low, act_high = _validate_act_bounds(act_min, act_max)
    count = inputs.height * inputs.width
    output: list[int] = []
    for c in range(inputs.channels):
        total = 0
        for h in range(inputs.height):
            for w in range(inputs.width):
                total = _checked_accumulate(total, inputs.value_at(h, w, c), "global average sum")
        averaged = _round_ties_away(total, count)
        output.append(max(act_low, min(act_high, averaged)))
    return Tensor((1, 1, inputs.channels), tuple(output), inputs.scale, inputs.zero_point)


def clamp(inputs: Tensor, act_min: int, act_max: int) -> Tensor:
    """Apply only the activation bounds, preserving shape, scale and zero point."""
    if not isinstance(inputs, Tensor):
        raise ValueError("inputs must be a Tensor")
    act_low, act_high = _validate_act_bounds(act_min, act_max)
    output = tuple(max(act_low, min(act_high, value)) for value in inputs.data)
    return Tensor(inputs.shape, output, inputs.scale, inputs.zero_point)


def _exp_on_interval_q31(a: int) -> int:
    """Pinned gemmlowp exp on the Q31 interval [-1/4, 0) via the 4-term Taylor series."""
    x = a + (1 << 28)
    x2 = saturating_rounding_doubling_high_mul(x, x)
    x3 = saturating_rounding_doubling_high_mul(x2, x)
    x4 = saturating_rounding_doubling_high_mul(x2, x2)
    x4_over_4 = rounding_divide_by_pot(x4, 2)
    series = rounding_divide_by_pot(
        saturating_rounding_doubling_high_mul(x4_over_4 + x3, _EXP_ONE_OVER_THREE) + x2, 1
    )
    return _EXP_CONSTANT_TERM + saturating_rounding_doubling_high_mul(
        _EXP_CONSTANT_TERM, x + series
    )


def _exp_on_negative_values(a: int) -> int:
    """Pinned gemmlowp exp for Q5.26 raw input a <= 0, returning a Q31 result."""
    quarter = 1 << 24
    a_mod_quarter = (a & (quarter - 1)) - quarter
    result = _exp_on_interval_q31(a_mod_quarter << 5)
    remainder = a_mod_quarter - a
    for exponent, multiplier in _EXP_BARREL_MULTIPLIERS:
        if remainder & (1 << (26 + exponent)):
            result = saturating_rounding_doubling_high_mul(result, multiplier)
    return INT32_MAX if a == 0 else result


def _saturating_left_shift(value: int, exponent: int) -> int:
    if exponent <= 0:
        return value
    threshold = (1 << (31 - exponent)) - 1
    if value > threshold:
        return INT32_MAX
    if value < -threshold:
        return INT32_MIN
    return value << exponent


def _one_over_one_plus_x(a: int) -> int:
    """Pinned gemmlowp Newton-Raphson 1/(1+x) for Q31 x in [0, 1), returning Q31."""
    total = a + INT32_MAX
    half_denominator = _trunc_div(total + (1 if total >= 0 else -1), 2)
    estimate = _RECIPROCAL_48_OVER_17 + saturating_rounding_doubling_high_mul(
        half_denominator, _RECIPROCAL_NEG_32_OVER_17
    )
    for _ in range(3):
        product = saturating_rounding_doubling_high_mul(half_denominator, estimate)
        one_minus = (1 << 29) - product
        increment = saturating_rounding_doubling_high_mul(estimate, one_minus)
        estimate += _saturating_left_shift(increment, 2)
    return _saturating_left_shift(estimate, 1)


def softmax_parameters(input_scale: float, beta: float) -> dict[str, int]:
    """Pinned PreprocessSoftmaxScaling/CalculateInputRadius for Q5.26."""
    for name, value in (("input scale", input_scale), ("beta", beta)):
        if isinstance(value, bool) or not isinstance(value, (int, float)):
            raise ValueError(f"softmax {name} must be positive and finite")
        if not math.isfinite(value) or value <= 0:
            raise ValueError(f"softmax {name} must be positive and finite")
    scaled = min(float(beta) * float(input_scale) * (1 << 26), float(INT32_MAX))
    if scaled <= 1.0:
        raise ValueError("softmax scaling must exceed one for the pinned integer kernel")
    multiplier, shift = quantize_multiplier(scaled)
    return {
        "input_multiplier": multiplier,
        "input_left_shift": shift,
        "diff_min": -((31 * (1 << 26)) // (1 << shift)),
    }


def softmax_int8(
    logits: Tensor,
    *,
    input_multiplier: int,
    input_left_shift: int,
    diff_min: int,
) -> Tensor:
    """Execute the pinned TFLite reference_ops::Softmax<int8_t, int8_t> integer path."""
    if not isinstance(logits, Tensor):
        raise ValueError("logits must be a Tensor")
    _require_multiplier(input_multiplier, "input multiplier")
    _require_int(input_left_shift, "input left shift")
    if input_multiplier == 0:
        raise ValueError("softmax input multiplier must be positive")
    if input_left_shift < 0 or input_left_shift > 31:
        raise ValueError("input left shift must be within 0..31")
    _require_int(diff_min, "diff_min")
    radius = (31 * (1 << 26)) // (1 << input_left_shift)
    if diff_min < -radius or diff_min > 0:
        raise ValueError("diff_min exceeds the safe Q5.26 input radius")
    depth = logits.channels
    output: list[int] = []
    for row in range(logits.height * logits.width):
        values = logits.data[row * depth : (row + 1) * depth]
        maximum = max(values)
        exponentials: list[int | None] = []
        for value in values:
            difference = value - maximum
            if difference >= diff_min:
                scaled = saturating_rounding_doubling_high_mul(
                    difference * (1 << input_left_shift), input_multiplier
                )
                exponentials.append(_exp_on_negative_values(scaled))
            else:
                exponentials.append(None)
        accumulation = sum(
            rounding_divide_by_pot(exp, 12) for exp in exponentials if exp is not None
        )
        if accumulation >= 1 << 31:
            raise ArithmeticFault("checked INT32 overflow in softmax accumulation")
        headroom = 32 - accumulation.bit_length()
        num_bits_over_unit = 12 - headroom
        shifted_sum = ((accumulation << headroom) & 0xFFFFFFFF) - (1 << 31)
        scale = _one_over_one_plus_x(shifted_sum)
        for exp in exponentials:
            if exp is None:
                output.append(INT8_MIN)
                continue
            unsaturated = rounding_divide_by_pot(
                saturating_rounding_doubling_high_mul(scale, exp), num_bits_over_unit + 23
            )
            output.append(max(INT8_MIN, min(INT8_MAX, unsaturated + INT8_MIN)))
    return Tensor(
        logits.shape, tuple(output), SOFTMAX_OUTPUT_SCALE, SOFTMAX_OUTPUT_ZERO_POINT
    )
