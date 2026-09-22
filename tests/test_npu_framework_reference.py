"""Independent pinned-kernel Softmax and whole-model numerical regressions."""
from __future__ import annotations

import dataclasses
import hashlib
import random
import struct
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

from npu_framework_reference import (  # noqa: E402
    FrameworkOracle, OracleError, build_oracle, decode_outputs,
)
from npu_model import GraphInfo, OperatorInfo, TensorInfo, load_kws_model, load_vww_model  # noqa: E402
from npu_reference import Tensor, softmax_int8, softmax_parameters  # noqa: E402
from npu_compiler_p0 import (  # noqa: E402
    compile_model, compile_kws, compile_vww, evaluate_reference, CompilerError,
    KWS_CORPUS_FIRST, VWW_CORPUS_FIRST, vww_input_bytes, serialize_descriptors,
)
from npu_executor import execute_job, ExecutorFault, FAULT_DESCRIPTOR  # noqa: E402
from qualify_npu_p0 import compare_layers  # noqa: E402


KWS_SCALE = 0.14469251036643982
VWW_SCALE = 0.014636218547821045


def softmax_graph(shape, scale, beta=1.0):
    tensors = (
        TensorInfo("logits", shape, 9, (scale,), (0,), 0, 0, None),
        TensorInfo("output", shape, 9, (1 / 256,), (-128,), 0, 0, None),
    )
    return GraphInfo(tensors, (OperatorInfo(25, "SOFTMAX", (0,), (1,), {"beta": beta}),), (0,), (1,))


@pytest.fixture(scope="module")
def executable(tmp_path_factory):
    return build_oracle(tmp_path_factory.mktemp("npu-framework"))[0]


@pytest.mark.parametrize("scale,expected", [
    (KWS_SCALE, (1242899200, 24, -124)),
    (VWW_SCALE, (2011586560, 20, -1984)),
])
def test_model_specific_parameters(scale, expected):
    assert tuple(softmax_parameters(scale, 1.0).values()) == expected


@pytest.mark.parametrize("value", [float("nan"), float("inf"), 0.0, -1.0, True])
def test_bad_softmax_scale_beta(value):
    with pytest.raises(ValueError):
        softmax_parameters(value, 1.0)
    with pytest.raises(ValueError):
        softmax_parameters(0.1, value)


def test_parameter_safety_and_no_default():
    logits = Tensor((1, 1, 2), (-128, 127), VWW_SCALE, 0)
    with pytest.raises(TypeError):
        softmax_int8(logits)
    with pytest.raises(ValueError):
        softmax_parameters(1e-20, 1.0)
    for shift, cutoff in ((-1, 0), (32, 0), (24, -125), (20, -1985)):
        with pytest.raises(ValueError):
            softmax_int8(logits, input_multiplier=1242899200,
                         input_left_shift=shift, diff_min=cutoff)


def test_all_vww_two_class_inputs(executable, tmp_path):
    values = tuple(v for a in range(-128, 128) for b in range(-128, 128) for v in (a, b))
    graph = softmax_graph((1, 256, 256, 2), VWW_SCALE)
    golden = FrameworkOracle(graph, executable, tmp_path).evaluate(
        bytes(v & 255 for v in values), "exhaustive"
    )[0]
    actual = softmax_int8(Tensor((256, 256, 2), values, VWW_SCALE, 0),
                          **softmax_parameters(VWW_SCALE, 1.0))
    assert bytes(v & 255 for v in actual.data) == golden
    for pair, expected in (((0, 10), (-9, 9)), ((-114, 115), (-119, 119)),
                           ((-128, 127), (-122, 122))):
        offset = ((pair[0] + 128) * 256 + pair[1] + 128) * 2
        assert actual.data[offset:offset + 2] == expected


def test_kws_vectors_and_cutoff(executable, tmp_path):
    rng = random.Random(0x4E505530)
    rows = [(7,) * 12, (0, -124, -125, -128, -1, -123, 0, -40, -20, -60, -80, -100)]
    rows += [tuple(rng.randrange(-128, 128) for _ in range(12)) for _ in range(254)]
    values = tuple(v for row in rows for v in row)
    graph = softmax_graph((1, 16, 16, 12), KWS_SCALE)
    expected = FrameworkOracle(graph, executable, tmp_path).evaluate(
        bytes(v & 255 for v in values), "kws-seed-4e505530"
    )[0]
    actual = softmax_int8(Tensor((16, 16, 12), values, KWS_SCALE, 0),
                          **softmax_parameters(KWS_SCALE, 1.0))
    assert bytes(v & 255 for v in actual.data) == expected


@pytest.mark.parametrize("workload", ["kws", "vww"])
def test_actual_model_three_way(executable, tmp_path, workload):
    if workload == "kws":
        graph, job, image = load_kws_model().main_graph(), compile_kws(), KWS_CORPUS_FIRST.read_bytes()
    else:
        graph, job = load_vww_model().main_graph(), compile_vww()
        image = vww_input_bytes(VWW_CORPUS_FIRST.read_bytes())
    expected = FrameworkOracle(graph, executable, tmp_path).evaluate(image, workload)
    result = execute_job(job, image)
    reference = evaluate_reference(graph, image)
    assert compare_layers([bytes(v & 255 for v in t.data) for t in result.layers],
                          [bytes(v & 255 for v in t.data) for t in reference], expected) == []
    params = softmax_parameters(graph.tensors[graph.operators[-1].inputs[0]].scales[0], 1.0)
    assert all(job.steps[-1][k] == v for k, v in params.items())
    if workload == "vww":
        assert result.layers[-2].data == (-114, 115)
        assert result.output.data == (-119, 119)
        logits = result.layers[-2]
        wrong = softmax_int8(logits, **softmax_parameters(KWS_SCALE, 1.0))
        assert bytes(v & 255 for v in wrong.data) != expected[-1]
        bad_step = {**job.steps[-1], **softmax_parameters(KWS_SCALE, 1.0)}
        bad_result = execute_job(dataclasses.replace(job, steps=[job.steps[0], bad_step]), image)
        findings = compare_layers([bytes(v & 255 for v in t.data) for t in bad_result.layers],
                                  [bytes(v & 255 for v in t.data) for t in reference], expected)
        assert len(findings) == 1
        assert findings[0]["layer"] == 29 and findings[0]["path"] == "executor"


def test_compiler_softmax_validation():
    graph = softmax_graph((1, 2), VWW_SCALE)
    for value in (float("nan"), float("inf"), 0.0, -1.0):
        broken = dataclasses.replace(graph, operators=(dataclasses.replace(
            graph.operators[0], options={"beta": value}),))
        with pytest.raises(CompilerError, match="operator 0.*SOFTMAX"):
            compile_model(broken, workload="invalid")
    for output in (dataclasses.replace(graph.tensors[1], scales=(0.1,)),
                   dataclasses.replace(graph.tensors[1], zero_points=(0,)),
                   dataclasses.replace(graph.tensors[1], shape=(1, 3))):
        with pytest.raises(CompilerError, match="operator 0.*SOFTMAX"):
            compile_model(dataclasses.replace(graph, tensors=(graph.tensors[0], output)),
                          workload="invalid")


def test_executor_rejects_missing_and_unsafe_step():
    # A two-element FC keeps each negative test independent and inexpensive.
    graph = softmax_graph((1, 2), VWW_SCALE)
    tensors = (graph.tensors[0],
               TensorInfo("weights", (2, 2), 9, (0.1,), (0,), 0, 0, bytes((1, 0, 0, 1))),
               TensorInfo("bias", (2,), 2, (VWW_SCALE * 0.1,), (0,), 0, 0, bytes(8)),
               graph.tensors[0], graph.tensors[1])
    ops = (OperatorInfo(9, "FULLY_CONNECTED", (0, 1, 2), (3,), {"fused_activation": "NONE"}),
           OperatorInfo(25, "SOFTMAX", (3,), (4,), {"beta": 1.0}))
    job = compile_model(GraphInfo(tensors, ops, (0,), (4,)), workload="synthetic")
    for key in ("input_multiplier", "input_left_shift", "diff_min"):
        bad = dict(job.steps[-1])
        del bad[key]
        with pytest.raises(ExecutorFault) as caught:
            execute_job(dataclasses.replace(job, steps=[job.steps[0], bad]), bytes((0, 10)))
        assert caught.value.code == FAULT_DESCRIPTOR
    bad = {**job.steps[-1], "input_left_shift": 32}
    with pytest.raises(ExecutorFault) as caught:
        execute_job(dataclasses.replace(job, steps=[job.steps[0], bad]), bytes((0, 10)))
    assert caught.value.code == FAULT_DESCRIPTOR


def test_hardware_artifacts_unchanged():
    # Pre-repair P0 artifact digests; Softmax lives only in the host execution plan.
    expected = {
        "kws": ("5b96b55919129c7d2be25b1831ccc5dd40496d11be11b080347bf884f32901d6",
                "0348b356f552e00e42458abcd7d41f9a4c31cb603f77e15739c360a3faf862a3",
                "49bf0ed030d9cb990e3f3ebc5e887d17415aee8417df1633dc8c472c8c755341"),
        "vww": ("9bddef9acf59ce9eb1df0f6bcce58e86883f0b34ab755ddceed26e898586c7ef",
                "d35eed59a3b08b5bb3fee2c9b5f6a349790f9d2d09cfbe5b6abd0bbef36a05b6",
                "2df295f905b45838415e40fd5cf8f2ecc43f6d5f7a1d733b0a36ee7e797eb151"),
    }
    for name, compile in (("kws", compile_kws), ("vww", compile_vww)):
        job = compile()
        assert tuple(hashlib.sha256(blob).hexdigest() for blob in
                     (serialize_descriptors(job), job.weights, job.params)) == expected[name]


def test_output_protocol_rejects_truncation_and_trailing_bytes():
    graph = softmax_graph((1, 2), VWW_SCALE)
    valid = b"NPO1" + struct.pack("<III", 1, 1, 2) + bytes((0, 0))
    assert decode_outputs(graph, valid) == [bytes((0, 0))]
    for blob in (valid[:-1], valid + b"x", b"", b"bad!"):
        with pytest.raises(OracleError):
            decode_outputs(graph, blob)


def test_oracle_nonzero_exit_and_missing_executable(executable, tmp_path):
    graph = softmax_graph((1, 2), VWW_SCALE)
    oracle = FrameworkOracle(graph, executable, tmp_path)
    with pytest.raises(OracleError, match="execution failed"):
        oracle.evaluate(b"x", "wrong-size")
    oracle.executable = tmp_path / "absent"
    with pytest.raises(OracleError, match="unavailable"):
        oracle.evaluate(b"xx", "missing")
