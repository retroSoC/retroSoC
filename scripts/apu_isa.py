"""Frozen APU microcode V1 encoding and APUMC bundle helpers."""

from __future__ import annotations

import binascii
import struct
from dataclasses import dataclass
from enum import IntEnum
from typing import Iterable


APUMC_MAGIC = 0x41504D43
APUMC_ABI = 0x00010000
APUMC_HEADER_BYTES = 64
APUMC_ENTRY_BYTES = 32
APUMC_ENTRY_COUNT = 3
APUMC_INSTRUCTION_OFFSET = 192
APUMC_MAX_INSTRUCTIONS = 2048
APUMC_P3_CAPABILITY_MASK = 0


class InstructionClass(IntEnum):
    CONTROL = 0
    SCALAR = 1
    BITSTREAM = 2
    ENTROPY = 3
    LOCAL = 4
    KERNEL = 5
    TRANSPORT = 6


class ControlOpcode(IntEnum):
    NOP = 0
    END = 1
    TRAP = 2
    JUMP_FWD = 3
    CALL_FWD = 4
    RET = 5
    LOOP_SETUP = 6
    LOOP_BACK = 7
    WAIT = 8


class ScalarOpcode(IntEnum):
    MOV = 0
    MOVI = 1
    ADD = 2
    SUB = 3
    AND = 4
    OR = 5
    XOR = 6
    SHL = 7
    SHR = 8
    SAR = 9
    CMP = 10
    MIN = 11
    MAX = 12
    SAT = 13


PREDICATES = {
    "always": 0,
    "eq": 1,
    "ne": 2,
    "slt": 3,
    "sge": 4,
    "ult": 5,
    "uge": 6,
    "input_exhausted": 7,
    "input_ready": 8,
    "output_ready": 9,
    "kernel_done": 10,
    "transport_done": 11,
}

CONTROL_OPCODES = {opcode.name.lower(): int(opcode) for opcode in ControlOpcode}
SCALAR_OPCODES = {opcode.name.lower(): int(opcode) for opcode in ScalarOpcode}
DEFERRED_OPCODES = {
    "bitstream": ("refill", "peek", "get", "skip", "align", "frame_sync", "crc8", "crc16"),
    "entropy": ("huff_symbol", "huff_pair", "huff_quad", "unary", "rice4", "rice5", "sign_restore"),
    "local": ("ld32", "st32", "table8", "table16", "table32", "fifo_pop", "fifo_push"),
    "kernel": (
        "requant",
        "stereo",
        "imdct6",
        "imdct18",
        "dct32_poly",
        "fixed",
        "lpc",
        "decorrelate",
        "resample",
        "pcm_pack",
    ),
    "transport": (
        "input_refill",
        "output_commit",
        "output_stream",
        "dma_wait",
        "frame_commit",
        "job_result",
        "event",
    ),
}
WAIT_SOURCES = ("dma", "kernel", "input_fifo", "output_fifo", "tx_stream", "ring_writeback")
PRIMITIVES = (
    "bitstream",
    "crc",
    "huffman",
    "rice",
    "local_memory",
    "local_fifo",
    "requantize",
    "stereo",
    "imdct6",
    "imdct18",
    "dct32_poly",
    "fixed",
    "lpc",
    "decorrelate",
    "resampler",
    "pcm_pack",
    "dma_input",
    "dma_output",
    "stream_output",
    "frame_commit",
    "event",
)
TRAP_REASONS = (
    "reserved",
    "illegal",
    "pc_range",
    "call_stack",
    "loop",
    "local_range",
    "unavailable",
    "watchdog",
    "retired_budget",
    "engine",
    "explicit",
)


def abi_manifest() -> dict[str, object]:
    """Return the canonical P3 ABI input consumed by generated tool reports."""

    return {
        "apumc": {
            "magic": APUMC_MAGIC,
            "abi": APUMC_ABI,
            "header_bytes": APUMC_HEADER_BYTES,
            "entry_bytes": APUMC_ENTRY_BYTES,
            "entry_count": APUMC_ENTRY_COUNT,
            "max_instructions": APUMC_MAX_INSTRUCTIONS,
        },
        "classes": {item.name.lower(): int(item) for item in InstructionClass},
        "control_opcodes": CONTROL_OPCODES,
        "scalar_opcodes": SCALAR_OPCODES,
        "deferred_opcodes": {
            name: {opcode: number for number, opcode in enumerate(opcodes)}
            for name, opcodes in DEFERRED_OPCODES.items()
        },
        "predicates": PREDICATES,
        "wait_sources": {name: number for number, name in enumerate(WAIT_SOURCES)},
        "primitives": {name: number for number, name in enumerate(PRIMITIVES)},
        "trap_reasons": {name: number for number, name in enumerate(TRAP_REASONS)},
        "instruction_fields": {
            "immediate": 0,
            "aux": 32,
            "src1": 40,
            "src0": 44,
            "dst": 48,
            "predicate": 52,
            "opcode": 56,
            "class": 60,
        },
        "entry_words": {
            "format_pc": 0,
            "range": 1,
            "scratch_base": 2,
            "scratch_bytes": 3,
            "max_loop": 4,
            "max_retired": 5,
            "primitives": 6,
            "table": 7,
        },
        "p3_implemented_primitive_mask": APUMC_P3_CAPABILITY_MASK,
    }


@dataclass(frozen=True)
class Instruction:
    instruction_class: int
    opcode: int
    predicate: int = 0
    dst: int = 0
    src0: int = 0
    src1: int = 0
    aux: int = 0
    immediate: int = 0

    def encode(self) -> int:
        fields = (
            (self.instruction_class, 4, 60),
            (self.opcode, 4, 56),
            (self.predicate, 4, 52),
            (self.dst, 4, 48),
            (self.src0, 4, 44),
            (self.src1, 4, 40),
            (self.aux, 8, 32),
            (self.immediate, 32, 0),
        )
        word = 0
        for value, width, shift in fields:
            if value < 0 or value >= (1 << width):
                raise ValueError(f"field value {value} does not fit {width} bits")
            word |= value << shift
        return word

    @classmethod
    def decode(cls, word: int) -> Instruction:
        if word < 0 or word >= (1 << 64):
            raise ValueError("instruction must fit 64 bits")
        return cls(
            instruction_class=(word >> 60) & 0xF,
            opcode=(word >> 56) & 0xF,
            predicate=(word >> 52) & 0xF,
            dst=(word >> 48) & 0xF,
            src0=(word >> 44) & 0xF,
            src1=(word >> 40) & 0xF,
            aux=(word >> 32) & 0xFF,
            immediate=word & 0xFFFFFFFF,
        )


@dataclass(frozen=True)
class Entry:
    format_id: int
    entry_pc: int
    first_pc: int
    last_pc: int
    max_loop_count: int
    max_retired: int
    scratch_base: int = 0
    scratch_bytes: int = 0
    primitive_mask: int = 0
    table_offset: int = 0
    table_bytes: int = 0

    def words(self) -> tuple[int, ...]:
        return (
            self.format_id | (self.entry_pc << 4),
            self.first_pc | (self.last_pc << 16),
            self.scratch_base,
            self.scratch_bytes,
            self.max_loop_count,
            self.max_retired,
            self.primitive_mask,
            self.table_offset | (self.table_bytes << 16),
        )


def crc32_iso_hdlc(payload: bytes) -> int:
    """Return the reflected ISO-HDLC CRC used by APUMC."""

    return binascii.crc32(payload) & 0xFFFFFFFF


def trap_detail(reason: int, pc: int, instruction: Instruction) -> int:
    return (
        (reason & 0xFF)
        | ((pc & 0x7FF) << 8)
        | ((instruction.instruction_class & 0xF) << 19)
        | ((instruction.opcode & 0xF) << 23)
        | ((instruction.aux & 0x1F) << 27)
    )


def _require_zero(instruction: Instruction, names: Iterable[str]) -> None:
    for name in names:
        if getattr(instruction, name) != 0:
            raise ValueError(f"{name} is reserved for this opcode")


def validate_p3_instruction(instruction: Instruction) -> None:
    """Validate one instruction against the P3 class-0/class-1 subset."""

    if instruction.predicate > 11:
        raise ValueError("predicate is reserved")
    if instruction.instruction_class == InstructionClass.CONTROL:
        if instruction.opcode > ControlOpcode.WAIT:
            raise ValueError("control opcode is unallocated")
        opcode = ControlOpcode(instruction.opcode)
        if opcode in (ControlOpcode.NOP, ControlOpcode.END):
            _require_zero(instruction, ("dst", "src0", "src1", "aux", "immediate"))
        elif opcode == ControlOpcode.TRAP:
            _require_zero(instruction, ("dst", "src0", "src1", "aux"))
        elif opcode in (ControlOpcode.JUMP_FWD, ControlOpcode.CALL_FWD):
            _require_zero(instruction, ("dst", "src0", "src1", "aux"))
            if not 1 <= instruction.immediate <= 0x7FF:
                raise ValueError("forward branch delta must be 1..2047")
        elif opcode == ControlOpcode.RET:
            _require_zero(instruction, ("dst", "src0", "src1", "aux", "immediate"))
            if instruction.predicate != 0:
                raise ValueError("RET predicate must be always")
        elif opcode == ControlOpcode.LOOP_SETUP:
            _require_zero(instruction, ("dst", "src1", "immediate"))
            if instruction.predicate != 0 or instruction.aux > 3:
                raise ValueError("LOOP_SETUP requires always predicate and slot 0..3")
        elif opcode == ControlOpcode.LOOP_BACK:
            _require_zero(instruction, ("dst", "src0", "src1"))
            if (
                instruction.predicate != 0
                or instruction.aux > 3
                or not 1 <= instruction.immediate <= 0x7FF
            ):
                raise ValueError("LOOP_BACK encoding is invalid")
        else:
            _require_zero(instruction, ("dst", "src0", "src1", "immediate"))
            if instruction.predicate != 0 or instruction.aux > 5:
                raise ValueError("WAIT encoding is invalid")
            raise ValueError("WAIT requires a primitive unavailable in P3")
        return

    if instruction.instruction_class != InstructionClass.SCALAR:
        if instruction.instruction_class <= 6:
            raise ValueError("instruction class is unavailable in P3")
        raise ValueError("instruction class is invalid in V1")
    if instruction.opcode > ScalarOpcode.SAT:
        raise ValueError("scalar opcode is unallocated")

    opcode = ScalarOpcode(instruction.opcode)
    if opcode == ScalarOpcode.MOV:
        _require_zero(instruction, ("src1", "aux", "immediate"))
    elif opcode == ScalarOpcode.MOVI:
        _require_zero(instruction, ("src0", "src1", "aux"))
    elif opcode in (
        ScalarOpcode.ADD,
        ScalarOpcode.SUB,
        ScalarOpcode.AND,
        ScalarOpcode.OR,
        ScalarOpcode.XOR,
        ScalarOpcode.SHL,
        ScalarOpcode.SHR,
        ScalarOpcode.SAR,
    ):
        _require_zero(instruction, ("aux", "immediate"))
    elif opcode == ScalarOpcode.CMP:
        _require_zero(instruction, ("dst", "aux", "immediate"))
    elif opcode in (ScalarOpcode.MIN, ScalarOpcode.MAX):
        _require_zero(instruction, ("immediate",))
        if instruction.aux > 1:
            raise ValueError("MIN/MAX aux must select unsigned or signed")
    elif opcode == ScalarOpcode.SAT:
        _require_zero(instruction, ("src1", "immediate"))
        if instruction.aux & 0xC0 or (instruction.aux & 0x1F) not in (0, 8, 16, 24):
            raise ValueError("SAT width/sign encoding is invalid")


def validate_entry(entry: Entry, instruction_count: int) -> None:
    if entry.format_id not in range(APUMC_ENTRY_COUNT):
        raise ValueError("entry format must be 0, 1, or 2")
    if not (0 <= entry.first_pc <= entry.entry_pc <= entry.last_pc < instruction_count):
        raise ValueError("entry PC range is invalid")
    if not 1 <= entry.max_loop_count <= 0xFFFF:
        raise ValueError("maximum loop count must be 1..65535")
    if not 1 <= entry.max_retired <= 0xFFFFFF:
        raise ValueError("maximum retired count must be 1..16777215")
    if any(
        (
            entry.scratch_base,
            entry.scratch_bytes,
            entry.primitive_mask,
            entry.table_offset,
            entry.table_bytes,
        )
    ):
        raise ValueError("P3 entries cannot use scratch, table, or primitives")


def control_flow_report(instructions: list[Instruction], entry: Entry) -> dict[str, object]:
    """Prove bounded V1 control flow and return its deterministic report."""

    loop_pairs: dict[int, int] = {}
    active_setup: dict[int, int] = {}
    intervals: list[tuple[int, int]] = []
    for pc in range(entry.first_pc, entry.last_pc + 1):
        instruction = instructions[pc]
        if instruction.instruction_class != InstructionClass.CONTROL:
            continue
        opcode = ControlOpcode(instruction.opcode)
        if opcode in (ControlOpcode.JUMP_FWD, ControlOpcode.CALL_FWD):
            target = pc + 1 + instruction.immediate
            if target > entry.last_pc:
                raise ValueError(f"entry {entry.format_id} branch at PC {pc} leaves its range")
        elif opcode == ControlOpcode.LOOP_SETUP:
            slot = instruction.aux & 3
            if slot in active_setup:
                raise ValueError(f"entry {entry.format_id} reuses active loop slot {slot}")
            active_setup[slot] = pc
        elif opcode == ControlOpcode.LOOP_BACK:
            slot = instruction.aux & 3
            if slot not in active_setup:
                raise ValueError(f"entry {entry.format_id} loop at PC {pc} has no setup")
            setup = active_setup.pop(slot)
            if pc + 1 - instruction.immediate != setup + 1:
                raise ValueError(f"entry {entry.format_id} loop at PC {pc} has wrong target")
            loop_pairs[pc] = setup + 1
            intervals.append((setup + 1, pc))
    if active_setup:
        raise ValueError(f"entry {entry.format_id} has an unterminated loop setup")
    for first_index, first in enumerate(intervals):
        for second in intervals[first_index + 1 :]:
            crossing = first[0] < second[0] <= first[1] < second[1]
            reverse_crossing = second[0] < first[0] <= second[1] < first[1]
            if crossing or reverse_crossing:
                raise ValueError(f"entry {entry.format_id} has crossing loops")

    State = tuple[int, tuple[int, ...], tuple[int | None, ...]]
    pending: list[State] = [(entry.entry_pc, (), (None, None, None, None))]
    visited: set[State] = set()
    edges: set[tuple[int, int, str]] = set()
    terminals: set[int] = set()
    maximum_call_depth = 0
    maximum_pending_states = 1
    while pending:
        maximum_pending_states = max(maximum_pending_states, len(pending))
        pc, returns, loops = pending.pop()
        state = (pc, returns, loops)
        if state in visited:
            continue
        visited.add(state)
        if pc < entry.first_pc or pc > entry.last_pc:
            raise ValueError(f"entry {entry.format_id} can fall outside its program range")
        instruction = instructions[pc]
        successors: list[State] = []
        predicate_may_be_false = instruction.predicate != 0
        if predicate_may_be_false:
            successors.append((pc + 1, returns, loops))
            edges.add((pc, pc + 1, "predicate_false"))
        if instruction.instruction_class != InstructionClass.CONTROL:
            successors.append((pc + 1, returns, loops))
            edges.add((pc, pc + 1, "fallthrough"))
        else:
            opcode = ControlOpcode(instruction.opcode)
            if opcode in (ControlOpcode.END, ControlOpcode.TRAP):
                terminals.add(pc)
            elif opcode == ControlOpcode.JUMP_FWD:
                target = pc + 1 + instruction.immediate
                successors.append((target, returns, loops))
                edges.add((pc, target, "jump_true"))
            elif opcode == ControlOpcode.CALL_FWD:
                if len(returns) == 4:
                    raise ValueError(f"entry {entry.format_id} can exceed four nested calls")
                target = pc + 1 + instruction.immediate
                successors.append((target, (*returns, pc + 1), loops))
                maximum_call_depth = max(maximum_call_depth, len(returns) + 1)
                edges.add((pc, target, "call_true"))
            elif opcode == ControlOpcode.RET:
                if not returns:
                    raise ValueError(f"entry {entry.format_id} can return with an empty stack")
                successors.append((returns[-1], returns[:-1], loops))
                edges.add((pc, returns[-1], "return"))
            elif opcode == ControlOpcode.LOOP_SETUP:
                slot = instruction.aux & 3
                if loops[slot] is not None:
                    raise ValueError(f"entry {entry.format_id} can reuse active loop slot {slot}")
                updated = list(loops)
                updated[slot] = pc + 1
                successors.append((pc + 1, returns, tuple(updated)))
                edges.add((pc, pc + 1, "loop_setup"))
            elif opcode == ControlOpcode.LOOP_BACK:
                slot = instruction.aux & 3
                if loops[slot] != loop_pairs.get(pc):
                    raise ValueError(f"entry {entry.format_id} has an invalid runtime loop path")
                successors.append((loop_pairs[pc], returns, loops))
                edges.add((pc, loop_pairs[pc], "loop_repeat"))
                updated = list(loops)
                updated[slot] = None
                successors.append((pc + 1, returns, tuple(updated)))
                edges.add((pc, pc + 1, "loop_exit"))
            elif opcode == ControlOpcode.NOP:
                successors.append((pc + 1, returns, loops))
                edges.add((pc, pc + 1, "fallthrough"))
            else:
                raise ValueError("WAIT requires a primitive unavailable in P3")
        pending.extend(successors)
        if len(visited) > APUMC_MAX_INSTRUCTIONS * 64:
            raise ValueError(f"entry {entry.format_id} control-flow proof exceeded its bound")
    if not terminals:
        raise ValueError(f"entry {entry.format_id} has no reachable END or TRAP")

    return {
        "entry": entry.format_id,
        "entry_pc": entry.entry_pc,
        "first_pc": entry.first_pc,
        "last_pc": entry.last_pc,
        "reachable_states": len(visited),
        "maximum_call_depth": maximum_call_depth,
        "maximum_pending_states": maximum_pending_states,
        "terminals": sorted(terminals),
        "loops": [
            {"setup_pc": first - 1, "first_pc": first, "back_pc": last}
            for first, last in sorted(intervals)
        ],
        "edges": [
            {"source": source, "target": target, "kind": kind}
            for source, target, kind in sorted(edges)
        ],
        "proof": "passed",
    }


def validate_control_flow(instructions: list[Instruction], entry: Entry) -> None:
    """Prove bounded V1 control flow for one entry descriptor."""

    control_flow_report(instructions, entry)


def build_apumc(instructions: list[Instruction], entries: list[Entry], build_id: int = 0) -> bytes:
    if not 1 <= len(instructions) <= APUMC_MAX_INSTRUCTIONS:
        raise ValueError("instruction count must be 1..2048")
    if len(entries) != APUMC_ENTRY_COUNT:
        raise ValueError("APUMC V1 requires exactly three entries")
    for index, entry in enumerate(entries):
        if entry.format_id != index:
            raise ValueError("entry descriptor order must be WAV, MP3, FLAC")
        validate_entry(entry, len(instructions))
    for instruction in instructions:
        validate_p3_instruction(instruction)
    for entry in entries:
        validate_control_flow(instructions, entry)

    descriptor = b"".join(struct.pack("<8I", *entry.words()) for entry in entries)
    padding = bytes(APUMC_INSTRUCTION_OFFSET - APUMC_HEADER_BYTES - len(descriptor))
    encoded = b"".join(struct.pack("<Q", instruction.encode()) for instruction in instructions)
    payload = descriptor + padding + encoded
    total_bytes = APUMC_HEADER_BYTES + len(payload)
    crc = crc32_iso_hdlc(payload)
    header = struct.pack(
        "<16I",
        APUMC_MAGIC,
        APUMC_ABI,
        total_bytes,
        len(instructions),
        APUMC_INSTRUCTION_OFFSET,
        0,
        0,
        APUMC_HEADER_BYTES,
        APUMC_ENTRY_COUNT,
        APUMC_P3_CAPABILITY_MASK,
        0,
        crc,
        build_id & 0xFFFFFFFF,
        (build_id >> 32) & 0xFFFFFFFF,
        0,
        0,
    )
    return header + payload


def parse_apumc(bundle: bytes) -> tuple[list[Instruction], list[Entry], tuple[int, ...]]:
    if len(bundle) < APUMC_HEADER_BYTES:
        raise ValueError("bundle is smaller than the APUMC header")
    header = struct.unpack_from("<16I", bundle)
    if (
        header[0] != APUMC_MAGIC
        or header[1] != APUMC_ABI
        or header[2] != len(bundle)
        or len(bundle) < 160
        or header[14] != 0
        or header[15] != 0
    ):
        raise ValueError("APUMC header is invalid")
    if header[8] != APUMC_ENTRY_COUNT:
        raise ValueError("APUMC V1 requires exactly three entries")
    instruction_count = header[3]
    instruction_offset = header[4]
    table_offset = header[5]
    table_bytes = header[6]
    entry_offset = header[7]
    instruction_end = instruction_offset + instruction_count * 8
    entry_end = entry_offset + APUMC_ENTRY_COUNT * APUMC_ENTRY_BYTES
    if not 1 <= instruction_count <= APUMC_MAX_INSTRUCTIONS:
        raise ValueError("APUMC instruction count is invalid")
    if (
        instruction_offset < APUMC_HEADER_BYTES
        or instruction_offset % 64 != 0
        or instruction_end > len(bundle)
        or entry_offset < APUMC_HEADER_BYTES
        or entry_offset % APUMC_ENTRY_BYTES != 0
        or entry_end > len(bundle)
        or not (instruction_end <= entry_offset or entry_end <= instruction_offset)
        or table_offset % 4 != 0
        or table_bytes != 0
        or table_offset != 0
        or header[9] != 0
        or header[10] != 0
    ):
        raise ValueError("APUMC range or P3 capability fields are invalid")
    if crc32_iso_hdlc(bundle[APUMC_HEADER_BYTES:]) != header[11]:
        raise ValueError("APUMC CRC mismatch")
    entries = []
    for index in range(APUMC_ENTRY_COUNT):
        words = struct.unpack_from("<8I", bundle, entry_offset + index * APUMC_ENTRY_BYTES)
        if (
            words[0] >> 15
            or (words[1] & 0xF800F800)
            or words[2]
            or words[3]
            or words[4] >> 16
            or words[5] >> 24
            or words[6]
            or words[7]
        ):
            raise ValueError(f"APUMC entry {index} has invalid reserved or P3 fields")
        entries.append(
            Entry(
                format_id=words[0] & 0xF,
                entry_pc=(words[0] >> 4) & 0x7FF,
                first_pc=words[1] & 0x7FF,
                last_pc=(words[1] >> 16) & 0x7FF,
                scratch_base=words[2] & 0x1FFFF,
                scratch_bytes=words[3] & 0x1FFFF,
                max_loop_count=words[4] & 0xFFFF,
                max_retired=words[5] & 0xFFFFFF,
                primitive_mask=words[6],
                table_offset=words[7] & 0xFFFF,
                table_bytes=(words[7] >> 16) & 0xFFFF,
            )
        )
    instructions = [
        Instruction.decode(struct.unpack_from("<Q", bundle, instruction_offset + pc * 8)[0])
        for pc in range(instruction_count)
    ]
    occupied = bytearray(len(bundle))
    occupied[:APUMC_HEADER_BYTES] = bytes([1]) * APUMC_HEADER_BYTES
    occupied[entry_offset:entry_end] = bytes([1]) * (entry_end - entry_offset)
    occupied[instruction_offset:instruction_end] = bytes([1]) * (
        instruction_end - instruction_offset
    )
    if any(byte for index, byte in enumerate(bundle) if not occupied[index]):
        raise ValueError("APUMC padding must be zero")
    for index, entry in enumerate(entries):
        if entry.format_id != index:
            raise ValueError("entry descriptor order must be WAV, MP3, FLAC")
        validate_entry(entry, instruction_count)
    for instruction in instructions:
        validate_p3_instruction(instruction)
    for entry in entries:
        validate_control_flow(instructions, entry)
    return instructions, entries, header
