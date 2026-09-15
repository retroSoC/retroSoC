"""Frozen APUM 1.0 KWS container definitions and independent validators."""

from __future__ import annotations

import hashlib
import struct
from dataclasses import dataclass
from typing import Final

APUM_MAGIC: Final = 0x4D555041
APUM_ABI: Final = 0x00010000
APUM_BYTES: Final = 32768
APUM_HEADER_BYTES: Final = 64
APUM_OPERATOR_OFFSET: Final = 0x0040
APUM_OPERATOR_COUNT: Final = 12
APUM_OPERATOR_BYTES: Final = 64
APUM_TENSOR_OFFSET: Final = 0x0340
APUM_TENSOR_COUNT: Final = 13
APUM_TENSOR_BYTES: Final = 32
APUM_PARAMETER_OFFSET: Final = 0x0500
APUM_PARAMETER_BYTES: Final = 29072
APUM_PARAMETER_END: Final = APUM_PARAMETER_OFFSET + APUM_PARAMETER_BYTES
APUM_PAYLOAD_CRC: Final = 0xB9034B22
APUM_SHA256: Final = "87861b5f866182969e34917b4bf57cab61cd2245c3ab9b933797209322e3ce63"
APUM_PARAMS_SHA256: Final = "0e4eb210d247a45747049ef9602bbd7e90868e9cb1c04fb2a02f128db44e241e"
APUM_MULTIPLIER_SHIFT_SHA256: Final = (
    "222e05821695f3fdd47be682b2cc75e0e735aa106436bf941cdda3ef8cb03b59"
)
TFLITE_SHA256: Final = "aeea436800704fce17b17292e4412630ad856e9d777c044c64ef748a880bd0ae"
CORPUS_SHA256: Final = "57fa600948ef7a19ed5eb0d0e73c7d09fef7d0dbb12bc8833a0a8caad1d6845e"

_TENSOR_PROFILE: Final = (
    (1, 49, 10, 1, 0x4000, 490, 0x3F15AF17, 83),
    (1, 25, 5, 64, 0x0000, 8000, 0x3DA13AC8, -128),
    (1, 25, 5, 64, 0x2000, 8000, 0x3DA99AEA, -128),
    (1, 25, 5, 64, 0x0000, 8000, 0x3D75DD81, -128),
    (1, 25, 5, 64, 0x2000, 8000, 0x3D808854, -128),
    (1, 25, 5, 64, 0x0000, 8000, 0x3D19329E, -128),
    (1, 25, 5, 64, 0x2000, 8000, 0x3D3C02C1, -128),
    (1, 25, 5, 64, 0x0000, 8000, 0x3D070C5A, -128),
    (1, 25, 5, 64, 0x2000, 8000, 0x3D3FDF8A, -128),
    (1, 25, 5, 64, 0x0000, 8000, 0x3DA452DB, -128),
    (1, 1, 1, 64, 0x2000, 64, 0x3DA452DB, -128),
    (1, 1, 1, 12, 0x0000, 12, 0x3E142A46, 14),
    (1, 1, 1, 12, 0x2000, 12, 0x3B800000, -128),
)
_OPCODES: Final = (1, 2, 1, 2, 1, 2, 1, 2, 1, 3, 4, 5)
_WEIGHT_BYTES: Final = (2560, 576, 4096, 576, 4096, 576, 4096, 576, 4096, 0, 768, 0)
_OUTPUT_CHANNELS: Final = (64, 64, 64, 64, 64, 64, 64, 64, 64, 64, 12, 12)
_KERNELS: Final = (
    (10, 4, 2, 2),
    (3, 3, 1, 1),
    (1, 1, 1, 1),
    (3, 3, 1, 1),
    (1, 1, 1, 1),
    (3, 3, 1, 1),
    (1, 1, 1, 1),
    (3, 3, 1, 1),
    (1, 1, 1, 1),
    (25, 5, 25, 5),
    (1, 1, 1, 1),
    (1, 1, 1, 1),
)
_PADDING: Final = (
    (4, 5, 1, 1),
    (1, 1, 1, 1),
    (0, 0, 0, 0),
    (1, 1, 1, 1),
    (0, 0, 0, 0),
    (1, 1, 1, 1),
    (0, 0, 0, 0),
    (1, 1, 1, 1),
    (0, 0, 0, 0),
    (0, 0, 0, 0),
    (0, 0, 0, 0),
    (0, 0, 0, 0),
)


def crc32_iso_hdlc(data: bytes) -> int:
    """Calculate CRC-32/ISO-HDLC with the exact APUM byte ordering."""
    crc = 0xFFFFFFFF
    for value in data:
        crc ^= value
        for _ in range(8):
            crc = (crc >> 1) ^ (0xEDB88320 if (crc & 1) != 0 else 0)
    return crc ^ 0xFFFFFFFF


@dataclass(frozen=True)
class ApumHeader:
    magic: int
    abi: int
    total_bytes: int
    operator_set: int
    mfcc_rows: int
    mfcc_coefficients: int
    classes: int
    operators: int
    parameter_bytes: int
    scratch_bytes: int
    quantization_profile: int
    crc: int
    model_id: int
    threshold: int
    debounce: int
    tensor_count: int
    layout_id: int


@dataclass(frozen=True)
class ApumOperator:
    opcode: int
    flags: int
    input_tensor: int
    output_tensor: int
    weight_offset: int
    bias_offset: int
    multiplier_offset: int
    shift_offset: int
    weight_bytes: int
    output_channels: int
    kernel_height: int
    kernel_width: int
    stride_height: int
    stride_width: int
    padding: tuple[int, int, int, int]
    input_zero: int
    output_zero: int
    clamp_min: int
    clamp_max: int


@dataclass(frozen=True)
class ApumTensor:
    shape: tuple[int, int, int, int]
    scratch_offset: int
    byte_count: int
    element_type: int
    scale_bits: int
    zero_point: int


def _invalid(message: str) -> ValueError:
    return ValueError(f"invalid APUM 1.0: {message}")


def _interval(offset: int, size: int, label: str) -> tuple[int, int, str]:
    if (offset & 15) != 0 or size <= 0 or offset < APUM_PARAMETER_OFFSET:
        raise _invalid(f"{label} range/alignment")
    end = offset + size
    if end > APUM_PARAMETER_END:
        raise _invalid(f"{label} outside parameter region")
    return offset, end, label


def _parse_header(image: bytes) -> ApumHeader:
    words = struct.unpack_from("<10I", image, 0)
    magic, abi, total, op_set, mfcc, classes, params, scratch, quant, crc = words
    model_id = struct.unpack_from("<Q", image, 0x28)[0]
    defaults, tensor_count, layout_id, reserved = struct.unpack_from("<4I", image, 0x30)
    if reserved != 0:
        raise _invalid("header reserved word is nonzero")
    return ApumHeader(
        magic=magic,
        abi=abi,
        total_bytes=total,
        operator_set=op_set,
        mfcc_rows=mfcc & 0xFFFF,
        mfcc_coefficients=mfcc >> 16,
        classes=classes & 0xFFFF,
        operators=classes >> 16,
        parameter_bytes=params,
        scratch_bytes=scratch,
        quantization_profile=quant,
        crc=crc,
        model_id=model_id,
        threshold=defaults & 0xFF,
        debounce=(defaults >> 8) & 0xFF,
        tensor_count=tensor_count,
        layout_id=layout_id,
    )


def _parse_operator(image: bytes, index: int) -> ApumOperator:
    offset = APUM_OPERATOR_OFFSET + index * APUM_OPERATOR_BYTES
    fields = struct.unpack_from("<HHHHIIIIIIHHHH4BiiiiI", image, offset)
    return ApumOperator(
        opcode=fields[0],
        flags=fields[1],
        input_tensor=fields[2],
        output_tensor=fields[3],
        weight_offset=fields[4],
        bias_offset=fields[5],
        multiplier_offset=fields[6],
        shift_offset=fields[7],
        weight_bytes=fields[8],
        output_channels=fields[9],
        kernel_height=fields[10],
        kernel_width=fields[11],
        stride_height=fields[12],
        stride_width=fields[13],
        padding=(fields[14], fields[15], fields[16], fields[17]),
        input_zero=fields[18],
        output_zero=fields[19],
        clamp_min=fields[20],
        clamp_max=fields[21],
    )


def _parse_tensor(image: bytes, index: int) -> ApumTensor:
    offset = APUM_TENSOR_OFFSET + index * APUM_TENSOR_BYTES
    n, height, width, channels, scratch, count, element, scale, zero, reserved = struct.unpack_from(
        "<HHHHIIIIiI", image, offset
    )
    if reserved != 0:
        raise _invalid(f"tensor {index} reserved word is nonzero")
    return ApumTensor(
        shape=(n, height, width, channels),
        scratch_offset=scratch,
        byte_count=count,
        element_type=element,
        scale_bits=scale,
        zero_point=zero,
    )


def _validate_header(header: ApumHeader, image: bytes) -> None:
    expected = (
        header.magic == APUM_MAGIC,
        header.abi == APUM_ABI,
        header.total_bytes == APUM_BYTES,
        header.operator_set == 1,
        header.mfcc_rows == 49,
        header.mfcc_coefficients == 10,
        header.classes == 12,
        header.operators == APUM_OPERATOR_COUNT,
        header.parameter_bytes == APUM_PARAMETER_BYTES,
        header.scratch_bytes == APUM_BYTES,
        header.quantization_profile == 1,
        header.model_id == 0xCE4F70006843EAAE,
        header.threshold == 128,
        header.debounce == 3,
        header.tensor_count == APUM_TENSOR_COUNT,
        header.layout_id == 1,
    )
    if not all(expected):
        raise _invalid("header profile")
    if image[0x32:0x34] != b"\x00\x00":
        raise _invalid("header defaults reserved bits")
    if crc32_iso_hdlc(image[APUM_HEADER_BYTES:]) != header.crc:
        raise _invalid("payload CRC")
    if header.crc != APUM_PAYLOAD_CRC:
        raise _invalid("non-frozen payload CRC")


def _validate_tensors(image: bytes) -> list[ApumTensor]:
    tensors = [_parse_tensor(image, index) for index in range(APUM_TENSOR_COUNT)]
    for index, tensor in enumerate(tensors):
        n, height, width, channels, scratch, count, scale, zero = _TENSOR_PROFILE[index]
        if (
            tensor.shape != (n, height, width, channels)
            or tensor.scratch_offset != scratch
            or tensor.byte_count != count
            or tensor.element_type != 1
            or tensor.scale_bits != scale
            or tensor.zero_point != zero
        ):
            raise _invalid(f"tensor {index} fixed profile")
        if tensor.byte_count != n * height * width * channels:
            raise _invalid(f"tensor {index} byte count")
        if tensor.scratch_offset + tensor.byte_count > APUM_BYTES:
            raise _invalid(f"tensor {index} scratch range")
    return tensors


def _validate_operators(image: bytes, tensors: list[ApumTensor]) -> list[ApumOperator]:
    operators = [_parse_operator(image, index) for index in range(APUM_OPERATOR_COUNT)]
    intervals: list[tuple[int, int, str]] = []
    for index, operator in enumerate(operators):
        if (
            operator.opcode != _OPCODES[index]
            or operator.flags != (1 if index < 9 else 0)
            or operator.input_tensor != index
            or operator.output_tensor != index + 1
            or operator.weight_bytes != _WEIGHT_BYTES[index]
            or operator.output_channels != _OUTPUT_CHANNELS[index]
            or (
                operator.kernel_height,
                operator.kernel_width,
                operator.stride_height,
                operator.stride_width,
            )
            != _KERNELS[index]
            or operator.padding != _PADDING[index]
            or operator.input_zero != tensors[index].zero_point
            or operator.output_zero != tensors[index + 1].zero_point
            or operator.clamp_min != -128
            or operator.clamp_max != 127
        ):
            raise _invalid(f"operator {index} fixed profile")
        if operator.opcode in (3, 5):
            if any(
                value != 0
                for value in (
                    operator.weight_offset,
                    operator.bias_offset,
                    operator.multiplier_offset,
                    operator.shift_offset,
                    operator.weight_bytes,
                )
            ):
                raise _invalid(f"operator {index} parameter fields")
            continue
        if index == 10 and operator.flags != 0:
            raise _invalid("fully connected ReLU flag")
        intervals.extend(
            (
                _interval(
                    operator.weight_offset, operator.weight_bytes, f"operator {index} weights"
                ),
                _interval(
                    operator.bias_offset, operator.output_channels * 4, f"operator {index} biases"
                ),
                _interval(
                    operator.multiplier_offset,
                    operator.output_channels * 4,
                    f"operator {index} multipliers",
                ),
                _interval(
                    operator.shift_offset, operator.output_channels * 4, f"operator {index} shifts"
                ),
            )
        )
    intervals.sort()
    if intervals[0][0] != APUM_PARAMETER_OFFSET or intervals[-1][1] != APUM_PARAMETER_END:
        raise _invalid("parameter coverage")
    for previous, current in zip(intervals, intervals[1:]):
        if previous[1] != current[0]:
            raise _invalid("parameter overlap or gap")
    return operators


def parse_apum(image: bytes, *, require_golden_image: bool = True) -> ApumHeader:
    """Validate the complete immutable APUM 1.0 profile and return its header."""
    if len(image) != APUM_BYTES:
        raise _invalid("image size")
    header = _parse_header(image)
    _validate_header(header, image)
    if image[0x4E0:APUM_PARAMETER_OFFSET] != bytes(APUM_PARAMETER_OFFSET - 0x4E0):
        raise _invalid("metadata padding")
    if image[APUM_PARAMETER_END:] != bytes(APUM_BYTES - APUM_PARAMETER_END):
        raise _invalid("tail padding")
    tensors = _validate_tensors(image)
    _validate_operators(image, tensors)
    if (
        hashlib.sha256(image[APUM_PARAMETER_OFFSET:APUM_PARAMETER_END]).hexdigest()
        != APUM_PARAMS_SHA256
    ):
        raise _invalid("parameter SHA-256")
    if require_golden_image and image_sha256(image) != APUM_SHA256:
        raise _invalid("complete image SHA-256")
    return header


def apum_layout(image: bytes) -> dict[str, object]:
    """Return the reviewable fixed APUM layout after strict validation."""
    header = parse_apum(image)
    tensors = _validate_tensors(image)
    operators = _validate_operators(image, tensors)
    return {
        "abi": header.abi,
        "image_bytes": len(image),
        "payload_crc": header.crc,
        "image_sha256": image_sha256(image),
        "parameter_sha256": hashlib.sha256(
            image[APUM_PARAMETER_OFFSET:APUM_PARAMETER_END]
        ).hexdigest(),
        "operators": [operator.__dict__ for operator in operators],
        "tensors": [tensor.__dict__ for tensor in tensors],
    }


def image_sha256(image: bytes) -> str:
    return hashlib.sha256(image).hexdigest()


def quantize_confidence(softmax: int) -> int:
    """Apply the frozen signed-INT8 Softmax byte to public unsigned confidence."""
    return max(0, min(255, int(softmax) + 128))


def select_class(scores: list[int]) -> int:
    """Choose the lowest class ID among maximum signed INT8 scores."""
    if not scores:
        raise ValueError("at least one class score is required")
    return min(range(len(scores)), key=lambda index: (-scores[index], index))


def _signed_byte(value: int) -> int:
    return value - 256 if value >= 128 else value


def _trunc_div(numerator: int, denominator: int) -> int:
    return numerator // denominator if numerator >= 0 else -((-numerator) // denominator)


def _saturating_high_mul(left: int, right: int) -> int:
    if left == -(1 << 31) and right == -(1 << 31):
        return (1 << 31) - 1
    product = left * right
    nudge = (1 << 30) if product >= 0 else 1 - (1 << 30)
    return _trunc_div(product + nudge, 1 << 31)


def _rounding_divide_pot(value: int, exponent: int) -> int:
    if exponent == 0:
        return value
    mask = (1 << exponent) - 1
    remainder = value & mask
    threshold = (mask >> 1) + (1 if value < 0 else 0)
    return (value >> exponent) + (1 if remainder > threshold else 0)


def _multiply_quantized(value: int, multiplier: int, shift: int) -> int:
    left_shift = max(shift, 0)
    right_shift = max(-shift, 0)
    shifted = value << left_shift
    if not -(1 << 31) <= shifted < (1 << 31):
        raise OverflowError("APUM requantization left shift overflow")
    return _rounding_divide_pot(
        _saturating_high_mul(shifted, multiplier), right_shift
    )


def _exp_interval_q31(raw: int) -> int:
    x = raw + (1 << 28)
    x2 = _saturating_high_mul(x, x)
    x3 = _saturating_high_mul(x2, x)
    x4 = _saturating_high_mul(x2, x2)
    series = _rounding_divide_pot(
        _saturating_high_mul(_rounding_divide_pot(x4, 2) + x3, 715827883)
        + x2,
        1,
    )
    return 1895147668 + _saturating_high_mul(1895147668, x + series)


def _softmax_exp_q31(difference: int) -> int:
    scaled = _saturating_high_mul((-difference) << 24, 1242899200)
    quarter = 1 << 24
    reduced = (scaled & (quarter - 1)) - quarter
    result = _exp_interval_q31(reduced << 5)
    remainder = reduced - scaled
    for exponent, multiplier in (
        (-2, 1672461947),
        (-1, 1302514674),
        (0, 790015084),
        (1, 290630308),
        (2, 39332535),
        (3, 720401),
        (4, 242),
    ):
        if (remainder & (1 << (26 + exponent))) != 0:
            result = _saturating_high_mul(result, multiplier)
    return (1 << 31) - 1 if scaled == 0 else result


def _reciprocal_q31(value: int) -> int:
    total = value + ((1 << 31) - 1)
    half_denominator = _trunc_div(total + (1 if total >= 0 else -1), 2)
    estimate = 1515870810 + _saturating_high_mul(
        half_denominator, -1010580540
    )
    for _ in range(3):
        product = _saturating_high_mul(half_denominator, estimate)
        correction = 0x20000000 - product
        estimate += _saturating_high_mul(estimate, correction)
    return max(-(1 << 31), min((1 << 31) - 1, estimate << 1))


def _parameter_i32(image: bytes, offset: int, count: int) -> list[int]:
    return list(struct.unpack_from(f"<{count}i", image, offset))


def _weighted_operator(
    image: bytes, operator: ApumOperator, source: list[int], operator_index: int
) -> list[int]:
    output = [0] * operator.output_channels
    biases = _parameter_i32(image, operator.bias_offset, operator.output_channels)
    multipliers = _parameter_i32(
        image, operator.multiplier_offset, operator.output_channels
    )
    shifts = _parameter_i32(image, operator.shift_offset, operator.output_channels)
    weights = image[
        operator.weight_offset : operator.weight_offset + operator.weight_bytes
    ]
    output_count = 25 * 5 * operator.output_channels if operator_index < 9 else 12
    output = [0] * output_count
    for output_index in range(output_count):
        channel = output_index % operator.output_channels
        spatial = output_index // operator.output_channels
        output_height = spatial // 5
        output_width = spatial % 5
        accumulator = biases[channel]
        if operator_index == 0:
            for term in range(40):
                input_height = output_height * 2 + term // 4 - 4
                input_width = output_width * 2 + term % 4 - 1
                input_value = operator.input_zero
                if 0 <= input_height < 49 and 0 <= input_width < 10:
                    input_value = source[input_height * 10 + input_width]
                weight = _signed_byte(weights[channel * 40 + term])
                accumulator += (input_value - operator.input_zero) * weight
        elif operator_index in (1, 3, 5, 7):
            for term in range(9):
                input_height = output_height + term // 3 - 1
                input_width = output_width + term % 3 - 1
                input_value = operator.input_zero
                if 0 <= input_height < 25 and 0 <= input_width < 5:
                    input_value = source[
                        (input_height * 5 + input_width) * 64 + channel
                    ]
                weight = _signed_byte(weights[term * 64 + channel])
                accumulator += (input_value - operator.input_zero) * weight
        else:
            for term in range(64):
                input_value = source[term] if operator_index == 10 else source[spatial * 64 + term]
                weight = _signed_byte(weights[channel * 64 + term])
                accumulator += (input_value - operator.input_zero) * weight
        if not -(1 << 31) <= accumulator < (1 << 31):
            raise OverflowError(f"APUM operator {operator_index} accumulator overflow")
        quantized = (
            _multiply_quantized(accumulator, multipliers[channel], shifts[channel])
            + operator.output_zero
        )
        clamp_min = max(operator.clamp_min, operator.output_zero) if operator.flags & 1 else -128
        output[output_index] = max(clamp_min, min(operator.clamp_max, quantized))
    return output


def _softmax(logits: list[int]) -> list[int]:
    maximum = max(logits)
    exponentials = [
        _softmax_exp_q31(maximum - value) if value - maximum >= -124 else 0
        for value in logits
    ]
    accumulation = sum(_rounding_divide_pot(value, 12) for value in exponentials)
    headroom = 32 - accumulation.bit_length()
    shifted_sum = ((accumulation << headroom) & 0xFFFFFFFF) - (1 << 31)
    scale = _reciprocal_q31(shifted_sum)
    num_bits_over_unit = 12 - headroom
    result = []
    for exponential in exponentials:
        probability = _rounding_divide_pot(
            _saturating_high_mul(scale, exponential), num_bits_over_unit + 23
        )
        result.append(max(-128, min(127, probability - 128)))
    return result


def infer_apum(image: bytes, features: bytes) -> list[list[int]]:
    """Run the frozen scalar INT8 graph and return every published tensor."""
    parse_apum(image)
    if len(features) != 490:
        raise ValueError("APUM inference requires exactly 490 INT8 feature bytes")
    tensors = [_parse_tensor(image, index) for index in range(APUM_TENSOR_COUNT)]
    operators = [_parse_operator(image, index) for index in range(APUM_OPERATOR_COUNT)]
    current = [_signed_byte(value) for value in features]
    layers: list[list[int]] = []
    for operator_index, operator in enumerate(operators):
        if operator_index < 9 or operator_index == 10:
            current = _weighted_operator(image, operator, current, operator_index)
        elif operator_index == 9:
            pooled = []
            for channel in range(64):
                total = sum(current[spatial * 64 + channel] for spatial in range(125))
                pooled.append(
                    _trunc_div(total + (62 if total >= 0 else -62), 125)
                )
            current = pooled
        else:
            current = _softmax(current)
        if len(current) != tensors[operator.output_tensor].byte_count:
            raise ValueError(f"APUM operator {operator_index} output size")
        layers.append(current)
    return layers
