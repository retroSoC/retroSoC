"""Frozen PIO-lite ISA1.0 objects, encoding, relocation, and slot allocation."""

from __future__ import annotations

from dataclasses import dataclass, field
from enum import IntEnum


ISA_VERSION = 0x00010000
INSTRUCTION_WORDS = 32
FIFO_DEPTH = 8
SM_COUNT = 2

OPCODE_SHIFT = 12
DELAY_SHIFT = 8
BRANCH_TARGET_MASK = 0x1F


class Opcode(IntEnum):
    CTRL = 0x0
    SET_PIN = 0x1
    SET_DIR = 0x2
    SET_COUNT = 0x3
    IN = 0x4
    OUT = 0x5
    MOVE = 0x6
    FIFO = 0x7
    WAIT = 0x8
    BRANCH = 0x9
    FLAG = 0xA


CTRL_COMMANDS = {"NOP": 0, "HALT": 1, "CLEAR_ISR": 2, "CLEAR_OSR": 3}
IN_SOURCES = {"PINS": 0, "X": 1, "Y": 2, "ZERO": 3}
OUT_DESTINATIONS = {"PINS": 0, "DIRECTIONS": 1, "X": 2, "Y": 3, "DISCARD": 4}
MOVE_REGISTERS = {"ISR": 0, "OSR": 1, "X": 2, "Y": 3}
MOVE_SOURCES = {**MOVE_REGISTERS, "ZERO": 4, "ONES": 5}
FIFO_OPERATIONS = {"PULL": 0, "PUSH": 1}
FIFO_MODES = {"NONBLOCKING": 0, "BLOCKING": 1}
BRANCH_CONDITIONS = {
    "ALWAYS": 0,
    "X_ZERO": 1,
    "Y_ZERO": 2,
    "DEC_X_NONZERO": 3,
    "DEC_Y_NONZERO": 4,
    "TEST_PIN_HIGH": 5,
    "FIFO_FAILED": 6,
    "TEST_FLAG_SET": 7,
}
WAIT_SOURCES = {"PIN": 0, "FLAG": 1}
FLAG_ACTIONS = {"CLEAR": 0, "SET": 1}


class ISAError(ValueError):
    """An instruction or program violates the frozen ISA."""


class AllocationError(ValueError):
    """A program cannot be allocated in the shared instruction store."""


@dataclass(frozen=True)
class Instruction:
    opcode: int
    delay: int = 0
    operand: int = 0

    def validate(self) -> None:
        if not isinstance(self.opcode, int) or not 0 <= self.opcode <= 0xF:
            raise ISAError("opcode must be an unsigned four-bit value")
        if not isinstance(self.delay, int) or not 0 <= self.delay <= 15:
            raise ISAError("delay must be in 0..15")
        if not isinstance(self.operand, int) or not 0 <= self.operand <= 0xFF:
            raise ISAError("operand must be an unsigned eight-bit value")
        if self.opcode > Opcode.FLAG:
            raise ISAError("reserved opcode is an illegal instruction")

        operand = self.operand
        if self.opcode == Opcode.CTRL:
            if operand & 0x1F or (operand >> 5) > 3:
                raise ISAError("CTRL contains reserved bits or a reserved command")
            if operand >> 5 == CTRL_COMMANDS["HALT"] and self.delay != 0:
                raise ISAError("HALT requires delay zero")
        elif self.opcode in (Opcode.SET_PIN, Opcode.SET_DIR, Opcode.SET_COUNT):
            return
        elif self.opcode == Opcode.IN:
            if operand >> 5 > 3:
                raise ISAError("IN source is reserved")
        elif self.opcode == Opcode.OUT:
            destination = operand >> 5
            if destination > 4:
                raise ISAError("OUT destination is reserved")
            if destination in (2, 3) and encoded_count(operand & 0x1F) > 16:
                raise ISAError("OUT to X/Y is limited to 16 bits")
        elif self.opcode == Opcode.MOVE:
            if operand & 0x7 or ((operand >> 3) & 0x7) > 5:
                raise ISAError("MOVE contains reserved bits or a reserved source")
        elif self.opcode == Opcode.FIFO:
            if operand & 0x3F:
                raise ISAError("FIFO reserved bits must be zero")
        elif self.opcode == Opcode.WAIT:
            if operand & 1:
                raise ISAError("WAIT reserved bit must be zero")
            if operand & 0x80 and ((operand >> 1) & 0x1F) > 3:
                raise ISAError("WAIT flag index is outside 0..3")
        elif self.opcode == Opcode.BRANCH:
            return
        elif self.opcode == Opcode.FLAG:
            if operand & 0x1F:
                raise ISAError("FLAG reserved bits must be zero")

    def encode(self) -> int:
        self.validate()
        return (self.opcode << OPCODE_SHIFT) | (self.delay << DELAY_SHIFT) | self.operand

    @classmethod
    def decode(cls, word: int) -> Instruction:
        if not isinstance(word, int) or not 0 <= word <= 0xFFFF:
            raise ISAError("instruction word must be an unsigned 16-bit value")
        instruction = cls((word >> OPCODE_SHIFT) & 0xF, (word >> DELAY_SHIFT) & 0xF, word & 0xFF)
        instruction.validate()
        return instruction


@dataclass(frozen=True)
class PinWindow:
    base: int
    width: int

    def validate(self, name: str, maximum_width: int = 32) -> None:
        if not isinstance(self.base, int) or not 0 <= self.base <= 31:
            raise ISAError(f"{name} base must be in 0..31")
        if not isinstance(self.width, int) or not 0 <= self.width <= maximum_width:
            raise ISAError(f"{name} width must be in 0..{maximum_width}")
        if self.base + self.width > 32:
            raise ISAError(f"{name} window exceeds GPIO31")

    def mask(self) -> int:
        if self.width == 0:
            return 0
        return ((1 << self.width) - 1) << self.base


@dataclass(frozen=True)
class ShiftSpec:
    bits: int
    direction: str
    mode: str

    def validate(self, name: str) -> None:
        if not isinstance(self.bits, int) or not 1 <= self.bits <= 32:
            raise ISAError(f"{name} bit count must be in 1..32")
        if self.direction not in ("left", "right"):
            raise ISAError(f"{name} direction must be left or right")
        if self.mode not in ("manual", "auto"):
            raise ISAError(f"{name} mode must be manual or auto")


@dataclass(frozen=True)
class TestSpec:
    pin: int | None
    flag: int

    def validate(self) -> None:
        if self.pin is not None and (not isinstance(self.pin, int) or not 0 <= self.pin <= 31):
            raise ISAError("test pin must be none or a GPIO index in 0..31")
        if not isinstance(self.flag, int) or not 0 <= self.flag <= 3:
            raise ISAError("test flag must be in 0..3")


@dataclass(frozen=True)
class PackingSpec:
    tx_items: int
    rx_items: int
    item_bits: int

    def validate(self) -> None:
        for name, value in (("TX_ITEMS", self.tx_items), ("RX_ITEMS", self.rx_items)):
            if not isinstance(value, int) or not 0 <= value <= 0xFFFFFFFF:
                raise ISAError(f"packing {name} must be an unsigned 32-bit value")
        if not isinstance(self.item_bits, int) or not 1 <= self.item_bits <= 32:
            raise ISAError("packing ITEM_BITS must be in 1..32")


@dataclass(frozen=True)
class TimingSpec:
    clock_ticks: int
    behavior: str

    def validate(self) -> None:
        if not isinstance(self.clock_ticks, int) or not 1 <= self.clock_ticks <= 0xFFFFFFFF:
            raise ISAError("clock_ticks must be an unsigned nonzero 32-bit value")
        if self.behavior not in ("fixed", "stretchable"):
            raise ISAError("clock_ticks behavior must be fixed or stretchable")


@dataclass(frozen=True)
class Program:
    name: str
    instructions: tuple[Instruction, ...]
    entry: int
    wrap_bottom: int
    wrap_top: int
    in_window: PinWindow
    out_window: PinWindow
    set_window: PinWindow
    tx: ShiftSpec
    rx: ShiftSpec
    test: TestSpec
    packing: PackingSpec
    timing: TimingSpec
    claim_mask: int
    flag_mask: int
    isa_version: int = ISA_VERSION
    source_lines: tuple[int, ...] = field(default=(), compare=False)

    @property
    def words(self) -> tuple[int, ...]:
        return tuple(instruction.encode() for instruction in self.instructions)

    @property
    def relocation_sites(self) -> tuple[int, ...]:
        return tuple(
            offset
            for offset, instruction in enumerate(self.instructions)
            if instruction.opcode == Opcode.BRANCH
        )

    def validate(self) -> None:
        if self.isa_version != ISA_VERSION:
            raise ISAError(
                f"unsupported PIO-lite ISA version 0x{self.isa_version:08X}; expected 0x{ISA_VERSION:08X}"
            )
        if not self.name or not self.name.isascii() or not self.name.replace("_", "a").isalnum():
            raise ISAError("program name must be an ASCII identifier")
        if not (self.name[0].isalpha() or self.name[0] == "_"):
            raise ISAError("program name must start with a letter or underscore")
        if not 1 <= len(self.instructions) <= INSTRUCTION_WORDS:
            raise ISAError("program must contain 1..32 instructions")
        if self.source_lines and len(self.source_lines) != len(self.instructions):
            raise ISAError("source-line metadata does not match the instruction count")
        for instruction in self.instructions:
            instruction.validate()
        for name, offset in (
            ("entry", self.entry),
            ("wrap_bottom", self.wrap_bottom),
            ("wrap_top", self.wrap_top),
        ):
            if not isinstance(offset, int) or not 0 <= offset < len(self.instructions):
                raise ISAError(f"{name} is outside the program")
        if self.wrap_bottom > self.wrap_top:
            raise ISAError("wrap_bottom must not exceed wrap_top")
        self.in_window.validate("IN")
        self.out_window.validate("OUT")
        self.set_window.validate("SET", maximum_width=8)
        self.tx.validate("TX_BITS")
        self.rx.validate("RX_BITS")
        self.test.validate()
        self.packing.validate()
        self.timing.validate()

        for offset, instruction in enumerate(self.instructions):
            operand = instruction.operand
            if instruction.opcode == Opcode.BRANCH and (operand & 0x1F) >= len(self.instructions):
                raise ISAError(f"branch at instruction {offset} is outside the program")
            if instruction.opcode == Opcode.IN and operand >> 5 == IN_SOURCES["PINS"]:
                if encoded_count(operand & 0x1F) > self.in_window.width:
                    raise ISAError(f"IN at instruction {offset} exceeds the configured input window")
            if instruction.opcode == Opcode.OUT and operand >> 5 in (
                OUT_DESTINATIONS["PINS"],
                OUT_DESTINATIONS["DIRECTIONS"],
            ):
                if encoded_count(operand & 0x1F) > self.out_window.width:
                    raise ISAError(f"OUT at instruction {offset} exceeds the configured output window")
            if (
                instruction.opcode in (Opcode.SET_PIN, Opcode.SET_DIR)
                and self.set_window.width == 0
            ):
                raise ISAError(f"SET at instruction {offset} requires an enabled SET window")
            if (
                instruction.opcode == Opcode.BRANCH
                and operand >> 5 == BRANCH_CONDITIONS["TEST_PIN_HIGH"]
                and self.test.pin is None
            ):
                raise ISAError(f"test-pin branch at instruction {offset} has no selected pin")

        expected_claim_mask, expected_flag_mask = referenced_resources(
            self.instructions, self.in_window, self.out_window, self.set_window, self.test
        )
        if self.claim_mask != expected_claim_mask:
            raise ISAError("claim-mask metadata does not match program resources")
        if self.flag_mask != expected_flag_mask:
            raise ISAError("flag metadata does not match program resources")


@dataclass(frozen=True)
class RelocatedProgram:
    program: Program
    base: int
    words: tuple[int, ...]
    entry: int
    wrap_bottom: int
    wrap_top: int


@dataclass(frozen=True)
class Allocation:
    handle: int
    image: RelocatedProgram

    @property
    def base(self) -> int:
        return self.image.base

    @property
    def words(self) -> tuple[int, ...]:
        return self.image.words


def encoded_count(field_value: int) -> int:
    if not isinstance(field_value, int) or not 0 <= field_value <= 31:
        raise ISAError("encoded count must be a five-bit value")
    return 32 if field_value == 0 else field_value


def test_pin_is_used(instructions: tuple[Instruction, ...]) -> bool:
    return any(
        instruction.opcode == Opcode.BRANCH
        and instruction.operand >> 5 == BRANCH_CONDITIONS["TEST_PIN_HIGH"]
        for instruction in instructions
    )


def referenced_resources(
    instructions: tuple[Instruction, ...],
    in_window: PinWindow,
    out_window: PinWindow,
    set_window: PinWindow,
    test: TestSpec,
) -> tuple[int, int]:
    claim_mask = in_window.mask() | out_window.mask() | set_window.mask()
    flag_mask = 0
    for instruction in instructions:
        operand = instruction.operand
        if instruction.opcode == Opcode.WAIT:
            index = (operand >> 1) & 0x1F
            if operand & 0x80:
                flag_mask |= 1 << index
            else:
                claim_mask |= 1 << index
        elif instruction.opcode == Opcode.FLAG:
            flag_mask |= 1 << ((operand >> 5) & 0x3)
        elif instruction.opcode == Opcode.BRANCH:
            condition = operand >> 5
            if condition == BRANCH_CONDITIONS["TEST_PIN_HIGH"]:
                if test.pin is None:
                    raise ISAError("test-pin branch requires a selected test pin")
                claim_mask |= 1 << test.pin
            elif condition == BRANCH_CONDITIONS["TEST_FLAG_SET"]:
                flag_mask |= 1 << test.flag
    return claim_mask, flag_mask


def relocate_program(program: Program, base: int) -> RelocatedProgram:
    program.validate()
    if not isinstance(base, int) or not 0 <= base < INSTRUCTION_WORDS:
        raise AllocationError("allocation base must be in 0..31")
    if base + len(program.instructions) > INSTRUCTION_WORDS:
        raise AllocationError("allocation base plus program length exceeds 32 slots")

    relocated_words = []
    for offset, instruction in enumerate(program.instructions):
        word = instruction.encode()
        if instruction.opcode == Opcode.BRANCH:
            local_target = instruction.operand & BRANCH_TARGET_MASK
            absolute_target = base + local_target
            if absolute_target > 31 or not base <= absolute_target < base + len(program.instructions):
                raise AllocationError(f"relocated branch at instruction {offset} is outside the image")
            word = (word & ~BRANCH_TARGET_MASK) | absolute_target
        relocated = Instruction.decode(word)
        relocated_words.append(relocated.encode())
    return RelocatedProgram(
        program=program,
        base=base,
        words=tuple(relocated_words),
        entry=base + program.entry,
        wrap_bottom=base + program.wrap_bottom,
        wrap_top=base + program.wrap_top,
    )


class InstructionAllocator:
    """Atomic first-fit allocator for the shared 32-slot instruction store."""

    def __init__(self) -> None:
        self._bitmap = 0
        self._allocations: dict[int, Allocation] = {}
        self._references: dict[int, int] = {}
        self._next_handle = 1

    @property
    def valid_bitmap(self) -> int:
        return self._bitmap

    @property
    def allocations(self) -> tuple[Allocation, ...]:
        return tuple(sorted(self._allocations.values(), key=lambda item: item.base))

    def read_word(self, index: int) -> int:
        if not isinstance(index, int) or not 0 <= index < INSTRUCTION_WORDS:
            raise AllocationError("instruction-store index must be in 0..31")
        for allocation in self._allocations.values():
            if allocation.base <= index < allocation.base + len(allocation.words):
                return allocation.words[index - allocation.base]
        return 0

    def load(self, program: Program, base: int | None = None) -> Allocation:
        program.validate()
        for allocation in self._allocations.values():
            if allocation.image.program == program:
                if base is not None and allocation.base != base:
                    raise AllocationError("identical image is already published at another base")
                self._references[allocation.handle] += 1
                return allocation

        length = len(program.instructions)
        if base is None:
            base = self._first_fit(length)
        if not isinstance(base, int) or not 0 <= base < INSTRUCTION_WORDS:
            raise AllocationError("allocation base must be in 0..31")
        if base + length > INSTRUCTION_WORDS:
            raise AllocationError("allocation base plus program length exceeds 32 slots")
        region_mask = ((1 << length) - 1) << base
        if self._bitmap & region_mask:
            raise AllocationError("requested instruction slots are already allocated")

        image = relocate_program(program, base)
        for word in image.words:
            Instruction.decode(word)
        allocation = Allocation(self._next_handle, image)
        self._allocations[allocation.handle] = allocation
        self._references[allocation.handle] = 1
        self._bitmap |= region_mask
        self._next_handle += 1
        return allocation

    def unload(self, allocation: Allocation) -> None:
        canonical = self._allocations.get(allocation.handle)
        if canonical is None or allocation is not canonical:
            raise AllocationError("unknown or foreign allocation")
        self._references[canonical.handle] -= 1
        if self._references[canonical.handle] == 0:
            length = len(canonical.words)
            self._bitmap &= ~(((1 << length) - 1) << canonical.base)
            del self._references[canonical.handle]
            del self._allocations[canonical.handle]

    def _first_fit(self, length: int) -> int:
        for base in range(INSTRUCTION_WORDS - length + 1):
            if self._bitmap & (((1 << length) - 1) << base) == 0:
                return base
        raise AllocationError("no contiguous instruction region has enough free slots")
