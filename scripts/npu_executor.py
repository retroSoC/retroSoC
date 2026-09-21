"""Compiled-job functional executor for Mini NPU descriptor ABI 1.0 (NPU-P0).

Runs a CompiledJob (scripts/npu_compiler_p0.py) over byte regions with
arithmetic identical to scripts/npu_reference.py: tile iteration (TILE_H x
TILE_W row-major output positions, shortened at edges), output-channel groups
of eight with tail lanes, K-slice chunking (bias added once before the first
slice, partial sums carried across slices, requantization only after the full
reduction), dense A[k][8]/W[k][8] lane semantics (masked tail lanes carry
zero weights / input-zero activations and never affect results), depthwise
eight channel lanes, GLOBAL_AVERAGE_POOL count=H*W ties-away, and the
explicit terminal CPU softmax step. Opcode 4 ADD is executed end to end even
though the two locked models do not use it; pool/CLAMP opcodes are defined
by the ABI but are not placed by the P0 compiler and fault UNSUPPORTED here.

Address map: physical addresses are decoded through region bases and sizes
("arena", "weights", "params"); the descriptor array base ("descriptors") is
used for validation only. DEFAULT_BASES documents the aligned test map:
arena 0x1000_0000, weights 0x2000_0000, params 0x3000_0000, descriptors
0x4000_0000. Unmapped or region-crossing accesses raise
ExecutorFault(FAULT_RANGE); DescriptorError failures are re-raised as
ExecutorFault with the same code; checked INT32 overflow surfaces as
ExecutorFault(FAULT_ARITHMETIC).
"""

from __future__ import annotations

import hashlib
import struct
from dataclasses import dataclass
from typing import Final

from npu_descriptors import (
    DESCRIPTOR_BYTES,
    FAULT_DESCRIPTOR,
    FAULT_RANGE,
    FAULT_UNSUPPORTED,
    OP_ADD,
    OP_AVERAGE_POOL,
    OP_CLAMP,
    OP_CONV2D,
    OP_DEPTHWISE3X3,
    OP_FULLY_CONNECTED,
    OP_GLOBAL_AVERAGE_POOL,
    OP_MAX_POOL,
    Descriptor,
    DescriptorError,
    used_span,
    validate_descriptor,
)
from npu_reference import (
    INT32_MAX,
    INT32_MIN,
    ArithmeticFault,
    Tensor,
    average_pool,
    clamp,
    max_pool,
    multiply_by_quantized_multiplier,
    softmax_int8,
)

FAULT_ARITHMETIC: Final = 7

DEFAULT_BASES: Final = {
    "arena": 0x1000_0000,
    "weights": 0x2000_0000,
    "params": 0x3000_0000,
    "descriptors": 0x4000_0000,
}

_RELOCATION_WORDS: Final = {
    2: "input0_base",
    3: "input1_base",
    4: "output_base",
    5: "param_base",
    24: "weight_base",
}

ADD_LEFT_SHIFT: Final = 20
_UINT32_MODULUS: Final = 1 << 32


class ExecutorFault(Exception):
    """Execution failure carrying a spec FAULT_CODE (1/2/3/7)."""

    def __init__(self, code: int, message: str) -> None:
        super().__init__(message)
        self.code = code


@dataclass
class ExecutionResult:
    """Per-layer tensors (descriptors in order, then the CPU softmax), their
    raw-byte SHA-256 digests, and the final output tensor."""

    layers: list[Tensor]
    digests: list[str]
    output: Tensor


def _signed(block: bytes) -> list[int]:
    return [value - 256 if value >= 128 else value for value in block]


class _Memory:
    """Region-based address decoder; unmapped/crossing accesses fault RANGE."""

    def __init__(self, regions: dict[str, tuple[int, bytearray]]) -> None:
        self._regions = regions

    def _locate(self, address: int, size: int) -> tuple[bytearray, int]:
        for base, buffer in self._regions.values():
            if base <= address and address + size <= base + len(buffer):
                return buffer, address - base
        raise ExecutorFault(
            FAULT_RANGE,
            f"access at 0x{address:08x} ({size} bytes) is unmapped or crosses a region",
        )

    def read(self, address: int, size: int) -> bytes:
        if size == 0:
            return b""
        buffer, offset = self._locate(address, size)
        return bytes(buffer[offset : offset + size])

    def write(self, address: int, payload: bytes) -> None:
        if not payload:
            return
        buffer, offset = self._locate(address, len(payload))
        buffer[offset : offset + len(payload)] = payload


def relocate_descriptors(job, bases: dict[str, int]) -> list[Descriptor]:
    """Finalize templates: add region bases to address words, checked arithmetic."""
    relocated = [Descriptor(**vars(desc)) for desc in job.descriptors]
    for relocation in job.relocations:
        index = relocation["descriptor_index"]
        word = relocation["word_index"]
        region = relocation["region"]
        offset = relocation["offset"]
        field = _RELOCATION_WORDS.get(word)
        if field is None:
            raise ExecutorFault(FAULT_DESCRIPTOR, f"relocation targets word {word}")
        if not 0 <= index < len(relocated):
            raise ExecutorFault(FAULT_DESCRIPTOR, f"relocation descriptor {index} out of range")
        if region not in bases:
            raise ExecutorFault(FAULT_RANGE, f"relocation region {region!r} has no base")
        if getattr(relocated[index], field) != offset:
            raise ExecutorFault(
                FAULT_DESCRIPTOR, "relocation offset does not match the template word"
            )
        value = bases[region] + offset
        if value >= _UINT32_MODULUS:
            raise ExecutorFault(FAULT_RANGE, "relocated address wraps the 32-bit space")
        setattr(relocated[index], field, value)
    return relocated


def _read_channel_params(mem: _Memory, desc: Descriptor) -> tuple[list[int], ...]:
    raw = mem.read(desc.param_base, desc.param_bytes)
    bias: list[int] = []
    multipliers: list[int] = []
    shifts: list[int] = []
    for channel in range(desc.cout):
        b_value, m_value, s_value, reserved = struct.unpack_from("<iiiI", raw, channel * 16)
        if reserved:
            raise ExecutorFault(FAULT_DESCRIPTOR, "parameter record reserved word nonzero")
        if m_value < 0:
            raise ExecutorFault(FAULT_DESCRIPTOR, "parameter multiplier must be nonnegative")
        if not -31 <= s_value <= 30:
            raise ExecutorFault(FAULT_DESCRIPTOR, "parameter shift outside -31..30")
        bias.append(b_value)
        multipliers.append(m_value)
        shifts.append(s_value)
    return bias, multipliers, shifts


def _accumulate(accumulator: int, term: int, checked: bool, context: str) -> int:
    total = accumulator + term
    if checked and (total > INT32_MAX or total < INT32_MIN):
        raise ArithmeticFault(f"checked INT32 overflow in {context}")
    return total


def _requantize_out(value: int, desc: Descriptor) -> int:
    return max(desc.act_min, min(desc.act_max, value)) & 0xFF


def _execute_dense(mem: _Memory, desc: Descriptor) -> bytes:
    """CONV2D and FULLY_CONNECTED: dense A[k][8]/W[k][8] lane semantics."""
    h, w, cin, cout = desc.h, desc.w, desc.cin, desc.cout
    oh, ow = desc.oh, desc.ow
    kh, kw, sh, sw = desc.kh, desc.kw, desc.sh, desc.sw
    pad_top, pad_left = desc.pad_top, desc.pad_left
    irow, orow = desc.input0_row_bytes, desc.output_row_bytes
    zin, zout = desc.input0_zero, desc.output_zero
    full_k = kh * kw * cin if desc.opcode == OP_CONV2D else cin
    k_slice = desc.k_slice
    source = _signed(mem.read(desc.input0_base, used_span(h, w, cin, irow)))
    weights = _signed(mem.read(desc.weight_base, desc.weight_bytes))
    bias, multipliers, shifts = _read_channel_params(mem, desc)
    # Reduction decomposition in the locked kh,kw,cin order (FC: kh=kw=1).
    kwcin = kw * cin
    decomp = [(k // kwcin, (k % kwcin) // cin, k % cin) for k in range(full_k)]
    # Bias starts each reduction; products are bounded by 255*127, so when the
    # bound stays in INT32 no ordered update can overflow and checks are moot.
    checked = max(abs(value) for value in bias) + 255 * 127 * full_k > INT32_MAX
    out = bytearray(used_span(oh, ow, cout, orow))
    tile_h, tile_w = desc.tile_h, desc.tile_w
    for tile_y in range(0, oh, tile_h):
        rows = min(tile_h, oh - tile_y)
        for tile_x in range(0, ow, tile_w):
            cols = min(tile_w, ow - tile_x)
            for position in range(rows * cols):
                oy = tile_y + position // cols
                ox = tile_x + position % cols
                iy0 = oy * sh - pad_top
                ix0 = ox * sw - pad_left
                # Gather A for this position once; padding reads the input zero
                # point, which centers to zero and cannot affect any sum.
                avec = [0] * full_k
                for k, (dkh, dkw, ci) in enumerate(decomp):
                    iy = iy0 + dkh
                    ix = ix0 + dkw
                    if 0 <= iy < h and 0 <= ix < w:
                        avec[k] = source[iy * irow + ix * cin + ci] - zin
                obase = oy * orow + ox * cout
                for group in range(0, cout, 8):
                    lanes = min(8, cout - group)  # masked tail lanes carry zero W
                    wgroup = (group // 8) * full_k * 8
                    for lane in range(lanes):
                        channel = group + lane
                        woffset = wgroup + lane
                        accumulator = bias[channel]
                        for s0 in range(0, full_k, k_slice):
                            for k in range(s0, min(s0 + k_slice, full_k)):
                                accumulator = _accumulate(
                                    accumulator,
                                    avec[k] * weights[woffset + k * 8],
                                    checked,
                                    "conv2d accumulation",
                                )
                        value = (
                            multiply_by_quantized_multiplier(
                                accumulator, multipliers[channel], shifts[channel]
                            )
                            + zout
                        )
                        out[obase + channel] = _requantize_out(value, desc)
    mem.write(desc.output_base, bytes(out))
    return bytes(out)


def _execute_depthwise(mem: _Memory, desc: Descriptor) -> bytes:
    """DEPTHWISE3X3: eight channel lanes at one output position at a time."""
    h, w, cin = desc.h, desc.w, desc.cin
    oh, ow = desc.oh, desc.ow
    sh, sw = desc.sh, desc.sw
    pad_top, pad_left = desc.pad_top, desc.pad_left
    irow, orow = desc.input0_row_bytes, desc.output_row_bytes
    zin, zout = desc.input0_zero, desc.output_zero
    k_slice = desc.k_slice
    source = _signed(mem.read(desc.input0_base, used_span(h, w, cin, irow)))
    weights = _signed(mem.read(desc.weight_base, desc.weight_bytes))
    bias, multipliers, shifts = _read_channel_params(mem, desc)
    checked = max(abs(value) for value in bias) + 255 * 127 * 9 > INT32_MAX
    out = bytearray(used_span(oh, ow, cin, orow))
    tile_h, tile_w = desc.tile_h, desc.tile_w
    for tile_y in range(0, oh, tile_h):
        rows = min(tile_h, oh - tile_y)
        for tile_x in range(0, ow, tile_w):
            cols = min(tile_w, ow - tile_x)
            for position in range(rows * cols):
                oy = tile_y + position // cols
                ox = tile_x + position % cols
                iy0 = oy * sh - pad_top
                ix0 = ox * sw - pad_left
                obase = oy * orow + ox * cin
                for group in range(0, cin, 8):
                    lanes = min(8, cin - group)
                    wgroup = (group // 8) * 72
                    for lane in range(lanes):
                        channel = group + lane
                        accumulator = bias[channel]
                        for s0 in range(0, 9, k_slice):
                            for kk in range(s0, min(s0 + k_slice, 9)):
                                iy = iy0 + kk // 3
                                ix = ix0 + kk % 3
                                if 0 <= iy < h and 0 <= ix < w:
                                    accumulator = _accumulate(
                                        accumulator,
                                        (source[iy * irow + ix * cin + channel] - zin)
                                        * weights[wgroup + kk * 8 + lane],
                                        checked,
                                        "depthwise accumulation",
                                    )
                        value = (
                            multiply_by_quantized_multiplier(
                                accumulator, multipliers[channel], shifts[channel]
                            )
                            + zout
                        )
                        out[obase + channel] = _requantize_out(value, desc)
    mem.write(desc.output_base, bytes(out))
    return bytes(out)


def _execute_global_average_pool(mem: _Memory, desc: Descriptor) -> bytes:
    """GLOBAL_AVERAGE_POOL: raw-byte sum over H*W, ties-away, count=H*W."""
    h, w, cin = desc.h, desc.w, desc.cin
    irow = desc.input0_row_bytes
    k_slice = desc.k_slice
    count = h * w
    source = _signed(mem.read(desc.input0_base, used_span(h, w, cin, irow)))
    out = bytearray(cin)
    for channel in range(cin):
        total = 0
        for s0 in range(0, count, k_slice):
            for position in range(s0, min(s0 + k_slice, count)):
                iy = position // w
                ix = position % w
                total = _accumulate(
                    total,
                    source[iy * irow + ix * cin + channel],
                    True,
                    "global average sum",
                )
        averaged = (abs(total) + count // 2) // count
        if total < 0:
            averaged = -averaged
        out[channel] = max(desc.act_min, min(desc.act_max, averaged)) & 0xFF
    mem.write(desc.output_base, bytes(out))
    return bytes(out)


def _execute_add(mem: _Memory, desc: Descriptor) -> bytes:
    """ADD: pinned 2^20 pre-scaled INT8 path with checked sum."""
    h, w, cin = desc.h, desc.w, desc.cin
    raw = mem.read(desc.param_base, desc.param_bytes)
    left_shift, m0, s0, m1, s1, mout, sout, reserved = struct.unpack("<IiiiiiiI", raw)
    if reserved or left_shift != ADD_LEFT_SHIFT:
        raise ExecutorFault(FAULT_DESCRIPTOR, "ADD parameter encoding is not the pinned form")
    for multiplier, shift, name in ((m0, s0, "m0"), (m1, s1, "m1"), (mout, sout, "mout")):
        if multiplier < 0:
            raise ExecutorFault(FAULT_DESCRIPTOR, f"ADD {name} multiplier must be nonnegative")
        if not -31 <= shift <= 30:
            raise ExecutorFault(FAULT_DESCRIPTOR, f"ADD {name} shift outside -31..30")
    in0 = _signed(mem.read(desc.input0_base, used_span(h, w, cin, desc.input0_row_bytes)))
    in1 = _signed(mem.read(desc.input1_base, used_span(h, w, cin, desc.input1_row_bytes)))
    z0, z1, zout = desc.input0_zero, desc.input1_zero, desc.output_zero
    out = bytearray(used_span(desc.oh, desc.ow, desc.cout, desc.output_row_bytes))
    for iy in range(h):
        for ix in range(w):
            i0 = iy * desc.input0_row_bytes + ix * cin
            i1 = iy * desc.input1_row_bytes + ix * cin
            io = iy * desc.output_row_bytes + ix * desc.cout
            for channel in range(cin):
                x0 = (in0[i0 + channel] - z0) << left_shift
                x1 = (in1[i1 + channel] - z1) << left_shift
                term0 = multiply_by_quantized_multiplier(x0, m0, s0)
                term1 = multiply_by_quantized_multiplier(x1, m1, s1)
                total = term0 + term1
                if total > INT32_MAX or total < INT32_MIN:
                    raise ArithmeticFault("checked INT32 overflow in ADD sum")
                value = multiply_by_quantized_multiplier(total, mout, sout) + zout
                out[io + channel] = _requantize_out(value, desc)
    mem.write(desc.output_base, bytes(out))
    return bytes(out)


def _activation_tensor(mem: _Memory, desc: Descriptor, *, input1: bool = False) -> Tensor:
    base = desc.input1_base if input1 else desc.input0_base
    row = desc.input1_row_bytes if input1 else desc.input0_row_bytes
    zero = desc.input1_zero if input1 else desc.input0_zero
    raw = _signed(mem.read(base, used_span(desc.h, desc.w, desc.cin, row)))
    packed = tuple(
        raw[y * row + x * desc.cin + channel]
        for y in range(desc.h) for x in range(desc.w) for channel in range(desc.cin)
    )
    return Tensor((desc.h, desc.w, desc.cin), packed, 1.0, zero)


def _execute_pool(mem: _Memory, desc: Descriptor) -> bytes:
    source = _activation_tensor(mem, desc)
    kwargs = {
        "kernel_h": desc.kh, "kernel_w": desc.kw,
        "stride_h": desc.sh, "stride_w": desc.sw,
        "pad_top": desc.pad_top, "pad_bottom": desc.pad_bottom,
        "pad_left": desc.pad_left, "pad_right": desc.pad_right,
        "act_min": desc.act_min, "act_max": desc.act_max,
    }
    result = (max_pool(source, **kwargs) if desc.opcode == OP_MAX_POOL
              else average_pool(source, **kwargs))
    block = bytes(value & 0xFF for value in result.data)
    mem.write(desc.output_base, block)
    return block


def _execute_clamp(mem: _Memory, desc: Descriptor) -> bytes:
    result = clamp(_activation_tensor(mem, desc), desc.act_min, desc.act_max)
    block = bytes(value & 0xFF for value in result.data)
    mem.write(desc.output_base, block)
    return block


def _execute_validated(mem: _Memory, desc: Descriptor) -> bytes:
    try:
        if desc.opcode in (OP_CONV2D, OP_FULLY_CONNECTED):
            return _execute_dense(mem, desc)
        if desc.opcode == OP_DEPTHWISE3X3:
            return _execute_depthwise(mem, desc)
        if desc.opcode == OP_GLOBAL_AVERAGE_POOL:
            return _execute_global_average_pool(mem, desc)
        if desc.opcode == OP_ADD:
            return _execute_add(mem, desc)
        if desc.opcode in (OP_MAX_POOL, OP_AVERAGE_POOL):
            return _execute_pool(mem, desc)
        if desc.opcode == OP_CLAMP:
            return _execute_clamp(mem, desc)
        raise ExecutorFault(
            FAULT_UNSUPPORTED,
            f"opcode {desc.opcode} is defined by the ABI but not placed by NPU-P0",
        )
    except ArithmeticFault as error:
        raise ExecutorFault(FAULT_ARITHMETIC, str(error)) from error


def execute_job(
    job, input_bytes: bytes, *, bases: dict[str, int] | None = None
) -> ExecutionResult:
    """Execute one compiled job over fresh regions and return all layer tensors.

    input_bytes are the raw INT8 model input bytes placed at job.input_offset
    in the arena. bases may override the documented DEFAULT_BASES map.
    """
    merged = dict(DEFAULT_BASES)
    if bases:
        merged.update(bases)
    expected = job.report.get("input", {}).get("bytes")
    if expected is not None and len(input_bytes) != expected:
        raise ExecutorFault(
            FAULT_RANGE, f"input is {len(input_bytes)} bytes, expected {expected}"
        )
    arena = bytearray(job.arena_bytes)
    if job.input_offset + len(input_bytes) > len(arena):
        raise ExecutorFault(FAULT_RANGE, "input image does not fit the arena")
    arena[job.input_offset : job.input_offset + len(input_bytes)] = input_bytes
    mem = _Memory(
        {
            "arena": (merged["arena"], arena),
            "weights": (merged["weights"], bytearray(job.weights)),
            "params": (merged["params"], bytearray(job.params)),
        }
    )
    relocated = relocate_descriptors(job, merged)
    region = (merged["descriptors"], len(relocated) * DESCRIPTOR_BYTES)
    finalized: list[Descriptor] = []
    for index, desc in enumerate(relocated):
        try:
            wire = Descriptor.from_bytes(desc.to_bytes())
            validate_descriptor(wire, descriptor_region=region)
        except DescriptorError as error:
            raise ExecutorFault(error.code, f"descriptor {index}: {error}") from error
        finalized.append(wire)
    metadata = {}
    for entry in job.report.get("operators", ()):
        descriptor_index = entry.get("descriptor_index")
        if descriptor_index is not None:
            metadata[descriptor_index] = entry
    for index in range(len(finalized)):
        if index not in metadata:
            raise ExecutorFault(
                FAULT_DESCRIPTOR, f"job report lacks metadata for descriptor {index}"
            )
    layers: list[Tensor] = []
    digests: list[str] = []
    descriptor_layers: dict[int, Tensor] = {}
    for step in job.steps:
        kind = step.get("kind")
        if kind == "npu":
            first = step["first_descriptor"]
            for index in range(first, first + step["count"]):
                desc = finalized[index]
                block = _execute_validated(mem, desc)
                entry = metadata.get(index)
                quant = entry["quantization"]
                tensor = Tensor(
                    (desc.oh, desc.ow, desc.cout),
                    tuple(_signed(block)),
                    float(quant["output_scale"]),
                    desc.output_zero,
                )
                layers.append(tensor)
                descriptor_layers[index] = tensor
                digests.append(hashlib.sha256(block).hexdigest())
        elif kind == "cpu" and step.get("op") == "softmax":
            source_index = step["source_descriptor"]
            if (not isinstance(source_index, int) or source_index < 0 or
                    source_index >= len(finalized)):
                raise ExecutorFault(FAULT_DESCRIPTOR, "invalid softmax source descriptor")
            desc = finalized[source_index]
            entry = metadata.get(source_index)
            quant = entry["quantization"]
            span = used_span(desc.oh, desc.ow, desc.cout, desc.output_row_bytes)
            block = mem.read(desc.output_base, span)
            logits = Tensor(
                (desc.oh, desc.ow, desc.cout),
                tuple(_signed(block)),
                float(quant["output_scale"]),
                desc.output_zero,
            )
            try:
                result = softmax_int8(
                    logits,
                    input_multiplier=step["input_multiplier"],
                    input_left_shift=step["input_left_shift"],
                    diff_min=step["diff_min"],
                )
            except ArithmeticFault as error:
                raise ExecutorFault(FAULT_ARITHMETIC, str(error)) from error
            except (KeyError, ValueError, TypeError) as error:
                raise ExecutorFault(FAULT_DESCRIPTOR, f"invalid softmax step: {error}") from error
            layers.append(result)
            digests.append(
                hashlib.sha256(bytes(value & 0xFF for value in result.data)).hexdigest()
            )
        else:
            raise ExecutorFault(FAULT_UNSUPPORTED, f"unsupported execution step {step!r}")
    if not layers:
        raise ExecutorFault(FAULT_DESCRIPTOR, "job produced no layers")
    output = layers[-1]
    output_descriptor = job.report.get("output", {}).get("source_descriptor")
    if not any(step.get("kind") == "cpu" for step in job.steps):
        output = descriptor_layers.get(output_descriptor, output)
    return ExecutionResult(layers=layers, digests=digests, output=output)
