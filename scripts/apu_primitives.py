"""Bit-accurate APU-P4 primitive reference model."""

from __future__ import annotations

from dataclasses import dataclass, field

from apu_isa import (
    BitstreamOpcode,
    EntropyOpcode,
    Entry,
    Instruction,
    InstructionClass,
    KernelOpcode,
    LocalOpcode,
)


LOCAL_DATA_BYTES = 0x1C000
CODEC_BYTES = 0xA000
TABLE_SCRATCH_BYTES = 0x6000
INPUT_BASE = 0x6000
OUTPUT_BASE = 0x8000
KWS_BASE = 0xA000
INTERNAL_BASE = 0x1A000


class PrimitiveFault(RuntimeError):
    def __init__(self, code: int, stage: int, reason: int = 9):
        self.code = code
        self.stage = stage
        self.reason = reason
        super().__init__(f"APU primitive fault code={code} stage={stage} reason={reason}")


@dataclass
class LocalMemory:
    data: bytearray = field(default_factory=lambda: bytearray(LOCAL_DATA_BYTES))
    valid_words: list[bool] = field(default_factory=lambda: [False] * (CODEC_BYTES // 4))
    table_bytes: int = 0
    image_valid: bool = False

    def publish_table(self, payload: bytes) -> None:
        if len(payload) > TABLE_SCRATCH_BYTES or len(payload) & 3:
            raise ValueError("P4 table payload is outside the frozen workspace")
        self.data[: len(payload)] = payload
        self.table_bytes = len(payload)
        self.image_valid = True

    def invalidate_image(self) -> None:
        self.image_valid = False
        self.table_bytes = 0

    def new_epoch(self) -> None:
        self.valid_words = [False] * len(self.valid_words)

    def _check_range(self, address: int, size: int, entry: Entry, table: bool = False) -> None:
        if address < 0 or size < 1 or address + size > LOCAL_DATA_BYTES:
            raise PrimitiveFault(11, 11, 5)
        if table:
            first = entry.table_offset
            last = first + entry.table_bytes
            if not self.image_valid or address < first or address + size > last:
                raise PrimitiveFault(11, 11, 5)
        else:
            first = entry.scratch_base
            last = first + entry.scratch_bytes
            if address < first or address + size > last:
                raise PrimitiveFault(11, 11, 5)

    def read(self, address: int, size: int, entry: Entry, table: bool = False) -> bytes:
        self._check_range(address, size, entry, table)
        if not table:
            first_word = address // 4
            last_word = (address + size - 1) // 4
            if any(not self.valid_words[index] for index in range(first_word, last_word + 1)):
                raise PrimitiveFault(11, 11, 5)
        return bytes(self.data[address : address + size])

    def write(self, address: int, payload: bytes, entry: Entry) -> None:
        self._check_range(address, len(payload), entry)
        if address < self.table_bytes:
            raise PrimitiveFault(11, 11, 5)
        self.data[address : address + len(payload)] = payload
        first_word = address // 4
        last_word = (address + len(payload) - 1) // 4
        for index in range(first_word, last_word + 1):
            self.valid_words[index] = True

    def inject(self, address: int, payload: bytes) -> None:
        if address < 0 or address + len(payload) > CODEC_BYTES:
            raise ValueError("verification injection exceeds the P4 codec region")
        self.data[address : address + len(payload)] = payload
        first_word = address // 4
        last_word = (address + len(payload) - 1) // 4
        for index in range(first_word, last_word + 1):
            self.valid_words[index] = True


@dataclass
class PrimitiveFifo:
    words: list[int] = field(default_factory=list)

    @property
    def full(self) -> bool:
        return len(self.words) == 64

    @property
    def empty(self) -> bool:
        return not self.words

    def push(self, word: int) -> None:
        if self.full or word & (0x1F << 35) or not 1 <= ((word >> 32) & 7) <= 4:
            raise PrimitiveFault(22, 7)
        self.words.append(word & ((1 << 41) - 1))

    def pop(self) -> int:
        if self.empty:
            raise PrimitiveFault(22, 4)
        return self.words.pop(0)

    def flush(self) -> None:
        self.words.clear()


@dataclass
class PrimitiveResult:
    writes: dict[int, int] = field(default_factory=dict)
    cycles: int = 1
    kernel_done: bool = False


class PrimitiveBam:
    def __init__(self, memory: LocalMemory | None = None):
        self.memory = memory if memory is not None else LocalMemory()
        self.input_fifo = PrimitiveFifo()
        self.output_fifo = PrimitiveFifo()
        self.bits: list[int] = []
        self.eof = False
        self.bit_position = 0
        self.kernel_done = False
        self.resample_profile: int | None = None

    @staticmethod
    def signed(value: int, width: int = 32) -> int:
        value &= (1 << width) - 1
        return value - (1 << width) if value & (1 << (width - 1)) else value

    @staticmethod
    def sat(value: int, width: int) -> int:
        return min(max(value, -(1 << (width - 1))), (1 << (width - 1)) - 1)

    @staticmethod
    def rne(value: int, shift: int) -> int:
        if shift == 0:
            return value
        magnitude = abs(value)
        quotient, remainder = divmod(magnitude, 1 << shift)
        halfway = 1 << (shift - 1)
        if remainder > halfway or (remainder == halfway and quotient & 1):
            quotient += 1
        return -quotient if value < 0 else quotient

    @staticmethod
    def _u32(value: int) -> int:
        return value & 0xFFFFFFFF

    def reset_mutable(self) -> None:
        self.memory.new_epoch()
        self.input_fifo.flush()
        self.output_fifo.flush()
        self.bits.clear()
        self.eof = False
        self.bit_position = 0
        self.kernel_done = False
        self.resample_profile = None

    def _refill(self, width: int) -> None:
        while len(self.bits) < width and not self.input_fifo.empty:
            word = self.input_fifo.pop()
            count = (word >> 32) & 7
            for byte_index in range(count):
                byte = (word >> (8 * byte_index)) & 0xFF
                self.bits.extend((byte >> bit_index) & 1 for bit_index in range(7, -1, -1))
            if word & (1 << 40):
                self.eof = True

    def _peek_bits(self, width: int, stage: int) -> int:
        self._refill(width)
        if len(self.bits) < width:
            raise PrimitiveFault(5, stage)
        value = 0
        for bit in self.bits[:width]:
            value = (value << 1) | bit
        return value

    def _get_bits(self, width: int, stage: int) -> int:
        value = self._peek_bits(width, stage)
        del self.bits[:width]
        self.bit_position = (self.bit_position + width) & 7
        return value

    def _read_u32(self, address: int, entry: Entry, table: bool = False) -> int:
        return int.from_bytes(self.memory.read(address, 4, entry, table), "little")

    def _read_s32(self, address: int, entry: Entry, table: bool = False) -> int:
        return self.signed(self._read_u32(address, entry, table))

    def _write_s32(self, address: int, value: int, entry: Entry) -> None:
        self.memory.write(address, self._u32(value).to_bytes(4, "little"), entry)

    def _resolve_ref(self, word: int, entry: Entry, size: int, *, state: bool = False) -> tuple[int, bool]:
        table = bool(word & 0x80000000)
        if word & (0x7FFF0000 if table else 0x7FFE0000) or word & 3:
            raise PrimitiveFault(11, 11, 5)
        if state and table:
            raise PrimitiveFault(11, 11, 5)
        offset = word & (0xFFFF if table else 0x1FFFF)
        address = (entry.table_offset if table else entry.scratch_base) + offset
        self.memory._check_range(address, size, entry, table)
        return address, table

    def _dot(self, left: list[int], right: list[int]) -> int:
        total = sum(a * b for a, b in zip(left, right, strict=True))
        if total < -(1 << 71) or total > (1 << 71) - 1:
            raise PrimitiveFault(22, 6)
        return total

    def execute(self, instruction: Instruction, registers: list[int], entry: Entry) -> PrimitiveResult:
        instruction_class = instruction.instruction_class
        if instruction_class == InstructionClass.BITSTREAM:
            return self._execute_bitstream(instruction, registers)
        if instruction_class == InstructionClass.ENTROPY:
            return self._execute_entropy(instruction, registers, entry)
        if instruction_class == InstructionClass.LOCAL:
            return self._execute_local(instruction, registers, entry)
        if instruction_class == InstructionClass.KERNEL:
            return self._execute_kernel(instruction, registers, entry)
        raise ValueError("instruction is not an APU-P4 primitive")

    def _execute_bitstream(self, instruction: Instruction, registers: list[int]) -> PrimitiveResult:
        opcode = BitstreamOpcode(instruction.opcode)
        width = instruction.immediate & 0x3F
        writes: dict[int, int] = {}
        cycles = 1
        if opcode == BitstreamOpcode.REFILL:
            self._refill(width)
            writes[instruction.dst] = min(len(self.bits), 64)
            cycles = 3
        elif opcode == BitstreamOpcode.PEEK:
            writes[instruction.dst] = self._peek_bits(width, 4)
        elif opcode == BitstreamOpcode.GET:
            writes[instruction.dst] = self._get_bits(width, 4)
        elif opcode == BitstreamOpcode.SKIP:
            self._get_bits(width, 4)
        elif opcode == BitstreamOpcode.ALIGN:
            skip = (-self.bit_position) & 7
            if skip:
                self._get_bits(skip, 4)
        elif opcode == BitstreamOpcode.FRAME_SYNC:
            if self.bit_position:
                self._get_bits((-self.bit_position) & 7, 4)
            pattern = registers[instruction.src0] & 0xFFFF
            mask = registers[instruction.src1] & 0xFFFF
            width = instruction.aux & 0x1F
            skipped = 0
            while skipped < instruction.immediate:
                if self._peek_bits(width, 4) & mask == pattern & mask:
                    writes[instruction.dst] = skipped
                    cycles = 2 + 2 * skipped
                    break
                if skipped + 1 == instruction.immediate:
                    raise PrimitiveFault(4, 4)
                self._get_bits(8, 4)
                skipped += 1
            else:
                raise PrimitiveFault(4, 4)
        elif opcode == BitstreamOpcode.CRC8:
            crc = registers[instruction.src0] & 0xFF
            byte = registers[instruction.src1] & 0xFF
            for bit_index in range(8):
                feedback = ((crc >> 7) ^ (byte >> (7 - bit_index))) & 1
                crc = (crc << 1) & 0xFF
                if feedback:
                    crc ^= 0x07
            writes[instruction.dst] = crc
        else:
            crc = registers[instruction.src0] & 0xFFFF
            byte = registers[instruction.src1] & 0xFF
            for bit_index in range(8):
                feedback = ((crc >> 15) ^ (byte >> (7 - bit_index))) & 1
                crc = (crc << 1) & 0xFFFF
                if feedback:
                    crc ^= 0x8005
            writes[instruction.dst] = crc
        return PrimitiveResult(writes, cycles)

    def _execute_entropy(
        self, instruction: Instruction, registers: list[int], entry: Entry
    ) -> PrimitiveResult:
        opcode = EntropyOpcode(instruction.opcode)
        writes: dict[int, int] = {}
        if opcode <= EntropyOpcode.HUFF_QUAD:
            count = registers[instruction.src1]
            if not 1 <= count <= 4096:
                raise PrimitiveFault(7, 5)
            start = entry.table_offset + registers[instruction.src0]
            entries = [self._read_u32(start + index * 4, entry, True) for index in range(count)]
            code = 0
            previous_length = 0
            match = None
            for word in entries:
                length = (word >> 16) & 0x1F
                if not previous_length <= length <= instruction.aux or word >> 21:
                    raise PrimitiveFault(7, 5)
                code <<= length - previous_length
                if self._peek_bits(length, 5) == code:
                    match = (word & 0xFFFF, length)
                    break
                code += 1
                previous_length = length
            if match is None:
                raise PrimitiveFault(7, 5)
            symbol, length = match
            self._get_bits(length, 5)
            if opcode == EntropyOpcode.HUFF_SYMBOL:
                writes[instruction.dst] = symbol
            elif opcode == EntropyOpcode.HUFF_PAIR:
                writes[instruction.dst] = (symbol >> 4) & 0xF
                writes[instruction.dst + 1] = symbol & 0xF
            else:
                for index in range(4):
                    writes[instruction.dst + index] = (symbol >> (3 - index)) & 1
            return PrimitiveResult(writes, 2 + 24 + count)
        if opcode == EntropyOpcode.UNARY:
            polarity = instruction.aux & 1
            run = 0
            while run <= instruction.immediate:
                bit = self._get_bits(1, 5)
                if bit != polarity:
                    writes[instruction.dst] = run
                    return PrimitiveResult(writes, 2 + run)
                run += 1
            raise PrimitiveFault(7, 5)
        if opcode in (EntropyOpcode.RICE4, EntropyOpcode.RICE5):
            width = 4 if opcode == EntropyOpcode.RICE4 else 5
            escape = 15 if width == 4 else 31
            parameter = registers[instruction.src0] & ((1 << width) - 1)
            if parameter == escape:
                raw_width = registers[instruction.src1] & 0x3F
                if not 1 <= raw_width <= 32:
                    raise PrimitiveFault(7, 5)
                value = self._get_bits(raw_width, 5)
                writes[instruction.dst] = self._u32(self.signed(value, raw_width))
                return PrimitiveResult(writes, 4 + raw_width)
            quotient = 0
            while self._get_bits(1, 5) == 0:
                quotient += 1
                if quotient > 65535:
                    raise PrimitiveFault(7, 5)
            remainder = self._get_bits(parameter, 5) if parameter else 0
            unsigned = (quotient << parameter) | remainder
            writes[instruction.dst] = self._u32((unsigned >> 1) ^ -(unsigned & 1))
            return PrimitiveResult(writes, 4 + quotient + parameter)
        magnitude = registers[instruction.src0]
        if magnitude == 0:
            writes[instruction.dst] = 0
            return PrimitiveResult(writes, 3)
        linbits = registers[instruction.src1] & 0x1F
        extra = self._get_bits(linbits, 5) if linbits else 0
        value = magnitude + extra
        if self._get_bits(1, 5):
            value = -value
        writes[instruction.dst] = self._u32(value)
        return PrimitiveResult(writes, 3 + linbits)

    def _execute_local(
        self, instruction: Instruction, registers: list[int], entry: Entry
    ) -> PrimitiveResult:
        opcode = LocalOpcode(instruction.opcode)
        writes: dict[int, int] = {}
        if opcode in (LocalOpcode.LD32, LocalOpcode.ST32):
            offset = self.signed(instruction.immediate, 16)
            address = entry.scratch_base + registers[instruction.src0] + offset
            if address & 3:
                raise PrimitiveFault(11, 11, 5)
            if opcode == LocalOpcode.LD32:
                writes[instruction.dst] = self._read_u32(address, entry)
                return PrimitiveResult(writes, 2)
            self._write_s32(address, registers[instruction.src1], entry)
            return PrimitiveResult(cycles=1)
        if opcode in (LocalOpcode.TABLE8, LocalOpcode.TABLE16, LocalOpcode.TABLE32):
            size = 1 << (instruction.opcode - LocalOpcode.TABLE8)
            address = entry.table_offset + registers[instruction.src0] + registers[instruction.src1] * size
            if address & (size - 1):
                raise PrimitiveFault(11, 11, 5)
            writes[instruction.dst] = int.from_bytes(self.memory.read(address, size, entry, True), "little")
            return PrimitiveResult(writes, 2)
        if opcode == LocalOpcode.FIFO_POP:
            word = self.input_fifo.pop()
            writes[instruction.dst] = word & 0xFFFFFFFF
            writes[instruction.dst + 1] = ((word >> 32) & 7) | (((word >> 40) & 1) << 8)
            return PrimitiveResult(writes)
        metadata = registers[instruction.src1]
        if metadata & ~0x107 or not 1 <= (metadata & 7) <= 4:
            raise PrimitiveFault(22, 7)
        self.output_fifo.push(
            (registers[instruction.src0] & 0xFFFFFFFF)
            | ((metadata & 7) << 32)
            | (((metadata >> 8) & 1) << 40)
        )
        return PrimitiveResult()

    def _kernel_arrays(
        self, instruction: Instruction, registers: list[int], entry: Entry
    ) -> tuple[int, int, int, int]:
        count = instruction.immediate & 0xFFFF
        input_address = entry.scratch_base + registers[instruction.src0]
        parameter_address = entry.scratch_base + registers[instruction.src1]
        output_address = entry.scratch_base + registers[instruction.dst]
        output_alignment = (
            2
            if instruction.opcode == KernelOpcode.PCM_PACK and (instruction.aux & 3) == 0
            else 4
        )
        if (
            entry.scratch_base & 3
            or input_address & 3
            or parameter_address & 3
            or output_address & (output_alignment - 1)
        ):
            raise PrimitiveFault(11, 11, 5)
        self.memory._check_range(parameter_address, 4, entry)
        return count, input_address, parameter_address, output_address

    def _execute_kernel(
        self, instruction: Instruction, registers: list[int], entry: Entry
    ) -> PrimitiveResult:
        opcode = KernelOpcode(instruction.opcode)
        count, input_address, parameter_address, output_address = self._kernel_arrays(
            instruction, registers, entry
        )
        produced = 0
        cycles = 8
        if opcode == KernelOpcode.REQUANT:
            reference = self._read_u32(parameter_address, entry)
            scale_address, scale_table = self._resolve_ref(reference, entry, count * 4)
            self.memory._check_range(input_address, count * 4, entry)
            width = (16, 24, 32)[instruction.aux >> 6]
            shift = 30 + (instruction.aux & 0x1F)
            for index in range(count):
                sample = self._read_s32(input_address + index * 4, entry)
                scale = self._read_s32(scale_address + index * 4, entry, scale_table)
                product = sample * scale
                value = self.rne(product, shift) if instruction.aux & 0x20 else product >> shift
                self._write_s32(output_address + index * 4, self.sat(value, width), entry)
            produced, cycles = count, 8 + 4 * count
        elif opcode in (KernelOpcode.STEREO, KernelOpcode.DECORRELATE):
            reference = self._read_u32(parameter_address, entry)
            second_address, _ = self._resolve_ref(reference, entry, count * 4, state=True)
            self.memory._check_range(input_address, count * 4, entry)
            for index in range(count):
                left = self._read_s32(input_address + index * 4, entry)
                right = self._read_s32(second_address + index * 4, entry)
                mode = instruction.aux & 3
                if mode == 0:
                    pair = left, right
                elif mode == 1:
                    pair = left, left - right
                elif mode == 2:
                    pair = left + right, right
                else:
                    middle = left * 2 + (right & 1)
                    pair = (middle + right) >> 1, (middle - right) >> 1
                if opcode == KernelOpcode.DECORRELATE and any(
                    value < -(1 << 31) or value > (1 << 31) - 1 for value in pair
                ):
                    raise PrimitiveFault(8, 6)
                for channel, value in enumerate(pair):
                    self._write_s32(output_address + (channel * count + index) * 4, self.sat(value, 32), entry)
            produced, cycles = 2 * count, 8 + 4 * count
        elif opcode in (KernelOpcode.IMDCT6, KernelOpcode.IMDCT18):
            order = 6 if opcode == KernelOpcode.IMDCT6 else 18
            reference = self._read_u32(parameter_address, entry)
            matrix_address, matrix_table = self._resolve_ref(reference, entry, 2 * order * order * 4)
            self.memory._check_range(input_address, count * order * 4, entry)
            for block in range(count):
                values = [self._read_s32(input_address + (block * order + item) * 4, entry) for item in range(order)]
                for row in range(2 * order):
                    coefficients = [
                        self._read_s32(matrix_address + (row * order + item) * 4, entry, matrix_table)
                        for item in range(order)
                    ]
                    value = self.sat(self.rne(self._dot(values, coefficients), 30), 32)
                    self._write_s32(output_address + (block * 2 * order + row) * 4, value, entry)
            produced = count * 2 * order
            cycles = 8 + (94 if order == 6 else 706) * count
        elif opcode == KernelOpcode.FIXED:
            order = instruction.aux & 7
            reference = self._read_u32(parameter_address, entry)
            history_address, _ = self._resolve_ref(reference, entry, max(order, 1) * 4, state=True)
            history = [self._read_s32(history_address + index * 4, entry) for index in range(order)]
            self.memory._check_range(input_address, count * 4, entry)
            for index in range(count):
                if order == 0:
                    predictor = 0
                elif order == 1:
                    predictor = history[0]
                elif order == 2:
                    predictor = 2 * history[0] - history[1]
                elif order == 3:
                    predictor = 3 * history[0] - 3 * history[1] + history[2]
                else:
                    predictor = 4 * history[0] - 6 * history[1] + 4 * history[2] - history[3]
                value = predictor + self._read_s32(input_address + index * 4, entry)
                if value < -(1 << 31) or value > (1 << 31) - 1:
                    raise PrimitiveFault(8, 6)
                self._write_s32(output_address + index * 4, value, entry)
                if order:
                    history = [value, *history[:-1]]
            for index, value in enumerate(history):
                self._write_s32(history_address + index * 4, value, entry)
            produced, cycles = count, 8 + (order + 4) * count
        elif opcode == KernelOpcode.LPC:
            order = instruction.aux & 0x3F
            coefficient_ref = self._read_u32(parameter_address, entry)
            history_ref = self._read_u32(parameter_address + 4, entry)
            shift = self.signed(self._read_u32(parameter_address + 8, entry), 32)
            if not -31 <= shift <= 31:
                raise PrimitiveFault(11, 11, 5)
            coefficient_address, coefficient_table = self._resolve_ref(coefficient_ref, entry, order * 4)
            history_address, _ = self._resolve_ref(history_ref, entry, order * 4, state=True)
            coefficients = [
                self._read_s32(coefficient_address + index * 4, entry, coefficient_table)
                for index in range(order)
            ]
            history = [self._read_s32(history_address + index * 4, entry) for index in range(order)]
            for index in range(count):
                predictor = self._dot(coefficients, history)
                predictor = predictor >> shift if shift >= 0 else predictor << -shift
                value = predictor + self._read_s32(input_address + index * 4, entry)
                if value < -(1 << 31) or value > (1 << 31) - 1:
                    raise PrimitiveFault(8, 6)
                self._write_s32(output_address + index * 4, value, entry)
                history = [value, *history[:-1]]
            for index, value in enumerate(history):
                self._write_s32(history_address + index * 4, value, entry)
            produced, cycles = count, 8 + (2 * order + 5) * count
        elif opcode == KernelOpcode.PCM_PACK:
            gain = self._read_s32(parameter_address, entry)
            channels = self._read_u32(parameter_address + 4, entry)
            if channels not in (1, 2) or (instruction.aux & 4 and channels != 1):
                raise PrimitiveFault(8, 7)
            samples = count * channels
            output = bytearray()
            for index in range(samples):
                sample = self._read_s32(input_address + index * 4, entry)
                value = self.rne(sample * gain, 30)
                packed = self.sat(value, 16 if (instruction.aux & 3) == 0 else 24)
                encoded = self._u32(packed).to_bytes(4, "little")
                encoded = encoded[:2] if (instruction.aux & 3) == 0 else encoded
                output.extend(encoded)
                if instruction.aux & 4:
                    output.extend(encoded)
            self.memory.write(output_address, output, entry)
            produced, cycles = len(output), 8 + 5 * (count * (2 if instruction.aux & 4 else channels))
        elif opcode == KernelOpcode.RESAMPLE:
            produced, cycles = self._resample(instruction, count, input_address, parameter_address, output_address, entry)
        else:
            produced, cycles = self._dct32(count, input_address, parameter_address, output_address, entry)
        self.kernel_done = True
        return PrimitiveResult({instruction.dst: produced}, cycles, True)

    def _dct32(self, count: int, input_address: int, parameter_address: int,
               output_address: int, entry: Entry) -> tuple[int, int]:
        refs = [self._read_u32(parameter_address + index * 4, entry) for index in range(3)]
        phase = self._read_u32(parameter_address + 12, entry)
        if phase >> 4:
            raise PrimitiveFault(11, 11, 5)
        matrix_address, matrix_table = self._resolve_ref(refs[0], entry, 32 * 32 * 4)
        window_address, window_table = self._resolve_ref(refs[1], entry, 16 * 32 * 4)
        history_address, _ = self._resolve_ref(refs[2], entry, 16 * 32 * 4, state=True)
        for block in range(count):
            values = [self._read_s32(input_address + (block * 32 + item) * 4, entry) for item in range(32)]
            transformed = []
            for row in range(32):
                coefficients = [
                    self._read_s32(matrix_address + (row * 32 + item) * 4, entry, matrix_table)
                    for item in range(32)
                ]
                transformed.append(self.sat(self.rne(self._dot(values, coefficients), 30), 32))
            for item, value in enumerate(transformed):
                self._write_s32(history_address + (phase * 32 + item) * 4, value, entry)
            for item in range(32):
                history = [
                    self._read_s32(history_address + (((phase - tap) & 15) * 32 + item) * 4, entry)
                    for tap in range(16)
                ]
                window = [
                    self._read_s32(window_address + (tap * 32 + item) * 4, entry, window_table)
                    for tap in range(16)
                ]
                self._write_s32(
                    output_address + (block * 32 + item) * 4,
                    self.sat(self.rne(self._dot(history, window), 30), 32),
                    entry,
                )
            phase = (phase + 1) & 15
        self._write_s32(parameter_address + 12, phase, entry)
        return 32 * count, 8 + 2304 * count

    def _resample(self, instruction: Instruction, count: int, input_address: int,
                  parameter_address: int, output_address: int, entry: Entry) -> tuple[int, int]:
        ratios = (
            (1, 1), (1, 2), (80, 147), (160, 147), (3, 2), (2, 1), (3, 1), (4, 1),
            (6, 1), (8, 1), (12, 1), (320, 147), (640, 147), (1280, 147), (2, 3), (4, 3),
        )
        profile = instruction.aux & 15
        if self.resample_profile is None:
            self.resample_profile = profile
        elif profile != self.resample_profile:
            raise PrimitiveFault(8, 7)
        refs = [self._read_u32(parameter_address + index * 4, entry) for index in range(3)]
        next_output = self._read_u32(parameter_address + 12, entry) | (
            self._read_u32(parameter_address + 16, entry) << 32
        )
        input_base = self._read_u32(parameter_address + 20, entry) | (
            self._read_u32(parameter_address + 24, entry) << 32
        )
        channels = self._read_u32(parameter_address + 28, entry)
        if channels not in (1, 2):
            raise PrimitiveFault(8, 7)
        if profile == 0:
            payload = self.memory.read(input_address, count * channels * 4, entry)
            self.memory.write(output_address, payload, entry)
            next_output += count
            input_base += count
            produced = count
            cycles = 8 + 2 * count * channels
        else:
            bank_index = 2 if profile in (1, 2) else (1 if profile == 14 else 0)
            coefficient_address, coefficient_table = self._resolve_ref(refs[bank_index], entry, 32 * 16 * 4)
            numerator, denominator = ratios[profile]
            produced = 0
            while next_output // numerator < input_base + count:
                source_index, remainder = divmod(next_output, numerator)
                quotient, phase_remainder = divmod(32 * remainder, numerator)
                phase = quotient
                doubled_remainder = 2 * phase_remainder
                if doubled_remainder > numerator or (
                    doubled_remainder == numerator and phase & 1
                ):
                    phase += 1
                if phase == 32:
                    phase = 0
                    source_index += 1
                for channel in range(channels):
                    samples = [
                        self._read_s32(
                            input_address + ((source_index + tap - 7 - input_base) * channels + channel) * 4,
                            entry,
                        )
                        for tap in range(16)
                    ]
                    coefficients = [
                        self._read_s32(coefficient_address + (phase * 16 + tap) * 4, entry, coefficient_table)
                        for tap in range(16)
                    ]
                    self._write_s32(
                        output_address + (produced * channels + channel) * 4,
                        self.sat(self.rne(self._dot(samples, coefficients), 30), 32),
                        entry,
                    )
                produced += 1
                next_output += denominator
            input_base += count
            cycles = 8 + 2 * count * channels + 36 * produced * channels
        for index, value in enumerate((next_output, input_base)):
            self._write_s32(parameter_address + 12 + index * 8, value & 0xFFFFFFFF, entry)
            self._write_s32(parameter_address + 16 + index * 8, value >> 32, entry)
        return produced, cycles
