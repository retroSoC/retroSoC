"""Import the locked MLPerf Tiny KWS TFLite graph into frozen APUM 1.0."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import struct
import subprocess
from dataclasses import dataclass
from pathlib import Path

from apu_kws import (
    APUM_ABI,
    APUM_BYTES,
    APUM_HEADER_BYTES,
    APUM_MAGIC,
    APUM_MULTIPLIER_SHIFT_SHA256,
    APUM_PARAMETER_END,
    APUM_PARAMETER_OFFSET,
    APUM_PARAMS_SHA256,
    APUM_PAYLOAD_CRC,
    APUM_SHA256,
    TFLITE_SHA256,
    apum_layout,
    crc32_iso_hdlc,
    image_sha256,
    parse_apum,
)

_OPERATOR_CODES = {
    "CONV_2D": 3,
    "DEPTHWISE_CONV_2D": 4,
    "AVERAGE_POOL_2D": 1,
    "RESHAPE": 22,
    "FULLY_CONNECTED": 9,
    "SOFTMAX": 25,
}
_APUM_OPCODES = (1, 2, 1, 2, 1, 2, 1, 2, 1, 3, 4, 5)
_ACTIVATIONS = (
    (22, (1, 25, 5, 64), 0x0000),
    (23, (1, 25, 5, 64), 0x2000),
    (24, (1, 25, 5, 64), 0x0000),
    (25, (1, 25, 5, 64), 0x2000),
    (26, (1, 25, 5, 64), 0x0000),
    (27, (1, 25, 5, 64), 0x2000),
    (28, (1, 25, 5, 64), 0x0000),
    (29, (1, 25, 5, 64), 0x2000),
    (30, (1, 25, 5, 64), 0x0000),
    (31, (1, 1, 1, 64), 0x2000),
    (33, (1, 1, 1, 12), 0x0000),
    (34, (1, 1, 1, 12), 0x2000),
)


class TfliteError(ValueError):
    """The managed input does not have the one frozen graph."""


class _Table:
    def __init__(self, image: bytes, position: int) -> None:
        self.image = image
        self.position = position
        self.vtable = position - struct.unpack_from("<i", image, position)[0]
        self.vtable_size = struct.unpack_from("<H", image, self.vtable)[0]

    def field(self, index: int) -> int | None:
        location = self.vtable + 4 + index * 2
        if location + 2 > self.vtable + self.vtable_size:
            return None
        offset = struct.unpack_from("<H", self.image, location)[0]
        return self.position + offset if offset != 0 else None

    def scalar(self, index: int, fmt: str, default: int | float = 0) -> int | float:
        location = self.field(index)
        return (
            default if location is None else struct.unpack_from("<" + fmt, self.image, location)[0]
        )

    def offset(self, index: int) -> int | None:
        location = self.field(index)
        if location is None:
            return None
        return location + struct.unpack_from("<I", self.image, location)[0]

    def vector(self, index: int, fmt: str) -> tuple[int | float, ...]:
        location = self.offset(index)
        if location is None:
            return ()
        length = struct.unpack_from("<I", self.image, location)[0]
        return struct.unpack_from("<" + fmt * length, self.image, location + 4)

    def tables(self, index: int) -> tuple["_Table", ...]:
        location = self.offset(index)
        if location is None:
            return ()
        length = struct.unpack_from("<I", self.image, location)[0]
        return tuple(
            _Table(
                self.image,
                location
                + 4
                + item * 4
                + struct.unpack_from("<I", self.image, location + 4 + item * 4)[0],
            )
            for item in range(length)
        )


@dataclass(frozen=True)
class _Tensor:
    shape: tuple[int, ...]
    kind: int
    buffer: bytes
    scales: tuple[float, ...]
    zero_points: tuple[int, ...]
    quantized_dimension: int
    scale_bits: int


@dataclass(frozen=True)
class _Operator:
    builtin: int
    inputs: tuple[int, ...]
    outputs: tuple[int, ...]
    options: _Table | None


def _require(condition: bool, message: str) -> None:
    if not condition:
        raise TfliteError(message)


def _root(image: bytes) -> _Table:
    _require(len(image) >= 8 and image[4:8] == b"TFL3", "not a TFLite v3 FlatBuffer")
    root = struct.unpack_from("<I", image, 0)[0]
    _require(root < len(image), "root offset")
    return _Table(image, root)


def _parse_tflite(image: bytes) -> tuple[tuple[_Tensor, ...], tuple[_Operator, ...]]:
    model = _root(image)
    operator_codes = tuple(int(code.scalar(0, "b")) for code in model.tables(1))
    subgraphs = model.tables(2)
    buffers = model.tables(4)
    _require(len(subgraphs) == 1, "subgraph count")
    raw_buffers = tuple(bytes(buffer.vector(0, "B")) for buffer in buffers)
    subgraph = subgraphs[0]
    tensors: list[_Tensor] = []
    for tensor in subgraph.tables(0):
        quantization = tensor.offset(4)
        quant = _Table(image, quantization) if quantization is not None else None
        scales = tuple(float(item) for item in quant.vector(2, "f")) if quant else ()
        zeroes = tuple(int(item) for item in quant.vector(3, "q")) if quant else ()
        buffer_index = int(tensor.scalar(2, "I"))
        _require(buffer_index < len(raw_buffers), "tensor buffer index")
        tensors.append(
            _Tensor(
                shape=tuple(int(item) for item in tensor.vector(0, "i")),
                kind=int(tensor.scalar(1, "b")),
                buffer=raw_buffers[buffer_index],
                scales=scales,
                zero_points=zeroes,
                quantized_dimension=int(quant.scalar(5, "i")) if quant else 0,
                scale_bits=struct.unpack("<I", struct.pack("<f", scales[0]))[0] if scales else 0,
            )
        )
    operators: list[_Operator] = []
    for operator in subgraph.tables(3):
        opcode_index = int(operator.scalar(0, "I"))
        _require(opcode_index < len(operator_codes), "operator-code index")
        options_offset = operator.offset(4)
        operators.append(
            _Operator(
                builtin=operator_codes[opcode_index],
                inputs=tuple(int(item) for item in operator.vector(1, "i")),
                outputs=tuple(int(item) for item in operator.vector(2, "i")),
                options=_Table(image, options_offset) if options_offset is not None else None,
            )
        )
    return tuple(tensors), tuple(operators)


def _q31_multiplier(value: float) -> tuple[int, int]:
    _require(value >= 0.0 and math.isfinite(value), "invalid effective quantization multiplier")
    fraction, shift = math.frexp(value)
    quantized = int(math.floor(fraction * (1 << 31) + 0.5))
    if quantized == (1 << 31):
        quantized //= 2
        shift += 1
    if shift < -31:
        return 0, 0
    _require(quantized <= 0x7FFFFFFF, "Q31 multiplier overflow")
    return quantized, shift


def _append_aligned(image: bytearray, cursor: int, values: bytes) -> tuple[int, int]:
    cursor = (cursor + 15) & ~15
    end = cursor + len(values)
    _require(end <= APUM_PARAMETER_END, "parameter image overflow")
    image[cursor:end] = values
    return cursor, end


def _expect_options(
    operator: _Operator, index: int
) -> tuple[int, int, int, int, tuple[int, int, int, int]]:
    _require(operator.options is not None, f"operator {index} options")
    options = operator.options
    if index == 9:
        # Pool2D: padding, stride_w, stride_h, filter_w, filter_h, activation.
        values = (
            int(options.scalar(0, "b")),
            int(options.scalar(1, "i")),
            int(options.scalar(2, "i")),
            int(options.scalar(3, "i")),
            int(options.scalar(4, "i")),
            int(options.scalar(5, "b")),
        )
        _require(values == (1, 5, 25, 5, 25, 0), "pool options")
        return 25, 5, 25, 5, (0, 0, 0, 0)
    if index == 10:
        _require(
            int(options.scalar(0, "b")) == 0 and int(options.scalar(1, "b")) == 0, "FC options"
        )
        return 1, 1, 1, 1, (0, 0, 0, 0)
    if index == 11:
        _require(
            struct.unpack("<I", struct.pack("<f", float(options.scalar(0, "f"))))[0] == 0x3F800000,
            "softmax beta",
        )
        return 1, 1, 1, 1, (0, 0, 0, 0)
    if index == 0:
        values = (
            int(options.scalar(0, "b")),
            int(options.scalar(1, "i")),
            int(options.scalar(2, "i")),
            int(options.scalar(3, "b")),
            int(options.scalar(4, "i", 1)),
            int(options.scalar(5, "i", 1)),
        )
        _require(values == (0, 2, 2, 1, 1, 1), "first convolution options")
        return 10, 4, 2, 2, (4, 5, 1, 1)
    if index in (1, 3, 5, 7):
        values = (
            int(options.scalar(0, "b")),
            int(options.scalar(1, "i")),
            int(options.scalar(2, "i")),
            int(options.scalar(3, "i")),
            int(options.scalar(4, "b")),
            int(options.scalar(5, "i", 1)),
            int(options.scalar(6, "i", 1)),
        )
        _require(values == (0, 1, 1, 1, 1, 1, 1), f"depthwise options {index}")
        return 3, 3, 1, 1, (1, 1, 1, 1)
    values = (
        int(options.scalar(0, "b")),
        int(options.scalar(1, "i")),
        int(options.scalar(2, "i")),
        int(options.scalar(3, "b")),
        int(options.scalar(4, "i", 1)),
        int(options.scalar(5, "i", 1)),
    )
    _require(values == (0, 1, 1, 1, 1, 1), f"pointwise options {index}")
    return 1, 1, 1, 1, (0, 0, 0, 0)


def _weighted_record(
    image: bytearray,
    cursor: int,
    tensors: tuple[_Tensor, ...],
    operator: _Operator,
    index: int,
    input_tensor: int,
    output_tensor: int,
) -> tuple[int, bytes]:
    _require(len(operator.inputs) == 3 and len(operator.outputs) == 1, f"operator {index} arity")
    source, weights, bias = (tensors[item] for item in operator.inputs)
    output = tensors[operator.outputs[0]]
    expected_output = _ACTIVATIONS[index][1] if index < 10 else _ACTIVATIONS[index][1]
    if index == 10:
        expected_output = (1, 1, 1, 12)
    _require(
        math.prod(output.shape) == math.prod(expected_output), f"operator {index} output shape"
    )
    _require(source.kind == 9 and weights.kind == 9 and bias.kind == 2, f"operator {index} types")
    _require(
        len(source.scales) == 1 and len(output.scales) == 1,
        f"operator {index} activation quantization",
    )
    channels = 12 if index == 10 else 64
    expected_scales = 1 if index == 10 else channels
    _require(
        len(weights.scales) == expected_scales and len(weights.zero_points) == expected_scales,
        f"operator {index} weight scales",
    )
    _require(
        len(bias.buffer) == channels * 4 and len(bias.scales) == expected_scales,
        f"operator {index} bias",
    )
    _require(
        all(value == 0 for value in weights.zero_points), f"operator {index} weight zero point"
    )
    weight_offset, cursor = _append_aligned(image, cursor, weights.buffer)
    bias_offset, cursor = _append_aligned(image, cursor, bias.buffer)
    multipliers: list[int] = []
    shifts: list[int] = []
    for channel in range(channels):
        weight_scale = weights.scales[0 if index == 10 else channel]
        multiplier, shift = _q31_multiplier(
            float(source.scales[0]) * float(weight_scale) / float(output.scales[0])
        )
        multipliers.append(multiplier)
        shifts.append(shift)
    multiplier_data = struct.pack("<" + "i" * channels, *multipliers)
    shift_data = struct.pack("<" + "i" * channels, *shifts)
    multiplier_offset, cursor = _append_aligned(image, cursor, multiplier_data)
    shift_offset, cursor = _append_aligned(image, cursor, shift_data)
    kernel_h, kernel_w, stride_h, stride_w, padding = _expect_options(operator, index)
    flags = 0 if index == 10 else 1
    record = struct.pack(
        "<HHHHIIIIIIHHHH4BiiiiI",
        _APUM_OPCODES[index],
        flags,
        input_tensor,
        output_tensor,
        weight_offset,
        bias_offset,
        multiplier_offset,
        shift_offset,
        len(weights.buffer),
        channels,
        kernel_h,
        kernel_w,
        stride_h,
        stride_w,
        *padding,
        source.zero_points[0],
        output.zero_points[0],
        -128,
        127,
        0,
    )
    return cursor, record + multiplier_data + shift_data


def import_tflite(model: Path) -> bytes:
    """Parse the exact frozen TFLite graph and return a strict APUM 1.0 image."""
    source = model.read_bytes()
    _require(hashlib.sha256(source).hexdigest() == TFLITE_SHA256, "unexpected TFLite SHA-256")
    tensors, operators = _parse_tflite(source)
    expected = (
        _OPERATOR_CODES["CONV_2D"],
        _OPERATOR_CODES["DEPTHWISE_CONV_2D"],
        _OPERATOR_CODES["CONV_2D"],
        _OPERATOR_CODES["DEPTHWISE_CONV_2D"],
        _OPERATOR_CODES["CONV_2D"],
        _OPERATOR_CODES["DEPTHWISE_CONV_2D"],
        _OPERATOR_CODES["CONV_2D"],
        _OPERATOR_CODES["DEPTHWISE_CONV_2D"],
        _OPERATOR_CODES["CONV_2D"],
        _OPERATOR_CODES["AVERAGE_POOL_2D"],
        _OPERATOR_CODES["RESHAPE"],
        _OPERATOR_CODES["FULLY_CONNECTED"],
        _OPERATOR_CODES["SOFTMAX"],
    )
    _require(tuple(operator.builtin for operator in operators) == expected, "operator graph")
    image = bytearray(APUM_BYTES)
    struct.pack_into(
        "<10I",
        image,
        0,
        APUM_MAGIC,
        APUM_ABI,
        APUM_BYTES,
        1,
        49 | (10 << 16),
        12 | (12 << 16),
        APUM_PARAMETER_END - APUM_PARAMETER_OFFSET,
        APUM_BYTES,
        1,
        0,
    )
    struct.pack_into("<Q", image, 0x28, 0xCE4F70006843EAAE)
    struct.pack_into("<I", image, 0x30, 128 | (3 << 8))
    struct.pack_into("<I", image, 0x34, 13)
    struct.pack_into("<I", image, 0x38, 1)
    activation_sources = (0,) + tuple(item[0] for item in _ACTIVATIONS)
    _require(len(activation_sources) == 13, "activation count")
    for index, source_index in enumerate(activation_sources):
        tensor = tensors[source_index]
        if index == 0:
            shape = (1, 49, 10, 1)
            scratch = 0x4000
        else:
            _, shape, scratch = _ACTIVATIONS[index - 1]
        _require(
            math.prod(tensor.shape) == math.prod(shape)
            and tensor.kind == 9
            and len(tensor.scales) == 1,
            f"tensor {index}",
        )
        struct.pack_into(
            "<HHHHIIIIiI",
            image,
            0x340 + index * 32,
            *shape,
            scratch,
            math.prod(shape),
            1,
            tensor.scale_bits,
            tensor.zero_points[0],
            0,
        )
    cursor = APUM_PARAMETER_OFFSET
    multiplier_shift = bytearray()
    source_ops = tuple(operators[index] for index in (*range(10), 11, 12))
    for index, operator in enumerate(source_ops):
        if index in (9, 11):
            kernel_h, kernel_w, stride_h, stride_w, padding = _expect_options(operator, index)
            flags = 0
            record = struct.pack(
                "<HHHHIIIIIIHHHH4BiiiiI",
                _APUM_OPCODES[index],
                flags,
                index,
                index + 1,
                0,
                0,
                0,
                0,
                0,
                64 if index == 9 else 12,
                kernel_h,
                kernel_w,
                stride_h,
                stride_w,
                *padding,
                tensors[activation_sources[index]].zero_points[0],
                tensors[activation_sources[index + 1]].zero_points[0],
                -128,
                127,
                0,
            )
        else:
            cursor, packed = _weighted_record(
                image, cursor, tensors, operator, index, index, index + 1
            )
            record, multiplier_data, shift_data = (
                packed[:64],
                packed[64 : 64 + (64 if index != 10 else 12) * 4],
                packed[64 + (64 if index != 10 else 12) * 4 :],
            )
            multiplier_shift.extend(multiplier_data)
            multiplier_shift.extend(shift_data)
        image[0x40 + index * 64 : 0x40 + (index + 1) * 64] = record
    _require(cursor == APUM_PARAMETER_END, "parameter size")
    _require(
        hashlib.sha256(image[APUM_PARAMETER_OFFSET:APUM_PARAMETER_END]).hexdigest()
        == APUM_PARAMS_SHA256,
        "frozen parameter hash",
    )
    _require(
        hashlib.sha256(multiplier_shift).hexdigest() == APUM_MULTIPLIER_SHIFT_SHA256,
        "frozen multiplier/shift hash",
    )
    struct.pack_into("<I", image, 0x24, crc32_iso_hdlc(image[APUM_HEADER_BYTES:]))
    _require(struct.unpack_from("<I", image, 0x24)[0] == APUM_PAYLOAD_CRC, "frozen payload CRC")
    _require(image_sha256(image) == APUM_SHA256, "frozen APUM SHA-256")
    return bytes(image)


def _git_identity(path: Path) -> dict[str, object]:
    root = path.resolve().parents[1]
    revision = subprocess.run(
        ["git", "-C", str(root), "rev-parse", "HEAD"], text=True, capture_output=True, check=False
    )
    dirty = subprocess.run(
        ["git", "-C", str(root), "status", "--porcelain"],
        text=True,
        capture_output=True,
        check=False,
    )
    return {
        "contract_revision": "apu-kws-convert/1.0.0",
        "git_revision": revision.stdout.strip() if revision.returncode == 0 else None,
        "git_dirty": bool(dirty.stdout.strip()),
        "source_sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--target", choices=("p7",), required=True)
    parser.add_argument("--model", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--manifest", type=Path, required=True)
    args = parser.parse_args()
    try:
        image = import_tflite(args.model)
        parse_apum(image)
    except (OSError, TfliteError, ValueError) as error:
        raise SystemExit(str(error)) from error
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(image)
    manifest = {
        **_git_identity(Path(__file__)),
        "target": args.target,
        "model": str(args.model.resolve()),
        "model_sha256": TFLITE_SHA256,
        "apum_sha256": image_sha256(image),
        "payload_crc": f"0x{APUM_PAYLOAD_CRC:08x}",
        "layout": apum_layout(image),
    }
    args.manifest.parent.mkdir(parents=True, exist_ok=True)
    args.manifest.write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    print(f"APUM image: {args.output} ({len(image)} bytes)")
    print(f"payload CRC: 0x{APUM_PAYLOAD_CRC:08x}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
