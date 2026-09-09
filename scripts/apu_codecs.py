"""Bounded APU-P5 container and integer PCM reference helpers."""

from __future__ import annotations

from dataclasses import dataclass
from fractions import Fraction

from apu_p5_coefficients import coefficient_words


class CodecError(ValueError):
    def __init__(self, code: int, stage: int, reason: int, offset: int, warnings: int = 0):
        self.code = code
        self.stage = stage
        self.reason = reason
        self.offset = offset
        self.warnings = warnings
        super().__init__(f"codec error {code}/{stage} reason 0x{reason:04x} at {offset}")


@dataclass(frozen=True)
class AudioInfo:
    rate: int
    channels: int
    bits: int
    samples: int | None
    data_offset: int
    data_bytes: int
    input_used: int
    warnings: int = 0


@dataclass(frozen=True)
class DecodedAudio:
    info: AudioInfo
    samples: tuple[tuple[int, ...], ...]


@dataclass(frozen=True)
class ProcessedPcm:
    rate: int
    channels: int
    bits: int
    frames: int
    payload: bytes


_RESAMPLE_RATIOS = (
    (1, 1),
    (1, 2),
    (80, 147),
    (160, 147),
    (3, 2),
    (2, 1),
    (3, 1),
    (4, 1),
    (6, 1),
    (8, 1),
    (12, 1),
    (320, 147),
    (640, 147),
    (1280, 147),
    (2, 3),
    (4, 3),
)


def _rne(value: int, shift: int) -> int:
    magnitude = abs(value)
    quotient, remainder = divmod(magnitude, 1 << shift)
    halfway = 1 << (shift - 1)
    if remainder > halfway or (remainder == halfway and quotient & 1):
        quotient += 1
    return -quotient if value < 0 else quotient


def _sat(value: int, bits: int) -> int:
    return min(max(value, -(1 << (bits - 1))), (1 << (bits - 1)) - 1)


def _profile(output_rate: int, input_rate: int) -> int:
    ratio = Fraction(output_rate, input_rate)
    for index, item in enumerate(_RESAMPLE_RATIOS):
        if ratio == Fraction(*item):
            return index
    raise CodecError(3, 0, 0x50, 0)


def _resample(samples: list[tuple[int, ...]], profile: int) -> list[tuple[int, ...]]:
    if profile == 0:
        return list(samples)
    ratio_l, ratio_m = _RESAMPLE_RATIOS[profile]
    bank = 2 if profile in (1, 2) else (1 if profile == 14 else 0)
    coefficients = coefficient_words()[bank * 512 : (bank + 1) * 512]
    channels = len(samples[0]) if samples else 1
    zero = (0,) * channels
    padded = [zero] * 7 + samples + [zero] * 9
    output: list[tuple[int, ...]] = []
    numerator = 0
    while numerator // ratio_l < len(samples):
        source_index, remainder = divmod(numerator, ratio_l)
        phase_floor, phase_remainder = divmod(32 * remainder, ratio_l)
        phase = phase_floor
        twice = phase_remainder * 2
        if twice > ratio_l or (twice == ratio_l and phase & 1):
            phase += 1
        if phase == 32:
            phase = 0
            source_index += 1
        values = []
        for channel in range(channels):
            total = sum(
                padded[source_index + tap][channel] * coefficients[phase * 16 + tap]
                for tap in range(16)
            )
            values.append(_sat(_rne(total, 30), 32))
        output.append(tuple(values))
        numerator += ratio_m
    return output


def process_pcm(
    audio: DecodedAudio,
    *,
    output_rate: int = 0,
    output_channels: int = 0,
    output_bits: int = 16,
    downmix: bool = False,
    resample: bool = False,
    i2s: bool = False,
) -> ProcessedPcm:
    if output_bits not in (16, 24):
        raise CodecError(3, 0, 0x50, 0)
    target_rate = output_rate or audio.info.rate
    logical_channels = output_channels or (2 if i2s else audio.info.channels)
    if logical_channels not in (1, 2):
        raise CodecError(3, 0, 0x50, 0)
    if downmix and (audio.info.channels != 2 or logical_channels != 1):
        raise CodecError(3, 0, 0x50, 0)
    if not downmix and audio.info.channels == 2 and logical_channels == 1:
        raise CodecError(3, 0, 0x50, 0)
    if not resample and target_rate != audio.info.rate:
        raise CodecError(3, 0, 0x50, 0)
    profile = _profile(target_rate, audio.info.rate) if resample else 0

    shift = 32 - audio.info.bits
    normalized = [tuple(sample << shift for sample in frame) for frame in audio.samples]
    if downmix:
        normalized = [(_sat(_rne(frame[0] + frame[1], 1), 32),) for frame in normalized]
    elif audio.info.channels == 1 and logical_channels == 2:
        normalized = [(frame[0], frame[0]) for frame in normalized]
    converted = _resample(normalized, profile)
    physical_channels = 2 if i2s else logical_channels
    if physical_channels == 2 and converted and len(converted[0]) == 1:
        converted = [(frame[0], frame[0]) for frame in converted]

    payload = bytearray()
    target_shift = 32 - output_bits
    for frame in converted:
        for sample in frame:
            value = _sat(sample >> target_shift, output_bits)
            if output_bits == 16:
                payload.extend(value.to_bytes(2, "little", signed=True))
            else:
                payload.extend(value.to_bytes(4, "little", signed=True))
    return ProcessedPcm(target_rate, physical_channels, output_bits, len(converted), bytes(payload))


class _BitReader:
    def __init__(self, data: bytes, offset: int):
        self.data = data
        self.bit = offset * 8

    @property
    def byte_offset(self) -> int:
        return self.bit // 8

    def get(self, width: int, *, stage: int = 5) -> int:
        if width < 0 or self.bit + width > len(self.data) * 8:
            raise CodecError(5, stage, 0x20, len(self.data), 1)
        value = 0
        remaining = width
        while remaining:
            bit_offset = self.bit & 7
            take = min(remaining, 8 - bit_offset)
            shift = 8 - bit_offset - take
            value = (value << take) | (
                (self.data[self.bit // 8] >> shift) & ((1 << take) - 1)
            )
            self.bit += take
            remaining -= take
        return value

    def signed(self, width: int, *, stage: int = 5) -> int:
        value = self.get(width, stage=stage)
        return value - (1 << width) if value & (1 << (width - 1)) else value

    def unary_zeros(self, limit: int = 65535) -> int:
        count = 0
        while self.get(1) == 0:
            count += 1
            if count > limit:
                raise CodecError(3, 5, 0x04, self.byte_offset, 1)
        return count

    def align_zero(self) -> None:
        while self.bit & 7:
            if self.get(1) != 0:
                raise CodecError(4, 4, 0x19, self.byte_offset, 1)


def _signed_range(value: int, width: int, offset: int) -> int:
    if value < -(1 << (width - 1)) or value > (1 << (width - 1)) - 1:
        raise CodecError(22, 6, 0x43, offset, 1)
    return value


def _utf8_integer(reader: _BitReader) -> int:
    first = reader.get(8, stage=4)
    if first < 0x80:
        return first
    prefix = 0x80
    count = 0
    while first & prefix:
        count += 1
        prefix >>= 1
    if count < 2 or count > 7:
        raise CodecError(4, 4, 0x17, reader.byte_offset - 1, 1)
    value = first & ((1 << (7 - count)) - 1)
    minimum = 1 << (7 if count == 2 else (5 * count - 4))
    for _ in range(count - 1):
        byte = reader.get(8, stage=4)
        if byte & 0xC0 != 0x80:
            raise CodecError(4, 4, 0x17, reader.byte_offset - 1, 1)
        value = (value << 6) | (byte & 0x3F)
    if value < minimum or value >= (1 << 36):
        raise CodecError(4, 4, 0x17, reader.byte_offset - count, 1)
    return value


def _u16(data: bytes, offset: int) -> int:
    if offset + 2 > len(data):
        raise CodecError(5, 4, 0x20, len(data))
    return int.from_bytes(data[offset : offset + 2], "little")


def _u32(data: bytes, offset: int) -> int:
    if offset + 4 > len(data):
        raise CodecError(5, 4, 0x20, len(data))
    return int.from_bytes(data[offset : offset + 4], "little")


def parse_wav(data: bytes, *, strict: bool = True) -> AudioInfo:
    if len(data) < 12 or data[:4] != b"RIFF" or data[8:12] != b"WAVE":
        raise CodecError(4, 4, 0x10, 0)
    riff_end = 8 + _u32(data, 4)
    if riff_end < 12 or riff_end > len(data):
        raise CodecError(4, 4, 0x11, 4)
    offset = 12
    fmt: tuple[int, int, int, int] | None = None
    data_chunk: tuple[int, int] | None = None
    skipped = 0
    chunks = 0
    warnings = 0
    while offset < riff_end:
        if offset + 8 > riff_end:
            raise CodecError(5, 4, 0x20, offset, warnings)
        chunk_id = data[offset : offset + 4]
        size = _u32(data, offset + 4)
        payload = offset + 8
        end = payload + size
        padded_end = end + (size & 1)
        if end < payload or padded_end > riff_end:
            raise CodecError(4, 4, 0x13, offset, warnings)
        chunks += 1
        if chunks > 1024:
            raise CodecError(3, 4, 0x04, offset, warnings)
        if chunk_id == b"fmt ":
            if fmt is not None or data_chunk is not None:
                raise CodecError(4, 4, 0x12, offset, warnings)
            tag = _u16(data, payload)
            channels = _u16(data, payload + 2)
            rate = _u32(data, payload + 4)
            average = _u32(data, payload + 8)
            alignment = _u16(data, payload + 12)
            bits = _u16(data, payload + 14)
            if tag == 1:
                if size not in (16, 18) or (size == 18 and _u16(data, payload + 16) != 0):
                    raise CodecError(4, 4, 0x14, payload, warnings)
            elif tag == 0xFFFE:
                pcm_guid = bytes.fromhex("0100000000001000800000aa00389b71")
                if (
                    size != 40
                    or _u16(data, payload + 16) != 22
                    or _u16(data, payload + 18) != bits
                    or data[payload + 24 : payload + 40] != pcm_guid
                ):
                    raise CodecError(3, 4, 0x03, payload, warnings)
                channel_mask = _u32(data, payload + 20)
                if (channels == 1 and channel_mask not in (0, 4)) or (
                    channels == 2 and channel_mask not in (0, 3)
                ):
                    raise CodecError(3, 4, 0x03, payload + 20, warnings)
            else:
                raise CodecError(3, 4, 0x03, payload, warnings)
            expected_alignment = channels * (bits // 8)
            if (
                channels not in (1, 2)
                or rate < 8000
                or rate > 96000
                or bits not in (8, 16, 24, 32)
                or alignment != expected_alignment
                or average != rate * expected_alignment
            ):
                raise CodecError(4, 4, 0x14, payload, warnings)
            fmt = (rate, channels, bits, alignment)
        elif chunk_id == b"data":
            if fmt is None or data_chunk is not None:
                raise CodecError(4, 4, 0x12, offset, warnings)
            if size % fmt[3]:
                raise CodecError(4, 4, 0x13, payload, warnings)
            data_chunk = (payload, size)
        else:
            skipped += size + (size & 1)
            if skipped > 1024 * 1024:
                raise CodecError(3, 4, 0x04, offset, warnings)
        if size & 1 and data[end] != 0:
            if strict:
                raise CodecError(4, 4, 0x19, end, warnings)
            warnings |= 1 << 2
        offset = padded_end
    if fmt is None or data_chunk is None:
        raise CodecError(4, 4, 0x12, offset, warnings)
    if strict and riff_end != len(data):
        raise CodecError(4, 4, 0x1B, riff_end, warnings)
    if not strict and riff_end != len(data):
        warnings |= 1 << 1
    rate, channels, bits, alignment = fmt
    return AudioInfo(
        rate,
        channels,
        bits,
        data_chunk[1] // alignment,
        data_chunk[0],
        data_chunk[1],
        riff_end,
        warnings,
    )


def decode_wav(data: bytes, *, strict: bool = True) -> DecodedAudio:
    info = parse_wav(data, strict=strict)
    bytes_per_sample = info.bits // 8
    frames: list[tuple[int, ...]] = []
    offset = info.data_offset
    for _ in range(info.samples or 0):
        channels: list[int] = []
        for _ in range(info.channels):
            encoded = data[offset : offset + bytes_per_sample]
            offset += bytes_per_sample
            if info.bits == 8:
                channels.append(encoded[0] - 128)
            else:
                channels.append(int.from_bytes(encoded, "little", signed=True))
        frames.append(tuple(channels))
    return DecodedAudio(info, tuple(frames))


def inspect_flac(data: bytes, *, strict: bool = True) -> AudioInfo:
    if len(data) < 8 or data[:4] != b"fLaC":
        raise CodecError(4, 4, 0x10, 0)
    offset = 4
    blocks = 0
    metadata_bytes = 0
    stream_info: AudioInfo | None = None
    last = False
    while not last:
        if offset + 4 > len(data):
            raise CodecError(5, 4, 0x20, len(data), 1)
        header = data[offset]
        last = bool(header & 0x80)
        block_type = header & 0x7F
        size = int.from_bytes(data[offset + 1 : offset + 4], "big")
        payload = offset + 4
        end = payload + size
        if end > len(data):
            raise CodecError(5, 4, 0x20, len(data), 1)
        blocks += 1
        metadata_bytes += size
        if blocks > 128 or metadata_bytes > 1024 * 1024:
            raise CodecError(3, 4, 0x04, offset, 1)
        if blocks == 1:
            if block_type != 0 or size != 34:
                raise CodecError(4, 4, 0x15, offset, 1)
            minimum = int.from_bytes(data[payload : payload + 2], "big")
            maximum = int.from_bytes(data[payload + 2 : payload + 4], "big")
            min_frame = int.from_bytes(data[payload + 4 : payload + 7], "big")
            max_frame = int.from_bytes(data[payload + 7 : payload + 10], "big")
            packed = int.from_bytes(data[payload + 10 : payload + 18], "big")
            rate = (packed >> 44) & 0xFFFFF
            channels = ((packed >> 41) & 7) + 1
            bits = ((packed >> 36) & 0x1F) + 1
            samples = packed & ((1 << 36) - 1)
            if (
                minimum < 16
                or maximum < minimum
                or maximum > (4096 if channels == 1 else 2048)
                or (min_frame and max_frame and min_frame > max_frame)
                or max_frame > 65536
                or channels not in (1, 2)
                or bits not in (16, 24)
                or rate < 8000
                or rate > 96000
            ):
                raise CodecError(3, 4, 0x04, payload, 1)
            stream_info = AudioInfo(rate, channels, bits, samples or None, 0, 0, 0, 1)
        elif block_type == 0 or block_type == 127:
            raise CodecError(4, 4, 0x16, offset, 1)
        elif block_type >= 7:
            raise CodecError(3, 4, 0x03, offset, 1)
        offset = end
    if stream_info is None:
        raise CodecError(4, 4, 0x15, 4, 1)
    if strict and stream_info.samples is None and offset != len(data):
        raise CodecError(4, 4, 0x1B, offset, 1)
    return AudioInfo(
        stream_info.rate,
        stream_info.channels,
        stream_info.bits,
        stream_info.samples,
        offset,
        len(data) - offset,
        offset,
        1,
    )


def crc8(data: bytes) -> int:
    value = 0
    for byte in data:
        value ^= byte
        for _ in range(8):
            value = ((value << 1) ^ (0x07 if value & 0x80 else 0)) & 0xFF
    return value


def crc16(data: bytes) -> int:
    value = 0
    for byte in data:
        value ^= byte << 8
        for _ in range(8):
            value = ((value << 1) ^ (0x8005 if value & 0x8000 else 0)) & 0xFFFF
    return value


@dataclass(frozen=True)
class _FlacMeta:
    minimum_block: int
    maximum_block: int
    minimum_frame: int
    maximum_frame: int
    rate: int
    channels: int
    bits: int
    total_samples: int | None
    frame_offset: int


def _flac_metadata(data: bytes) -> _FlacMeta:
    info = inspect_flac(data, strict=False)
    payload = 8
    minimum_block = int.from_bytes(data[payload : payload + 2], "big")
    maximum_block = int.from_bytes(data[payload + 2 : payload + 4], "big")
    minimum_frame = int.from_bytes(data[payload + 4 : payload + 7], "big")
    maximum_frame = int.from_bytes(data[payload + 7 : payload + 10], "big")
    return _FlacMeta(
        minimum_block,
        maximum_block,
        minimum_frame,
        maximum_frame,
        info.rate,
        info.channels,
        info.bits,
        info.samples,
        info.data_offset,
    )


def _block_size(code: int, reader: _BitReader) -> int:
    if code == 0:
        raise CodecError(4, 4, 0x17, reader.byte_offset, 1)
    if code == 1:
        return 192
    if code <= 5:
        return 576 << (code - 2)
    if code == 6:
        return reader.get(8, stage=4) + 1
    if code == 7:
        return reader.get(16, stage=4) + 1
    return 256 << (code - 8)


def _sample_rate(code: int, reader: _BitReader, stream_rate: int) -> int:
    fixed = {
        0: stream_rate,
        1: 88200,
        2: 176400,
        3: 192000,
        4: 8000,
        5: 16000,
        6: 22050,
        7: 24000,
        8: 32000,
        9: 44100,
        10: 48000,
        11: 96000,
    }
    if code in fixed:
        return fixed[code]
    if code == 12:
        return reader.get(8, stage=4) * 1000
    if code == 13:
        return reader.get(16, stage=4)
    if code == 14:
        return reader.get(16, stage=4) * 10
    raise CodecError(4, 4, 0x17, reader.byte_offset, 1)


def _sample_bits(code: int, stream_bits: int, offset: int) -> int:
    values = {0: stream_bits, 1: 8, 2: 12, 4: 16, 5: 20, 6: 24, 7: 32}
    if code not in values:
        raise CodecError(4, 4, 0x17, offset, 1)
    return values[code]


def _residuals(reader: _BitReader, block_size: int, order: int) -> list[int]:
    method = reader.get(2)
    if method > 1:
        raise CodecError(7, 5, 0x40, reader.byte_offset, 1)
    parameter_bits = 4 + method
    escape = (1 << parameter_bits) - 1
    partition_order = reader.get(4)
    partitions = 1 << partition_order
    if partition_order > 15 or block_size % partitions:
        raise CodecError(7, 5, 0x42, reader.byte_offset, 1)
    result: list[int] = []
    for partition in range(partitions):
        count = block_size // partitions - (order if partition == 0 else 0)
        if count < 0:
            raise CodecError(7, 5, 0x42, reader.byte_offset, 1)
        parameter = reader.get(parameter_bits)
        if parameter == escape:
            raw_width = reader.get(5)
            if raw_width == 0:
                result.extend([0] * count)
            else:
                result.extend(reader.signed(raw_width) for _ in range(count))
        else:
            for _ in range(count):
                quotient = reader.unary_zeros()
                remainder = reader.get(parameter) if parameter else 0
                unsigned = (quotient << parameter) | remainder
                result.append((unsigned >> 1) ^ -(unsigned & 1))
    if len(result) != block_size - order:
        raise CodecError(7, 5, 0x42, reader.byte_offset, 1)
    return result


def _fixed_predict(order: int, history: list[int]) -> int:
    if order == 0:
        return 0
    if order == 1:
        return history[-1]
    if order == 2:
        return 2 * history[-1] - history[-2]
    if order == 3:
        return 3 * history[-1] - 3 * history[-2] + history[-3]
    return 4 * history[-1] - 6 * history[-2] + 4 * history[-3] - history[-4]


def _subframe(reader: _BitReader, block_size: int, bits: int) -> list[int]:
    offset = reader.byte_offset
    if reader.get(1) != 0:
        raise CodecError(4, 5, 0x40, offset, 1)
    kind = reader.get(6)
    wasted_flag = reader.get(1)
    wasted = reader.unary_zeros() + 1 if wasted_flag else 0
    coded_bits = bits - wasted
    if coded_bits < 1:
        raise CodecError(7, 5, 0x41, offset, 1)

    if kind == 0:
        samples = [reader.signed(coded_bits)] * block_size
    elif kind == 1:
        samples = [reader.signed(coded_bits) for _ in range(block_size)]
    elif 8 <= kind <= 12:
        order = kind - 8
        if order > block_size:
            raise CodecError(7, 5, 0x40, offset, 1)
        samples = [reader.signed(coded_bits) for _ in range(order)]
        for residual in _residuals(reader, block_size, order):
            samples.append(_signed_range(_fixed_predict(order, samples) + residual, 32, offset))
    elif 32 <= kind <= 63:
        order = kind - 31
        if order > block_size:
            raise CodecError(7, 5, 0x40, offset, 1)
        samples = [reader.signed(coded_bits) for _ in range(order)]
        precision = reader.get(4) + 1
        if precision == 16:
            raise CodecError(7, 5, 0x40, reader.byte_offset, 1)
        shift = reader.signed(5)
        coefficients = [reader.signed(precision) for _ in range(order)]
        for residual in _residuals(reader, block_size, order):
            prediction = sum(coefficients[index] * samples[-index - 1] for index in range(order))
            prediction = prediction >> shift if shift >= 0 else prediction << -shift
            samples.append(_signed_range(prediction + residual, 32, offset))
    else:
        raise CodecError(7, 5, 0x40, offset, 1)
    restored = [_signed_range(sample << wasted, 32, offset) for sample in samples]
    return restored


def _decode_frame(
    data: bytes, offset: int, meta: _FlacMeta
) -> tuple[list[tuple[int, ...]], int, int, int, int]:
    start = offset
    reader = _BitReader(data, offset)
    if reader.get(14, stage=4) != 0x3FFE or reader.get(1, stage=4) != 0:
        raise CodecError(4, 4, 0x17, start, 1)
    strategy = reader.get(1, stage=4)
    block_code = reader.get(4, stage=4)
    rate_code = reader.get(4, stage=4)
    assignment = reader.get(4, stage=4)
    bits_code = reader.get(3, stage=4)
    if reader.get(1, stage=4) != 0:
        raise CodecError(4, 4, 0x17, start, 1)
    number = _utf8_integer(reader)
    block_size = _block_size(block_code, reader)
    rate = _sample_rate(rate_code, reader, meta.rate)
    bits = _sample_bits(bits_code, meta.bits, start)
    header_end = reader.byte_offset
    expected_crc8 = reader.get(8, stage=4)
    if crc8(data[start:header_end]) != expected_crc8:
        raise CodecError(6, 4, 0x30, header_end, 1)
    if assignment <= 7:
        channels = assignment + 1
    elif assignment <= 10:
        channels = 2
    else:
        raise CodecError(4, 4, 0x17, start, 1)
    if (rate, channels, bits) != (meta.rate, meta.channels, meta.bits):
        raise CodecError(4, 4, 0x18, start, 1)
    if block_size > (4096 if channels == 1 else 2048):
        raise CodecError(3, 4, 0x04, start, 1)

    channel_bits = [bits] * channels
    if assignment == 8:
        channel_bits[1] += 1
    elif assignment == 9:
        channel_bits[0] += 1
    elif assignment == 10:
        channel_bits[1] += 1
    planar = [_subframe(reader, block_size, channel_bits[channel]) for channel in range(channels)]
    reader.align_zero()
    footer = reader.byte_offset
    expected_crc16 = reader.get(16, stage=4)
    if crc16(data[start:footer]) != expected_crc16:
        raise CodecError(6, 4, 0x31, footer, 1)
    frame_end = reader.byte_offset
    frame_bytes = frame_end - start
    if (
        (meta.minimum_frame and frame_bytes < meta.minimum_frame)
        or (meta.maximum_frame and frame_bytes > meta.maximum_frame)
        or frame_bytes > 65536
    ):
        raise CodecError(3, 4, 0x04, start, 1)

    frames: list[tuple[int, ...]] = []
    for index in range(block_size):
        if assignment <= 7:
            values = tuple(planar[channel][index] for channel in range(channels))
        elif assignment == 8:
            left = planar[0][index]
            values = (left, left - planar[1][index])
        elif assignment == 9:
            right = planar[1][index]
            values = (planar[0][index] + right, right)
        else:
            side = planar[1][index]
            middle = (planar[0][index] << 1) | (side & 1)
            values = ((middle + side) >> 1, (middle - side) >> 1)
        frames.append(tuple(_signed_range(value, bits, start) for value in values))
    return frames, frame_end, block_size, strategy, number


def decode_flac(data: bytes, *, strict: bool = True) -> DecodedAudio:
    meta = _flac_metadata(data)
    offset = meta.frame_offset
    frames: list[tuple[int, ...]] = []
    blocks: list[int] = []
    strategy: int | None = None
    frame_number = 0
    while offset < len(data) and (meta.total_samples is None or len(frames) < meta.total_samples):
        decoded, frame_end, block_size, frame_strategy, number = _decode_frame(data, offset, meta)
        if strategy is None:
            strategy = frame_strategy
        elif strategy != frame_strategy:
            raise CodecError(4, 4, 0x18, offset, 1)
        expected_number = frame_number if frame_strategy == 0 else len(frames)
        if number != expected_number:
            raise CodecError(4, 4, 0x1A, offset, 1)
        frames.extend(decoded)
        blocks.append(block_size)
        frame_number += 1
        offset = frame_end
        if meta.total_samples is not None and len(frames) > meta.total_samples:
            raise CodecError(4, 4, 0x32, offset, 1)
    if meta.total_samples is not None and len(frames) != meta.total_samples:
        raise CodecError(4, 4, 0x32, offset, 1)
    for block_size in blocks[:-1]:
        if not meta.minimum_block <= block_size <= meta.maximum_block:
            raise CodecError(4, 4, 0x17, offset, 1)
    if blocks and blocks[-1] > meta.maximum_block:
        raise CodecError(3, 4, 0x04, offset, 1)
    warnings = 1
    if offset != len(data):
        if strict:
            raise CodecError(4, 4, 0x1B, offset, warnings)
        warnings |= 1 << 1
    info = AudioInfo(
        meta.rate,
        meta.channels,
        meta.bits,
        len(frames),
        meta.frame_offset,
        offset - meta.frame_offset,
        offset,
        warnings,
    )
    return DecodedAudio(info, tuple(frames))
