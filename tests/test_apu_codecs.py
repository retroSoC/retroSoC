"""APU-P5 codec profile, bundle, coefficient, and dependency tests."""

from __future__ import annotations

import hashlib
import json
import subprocess
import struct
import sys
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
from apu_isa import APUMC_P5_CAPABILITY_MASK, InstructionClass, parse_apumc  # noqa: E402
from apu_mcasm import assemble  # noqa: E402
from apu_p5_coefficients import coefficient_bytes  # noqa: E402


class _BitWriter:
    def __init__(self) -> None:
        self.bits: list[int] = []

    def put(self, value: int, width: int) -> None:
        self.bits.extend((value >> bit) & 1 for bit in range(width - 1, -1, -1))

    def signed(self, value: int, width: int) -> None:
        self.put(value & ((1 << width) - 1), width)

    def rice0(self, value: int) -> None:
        unsigned = (value << 1) if value >= 0 else ((-value << 1) - 1)
        self.bits.extend([0] * unsigned)
        self.bits.append(1)

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


def _framed_flac(subframes: bytes, assignment: int, expected: tuple[tuple[int, ...], ...]) -> bytes:
    channels = 1 if assignment == 0 else 2
    streaminfo = bytearray(34)
    streaminfo[0:2] = (16).to_bytes(2, "big")
    streaminfo[2:4] = (16).to_bytes(2, "big")
    packed = (48000 << 44) | ((channels - 1) << 41) | (15 << 36) | len(expected)
    streaminfo[10:18] = packed.to_bytes(8, "big")
    header = ((0x3FFE << 18) | (6 << 12) | (assignment << 4) | (4 << 1)).to_bytes(4, "big")
    header += b"\x00" + bytes([len(expected) - 1])
    header += bytes([crc8(header)])
    frame = header + subframes
    frame += crc16(frame).to_bytes(2, "big")
    return b"fLaC" + bytes([0x80, 0, 0, 34]) + streaminfo + frame


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
    assert (
        manifest["sha256"]["bundle"]
        == hashlib.sha256((tmp_path / "apu-p5.apumc").read_bytes()).hexdigest()
    )
    assert (
        manifest["sha256"]["coefficients"]
        == hashlib.sha256((tmp_path / "apu-p5-coefficients.bin").read_bytes()).hexdigest()
    )
    assert high_water["instruction_words"] == manifest["instruction_count"]
    assert high_water["control_store_bytes"] <= 16 * 1024
    assert high_water["table_bytes"] <= 6144
    assert high_water["maximum_scratch_end"] <= 0x6000


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
