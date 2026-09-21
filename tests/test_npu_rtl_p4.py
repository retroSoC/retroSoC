"""NPU-P4 operator differential RTL tests (Icarus and Verilator).

``test_npu_operator`` drives the production job controller (npu_core with
ExecutionReady=1 + npu_dma over a byte-memory BFM) with descriptor jobs whose
stored output bytes are compared byte-for-byte against the pinned Python
numerical reference (scripts/npu_reference.py) of the descriptor's own
quantization records. Descriptor jobs, operand tensors, parameter records,
golden windows and expected counters are generated here with a deterministic
LCG (recorded seeds). Validation-rejection cases reuse
scripts/npu_descriptors.py as the golden first-fault oracle and prove that no
side effects reach memory. Covers the NPU-V011/NPU-V012 operator lists and
the fixed models' operator shapes (KWS/VWW).
"""

from __future__ import annotations

import struct
import sys
import zlib
from pathlib import Path

import pytest


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
sys.path.insert(0, str(ROOT / "tests"))

from npu_descriptors import (  # noqa: E402
    DESCRIPTOR_BYTES,
    Descriptor,
    DescriptorError,
    full_reduction,
    used_span,
    validate_descriptor,
)
from npu_reference import Tensor  # noqa: E402
import npu_reference  # noqa: E402
from test_npu_rtl_p3 import (  # noqa: E402
    CORE_SOURCES,
    F_ARITHMETIC,
    MEM_BASE,
    _build_sim,
    _run,
    _tools,
)

OPERATOR_TB = ROOT / "tests/rtl" / "npu_operator_tb.sv"
P4_SOURCES = [
    *CORE_SOURCES[:-2],
    ROOT / "rtl/ip/multimedia" / "npu_mac_array.sv",
    ROOT / "rtl/ip/multimedia" / "npu_accumulator.sv",
    ROOT / "rtl/ip/multimedia" / "npu_vector.sv",
    ROOT / "rtl/ip/multimedia" / "npu_requantizer.sv",
    *CORE_SOURCES[-2:],
]

CORE_MEM_BYTES = 0x80000
GAP_FILL = 0xA5

OP_CONV2D = 1
OP_DEPTHWISE3X3 = 2
OP_FULLY_CONNECTED = 3
OP_ADD = 4
OP_MAX_POOL = 5
OP_AVERAGE_POOL = 6
OP_GLOBAL_AVERAGE_POOL = 7
OP_CLAMP = 8

R_DONE = 1
R_ERROR = 2

SCEN_COMPUTE = 0
SCEN_REJECT = 1
SCEN_ARITH = 2


# ---------------------------------------------------------------------------
# Deterministic LCG (the repo's Numerical Recipes idiom)
# ---------------------------------------------------------------------------


class _Rng:
    def __init__(self, seed: int) -> None:
        self.state = seed & 0xFFFFFFFF

    def next(self) -> int:
        self.state = (self.state * 1664525 + 1013904223) & 0xFFFFFFFF
        return self.state

    def byte(self) -> int:
        return (self.next() >> 16) & 0xFF

    def int8(self) -> int:
        value = self.byte()
        return value - 256 if value >= 128 else value

    def weight(self) -> int:
        value = self.int8()
        return 127 if value == -128 else value

    def int32(self) -> int:
        return struct.unpack("<i", struct.pack("<I", self.next()))[0]

    def nonneg31(self) -> int:
        return self.next() & 0x7FFFFFFF

    def shift(self) -> int:
        return (self.next() % 62) - 31

    def pick(self, seq):
        return seq[self.next() % len(seq)]


# ---------------------------------------------------------------------------
# Descriptor job construction (tensors, parameter records, golden, counters)
# ---------------------------------------------------------------------------


class _Job:
    """One descriptor job: memory image, golden output window, expectations."""

    def __init__(self, name: str, scen: int) -> None:
        self.name = name
        self.scen = scen
        self.descs: list[Descriptor] = []
        self.mem = bytearray([GAP_FILL] * CORE_MEM_BYTES)
        self.gold = bytearray([GAP_FILL] * CORE_MEM_BYTES)
        self._gold_spans: list[tuple[int, int]] = []
        self.gold_lo = CORE_MEM_BYTES
        self.gold_hi = 0
        self.macs = 0
        self.fcode = 0
        self.fdesc = 0xFFFFFFFF
        self.faddr = 0
        self.completed = 0
        self.alloc = 0x4000

    def region(self, size: int, align: int = 64) -> int:
        base = (self.alloc + align - 1) & ~(align - 1)
        self.alloc = base + max(size, 1)
        return base

    def place(self, base: int, payload: bytes) -> None:
        self.mem[base : base + len(payload)] = payload

    def place_golden(self, base: int, payload: bytes) -> None:
        self.gold[base : base + len(payload)] = payload
        self._gold_spans.append((base, base + len(payload)))
        self.gold_lo = min(self.gold_lo, base)
        self.gold_hi = max(self.gold_hi, base + len(payload))

    def finish(self) -> None:
        # Gap bytes inside the golden window (between the descriptors' output
        # spans) keep the initial memory image: a store outside the output
        # spans is a side effect and fails the byte-exact comparison.
        covered = bytearray(CORE_MEM_BYTES)
        for lo, hi in self._gold_spans:
            covered[lo:hi] = b"\x01" * (hi - lo)
        for index in range(CORE_MEM_BYTES):
            if not covered[index]:
                self.gold[index] = self.mem[index]
        if self.gold_hi == 0:
            self.gold_lo = 0
            self.gold_hi = 1



def _tile(th: int, tw: int, oh: int, ow: int) -> tuple[int, int]:
    """Clamp a tile choice to the descriptor limits (<=8 positions, <= output)."""
    rows = max(1, min(th, oh, 8))
    cols = max(1, min(tw, ow, 8 // rows))
    return (rows, cols)


def _degrade_shifts(shifts: list[int]) -> list[int]:
    """Clamp QM shifts to nonpositive so the golden can never fault (compute cases)."""
    return [min(value, 0) for value in shifts]


def _golden_conv(rng, inputs, weights, bias, mults, shifts, sh, sw, pads, zout, act,
                 allow_fault=False):
    try:
        ref = npu_reference.conv2d(
            inputs, weights, bias, mults, shifts,
            stride_h=sh, stride_w=sw,
            pad_top=pads[0], pad_bottom=pads[1], pad_left=pads[2], pad_right=pads[3],
            output_scale=1.0, output_zero_point=zout, act_min=act[0], act_max=act[1])
        return ref, shifts
    except npu_reference.ArithmeticFault:
        if allow_fault:
            oh = (inputs.height + pads[0] + pads[1] - len(weights[0])) // sh + 1
            ow = (inputs.width + pads[2] + pads[3] - len(weights[0][0])) // sw + 1
            zero = Tensor((oh, ow, len(weights)), tuple([0] * (oh * ow * len(weights))),
                          1.0, zout)
            return zero, shifts
        shifts = _degrade_shifts(shifts)
        ref = npu_reference.conv2d(
            inputs, weights, bias, mults, shifts,
            stride_h=sh, stride_w=sw,
            pad_top=pads[0], pad_bottom=pads[1], pad_left=pads[2], pad_right=pads[3],
            output_scale=1.0, output_zero_point=zout, act_min=act[0], act_max=act[1])
        return ref, shifts


def _golden_dw(rng, inputs, weights, bias, mults, shifts, sh, sw, pads, zout, act):
    try:
        ref = npu_reference.depthwise_conv2d(
            inputs, weights, bias, mults, shifts,
            stride_h=sh, stride_w=sw,
            pad_top=pads[0], pad_bottom=pads[1], pad_left=pads[2], pad_right=pads[3],
            output_scale=1.0, output_zero_point=zout, act_min=act[0], act_max=act[1])
    except npu_reference.ArithmeticFault:
        shifts = _degrade_shifts(shifts)
        ref = npu_reference.depthwise_conv2d(
            inputs, weights, bias, mults, shifts,
            stride_h=sh, stride_w=sw,
            pad_top=pads[0], pad_bottom=pads[1], pad_left=pads[2], pad_right=pads[3],
            output_scale=1.0, output_zero_point=zout, act_min=act[0], act_max=act[1])
    return ref, shifts


def _golden_add(rng, in0, in1, z0, z1, zout, quant, act):
    m0, s0, m1, s1, mout, sout = quant
    try:
        ref = npu_reference.add(
            Tensor(in0[0], in0[1], 1.0, z0), Tensor(in1[0], in1[1], 1.0, z1),
            input0_multiplier=m0, input0_shift=s0, input1_multiplier=m1, input1_shift=s1,
            output_multiplier=mout, output_shift=sout, output_scale=1.0,
            output_zero_point=zout, act_min=act[0], act_max=act[1])
    except npu_reference.ArithmeticFault:
        m0, s0, m1, s1, mout, sout = (m0, min(s0, 0), m1, min(s1, 0), mout, min(sout, 0))
        ref = npu_reference.add(
            Tensor(in0[0], in0[1], 1.0, z0), Tensor(in1[0], in1[1], 1.0, z1),
            input0_multiplier=m0, input0_shift=s0, input1_multiplier=m1, input1_shift=s1,
            output_multiplier=mout, output_shift=sout, output_scale=1.0,
            output_zero_point=zout, act_min=act[0], act_max=act[1])
    return ref, (m0, s0, m1, s1, mout, sout)

def _tensor_bytes(ref: Tensor) -> bytes:
    return bytes(value & 0xFF for value in ref.data)


def _out_words(desc: Descriptor, ref: Tensor, job: _Job) -> None:
    raw = _tensor_bytes(ref)
    cout = desc.cout
    out = bytearray(used_span(desc.oh, desc.ow, cout, desc.output_row_bytes))
    for oy in range(desc.oh):
        for ox in range(desc.ow):
            for channel in range(cout):
                out[oy * desc.output_row_bytes + ox * cout + channel] = raw[
                    (oy * desc.ow + ox) * cout + channel
                ]
    job.place_golden(desc.output_base - MEM_BASE, bytes(out))


def _pack_channel_params(bias: list[int], mults: list[int], shifts: list[int]) -> bytes:
    return b"".join(struct.pack("<iiiI", b_value, m_value, s_value, 0)
                    for b_value, m_value, s_value in zip(bias, mults, shifts))


def _pack_conv_weights(weights, cout: int, full_k: int) -> bytes:
    """Pack (Cout,Kh,Kw,Cin) nested weights as group-of-8 rows of lanes."""
    packed = bytearray()
    for group in range(0, cout, 8):
        lanes = min(8, cout - group)
        for k in range(full_k):
            for lane in range(8):
                value = 0
                if lane < lanes:
                    flat = weights[group + lane]
                    value = flat[k]
                packed.append(value & 0xFF)
    return bytes(packed)


def _flat_conv_weights(weights, cout: int, kh: int, kw: int, cin: int) -> list[list[int]]:
    """Flatten nested (Cout,Kh,Kw,Cin) weights in the kh,kw,cin reduction order."""
    flat: list[list[int]] = []
    for channel in range(cout):
        row: list[int] = []
        for dkh in range(kh):
            for dkw in range(kw):
                for ci in range(cin):
                    row.append(weights[channel][dkh][dkw][ci])
        flat.append(row)
    return flat


def _conv_like(rng: _Rng, job: _Job, *, opcode: int, h: int, w: int, cin: int, cout: int,
               kh: int, kw: int, sh: int, sw: int, pads: tuple[int, int, int, int],
               zin: int, zout: int, tile: tuple[int, int], k_slice: int,
               act: tuple[int, int], irow: int | None = None,
               orow: int | None = None, params: tuple | None = None,
               allow_fault: bool = False) -> Descriptor:
    """Build a CONV2D/FC job descriptor with reference golden content."""
    in_data = tuple(rng.int8() for _ in range(h * w * cin))
    weights = [[[[rng.weight() for _ in range(cin)] for _ in range(kw)] for _ in range(kh)]
               for _ in range(cout)]
    if params is None:
        bias = [max(-(1 << 28), min((1 << 28) - 1, rng.int32())) for _ in range(cout)]
        mults = [rng.nonneg31() for _ in range(cout)]
        shifts = [max(-31, min(3, rng.shift())) for _ in range(cout)]
    else:
        bias, mults, shifts = params
    if opcode == OP_FULLY_CONNECTED:
        kh, kw, sh, sw = 1, 1, 1, 1
        pads = (0, 0, 0, 0)
    ref, shifts = _golden_conv(rng, Tensor((h, w, cin), in_data, 1.0, zin), weights,
                               bias, mults, shifts, sh, sw, pads, zout, act,
                               allow_fault=allow_fault)
    oh, ow = ref.height, ref.width
    irow = irow if irow is not None else w * cin
    orow = orow if orow is not None else ow * cout
    desc = Descriptor()
    desc.version_opcode = 0x0100_0000 | opcode
    desc.input_hw = (w << 16) | h
    desc.channels = (cout << 16) | cin
    desc.output_hw = (ow << 16) | oh
    desc.input0_row_bytes = irow
    desc.output_row_bytes = orow
    desc.kernel_stride = (sw << 24) | (sh << 16) | (kw << 8) | kh
    desc.padding = (pads[3] << 24) | (pads[2] << 16) | (pads[1] << 8) | pads[0]
    desc.tile_hw = (tile[1] << 8) | tile[0]
    desc.k_slice = k_slice
    full_k = full_reduction(desc)
    in_span = used_span(h, w, cin, irow)
    out_span = used_span(oh, ow, cout, orow)
    desc.input0_base = MEM_BASE + job.region(in_span)
    desc.output_base = MEM_BASE + job.region(out_span)
    desc.param_base = MEM_BASE + job.region(cout * 16)
    desc.weight_base = MEM_BASE + job.region(((cout + 7) // 8) * full_k * 8)
    desc.input0_bytes = in_span
    desc.output_bytes = out_span
    desc.param_bytes = cout * 16
    desc.input0_zero = zin
    desc.output_zero = zout
    desc.act_min = act[0]
    desc.act_max = act[1]
    desc.weight_bytes = ((cout + 7) // 8) * full_k * 8
    validate_descriptor(desc, descriptor_region=(MEM_BASE, 8 * DESCRIPTOR_BYTES))
    job.descs.append(desc)
    job.place(desc.input0_base - MEM_BASE, bytes(value & 0xFF for value in in_data))
    job.place(desc.param_base - MEM_BASE, _pack_channel_params(bias, mults, shifts))
    flat = _flat_conv_weights(weights, cout, kh, kw, cin)
    job.place(desc.weight_base - MEM_BASE, _pack_conv_weights(flat, cout, full_k))
    _out_words(desc, ref, job)
    job.macs += oh * ow * cout * full_k
    return desc


def _dw_like(rng: _Rng, job: _Job, *, h: int, w: int, cin: int, sh: int, sw: int,
             pads: tuple[int, int, int, int], zin: int, zout: int,
             tile: tuple[int, int], k_slice: int, act: tuple[int, int],
             params: tuple | None = None) -> Descriptor:
    in_data = tuple(rng.int8() for _ in range(h * w * cin))
    weights = [[[rng.weight() for _ in range(cin)] for _ in range(3)] for _ in range(3)]
    if params is None:
        bias = [max(-(1 << 28), min((1 << 28) - 1, rng.int32())) for _ in range(cin)]
        mults = [rng.nonneg31() for _ in range(cin)]
        shifts = [max(-31, min(3, rng.shift())) for _ in range(cin)]
    else:
        bias, mults, shifts = params
    ref, shifts = _golden_dw(rng, Tensor((h, w, cin), in_data, 1.0, zin), weights,
                             bias, mults, shifts, sh, sw, pads, zout, act)
    oh, ow = ref.height, ref.width
    irow = w * cin
    orow = ow * cin
    desc = Descriptor()
    desc.version_opcode = 0x0100_0000 | OP_DEPTHWISE3X3
    desc.input_hw = (w << 16) | h
    desc.channels = (cin << 16) | cin
    desc.output_hw = (ow << 16) | oh
    desc.input0_row_bytes = irow
    desc.output_row_bytes = orow
    desc.kernel_stride = (sw << 24) | (sh << 16) | (3 << 8) | 3
    desc.padding = (pads[3] << 24) | (pads[2] << 16) | (pads[1] << 8) | pads[0]
    desc.tile_hw = (tile[1] << 8) | tile[0]
    desc.k_slice = k_slice
    in_span = used_span(h, w, cin, irow)
    out_span = used_span(oh, ow, cin, orow)
    desc.input0_base = MEM_BASE + job.region(in_span)
    desc.output_base = MEM_BASE + job.region(out_span)
    desc.param_base = MEM_BASE + job.region(cin * 16)
    desc.weight_base = MEM_BASE + job.region(((cin + 7) // 8) * 72)
    desc.input0_bytes = in_span
    desc.output_bytes = out_span
    desc.param_bytes = cin * 16
    desc.input0_zero = zin
    desc.output_zero = zout
    desc.act_min = act[0]
    desc.act_max = act[1]
    desc.weight_bytes = ((cin + 7) // 8) * 72
    validate_descriptor(desc, descriptor_region=(MEM_BASE, 8 * DESCRIPTOR_BYTES))
    job.descs.append(desc)
    job.place(desc.input0_base - MEM_BASE, bytes(value & 0xFF for value in in_data))
    job.place(desc.param_base - MEM_BASE, _pack_channel_params(bias, mults, shifts))
    flat = [[weights[dkh][dkw][c] for dkh in range(3) for dkw in range(3)] for c in range(cin)]
    packed = bytearray()
    for group in range(0, cin, 8):
        lanes = min(8, cin - group)
        for kk in range(9):
            for lane in range(8):
                value = flat[group + lane][kk] if lane < lanes else 0
                packed.append(value & 0xFF)
    job.place(desc.weight_base - MEM_BASE, bytes(packed))
    _out_words(desc, ref, job)
    job.macs += oh * ow * cin * 9
    return desc


def _pool_like(rng: _Rng, job: _Job, *, opcode: int, h: int, w: int, cin: int,
               kh: int, kw: int, sh: int, sw: int, pads: tuple[int, int, int, int],
               zp: int, tile: tuple[int, int], k_slice: int,
               act: tuple[int, int]) -> Descriptor:
    in_data = tuple(rng.int8() for _ in range(h * w * cin))
    call = npu_reference.max_pool if opcode == OP_MAX_POOL else npu_reference.average_pool
    ref = call(
        Tensor((h, w, cin), in_data, 1.0, zp),
        kernel_h=kh, kernel_w=kw, stride_h=sh, stride_w=sw,
        pad_top=pads[0], pad_bottom=pads[1], pad_left=pads[2], pad_right=pads[3],
        act_min=act[0], act_max=act[1],
    )
    oh, ow = ref.height, ref.width
    irow = w * cin
    orow = ow * cin
    desc = Descriptor()
    desc.version_opcode = 0x0100_0000 | opcode
    desc.input_hw = (w << 16) | h
    desc.channels = (cin << 16) | cin
    desc.output_hw = (ow << 16) | oh
    desc.input0_row_bytes = irow
    desc.output_row_bytes = orow
    desc.kernel_stride = (sw << 24) | (sh << 16) | (kw << 8) | kh
    desc.padding = (pads[3] << 24) | (pads[2] << 16) | (pads[1] << 8) | pads[0]
    desc.tile_hw = (tile[1] << 8) | tile[0]
    desc.k_slice = k_slice
    in_span = used_span(h, w, cin, irow)
    out_span = used_span(oh, ow, cin, orow)
    desc.input0_base = MEM_BASE + job.region(in_span)
    desc.output_base = MEM_BASE + job.region(out_span)
    desc.input0_bytes = in_span
    desc.output_bytes = out_span
    desc.input0_zero = zp
    desc.output_zero = zp
    desc.act_min = act[0]
    desc.act_max = act[1]
    validate_descriptor(desc, descriptor_region=(MEM_BASE, 8 * DESCRIPTOR_BYTES))
    job.descs.append(desc)
    job.place(desc.input0_base - MEM_BASE, bytes(value & 0xFF for value in in_data))
    _out_words(desc, ref, job)
    return desc


def _gap_like(rng: _Rng, job: _Job, *, h: int, w: int, cin: int, zp: int,
              tile: tuple[int, int], k_slice: int, act: tuple[int, int]) -> Descriptor:
    in_data = tuple(rng.int8() for _ in range(h * w * cin))
    ref = npu_reference.global_average_pool(
        Tensor((h, w, cin), in_data, 1.0, zp), act_min=act[0], act_max=act[1])
    desc = Descriptor()
    desc.version_opcode = 0x0100_0000 | OP_GLOBAL_AVERAGE_POOL
    desc.input_hw = (w << 16) | h
    desc.channels = (cin << 16) | cin
    desc.output_hw = (1 << 16) | 1
    desc.input0_row_bytes = w * cin
    desc.output_row_bytes = cin
    desc.tile_hw = (tile[1] << 8) | tile[0]
    desc.k_slice = k_slice
    in_span = used_span(h, w, cin, w * cin)
    desc.input0_base = MEM_BASE + job.region(in_span)
    desc.output_base = MEM_BASE + job.region(cin)
    desc.input0_bytes = in_span
    desc.output_bytes = cin
    desc.input0_zero = zp
    desc.output_zero = zp
    desc.act_min = act[0]
    desc.act_max = act[1]
    validate_descriptor(desc, descriptor_region=(MEM_BASE, 8 * DESCRIPTOR_BYTES))
    job.descs.append(desc)
    job.place(desc.input0_base - MEM_BASE, bytes(value & 0xFF for value in in_data))
    _out_words(desc, ref, job)
    return desc


def _add_like(rng: _Rng, job: _Job, *, h: int, w: int, cin: int,
              z0: int, z1: int, zout: int, tile: tuple[int, int], k_slice: int,
              act: tuple[int, int], alias: bool = False,
              multipliers: tuple | None = None) -> Descriptor:
    in0 = tuple(rng.int8() for _ in range(h * w * cin))
    in1 = in0 if alias else tuple(rng.int8() for _ in range(h * w * cin))
    if multipliers is None:
        m0, m1, mout = rng.nonneg31(), rng.nonneg31(), rng.nonneg31()
        s0, s1, sout = (max(-31, min(3, rng.shift())) for _ in range(3))
    else:
        m0, s0, m1, s1, mout, sout = multipliers
    ref, (m0, s0, m1, s1, mout, sout) = _golden_add(
        rng, ((h, w, cin), in0), ((h, w, cin), in1), z0, z1, zout,
        (m0, s0, m1, s1, mout, sout), act)
    oh, ow = h, w
    irow = w * cin
    orow = ow * cin
    desc = Descriptor()
    desc.version_opcode = 0x0100_0000 | OP_ADD
    desc.input_hw = (w << 16) | h
    desc.channels = (cin << 16) | cin
    desc.output_hw = (ow << 16) | oh
    desc.input0_row_bytes = irow
    desc.output_row_bytes = orow
    desc.input1_row_bytes = irow
    desc.kernel_stride = 0x0101_0101
    desc.tile_hw = (tile[1] << 8) | tile[0]
    desc.k_slice = k_slice
    in_span = used_span(h, w, cin, irow)
    out_span = used_span(oh, ow, cin, orow)
    desc.input0_base = MEM_BASE + job.region(in_span)
    desc.input1_base = desc.input0_base if alias else MEM_BASE + job.region(in_span)
    desc.output_base = MEM_BASE + job.region(out_span)
    desc.param_base = MEM_BASE + job.region(32)
    desc.input0_bytes = in_span
    desc.input1_bytes = in_span
    desc.output_bytes = out_span
    desc.param_bytes = 32
    desc.input0_zero = z0
    desc.input1_zero = z1
    desc.output_zero = zout
    desc.act_min = act[0]
    desc.act_max = act[1]
    validate_descriptor(desc, descriptor_region=(MEM_BASE, 8 * DESCRIPTOR_BYTES))
    job.descs.append(desc)
    job.place(desc.input0_base - MEM_BASE, bytes(value & 0xFF for value in in0))
    if not alias:
        job.place(desc.input1_base - MEM_BASE, bytes(value & 0xFF for value in in1))
    job.place(desc.param_base - MEM_BASE, struct.pack("<IiiiiiiI", 20, m0, s0, m1, s1,
                                                      mout, sout, 0))
    _out_words(desc, ref, job)
    return desc


def _clamp_like(rng: _Rng, job: _Job, *, h: int, w: int, cin: int, zp: int,
                tile: tuple[int, int], k_slice: int, act: tuple[int, int]) -> Descriptor:
    in_data = tuple(rng.int8() for _ in range(h * w * cin))
    ref = npu_reference.clamp(Tensor((h, w, cin), in_data, 1.0, zp), act[0], act[1])
    desc = Descriptor()
    desc.version_opcode = 0x0100_0000 | OP_CLAMP
    desc.input_hw = (w << 16) | h
    desc.channels = (cin << 16) | cin
    desc.output_hw = (w << 16) | h
    desc.input0_row_bytes = w * cin
    desc.output_row_bytes = w * cin
    desc.kernel_stride = 0x0101_0101
    desc.tile_hw = (tile[1] << 8) | tile[0]
    desc.k_slice = k_slice
    in_span = used_span(h, w, cin, w * cin)
    desc.input0_base = MEM_BASE + job.region(in_span)
    desc.output_base = MEM_BASE + job.region(in_span)
    desc.input0_bytes = in_span
    desc.output_bytes = in_span
    desc.input0_zero = zp
    desc.output_zero = zp
    desc.act_min = act[0]
    desc.act_max = act[1]
    validate_descriptor(desc, descriptor_region=(MEM_BASE, 8 * DESCRIPTOR_BYTES))
    job.descs.append(desc)
    job.place(desc.input0_base - MEM_BASE, bytes(value & 0xFF for value in in_data))
    _out_words(desc, ref, job)
    return desc


# ---------------------------------------------------------------------------
# Case emission
# ---------------------------------------------------------------------------


def _image_hex(path: Path, blob: bytes) -> None:
    pad = (-len(blob)) % 4
    words = struct.unpack(f"<{(len(blob) + pad) // 4}I", blob + bytes(pad))
    path.write_text("\n".join(f"{word & 0xFFFFFFFF:08x}" for word in words) + "\n",
                    encoding="utf-8")


def _emit(tmp_path: Path, job: _Job, cases: list[list[str]]) -> None:
    job.finish()
    for index, desc in enumerate(job.descs):
        job.place(index * DESCRIPTOR_BYTES, desc.to_bytes())
    image = tmp_path / f"op_{job.name}.hex"
    _image_hex(image, bytes(job.mem))
    golden = tmp_path / f"op_{job.name}_gold.hex"
    gold = bytes(job.gold[job.gold_lo : job.gold_hi])
    _image_hex(golden, gold)
    cases.append([
        f"+IMG={image}",
        f"+GOLD={golden}",
        f"+BASE={MEM_BASE:x}",
        f"+COUNT={len(job.descs)}",
        "+JOBID=5a5b5c5d",
        "+TIMEOUT=20000000",
        f"+SCEN={job.scen}",
        f"+FCODE={job.fcode}",
        f"+FDESC={job.fdesc:x}",
        f"+FADDR={job.faddr:x}",
        "+CODE=1",
        f"+MACS={job.macs}",
        f"+GOLD_BASE={(MEM_BASE + job.gold_lo):x}",
        f"+GOLD_BYTES={len(gold)}",
        f"+NAME={job.name}",
    ])


def _reject(tmp_path: Path, cases: list[list[str]], name: str, opcode: int,
            mutate) -> None:
    """One invalid descriptor: the golden validator is the first-fault oracle."""
    rng = _Rng(zlib.crc32(name.encode()))
    job = _Job(name, SCEN_REJECT)
    if opcode == OP_CONV2D:
        desc = _conv_like(rng, job, opcode=opcode, h=4, w=4, cin=1, cout=1, kh=1, kw=1,
                          sh=1, sw=1, pads=(0, 0, 0, 0), zin=0, zout=0, tile=(1, 1),
                          k_slice=1, act=(-128, 127))
    elif opcode == OP_DEPTHWISE3X3:
        desc = _dw_like(rng, job, h=4, w=4, cin=8, sh=1, sw=1, pads=(0, 0, 0, 0), zin=0,
                        zout=0, tile=(1, 1), k_slice=9, act=(-128, 127))
    elif opcode == OP_ADD:
        desc = _add_like(rng, job, h=2, w=2, cin=1, z0=0, z1=0, zout=0, tile=(1, 1),
                         k_slice=1, act=(-128, 127))
    else:
        desc = _clamp_like(rng, job, h=2, w=2, cin=1, zp=0, tile=(1, 1), k_slice=1,
                           act=(-128, 127))
    words = list(struct.unpack(f"<{DESCRIPTOR_BYTES // 4}I", desc.to_bytes()))
    mutate(words)
    record = Descriptor.from_bytes(struct.pack(f"<{len(words)}I", *words))
    try:
        validate_descriptor(record, descriptor_region=(MEM_BASE, DESCRIPTOR_BYTES))
        raise AssertionError(f"rejection case {name} unexpectedly validates")
    except DescriptorError as error:
        job.fcode = error.code
        job.faddr = MEM_BASE + (error.word * 4 if error.word is not None else 0)
    job.descs = [record]
    job.gold_lo = desc.output_base - MEM_BASE
    job.gold_hi = job.gold_lo + desc.output_bytes
    job.fdesc = 0
    _emit(tmp_path, job, cases)


def _operator_cases(tmp_path: Path) -> list[list[str]]:
    cases: list[list[str]] = []

    def compute(name: str, build) -> None:
        job = _Job(name, SCEN_COMPUTE)
        build(_Rng(zlib.crc32(name.encode()) ^ 0x5EED), job)
        _emit(tmp_path, job, cases)

    # -- V011: conv kernels {1,3,4,10,16} x strides {1,2}
    for kernel in (1, 3, 4, 10, 16):
        for stride in (1, 2):
            compute(f"conv_k{kernel}s{stride}",
                    lambda rng, job, kernel=kernel, stride=stride: _conv_like(
                        rng, job, opcode=OP_CONV2D, h=kernel + 3, w=kernel + 2, cin=3,
                        cout=5, kh=kernel, kw=kernel, sh=stride, sw=stride,
                        pads=(0, 0, 0, 0), zin=0, zout=0, tile=(2, 2),
                        k_slice=max(1, (kernel * kernel * 3) // 2), act=(-128, 127)))
    # -- KWS conv10x4 stride 2 asymmetric padding (4,5,1,1)
    compute("conv_kws_10x4",
            lambda rng, job: _conv_like(rng, job, opcode=OP_CONV2D, h=13, w=8, cin=1,
                                        cout=8, kh=10, kw=4, sh=2, sw=2, pads=(4, 5, 1, 1),
                                        zin=-5, zout=17, tile=(2, 2), k_slice=40,
                                        act=(-128, 127)))
    # -- zero-point extremes on a padded conv
    for zp in (-128, 0, 83, 127):
        compute(f"conv_zp{zp & 0xFF:02x}",
                lambda rng, job, zp=zp: _conv_like(
                    rng, job, opcode=OP_CONV2D, h=6, w=5, cin=4, cout=6, kh=3, kw=3,
                    sh=2, sw=2, pads=(2, 1, 1, 2), zin=zp, zout=-zp if zp != -128 else 0,
                    tile=(2, 3), k_slice=13, act=(-128, 127)))
    # -- depthwise 3x3 multiplier 1, strides and tails
    compute("dw33_s1", lambda rng, job: _dw_like(rng, job, h=6, w=7, cin=8, sh=1, sw=1,
                                                 pads=(1, 1, 1, 1), zin=0, zout=0,
                                                 tile=(2, 2), k_slice=9, act=(-128, 127)))
    compute("dw33_s2_c7", lambda rng, job: _dw_like(rng, job, h=9, w=5, cin=7, sh=2, sw=2,
                                                    pads=(0, 1, 1, 0), zin=9, zout=-9,
                                                    tile=(3, 1), k_slice=4, act=(-64, 63)))
    compute("dw33_c1", lambda rng, job: _dw_like(rng, job, h=4, w=4, cin=1, sh=1, sw=1,
                                                 pads=(1, 1, 1, 1), zin=-128, zout=127,
                                                 tile=(1, 1), k_slice=9, act=(-128, 127)))
    # -- fully connected
    compute("fc_64_12", lambda rng, job: _conv_like(
        rng, job, opcode=OP_FULLY_CONNECTED, h=1, w=1, cin=64, cout=12, kh=1, kw=1,
        sh=1, sw=1, pads=(0, 0, 0, 0), zin=3, zout=-7, tile=(1, 1), k_slice=64,
        act=(-128, 127)))
    compute("fc_tail", lambda rng, job: _conv_like(
        rng, job, opcode=OP_FULLY_CONNECTED, h=1, w=1, cin=37, cout=9, kh=1, kw=1,
        sh=1, sw=1, pads=(0, 0, 0, 0), zin=-11, zout=23, tile=(1, 1), k_slice=19,
        act=(-128, 100)))
    # -- shift boundaries with guaranteed-safe accumulators
    compute("fc_shift30", lambda rng, job: _conv_like(
        rng, job, opcode=OP_FULLY_CONNECTED, h=1, w=1, cin=1, cout=4, kh=1, kw=1,
        sh=1, sw=1, pads=(0, 0, 0, 0), zin=0, zout=0, tile=(1, 1), k_slice=1,
        act=(-128, 127),
        params=([1, 0, -1, 2], [0x7FFFFFFF] * 4, [30, 30, 30, 30])))
    compute("fc_shiftm31", lambda rng, job: _conv_like(
        rng, job, opcode=OP_FULLY_CONNECTED, h=1, w=1, cin=1, cout=4, kh=1, kw=1,
        sh=1, sw=1, pads=(0, 0, 0, 0), zin=0, zout=0, tile=(1, 1), k_slice=1,
        act=(-128, 127),
        params=([1000, -1000, 32768, -32768], [0x7FFFFFFF] * 4, [-31, -31, -31, -31])))
    compute("conv_mult_flush", lambda rng, job: _conv_like(
        rng, job, opcode=OP_CONV2D, h=3, w=3, cin=2, cout=4, kh=2, kw=2, sh=1, sw=1,
        pads=(0, 0, 0, 0), zin=0, zout=42, tile=(1, 1), k_slice=4, act=(-128, 127),
        params=([7, -9, 13, -3], [0, 0, 0, 0], [0, 0, 0, 0])))
    # -- ADD with independent scales/zeros and the input alias case
    compute("add_basic", lambda rng, job: _add_like(
        rng, job, h=4, w=5, cin=6, z0=-9, z1=11, zout=5, tile=(2, 2), k_slice=1,
        act=(-128, 127)))
    compute("add_alias", lambda rng, job: _add_like(
        rng, job, h=3, w=3, cin=3, z0=0, z1=0, zout=-20, tile=(1, 3), k_slice=1,
        act=(-128, 127), alias=True))
    compute("add_flush", lambda rng, job: _add_like(
        rng, job, h=2, w=2, cin=2, z0=0, z1=0, zout=127, tile=(1, 1), k_slice=1,
        act=(-128, 127), multipliers=(0, 0, 0, 0, 0, 0)))
    # -- pooling with padding exclusion and tie counts
    compute("maxpool_pad", lambda rng, job: _pool_like(
        rng, job, opcode=OP_MAX_POOL, h=7, w=6, cin=5, kh=3, kw=3, sh=2, sw=2,
        pads=(1, 1, 1, 1), zp=-3, tile=(2, 2), k_slice=9, act=(-128, 127)))
    compute("avgpool_ties", lambda rng, job: _pool_like(
        rng, job, opcode=OP_AVERAGE_POOL, h=5, w=5, cin=4, kh=2, kw=2, sh=1, sw=1,
        pads=(0, 1, 0, 1), zp=0, tile=(2, 2), k_slice=4, act=(-128, 127)))
    compute("avgpool_neg", lambda rng, job: _pool_like(
        rng, job, opcode=OP_AVERAGE_POOL, h=4, w=4, cin=3, kh=3, kw=3, sh=1, sw=1,
        pads=(2, 2, 2, 2), zp=127, tile=(1, 2), k_slice=9, act=(-128, 127)))
    compute("maxpool_k16", lambda rng, job: _pool_like(
        rng, job, opcode=OP_MAX_POOL, h=18, w=17, cin=2, kh=16, kw=16, sh=1, sw=1,
        pads=(0, 0, 0, 0), zp=-128, tile=(1, 1), k_slice=256, act=(-128, 127)))
    # -- GAP
    compute("gap_25x5", lambda rng, job: _gap_like(
        rng, job, h=25, w=5, cin=64, zp=-2, tile=(1, 1), k_slice=125, act=(-128, 127)))
    compute("gap_1x1", lambda rng, job: _gap_like(
        rng, job, h=1, w=1, cin=9, zp=83, tile=(1, 1), k_slice=1, act=(-128, 127)))
    # -- CLAMP
    compute("clamp_basic", lambda rng, job: _clamp_like(
        rng, job, h=6, w=6, cin=8, zp=0, tile=(2, 2), k_slice=1, act=(0, 100)))
    compute("clamp_relu6", lambda rng, job: _clamp_like(
        rng, job, h=3, w=4, cin=5, zp=-128, tile=(3, 1), k_slice=1, act=(0, 6)))

    # -- V012: M/N tails and channel edges
    for tail in (1, 7, 8, 9):
        compute(f"conv_tail{tail}",
                lambda rng, job, tail=tail: _conv_like(
                    rng, job, opcode=OP_CONV2D, h=5, w=max(3, tail), cin=tail, cout=tail,
                    kh=2, kw=2, sh=1, sw=1, pads=(0, 1, 1, 0), zin=0, zout=0,
                    tile=(2, 2), k_slice=min(7, 4 * tail), act=(-128, 127)))
    # -- K multi-chunk carry: full reductions 1023/1024/1025 with 1024-sized slices
    compute("conv_k1023", lambda rng, job: _conv_like(
        rng, job, opcode=OP_CONV2D, h=12, w=12, cin=31, cout=4, kh=3, kw=11, sh=1, sw=1,
        pads=(0, 0, 0, 0), zin=0, zout=0, tile=(2, 2), k_slice=1023, act=(-128, 127)))
    compute("conv_k1024", lambda rng, job: _conv_like(
        rng, job, opcode=OP_CONV2D, h=12, w=12, cin=32, cout=4, kh=4, kw=8, sh=1, sw=1,
        pads=(0, 0, 0, 0), zin=0, zout=0, tile=(2, 4), k_slice=1024, act=(-128, 127)))
    compute("conv_k1025", lambda rng, job: _conv_like(
        rng, job, opcode=OP_CONV2D, h=24, w=24, cin=41, cout=4, kh=5, kw=5, sh=1, sw=1,
        pads=(0, 0, 0, 0), zin=0, zout=0, tile=(2, 4), k_slice=1024, act=(-128, 127)))
    # -- K below/above the A-half reuse boundary
    compute("conv_reuse_edge", lambda rng, job: _conv_like(
        rng, job, opcode=OP_CONV2D, h=16, w=16, cin=8, cout=24, kh=4, kw=4, sh=1, sw=1,
        pads=(1, 1, 1, 1), zin=0, zout=0, tile=(2, 2), k_slice=128, act=(-128, 127)))
    compute("conv_noreuse", lambda rng, job: _conv_like(
        rng, job, opcode=OP_CONV2D, h=8, w=8, cin=32, cout=16, kh=5, kw=5, sh=1, sw=1,
        pads=(0, 0, 0, 0), zin=0, zout=0, tile=(2, 2), k_slice=200, act=(-128, 127)))
    # -- asymmetric zero-point padding
    compute("conv_asym_zp", lambda rng, job: _conv_like(
        rng, job, opcode=OP_CONV2D, h=5, w=4, cin=3, cout=3, kh=3, kw=3, sh=1, sw=1,
        pads=(2, 0, 1, 2), zin=127, zout=-128, tile=(2, 2), k_slice=9, act=(-128, 127)))
    # -- 4096-class maximum legal geometries that fit the private storage
    compute("gap_c4096", lambda rng, job: _gap_like(
        rng, job, h=1, w=1, cin=4096, zp=0, tile=(1, 1), k_slice=1, act=(-128, 127)))
    compute("clamp_c4096", lambda rng, job: _clamp_like(
        rng, job, h=1, w=1, cin=4096, zp=127, tile=(1, 1), k_slice=1, act=(0, 127)))
    compute("conv_c4096_w16k", lambda rng, job: _conv_like(
        rng, job, opcode=OP_CONV2D, h=1, w=1, cin=4, cout=4096, kh=1, kw=1, sh=1, sw=1,
        pads=(0, 0, 0, 0), zin=0, zout=0, tile=(1, 1), k_slice=4, act=(-128, 127)))
    # The 64 KiB parameter tensor spans eight local windows. A second staging
    # pass must rewind to group zero instead of reusing the final window.
    compute("conv_c4096_m3", lambda rng, job: _conv_like(
        rng, job, opcode=OP_CONV2D, h=1, w=3, cin=4, cout=4096, kh=1, kw=1, sh=1, sw=1,
        pads=(0, 0, 0, 0), zin=0, zout=0, tile=(1, 3), k_slice=4, act=(-128, 127)))
    # More than the two 8 KiB W halves must stream by group/K slice without
    # later external chunks overwriting the weights of earlier groups.
    compute("conv_pw_w32k", lambda rng, job: _conv_like(
        rng, job, opcode=OP_CONV2D, h=1, w=2, cin=128, cout=256, kh=1, kw=1,
        sh=1, sw=1, pads=(0, 0, 0, 0), zin=-128, zout=-128, tile=(1, 2),
        k_slice=37, act=(-128, 127)))
    compute("gap_multichunk", lambda rng, job: _gap_like(
        rng, job, h=64, w=32, cin=8, zp=0, tile=(1, 1), k_slice=1000, act=(-128, 127)))
    # -- strided rows (bank-heavy access patterns)
    compute("conv_strided", lambda rng, job: _conv_like(
        rng, job, opcode=OP_CONV2D, h=5, w=5, cin=4, cout=4, kh=3, kw=3, sh=1, sw=1,
        pads=(1, 1, 1, 1), zin=0, zout=0, tile=(2, 2), k_slice=36, act=(-128, 127),
        irow=5 * 4 + 13, orow=5 * 4 + 7))
    # -- equivalent-legal-tiling: same tensor, different TILE_HW/K_SLICE
    def _tiling_pair(rng: _Rng, job: _Job, tile, k_slice) -> None:
        shape = dict(opcode=OP_CONV2D, h=6, w=6, cin=4, cout=8, kh=3, kw=3, sh=1, sw=1,
                     pads=(1, 1, 1, 1), zin=0, zout=0, k_slice=k_slice, act=(-128, 127))
        saved = rng.state
        _conv_like(rng, job, tile=tile, **shape)
        rng.state = saved
    compute("tile_2x2", lambda rng, job: _tiling_pair(rng, job, (2, 2), 36))
    compute("tile_1x6", lambda rng, job: _tiling_pair(rng, job, (1, 6), 36))
    compute("tile_6x1_ks7", lambda rng, job: _tiling_pair(rng, job, (6, 1), 7))

    # -- fixed-model operator shapes: KWS conv10x4 + DW3x3/PW1x1 pair + GAP25x5 + FC64->12
    def _kws_model(rng: _Rng, job: _Job) -> None:
        _conv_like(rng, job, opcode=OP_CONV2D, h=13, w=8, cin=1, cout=8, kh=10, kw=4,
                   sh=2, sw=2, pads=(0, 0, 0, 0), zin=-5, zout=17, tile=(2, 2),
                   k_slice=40, act=(-128, 127))
        _dw_like(rng, job, h=2, w=3, cin=8, sh=1, sw=1, pads=(1, 1, 1, 1), zin=-5,
                 zout=11, tile=(2, 2), k_slice=9, act=(-128, 127))
        _conv_like(rng, job, opcode=OP_CONV2D, h=2, w=3, cin=8, cout=16, kh=1, kw=1,
                   sh=1, sw=1, pads=(0, 0, 0, 0), zin=-5, zout=3, tile=(2, 2), k_slice=8,
                   act=(-128, 127))
        _gap_like(rng, job, h=25, w=5, cin=64, zp=-2, tile=(1, 1), k_slice=125,
                  act=(-128, 127))
        _conv_like(rng, job, opcode=OP_FULLY_CONNECTED, h=1, w=1, cin=64, cout=12, kh=1,
                   kw=1, sh=1, sw=1, pads=(0, 0, 0, 0), zin=3, zout=-7, tile=(1, 1),
                   k_slice=64, act=(-128, 127))
    compute("kws_model", _kws_model)

    # -- fixed-model operator shapes: VWW conv3x3/s2 + DW/PW ladder + GAP3x3 + FC256->2
    def _vww_model(rng: _Rng, job: _Job) -> None:
        _conv_like(rng, job, opcode=OP_CONV2D, h=96, w=96, cin=3, cout=8, kh=3, kw=3,
                   sh=2, sw=2, pads=(1, 1, 1, 1), zin=-1, zout=9, tile=(2, 4), k_slice=27,
                   act=(-128, 127))
        _dw_like(rng, job, h=48, w=48, cin=8, sh=1, sw=1, pads=(1, 1, 1, 1), zin=-1,
                 zout=5, tile=(2, 4), k_slice=9, act=(-128, 127))
        _conv_like(rng, job, opcode=OP_CONV2D, h=48, w=48, cin=8, cout=16, kh=1, kw=1,
                   sh=1, sw=1, pads=(0, 0, 0, 0), zin=-1, zout=13, tile=(2, 2), k_slice=8,
                   act=(-128, 127))
        _gap_like(rng, job, h=3, w=3, cin=16, zp=0, tile=(1, 1), k_slice=9,
                  act=(-128, 127))
        _conv_like(rng, job, opcode=OP_FULLY_CONNECTED, h=1, w=1, cin=256, cout=2, kh=1,
                   kw=1, sh=1, sw=1, pads=(0, 0, 0, 0), zin=0, zout=0, tile=(1, 1),
                   k_slice=256, act=(-128, 127))
    compute("vww_model", _vww_model)

    # -- randomized legal shapes with recorded seeds
    for index in range(12):
        seed = 0xC0FFEE00 + index * 7919
        rng = _Rng(seed)
        opcode = rng.pick((OP_CONV2D, OP_DEPTHWISE3X3, OP_MAX_POOL, OP_AVERAGE_POOL,
                           OP_CLAMP, OP_ADD))

        def _rand(rng: _Rng, job: _Job, opcode=opcode, seed=seed) -> None:
            rng.state = seed
            if opcode == OP_CONV2D:
                kh = 1 + rng.next() % 5
                kw = 1 + rng.next() % 5
                sh = 1 + rng.next() % 2
                sw = 1 + rng.next() % 2
                pads = (rng.next() % kh, rng.next() % kh, rng.next() % kw, rng.next() % kw)
                h = kh + rng.next() % 8
                w = kw + rng.next() % 8
                oh = (h + pads[0] + pads[1] - kh) // sh + 1
                ow = (w + pads[2] + pads[3] - kw) // sw + 1
                if oh < 1 or ow < 1:
                    h, w = kh, kw
                    oh, ow = 1, 1
                    pads = (0, 0, 0, 0)
                tile = _tile(1 + rng.next() % 3, 1 + rng.next() % 3, oh, ow)
                cin = 1 + rng.next() % 17
                _conv_like(rng, job, opcode=opcode, h=h, w=w, cin=cin,
                           cout=1 + rng.next() % 17, kh=kh, kw=kw, sh=sh, sw=sw,
                           pads=pads, zin=rng.int8(), zout=rng.int8(),
                           tile=tile,
                           k_slice=min(1 + rng.next() % 40, kh * kw * cin),
                           act=(-128, 127))
            elif opcode == OP_DEPTHWISE3X3:
                sh = 1 + rng.next() % 2
                sw = 1 + rng.next() % 2
                pads = (rng.next() % 3, rng.next() % 3, rng.next() % 3, rng.next() % 3)
                h = 3 + rng.next() % 8
                w = 3 + rng.next() % 8
                oh = (h + pads[0] + pads[1] - 3) // sh + 1
                ow = (w + pads[2] + pads[3] - 3) // sw + 1
                tile = _tile(1 + rng.next() % 3, 1 + rng.next() % 3, oh, ow)
                _dw_like(rng, job, h=h, w=w,
                         cin=1 + rng.next() % 17, sh=sh, sw=sw, pads=pads,
                         zin=rng.int8(), zout=rng.int8(),
                         tile=tile,
                         k_slice=1 + rng.next() % 9, act=(-128, 127))
            elif opcode in (OP_MAX_POOL, OP_AVERAGE_POOL):
                kh = 1 + rng.next() % 4
                kw = 1 + rng.next() % 4
                sh = 1 + rng.next() % 2
                sw = 1 + rng.next() % 2
                pads = (rng.next() % kh, rng.next() % kh, rng.next() % kw, rng.next() % kw)
                zp = rng.int8()
                h = kh + rng.next() % 8
                w = kw + rng.next() % 8
                oh = (h + pads[0] + pads[1] - kh) // sh + 1
                ow = (w + pads[2] + pads[3] - kw) // sw + 1
                tile = _tile(1 + rng.next() % 3, 1 + rng.next() % 3, oh, ow)
                _pool_like(rng, job, opcode=opcode, h=h,
                           w=w, cin=1 + rng.next() % 17, kh=kh, kw=kw,
                           sh=sh, sw=sw, pads=pads, zp=zp,
                           tile=tile,
                           k_slice=min(1 + rng.next() % 16, kh * kw), act=(-128, 127))
            elif opcode == OP_ADD:
                h = 1 + rng.next() % 6
                w = 1 + rng.next() % 6
                _add_like(rng, job, h=h, w=w,
                          cin=1 + rng.next() % 17, z0=rng.int8(), z1=rng.int8(),
                          zout=rng.int8(),
                          tile=_tile(1 + rng.next() % 3, 1 + rng.next() % 3, h, w),
                          k_slice=1, act=(-128, 127))
            else:
                zp = rng.int8()
                h = 1 + rng.next() % 8
                w = 1 + rng.next() % 8
                _clamp_like(rng, job, h=h, w=w,
                            cin=1 + rng.next() % 33, zp=zp,
                            tile=_tile(1 + rng.next() % 3, 1 + rng.next() % 3, h, w),
                            k_slice=1,
                            act=(rng.pick((-128, -20, 0)), rng.pick((6, 100, 127))))
        compute(f"rand_{index:02d}_{seed:08x}", _rand)

    # -- validation rejections: fail BEFORE execution with correct codes
    _reject(tmp_path, cases, "rej_stride3", OP_CONV2D,
            lambda w: w.__setitem__(12, (w[12] & 0xFF00_FFFF) | (3 << 16)))
    _reject(tmp_path, cases, "rej_dw_mult", OP_DEPTHWISE3X3,
            lambda w: w.__setitem__(7, w[7] + (1 << 16)))
    _reject(tmp_path, cases, "rej_add_bcast", OP_ADD,
            lambda w: w.__setitem__(8, w[8] + 1))
    _reject(tmp_path, cases, "rej_clamp_shape", OP_CLAMP,
            lambda w: w.__setitem__(8, w[8] + 1))
    _reject(tmp_path, cases, "rej_pool_zp", OP_CLAMP,
            lambda w: w.__setitem__(22, (w[22] + 1) & 0xFF))

    # -- arithmetic faults: checked INT32 accumulate overflow (code 7)
    def _arith_overflow(rng: _Rng, job: _Job) -> None:
        from npu_reference import INT32_MAX
        bias = [INT32_MAX] + [rng.int32() for _ in range(7)]
        mults = [rng.nonneg31() for _ in range(8)]
        shifts = [rng.shift() for _ in range(8)]
        _conv_like(rng, job, opcode=OP_CONV2D, h=4, w=4, cin=4, cout=8, kh=2, kw=2,
                   sh=1, sw=1, pads=(0, 0, 0, 0), zin=-128, zout=0, tile=(2, 2),
                   k_slice=16, act=(-128, 127), params=(bias, mults, shifts),
                   allow_fault=True)
        job.fcode = F_ARITHMETIC
        job.fdesc = 0
        job.faddr = 0
        job.scen = SCEN_ARITH
    compute("arith_acc_overflow", _arith_overflow)

    # -- arithmetic fault: checked requantizer left shift (code 7)
    def _arith_shift(rng: _Rng, job: _Job) -> None:
        bias = [1 << 20] * 8
        mults = [1 << 20] * 8
        shifts = [30] * 8
        _conv_like(rng, job, opcode=OP_CONV2D, h=3, w=3, cin=2, cout=8, kh=2, kw=2,
                   sh=1, sw=1, pads=(0, 0, 0, 0), zin=-128, zout=0, tile=(1, 1),
                   k_slice=8, act=(-128, 127), params=(bias, mults, shifts),
                   allow_fault=True)
        job.fcode = F_ARITHMETIC
        job.fdesc = 0
        job.faddr = 0
        job.scen = SCEN_ARITH
    compute("arith_shift_overflow", _arith_shift)

    return cases


@pytest.mark.parametrize("simulator", ("iverilog", "verilator"))
def test_npu_operator(tmp_path: Path, simulator: str) -> None:
    tools = _tools()
    command = _build_sim(
        tools,
        simulator,
        tmp_path,
        f"npu_operator_{simulator}",
        "npu_operator_tb",
        OPERATOR_TB,
        P4_SOURCES,
    )
    for plusargs in _operator_cases(tmp_path):
        _run(command, plusargs, "NPU operator test passed")
