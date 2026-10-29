"""Independent frozen encodings and instruction-store checks for PIO-lite P1."""

from __future__ import annotations

import sys
from dataclasses import replace
from pathlib import Path

import pytest


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

from piolite_isa import (  # noqa: E402
    ISA_VERSION,
    AllocationError,
    Instruction,
    InstructionAllocator,
    ISAError,
    Opcode,
    PackingSpec,
    PinWindow,
    Program,
    ShiftSpec,
    TestSpec as PIOTestSpec,
    TimingSpec,
    encoded_count,
    relocate_program,
)


GOLDEN = (
    (0x0000, Instruction(0x0, 0, 0x00)),
    (0x0020, Instruction(0x0, 0, 0x20)),
    (0x0F40, Instruction(0x0, 15, 0x40)),
    (0x0060, Instruction(0x0, 0, 0x60)),
    (0x1FAB, Instruction(0x1, 15, 0xAB)),
    (0x2001, Instruction(0x2, 0, 0x01)),
    (0x30FF, Instruction(0x3, 0, 0xFF)),
    (0x4000, Instruction(0x4, 0, 0x00)),
    (0x417F, Instruction(0x4, 1, 0x7F)),
    (0x509F, Instruction(0x5, 0, 0x9F)),
    (0x504F, Instruction(0x5, 0, 0x4F)),
    (0x60E8, Instruction(0x6, 0, 0xE8)),
    (0x70C0, Instruction(0x7, 0, 0xC0)),
    (0x80C6, Instruction(0x8, 0, 0xC6)),
    (0x927F, Instruction(0x9, 2, 0x7F)),
    (0xA0E0, Instruction(0xA, 0, 0xE0)),
)


@pytest.mark.parametrize(("word", "instruction"), GOLDEN)
def test_independent_golden_encoding(word: int, instruction: Instruction) -> None:
    assert instruction.encode() == word
    assert Instruction.decode(word) == instruction


def _legal_form(opcode: int, delay: int, operand: int) -> bool:
    if opcode == 0:
        return operand & 0x1F == 0 and operand >> 5 <= 3 and not (
            operand == 0x20 and delay != 0
        )
    if opcode in (1, 2, 3, 9):
        return True
    if opcode == 4:
        return operand >> 5 <= 3
    if opcode == 5:
        count = 32 if operand & 0x1F == 0 else operand & 0x1F
        return operand >> 5 <= 4 and not (operand >> 5 in (2, 3) and count > 16)
    if opcode == 6:
        return operand & 7 == 0 and (operand >> 3) & 7 <= 5
    if opcode == 7:
        return operand & 0x3F == 0
    if opcode == 8:
        return operand & 1 == 0 and not (operand & 0x80 and (operand >> 1) & 0x1F > 3)
    if opcode == 10:
        return operand & 0x1F == 0
    return False


def test_every_legal_and_illegal_encoding_form() -> None:
    legal_count = 0
    illegal_count = 0
    for opcode in range(16):
        for delay in range(16):
            for operand in range(256):
                word = (opcode << 12) | (delay << 8) | operand
                if _legal_form(opcode, delay, operand):
                    legal_count += 1
                    assert Instruction.decode(word).encode() == word
                else:
                    illegal_count += 1
                    with pytest.raises(ISAError):
                        Instruction.decode(word)
    assert legal_count == 22257
    assert illegal_count == 43279


@pytest.mark.parametrize("word", (-1, 0x10000, 0x100000))
def test_word_width_is_checked(word: int) -> None:
    with pytest.raises(ISAError):
        Instruction.decode(word)


def test_count_zero_is_32_only_for_in_out() -> None:
    assert encoded_count(0) == 32
    assert encoded_count(1) == 1
    assert encoded_count(31) == 31
    assert Instruction(4, 0, 0).operand & 0x1F == 0
    assert Instruction(3, 0, 0).encode() == 0x3000
    with pytest.raises(ISAError):
        encoded_count(32)


def program(instructions: tuple[Instruction, ...] = (Instruction(0, 0, 0x20),)) -> Program:
    return Program(
        name="golden",
        instructions=instructions,
        entry=0,
        wrap_bottom=0,
        wrap_top=len(instructions) - 1,
        in_window=PinWindow(0, 0),
        out_window=PinWindow(0, 0),
        set_window=PinWindow(0, 0),
        tx=ShiftSpec(32, "right", "manual"),
        rx=ShiftSpec(32, "right", "manual"),
        test=PIOTestSpec(None, 0),
        packing=PackingSpec(0, 0, 8),
        timing=TimingSpec(1, "fixed"),
        claim_mask=0,
        flag_mask=0,
    )


def test_relocation_at_slot_zero_and_31_patches_only_branch_target() -> None:
    branch_program = replace(program((Instruction(Opcode.BRANCH, 7, 0xE0),)), flag_mask=1)
    at_zero = relocate_program(branch_program, 0)
    at_31 = relocate_program(branch_program, 31)
    assert at_zero.words == (0x97E0,)
    assert at_31.words == (0x97FF,)
    assert at_zero.words[0] ^ at_31.words[0] == 0x1F
    assert at_31.entry == at_31.wrap_bottom == at_31.wrap_top == 31


def test_isa_version_and_relocation_bounds_fail_before_publication() -> None:
    allocator = InstructionAllocator()
    with pytest.raises(ISAError, match="ISA version"):
        allocator.load(replace(program(), isa_version=ISA_VERSION + 1))
    bad_branch = program((Instruction(Opcode.BRANCH, 0, 1),))
    with pytest.raises(ISAError, match="outside the program"):
        allocator.load(bad_branch)
    with pytest.raises(AllocationError):
        relocate_program(program(), 32)
    with pytest.raises(AllocationError):
        relocate_program(program((Instruction(0), Instruction(0, 0, 0x20))), 31)
    assert allocator.valid_bitmap == 0
