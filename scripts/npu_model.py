"""Independent TFLite flatbuffer reader and NPU workload model extraction."""

from __future__ import annotations

import hashlib
import struct
from dataclasses import dataclass
from enum import IntEnum
from pathlib import Path
from typing import Any, Final


class FlatbufferError(ValueError):
    """A buffer is not a well-formed TFLite v3 flatbuffer."""


class Padding(IntEnum):
    SAME = 0
    VALID = 1


class FusedActivation(IntEnum):
    NONE = 0
    RELU = 1
    RELU_N1_TO_1 = 2
    RELU6 = 3


OP_ADD: Final = 0
OP_AVERAGE_POOL_2D: Final = 1
OP_CONV_2D: Final = 3
OP_DEPTHWISE_CONV_2D: Final = 4
OP_FULLY_CONNECTED: Final = 9
OP_MAX_POOL_2D: Final = 17
OP_RELU: Final = 19
OP_RESHAPE: Final = 22
OP_SOFTMAX: Final = 25
OP_CUSTOM: Final = 32

BUILTIN_OP_NAMES: Final = {
    OP_ADD: "ADD",
    OP_AVERAGE_POOL_2D: "AVERAGE_POOL_2D",
    OP_CONV_2D: "CONV_2D",
    OP_DEPTHWISE_CONV_2D: "DEPTHWISE_CONV_2D",
    OP_FULLY_CONNECTED: "FULLY_CONNECTED",
    OP_MAX_POOL_2D: "MAX_POOL_2D",
    OP_RELU: "RELU",
    OP_RESHAPE: "RESHAPE",
    OP_SOFTMAX: "SOFTMAX",
    OP_CUSTOM: "CUSTOM",
}

TENSOR_TYPE_NAMES: Final = {
    0: "FLOAT32",
    1: "FLOAT16",
    2: "INT32",
    3: "UINT8",
    4: "INT64",
    5: "STRING",
    6: "BOOL",
    7: "INT16",
    8: "COMPLEX64",
    9: "INT8",
    10: "FLOAT64",
    11: "COMPLEX128",
    12: "UINT64",
    13: "RESOURCE",
    14: "VARIANT",
    15: "UINT32",
    16: "UINT16",
}

REPO_ROOT: Final = Path(__file__).resolve().parents[1]
_MLPERF_TINY: Final = REPO_ROOT / ".cache/retrosoc/sources/apu-mlperf-tiny/benchmark/training"
KWS_TFLITE_PATH: Final = _MLPERF_TINY / "keyword_spotting/trained_models/kws_ref_model.tflite"
VWW_TFLITE_PATH: Final = _MLPERF_TINY / "visual_wake_words/trained_models/vww_96_int8.tflite"
KWS_TFLITE_SHA256: Final = "aeea436800704fce17b17292e4412630ad856e9d777c044c64ef748a880bd0ae"
VWW_TFLITE_SHA256: Final = "597a384c8c2c8a1276f04702f25013b7838f2f814f1ca7c174d295b73e3d6b7b"


def _check(condition: bool, message: str) -> None:
    if not condition:
        raise FlatbufferError(message)


def builtin_op_name(opcode: int) -> str:
    return BUILTIN_OP_NAMES.get(opcode, f"UNKNOWN_{opcode}")


class _Cursor:
    """Bounds-checked read-only view of one flatbuffer table."""

    __slots__ = ("_image", "_base", "_vtable", "_vtable_size")

    def __init__(self, image: bytes, base: int) -> None:
        _check(0 <= base <= len(image) - 4, "table base outside the buffer")
        vtable = base - struct.unpack_from("<i", image, base)[0]
        _check(0 <= vtable <= len(image) - 4, "vtable outside the buffer")
        vtable_size = struct.unpack_from("<H", image, vtable)[0]
        _check(4 <= vtable_size <= len(image) - vtable, "vtable size outside the buffer")
        self._image = image
        self._base = base
        self._vtable = vtable
        self._vtable_size = vtable_size

    def _entry(self, field: int) -> int | None:
        slot = self._vtable + 4 + field * 2
        if slot + 2 > self._vtable + self._vtable_size:
            return None
        delta = struct.unpack_from("<H", self._image, slot)[0]
        if delta == 0:
            return None
        return self._base + delta

    def has(self, field: int) -> bool:
        return self._entry(field) is not None

    def scalar(self, field: int, fmt: str, default: int | float = 0) -> int | float:
        at = self._entry(field)
        if at is None:
            return default
        size = struct.calcsize("<" + fmt)
        _check(at + size <= len(self._image), "scalar field outside the buffer")
        return struct.unpack_from("<" + fmt, self._image, at)[0]

    def offset(self, field: int) -> int | None:
        at = self._entry(field)
        if at is None:
            return None
        _check(at + 4 <= len(self._image), "offset field outside the buffer")
        target = at + struct.unpack_from("<I", self._image, at)[0]
        _check(4 <= target <= len(self._image), "offset target outside the buffer")
        return target

    def child(self, field: int) -> _Cursor | None:
        target = self.offset(field)
        return None if target is None else _Cursor(self._image, target)

    def vector(self, field: int, fmt: str) -> tuple[int | float, ...]:
        target = self.offset(field)
        if target is None:
            return ()
        _check(target + 4 <= len(self._image), "vector length outside the buffer")
        count = struct.unpack_from("<I", self._image, target)[0]
        size = struct.calcsize("<" + fmt)
        _check(count * size <= len(self._image) - target - 4, "vector body outside the buffer")
        return struct.unpack_from(f"<{count}{fmt}", self._image, target + 4)

    def children(self, field: int) -> tuple[_Cursor, ...]:
        target = self.offset(field)
        if target is None:
            return ()
        _check(target + 4 <= len(self._image), "table vector length outside the buffer")
        count = struct.unpack_from("<I", self._image, target)[0]
        _check(count * 4 <= len(self._image) - target - 4, "table vector outside the buffer")
        return tuple(
            _Cursor(
                self._image,
                target + 4 + item * 4 + struct.unpack_from("<I", self._image, target + 4 + item * 4)[0],
            )
            for item in range(count)
        )

    def text(self, field: int) -> str:
        target = self.offset(field)
        if target is None:
            return ""
        _check(target + 4 <= len(self._image), "string length outside the buffer")
        length = struct.unpack_from("<I", self._image, target)[0]
        _check(length <= len(self._image) - target - 4, "string body outside the buffer")
        return self._image[target + 4 : target + 4 + length].decode("utf-8", "replace")


def _root(image: bytes) -> _Cursor:
    _check(len(image) >= 8, "buffer too small for a TFLite header")
    _check(image[4:8] == b"TFL3", "missing TFL3 file identifier")
    return _Cursor(image, struct.unpack_from("<I", image, 0)[0])


@dataclass(frozen=True)
class TensorInfo:
    name: str
    shape: tuple[int, ...]
    dtype: int
    scales: tuple[float, ...]
    zero_points: tuple[int, ...]
    quantized_dimension: int
    buffer_index: int
    data: bytes | None

    @property
    def dtype_name(self) -> str:
        return TENSOR_TYPE_NAMES.get(self.dtype, f"UNKNOWN_{self.dtype}")

    @property
    def per_channel(self) -> bool:
        return len(self.scales) > 1


@dataclass(frozen=True)
class OperatorInfo:
    opcode: int
    op_name: str
    inputs: tuple[int, ...]
    outputs: tuple[int, ...]
    options: dict[str, Any]


@dataclass(frozen=True)
class GraphInfo:
    tensors: tuple[TensorInfo, ...]
    operators: tuple[OperatorInfo, ...]
    inputs: tuple[int, ...]
    outputs: tuple[int, ...]


@dataclass(frozen=True)
class ModelInfo:
    version: int
    description: str
    operator_codes: tuple[int, ...]
    subgraphs: tuple[GraphInfo, ...]

    def main_graph(self) -> GraphInfo:
        _check(len(self.subgraphs) > 0, "model has no subgraphs")
        return self.subgraphs[0]


def _enum_name(kind: type[IntEnum], value: int) -> str:
    try:
        return kind(value).name
    except ValueError:
        return f"UNKNOWN_{value}"


def _read_options(opcode: int, table: _Cursor | None) -> dict[str, Any]:
    if table is None:
        return {}
    if opcode == OP_CONV_2D:
        return {
            "padding": _enum_name(Padding, int(table.scalar(0, "b"))),
            "stride_w": int(table.scalar(1, "i")),
            "stride_h": int(table.scalar(2, "i")),
            "fused_activation": _enum_name(FusedActivation, int(table.scalar(3, "b"))),
            "dilation_w": int(table.scalar(4, "i", 1)),
            "dilation_h": int(table.scalar(5, "i", 1)),
        }
    if opcode == OP_DEPTHWISE_CONV_2D:
        return {
            "padding": _enum_name(Padding, int(table.scalar(0, "b"))),
            "stride_w": int(table.scalar(1, "i")),
            "stride_h": int(table.scalar(2, "i")),
            "depth_multiplier": int(table.scalar(3, "i")),
            "fused_activation": _enum_name(FusedActivation, int(table.scalar(4, "b"))),
            "dilation_w": int(table.scalar(5, "i", 1)),
            "dilation_h": int(table.scalar(6, "i", 1)),
        }
    if opcode in (OP_AVERAGE_POOL_2D, OP_MAX_POOL_2D):
        return {
            "padding": _enum_name(Padding, int(table.scalar(0, "b"))),
            "stride_w": int(table.scalar(1, "i")),
            "stride_h": int(table.scalar(2, "i")),
            "filter_width": int(table.scalar(3, "i")),
            "filter_height": int(table.scalar(4, "i")),
            "fused_activation": _enum_name(FusedActivation, int(table.scalar(5, "b"))),
        }
    if opcode == OP_FULLY_CONNECTED:
        return {
            "fused_activation": _enum_name(FusedActivation, int(table.scalar(0, "b"))),
            "weights_format": int(table.scalar(1, "b")),
        }
    if opcode == OP_SOFTMAX:
        return {"beta": float(table.scalar(0, "f"))}
    if opcode == OP_RESHAPE:
        return {"new_shape": tuple(int(dim) for dim in table.vector(0, "i"))}
    if opcode == OP_ADD:
        return {"fused_activation": _enum_name(FusedActivation, int(table.scalar(0, "b")))}
    return {}


def _read_operator_code(code: _Cursor) -> int:
    if code.has(3):
        return int(code.scalar(3, "i"))
    return int(code.scalar(0, "b"))


def _read_tensor(tensor: _Cursor, buffers: tuple[bytes, ...]) -> TensorInfo:
    buffer_index = int(tensor.scalar(2, "I"))
    _check(buffer_index < len(buffers), "tensor buffer index out of range")
    quant = tensor.child(4)
    payload = buffers[buffer_index]
    return TensorInfo(
        name=tensor.text(3),
        shape=tuple(int(dim) for dim in tensor.vector(0, "i")),
        dtype=int(tensor.scalar(1, "b")),
        scales=tuple(float(item) for item in quant.vector(2, "f")) if quant else (),
        zero_points=tuple(int(item) for item in quant.vector(3, "q")) if quant else (),
        quantized_dimension=int(quant.scalar(6, "i")) if quant else 0,
        buffer_index=buffer_index,
        data=payload if payload else None,
    )


def _read_operator(operator: _Cursor, codes: tuple[int, ...]) -> OperatorInfo:
    opcode_index = int(operator.scalar(0, "I"))
    _check(opcode_index < len(codes), "operator-code index out of range")
    opcode = codes[opcode_index]
    return OperatorInfo(
        opcode=opcode,
        op_name=builtin_op_name(opcode),
        inputs=tuple(int(item) for item in operator.vector(1, "i")),
        outputs=tuple(int(item) for item in operator.vector(2, "i")),
        options=_read_options(opcode, operator.child(4)),
    )


def _read_graph(
    graph: _Cursor, codes: tuple[int, ...], buffers: tuple[bytes, ...]
) -> GraphInfo:
    return GraphInfo(
        tensors=tuple(_read_tensor(tensor, buffers) for tensor in graph.children(0)),
        operators=tuple(_read_operator(operator, codes) for operator in graph.children(3)),
        inputs=tuple(int(item) for item in graph.vector(1, "i")),
        outputs=tuple(int(item) for item in graph.vector(2, "i")),
    )


def parse_tflite(data: bytes) -> ModelInfo:
    """Parse raw TFLite v3 bytes into a ModelInfo, rejecting malformed input."""
    image = bytes(data)
    model = _root(image)
    operator_codes = tuple(_read_operator_code(code) for code in model.children(1))
    buffers = tuple(bytes(buffer.vector(0, "B")) for buffer in model.children(4))
    subgraphs = tuple(
        _read_graph(subgraph, operator_codes, buffers) for subgraph in model.children(2)
    )
    return ModelInfo(
        version=int(model.scalar(0, "I")),
        description=model.text(3),
        operator_codes=operator_codes,
        subgraphs=subgraphs,
    )


def load_model(path: str | Path, expected_sha256: str) -> ModelInfo:
    """Read a TFLite file, pin its SHA-256, and parse it."""
    candidate = Path(path)
    try:
        payload = candidate.read_bytes()
    except OSError as error:
        raise FlatbufferError(f"cannot read {candidate}: {error}") from error
    digest = hashlib.sha256(payload).hexdigest()
    if digest != expected_sha256:
        raise FlatbufferError(
            f"SHA-256 mismatch for {candidate.name}: got {digest}, expected {expected_sha256}"
        )
    return parse_tflite(payload)


def load_kws_model() -> ModelInfo:
    """Load the hash-pinned MLPerf Tiny keyword-spotting workload model."""
    return load_model(KWS_TFLITE_PATH, KWS_TFLITE_SHA256)


def load_vww_model() -> ModelInfo:
    """Load the hash-pinned MLPerf Tiny visual-wake-words workload model."""
    return load_model(VWW_TFLITE_PATH, VWW_TFLITE_SHA256)


def _tensor_summary(tensor: TensorInfo) -> dict[str, Any]:
    return {
        "name": tensor.name,
        "shape": list(tensor.shape),
        "dtype": tensor.dtype_name,
        "quantization": {
            "per_channel": tensor.per_channel,
            "scales": list(tensor.scales),
            "zero_points": list(tensor.zero_points),
            "quantized_dimension": tensor.quantized_dimension,
        },
        "buffer_bytes": len(tensor.data) if tensor.data is not None else 0,
    }


def graph_summary(graph: GraphInfo) -> dict[str, Any]:
    """Build a JSON-serializable per-operator summary of one graph."""
    tensors = graph.tensors

    def view(indices: tuple[int, ...]) -> list[dict[str, Any]]:
        return [_tensor_summary(tensors[item]) for item in indices if 0 <= item < len(tensors)]

    operators: list[dict[str, Any]] = []
    for index, operator in enumerate(graph.operators):
        constants = [
            tensors[item]
            for item in operator.inputs
            if 0 <= item < len(tensors) and tensors[item].data is not None
        ]
        operators.append(
            {
                "index": index,
                "op": operator.op_name,
                "opcode": operator.opcode,
                "inputs": view(operator.inputs),
                "outputs": view(operator.outputs),
                "options": dict(operator.options),
                "constants": [
                    {"name": item.name, "bytes": len(item.data)} for item in constants
                ],
            }
        )
    return {
        "inputs": view(graph.inputs),
        "outputs": view(graph.outputs),
        "operators": operators,
    }
