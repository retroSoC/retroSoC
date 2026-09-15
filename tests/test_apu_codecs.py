"""APU-P5 codec profile, bundle, coefficient, and dependency tests."""

from __future__ import annotations

import hashlib
import json
import subprocess
import struct
import sys
from collections import Counter
from collections.abc import Callable
from functools import cache
from pathlib import Path

import pytest


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

from apu_codecs import (  # noqa: E402
    AudioInfo,
    CodecError,
    DecodedAudio,
    crc8,
    crc16,
    decode_flac,
    decode_wav,
    inspect_flac,
    parse_wav,
    process_pcm,
)
from apu_isa import (  # noqa: E402
    APUMC_ABI_V1,
    APUMC_ABI_V2,
    APUMC_P5_CAPABILITY_MASK,
    BitstreamOpcode,
    ControlOpcode,
    Entry,
    Instruction,
    InstructionClass,
    LocalOpcode,
    ScalarOpcode,
    build_apumc,
    parse_apumc,
    validate_instruction,
)
from apu_mcasm import Assembly, assemble  # noqa: E402
from apu_interpreter import Machine, TransportModel  # noqa: E402
from apu_p5_coefficients import coefficient_bytes  # noqa: E402
from apu_primitives import PrimitiveBam  # noqa: E402


class _BitWriter:
    def __init__(self) -> None:
        self.bits: list[int] = []

    def put(self, value: int, width: int) -> None:
        self.bits.extend((value >> bit) & 1 for bit in range(width - 1, -1, -1))

    def signed(self, value: int, width: int) -> None:
        self.put(value & ((1 << width) - 1), width)

    def rice0(self, value: int) -> None:
        self.rice(value, 0)

    def rice(self, value: int, parameter: int) -> None:
        unsigned = (value << 1) if value >= 0 else ((-value << 1) - 1)
        self.bits.extend([0] * (unsigned >> parameter))
        self.bits.append(1)
        if parameter:
            self.put(unsigned & ((1 << parameter) - 1), parameter)

    def bytes(self) -> bytes:
        while len(self.bits) & 7:
            self.bits.append(0)
        result = bytearray(len(self.bits) // 8)
        for index, bit in enumerate(self.bits):
            result[index // 8] |= bit << (7 - (index & 7))
        return bytes(result)


def _wav(payload: bytes, *, pad: int = 0) -> bytes:
    fmt = struct.pack("<HHIIHH", 1, 2, 48000, 192000, 4, 16)
    chunks = b"fmt " + struct.pack("<I", len(fmt)) + fmt
    chunks += b"data" + struct.pack("<I", len(payload)) + payload
    if len(payload) & 1:
        chunks += bytes([pad])
    return b"RIFF" + struct.pack("<I", len(chunks) + 4) + b"WAVE" + chunks


def _empty_flac() -> bytes:
    streaminfo = bytearray(34)
    streaminfo[0:2] = (16).to_bytes(2, "big")
    streaminfo[2:4] = (16).to_bytes(2, "big")
    packed = (48000 << 44) | (1 << 41) | (15 << 36)
    streaminfo[10:18] = packed.to_bytes(8, "big")
    return b"fLaC" + bytes([0x80]) + bytes([0, 0, 34]) + streaminfo


def _constant_flac(sample: int = -2) -> bytes:
    streaminfo = bytearray(34)
    streaminfo[0:2] = (16).to_bytes(2, "big")
    streaminfo[2:4] = (16).to_bytes(2, "big")
    packed = (48000 << 44) | (15 << 36) | 16
    streaminfo[10:18] = packed.to_bytes(8, "big")
    header = ((0x3FFE << 18) | (6 << 12) | (4 << 1)).to_bytes(4, "big")
    header += b"\x00\x0f"
    header += bytes([crc8(header)])
    frame = header + b"\x00" + sample.to_bytes(2, "big", signed=True)
    frame += crc16(frame).to_bytes(2, "big")
    return b"fLaC" + bytes([0x80, 0, 0, 34]) + streaminfo + frame


def _framed_flac(
    subframes: bytes,
    assignment: int,
    expected: tuple[tuple[int, ...], ...],
    *,
    bits: int = 16,
) -> bytes:
    channels = 1 if assignment == 0 else 2
    streaminfo = bytearray(34)
    streaminfo[0:2] = (16).to_bytes(2, "big")
    streaminfo[2:4] = (16).to_bytes(2, "big")
    packed = (48000 << 44) | ((channels - 1) << 41) | ((bits - 1) << 36) | len(expected)
    streaminfo[10:18] = packed.to_bytes(8, "big")
    bit_code = {16: 4, 24: 6}[bits]
    header = ((0x3FFE << 18) | (6 << 12) | (assignment << 4) | (bit_code << 1)).to_bytes(4, "big")
    header += b"\x00" + bytes([len(expected) - 1])
    header += bytes([crc8(header)])
    frame = header + subframes
    frame += crc16(frame).to_bytes(2, "big")
    return b"fLaC" + bytes([0x80, 0, 0, 34]) + streaminfo + frame


def _wav_pcm(rate: int, channels: int, bits: int, payload: bytes) -> bytes:
    alignment = channels * (bits // 8)
    fmt = struct.pack("<HHIIHH", 1, channels, rate, rate * alignment, alignment, bits)
    chunks = b"fmt " + struct.pack("<I", len(fmt)) + fmt
    chunks += b"data" + struct.pack("<I", len(payload)) + payload
    if len(payload) & 1:
        chunks += b"\0"
    return b"RIFF" + struct.pack("<I", len(chunks) + 4) + b"WAVE" + chunks


def _two_constant_flac(rate: int, first: int, second: int) -> bytes:
    streaminfo = bytearray(34)
    streaminfo[0:2] = (16).to_bytes(2, "big")
    streaminfo[2:4] = (16).to_bytes(2, "big")
    streaminfo[10:18] = ((rate << 44) | (15 << 36) | 32).to_bytes(8, "big")

    def frame(number: int, sample: int) -> bytes:
        header = ((0x3FFE << 18) | (6 << 12) | (4 << 1)).to_bytes(4, "big")
        header += bytes([number, 15])
        header += bytes([crc8(header)])
        payload = header + b"\0" + sample.to_bytes(2, "big", signed=True)
        return payload + crc16(payload).to_bytes(2, "big")

    return b"fLaC" + bytes([0x80, 0, 0, 34]) + streaminfo + frame(0, first) + frame(1, second)


def _constant_frames_flac(samples: tuple[int, ...], *, total_samples: int | None = None) -> bytes:
    streaminfo = bytearray(34)
    streaminfo[0:2] = (16).to_bytes(2, "big")
    streaminfo[2:4] = (16).to_bytes(2, "big")
    advertised = len(samples) * 16 if total_samples is None else total_samples
    streaminfo[10:18] = ((48000 << 44) | (15 << 36) | advertised).to_bytes(8, "big")
    result = bytearray(b"fLaC" + bytes([0x80, 0, 0, 34]) + streaminfo)
    for number, sample in enumerate(samples):
        header = ((0x3FFE << 18) | (6 << 12) | (4 << 1)).to_bytes(4, "big")
        header += bytes([number, 15])
        header += bytes([crc8(header)])
        frame = header + b"\0" + sample.to_bytes(2, "big", signed=True)
        result.extend(frame + crc16(frame).to_bytes(2, "big"))
    return bytes(result)


def _changed_geometry_header(
    number: int, *, rate_code: int = 0, assignment: int = 0, bits_code: int = 4
) -> bytes:
    header = (
        (0x3FFE << 18) | (6 << 12) | (rate_code << 8) | (assignment << 4) | (bits_code << 1)
    ).to_bytes(4, "big")
    header += bytes([number, 15])
    return header + bytes([crc8(header)])


def _rice_flac(values: tuple[int, ...]) -> bytes:
    writer = _BitWriter()
    writer.put(8, 7)
    writer.put(0, 1)
    writer.put(0, 2)
    writer.put(0, 4)
    writer.put(0, 4)
    for value in values:
        writer.rice0(value)
    image = bytearray(_framed_flac(writer.bytes(), 0, tuple((value,) for value in values)))
    image[8:10] = len(values).to_bytes(2, "big")
    image[10:12] = len(values).to_bytes(2, "big")
    return bytes(image)


def _empty_flac_with_padding(padding_bytes: int) -> bytes:
    image = bytearray(_empty_flac())
    image[4] = 0
    image.extend(bytes([0x81]))
    image.extend(padding_bytes.to_bytes(3, "big"))
    image.extend(bytes(padding_bytes))
    return bytes(image)


@cache
def _release_assembly() -> Assembly:
    source = (ROOT / "rtl/ip/multimedia/apu_p5_codecs.apus").read_text(encoding="utf-8")
    return assemble(source, "p5", coefficient_bytes())


def _run_release_codec(
    payload: bytes,
    format_id: int,
    *,
    output_rate: int,
    output_channels: int,
    output_bits: int,
    resample: bool = False,
    downmix: bool = False,
    capacity: int = 0x10000,
) -> dict[str, object]:
    assembly = _release_assembly()
    entry = assembly.entries[format_id]
    primitives = PrimitiveBam()
    primitives.memory.publish_table(coefficient_bytes())
    frame_bytes = output_channels * (2 if output_bits == 16 else 4)
    transport = TransportModel(
        input_data=payload,
        output_capacity=capacity,
        output_frame_bytes=frame_bytes,
    )
    machine = Machine(
        assembly.instructions,
        entry,
        target="p5",
        primitives=primitives,
        transport=transport,
        fetch_no_retirement_cycles=0,
        mc_abi=assembly.mc_abi,
    )
    control = (format_id << 4) | (int(downmix) << 10) | (int(resample) << 11)
    pcm_format = 0 if output_bits == 16 else 1
    output_config = output_rate | (output_channels << 17) | (pcm_format << 19)
    context = [
        control,
        0,
        output_config,
        1,
        0,
        0,
        0,
        0,
        len(payload),
        capacity,
        0,
        0,
        0,
        0,
        0,
        0,
    ]
    context_base = entry.scratch_base + entry.scratch_bytes - 64
    primitives.memory.inject(
        context_base,
        b"".join(value.to_bytes(4, "little") for value in context),
    )
    return machine.run()


def test_p5_coefficient_payload_is_deterministic_and_phase_normalized() -> None:
    payload = coefficient_bytes()
    assert len(payload) == 1536 * 4
    assert hashlib.sha256(payload).hexdigest() == (
        "947f536d1e1f19f9199b5c756a1629402703a5e0d25dadede696314fd5e5c83f"
    )
    words = struct.unpack("<1536i", payload)
    for phase in range(3 * 32):
        assert sum(words[phase * 16 : (phase + 1) * 16]) == 1 << 30


def test_p5_release_bundle_has_frozen_targets_and_unsupported_mp3() -> None:
    source = (ROOT / "rtl/ip/multimedia/apu_p5_codecs.apus").read_text(encoding="utf-8")
    assembly = assemble(source, "p5", coefficient_bytes())
    instructions, entries, header = parse_apumc(assembly.bundle, "p5")
    assert 2048 < len(instructions) <= 4096
    assert header[9] == entries[0].primitive_mask | entries[2].primitive_mask
    assert header[9] & ~APUMC_P5_CAPABILITY_MASK == 0
    assert entries[1].__dict__ == {
        "format_id": 1,
        "entry_pc": 0,
        "first_pc": 0,
        "last_pc": 0,
        "max_loop_count": 1,
        "max_retired": 1,
        "scratch_base": 0,
        "scratch_bytes": 0,
        "primitive_mask": 0,
        "table_offset": 0,
        "table_bytes": 0,
    }
    assert instructions[0].instruction_class == InstructionClass.CONTROL
    assert instructions[0].encode() == 0x0200000001000001
    with pytest.raises(ValueError):
        parse_apumc(assembly.bundle, "p4")


def test_release_flac_rice_parameter_survives_remainder_decode() -> None:
    values = (32, -23, -50, 40, 22, -71, 86, -5, 14, -7, -10, 29, -38, 19, -14, -5)
    fixed = _BitWriter()
    fixed.put(8, 7)
    fixed.put(0, 1)
    fixed.put(0, 2)
    fixed.put(0, 4)
    fixed.put(5, 4)
    for value in values:
        fixed.rice(value, 5)
    image = _framed_flac(fixed.bytes(), 0, tuple((value,) for value in values))
    result = _run_release_codec(
        image,
        2,
        output_rate=48000,
        output_channels=1,
        output_bits=16,
    )
    transport = result["transport"]
    assert transport is not None
    assert bytes.fromhex(transport["output"]) == struct.pack("<16h", *values)
    assert transport["frames"] == len(values)
    assert (transport["result_code"], transport["result_stage"]) == (0, 0)


def test_release_flac_partial_lpc_tail_does_not_execute_padding() -> None:
    sample = 131081
    coefficient = 16383
    residual = sample - (coefficient * sample)
    lpc = _BitWriter()
    lpc.put(32, 7)
    lpc.put(0, 1)
    lpc.signed(0, 24)
    lpc.put(14, 4)
    lpc.signed(0, 5)
    lpc.signed(coefficient, 15)
    lpc.put(1, 2)
    lpc.put(0, 4)
    lpc.put(27, 5)
    lpc.rice(sample, 27)
    for _ in range(14):
        lpc.rice(residual, 27)
    expected_samples = ((0,),) + ((sample,),) * 15
    image = _framed_flac(lpc.bytes(), 0, expected_samples, bits=24)
    result = _run_release_codec(
        image,
        2,
        output_rate=48000,
        output_channels=1,
        output_bits=24,
    )
    transport = result["transport"]
    assert transport is not None
    assert bytes.fromhex(transport["output"]) == struct.pack("<16i", *([0] + [sample] * 15))
    assert transport["frames"] == 16
    assert (transport["result_code"], transport["result_stage"]) == (0, 0)


@pytest.mark.parametrize("resample", [False, True])
def test_release_flac_refill_staging_preserves_pending_and_resampler_state(
    resample: bool,
) -> None:
    image = _constant_frames_flac(tuple(range(-16, 16)))
    decoded = decode_flac(image)
    output_rate = 96000 if resample else 48000
    expected = process_pcm(
        decoded,
        output_rate=output_rate,
        output_channels=1,
        output_bits=16,
        resample=resample,
    )
    result = _run_release_codec(
        image,
        2,
        output_rate=output_rate,
        output_channels=1,
        output_bits=16,
        resample=resample,
        capacity=max(0x10000, len(expected.payload)),
    )
    transport = result["transport"]
    assert transport is not None
    assert bytes.fromhex(transport["output"]) == expected.payload
    assert transport["frames"] == expected.frames
    assert (transport["result_code"], transport["result_stage"]) == (0, 0)


def test_release_flac_sample_count_error_keeps_only_verified_prefix() -> None:
    image = _constant_frames_flac((-3, 7, 11), total_samples=40)
    with pytest.raises(CodecError) as caught:
        decode_flac(image)
    error = caught.value
    assert (error.code, error.stage, error.reason) == (4, 4, 0x32)
    assert error.partial_audio is not None
    assert error.offset == 66
    assert error.input_used == len(image)
    assert error.partial_audio.samples == ((-3,),) * 16 + ((7,),) * 16

    result = _run_release_codec(
        image,
        2,
        output_rate=48000,
        output_channels=1,
        output_bits=16,
    )
    transport = result["transport"]
    assert transport is not None
    assert bytes.fromhex(transport["output"]) == struct.pack("<32h", *([-3] * 16 + [7] * 16))
    assert transport["frames"] == 32
    assert (
        transport["result_code"],
        transport["result_stage"],
        transport["result_detail"],
    ) == (4, 4, 0x02010032)


@pytest.mark.parametrize(
    "changed_header",
    [
        _changed_geometry_header(1, rate_code=1),
        _changed_geometry_header(1, assignment=1),
        _changed_geometry_header(1, bits_code=1),
    ],
)
def test_release_flac_midstream_geometry_error_keeps_verified_prefix(
    changed_header: bytes,
) -> None:
    first = _constant_frames_flac((23,), total_samples=0)
    image = first + changed_header
    with pytest.raises(CodecError) as caught:
        decode_flac(image)
    error = caught.value
    assert (error.code, error.stage, error.reason) == (4, 4, 0x18)
    assert error.partial_audio is not None
    assert error.offset == len(first)
    assert error.input_used == len(first) + len(changed_header) - 1
    assert error.partial_audio.samples == ((23,),) * 16

    result = _run_release_codec(
        image,
        2,
        output_rate=48000,
        output_channels=1,
        output_bits=16,
    )
    transport = result["transport"]
    assert transport is not None
    assert bytes.fromhex(transport["output"]) == struct.pack("<16h", *([23] * 16))
    assert transport["frames"] == 16
    assert (
        transport["result_code"],
        transport["result_stage"],
        transport["result_detail"],
    ) == (4, 4, 0x02010018)


@pytest.mark.parametrize(
    ("rate", "channels", "bits", "payload", "output_channels", "output_bits"),
    [
        (8000, 1, 8, bytes([0, 128, 255]), 1, 16),
        (48000, 2, 16, struct.pack("<hhhh", -32768, 32767, -1, 1), 2, 16),
        (44100, 1, 24, b"\0\0\x80\xff\xff\x7f", 2, 24),
        (96000, 1, 24, b"\0\0\x80\xff\xff\x7f", 2, 24),
        (96000, 2, 32, struct.pack("<ii", -2147483648, 2147483647), 2, 24),
    ],
)
def test_release_wav_microprogram_matches_bam_for_frozen_widths(
    rate: int,
    channels: int,
    bits: int,
    payload: bytes,
    output_channels: int,
    output_bits: int,
) -> None:
    image = _wav_pcm(rate, channels, bits, payload)
    decoded = decode_wav(image)
    expected = process_pcm(
        decoded,
        output_rate=rate,
        output_channels=output_channels,
        output_bits=output_bits,
    )
    result = _run_release_codec(
        image,
        0,
        output_rate=rate,
        output_channels=output_channels,
        output_bits=output_bits,
    )
    transport = result["transport"]
    assert transport is not None
    assert bytes.fromhex(transport["output"]) == expected.payload
    assert transport["frames"] == expected.frames
    assert (transport["result_code"], transport["result_stage"]) == (0, 0)


def test_release_flac_cross_frame_resampling_matches_integer_bam() -> None:
    image = _two_constant_flac(44100, -2000, 2000)
    source = DecodedAudio(
        AudioInfo(44100, 1, 16, 32, 0, 0, len(image)),
        ((-2000,),) * 16 + ((2000,),) * 16,
    )
    expected = process_pcm(
        source,
        output_rate=48000,
        output_channels=1,
        output_bits=16,
        resample=True,
    )
    result = _run_release_codec(
        image,
        2,
        output_rate=48000,
        output_channels=1,
        output_bits=16,
        resample=True,
    )
    transport = result["transport"]
    assert transport is not None
    assert bytes.fromhex(transport["output"]) == expected.payload
    assert transport["frames"] == expected.frames == 35
    assert transport["result_detail"] == 0x02010000


def test_release_wav_high_expansion_uses_only_complete_256_byte_commands() -> None:
    image = _wav_pcm(8000, 1, 16, bytes(64))
    decoded = decode_wav(image)
    expected = process_pcm(
        decoded,
        output_rate=96000,
        output_channels=2,
        output_bits=24,
        resample=True,
    )
    result = _run_release_codec(
        image,
        0,
        output_rate=96000,
        output_channels=2,
        output_bits=24,
        resample=True,
    )
    transport = result["transport"]
    assert transport is not None
    assert bytes.fromhex(transport["output"]) == expected.payload
    assert transport["frames"] == expected.frames == 384
    assert [command["bytes"] for command in transport["output_commands"]] == [256] * 12
    assert (transport["result_code"], transport["result_stage"]) == (0, 0)


def test_release_flac_entropy_and_reconstruction_profiles_match_bam() -> None:
    fixed_values = tuple(range(-4, 12))
    fixed = _BitWriter()
    fixed.put(8, 7)
    fixed.put(0, 1)
    fixed.put(0, 2)
    fixed.put(0, 4)
    fixed.put(0, 4)
    for value in fixed_values:
        fixed.rice0(value)

    lpc = _BitWriter()
    lpc.put(32, 7)
    lpc.put(0, 1)
    lpc.signed(7, 16)
    lpc.put(1, 4)
    lpc.signed(0, 5)
    lpc.signed(1, 2)
    lpc.put(0, 2)
    lpc.put(0, 4)
    lpc.put(0, 4)
    for _ in range(15):
        lpc.rice0(0)

    left = _BitWriter()
    left.put(0, 7)
    left.put(0, 1)
    left.signed(5, 16)
    left.put(0, 7)
    left.put(0, 1)
    left.signed(2, 17)

    cases = (
        _framed_flac(fixed.bytes(), 0, tuple((value,) for value in fixed_values)),
        _framed_flac(lpc.bytes(), 0, ((7,),) * 16),
        _framed_flac(left.bytes(), 8, ((5, 3),) * 16),
    )
    for image in cases:
        decoded = decode_flac(image)
        expected = process_pcm(
            decoded,
            output_rate=48000,
            output_channels=decoded.info.channels,
            output_bits=16,
        )
        result = _run_release_codec(
            image,
            2,
            output_rate=48000,
            output_channels=decoded.info.channels,
            output_bits=16,
        )
        transport = result["transport"]
        assert transport is not None
        assert bytes.fromhex(transport["output"]) == expected.payload
        assert transport["frames"] == expected.frames
        assert (transport["result_code"], transport["result_stage"]) == (0, 0)


@pytest.mark.parametrize(
    "values",
    [
        (-32768,) + (0,) * 15,
        (20,) * 64,
    ],
)
def test_release_flac_long_rice_profiles_fit_the_retirement_budget(
    values: tuple[int, ...],
) -> None:
    image = _rice_flac(values)
    result = _run_release_codec(
        image,
        2,
        output_rate=48000,
        output_channels=1,
        output_bits=16,
    )
    transport = result["transport"]
    assert transport is not None
    assert bytes.fromhex(transport["output"]) == struct.pack(f"<{len(values)}h", *values)
    assert transport["frames"] == len(values)
    assert result["retired"] < (1 << 24)
    assert (transport["result_code"], transport["result_stage"]) == (0, 0)


def test_release_flac_rejects_a_rice_quotient_above_65535() -> None:
    result = _run_release_codec(
        _rice_flac((32768,) + (0,) * 15),
        2,
        output_rate=48000,
        output_channels=1,
        output_bits=16,
    )
    transport = result["transport"]
    assert transport is not None
    assert bytes.fromhex(transport["output"]) == b""
    assert (transport["result_code"], transport["result_stage"]) == (3, 5)
    assert transport["result_detail"] == 0x02010004


@pytest.mark.parametrize("padding_bytes", [65535, 65536, (1024 * 1024) - 34])
def test_release_flac_consumes_complete_opaque_metadata(padding_bytes: int) -> None:
    image = _empty_flac_with_padding(padding_bytes)
    decoded = decode_flac(image)
    assert decoded.info.samples == 0
    result = _run_release_codec(
        image,
        2,
        output_rate=48000,
        output_channels=2,
        output_bits=16,
    )
    transport = result["transport"]
    assert transport is not None
    assert transport["input_used"] == len(image)
    assert transport["frames"] == 0
    assert transport["output_commands"] == []
    assert result["retired"] < (1 << 24)
    assert (transport["result_code"], transport["result_stage"]) == (0, 0)


@pytest.mark.parametrize(
    ("mutation", "expected"),
    [
        (lambda payload: b"x" + payload[1:], (4, 4, 0x02010010)),
        (lambda payload: payload[:-1] + bytes([payload[-1] ^ 1]), (6, 4, 0x02010031)),
    ],
)
def test_release_flac_malformed_vectors_report_exact_tuple(
    mutation: Callable[[bytes], bytes], expected: tuple[int, int, int]
) -> None:
    image = mutation(_constant_flac())
    result = _run_release_codec(
        image,
        2,
        output_rate=48000,
        output_channels=1,
        output_bits=16,
    )
    transport = result["transport"]
    assert transport is not None
    assert bytes.fromhex(transport["output"]) == b""
    assert (
        transport["result_code"],
        transport["result_stage"],
        transport["result_detail"],
    ) == expected


def test_flac_metadata_structure_precedes_impossible_length() -> None:
    image = bytearray(_empty_flac())
    image[4] = 0
    metadata_offset = len(image)
    image.extend(b"\xff\xff\xff\xff")
    with pytest.raises(CodecError) as caught:
        inspect_flac(bytes(image))
    error = caught.value
    assert (error.code, error.stage, error.reason) == (4, 4, 0x16)
    assert error.offset == metadata_offset
    assert error.input_used == metadata_offset + 4

    result = _run_release_codec(
        bytes(image),
        2,
        output_rate=48000,
        output_channels=1,
        output_bits=16,
    )
    transport = result["transport"]
    assert transport is not None
    assert bytes.fromhex(transport["output"]) == b""
    assert (
        transport["result_code"],
        transport["result_stage"],
        transport["result_detail"],
    ) == (4, 4, 0x02010016)


def test_flac_invalid_first_streaminfo_size_reports_header_only_input() -> None:
    image = bytearray(_empty_flac())
    image[5:8] = (0xFFFFFF).to_bytes(3, "big")
    with pytest.raises(CodecError) as caught:
        inspect_flac(bytes(image))
    error = caught.value
    assert (error.code, error.stage, error.reason) == (4, 4, 0x15)
    assert (error.offset, error.input_used) == (5, 8)


def test_flac_frame_number_precedes_crc8_failure() -> None:
    image = bytearray(_constant_flac())
    frame_offset = 42
    image[frame_offset + 4] = 1
    image[frame_offset + 6] ^= 1
    with pytest.raises(CodecError) as caught:
        decode_flac(bytes(image))
    error = caught.value
    assert (error.code, error.stage, error.reason) == (4, 4, 0x1A)
    assert error.offset == frame_offset
    assert error.input_used == frame_offset + 6


def test_release_flac_rejects_nonfinal_block_below_streaminfo_minimum() -> None:
    streaminfo = bytearray(34)
    streaminfo[0:2] = (16).to_bytes(2, "big")
    streaminfo[2:4] = (16).to_bytes(2, "big")
    streaminfo[10:18] = ((48000 << 44) | (15 << 36) | 24).to_bytes(8, "big")

    def frame(number: int, count: int, sample: int) -> bytes:
        header = ((0x3FFE << 18) | (6 << 12) | (4 << 1)).to_bytes(4, "big")
        header += bytes([number, count - 1])
        header += bytes([crc8(header)])
        payload = header + b"\0" + sample.to_bytes(2, "big", signed=True)
        return payload + crc16(payload).to_bytes(2, "big")

    image = bytearray(b"fLaC" + bytes([0x80, 0, 0, 34]) + streaminfo)
    image.extend(frame(0, 8, 3))
    image.extend(frame(1, 16, 4))
    with pytest.raises(CodecError) as caught:
        decode_flac(bytes(image))
    assert (caught.value.code, caught.value.stage, caught.value.reason) == (3, 4, 0x04)
    result = _run_release_codec(
        bytes(image),
        2,
        output_rate=48000,
        output_channels=1,
        output_bits=16,
    )
    transport = result["transport"]
    assert transport is not None
    assert bytes.fromhex(transport["output"]) == b""
    assert (transport["result_code"], transport["result_stage"]) == (3, 4)
    assert transport["result_detail"] == 0x02010004


@pytest.mark.parametrize("field_offset", [12, 15])
def test_release_flac_rejects_actual_frame_size_outside_hints(field_offset: int) -> None:
    image = bytearray(_constant_flac())
    actual_size = len(image) - 42
    if field_offset == 12:
        image[field_offset : field_offset + 3] = (actual_size + 1).to_bytes(3, "big")
    else:
        image[field_offset : field_offset + 3] = (actual_size - 1).to_bytes(3, "big")
    result = _run_release_codec(
        bytes(image),
        2,
        output_rate=48000,
        output_channels=1,
        output_bits=16,
    )
    transport = result["transport"]
    assert transport is not None
    assert bytes.fromhex(transport["output"]) == b""
    assert (transport["result_code"], transport["result_stage"]) == (3, 4)
    assert transport["result_detail"] == 0x02010004


@pytest.mark.parametrize(
    ("mutation", "expected"),
    [
        (lambda data: data.__setitem__(slice(8, 10), (1).to_bytes(2, "big")), (3, 4, 8)),
        (lambda data: data.__setitem__(slice(10, 12), (4097).to_bytes(2, "big")), (3, 4, 10)),
        (lambda data: data.__setitem__(slice(15, 18), (65537).to_bytes(3, "big")), (3, 4, 15)),
        (
            lambda data: data.__setitem__(
                slice(18, 26),
                ((48000 << 44) | (2 << 41) | (15 << 36)).to_bytes(8, "big"),
            ),
            (3, 2, 18),
        ),
    ],
)
def test_flac_streaminfo_uses_frozen_first_field_diagnostic(
    mutation: Callable[[bytearray], None], expected: tuple[int, int, int]
) -> None:
    image = bytearray(_empty_flac())
    mutation(image)
    with pytest.raises(CodecError) as caught:
        inspect_flac(bytes(image))
    error = caught.value
    assert (error.code, error.reason, error.offset) == expected
    assert error.stage == 4
    assert error.input_used == 42


def test_pinned_flac_streaminfo_first_offenders_cover_all_62_cases() -> None:
    corpus = ROOT / ".cache/retrosoc/sources/apu-flac-corpus"
    if not corpus.is_dir():
        raise RuntimeError("pinned APU FLAC corpus is required; run make setup-apu-reference")
    observed: Counter[tuple[int, int, int]] = Counter()
    for path in sorted(corpus.rglob("*.flac")):
        data = path.read_bytes()
        if len(data) < 42 or data[:5] not in (b"fLaC\x00", b"fLaC\x80"):
            continue
        minimum = int.from_bytes(data[8:10], "big")
        maximum = int.from_bytes(data[10:12], "big")
        min_frame = int.from_bytes(data[12:15], "big")
        max_frame = int.from_bytes(data[15:18], "big")
        packed = int.from_bytes(data[18:26], "big")
        rate = (packed >> 44) & 0xFFFFF
        channels = ((packed >> 41) & 7) + 1
        bits = ((packed >> 36) & 0x1F) + 1
        expected: tuple[int, int, int] | None = None
        if minimum < 16:
            expected = (3, 4, 8)
        elif maximum < minimum:
            expected = (4, 0x15, 10)
        elif channels in (1, 2) and maximum > (4096 if channels == 1 else 2048):
            expected = (3, 4, 10)
        elif min_frame and max_frame and min_frame > max_frame:
            expected = (4, 0x15, 15)
        elif max_frame > 65536:
            expected = (3, 4, 15)
        elif channels not in (1, 2) or bits not in (16, 24) or not 8000 <= rate <= 96000:
            expected = (3, 2, 18)
        if expected is None:
            continue
        with pytest.raises(CodecError) as caught:
            inspect_flac(data)
        error = caught.value
        assert (error.code, error.reason, error.offset) == expected, path
        observed[expected] += 1
    assert observed == Counter({(3, 4, 10): 50, (3, 2, 18): 9, (3, 4, 8): 2, (3, 4, 15): 1})


def test_pinned_faulty_total_samples_keeps_exact_nine_frame_prefix() -> None:
    path = (
        ROOT
        / ".cache/retrosoc/sources/apu-flac-corpus/faulty/05 - wrong total number of samples.flac"
    )
    if not path.is_file():
        raise RuntimeError("pinned APU FLAC corpus is required; run make setup-apu-reference")
    with pytest.raises(CodecError) as caught:
        decode_flac(path.read_bytes())
    error = caught.value
    assert (error.code, error.stage, error.reason) == (4, 4, 0x32)
    assert (error.offset, error.input_used) == (29914, 34352)
    assert error.partial_audio is not None
    assert len(error.partial_audio.samples) == 36864
    pcm = process_pcm(
        error.partial_audio,
        output_rate=24000,
        output_channels=1,
        output_bits=16,
    )
    assert len(pcm.payload) == 73728
    assert hashlib.sha256(pcm.payload).hexdigest() == (
        "d597319c13a24e075e7aeb7ec33e007cae95a12323d11157bf9b13805c26f14e"
    )


def test_release_wav_capacity_returns_only_complete_prefix() -> None:
    image = _wav_pcm(48000, 2, 16, struct.pack("<hhhh", -32768, 32767, -1, 1))
    result = _run_release_codec(
        image,
        0,
        output_rate=48000,
        output_channels=2,
        output_bits=16,
        capacity=6,
    )
    transport = result["transport"]
    assert transport is not None
    assert bytes.fromhex(transport["output"]) == struct.pack("<hh", -32768, 32767)
    assert transport["frames"] == 1
    assert (transport["result_code"], transport["result_stage"]) == (8, 8)
    assert transport["result_detail"] == 0x00000051


def test_crc_primitives_do_not_prefill_or_consume_the_shared_fifo() -> None:
    instructions = [
        Instruction(InstructionClass.SCALAR, ScalarOpcode.MOVI, dst=1, immediate=0),
        Instruction(InstructionClass.SCALAR, ScalarOpcode.MOVI, dst=2, immediate=0x12),
        Instruction(InstructionClass.BITSTREAM, BitstreamOpcode.CRC8, dst=3, src0=1, src1=2),
        Instruction(InstructionClass.LOCAL, LocalOpcode.FIFO_POP, dst=4),
        Instruction(InstructionClass.CONTROL, ControlOpcode.END),
    ]
    entry = Entry(0, 0, 0, 4, 1, 8)
    primitives = PrimitiveBam()
    machine = Machine(
        instructions,
        entry,
        target="p5",
        primitives=primitives,
        fetch_no_retirement_cycles=0,
        mc_abi=APUMC_ABI_V2,
    )
    primitives.input_fifo.push(0x0000010444332211)
    result = machine.run()
    assert result["registers"][4:6] == [0x44332211, 0x104]


def test_p5_release_microassembly_matches_the_deterministic_emitter() -> None:
    subprocess.run(
        [
            sys.executable,
            str(ROOT / "scripts/generate_apu_p5_microcode.py"),
            "--output",
            str(ROOT / "rtl/ip/multimedia/apu_p5_codecs.apus"),
            "--check",
        ],
        check=True,
    )


def _capacity_program(count: int) -> tuple[list[Instruction], list[Entry]]:
    instructions = [Instruction(InstructionClass.CONTROL, ControlOpcode.NOP)] * (count - 1)
    instructions.append(Instruction(InstructionClass.CONTROL, ControlOpcode.END))
    entries = [Entry(index, 0, 0, count - 1, 1, count) for index in range(3)]
    return instructions, entries


@pytest.mark.parametrize(
    ("abi", "count"),
    [(APUMC_ABI_V1, 2048), (APUMC_ABI_V2, 2049), (APUMC_ABI_V2, 2437), (APUMC_ABI_V2, 4096)],
)
def test_p5_apumc_capacity_boundaries_accept(abi: int, count: int) -> None:
    instructions, entries = _capacity_program(count)
    bundle = build_apumc(instructions, entries, target="p5", abi=abi)
    parsed, parsed_entries, header = parse_apumc(bundle, "p5")
    assert len(parsed) == count
    assert parsed_entries == entries
    assert header[1] == abi


@pytest.mark.parametrize(("abi", "count"), [(APUMC_ABI_V1, 2049), (APUMC_ABI_V2, 4097)])
def test_p5_apumc_capacity_boundaries_reject(abi: int, count: int) -> None:
    instructions, entries = _capacity_program(count)
    with pytest.raises(ValueError, match="instruction count"):
        build_apumc(instructions, entries, target="p5", abi=abi)


def test_p5_apumc_v2_round_trips_high_pcs_and_branch_bit_11() -> None:
    instructions = [Instruction(InstructionClass.CONTROL, ControlOpcode.NOP)] * 4096
    instructions[2047] = Instruction(InstructionClass.CONTROL, ControlOpcode.END)
    instructions[4095] = Instruction(InstructionClass.CONTROL, ControlOpcode.END)
    entries = [
        Entry(0, 0, 0, 2047, 1, 2048),
        Entry(1, 2047, 2047, 2048, 1, 2),
        Entry(2, 2048, 2048, 4095, 1, 4096),
    ]
    bundle = build_apumc(instructions, entries, target="p5", abi=APUMC_ABI_V2)
    _, parsed_entries, _ = parse_apumc(bundle, "p5")
    assert parsed_entries == entries
    wide_branch = Instruction(InstructionClass.CONTROL, ControlOpcode.JUMP_FWD, immediate=2048)
    validate_instruction(wide_branch, "p5", APUMC_ABI_V2)
    with pytest.raises(ValueError, match="image PC width"):
        validate_instruction(wide_branch, "p5", APUMC_ABI_V1)


def test_p5_interpreter_executes_v2_branch_bit_11() -> None:
    instructions = [Instruction(InstructionClass.CONTROL, ControlOpcode.NOP)] * 2050
    instructions[0] = Instruction(InstructionClass.CONTROL, ControlOpcode.JUMP_FWD, immediate=2048)
    instructions[2049] = Instruction(InstructionClass.CONTROL, ControlOpcode.END)
    entry = Entry(0, 0, 0, 2049, 1, 4)
    result = Machine(instructions, entry, target="p5", mc_abi=APUMC_ABI_V2).run()
    assert (result["pc"], result["retired"]) == (2049, 2)


def test_p5_release_reports_hashes_and_storage_high_water(tmp_path: Path) -> None:
    subprocess.run(
        [
            sys.executable,
            str(ROOT / "scripts/build_apu_p5_bundle.py"),
            "--output-dir",
            str(tmp_path),
        ],
        check=True,
    )
    manifest = json.loads((tmp_path / "manifest.json").read_text(encoding="utf-8"))
    high_water = json.loads((tmp_path / "high-water.json").read_text(encoding="utf-8"))
    cfg_report = json.loads((tmp_path / "cfg-report.json").read_text(encoding="utf-8"))
    primitive_manifest = json.loads(
        (tmp_path / "primitive-manifest.json").read_text(encoding="utf-8")
    )
    assert (
        manifest["sha256"]["bundle"]
        == hashlib.sha256((tmp_path / "apu-p5.apumc").read_bytes()).hexdigest()
    )
    assert (
        manifest["sha256"]["coefficients"]
        == hashlib.sha256((tmp_path / "apu-p5-coefficients.bin").read_bytes()).hexdigest()
    )
    assert high_water["instruction_words"] == manifest["instruction_count"]
    assert manifest["abi"] == "2.0"
    assert manifest["mc_abi"] == "0x00020000"
    assert high_water["apumc_version"] == "0x00020000"
    assert high_water["maximum_instruction_words"] == 4096
    assert high_water["free_instruction_words"] == 4096 - high_water["instruction_words"]
    assert high_water["control_store_bytes"] <= 32 * 1024
    assert high_water["table_bytes"] <= 6144
    assert high_water["maximum_scratch_end"] <= 0x6000
    proof_workspace = high_water["loader_proof_workspace"]
    assert proof_workspace == {
        "memo_entries": 8192,
        "memo_entry_bits": 65,
        "memo_storage_bytes_ceiling": 66560,
        "pending_path_records_v1": 2048,
        "pending_path_records_v2": 4096,
        "pending_record_bits": 64,
        "pending_storage_bytes_v1": 16384,
        "pending_storage_bytes_v2": 32768,
        "traversal_limit_v1": 131072,
        "traversal_limit_v2": 262144,
    }
    assert len(cfg_report["control_flow"]) == 3
    assert primitive_manifest["implemented_mask"] == 0x001FFFFF
    assert primitive_manifest["required_mask"] == 0x001FF83B
    for name, digest in manifest["sha256"]["reports"].items():
        assert digest == hashlib.sha256((tmp_path / name).read_bytes()).hexdigest()


def test_wav_profile_accepts_pcm_and_enforces_padding_and_extent() -> None:
    image = _wav(b"\x00\x80\x00\x7f")
    info = parse_wav(image)
    assert (info.rate, info.channels, info.bits, info.samples) == (48000, 2, 16, 1)
    assert info.input_used == len(image)

    malformed = bytearray(image)
    malformed[4:8] = UINT32_MAX = (0xFFFFFFFF).to_bytes(4, "little")
    assert malformed[4:8] == UINT32_MAX
    with pytest.raises(CodecError) as caught:
        parse_wav(bytes(malformed))
    assert (caught.value.code, caught.value.reason, caught.value.offset) == (4, 0x11, 4)

    odd = _wav(b"\x00", pad=0xA5)
    with pytest.raises(CodecError) as caught:
        parse_wav(odd)
    assert caught.value.reason == 0x13


@pytest.mark.parametrize(
    ("bits", "encoded", "expected"),
    [
        (8, bytes([0, 128, 255]), (-128, 0, 127)),
        (16, struct.pack("<hhh", -32768, 0, 32767), (-32768, 0, 32767)),
        (
            24,
            b"\x00\x00\x80\x00\x00\x00\xff\xff\x7f",
            (-8388608, 0, 8388607),
        ),
        (
            32,
            struct.pack("<iii", -2147483648, 0, 2147483647),
            (-2147483648, 0, 2147483647),
        ),
    ],
)
def test_wav_decode_all_frozen_integer_widths(
    bits: int, encoded: bytes, expected: tuple[int, ...]
) -> None:
    alignment = bits // 8
    fmt = struct.pack("<HHIIHH", 1, 1, 8000, 8000 * alignment, alignment, bits)
    chunks = b"fmt " + struct.pack("<I", len(fmt)) + fmt
    chunks += b"data" + struct.pack("<I", len(encoded)) + encoded
    if len(encoded) & 1:
        chunks += b"\x00"
    image = b"RIFF" + struct.pack("<I", len(chunks) + 4) + b"WAVE" + chunks
    decoded = decode_wav(image)
    assert tuple(frame[0] for frame in decoded.samples) == expected


def test_flac_streaminfo_profile_and_crc_helpers() -> None:
    info = inspect_flac(_empty_flac())
    assert (info.rate, info.channels, info.bits, info.samples, info.warnings) == (
        48000,
        2,
        16,
        None,
        1,
    )
    assert crc8(b"123456789") == 0xF4
    assert crc16(b"123456789") == 0xFEE8
    decoded = decode_flac(_empty_flac())
    assert decoded.samples == ()
    assert decoded.info.input_used == len(_empty_flac())


def test_native_flac_constant_frame_decodes_before_publication() -> None:
    image = _constant_flac()
    decoded = decode_flac(image)
    assert decoded.info.samples == 16
    assert decoded.samples == ((-2,),) * 16
    damaged = bytearray(image)
    damaged[-1] ^= 1
    with pytest.raises(CodecError) as caught:
        decode_flac(bytes(damaged))
    assert (caught.value.code, caught.value.stage, caught.value.reason) == (6, 4, 0x31)


def test_native_flac_fixed_lpc_and_side_channel_reconstruction() -> None:
    fixed_values = tuple(range(-4, 12))
    fixed = _BitWriter()
    fixed.put(8, 7)
    fixed.put(0, 1)
    fixed.put(0, 2)
    fixed.put(0, 4)
    fixed.put(0, 4)
    for value in fixed_values:
        fixed.rice0(value)
    fixed_image = _framed_flac(fixed.bytes(), 0, tuple((value,) for value in fixed_values))
    assert decode_flac(fixed_image).samples == tuple((value,) for value in fixed_values)

    lpc = _BitWriter()
    lpc.put(32, 7)
    lpc.put(0, 1)
    lpc.signed(7, 16)
    lpc.put(1, 4)
    lpc.signed(0, 5)
    lpc.signed(1, 2)
    lpc.put(0, 2)
    lpc.put(0, 4)
    lpc.put(0, 4)
    for _ in range(15):
        lpc.rice0(0)
    lpc_expected = ((7,),) * 16
    assert decode_flac(_framed_flac(lpc.bytes(), 0, lpc_expected)).samples == lpc_expected

    left = _BitWriter()
    left.put(0, 7)
    left.put(0, 1)
    left.signed(5, 16)
    left.put(0, 7)
    left.put(0, 1)
    left.signed(2, 17)
    stereo_expected = ((5, 3),) * 16
    assert decode_flac(_framed_flac(left.bytes(), 8, stereo_expected)).samples == stereo_expected


def test_integer_postprocessing_downmix_resample_and_pack() -> None:
    stereo = DecodedAudio(
        AudioInfo(48000, 2, 16, 2, 0, 8, 8),
        ((32767, -32768), (1, 0)),
    )
    passthrough = process_pcm(stereo, output_channels=2, output_bits=16)
    assert passthrough.payload == struct.pack("<hhhh", 32767, -32768, 1, 0)
    downmixed = process_pcm(stereo, output_channels=1, output_bits=16, downmix=True)
    assert struct.unpack("<hh", downmixed.payload) == (-1, 0)

    mono = DecodedAudio(
        AudioInfo(44100, 1, 16, 147, 0, 294, 294),
        tuple((index - 73,) for index in range(147)),
    )
    converted = process_pcm(
        mono,
        output_rate=48000,
        output_channels=1,
        output_bits=24,
        resample=True,
        i2s=True,
    )
    assert converted.rate == 48000
    assert converted.channels == 2
    assert converted.frames == 160
    words = struct.unpack(f"<{converted.frames * 2}i", converted.payload)
    assert all(words[index] == words[index + 1] for index in range(0, len(words), 2))


def test_p5_corpus_qualifier_emits_per_file_agreement(tmp_path: Path) -> None:
    corpus = tmp_path / "corpus"
    corpus.mkdir()
    (corpus / "LICENSE.txt").write_text("CC0\n", encoding="utf-8")
    (corpus / "constant.flac").write_bytes(_constant_flac())
    reference = tmp_path / "flac"
    reference.write_text(
        "#!/usr/bin/env python3\nimport sys\nsys.stdout.buffer.write(b'\\xfe\\xff' * 16)\n",
        encoding="utf-8",
    )
    reference.chmod(0o755)
    manifest_path = tmp_path / "corpus.json"
    subprocess.run(
        [
            sys.executable,
            str(ROOT / "scripts/qualify_apu_p5_corpus.py"),
            "--flac",
            str(reference),
            "--corpus",
            str(corpus),
            "--output",
            str(manifest_path),
        ],
        check=True,
    )
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    assert manifest["file_count"] == 1
    assert manifest["counts"] == {"malformed": 0, "supported": 1, "unsupported": 0}
    assert manifest["files"][0]["model_reference_agreement"] is True
    truth = manifest["files"][0]["production_truth"]
    assert truth == {
        "code": 0,
        "error_offset": 0,
        "frames": 16,
        "input_used": len(_constant_flac()),
        "input_used_policy": "exact",
        "output_bytes": 32,
        "pcm_sha256": hashlib.sha256(b"\xfe\xff" * 16).hexdigest(),
        "reason": 0,
        "source_info": 48000 | (1 << 17) | (16 << 19),
        "stage": 0,
        "status": "success",
        "warnings": 1,
    }


def test_p5_reference_inputs_match_frozen_lock() -> None:
    lock = json.loads((ROOT / "dependencies/dependencies.lock.json").read_text(encoding="utf-8"))
    assert lock["sources"]["apu_libflac"]["revision"] == (
        "1507800de4b70e21be71f38caa0d9079d0bc6e45"
    )
    assert lock["sources"]["apu_flac_corpus"]["revision"] == (
        "aa7b0c6cf32994c106ae517a08134c28a96ff5b2"
    )
    assert lock["archives"]["apu_libflac"]["sha256"] == (
        "d80ef5facdb21972efe91774da03d6b9abf216aa17093d740fcc411cd8afbb41"
    )
    assert lock["archives"]["apu_flac_corpus"]["sha256"] == (
        "36de2310155b4084011fbd56f24603dfef91a26c5433e3f92bd21995b45089c3"
    )
