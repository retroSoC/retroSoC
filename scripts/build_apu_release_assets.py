#!/usr/bin/env python3
"""Generate the embedded APU release-evidence assets for the apu_release app.

Reads the deterministic P5 APUMC microcode bundle, the frozen P7 APUM KWS
model, and one locked KWS corpus utterance; synthesizes a small deterministic
mono 48 kHz S16 WAV fixture; computes the frozen expected PCM through the
bit-accurate codec model; and emits a C header with every byte array and CRC
the LP/HP evidence flow needs. The generator is deterministic: no network, no
clock, and no randomness.
"""

from __future__ import annotations

import argparse
import hashlib
import struct
import zlib
from pathlib import Path

import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

from apu_codecs import decode_wav, process_pcm  # noqa: E402
from apu_kws import APUM_ABI, APUM_BYTES, APUM_MAGIC, APUM_PAYLOAD_CRC, APUM_SHA256  # noqa: E402

APUMC_MAGIC = 0x41504D43
APUMC_ABI_VERSIONS = (0x00010000, 0x00020000)
APUMC_HEADER_BYTES = 64
APUMC_HEADER_CRC_WORD = 11

WAV_RATE = 48000
WAV_CHANNELS = 1
WAV_BITS = 16
WAV_FRAMES = 480

KWS_WINDOW_BYTES = 32000
KWS_EXPECTED_CLASS = 7  # "Stop" in the frozen class order
KWS_THRESHOLD = 1
KWS_DEBOUNCE = 1
# Locked corpus manifest row 000000 (docs/ip/apu-kws-corpus.tsv).
KWS_CORPUS_RELPATH = "stop/563aa4e6_nohash_3.wav"
KWS_WAV_SHA256 = "6ed51beca5b58fbbb06a16af68f120066218cf52c3fd4237f222a8ea9c972199"
KWS_PCM_SHA256 = "d843b234a0f585d143c88aed0acc1cca5ed02150f3cf5b77cb0489ad5429d725"


def _require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def _crc32(data: bytes) -> int:
    return zlib.crc32(data) & 0xFFFFFFFF


def _sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _load_apumc(path: Path) -> tuple[bytes, int, int]:
    image = path.read_bytes()
    _require(len(image) >= APUMC_HEADER_BYTES, f"APUMC bundle too small: {path}")
    magic, abi = struct.unpack_from("<II", image, 0)
    _require(magic == APUMC_MAGIC, f"APUMC magic mismatch in {path}")
    _require(abi in APUMC_ABI_VERSIONS, f"APUMC ABI 0x{abi:08x} is not supported")
    header_crc = struct.unpack_from("<I", image, APUMC_HEADER_CRC_WORD * 4)[0]
    payload_crc = _crc32(image[APUMC_HEADER_BYTES:])
    _require(header_crc == payload_crc, f"APUMC header CRC disagrees with payload CRC in {path}")
    return image, _crc32(image), payload_crc


def _load_apum(path: Path) -> tuple[bytes, int]:
    image = path.read_bytes()
    _require(len(image) == APUM_BYTES, f"APUM model is not {APUM_BYTES} bytes: {path}")
    magic, abi = struct.unpack_from("<II", image, 0)
    _require(magic == APUM_MAGIC, f"APUM magic mismatch in {path}")
    _require(abi == APUM_ABI, f"APUM ABI 0x{abi:08x} mismatch in {path}")
    payload_crc = struct.unpack_from("<I", image, 0x24)[0]
    _require(payload_crc == APUM_PAYLOAD_CRC, f"APUM payload CRC mismatch in {path}")
    _require(_sha256(image) == APUM_SHA256, f"APUM image SHA-256 mismatch in {path}")
    return image, _crc32(image)


def _synthesize_wav() -> bytes:
    samples = [((index * 48271 + 12345) % 65536) - 32768 for index in range(WAV_FRAMES)]
    payload = struct.pack(f"<{WAV_FRAMES}h", *samples)
    alignment = WAV_CHANNELS * (WAV_BITS // 8)
    fmt = struct.pack("<HHIIHH", 1, WAV_CHANNELS, WAV_RATE, WAV_RATE * alignment, alignment, WAV_BITS)
    chunks = b"fmt " + struct.pack("<I", len(fmt)) + fmt
    chunks += b"data" + struct.pack("<I", len(payload)) + payload
    return b"RIFF" + struct.pack("<I", len(chunks) + 4) + b"WAVE" + chunks


def _expected_pcm(wav: bytes) -> tuple[int, int, int]:
    audio = decode_wav(wav, strict=True)
    processed = process_pcm(audio, output_bits=16)
    _require(processed.rate == WAV_RATE, "fixture rate mismatch")
    _require(processed.channels == WAV_CHANNELS, "fixture channel mismatch")
    _require(processed.frames == WAV_FRAMES, "fixture frame mismatch")
    _require(len(processed.payload) == WAV_FRAMES * 2, "fixture payload size mismatch")
    info = audio.info
    _require(info.input_used == len(wav), "fixture WAV is not fully consumed")
    return _crc32(processed.payload), len(processed.payload), processed.frames


def _extract_mono16k_data(wav: bytes) -> bytes:
    _require(len(wav) >= 12 and wav[0:4] == b"RIFF" and wav[8:12] == b"WAVE", "KWS source is not RIFF/WAVE")
    fmt: bytes | None = None
    data: bytes | None = None
    offset = 12
    while offset + 8 <= len(wav):
        chunk_size = struct.unpack_from("<I", wav, offset + 4)[0]
        body = wav[offset + 8 : offset + 8 + chunk_size]
        _require(len(body) == chunk_size, "KWS source chunk is truncated")
        if wav[offset : offset + 4] == b"fmt ":
            fmt = body
        elif wav[offset : offset + 4] == b"data":
            data = body
        offset += 8 + chunk_size + (chunk_size & 1)
    _require(fmt is not None and len(fmt) >= 16 and data is not None, "KWS source lacks fmt/data")
    audio_format, channels, rate, _byte_rate, _align, bits = struct.unpack_from("<HHIIHH", fmt)
    _require(
        (audio_format, channels, rate, bits) == (1, 1, 16000, 16),
        "KWS source is not mono/16000/S16 PCM",
    )
    _require(len(data) <= KWS_WINDOW_BYTES and len(data) % 2 == 0, "KWS source exceeds one window")
    return data


def _load_kws_pcm(corpus_root: Path) -> tuple[bytes, int]:
    source = corpus_root / KWS_CORPUS_RELPATH
    _require(source.is_file(), f"locked KWS corpus utterance missing: {source}")
    wav = source.read_bytes()
    _require(_sha256(wav) == KWS_WAV_SHA256, f"KWS source WAV SHA-256 mismatch: {source}")
    padded = _extract_mono16k_data(wav)
    padded = padded + bytes(KWS_WINDOW_BYTES - len(padded))
    _require(_sha256(padded) == KWS_PCM_SHA256, f"KWS padded PCM SHA-256 mismatch: {source}")
    return padded, _crc32(padded)


def _format_array(name: str, data: bytes) -> str:
    lines = [f"static const uint8_t {name}[{len(data)}] __attribute__((aligned(64))) = {{"]
    for offset in range(0, len(data), 16):
        chunk = ",".join(f"0x{value:02X}" for value in data[offset : offset + 16])
        lines.append(f"    {chunk},")
    lines.append("};")
    return "\n".join(lines)


def _emit(args: argparse.Namespace) -> str:
    apumc, apumc_crc, apumc_payload_crc = _load_apumc(args.apumc)
    apum, apum_crc = _load_apum(args.apum)
    wav = _synthesize_wav()
    pcm_crc, pcm_bytes, pcm_frames = _expected_pcm(wav)
    kws_pcm, kws_crc = _load_kws_pcm(args.kws_corpus)

    sections = [
        "/* Generated by scripts/build_apu_release_assets.py; do not edit. */",
        "#ifndef APU_RELEASE_ASSETS_H",
        "#define APU_RELEASE_ASSETS_H",
        "",
        "#include <stdint.h>",
        "",
        f"#define RS_APU_RELEASE_APUMC_SIZE        UINT32_C({len(apumc)})",
        f"#define RS_APU_RELEASE_APUMC_CRC         UINT32_C(0x{apumc_crc:08X})",
        f"#define RS_APU_RELEASE_APUMC_PAYLOAD_CRC UINT32_C(0x{apumc_payload_crc:08X})",
        f"#define RS_APU_RELEASE_APUM_SIZE         UINT32_C({len(apum)})",
        f"#define RS_APU_RELEASE_APUM_CRC          UINT32_C(0x{apum_crc:08X})",
        f"#define RS_APU_RELEASE_APUM_PAYLOAD_CRC UINT32_C(0x{APUM_PAYLOAD_CRC:08X})",
        f"#define RS_APU_RELEASE_WAV_SIZE         UINT32_C({len(wav)})",
        f"#define RS_APU_RELEASE_WAV_CRC          UINT32_C(0x{_crc32(wav):08X})",
        f"#define RS_APU_RELEASE_WAV_RATE         UINT32_C({WAV_RATE})",
        f"#define RS_APU_RELEASE_WAV_CHANNELS     UINT32_C({WAV_CHANNELS})",
        f"#define RS_APU_RELEASE_WAV_BITS         UINT32_C({WAV_BITS})",
        f"#define RS_APU_RELEASE_PCM_CRC          UINT32_C(0x{pcm_crc:08X})",
        f"#define RS_APU_RELEASE_PCM_BYTES        UINT32_C({pcm_bytes})",
        f"#define RS_APU_RELEASE_PCM_FRAMES       UINT32_C({pcm_frames})",
        f"#define RS_APU_RELEASE_KWS_SIZE         UINT32_C({len(kws_pcm)})",
        f"#define RS_APU_RELEASE_KWS_CRC          UINT32_C(0x{kws_crc:08X})",
        f"#define RS_APU_RELEASE_KWS_CLASS        UINT32_C({KWS_EXPECTED_CLASS})",
        f"#define RS_APU_RELEASE_KWS_THRESHOLD    UINT32_C({KWS_THRESHOLD})",
        f"#define RS_APU_RELEASE_KWS_DEBOUNCE     UINT32_C({KWS_DEBOUNCE})",
        "",
        _format_array("rs_apu_release_apumc", apumc),
        "",
        _format_array("rs_apu_release_apum", apum),
        "",
        _format_array("rs_apu_release_wav", wav),
        "",
        _format_array("rs_apu_release_kws_pcm", kws_pcm),
        "",
        "#endif",
        "",
    ]
    return "\n".join(sections)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apumc", type=Path, required=True, help="P5 APUMC bundle path")
    parser.add_argument("--apum", type=Path, required=True, help="P7 APUM KWS model path")
    parser.add_argument(
        "--kws-corpus",
        type=Path,
        required=True,
        help="locked apu-kws-pcm corpus root (run the P7 reference setup first)",
    )
    parser.add_argument("--output", type=Path, required=True, help="generated C header path")
    args = parser.parse_args()
    content = _emit(args)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(content, encoding="ascii", newline="\n")
    print(f"apu_release assets: {args.output} ({len(content)} bytes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
