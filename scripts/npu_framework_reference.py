"""Independent locked TFLite integer-kernel oracle; host verification only.

Only the raw model reader is shared with compilation. Quantization, geometry,
unpacked model weights and graph execution do not use NPU lowering or numerics.
"""
from __future__ import annotations

import hashlib
import json
import shutil
import struct
import subprocess
import time
from pathlib import Path

from npu_model import GraphInfo

ROOT = Path(__file__).resolve().parents[1]
SOURCES = ("apu_tensorflow", "apu_gemmlowp")


class OracleError(RuntimeError):
    """Missing/stale oracle input or failed framework execution."""


def checked_sources() -> dict[str, Path]:
    lock = json.loads((ROOT / "dependencies/dependencies.lock.json").read_text())
    result = {}
    for name in SOURCES:
        spec = lock["sources"][name]
        path = ROOT / spec["destination"]
        try:
            revision = subprocess.check_output(
                ["git", "-C", str(path), "rev-parse", "HEAD"], text=True,
                stderr=subprocess.PIPE,
            ).strip()
            dirty = subprocess.check_output(
                ["git", "-C", str(path), "status", "--porcelain"], text=True,
                stderr=subprocess.PIPE,
            ).strip()
        except (OSError, subprocess.CalledProcessError) as error:
            raise OracleError(f"missing locked oracle source: {name}") from error
        if revision != spec["revision"] or dirty:
            raise OracleError(f"stale or dirty locked oracle source: {name}")
        result[name] = path
    return result


def build_oracle(directory: Path, cxx: str = "g++") -> tuple[Path, dict]:
    sources = checked_sources()
    compiler = shutil.which(cxx)
    if compiler is None:
        raise OracleError(f"missing host C++ compiler: {cxx}")
    directory.mkdir(parents=True, exist_ok=True)
    adapter = ROOT / "tests/cpp/npu_framework_reference.cc"
    quant = sources["apu_tensorflow"] / "tensorflow/lite/kernels/internal/quantization_util.cc"
    executable = directory / "npu_framework_reference"
    command = [compiler, "-std=c++11", "-O2", "-ffp-contract=off",
               *(f"-I{path}" for path in sources.values()), str(adapter), str(quant),
               "-o", str(executable)]
    completed = subprocess.run(command, capture_output=True, text=True, check=False)
    (directory / "compile.log").write_text(completed.stdout + completed.stderr)
    if completed.returncode:
        raise OracleError(f"framework oracle compilation failed: {directory / 'compile.log'}")
    lock = json.loads((ROOT / "dependencies/dependencies.lock.json").read_text())
    evidence = {
        "command": command,
        "compiler_version": subprocess.check_output([compiler, "--version"], text=True),
        "sources": {name: lock["sources"][name]["revision"] for name in SOURCES},
        "adapter_sha256": hashlib.sha256(adapter.read_bytes()).hexdigest(),
        "binary_sha256": hashlib.sha256(executable.read_bytes()).hexdigest(),
        "shared_boundary": "raw npu_model parser only; no shared lowering or arithmetic",
    }
    (directory / "build.json").write_text(json.dumps(evidence, indent=2, sort_keys=True) + "\n")
    return executable, evidence


def encode_graph(graph: GraphInfo) -> bytes:
    """Encode raw, unpacked TFLite graph metadata for the host adapter."""
    data = bytearray(b"NPM1")

    def u32(value):
        data.extend(struct.pack("<I", value))

    def indices(values):
        u32(len(values))
        for value in values:
            u32(value)

    u32(len(graph.tensors))
    for tensor in graph.tensors:
        indices(tensor.shape)
        u32(tensor.dtype)
        u32(len(tensor.scales))
        for value in tensor.scales:
            data.extend(struct.pack("<d", value))
        u32(len(tensor.zero_points))
        for value in tensor.zero_points:
            data.extend(struct.pack("<i", value))
        raw = tensor.data or b""
        u32(len(raw))
        data.extend(raw)
    indices(graph.inputs)
    u32(len(graph.operators))
    for op in graph.operators:
        u32(op.opcode)
        indices(op.inputs)
        indices(op.outputs)
        o = op.options
        values = [
            {"SAME": 0, "VALID": 1}[o.get("padding", "VALID")],
            o.get("stride_h", 1), o.get("stride_w", 1),
            o.get("dilation_h", 1), o.get("dilation_w", 1),
            o.get("depth_multiplier", 1),
            o.get("filter_height", 1), o.get("filter_width", 1),
            {"NONE": 0, "RELU": 1, "RELU6": 3}[o.get("fused_activation", "NONE")],
        ]
        data.extend(struct.pack("<9id", *values, o.get("beta", 1.0)))
    return bytes(data)


def decode_outputs(graph: GraphInfo, blob: bytes) -> list[bytes]:
    ops = [op for op in graph.operators if op.op_name != "RESHAPE"]
    if len(blob) < 8 or blob[:4] != b"NPO1" or struct.unpack_from("<I", blob, 4)[0] != len(ops):
        raise OracleError("invalid/truncated framework output header")
    cursor = 8
    layers = []
    for op in ops:
        if cursor + 8 > len(blob):
            raise OracleError("truncated framework layer header")
        index, size = struct.unpack_from("<II", blob, cursor)
        cursor += 8
        expected = 1
        for dim in graph.tensors[op.outputs[0]].shape:
            expected *= dim
        if index != op.outputs[0] or size != expected or cursor + size > len(blob):
            raise OracleError("framework tensor identity/length mismatch")
        layers.append(blob[cursor:cursor + size])
        cursor += size
    if cursor != len(blob):
        raise OracleError("unexpected trailing framework output")
    return layers


class FrameworkOracle:
    def __init__(self, graph: GraphInfo, executable: Path, directory: Path):
        self.graph = graph
        self.executable = executable.resolve()
        self.directory = directory.resolve()
        self.directory.mkdir(parents=True, exist_ok=True)
        self.model = self.directory / "raw-model.bin"
        self.model.write_bytes(encode_graph(graph))

    def evaluate(self, image: bytes, case: str) -> list[bytes]:
        if Path(case).name != case or case in ("", ".", ".."):
            raise OracleError("invalid oracle case identifier")
        folder = self.directory / case
        folder.mkdir(exist_ok=True)
        inp, out = folder / "input.bin", folder / "layers.bin"
        inp.write_bytes(image)
        command = [str(self.executable), str(self.model), str(inp), str(out)]
        started = time.monotonic()
        try:
            completed = subprocess.run(command, capture_output=True, timeout=120, check=False)
        except (OSError, subprocess.TimeoutExpired) as error:
            raise OracleError(f"framework execution unavailable: {case}: {error}") from error
        (folder / "oracle.log").write_bytes(completed.stdout + completed.stderr)
        (folder / "run.json").write_text(json.dumps({
            "command": command, "returncode": completed.returncode,
            "duration_seconds": time.monotonic() - started,
            "model_sha256": hashlib.sha256(self.model.read_bytes()).hexdigest(),
        }, indent=2, sort_keys=True) + "\n")
        if completed.returncode:
            raise OracleError(f"framework execution failed: {case}: {completed.stderr.decode()}")
        return decode_outputs(self.graph, out.read_bytes())
