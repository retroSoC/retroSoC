"""Locked NPU-P0 TFLite workload reader tests."""

from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path

import pytest


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

from npu_model import (  # noqa: E402
    KWS_TFLITE_PATH,
    KWS_TFLITE_SHA256,
    VWW_TFLITE_PATH,
    VWW_TFLITE_SHA256,
    FlatbufferError,
    graph_summary,
    load_kws_model,
    load_model,
    load_vww_model,
    parse_tflite,
)

KWS_MODEL = KWS_TFLITE_PATH
VWW_MODEL = VWW_TFLITE_PATH

_KWS_SEQUENCE = (
    ["CONV_2D"]
    + ["DEPTHWISE_CONV_2D", "CONV_2D"] * 4
    + ["AVERAGE_POOL_2D", "RESHAPE", "FULLY_CONNECTED", "SOFTMAX"]
)
_VWW_SEQUENCE = (
    ["CONV_2D"]
    + ["DEPTHWISE_CONV_2D", "CONV_2D"] * 13
    + ["AVERAGE_POOL_2D", "RESHAPE", "FULLY_CONNECTED", "SOFTMAX"]
)


def test_npu_p0_kws_locked_model_graph_matches_pin() -> None:
    if not KWS_MODEL.is_file():
        pytest.skip("locked NPU workload models were not installed")
    image = KWS_MODEL.read_bytes()

    assert len(image) == 53936
    assert hashlib.sha256(image).hexdigest() == KWS_TFLITE_SHA256

    model = load_kws_model()
    assert model.version == 3
    assert len(model.subgraphs) == 1
    assert model.operator_codes == (3, 4, 1, 22, 9, 25)
    graph = model.main_graph()

    assert [operator.op_name for operator in graph.operators] == _KWS_SEQUENCE

    assert graph.inputs == (0,)
    source = graph.tensors[graph.inputs[0]]
    assert source.shape == (1, 49, 10, 1)
    assert source.dtype_name == "INT8"
    assert source.zero_points == (83,)
    assert source.scales[0] == pytest.approx(0.5847029, rel=1e-6)

    convs = [op for op in graph.operators if op.op_name == "CONV_2D"]
    depthwise = [op for op in graph.operators if op.op_name == "DEPTHWISE_CONV_2D"]
    assert len(convs) == 5
    assert len(depthwise) == 4
    for operator in convs + depthwise:
        weights = graph.tensors[operator.inputs[1]]
        bias = graph.tensors[operator.inputs[2]]
        assert weights.per_channel
        assert len(weights.scales) == 64
        assert len(weights.zero_points) == 64
        assert bias.dtype_name == "INT32"
        assert len(bias.scales) == 64
        expected_dim = 0 if operator.op_name == "CONV_2D" else 3
        assert weights.quantized_dimension == expected_dim
    assert [graph.tensors[op.inputs[1]].shape for op in convs] == [
        (64, 10, 4, 1),
        (64, 1, 1, 64),
        (64, 1, 1, 64),
        (64, 1, 1, 64),
        (64, 1, 1, 64),
    ]
    assert convs[0].options == {
        "padding": "SAME",
        "stride_w": 2,
        "stride_h": 2,
        "fused_activation": "RELU",
        "dilation_w": 1,
        "dilation_h": 1,
    }
    assert depthwise[0].options["depth_multiplier"] == 1

    pooling = graph.operators[9]
    assert pooling.options == {
        "padding": "VALID",
        "stride_w": 5,
        "stride_h": 25,
        "filter_width": 5,
        "filter_height": 25,
        "fused_activation": "NONE",
    }

    dense = graph.operators[11]
    assert graph.tensors[dense.outputs[0]].shape == (1, 12)
    assert graph.tensors[dense.outputs[0]].zero_points == (14,)

    assert graph.outputs == (34,)
    result = graph.tensors[graph.outputs[0]]
    assert result.shape == (1, 12)
    assert result.zero_points == (-128,)
    assert result.scales[0] == pytest.approx(1.0 / 256.0)


def test_npu_p0_vww_locked_model_graph_matches_pin() -> None:
    if not VWW_MODEL.is_file():
        pytest.skip("locked NPU workload models were not installed")
    image = VWW_MODEL.read_bytes()

    assert len(image) == 333288
    assert hashlib.sha256(image).hexdigest() == VWW_TFLITE_SHA256

    model = load_vww_model()
    assert model.version == 3
    assert model.operator_codes == (3, 4, 1, 22, 9, 25, 114, 6)
    graph = model.main_graph()

    assert [operator.op_name for operator in graph.operators] == _VWW_SEQUENCE
    assert {operator.opcode for operator in graph.operators} <= {1, 3, 4, 9, 22, 25}

    source = graph.tensors[graph.inputs[0]]
    assert source.shape == (1, 96, 96, 3)
    assert source.dtype_name == "INT8"
    assert source.zero_points == (-128,)
    assert source.scales[0] == pytest.approx(1.0 / 255.0, rel=1e-6)

    convs = [op for op in graph.operators if op.op_name == "CONV_2D"]
    depthwise = [op for op in graph.operators if op.op_name == "DEPTHWISE_CONV_2D"]
    assert len(convs) == 14
    assert len(depthwise) == 13
    for operator in convs:
        weights = graph.tensors[operator.inputs[1]]
        assert weights.per_channel
        assert len(weights.scales) == weights.shape[0]
        assert weights.quantized_dimension == 0
    for operator in depthwise:
        weights = graph.tensors[operator.inputs[1]]
        assert weights.per_channel
        assert len(weights.scales) == weights.shape[3]
        assert weights.quantized_dimension == 3

    pooling = graph.operators[27]
    assert pooling.options == {
        "padding": "VALID",
        "stride_w": 3,
        "stride_h": 3,
        "filter_width": 3,
        "filter_height": 3,
        "fused_activation": "NONE",
    }

    assert graph.outputs == (88,)
    result = graph.tensors[graph.outputs[0]]
    assert result.shape == (1, 2)
    assert result.zero_points == (-128,)
    assert result.scales[0] == pytest.approx(1.0 / 256.0)
    logits = graph.tensors[graph.operators[29].outputs[0]]
    assert logits.shape == (1, 2)
    assert logits.zero_points == (-5,)


def test_npu_p0_load_model_rejects_mutated_copy(tmp_path: Path) -> None:
    if not KWS_MODEL.is_file():
        pytest.skip("locked NPU workload models were not installed")
    mutated = tmp_path / "mutated-kws.tflite"
    data = bytearray(KWS_MODEL.read_bytes())
    data[-1] ^= 1
    mutated.write_bytes(data)

    with pytest.raises(FlatbufferError, match="SHA-256"):
        load_model(mutated, KWS_TFLITE_SHA256)


@pytest.mark.parametrize(
    "blob",
    [
        b"",
        b"tflite?",
        b"\x00" * 64,
        b"\x18\x00\x00\x00TFL3" + b"\xff" * 8,
        b"\x04\x00\x00\x00TFL3" + b"\x00" * 60,
    ],
)
def test_npu_p0_parse_rejects_malformed_buffers(blob: bytes) -> None:
    with pytest.raises(FlatbufferError):
        parse_tflite(blob)


def test_npu_p0_parse_rejects_truncated_model() -> None:
    if not KWS_MODEL.is_file():
        pytest.skip("locked NPU workload models were not installed")
    with pytest.raises(FlatbufferError):
        parse_tflite(KWS_MODEL.read_bytes()[:1024])


def test_npu_p0_graph_summary_is_json_serializable() -> None:
    if not KWS_MODEL.is_file() or not VWW_MODEL.is_file():
        pytest.skip("locked NPU workload models were not installed")
    kws = graph_summary(load_kws_model().main_graph())
    vww = graph_summary(load_vww_model().main_graph())

    assert json.loads(json.dumps(kws))["operators"][0]["op"] == "CONV_2D"
    assert json.loads(json.dumps(vww))["operators"][-1]["op"] == "SOFTMAX"

    assert len(kws["operators"]) == 13
    assert len(vww["operators"]) == 31
    assert kws["inputs"][0]["shape"] == [1, 49, 10, 1]
    assert vww["inputs"][0]["shape"] == [1, 96, 96, 3]
    first = kws["operators"][0]
    assert first["constants"] == [
        {"name": "functional_1/conv2d/Conv2D", "bytes": 2560},
        {
            "name": "functional_1/activation/Relu;functional_1/batch_normalization/FusedBatchNormV3;"
            "functional_1/conv2d/BiasAdd/ReadVariableOp/resource;functional_1/conv2d/BiasAdd;"
            "functional_1/conv2d_4/Conv2D;functional_1/conv2d/Conv2D",
            "bytes": 256,
        },
    ]
    assert first["outputs"][0]["quantization"]["per_channel"] is False
    assert first["inputs"][1]["quantization"]["per_channel"] is True
