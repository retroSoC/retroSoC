"""NPU numerical profile 1 independent scalar reference tests."""

from __future__ import annotations

import sys
from pathlib import Path

import pytest


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

from npu_reference import (  # noqa: E402
    INT32_MAX,
    INT32_MIN,
    SOFTMAX_OUTPUT_SCALE,
    SOFTMAX_OUTPUT_ZERO_POINT,
    ArithmeticFault,
    Tensor,
    add,
    average_pool,
    clamp,
    conv2d,
    depthwise_conv2d,
    fully_connected,
    global_average_pool,
    max_pool,
    multiply_by_quantized_multiplier,
    quantize_multiplier,
    rounding_divide_by_pot,
    saturating_rounding_doubling_high_mul,
    softmax_int8,
)

# quantize_multiplier(1.0) == (1073741824, 1); QM(x, 2^30, 1) is the identity for |x| < 2^30.
IDENTITY_MULTIPLIER = 1073741824
IDENTITY_SHIFT = 1


def _run_conv(inputs, weights, bias, **kwargs):
    params = {
        "stride_h": 1,
        "stride_w": 1,
        "pad_top": 0,
        "pad_bottom": 0,
        "pad_left": 0,
        "pad_right": 0,
        "output_scale": 0.05,
        "output_zero_point": -3,
        "act_min": -128,
        "act_max": 127,
    }
    params.update(kwargs)
    cout = len(bias)
    return conv2d(
        inputs,
        weights,
        bias,
        [IDENTITY_MULTIPLIER] * cout,
        [IDENTITY_SHIFT] * cout,
        **params,
    )


def test_quantize_multiplier_known_values():
    assert quantize_multiplier(0.5) == (1073741824, 0)
    assert quantize_multiplier(1.0) == (1073741824, 1)
    assert quantize_multiplier(0.25) == (1073741824, -1)
    assert quantize_multiplier(0.75) == (1610612736, 0)
    assert quantize_multiplier(1.0 / 3.0) == (1431655765, -1)
    assert quantize_multiplier(0.0) == (0, 0)


def test_quantize_multiplier_carry_renormalization():
    # frexp(1.9999999999999998) fraction rounds up to exactly 2^31, so the pinned
    # carry step halves the Q31 word and increments the shift.
    assert quantize_multiplier(1.9999999999999998) == (1073741824, 2)


def test_quantize_multiplier_shift_boundaries():
    assert quantize_multiplier(2.0**-31) == (1073741824, -30)
    assert quantize_multiplier(2.0**-32) == (1073741824, -31)
    # Shifts below -31 flush to multiplier=0, shift=0.
    assert quantize_multiplier(2.0**-33) == (0, 0)
    assert quantize_multiplier(536870912.0) == (1073741824, 30)


def test_quantize_multiplier_rejects_invalid():
    with pytest.raises(ValueError):
        quantize_multiplier(-0.5)
    with pytest.raises(ValueError):
        quantize_multiplier(float("nan"))
    with pytest.raises(ValueError):
        quantize_multiplier(float("inf"))


def test_saturating_rounding_doubling_high_mul():
    srdhm = saturating_rounding_doubling_high_mul
    assert srdhm(1 << 30, 1 << 30) == 1 << 29
    assert srdhm(-(1 << 30), 1 << 30) == -(1 << 29)
    assert srdhm(0, INT32_MIN) == 0
    assert srdhm(INT32_MAX, INT32_MAX) == 2147483646
    # INT32_MIN times INT32_MIN saturates to INT32_MAX.
    assert srdhm(INT32_MIN, INT32_MIN) == INT32_MAX
    # Nudge asymmetry: exact ties round toward positive infinity. The positive
    # product gets 2^30, the negative one gets 1-2^30, so (1*2^30)/2^31 ties up
    # to 1 while (-1*2^30)/2^31 truncates to 0.
    assert srdhm(1, 1 << 30) == 1
    assert srdhm(-1, 1 << 30) == 0
    assert srdhm(3, 5) == 0


def test_rounding_divide_by_pot():
    rdp = rounding_divide_by_pot
    assert rdp(100, 0) == 100
    assert rdp(-100, 0) == -100
    assert rdp(4, 1) == 2
    assert rdp(-6, 1) == -3
    # Positive and negative ties both round away from zero.
    assert rdp(7, 1) == 4
    assert rdp(5, 1) == 3
    assert rdp(-7, 1) == -4
    assert rdp(-5, 1) == -3
    assert rdp(-3, 1) == -2
    assert rdp(3, 1) == 2
    # The negative threshold gains +1, giving the ties-away asymmetry at r=2.
    assert rdp(6, 2) == 2
    assert rdp(-6, 2) == -2
    assert rdp(2, 2) == 1
    assert rdp(-2, 2) == -1


def test_multiply_by_quantized_multiplier_double_rounding():
    # Double rounding: SRDHM rounds 5*0.5 to 3 (tie up), then RDP rounds 3/2 to
    # 2. A single rounding of 5*0.25=1.25 would give 1.
    assert multiply_by_quantized_multiplier(5, 1 << 30, -1) == 2
    assert multiply_by_quantized_multiplier(3, 1 << 30, -1) == 1
    # SRDHM rounds 11*0.5 to 6 (tie up), then RDP rounds 6/4 to 2. A single
    # rounding of 11*0.25=2.75 would give 3.
    assert multiply_by_quantized_multiplier(11, 1 << 30, -2) == 2
    assert multiply_by_quantized_multiplier(1000, 1 << 30, 0) == 500
    assert multiply_by_quantized_multiplier(117, IDENTITY_MULTIPLIER, IDENTITY_SHIFT) == 117
    assert multiply_by_quantized_multiplier(1, 1 << 30, 30) == 1 << 29
    assert multiply_by_quantized_multiplier(1 << 30, 1 << 30, -31) == 0


def test_multiply_by_quantized_multiplier_faults_and_validation():
    with pytest.raises(ArithmeticFault):
        multiply_by_quantized_multiplier(1 << 30, 1 << 30, 2)
    with pytest.raises(ArithmeticFault):
        multiply_by_quantized_multiplier(-(1 << 30), 1 << 30, 2)
    with pytest.raises(ValueError):
        multiply_by_quantized_multiplier(1, 1 << 30, 31)
    with pytest.raises(ValueError):
        multiply_by_quantized_multiplier(1, 1 << 30, -32)
    with pytest.raises(ValueError):
        multiply_by_quantized_multiplier(1, -1, 0)
    with pytest.raises(ValueError):
        multiply_by_quantized_multiplier(1, 1 << 31, 0)


def test_tensor_validation():
    Tensor((1, 1, 1), (0,), 0.1, 0)
    with pytest.raises(ValueError):
        Tensor((1, 1), (0,), 0.1, 0)
    with pytest.raises(ValueError):
        Tensor((0, 1, 1), (), 0.1, 0)
    with pytest.raises(ValueError):
        Tensor((1, 1, 1), (0, 1), 0.1, 0)
    with pytest.raises(ValueError):
        Tensor((1, 1, 1), (128,), 0.1, 0)
    with pytest.raises(ValueError):
        Tensor((1, 1, 1), (0,), 0.0, 0)
    with pytest.raises(ValueError):
        Tensor((1, 1, 1), (0,), 0.1, 128)


def test_conv2d_hand_computed():
    inputs = Tensor((3, 3, 1), tuple(range(1, 10)), 0.02, 2)
    weights = [[[[1], [2]], [[3], [4]]]]
    # Manual INT32 accumulators with zp=2, bias=10, identity requant, zout=-3:
    # 10+(1-2)*1+(2-2)*2+(4-2)*3+(5-2)*4 = 27 -> 24
    # 10+(2-2)*1+(3-2)*2+(5-2)*3+(6-2)*4 = 37 -> 34
    # 10+(4-2)*1+(5-2)*2+(7-2)*3+(8-2)*4 = 57 -> 54
    # 10+(5-2)*1+(6-2)*2+(8-2)*3+(9-2)*4 = 67 -> 64
    output = _run_conv(inputs, weights, [10])
    assert output.shape == (2, 2, 1)
    assert output.data == (24, 34, 54, 64)
    assert output.scale == 0.05
    assert output.zero_point == -3


def test_conv2d_padding_contributes_zero_point():
    inputs = Tensor((3, 3, 1), tuple(range(1, 10)), 0.02, 2)
    weights = [[[[1], [2]], [[3], [4]]]]
    # Pad top/left by one: padding positions contribute the raw zero point 2,
    # centering to zero. out(0,0) sees only input (0,0): 10+(1-2)*4=6 -> 3.
    # out(0,1) sees (0,0),(0,1): 10+(1-2)*3+(2-2)*4=7 -> 4.
    output = _run_conv(inputs, weights, [10], pad_top=1, pad_left=1)
    assert output.shape == (3, 3, 1)
    assert output.data == (3, 4, 11, 13, 24, 34, 31, 54, 64)


def test_conv2d_activation_bounds():
    inputs = Tensor((1, 1, 1), (5,), 0.02, 10)
    weights = [[[[4]]]]
    # acc = 0 + (5-10)*4 = -20 -> zout -3 gives -23.
    plain = _run_conv(inputs, weights, [0])
    assert plain.data == (-23,)
    # ReLU-derived bound max(ACT_MIN, zout) clamps to -3.
    relu = _run_conv(inputs, weights, [0], act_min=-3)
    assert relu.data == (-3,)


def test_conv2d_accumulation_overflow():
    inputs = Tensor((1, 1, 1), (127,), 0.02, 0)
    with pytest.raises(ArithmeticFault):
        _run_conv(inputs, [[[[127]]]], [INT32_MAX], output_zero_point=0)
    negatives = Tensor((1, 1, 1), (-128,), 0.02, 0)
    with pytest.raises(ArithmeticFault):
        _run_conv(negatives, [[[[127]]]], [INT32_MIN], output_zero_point=0)
    # An accumulator exactly at the INT32 limit is legal (shift-0 requant here).
    output = conv2d(
        inputs,
        [[[[1]]]],
        [INT32_MAX - 127],
        [1 << 30],
        [0],
        stride_h=1,
        stride_w=1,
        pad_top=0,
        pad_bottom=0,
        pad_left=0,
        pad_right=0,
        output_scale=0.05,
        output_zero_point=0,
        act_min=-128,
        act_max=127,
    )
    assert output.data == (127,)


def test_conv2d_validation():
    inputs = Tensor((3, 3, 1), tuple(range(9)), 0.02, 0)
    with pytest.raises(ValueError):
        _run_conv(inputs, [[[[-128]]]], [0])
    with pytest.raises(ValueError):
        _run_conv(inputs, [[[[1]]]], [0, 0])
    with pytest.raises(ValueError):
        _run_conv(inputs, [[[[1]]]], [0], stride_h=3)
    with pytest.raises(ValueError):
        _run_conv(inputs, [[[[1], [1]], [[1], [1]]]], [0], pad_top=2)
    with pytest.raises(ValueError):
        _run_conv(inputs, [[[[1]]]], [0], act_min=5, act_max=-5)
    two_channel = Tensor((1, 1, 2), (1, 2), 0.02, 0)
    with pytest.raises(ValueError):
        _run_conv(two_channel, [[[[1]]]], [0])
    tiny = Tensor((1, 1, 1), (0,), 0.02, 0)
    with pytest.raises(ValueError):
        _run_conv(tiny, [[[[1], [1]]]], [0])


def test_depthwise_conv2d_hand_computed():
    inputs = Tensor(
        (4, 4, 1),
        (5, -3, 0, 7, 12, 1, -6, 2, -9, 4, 8, -1, 3, -5, 6, 10),
        0.03,
        -2,
    )
    weights = [[[1], [0], [-1]], [[2], [1], [2]], [[-1], [0], [1]]]
    # 3x3 kernel, stride 1, pad 1 everywhere, bias -50, zp -2, identity requant,
    # zout 4. out(1,1) covers rows/cols 0..2:
    # -50 + 7*1 + (-1)*0 + 2*(-1) + 14*2 + 3*1 + (-4)*2 + (-7)*(-1) + 6*0 + 10*1
    # = -5 -> -1. out(0,0) covers the valid 2x2 corner: -50+7*1+(-1)*2+14*0+3*1
    # = -42 -> -38.
    output = depthwise_conv2d(
        inputs,
        weights,
        [-50],
        [IDENTITY_MULTIPLIER],
        [IDENTITY_SHIFT],
        stride_h=1,
        stride_w=1,
        pad_top=1,
        pad_bottom=1,
        pad_left=1,
        pad_right=1,
        output_scale=0.04,
        output_zero_point=4,
        act_min=-128,
        act_max=127,
    )
    assert output.shape == (4, 4, 1)
    assert output.data == (
        -38, -47, -27, -29, -19, -1, -51, -58, -47, -13, -8, -37, -53, -40, -15, -8
    )


def test_depthwise_conv2d_multi_channel_stride2():
    inputs = Tensor(
        (3, 3, 2),
        (1, 10, 2, 20, 3, 30, 4, 40, 5, 50, 6, 60, 7, 70, 8, 80, 9, 90),
        0.03,
        0,
    )
    weights = [[[1, -1], [0, 2]], [[-1, 1], [1, 0]], [[2, 1], [0, -2]]]
    # 3x2 kernel, stride 2, zp 0. Channel 0: 10+1*1+2*0+4*(-1)+5*1+7*2+8*0 = 26.
    # Channel 1: -20+10*(-1)+20*2+40*1+50*0+70*1+80*(-2) = -40.
    output = depthwise_conv2d(
        inputs,
        weights,
        [10, -20],
        [IDENTITY_MULTIPLIER, IDENTITY_MULTIPLIER],
        [IDENTITY_SHIFT, IDENTITY_SHIFT],
        stride_h=2,
        stride_w=2,
        pad_top=0,
        pad_bottom=0,
        pad_left=0,
        pad_right=0,
        output_scale=0.04,
        output_zero_point=0,
        act_min=-128,
        act_max=127,
    )
    assert output.shape == (1, 1, 2)
    assert output.data == (26, -40)


def test_fully_connected_hand_computed():
    inputs = Tensor((1, 1, 3), (10, -20, 30), 0.01, 1)
    weights = [[1, -1, 2], [-2, 4, 1]]
    # Channel 0: 7 + (10-1)*1 + (-20-1)*(-1) + (30-1)*2 = 95 -> 100 with zout 5.
    # Channel 1: -9 + 9*(-2) + (-21)*4 + 29*1 = -82 -> -77.
    output = fully_connected(
        inputs,
        weights,
        [7, -9],
        [IDENTITY_MULTIPLIER, IDENTITY_MULTIPLIER],
        [IDENTITY_SHIFT, IDENTITY_SHIFT],
        output_scale=0.02,
        output_zero_point=5,
        act_min=-128,
        act_max=127,
    )
    assert output.shape == (1, 1, 2)
    assert output.data == (100, -77)
    # Per-tensor scale form broadcasts one (multiplier, shift) pair.
    broadcast = fully_connected(
        inputs,
        weights,
        [7, -9],
        IDENTITY_MULTIPLIER,
        IDENTITY_SHIFT,
        output_scale=0.02,
        output_zero_point=5,
        act_min=-128,
        act_max=127,
    )
    assert broadcast.data == output.data


def test_fully_connected_validation():
    inputs = Tensor((1, 1, 1), (127,), 0.01, 0)
    with pytest.raises(ValueError):
        fully_connected(
            inputs, [[-128]], [0], IDENTITY_MULTIPLIER, IDENTITY_SHIFT,
            output_scale=0.02, output_zero_point=0, act_min=-128, act_max=127,
        )
    with pytest.raises(ValueError):
        fully_connected(
            Tensor((1, 2, 1), (1, 2), 0.01, 0), [[1]], [0],
            IDENTITY_MULTIPLIER, IDENTITY_SHIFT,
            output_scale=0.02, output_zero_point=0, act_min=-128, act_max=127,
        )
    with pytest.raises(ArithmeticFault):
        fully_connected(
            inputs, [[127]], [INT32_MAX], IDENTITY_MULTIPLIER, IDENTITY_SHIFT,
            output_scale=0.02, output_zero_point=0, act_min=-128, act_max=127,
        )


def _run_add(input0, input1, **kwargs):
    multiplier, shift = quantize_multiplier(0.5)
    out_multiplier, out_shift = quantize_multiplier(2.0**-19)
    params = {
        "input0_multiplier": multiplier,
        "input0_shift": shift,
        "input1_multiplier": multiplier,
        "input1_shift": shift,
        "output_multiplier": out_multiplier,
        "output_shift": out_shift,
        "output_scale": 0.01,
        "output_zero_point": 15,
        "act_min": -128,
        "act_max": 127,
    }
    params.update(kwargs)
    return add(input0, input1, **params)


def test_add_hand_computed():
    # scale0=scale1=output scale: input multipliers are 0.5 and the output
    # multiplier is 2^-19, so out = clamp((a-z0) + (b-z1) + zout) exactly.
    input0 = Tensor((1, 2, 2), (5, -3, 0, 120), 0.01, 10)
    input1 = Tensor((1, 2, 2), (-7, 3, 40, -100), 0.01, -5)
    output = _run_add(input0, input1)
    assert output.shape == (1, 2, 2)
    assert output.data == (8, 10, 50, 30)
    assert output.scale == 0.01
    assert output.zero_point == 15
    # 110 + 15 = 125 stays in range; a larger sum clamps to ACT_MAX.
    hot = Tensor((1, 1, 1), (127,), 0.01, 0)
    hotter = Tensor((1, 1, 1), (127,), 0.01, 0)
    assert _run_add(hot, hotter).data == (127,)


def test_add_faults_and_validation():
    input0 = Tensor((1, 1, 1), (127,), 0.01, -128)
    input1 = Tensor((1, 1, 1), (-128,), 0.01, 127)
    with pytest.raises(ArithmeticFault):
        add(
            input0,
            input1,
            input0_multiplier=INT32_MAX,
            input0_shift=30,
            input1_multiplier=1 << 30,
            input1_shift=0,
            output_multiplier=1 << 30,
            output_shift=0,
            output_scale=0.01,
            output_zero_point=0,
            act_min=-128,
            act_max=127,
        )
    with pytest.raises(ValueError):
        _run_add(input0, Tensor((1, 1, 2), (1, 2), 0.01, -128))


def test_max_pool_padding_exclusion():
    # Zero point 100 is metadata only: padding is excluded entirely, so the
    # maximum comes from valid raw positions even when all are negative.
    inputs = Tensor((2, 2, 1), (-100, -90, -80, -70), 0.05, 100)
    output = max_pool(
        inputs,
        kernel_h=2,
        kernel_w=2,
        stride_h=1,
        stride_w=1,
        pad_top=1,
        pad_bottom=1,
        pad_left=1,
        pad_right=1,
    )
    assert output.shape == (3, 3, 1)
    assert output.data == (-100, -90, -90, -80, -70, -70, -80, -70, -70)
    assert output.scale == inputs.scale
    assert output.zero_point == inputs.zero_point
    valid = max_pool(inputs, kernel_h=2, kernel_w=2, stride_h=1, stride_w=1)
    assert valid.data == (-70,)


def test_max_pool_multi_channel_and_clamp():
    inputs = Tensor(
        (3, 4, 2),
        (-15, -12, -8, -5, -1, 2, 6, 9, 13, -15, -11, -8,
         -4, -1, 3, 6, 10, 13, -14, -11, -7, -4, 0, 3),
        0.05,
        0,
    )
    output = max_pool(
        inputs,
        kernel_h=3,
        kernel_w=3,
        stride_h=2,
        stride_w=2,
        pad_top=1,
        pad_bottom=1,
        pad_left=1,
        pad_right=1,
    )
    assert output.shape == (2, 2, 2)
    assert output.data == (13, -5, 6, 9, 13, 13, 3, 6)
    clamped = max_pool(
        inputs,
        kernel_h=3,
        kernel_w=3,
        stride_h=2,
        stride_w=2,
        pad_top=1,
        pad_bottom=1,
        pad_left=1,
        pad_right=1,
        act_min=0,
        act_max=10,
    )
    assert clamped.data == (10, 0, 6, 9, 10, 10, 3, 6)


def test_average_pool_ties_and_padding():
    inputs = Tensor((1, 2, 2), (1, -1, 2, -2), 0.05, 0)
    # 3/2=1.5 ties away to 2; -3/2=-1.5 ties away to -2.
    output = average_pool(inputs, kernel_h=1, kernel_w=2, stride_h=1, stride_w=1)
    assert output.data == (2, -2)
    # pad_left=1: the first output averages only the valid column (count 1).
    padded = average_pool(
        inputs, kernel_h=1, kernel_w=2, stride_h=1, stride_w=1, pad_left=1
    )
    assert padded.shape == (1, 2, 2)
    assert padded.data == (1, -1, 2, -2)
    wide = Tensor((1, 3, 2), (1, -1, 2, -2, 3, -4), 0.05, 0)
    # 6/3=2 exactly; -7/3=-2.33 rounds to -2.
    assert average_pool(wide, kernel_h=1, kernel_w=3, stride_h=1, stride_w=1).data == (2, -2)
    assert average_pool(wide, kernel_h=1, kernel_w=3, stride_h=1, stride_w=1,
                        act_min=0).data == (2, 0)


def test_global_average_pool():
    inputs = Tensor((2, 2, 2), (1, -1, 2, -2, 3, -3, 4, -4), 0.07, 9)
    # Channel sums 10 and -10 over count H*W=4: 2.5 -> 3, -2.5 -> -3.
    output = global_average_pool(inputs)
    assert output.shape == (1, 1, 2)
    assert output.data == (3, -3)
    assert output.scale == inputs.scale
    assert output.zero_point == inputs.zero_point


def test_clamp():
    inputs = Tensor((1, 1, 5), (-128, -5, 0, 100, 127), 0.1, -3)
    output = clamp(inputs, -3, 40)
    assert output.shape == inputs.shape
    assert output.data == (-3, -3, 0, 40, 40)
    assert output.scale == inputs.scale
    assert output.zero_point == inputs.zero_point


def test_softmax_int8_kws_logits():
    logits = Tensor(
        (1, 1, 12), (12, -3, 15, -20, 7, 25, -31, 13, -9, 5, -17, 30), 0.1446, 14
    )
    output = softmax_int8(logits)
    # Frozen constants computed once with the pinned integer path in
    # npu_reference.softmax_int8 (input_multiplier=1242899200, left shift 24,
    # diff_min=-124) and cross-checked against a float64 softmax at the
    # effective input scale 1242899200/2^33 within one LSB.
    assert output.data == (
        -118, -127, -112, -128, -123, -60, -128, -116, -128, -124, -128, 11
    )
    # Output scale 1/256 with zero point -128: probabilities sum to about 256.
    assert 254 <= sum(value + 128 for value in output.data) <= 258
    assert output.scale == SOFTMAX_OUTPUT_SCALE == 1.0 / 256.0
    assert output.zero_point == SOFTMAX_OUTPUT_ZERO_POINT == -128
    assert output.shape == (1, 1, 12)


def test_softmax_int8_edge_cases():
    # Uniform logits give a uniform distribution: 256/12 rounds to 21 per class.
    uniform = softmax_int8(Tensor((1, 1, 12), (5,) * 12, 0.1446, 0))
    assert uniform.data == (-107,) * 12
    # Every non-maximum class below diff_min: the winner takes probability one,
    # which saturates the INT8 output at 127; excluded classes emit -128.
    single = softmax_int8(Tensor((1, 1, 3), (0, -125, -125), 0.1446, 0))
    assert single.data == (127, -128, -128)
    # diff_min boundary: -124 is included, -125 is excluded (both emit -128
    # here because exp(-124) is far below one output LSB).
    boundary = softmax_int8(Tensor((1, 1, 3), (0, -124, -125), 0.1446, 0))
    assert boundary.data == (127, -128, -128)
    # Softmax runs over the trailing channel dim of each H*W row; tied maxima
    # share probability equally.
    two_rows = softmax_int8(Tensor((1, 2, 3), (10, 0, -10, -5, 5, 15), 0.1446, 0))
    assert two_rows.data == (70, -81, -117, -117, -81, 70)
    assert sum(value + 128 for value in two_rows.data[:3]) == 256
    assert sum(value + 128 for value in two_rows.data[3:]) == 256


def test_softmax_int8_accumulation_overflow():
    # 4096 tied maxima accumulate 4096 * 524288 = 2^31, which traps instead of
    # wrapping the checked Q12 accumulation.
    logits = Tensor((1, 1, 4096), (7,) * 4096, 0.1, 0)
    with pytest.raises(ArithmeticFault):
        softmax_int8(logits)


def test_softmax_int8_parameter_validation():
    logits = Tensor((1, 1, 2), (0, -1), 0.1446, 0)
    with pytest.raises(ValueError):
        softmax_int8(logits, input_multiplier=-1)
    with pytest.raises(ValueError):
        softmax_int8(logits, input_left_shift=25)
    with pytest.raises(ValueError):
        softmax_int8(logits, diff_min=-125)
