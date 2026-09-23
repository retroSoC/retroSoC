"""NPU descriptor ABI 1.0 encode/decode and validator tests."""

from __future__ import annotations

import struct
import sys
from pathlib import Path

import pytest


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

from npu_descriptors import (  # noqa: E402
    ABI_VERSION,
    DESCRIPTOR_BYTES,
    DESCRIPTOR_WORDS,
    FAULT_DESCRIPTOR,
    FAULT_RANGE,
    FAULT_UNSUPPORTED,
    MAX_DIMENSION,
    MAX_K_SLICE,
    OPCODE_NAMES,
    Descriptor,
    DescriptorError,
    full_reduction,
    used_span,
    validate_descriptor,
)

IN0_BASE = 0x0001_0000
IN1_BASE = 0x0002_0000
OUT_BASE = 0x0003_0000
WGT_BASE = 0x0004_0000
PRM_BASE = 0x0005_0000
DESC_REGION = (0x0000_1000, 0x1000)
UNIT_KERNEL_STRIDE = 0x0101_0101


def _hw(lo: int, hi: int) -> int:
    return lo | (hi << 16)


def _kernel_stride(kh: int, kw: int, sh: int, sw: int) -> int:
    return kh | (kw << 8) | (sh << 16) | (sw << 24)


def _padding(top: int, bottom: int, left: int, right: int) -> int:
    return top | (bottom << 8) | (left << 16) | (right << 24)


def _tile(tile_h: int, tile_w: int) -> int:
    return tile_h | (tile_w << 8)


def make_conv_descriptor() -> Descriptor:
    """KWS-like CONV2D: 49x10x1, kernel 10x4 stride 2 pad (4,5,1,1) -> 25x5x64."""
    return Descriptor(
        version_opcode=0x0100_0001,
        input0_base=IN0_BASE,
        output_base=OUT_BASE,
        param_base=PRM_BASE,
        input_hw=_hw(49, 10),
        channels=_hw(1, 64),
        output_hw=_hw(25, 5),
        input0_row_bytes=10,
        output_row_bytes=320,
        kernel_stride=_kernel_stride(10, 4, 2, 2),
        padding=_padding(4, 5, 1, 1),
        tile_hw=_tile(2, 4),
        k_slice=40,
        input0_bytes=490,
        output_bytes=8000,
        param_bytes=64 * 16,
        input0_zero=-3,
        output_zero=14,
        act_min=-128,
        act_max=127,
        weight_base=WGT_BASE,
        weight_bytes=2560,
    )


def make_depthwise_descriptor() -> Descriptor:
    """DEPTHWISE3X3 3x3 stride 1 pad 1 on 25x5x64 -> 25x5x64."""
    return Descriptor(
        version_opcode=0x0100_0002,
        input0_base=IN0_BASE,
        output_base=OUT_BASE,
        param_base=PRM_BASE,
        input_hw=_hw(25, 5),
        channels=_hw(64, 64),
        output_hw=_hw(25, 5),
        input0_row_bytes=320,
        output_row_bytes=320,
        kernel_stride=_kernel_stride(3, 3, 1, 1),
        padding=_padding(1, 1, 1, 1),
        tile_hw=_tile(2, 4),
        k_slice=9,
        input0_bytes=8000,
        output_bytes=8000,
        param_bytes=64 * 16,
        input0_zero=-3,
        output_zero=14,
        act_min=-128,
        act_max=127,
        weight_base=WGT_BASE,
        weight_bytes=576,
    )


def make_fully_connected_descriptor() -> Descriptor:
    """FULLY_CONNECTED with Cin=64, Cout=12."""
    return Descriptor(
        version_opcode=0x0100_0003,
        input0_base=IN0_BASE,
        output_base=OUT_BASE,
        param_base=PRM_BASE,
        input_hw=_hw(1, 1),
        channels=_hw(64, 12),
        output_hw=_hw(1, 1),
        input0_row_bytes=64,
        output_row_bytes=12,
        kernel_stride=UNIT_KERNEL_STRIDE,
        padding=0,
        tile_hw=_tile(1, 1),
        k_slice=64,
        input0_bytes=64,
        output_bytes=12,
        param_bytes=12 * 16,
        input0_zero=-3,
        output_zero=14,
        act_min=-128,
        act_max=127,
        weight_base=WGT_BASE,
        weight_bytes=2 * 64 * 8,
    )


def make_add_descriptor() -> Descriptor:
    """ADD on 25x5x64 with independent input zero points."""
    return Descriptor(
        version_opcode=0x0100_0004,
        input0_base=IN0_BASE,
        input1_base=IN1_BASE,
        output_base=OUT_BASE,
        param_base=PRM_BASE,
        input_hw=_hw(25, 5),
        channels=_hw(64, 64),
        output_hw=_hw(25, 5),
        input0_row_bytes=320,
        output_row_bytes=320,
        input1_row_bytes=320,
        kernel_stride=UNIT_KERNEL_STRIDE,
        padding=0,
        tile_hw=_tile(2, 4),
        k_slice=1,
        input0_bytes=8000,
        input1_bytes=8000,
        output_bytes=8000,
        param_bytes=32,
        input0_zero=-3,
        input1_zero=7,
        output_zero=14,
        act_min=-128,
        act_max=127,
    )


def make_max_pool_descriptor() -> Descriptor:
    """MAX_POOL 3x3 stride 2 pad 1 on 25x5x64 -> 13x3x64."""
    return Descriptor(
        version_opcode=0x0100_0005,
        input0_base=IN0_BASE,
        output_base=OUT_BASE,
        input_hw=_hw(25, 5),
        channels=_hw(64, 64),
        output_hw=_hw(13, 3),
        input0_row_bytes=320,
        output_row_bytes=192,
        kernel_stride=_kernel_stride(3, 3, 2, 2),
        padding=_padding(1, 1, 1, 1),
        tile_hw=_tile(2, 3),
        k_slice=9,
        input0_bytes=8000,
        output_bytes=12 * 192 + 3 * 64,
        input0_zero=-3,
        output_zero=-3,
        act_min=-128,
        act_max=127,
    )


def make_average_pool_descriptor() -> Descriptor:
    """AVERAGE_POOL 2x2 stride 2 no padding on 25x5x64 -> 12x2x64."""
    return Descriptor(
        version_opcode=0x0100_0006,
        input0_base=IN0_BASE,
        output_base=OUT_BASE,
        input_hw=_hw(25, 5),
        channels=_hw(64, 64),
        output_hw=_hw(12, 2),
        input0_row_bytes=320,
        output_row_bytes=128,
        kernel_stride=_kernel_stride(2, 2, 2, 2),
        padding=0,
        tile_hw=_tile(2, 2),
        k_slice=4,
        input0_bytes=8000,
        output_bytes=11 * 128 + 2 * 64,
        input0_zero=-3,
        output_zero=-3,
        act_min=-128,
        act_max=127,
    )


def make_global_average_pool_descriptor() -> Descriptor:
    """GLOBAL_AVERAGE_POOL on 25x5x64 -> 1x1x64."""
    return Descriptor(
        version_opcode=0x0100_0007,
        input0_base=IN0_BASE,
        output_base=OUT_BASE,
        input_hw=_hw(25, 5),
        channels=_hw(64, 64),
        output_hw=_hw(1, 1),
        input0_row_bytes=320,
        output_row_bytes=64,
        kernel_stride=0,
        padding=0,
        tile_hw=_tile(1, 1),
        k_slice=125,
        input0_bytes=8000,
        output_bytes=64,
        input0_zero=-3,
        output_zero=-3,
        act_min=-128,
        act_max=127,
    )


def make_clamp_descriptor() -> Descriptor:
    """CLAMP (standalone ReLU) on 25x5x64 -> 25x5x64."""
    return Descriptor(
        version_opcode=0x0100_0008,
        input0_base=IN0_BASE,
        output_base=OUT_BASE,
        input_hw=_hw(25, 5),
        channels=_hw(64, 64),
        output_hw=_hw(25, 5),
        input0_row_bytes=320,
        output_row_bytes=320,
        kernel_stride=UNIT_KERNEL_STRIDE,
        padding=0,
        tile_hw=_tile(4, 2),
        k_slice=1,
        input0_bytes=8000,
        output_bytes=8000,
        input0_zero=-3,
        output_zero=-3,
        act_min=0,
        act_max=127,
    )


def _expect_invalid(desc: Descriptor, code: int, word: int | None) -> None:
    with pytest.raises(DescriptorError) as excinfo:
        validate_descriptor(desc)
    assert excinfo.value.code == code
    assert excinfo.value.word == word


def test_constants() -> None:
    assert ABI_VERSION == 0x0100
    assert DESCRIPTOR_WORDS == 32
    assert DESCRIPTOR_BYTES == 128
    assert MAX_K_SLICE == 1024
    assert MAX_DIMENSION == 4096
    assert FAULT_DESCRIPTOR == 1
    assert FAULT_UNSUPPORTED == 2
    assert FAULT_RANGE == 3
    assert OPCODE_NAMES == {
        1: "CONV2D",
        2: "DEPTHWISE3X3",
        3: "FULLY_CONNECTED",
        4: "ADD",
        5: "MAX_POOL",
        6: "AVERAGE_POOL",
        7: "GLOBAL_AVERAGE_POOL",
        8: "CLAMP",
    }


def test_used_span() -> None:
    assert used_span(49, 10, 1, 10) == 490
    assert used_span(25, 5, 64, 320) == 8000
    assert used_span(1, 1, 12, 12) == 12


def test_full_reduction() -> None:
    assert full_reduction(make_conv_descriptor()) == 40
    assert full_reduction(make_depthwise_descriptor()) == 9
    assert full_reduction(make_fully_connected_descriptor()) == 64
    assert full_reduction(make_add_descriptor()) == 1
    assert full_reduction(make_max_pool_descriptor()) == 9
    assert full_reduction(make_average_pool_descriptor()) == 4
    assert full_reduction(make_global_average_pool_descriptor()) == 125
    assert full_reduction(make_clamp_descriptor()) == 1


def test_conv_roundtrip() -> None:
    desc = make_conv_descriptor()
    data = desc.to_bytes()
    assert len(data) == DESCRIPTOR_BYTES
    words = struct.unpack("<32I", data)
    assert words[0] == 0x0100_0001
    assert words[1] == 0
    assert words[2] == IN0_BASE
    assert words[3] == 0
    assert words[4] == OUT_BASE
    assert words[5] == PRM_BASE
    assert words[6] == 49 | (10 << 16)
    assert words[7] == 1 | (64 << 16)
    assert words[8] == 25 | (5 << 16)
    assert words[9] == 10
    assert words[10] == 320
    assert words[11] == 0
    assert words[12] == 10 | (4 << 8) | (2 << 16) | (2 << 24)
    assert words[13] == 4 | (5 << 8) | (1 << 16) | (1 << 24)
    assert words[14] == 2 | (4 << 8)
    assert words[15] == 40
    assert words[16] == 490
    assert words[17] == 0
    assert words[18] == 8000
    assert words[19] == 64 * 16
    assert words[20] == 0xFD  # -3 two's complement
    assert words[21] == 0
    assert words[22] == 14
    assert words[23] == 0x80 | (127 << 8)
    assert words[24] == WGT_BASE
    assert words[25] == 2560
    assert words[26:] == (0,) * 6
    decoded = Descriptor.from_bytes(data)
    assert decoded == desc
    assert decoded.input0_zero == -3
    assert decoded.act_min == -128
    assert decoded.act_max == 127
    assert decoded.to_bytes() == data
    validate_descriptor(decoded, descriptor_region=DESC_REGION)


def test_from_bytes_lossless() -> None:
    raw = bytes(range(DESCRIPTOR_BYTES))
    assert Descriptor.from_bytes(raw).to_bytes() == raw


def test_from_bytes_length() -> None:
    with pytest.raises(ValueError):
        Descriptor.from_bytes(b"\x00" * (DESCRIPTOR_BYTES - 4))
    with pytest.raises(ValueError):
        Descriptor.from_bytes(b"\x00" * (DESCRIPTOR_BYTES + 4))


def test_valid_conv2d() -> None:
    validate_descriptor(make_conv_descriptor(), descriptor_region=DESC_REGION)


def test_valid_depthwise3x3() -> None:
    validate_descriptor(make_depthwise_descriptor(), descriptor_region=DESC_REGION)


def test_valid_fully_connected() -> None:
    validate_descriptor(make_fully_connected_descriptor(), descriptor_region=DESC_REGION)


def test_valid_add() -> None:
    validate_descriptor(make_add_descriptor(), descriptor_region=DESC_REGION)


def test_valid_max_pool() -> None:
    validate_descriptor(make_max_pool_descriptor(), descriptor_region=DESC_REGION)


def test_valid_average_pool() -> None:
    validate_descriptor(make_average_pool_descriptor(), descriptor_region=DESC_REGION)


def test_valid_global_average_pool() -> None:
    validate_descriptor(
        make_global_average_pool_descriptor(), descriptor_region=DESC_REGION
    )


def test_valid_clamp() -> None:
    validate_descriptor(make_clamp_descriptor(), descriptor_region=DESC_REGION)


def test_add_input_aliasing_valid() -> None:
    desc = make_add_descriptor()
    desc.input1_base = desc.input0_base
    validate_descriptor(desc, descriptor_region=DESC_REGION)


def test_reject_bad_version() -> None:
    desc = make_conv_descriptor()
    desc.version_opcode = 0x0200_0001
    _expect_invalid(desc, FAULT_DESCRIPTOR, 0)


def test_reject_reserved_nonzero() -> None:
    desc = make_conv_descriptor()
    desc.reserved1 = 1
    _expect_invalid(desc, FAULT_DESCRIPTOR, 1)
    desc = make_conv_descriptor()
    desc.reserved30 = 0x10
    _expect_invalid(desc, FAULT_DESCRIPTOR, 30)
    desc = make_conv_descriptor()
    desc.version_opcode = 0x0100_0101
    _expect_invalid(desc, FAULT_DESCRIPTOR, 0)


def test_reject_unsupported_opcode() -> None:
    desc = make_conv_descriptor()
    desc.version_opcode = 0x0100_0000
    _expect_invalid(desc, FAULT_UNSUPPORTED, 0)
    desc = make_conv_descriptor()
    desc.version_opcode = 0x0100_0009
    _expect_invalid(desc, FAULT_UNSUPPORTED, 0)


def test_reject_dimension_out_of_range() -> None:
    desc = make_conv_descriptor()
    desc.input_hw = _hw(0, 10)
    _expect_invalid(desc, FAULT_RANGE, 6)
    desc = make_conv_descriptor()
    desc.input_hw = _hw(4097, 10)
    _expect_invalid(desc, FAULT_RANGE, 6)
    desc = make_conv_descriptor()
    desc.channels = _hw(0, 64)
    _expect_invalid(desc, FAULT_RANGE, 7)


def test_reject_output_size_mismatch() -> None:
    desc = make_conv_descriptor()
    desc.output_hw = _hw(24, 5)  # computed is 25x5
    _expect_invalid(desc, FAULT_RANGE, 8)


def test_reject_padding_ge_kernel() -> None:
    desc = make_conv_descriptor()
    desc.padding = _padding(10, 5, 1, 1)  # top pad equals Kh=10
    _expect_invalid(desc, FAULT_RANGE, 13)


def test_reject_conv_stride_three() -> None:
    desc = make_conv_descriptor()
    desc.kernel_stride = _kernel_stride(10, 4, 3, 3)
    desc.output_hw = _hw(17, 3)  # keep the computed output size consistent
    desc.output_row_bytes = 192
    desc.output_bytes = 16 * 192 + 3 * 64
    _expect_invalid(desc, FAULT_UNSUPPORTED, 12)


def test_reject_depthwise_kernel_size() -> None:
    desc = make_depthwise_descriptor()
    desc.kernel_stride = _kernel_stride(1, 3, 1, 1)
    desc.padding = 0
    desc.output_hw = _hw(25, 3)  # computed output for a 1x3 kernel
    desc.output_row_bytes = 192
    desc.output_bytes = 24 * 192 + 3 * 64
    _expect_invalid(desc, FAULT_UNSUPPORTED, 12)


def test_reject_fully_connected_geometry() -> None:
    desc = make_fully_connected_descriptor()
    desc.input_hw = _hw(2, 1)
    _expect_invalid(desc, FAULT_UNSUPPORTED, 6)


def test_reject_add_broadcast() -> None:
    desc = make_add_descriptor()
    desc.output_hw = _hw(13, 3)
    _expect_invalid(desc, FAULT_UNSUPPORTED, 8)


def test_reject_pool_zero_point_mismatch() -> None:
    desc = make_max_pool_descriptor()
    desc.output_zero = 9
    _expect_invalid(desc, FAULT_UNSUPPORTED, 22)


def test_reject_clamp_zero_point_mismatch() -> None:
    desc = make_clamp_descriptor()
    desc.output_zero = 9
    _expect_invalid(desc, FAULT_UNSUPPORTED, 22)


def test_reject_tile_product() -> None:
    desc = make_conv_descriptor()
    desc.tile_hw = _tile(3, 3)
    _expect_invalid(desc, FAULT_DESCRIPTOR, 14)


def test_reject_tile_exceeds_output() -> None:
    desc = make_global_average_pool_descriptor()
    desc.tile_hw = _tile(2, 1)  # OH is 1
    _expect_invalid(desc, FAULT_RANGE, 14)


def test_reject_k_slice() -> None:
    desc = make_conv_descriptor()
    desc.k_slice = 0
    _expect_invalid(desc, FAULT_DESCRIPTOR, 15)
    desc = make_conv_descriptor()
    desc.k_slice = 1025
    _expect_invalid(desc, FAULT_DESCRIPTOR, 15)
    desc = make_conv_descriptor()
    desc.k_slice = 41  # full K is 10*4*1 = 40
    _expect_invalid(desc, FAULT_UNSUPPORTED, 15)


def test_reject_span_exceeds_allocation() -> None:
    desc = make_conv_descriptor()
    desc.input0_bytes = 489  # used span is 490
    _expect_invalid(desc, FAULT_RANGE, 16)


def test_reject_address_wrap() -> None:
    desc = make_conv_descriptor()
    desc.input0_base = 0xFFFF_FF00  # base + span crosses 2**32
    _expect_invalid(desc, FAULT_RANGE, 2)


def test_reject_output_input_overlap() -> None:
    desc = make_conv_descriptor()
    desc.output_base = desc.input0_base + 0x40
    _expect_invalid(desc, FAULT_RANGE, None)


def test_reject_add_input1_output_overlap() -> None:
    desc = make_add_descriptor()
    desc.input1_base = desc.output_base
    _expect_invalid(desc, FAULT_RANGE, None)


def test_reject_descriptor_region_overlap() -> None:
    desc = make_conv_descriptor()
    with pytest.raises(DescriptorError) as excinfo:
        validate_descriptor(desc, descriptor_region=(IN0_BASE, 0x100))
    assert excinfo.value.code == FAULT_RANGE


def test_reject_unaligned_bases() -> None:
    desc = make_conv_descriptor()
    desc.param_base = PRM_BASE + 32
    _expect_invalid(desc, FAULT_DESCRIPTOR, 5)
    desc = make_conv_descriptor()
    desc.weight_base = WGT_BASE + 32
    _expect_invalid(desc, FAULT_DESCRIPTOR, 24)


def test_reject_weight_bytes() -> None:
    desc = make_conv_descriptor()
    desc.weight_bytes = 2552  # exact is ceil(64/8)*40*8 = 2560
    _expect_invalid(desc, FAULT_DESCRIPTOR, 25)
    desc = make_depthwise_descriptor()
    desc.weight_bytes = 575  # exact is ceil(64/8)*72 = 576
    _expect_invalid(desc, FAULT_DESCRIPTOR, 25)


def test_reject_param_bytes() -> None:
    desc = make_conv_descriptor()
    desc.param_bytes = 1008  # exact is 64*16 = 1024
    _expect_invalid(desc, FAULT_DESCRIPTOR, 19)
    desc = make_add_descriptor()
    desc.param_bytes = 16  # exact is 32
    _expect_invalid(desc, FAULT_DESCRIPTOR, 19)
    desc = make_max_pool_descriptor()
    desc.param_base = PRM_BASE
    desc.param_bytes = 32  # pooling has no parameters
    _expect_invalid(desc, FAULT_DESCRIPTOR, 5)


def test_reject_non_add_input1_fields() -> None:
    desc = make_conv_descriptor()
    desc.input1_base = IN1_BASE
    _expect_invalid(desc, FAULT_DESCRIPTOR, 3)
    desc = make_conv_descriptor()
    desc.input1_zero = 5
    _expect_invalid(desc, FAULT_DESCRIPTOR, 21)


def test_reject_activation_bounds() -> None:
    desc = make_conv_descriptor()
    desc.act_min = 10
    desc.act_max = -10
    _expect_invalid(desc, FAULT_DESCRIPTOR, 23)
    desc = make_conv_descriptor()
    desc.act_min = -129
    _expect_invalid(desc, FAULT_DESCRIPTOR, 23)


def test_reject_signed_byte_upper_bits() -> None:
    data = bytearray(make_conv_descriptor().to_bytes())
    struct.pack_into("<I", data, 20 * 4, 0x0100_0003)
    desc = Descriptor.from_bytes(bytes(data))
    _expect_invalid(desc, FAULT_DESCRIPTOR, 20)
    data = bytearray(make_conv_descriptor().to_bytes())
    struct.pack_into("<I", data, 23 * 4, 0x0001_0000)
    desc = Descriptor.from_bytes(bytes(data))
    _expect_invalid(desc, FAULT_DESCRIPTOR, 23)


def test_first_error_ordering() -> None:
    desc = make_conv_descriptor()
    desc.version_opcode = 0x0200_0001  # structural
    desc.output_base = desc.input0_base  # overlap, checked last
    _expect_invalid(desc, FAULT_DESCRIPTOR, 0)
    desc = make_conv_descriptor()
    desc.version_opcode = 0x0100_0009  # opcode support
    desc.input_hw = _hw(0, 10)  # geometry, checked later
    _expect_invalid(desc, FAULT_UNSUPPORTED, 0)
