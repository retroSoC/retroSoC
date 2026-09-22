"""Mini NPU descriptor ABI 1.0 encode/decode and validation."""

from __future__ import annotations

import struct
from dataclasses import dataclass
from typing import Final

# Host-side offline validator for docs/ip/npu.md "Descriptor ABI 1.0".
#
# Fault classification follows the spec FAULT_CODE table:
#   FAULT_DESCRIPTOR (1): malformed record or parameter encoding decidable from the
#       record alone -- bad version, nonzero reserved bits/words, nonzero upper bits
#       of signed-byte fields, out-of-range zero points or bounds, ACT_MIN > ACT_MAX,
#       nonzero unused operation fields, K_SLICE outside 1..1024, TILE_H/TILE_W
#       outside 1..8 or product above 8, inexact WEIGHT_BYTES/PARAM_BYTES, missing
#       required bases, and misaligned PARAM_BASE/WEIGHT_BASE.
#   FAULT_UNSUPPORTED (2): undefined opcode, or an operator-profile capability
#       violation on a well-formed record -- kernel/stride limits, the fixed
#       kernel/stride and padding words of FC/ADD/CLAMP, non-1x1 FC geometry,
#       ADD/CLAMP shape changes (no broadcasting), Cout != Cin where required,
#       unequal pool/GAP/CLAMP zero points, and K_SLICE above the full reduction.
#   FAULT_RANGE (3): address, span, geometry, and overlap failures -- dimensions
#       outside 1..4096, zero kernel/stride lanes, pad >= kernel, non-positive or
#       mismatching computed output extent, tile above OH/OW, row stride below W*C,
#       used span above the declared allocation, 32-bit address wrap, and any
#       illegal allocation overlap.
#
# validate_descriptor checks in a deterministic order: structural record, opcode
# support, unused operation fields, geometry/dimensions, per-operator constraints,
# strides/spans, alignment, overlap. The first violation raises DescriptorError.

ABI_VERSION: Final = 0x0100
DESCRIPTOR_WORDS: Final = 32
DESCRIPTOR_BYTES: Final = 4 * DESCRIPTOR_WORDS
MAX_K_SLICE: Final = 1024
MAX_DIMENSION: Final = 4096
MAX_TILE: Final = 8
BASE_ALIGNMENT: Final = 64
ADD_PARAM_BYTES: Final = 32
PARAM_RECORD_BYTES: Final = 16
UINT32_MODULUS: Final = 1 << 32

FAULT_DESCRIPTOR: Final = 1
FAULT_UNSUPPORTED: Final = 2
FAULT_RANGE: Final = 3

OP_CONV2D: Final = 1
OP_DEPTHWISE3X3: Final = 2
OP_FULLY_CONNECTED: Final = 3
OP_ADD: Final = 4
OP_MAX_POOL: Final = 5
OP_AVERAGE_POOL: Final = 6
OP_GLOBAL_AVERAGE_POOL: Final = 7
OP_CLAMP: Final = 8

OPCODE_NAMES: Final = {
    OP_CONV2D: "CONV2D",
    OP_DEPTHWISE3X3: "DEPTHWISE3X3",
    OP_FULLY_CONNECTED: "FULLY_CONNECTED",
    OP_ADD: "ADD",
    OP_MAX_POOL: "MAX_POOL",
    OP_AVERAGE_POOL: "AVERAGE_POOL",
    OP_GLOBAL_AVERAGE_POOL: "GLOBAL_AVERAGE_POOL",
    OP_CLAMP: "CLAMP",
}

WORD_VERSION_OPCODE: Final = 0
WORD_RESERVED1: Final = 1
WORD_INPUT0_BASE: Final = 2
WORD_INPUT1_BASE: Final = 3
WORD_OUTPUT_BASE: Final = 4
WORD_PARAM_BASE: Final = 5
WORD_INPUT_HW: Final = 6
WORD_CHANNELS: Final = 7
WORD_OUTPUT_HW: Final = 8
WORD_INPUT0_ROW_BYTES: Final = 9
WORD_OUTPUT_ROW_BYTES: Final = 10
WORD_INPUT1_ROW_BYTES: Final = 11
WORD_KERNEL_STRIDE: Final = 12
WORD_PADDING: Final = 13
WORD_TILE_HW: Final = 14
WORD_K_SLICE: Final = 15
WORD_INPUT0_BYTES: Final = 16
WORD_INPUT1_BYTES: Final = 17
WORD_OUTPUT_BYTES: Final = 18
WORD_PARAM_BYTES: Final = 19
WORD_INPUT0_ZERO: Final = 20
WORD_INPUT1_ZERO: Final = 21
WORD_OUTPUT_ZERO: Final = 22
WORD_ACTIVATION_BOUNDS: Final = 23
WORD_WEIGHT_BASE: Final = 24
WORD_WEIGHT_BYTES: Final = 25

_KERNEL_OPS: Final = (OP_CONV2D, OP_DEPTHWISE3X3, OP_MAX_POOL, OP_AVERAGE_POOL)
_WEIGHTED_OPS: Final = (OP_CONV2D, OP_DEPTHWISE3X3, OP_FULLY_CONNECTED)
_PARAMETERIZED_OPS: Final = _WEIGHTED_OPS + (OP_ADD,)
_UNIT_KERNEL_STRIDE: Final = 0x01010101


class DescriptorError(ValueError):
    """Descriptor validation failure.

    Attributes:
        code: FAULT_DESCRIPTOR (1), FAULT_UNSUPPORTED (2), or FAULT_RANGE (3),
            matching the FAULT_CODE table in docs/ip/npu.md.
        word: Zero-based index of the first offending descriptor word, or None
            when the failure is a relationship between words (overlap).
    """

    def __init__(self, code: int, word: int | None, message: str) -> None:
        super().__init__(message)
        self.code = code
        self.word = word


def _decode_zero_point(word: int) -> int:
    if word <= 0xFF:
        return word - 0x100 if word >= 0x80 else word
    return word  # nonzero upper bits: keep the raw word for validation to reject


def _encode_signed_byte(value: int) -> int:
    return value & 0xFF if value < 0 else value


def _decode_bounds(word: int) -> tuple[int, int]:
    act_min = _decode_zero_point(word & 0xFF)
    act_max = _decode_zero_point((word >> 8) & 0xFF)
    if word > 0xFFFF:
        act_min = word  # nonzero upper half: keep the raw word for validation
    return act_min, act_max


def _encode_bounds(act_min: int, act_max: int) -> int:
    return _encode_signed_byte(act_min) | (_encode_signed_byte(act_max) << 8)


@dataclass
class Descriptor:
    """One 128-byte ABI 1.0 record, one field per word (word 23 is split).

    Fields are the packed little-endian words of the wire format; zero points
    and activation bounds are stored as signed integers. from_bytes is
    lossless: a signed-byte word with nonzero upper bits is kept as its raw
    unsigned value so validate_descriptor can reject the encoding, and
    to_bytes reproduces the original record byte-exactly.
    """

    version_opcode: int = 0
    reserved1: int = 0
    input0_base: int = 0
    input1_base: int = 0
    output_base: int = 0
    param_base: int = 0
    input_hw: int = 0
    channels: int = 0
    output_hw: int = 0
    input0_row_bytes: int = 0
    output_row_bytes: int = 0
    input1_row_bytes: int = 0
    kernel_stride: int = 0
    padding: int = 0
    tile_hw: int = 0
    k_slice: int = 0
    input0_bytes: int = 0
    input1_bytes: int = 0
    output_bytes: int = 0
    param_bytes: int = 0
    input0_zero: int = 0
    input1_zero: int = 0
    output_zero: int = 0
    act_min: int = 0
    act_max: int = 0
    weight_base: int = 0
    weight_bytes: int = 0
    reserved26: int = 0
    reserved27: int = 0
    reserved28: int = 0
    reserved29: int = 0
    reserved30: int = 0
    reserved31: int = 0

    @property
    def version(self) -> int:
        return (self.version_opcode >> 16) & 0xFFFF

    @property
    def opcode(self) -> int:
        return self.version_opcode & 0xFF

    @property
    def h(self) -> int:
        return self.input_hw & 0xFFFF

    @property
    def w(self) -> int:
        return (self.input_hw >> 16) & 0xFFFF

    @property
    def cin(self) -> int:
        return self.channels & 0xFFFF

    @property
    def cout(self) -> int:
        return (self.channels >> 16) & 0xFFFF

    @property
    def oh(self) -> int:
        return self.output_hw & 0xFFFF

    @property
    def ow(self) -> int:
        return (self.output_hw >> 16) & 0xFFFF

    @property
    def kh(self) -> int:
        return self.kernel_stride & 0xFF

    @property
    def kw(self) -> int:
        return (self.kernel_stride >> 8) & 0xFF

    @property
    def sh(self) -> int:
        return (self.kernel_stride >> 16) & 0xFF

    @property
    def sw(self) -> int:
        return (self.kernel_stride >> 24) & 0xFF

    @property
    def pad_top(self) -> int:
        return self.padding & 0xFF

    @property
    def pad_bottom(self) -> int:
        return (self.padding >> 8) & 0xFF

    @property
    def pad_left(self) -> int:
        return (self.padding >> 16) & 0xFF

    @property
    def pad_right(self) -> int:
        return (self.padding >> 24) & 0xFF

    @property
    def tile_h(self) -> int:
        return self.tile_hw & 0xFF

    @property
    def tile_w(self) -> int:
        return (self.tile_hw >> 8) & 0xFF

    def _words(self) -> list[int]:
        return [
            self.version_opcode,
            self.reserved1,
            self.input0_base,
            self.input1_base,
            self.output_base,
            self.param_base,
            self.input_hw,
            self.channels,
            self.output_hw,
            self.input0_row_bytes,
            self.output_row_bytes,
            self.input1_row_bytes,
            self.kernel_stride,
            self.padding,
            self.tile_hw,
            self.k_slice,
            self.input0_bytes,
            self.input1_bytes,
            self.output_bytes,
            self.param_bytes,
            _encode_signed_byte(self.input0_zero),
            _encode_signed_byte(self.input1_zero),
            _encode_signed_byte(self.output_zero),
            _encode_bounds(self.act_min, self.act_max),
            self.weight_base,
            self.weight_bytes,
            self.reserved26,
            self.reserved27,
            self.reserved28,
            self.reserved29,
            self.reserved30,
            self.reserved31,
        ]

    def to_bytes(self) -> bytes:
        """Encode as the 32 little-endian words of the wire record."""
        return struct.pack(f"<{DESCRIPTOR_WORDS}I", *self._words())

    @classmethod
    def from_bytes(cls, data: bytes) -> Descriptor:
        """Decode a 128-byte record; fails only on a wrong byte length."""
        if len(data) != DESCRIPTOR_BYTES:
            raise ValueError(
                f"descriptor record is {len(data)} bytes, expected {DESCRIPTOR_BYTES}"
            )
        words = struct.unpack(f"<{DESCRIPTOR_WORDS}I", data)
        act_min, act_max = _decode_bounds(words[WORD_ACTIVATION_BOUNDS])
        return cls(
            version_opcode=words[WORD_VERSION_OPCODE],
            reserved1=words[WORD_RESERVED1],
            input0_base=words[WORD_INPUT0_BASE],
            input1_base=words[WORD_INPUT1_BASE],
            output_base=words[WORD_OUTPUT_BASE],
            param_base=words[WORD_PARAM_BASE],
            input_hw=words[WORD_INPUT_HW],
            channels=words[WORD_CHANNELS],
            output_hw=words[WORD_OUTPUT_HW],
            input0_row_bytes=words[WORD_INPUT0_ROW_BYTES],
            output_row_bytes=words[WORD_OUTPUT_ROW_BYTES],
            input1_row_bytes=words[WORD_INPUT1_ROW_BYTES],
            kernel_stride=words[WORD_KERNEL_STRIDE],
            padding=words[WORD_PADDING],
            tile_hw=words[WORD_TILE_HW],
            k_slice=words[WORD_K_SLICE],
            input0_bytes=words[WORD_INPUT0_BYTES],
            input1_bytes=words[WORD_INPUT1_BYTES],
            output_bytes=words[WORD_OUTPUT_BYTES],
            param_bytes=words[WORD_PARAM_BYTES],
            input0_zero=_decode_zero_point(words[WORD_INPUT0_ZERO]),
            input1_zero=_decode_zero_point(words[WORD_INPUT1_ZERO]),
            output_zero=_decode_zero_point(words[WORD_OUTPUT_ZERO]),
            act_min=act_min,
            act_max=act_max,
            weight_base=words[WORD_WEIGHT_BASE],
            weight_bytes=words[WORD_WEIGHT_BYTES],
            reserved26=words[26],
            reserved27=words[27],
            reserved28=words[28],
            reserved29=words[29],
            reserved30=words[30],
            reserved31=words[31],
        )


def used_span(h: int, w: int, c: int, row_bytes: int) -> int:
    """Accessible bytes of one operand: (h - 1) * row_bytes + w * c."""
    return (h - 1) * row_bytes + w * c


def full_reduction(desc: Descriptor) -> int:
    """Full K of the operator: the length of one complete output reduction."""
    opcode = desc.opcode
    if opcode == OP_CONV2D:
        return desc.kh * desc.kw * desc.cin
    if opcode == OP_DEPTHWISE3X3:
        return 9
    if opcode == OP_FULLY_CONNECTED:
        return desc.cin
    if opcode in (OP_MAX_POOL, OP_AVERAGE_POOL):
        return desc.kh * desc.kw
    if opcode == OP_GLOBAL_AVERAGE_POOL:
        return desc.h * desc.w
    return 1  # ADD and CLAMP reduce over a single element


def check_no_overlap(
    ranges: list[tuple[int, int, str]],
    *,
    allow_alias: set[frozenset[str]] | None = None,
) -> None:
    """Raise FAULT_RANGE on the first overlapping pair of [base, base+bytes) ranges."""
    allowed = allow_alias if allow_alias is not None else set()
    for index, (base_a, size_a, name_a) in enumerate(ranges):
        if size_a <= 0:
            continue
        for base_b, size_b, name_b in ranges[index + 1 :]:
            if size_b <= 0:
                continue
            if frozenset((name_a, name_b)) in allowed:
                continue
            if base_a < base_b + size_b and base_b < base_a + size_a:
                raise DescriptorError(
                    FAULT_RANGE,
                    None,
                    f"illegal overlap: {name_a} [0x{base_a:x}, 0x{base_a + size_a:x})"
                    f" vs {name_b} [0x{base_b:x}, 0x{base_b + size_b:x})",
                )


def _check_structure(desc: Descriptor) -> None:
    if desc.version != ABI_VERSION:
        raise DescriptorError(
            FAULT_DESCRIPTOR,
            WORD_VERSION_OPCODE,
            f"version 0x{desc.version:04x} is not ABI {ABI_VERSION:#06x}",
        )
    if (desc.version_opcode >> 8) & 0xFF:
        raise DescriptorError(
            FAULT_DESCRIPTOR, WORD_VERSION_OPCODE, "VERSION_OPCODE bits15:8 must be zero"
        )
    if desc.reserved1:
        raise DescriptorError(FAULT_DESCRIPTOR, WORD_RESERVED1, "word 1 must be zero")
    reserved_tail = (
        desc.reserved26,
        desc.reserved27,
        desc.reserved28,
        desc.reserved29,
        desc.reserved30,
        desc.reserved31,
    )
    for offset, value in enumerate(reserved_tail):
        if value:
            raise DescriptorError(
                FAULT_DESCRIPTOR, 26 + offset, f"reserved word {26 + offset} must be zero"
            )
    if desc.tile_hw >> 16:
        raise DescriptorError(
            FAULT_DESCRIPTOR, WORD_TILE_HW, "TILE_HW upper half must be zero"
        )
    for value, word, name in (
        (desc.input0_zero, WORD_INPUT0_ZERO, "INPUT0_ZERO"),
        (desc.output_zero, WORD_OUTPUT_ZERO, "OUTPUT_ZERO"),
    ):
        if not -128 <= value <= 127:
            raise DescriptorError(
                FAULT_DESCRIPTOR, word, f"{name} is not a canonical signed byte"
            )
    if not -128 <= desc.act_min <= 127 or not -128 <= desc.act_max <= 127:
        raise DescriptorError(
            FAULT_DESCRIPTOR,
            WORD_ACTIVATION_BOUNDS,
            "activation bounds are not canonical signed bytes",
        )
    if desc.act_min > desc.act_max:
        raise DescriptorError(
            FAULT_DESCRIPTOR,
            WORD_ACTIVATION_BOUNDS,
            f"ACT_MIN {desc.act_min} exceeds ACT_MAX {desc.act_max}",
        )
    if not 1 <= desc.tile_h <= MAX_TILE or not 1 <= desc.tile_w <= MAX_TILE:
        raise DescriptorError(
            FAULT_DESCRIPTOR,
            WORD_TILE_HW,
            f"TILE_H/TILE_W {desc.tile_h}x{desc.tile_w} outside 1..{MAX_TILE}",
        )
    if desc.tile_h * desc.tile_w > MAX_TILE:
        raise DescriptorError(
            FAULT_DESCRIPTOR,
            WORD_TILE_HW,
            f"tile {desc.tile_h}x{desc.tile_w} exceeds {MAX_TILE} output positions",
        )
    if not 1 <= desc.k_slice <= MAX_K_SLICE:
        raise DescriptorError(
            FAULT_DESCRIPTOR,
            WORD_K_SLICE,
            f"K_SLICE {desc.k_slice} outside 1..{MAX_K_SLICE}",
        )


def _check_unused_fields(desc: Descriptor, opcode: int) -> None:
    if opcode != OP_ADD:
        for value, word, name in (
            (desc.input1_base, WORD_INPUT1_BASE, "INPUT1_BASE"),
            (desc.input1_row_bytes, WORD_INPUT1_ROW_BYTES, "INPUT1_ROW_BYTES"),
            (desc.input1_bytes, WORD_INPUT1_BYTES, "INPUT1_BYTES"),
            (desc.input1_zero, WORD_INPUT1_ZERO, "INPUT1_ZERO"),
        ):
            if value != 0:
                raise DescriptorError(
                    FAULT_DESCRIPTOR, word, f"{name} is only used by ADD and must be zero"
                )
    if opcode not in _WEIGHTED_OPS:
        for value, word, name in (
            (desc.weight_base, WORD_WEIGHT_BASE, "WEIGHT_BASE"),
            (desc.weight_bytes, WORD_WEIGHT_BYTES, "WEIGHT_BYTES"),
        ):
            if value != 0:
                raise DescriptorError(
                    FAULT_DESCRIPTOR, word, f"{name} is unused by {OPCODE_NAMES[opcode]}"
                )
    if opcode not in _PARAMETERIZED_OPS:
        for value, word, name in (
            (desc.param_base, WORD_PARAM_BASE, "PARAM_BASE"),
            (desc.param_bytes, WORD_PARAM_BYTES, "PARAM_BYTES"),
        ):
            if value != 0:
                raise DescriptorError(
                    FAULT_DESCRIPTOR, word, f"{name} is unused by {OPCODE_NAMES[opcode]}"
                )
    if opcode == OP_GLOBAL_AVERAGE_POOL:
        if desc.kernel_stride != 0:
            raise DescriptorError(
                FAULT_DESCRIPTOR,
                WORD_KERNEL_STRIDE,
                "GLOBAL_AVERAGE_POOL kernel/stride word must be zero",
            )
        if desc.padding != 0:
            raise DescriptorError(
                FAULT_DESCRIPTOR, WORD_PADDING, "GLOBAL_AVERAGE_POOL padding must be zero"
            )


def _check_geometry(desc: Descriptor, opcode: int) -> None:
    for value, word, name in (
        (desc.h, WORD_INPUT_HW, "H"),
        (desc.w, WORD_INPUT_HW, "W"),
        (desc.cin, WORD_CHANNELS, "Cin"),
        (desc.cout, WORD_CHANNELS, "Cout"),
        (desc.oh, WORD_OUTPUT_HW, "OH"),
        (desc.ow, WORD_OUTPUT_HW, "OW"),
    ):
        if not 1 <= value <= MAX_DIMENSION:
            raise DescriptorError(
                FAULT_RANGE, word, f"{name} {value} outside 1..{MAX_DIMENSION}"
            )
    if opcode in _KERNEL_OPS:
        if desc.kh < 1 or desc.kw < 1 or desc.sh < 1 or desc.sw < 1:
            raise DescriptorError(
                FAULT_RANGE,
                WORD_KERNEL_STRIDE,
                "kernel/stride lanes must be nonzero for a kernel operator",
            )
        if (
            desc.pad_top >= desc.kh
            or desc.pad_bottom >= desc.kh
            or desc.pad_left >= desc.kw
            or desc.pad_right >= desc.kw
        ):
            raise DescriptorError(
                FAULT_RANGE,
                WORD_PADDING,
                "padding must be strictly less than the kernel dimension",
            )
        expect_oh = (desc.h + desc.pad_top + desc.pad_bottom - desc.kh) // desc.sh + 1
        expect_ow = (desc.w + desc.pad_left + desc.pad_right - desc.kw) // desc.sw + 1
        if expect_oh <= 0 or expect_ow <= 0:
            raise DescriptorError(
                FAULT_RANGE,
                WORD_OUTPUT_HW,
                f"computed output extent {expect_oh}x{expect_ow} is not positive",
            )
        if desc.oh != expect_oh or desc.ow != expect_ow:
            raise DescriptorError(
                FAULT_RANGE,
                WORD_OUTPUT_HW,
                f"descriptor output {desc.oh}x{desc.ow} does not match computed"
                f" {expect_oh}x{expect_ow}",
            )


def _check_kernel_stride(desc: Descriptor, kernel_max: int) -> None:
    if not 1 <= desc.kh <= kernel_max or not 1 <= desc.kw <= kernel_max:
        raise DescriptorError(
            FAULT_UNSUPPORTED,
            WORD_KERNEL_STRIDE,
            f"kernel {desc.kh}x{desc.kw} outside 1..{kernel_max}",
        )
    if desc.sh not in (1, 2) or desc.sw not in (1, 2):
        raise DescriptorError(
            FAULT_UNSUPPORTED,
            WORD_KERNEL_STRIDE,
            f"stride {desc.sh}x{desc.sw} is not 1 or 2",
        )


def _check_operator(desc: Descriptor, opcode: int) -> None:
    if opcode == OP_CONV2D:
        _check_kernel_stride(desc, 16)
    elif opcode == OP_DEPTHWISE3X3:
        if desc.kh != 3 or desc.kw != 3:
            raise DescriptorError(
                FAULT_UNSUPPORTED,
                WORD_KERNEL_STRIDE,
                f"DEPTHWISE3X3 kernel is {desc.kh}x{desc.kw}, not 3x3",
            )
        _check_kernel_stride(desc, 16)
        if desc.cout != desc.cin:
            raise DescriptorError(
                FAULT_UNSUPPORTED,
                WORD_CHANNELS,
                "depthwise multiplier 1 requires Cout == Cin",
            )
    elif opcode == OP_FULLY_CONNECTED:
        if desc.h != 1 or desc.w != 1:
            raise DescriptorError(
                FAULT_UNSUPPORTED, WORD_INPUT_HW, "FULLY_CONNECTED requires H == W == 1"
            )
        if desc.oh != 1 or desc.ow != 1:
            raise DescriptorError(
                FAULT_UNSUPPORTED, WORD_OUTPUT_HW, "FULLY_CONNECTED requires OH == OW == 1"
            )
        if desc.kernel_stride != _UNIT_KERNEL_STRIDE:
            raise DescriptorError(
                FAULT_UNSUPPORTED,
                WORD_KERNEL_STRIDE,
                "FULLY_CONNECTED kernel/stride word must be 0x01010101",
            )
        if desc.padding != 0:
            raise DescriptorError(
                FAULT_UNSUPPORTED, WORD_PADDING, "FULLY_CONNECTED padding must be zero"
            )
    elif opcode == OP_ADD:
        if not -128 <= desc.input1_zero <= 127:
            raise DescriptorError(
                FAULT_DESCRIPTOR, WORD_INPUT1_ZERO, "INPUT1_ZERO is not a signed byte"
            )
        if desc.input1_base == 0:
            raise DescriptorError(
                FAULT_DESCRIPTOR, WORD_INPUT1_BASE, "ADD requires INPUT1_BASE"
            )
        if desc.oh != desc.h or desc.ow != desc.w:
            raise DescriptorError(
                FAULT_UNSUPPORTED,
                WORD_OUTPUT_HW,
                "ADD does not broadcast: output geometry must equal input geometry",
            )
        if desc.cout != desc.cin:
            raise DescriptorError(
                FAULT_UNSUPPORTED, WORD_CHANNELS, "ADD requires Cout == Cin"
            )
        if desc.kernel_stride != _UNIT_KERNEL_STRIDE:
            raise DescriptorError(
                FAULT_UNSUPPORTED,
                WORD_KERNEL_STRIDE,
                "ADD kernel/stride word must be 0x01010101",
            )
        if desc.padding != 0:
            raise DescriptorError(
                FAULT_UNSUPPORTED, WORD_PADDING, "ADD padding must be zero"
            )
    elif opcode in (OP_MAX_POOL, OP_AVERAGE_POOL):
        _check_kernel_stride(desc, 16)
        if desc.cout != desc.cin:
            raise DescriptorError(
                FAULT_UNSUPPORTED, WORD_CHANNELS, "pooling requires Cout == Cin"
            )
        if desc.input0_zero != desc.output_zero:
            raise DescriptorError(
                FAULT_UNSUPPORTED,
                WORD_OUTPUT_ZERO,
                "pooling requires equal input/output zero points",
            )
    elif opcode == OP_GLOBAL_AVERAGE_POOL:
        if desc.oh != 1 or desc.ow != 1:
            raise DescriptorError(
                FAULT_UNSUPPORTED,
                WORD_OUTPUT_HW,
                "GLOBAL_AVERAGE_POOL requires OH == OW == 1",
            )
        if desc.cout != desc.cin:
            raise DescriptorError(
                FAULT_UNSUPPORTED, WORD_CHANNELS, "GLOBAL_AVERAGE_POOL requires Cout == Cin"
            )
        if desc.input0_zero != desc.output_zero:
            raise DescriptorError(
                FAULT_UNSUPPORTED,
                WORD_OUTPUT_ZERO,
                "GLOBAL_AVERAGE_POOL requires equal input/output zero points",
            )
    elif opcode == OP_CLAMP:
        if desc.oh != desc.h or desc.ow != desc.w:
            raise DescriptorError(
                FAULT_UNSUPPORTED,
                WORD_OUTPUT_HW,
                "CLAMP requires identical input/output geometry",
            )
        if desc.cout != desc.cin:
            raise DescriptorError(
                FAULT_UNSUPPORTED, WORD_CHANNELS, "CLAMP requires Cout == Cin"
            )
        if desc.input0_zero != desc.output_zero:
            raise DescriptorError(
                FAULT_UNSUPPORTED,
                WORD_OUTPUT_ZERO,
                "CLAMP requires identical input/output quantization",
            )
        if desc.kernel_stride != _UNIT_KERNEL_STRIDE:
            raise DescriptorError(
                FAULT_UNSUPPORTED,
                WORD_KERNEL_STRIDE,
                "CLAMP kernel/stride word must be 0x01010101",
            )
        if desc.padding != 0:
            raise DescriptorError(
                FAULT_UNSUPPORTED, WORD_PADDING, "CLAMP padding must be zero"
            )

    full_k = full_reduction(desc)
    if desc.k_slice > full_k:
        raise DescriptorError(
            FAULT_UNSUPPORTED,
            WORD_K_SLICE,
            f"K_SLICE {desc.k_slice} exceeds the full reduction {full_k}",
        )
    if desc.tile_h > desc.oh or desc.tile_w > desc.ow:
        raise DescriptorError(
            FAULT_RANGE,
            WORD_TILE_HW,
            f"tile {desc.tile_h}x{desc.tile_w} exceeds output {desc.oh}x{desc.ow}",
        )

    if opcode in _WEIGHTED_OPS:
        if desc.weight_base == 0:
            raise DescriptorError(
                FAULT_DESCRIPTOR, WORD_WEIGHT_BASE, "packed weights are required"
            )
        if opcode == OP_DEPTHWISE3X3:
            expect_weight_bytes = ((desc.cin + 7) // 8) * 72
        else:
            expect_weight_bytes = ((desc.cout + 7) // 8) * full_k * 8
        if desc.weight_bytes != expect_weight_bytes:
            raise DescriptorError(
                FAULT_DESCRIPTOR,
                WORD_WEIGHT_BYTES,
                f"WEIGHT_BYTES {desc.weight_bytes} is not the exact packed length"
                f" {expect_weight_bytes}",
            )
        if desc.param_base == 0:
            raise DescriptorError(
                FAULT_DESCRIPTOR, WORD_PARAM_BASE, "parameter array is required"
            )
        if desc.param_bytes != desc.cout * PARAM_RECORD_BYTES:
            raise DescriptorError(
                FAULT_DESCRIPTOR,
                WORD_PARAM_BYTES,
                f"PARAM_BYTES {desc.param_bytes} is not Cout*16"
                f" ({desc.cout * PARAM_RECORD_BYTES})",
            )
    elif opcode == OP_ADD:
        if desc.param_base == 0:
            raise DescriptorError(
                FAULT_DESCRIPTOR, WORD_PARAM_BASE, "ADD parameter array is required"
            )
        if desc.param_bytes != ADD_PARAM_BYTES:
            raise DescriptorError(
                FAULT_DESCRIPTOR,
                WORD_PARAM_BYTES,
                f"ADD PARAM_BYTES {desc.param_bytes} is not {ADD_PARAM_BYTES}",
            )


def _check_strides_and_spans(desc: Descriptor, opcode: int) -> None:
    min_input_row = desc.w * desc.cin
    if desc.input0_row_bytes < min_input_row:
        raise DescriptorError(
            FAULT_RANGE,
            WORD_INPUT0_ROW_BYTES,
            f"INPUT0_ROW_BYTES {desc.input0_row_bytes} is below W*Cin {min_input_row}",
        )
    min_output_row = desc.ow * desc.cout
    if desc.output_row_bytes < min_output_row:
        raise DescriptorError(
            FAULT_RANGE,
            WORD_OUTPUT_ROW_BYTES,
            f"OUTPUT_ROW_BYTES {desc.output_row_bytes} is below OW*Cout {min_output_row}",
        )
    if opcode == OP_ADD and desc.input1_row_bytes < min_input_row:
        raise DescriptorError(
            FAULT_RANGE,
            WORD_INPUT1_ROW_BYTES,
            f"INPUT1_ROW_BYTES {desc.input1_row_bytes} is below W*Cin {min_input_row}",
        )
    operands = [
        (
            "INPUT0",
            desc.input0_base,
            used_span(desc.h, desc.w, desc.cin, desc.input0_row_bytes),
            desc.input0_bytes,
            WORD_INPUT0_BASE,
            WORD_INPUT0_BYTES,
        ),
    ]
    if opcode == OP_ADD:
        operands.append(
            (
                "INPUT1",
                desc.input1_base,
                used_span(desc.h, desc.w, desc.cin, desc.input1_row_bytes),
                desc.input1_bytes,
                WORD_INPUT1_BASE,
                WORD_INPUT1_BYTES,
            )
        )
    operands.append(
        (
            "OUTPUT",
            desc.output_base,
            used_span(desc.oh, desc.ow, desc.cout, desc.output_row_bytes),
            desc.output_bytes,
            WORD_OUTPUT_BASE,
            WORD_OUTPUT_BYTES,
        )
    )
    for name, base, span, allocated, base_word, bytes_word in operands:
        if span > allocated:
            raise DescriptorError(
                FAULT_RANGE,
                bytes_word,
                f"{name} used span {span} exceeds declared allocation {allocated}",
            )
        if base + span > UINT32_MODULUS:
            raise DescriptorError(
                FAULT_RANGE,
                base_word,
                f"{name} used span wraps the 32-bit address space",
            )
        if base + allocated > UINT32_MODULUS:
            raise DescriptorError(
                FAULT_RANGE,
                base_word,
                f"{name} allocation wraps the 32-bit address space",
            )
    for name, base, size, base_word in (
        ("WEIGHT", desc.weight_base, desc.weight_bytes, WORD_WEIGHT_BASE),
        ("PARAM", desc.param_base, desc.param_bytes, WORD_PARAM_BASE),
    ):
        if size and base + size > UINT32_MODULUS:
            raise DescriptorError(
                FAULT_RANGE,
                base_word,
                f"{name} allocation wraps the 32-bit address space",
            )


def _check_alignment(desc: Descriptor) -> None:
    if desc.param_base and desc.param_base % BASE_ALIGNMENT:
        raise DescriptorError(
            FAULT_DESCRIPTOR, WORD_PARAM_BASE, "PARAM_BASE must be 64-byte aligned"
        )
    if desc.weight_base and desc.weight_base % BASE_ALIGNMENT:
        raise DescriptorError(
            FAULT_DESCRIPTOR, WORD_WEIGHT_BASE, "WEIGHT_BASE must be 64-byte aligned"
        )


def _check_overlap(
    desc: Descriptor, opcode: int, descriptor_region: tuple[int, int] | None
) -> None:
    ranges: list[tuple[int, int, str]] = [
        (desc.input0_base, desc.input0_bytes, "input0"),
        (desc.output_base, desc.output_bytes, "output"),
    ]
    if opcode == OP_ADD:
        ranges.append((desc.input1_base, desc.input1_bytes, "input1"))
    if desc.weight_bytes:
        ranges.append((desc.weight_base, desc.weight_bytes, "weights"))
    if desc.param_bytes:
        ranges.append((desc.param_base, desc.param_bytes, "params"))
    if descriptor_region is not None:
        region_base, region_bytes = descriptor_region
        if region_bytes and region_base + region_bytes > UINT32_MODULUS:
            raise DescriptorError(
                FAULT_RANGE, None, "descriptor region wraps the 32-bit address space"
            )
        ranges.append((region_base, region_bytes, "descriptor"))
    allow_alias = {frozenset(("input0", "input1"))} if opcode == OP_ADD else None
    check_no_overlap(ranges, allow_alias=allow_alias)


def validate_descriptor(
    desc: Descriptor, *, descriptor_region: tuple[int, int] | None = None
) -> None:
    """Validate one record, raising DescriptorError on the first violation.

    Checks run in a deterministic order: structural record (version, reserved,
    signed-byte encodings, tile/K_SLICE domains), opcode support, unused
    operation fields, geometry/dimensions, per-operator constraints,
    strides/spans, alignment, overlap. descriptor_region, when given, is the
    (base, bytes) of the job's descriptor array and must be disjoint from
    every operand allocation.
    """
    _check_structure(desc)
    opcode = desc.opcode
    if opcode not in OPCODE_NAMES:
        raise DescriptorError(
            FAULT_UNSUPPORTED, WORD_VERSION_OPCODE, f"opcode {opcode} is not supported"
        )
    _check_unused_fields(desc, opcode)
    _check_geometry(desc, opcode)
    _check_operator(desc, opcode)
    _check_strides_and_spans(desc, opcode)
    _check_alignment(desc)
    _check_overlap(desc, opcode, descriptor_region)
