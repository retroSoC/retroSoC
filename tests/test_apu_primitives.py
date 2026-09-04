"""APU-P4 primitive BAM and target-profile coverage."""

from __future__ import annotations

import binascii
import os
import random
import shutil
import struct
import subprocess
import sys
from pathlib import Path

import pytest


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

from apu_isa import (  # noqa: E402
    APUMC_P4_CAPABILITY_MASK,
    BitstreamOpcode,
    ControlOpcode,
    EntropyOpcode,
    Entry,
    Instruction,
    InstructionClass,
    KernelOpcode,
    LocalOpcode,
    build_apumc,
    parse_apumc,
    validate_p3_instruction,
    validate_p4_instruction,
)
from apu_primitives import LocalMemory, PrimitiveBam, PrimitiveFault  # noqa: E402
from apu_mcasm import assemble  # noqa: E402
from apu_interpreter import Machine, SequencerTrap  # noqa: E402


ENTRY = Entry(
    0,
    0,
    0,
    0,
    1,
    1000,
    scratch_base=0x1000,
    scratch_bytes=0x5000,
    primitive_mask=APUMC_P4_CAPABILITY_MASK,
    table_offset=0,
    table_bytes=0x1000,
)


def instruction(instruction_class: int, opcode: int, **values: int) -> Instruction:
    return Instruction(instruction_class, opcode, **values)


def write_words(memory: LocalMemory, address: int, values: list[int]) -> None:
    memory.inject(address, b"".join(struct.pack("<I", value & 0xFFFFFFFF) for value in values))


def read_words(memory: LocalMemory, address: int, count: int) -> list[int]:
    return list(struct.unpack_from(f"<{count}I", memory.data, address))


def test_p4_target_is_separate_from_p3() -> None:
    primitive = instruction(InstructionClass.BITSTREAM, BitstreamOpcode.GET, dst=0, immediate=8)
    validate_p4_instruction(primitive)
    with pytest.raises(ValueError, match="unavailable"):
        validate_p3_instruction(primitive)
    for source in (0, 4, 5):
        with pytest.raises(ValueError, match="unavailable"):
            validate_p4_instruction(
                instruction(InstructionClass.CONTROL, ControlOpcode.WAIT, aux=source)
            )
    for source in (1, 2, 3):
        validate_p4_instruction(instruction(InstructionClass.CONTROL, ControlOpcode.WAIT, aux=source))
    with pytest.raises(ValueError, match="unavailable"):
        validate_p4_instruction(instruction(InstructionClass.TRANSPORT, 0))


def test_p4_bundle_table_scratch_and_mask() -> None:
    program = [instruction(InstructionClass.CONTROL, ControlOpcode.END)]
    entries = [ENTRY.__class__(index, 0, 0, 0, 1, 1, 0x1000, 0x1000, 0, 0, 0) for index in range(3)]
    table = struct.pack("<4I", 1, 2, 3, 4)
    bundle = build_apumc(program, entries, target="p4", table_payload=table)
    _, parsed_entries, header = parse_apumc(bundle, "p4")
    assert header[5] == 200
    assert header[6] == len(table)
    assert header[9] == 0
    assert header[10] == 0x2000
    assert parsed_entries == entries
    with pytest.raises(ValueError):
        parse_apumc(bundle, "p3")


def test_p4_zero_byte_table_offset_stays_range_checked() -> None:
    program = [instruction(InstructionClass.CONTROL, ControlOpcode.END)]
    entries = [Entry(index, 0, 0, 0, 1, 1) for index in range(3)]
    bundle = bytearray(build_apumc(program, entries, target="p4"))
    struct.pack_into("<I", bundle, 20, len(bundle) + 4)
    with pytest.raises(ValueError, match="range"):
        parse_apumc(bytes(bundle), "p4")


def test_p4_assembler_emits_targeted_cfg_and_table() -> None:
    assembly = assemble(
        """
        .build_id 0x1234
        .entry 0 start start finish 4 32 0x1000 0x1000 0x21 0 4
        .entry 1 start start finish 4 32 0x1000 0x1000 0x21 0 4
        .entry 2 start start finish 4 32 0x1000 0x1000 0x21 0 4
        .table32 0x00010001
        start:
          wait 2
          fifo_pop r2
        finish:
          end
        """,
        target="p4",
    )
    instructions, entries, header = parse_apumc(assembly.bundle, "p4")
    assert assembly.target == "p4"
    assert assembly.table_payload == struct.pack("<I", 0x00010001)
    assert header[6] == 4
    assert header[9] == 0x21
    assert entries[0].primitive_mask == 0x21
    assert instructions[0].opcode == ControlOpcode.WAIT


def test_p4_interpreter_stalls_without_eof_and_watchdogs() -> None:
    program = [
        instruction(InstructionClass.BITSTREAM, BitstreamOpcode.GET, dst=0, immediate=8),
        instruction(InstructionClass.CONTROL, ControlOpcode.END),
    ]
    entry = Entry(0, 0, 0, 1, 1, 16, 0, 0, 1, 0, 0)
    machine = Machine(
        program,
        entry,
        timeout=3,
        fetch_no_retirement_cycles=0,
        target="p4",
        primitives=PrimitiveBam(),
    )
    with pytest.raises(SequencerTrap) as caught:
        machine.run()
    assert caught.value.reason == 7


def test_p4_local_sram_has_macro_and_inferred_profiles() -> None:
    source = (ROOT / "rtl/ip/multimedia/apu_local_sram.sv").read_text(encoding="utf-8")
    assert "localparam int unsigned BankCount = 28" in source
    assert "tc_sram_1024x32 u_local_sram" in source
    assert "parameterintunsignedMemoryWordCount=`APB4_APU__LOCAL_DATA_BYTES/4" in "".join(
        source.split()
    )
    assert "logic[31:0]mem[0:MemoryWordCount-1]" in "".join(source.split())
    assert "`ifdef HAVE_SRAM_MACRO" in source
    assert "`else" in source


def test_bitstream_crc_and_frame_sync() -> None:
    bam = PrimitiveBam()
    bam.input_fifo.push(0x44332211 | (4 << 32))
    bam.input_fifo.push(0x55 | (1 << 32) | (1 << 40))
    registers = [0] * 16
    result = bam.execute(instruction(2, BitstreamOpcode.REFILL, dst=0, immediate=16), registers, ENTRY)
    assert result.writes[0] == 32
    assert result.cycles == 3
    assert bam.execute(instruction(2, BitstreamOpcode.PEEK, dst=1, immediate=8), registers, ENTRY).writes[1] == 0x11
    assert bam.execute(instruction(2, BitstreamOpcode.GET, dst=1, immediate=8), registers, ENTRY).writes[1] == 0x11
    bam.execute(instruction(2, BitstreamOpcode.SKIP, immediate=4), registers, ENTRY)
    bam.execute(instruction(2, BitstreamOpcode.ALIGN), registers, ENTRY)
    registers[2], registers[3] = 0x4455, 0xFFFF
    result = bam.execute(
        instruction(2, BitstreamOpcode.FRAME_SYNC, dst=4, src0=2, src1=3, aux=16, immediate=4),
        registers,
        ENTRY,
    )
    assert result.writes[4] == 1
    registers[5], registers[6] = 0, 0x31
    assert bam.execute(instruction(2, BitstreamOpcode.CRC8, dst=7, src0=5, src1=6), registers, ENTRY).writes[7] == 0x97
    assert bam.execute(instruction(2, BitstreamOpcode.CRC16, dst=7, src0=5, src1=6), registers, ENTRY).writes[7] == 0x80A5


def test_entropy_modes_and_faults() -> None:
    memory = LocalMemory()
    table = struct.pack("<3I", 1 | (1 << 16), 0x23 | (2 << 16), 0xA | (2 << 16))
    memory.publish_table(table + bytes(0x1000 - len(table)))
    bam = PrimitiveBam(memory)
    registers = [0] * 16
    registers[0], registers[1] = 0, 3
    bam.input_fifo.push(0b01011000 | (1 << 32) | (1 << 40))
    assert bam.execute(instruction(3, EntropyOpcode.HUFF_SYMBOL, dst=2, src0=0, src1=1, aux=2), registers, ENTRY).writes[2] == 1
    assert bam.execute(instruction(3, EntropyOpcode.HUFF_PAIR, dst=2, src0=0, src1=1, aux=2), registers, ENTRY).writes == {2: 2, 3: 3}

    bam = PrimitiveBam(memory)
    bam.input_fifo.push(0b00101011 | (1 << 32) | (1 << 40))
    assert bam.execute(instruction(3, EntropyOpcode.UNARY, dst=0, aux=0, immediate=8), registers, ENTRY).writes[0] == 2
    registers[0] = 1
    result = bam.execute(instruction(3, EntropyOpcode.RICE4, dst=2, src0=0, src1=1), registers, ENTRY)
    assert result.writes[2] == 1
    registers[0], registers[1] = 4, 1
    assert bam.execute(instruction(3, EntropyOpcode.SIGN_RESTORE, dst=2, src0=0, src1=1), registers, ENTRY).writes[2] == 0xFFFFFFFB
    bam = PrimitiveBam(memory)
    bam.input_fifo.push(1 << 32 | 1 << 40)
    with pytest.raises(PrimitiveFault) as caught:
        bam.execute(instruction(3, EntropyOpcode.UNARY, dst=0, aux=0, immediate=1), registers, ENTRY)
    assert (caught.value.code, caught.value.stage) == (7, 5)


def test_local_memory_and_fifo_epoch() -> None:
    memory = LocalMemory()
    memory.publish_table(struct.pack("<I", 0x12345678) + bytes(0xFFC))
    memory.new_epoch()
    bam = PrimitiveBam(memory)
    registers = [0] * 16
    registers[0], registers[1] = 0, 0xA5A55A5A
    bam.execute(instruction(4, LocalOpcode.ST32, src0=0, src1=1), registers, ENTRY)
    assert bam.execute(instruction(4, LocalOpcode.LD32, dst=2, src0=0), registers, ENTRY).writes[2] == registers[1]
    assert bam.execute(instruction(4, LocalOpcode.TABLE16, dst=3, src0=0, src1=0), registers, ENTRY).writes[3] == 0x5678
    bam.input_fifo.push(0xDEADBEEF | (4 << 32) | (1 << 40))
    assert bam.execute(instruction(4, LocalOpcode.FIFO_POP, dst=4), registers, ENTRY).writes == {4: 0xDEADBEEF, 5: 0x104}
    registers[4], registers[5] = 0x01020304, 0x104
    bam.execute(instruction(4, LocalOpcode.FIFO_PUSH, src0=4, src1=5), registers, ENTRY)
    assert bam.output_fifo.pop() == 0x01020304 | (4 << 32) | (1 << 40)
    bam.reset_mutable()
    with pytest.raises(PrimitiveFault) as caught:
        bam.execute(instruction(4, LocalOpcode.LD32, dst=2, src0=0), registers, ENTRY)
    assert caught.value.reason == 5


def test_requant_stereo_fixed_lpc_and_pcm_pack() -> None:
    memory = LocalMemory()
    memory.publish_table(bytes(0x1000))
    memory.new_epoch()
    bam = PrimitiveBam(memory)
    registers = [0] * 16
    write_words(memory, 0x1000, [1000, -1000])
    write_words(memory, 0x1040, [1 << 30, 1 << 30])
    write_words(memory, 0x1080, [0x40])
    registers[0], registers[1], registers[2] = 0, 0x80, 0x100
    result = bam.execute(instruction(5, KernelOpcode.REQUANT, dst=2, src0=0, src1=1, aux=2 << 6, immediate=2), registers, ENTRY)
    assert read_words(memory, 0x1100, 2) == [1000, 0xFFFFFC18]
    assert result.cycles == 16

    write_words(memory, 0x1200, [3, 4])
    write_words(memory, 0x1240, [1, 2])
    write_words(memory, 0x1280, [0x240])
    registers[0], registers[1], registers[2] = 0x200, 0x280, 0x300
    result = bam.execute(instruction(5, KernelOpcode.STEREO, dst=2, src0=0, src1=1, aux=1, immediate=2), registers, ENTRY)
    assert read_words(memory, 0x1300, 4) == [3, 4, 2, 2]
    assert result.writes[2] == 4

    write_words(memory, 0x1400, [1, 1])
    write_words(memory, 0x1440, [2, 1])
    write_words(memory, 0x1480, [0x440])
    registers[0], registers[1], registers[2] = 0x400, 0x480, 0x500
    bam.execute(instruction(5, KernelOpcode.FIXED, dst=2, src0=0, src1=1, aux=2, immediate=2), registers, ENTRY)
    assert read_words(memory, 0x1500, 2) == [4, 7]

    write_words(memory, 0x1600, [1, 1])
    write_words(memory, 0x1640, [1, 1])
    write_words(memory, 0x1680, [1, 0])
    write_words(memory, 0x16C0, [0x640, 0x680, 0])
    registers[0], registers[1], registers[2] = 0x600, 0x6C0, 0x700
    bam.execute(instruction(5, KernelOpcode.LPC, dst=2, src0=0, src1=1, aux=2, immediate=2), registers, ENTRY)
    assert read_words(memory, 0x1700, 2) == [2, 4]

    write_words(memory, 0x1800, [100, -100])
    write_words(memory, 0x1840, [1 << 30, 2])
    registers[0], registers[1], registers[2] = 0x800, 0x840, 0x900
    result = bam.execute(instruction(5, KernelOpcode.PCM_PACK, dst=2, src0=0, src1=1, aux=0, immediate=1), registers, ENTRY)
    assert memory.data[0x1900:0x1904] == struct.pack("<hh", 100, -100)
    assert result.writes[2] == 4


@pytest.mark.parametrize("opcode", list(KernelOpcode))
@pytest.mark.parametrize("misaligned_register", (0, 1, 2))
def test_kernel_offsets_reject_misalignment_before_access(
    opcode: KernelOpcode, misaligned_register: int
) -> None:
    memory = LocalMemory()
    memory.publish_table(b"")
    memory.new_epoch()
    bam = PrimitiveBam(memory)
    registers = [0] * 16
    registers[misaligned_register] = 1
    with pytest.raises(PrimitiveFault) as caught:
        bam.execute(
            instruction(5, opcode, dst=2, src0=0, src1=1, immediate=1),
            registers,
            ENTRY,
        )
    assert (caught.value.code, caught.value.stage, caught.value.reason) == (11, 11, 5)


def test_kernel_reference_rejects_misalignment_before_output() -> None:
    memory = LocalMemory()
    memory.publish_table(b"")
    memory.new_epoch()
    bam = PrimitiveBam(memory)
    registers = [0] * 16
    write_words(memory, 0x1000, [100])
    write_words(memory, 0x1100, [1])
    registers[0], registers[1], registers[2] = 0, 0x100, 0x200
    with pytest.raises(PrimitiveFault) as caught:
        bam.execute(
            instruction(5, KernelOpcode.REQUANT, dst=2, src0=0, src1=1, immediate=1),
            registers,
            ENTRY,
        )
    assert (caught.value.code, caught.value.stage, caught.value.reason) == (11, 11, 5)


def test_interpreter_models_pending_kernel_scoreboard_and_abort() -> None:
    program = [
        instruction(5, KernelOpcode.REQUANT, dst=2, src0=0, src1=1, aux=2 << 6, immediate=1),
        instruction(1, 1, dst=3, immediate=0x55),
        instruction(1, 0, dst=4, src0=2),
        instruction(0, ControlOpcode.WAIT, aux=1),
        instruction(0, ControlOpcode.END),
    ]
    entry = Entry(0, 0, 0, 4, 1, 32, 0x1000, 0x1000, 0x41, 0, 0)
    primitives = PrimitiveBam()
    machine = Machine(
        program,
        entry,
        timeout=64,
        fetch_no_retirement_cycles=0,
        target="p4",
        primitives=primitives,
    )
    write_words(primitives.memory, 0x1000, [1000])
    write_words(primitives.memory, 0x1040, [1 << 30])
    write_words(primitives.memory, 0x1080, [0x40])
    machine.registers[0], machine.registers[1], machine.registers[2] = 0, 0x80, 0x100

    assert not machine.step()
    assert machine.retired == 1
    assert machine.kernel_pending_dst == 2
    assert machine.registers[2] == 0x100
    assert not machine.step()
    assert machine.registers[3] == 0x55
    retired_before = machine.retired
    assert not machine.step()
    assert machine.retired == retired_before
    while machine.kernel_pending_dst is not None:
        assert not machine.step()
    assert machine.registers[2] == 1
    assert machine.step() is False
    assert machine.registers[4] == 1

    machine.begin_entry(entry)
    write_words(primitives.memory, 0x1000, [1000])
    write_words(primitives.memory, 0x1040, [1 << 30])
    write_words(primitives.memory, 0x1080, [0x40])
    machine.registers[0], machine.registers[1], machine.registers[2] = 0, 0x80, 0x100
    assert not machine.step()
    machine.abort()
    assert machine.kernel_pending_dst is None
    assert not primitives.kernel_done
    assert not primitives.memory.valid_words[0x1000 // 4]


def test_interpreter_pending_kernel_watchdog_and_error_boundary() -> None:
    requant_program = [
        instruction(5, KernelOpcode.REQUANT, dst=2, src0=0, src1=1, aux=2 << 6, immediate=1),
        instruction(1, 0, dst=4, src0=2),
        instruction(0, ControlOpcode.END),
    ]
    entry = Entry(0, 0, 0, 2, 1, 16, 0x1000, 0x1000, 0x40, 0, 0)
    primitives = PrimitiveBam()
    machine = Machine(
        requant_program,
        entry,
        timeout=1,
        fetch_no_retirement_cycles=0,
        target="p4",
        primitives=primitives,
    )
    write_words(primitives.memory, 0x1000, [1000])
    write_words(primitives.memory, 0x1040, [1 << 30])
    write_words(primitives.memory, 0x1080, [0x40])
    machine.registers[0], machine.registers[1], machine.registers[2] = 0, 0x80, 0x100
    assert not machine.step()
    with pytest.raises(SequencerTrap) as caught:
        machine.step()
    assert caught.value.reason == 7

    error_program = [
        instruction(5, KernelOpcode.DECORRELATE, dst=2, src0=0, src1=1, aux=1, immediate=1),
        instruction(1, 1, dst=3, immediate=0x55),
        instruction(0, ControlOpcode.END),
    ]
    primitives = PrimitiveBam()
    machine = Machine(
        error_program,
        entry,
        timeout=16,
        fetch_no_retirement_cycles=0,
        target="p4",
        primitives=primitives,
    )
    write_words(primitives.memory, 0x1000, [0x7FFFFFFF])
    write_words(primitives.memory, 0x1040, [0xFFFFFFFF])
    write_words(primitives.memory, 0x1080, [0x40])
    machine.registers[0], machine.registers[1], machine.registers[2] = 0, 0x80, 0x100
    assert not machine.step()
    assert machine.retired == 1
    with pytest.raises(SequencerTrap) as caught:
        machine.step()
    assert caught.value.reason == 9


def test_transform_and_resampler_profiles() -> None:
    memory = LocalMemory()
    table = bytearray(0x1000)
    for index in range(72):
        struct.pack_into("<I", table, index * 4, (1 << 30) if index % 6 == index // 6 else 0)
    memory.publish_table(table)
    memory.new_epoch()
    bam = PrimitiveBam(memory)
    registers = [0] * 16
    write_words(memory, 0x1000, [1, 2, 3, 4, 5, 6])
    write_words(memory, 0x1080, [0x80000000])
    registers[0], registers[1], registers[2] = 0, 0x80, 0x200
    result = bam.execute(instruction(5, KernelOpcode.IMDCT6, dst=2, src0=0, src1=1, immediate=1), registers, ENTRY)
    assert read_words(memory, 0x1200, 6) == [1, 2, 3, 4, 5, 6]
    assert result.cycles == 102

    write_words(memory, 0x1400, [7, 8])
    write_words(memory, 0x1480, [0, 0, 0, 0, 0, 0, 0, 2])
    registers[0], registers[1], registers[2] = 0x400, 0x480, 0x500
    result = bam.execute(instruction(5, KernelOpcode.RESAMPLE, dst=2, src0=0, src1=1, aux=0, immediate=1), registers, ENTRY)
    assert read_words(memory, 0x1500, 2) == [7, 8]
    assert result.cycles == 12


def test_imdct18_dct32_decorrelate_and_pcm_duplicate() -> None:
    memory = LocalMemory()
    table = bytearray(0x1800)
    for row in range(32):
        struct.pack_into("<I", table, (row * 32 + row) * 4, 1 << 30)
        struct.pack_into("<I", table, 0x1000 + row * 4, 1 << 30)
    memory.publish_table(table)
    memory.new_epoch()
    entry = Entry(0, 0, 0, 0, 1, 20000, 0x2000, 0x4000, 0xFFFF, 0, 0x1800)
    bam = PrimitiveBam(memory)
    registers = [0] * 16

    write_words(memory, 0x2000, list(range(1, 19)))
    write_words(memory, 0x2800, [0x80000000])
    registers[0], registers[1], registers[2] = 0, 0x800, 0x1000
    result = bam.execute(
        instruction(5, KernelOpcode.IMDCT18, dst=2, src0=0, src1=1, immediate=1),
        registers,
        entry,
    )
    assert result.writes[2] == 36
    assert result.cycles == 714

    write_words(memory, 0x2000, list(range(1, 33)))
    write_words(memory, 0x2800, [0x80000000, 0x80001000, 0x1000, 0])
    write_words(memory, 0x3000, [0] * (16 * 32))
    registers[0], registers[1], registers[2] = 0, 0x800, 0x2000
    result = bam.execute(
        instruction(5, KernelOpcode.DCT32_POLY, dst=2, src0=0, src1=1, immediate=1),
        registers,
        entry,
    )
    assert result.writes[2] == 32
    assert read_words(memory, 0x4000, 32) == list(range(1, 33))
    assert result.cycles == 2312

    write_words(memory, 0x2200, [10])
    write_words(memory, 0x2240, [3])
    write_words(memory, 0x2280, [0x240])
    registers[0], registers[1], registers[2] = 0x200, 0x280, 0x300
    result = bam.execute(
        instruction(5, KernelOpcode.DECORRELATE, dst=2, src0=0, src1=1, aux=1, immediate=1),
        registers,
        entry,
    )
    assert read_words(memory, 0x2300, 2) == [10, 7]
    assert result.writes[2] == 2

    write_words(memory, 0x2400, [100])
    write_words(memory, 0x2440, [1 << 30, 1])
    registers[0], registers[1], registers[2] = 0x400, 0x440, 0x500
    result = bam.execute(
        instruction(5, KernelOpcode.PCM_PACK, dst=2, src0=0, src1=1, aux=4, immediate=1),
        registers,
        entry,
    )
    assert memory.data[0x2500:0x2504] == struct.pack("<hh", 100, 100)
    assert result.writes[2] == 4


@pytest.mark.parametrize(
    ("profile", "numerator", "denominator"),
    [
        (0, 1, 1),
        (1, 1, 2),
        (2, 80, 147),
        (3, 160, 147),
        (4, 3, 2),
        (5, 2, 1),
        (6, 3, 1),
        (7, 4, 1),
        (8, 6, 1),
        (9, 8, 1),
        (10, 12, 1),
        (11, 320, 147),
        (12, 640, 147),
        (13, 1280, 147),
        (14, 2, 3),
        (15, 4, 3),
    ],
)
def test_all_resampler_profiles(profile: int, numerator: int, denominator: int) -> None:
    memory = LocalMemory()
    memory.publish_table(bytes(0x1800))
    memory.new_epoch()
    entry = Entry(0, 0, 0, 0, 1, 20000, 0x2000, 0x4000, 0xFFFF, 0, 0x1800)
    bam = PrimitiveBam(memory)
    registers = [0] * 16
    write_words(memory, 0x20E4, [0] * 17)
    write_words(
        memory,
        0x2400,
        [0x80000000, 0x80000800, 0x80001000, 0, 0, 0, 0, 1],
    )
    registers[0], registers[1], registers[2] = 0x100, 0x400, 0x800
    result = bam.execute(
        instruction(5, KernelOpcode.RESAMPLE, dst=2, src0=0, src1=1, aux=profile, immediate=1),
        registers,
        entry,
    )
    expected_frames = (numerator + denominator - 1) // denominator
    assert result.writes[2] == expected_frames
    expected_cycles = 10 if profile == 0 else 10 + 36 * expected_frames
    assert result.cycles == expected_cycles
    assert read_words(memory, 0x2800, expected_frames) == [0] * expected_frames


def _p4_rtl_sources() -> list[Path]:
    multimedia = ROOT / "rtl/ip/multimedia"
    return [
        ROOT / "rtl/managed/clusterip/common/rtl/utils/fifo.sv",
        multimedia / "apu_local_sram.sv",
        multimedia / "apu_bitstream_engine.sv",
        multimedia / "apu_entropy_engine.sv",
        multimedia / "apu_reconstruction_engine.sv",
        multimedia / "apu_transform_engine.sv",
        multimedia / "apu_resampler.sv",
        multimedia / "apu_kernel_engine.sv",
        multimedia / "apu_primitive_dispatcher.sv",
        ROOT / "tests/rtl/apu_p4_primitives_tb.sv",
    ]


def _requant_corpus(tmp_path: Path) -> tuple[Path, int]:
    random_source = random.Random(0xA4C0DE)
    cases = [
        (-0x80000000, -0x80000000, 0x80),
        (-0x80000000, 0x7FFFFFFF, 0xA0),
        (0x7FFFFFFF, -0x80000000, 0x41),
        (0x7FFFFFFF, 0x7FFFFFFF, 0x61),
        (1, 1 << 29, 0xA0),
        (3, 1 << 29, 0xA0),
        (-1, 1 << 29, 0xA0),
        (-3, 1 << 29, 0xA0),
    ]
    for _ in range(24):
        sample = random_source.randint(-0x80000000, 0x7FFFFFFF)
        scale = random_source.randint(-0x80000000, 0x7FFFFFFF)
        shift = random_source.randrange(32)
        rounding = random_source.randrange(2)
        width = random_source.randrange(3)
        cases.append((sample, scale, shift | (rounding << 5) | (width << 6)))

    words: list[int] = []
    entry = Entry(0, 0, 0, 0, 1, 1000, 0x2000, 0x4000, 0x40, 0, 0)
    for sample, scale, aux in cases:
        memory = LocalMemory()
        memory.publish_table(b"")
        memory.new_epoch()
        bam = PrimitiveBam(memory)
        registers = [0] * 16
        write_words(memory, 0x2E00, [sample])
        write_words(memory, 0x2E40, [scale])
        write_words(memory, 0x2E80, [0xE40])
        registers[0], registers[1], registers[2] = 0xE00, 0xE80, 0xEC0
        bam.execute(
            instruction(
                5,
                KernelOpcode.REQUANT,
                dst=2,
                src0=0,
                src1=1,
                aux=aux,
                immediate=1,
            ),
            registers,
            entry,
        )
        expected = read_words(memory, 0x2EC0, 1)[0]
        words.extend((sample & 0xFFFFFFFF, scale & 0xFFFFFFFF, aux, expected))

    vector_path = tmp_path / "apu_p4_requant_vectors.hex"
    vector_path.write_text("\n".join(f"{word:08x}" for word in words) + "\n", encoding="utf-8")
    return vector_path, len(cases)


def _fifo_word(payload: bytes, *, last: bool = True) -> int:
    if not 1 <= len(payload) <= 4:
        raise ValueError("P4 corpus FIFO payload must contain one to four bytes")
    return int.from_bytes(payload.ljust(4, b"\0"), "little") | (len(payload) << 32) | (
        int(last) << 40
    )


class _SharedCorpus:
    def __init__(self) -> None:
        self.lines: list[str] = []
        self.covered: set[tuple[int, int]] = set()
        self.case_index = 0

    @staticmethod
    def _word(value: int) -> str:
        return f"32'h{value & 0xFFFFFFFF:08x}"

    def add(
        self,
        name: str,
        operations: list[Instruction],
        *,
        registers: dict[int, int] | None = None,
        table_words: dict[int, int] | None = None,
        scratch_words: dict[int, int] | None = None,
        input_words: list[int] | None = None,
        check_words: list[int] | None = None,
        check_output_fifo: bool = False,
    ) -> None:
        registers = {} if registers is None else registers
        table_words = {} if table_words is None else table_words
        scratch_words = {} if scratch_words is None else scratch_words
        input_words = [] if input_words is None else input_words
        check_words = [] if check_words is None else check_words

        table = bytearray(0x1800)
        for address, value in table_words.items():
            struct.pack_into("<I", table, address, value & 0xFFFFFFFF)
        memory = LocalMemory()
        memory.publish_table(bytes(table))
        memory.new_epoch()
        bam = PrimitiveBam(memory)
        for address, value in scratch_words.items():
            write_words(memory, address, [value])
        for value in input_words:
            bam.input_fifo.push(value)
        gpr = [0] * 16
        for register, value in registers.items():
            gpr[register] = value & 0xFFFFFFFF

        label = "".join(character if character.isalnum() else "_" for character in name)
        self.lines.extend((f"begin : shared_corpus_{self.case_index}_{label}", "  hard_reset();"))
        self.case_index += 1
        for address, value in sorted(table_words.items()):
            self.lines.append(
                f"  publish_table_word(17'h{address:05x}, {self._word(value)});"
            )
        for address, value in sorted(scratch_words.items()):
            self.lines.append(f"  inject_word(17'h{address:05x}, {self._word(value)});")
        for value in input_words:
            self.lines.append(f"  push_input(41'h{value & ((1 << 41) - 1):011x});")

        fault_seen = False
        for operation_index, operation in enumerate(operations):
            self.covered.add((int(operation.instruction_class), int(operation.opcode)))
            source0 = gpr[operation.src0]
            source1 = gpr[operation.src1]
            destination = gpr[operation.dst]
            try:
                result = bam.execute(operation, gpr, RTL_CORPUS_ENTRY)
            except PrimitiveFault as fault:
                latency_bound = self._fault_latency_bound(operation, gpr)
                self.lines.append(
                    "  issue_expect_corpus_error("
                    f"64'h{operation.encode():016x}, {self._word(source0)}, {self._word(source1)}, "
                    f"{self._word(destination)}, 6'd{fault.code}, 4'd{fault.stage}, 8'd{fault.reason}, "
                    f"1'b{int(latency_bound is not None)}, 32'd{latency_bound or 0}, "
                    f"1'b{int(operation.instruction_class == InstructionClass.LOCAL)});"
                )
                fault_seen = True
                if operation_index + 1 != len(operations):
                    raise AssertionError(f"faulting corpus operation must terminate case {name}")
                self._append_stream_state_checks(name, bam)
                break

            self.lines.append(
                f"  issue(64'h{operation.encode():016x}, {self._word(source0)}, "
                f"{self._word(source1)}, {self._word(destination)}, observed, cycles);"
            )
            ordered_writes = sorted(result.writes.items())
            self.lines.append(
                f"  if (result_words != 3'd{len(ordered_writes)} || cycles != 32'd{result.cycles}) "
                f"$fatal(1, \"shared corpus {name} result shape/latency mismatch\");"
            )
            for word_index, (register, value) in enumerate(ordered_writes):
                self.lines.append(
                    f"  if (result_dst + 4'd{word_index} != 4'd{register} || "
                    f"result_data[{word_index}] != {self._word(value)}) "
                    f"$fatal(1, \"shared corpus {name} destination mismatch\");"
                )
                gpr[register] = value & 0xFFFFFFFF
            self.lines.append(
                f"  if (result_kernel != 1'b{int(result.kernel_done)}) "
                f"$fatal(1, \"shared corpus {name} kernel tag mismatch\");"
            )
            self._append_stream_state_checks(name, bam)

        for address in check_words:
            expected = int.from_bytes(memory.data[address : address + 4], "little")
            self.lines.extend(
                (
                    f"  read_word(17'h{address:05x}, observed);",
                    f"  if (observed != {self._word(expected)}) "
                    f"$fatal(1, \"shared corpus {name} memory mismatch at {address:#x} "
                    f"got=%08x expected=%08x\", observed, {self._word(expected)});",
                )
            )
        if check_output_fifo:
            if fault_seen or len(bam.output_fifo.words) != 1:
                raise AssertionError(f"shared corpus {name} did not produce one output FIFO word")
            expected_fifo = bam.output_fifo.words[0]
            self.lines.extend(
                (
                    f"  if (!output_valid || output_data != 41'h{expected_fifo:011x}) "
                    f"$fatal(1, \"shared corpus {name} output FIFO mismatch\");",
                    "  output_accept = 1'b1;",
                    "  @(posedge clk_i);",
                    "  output_accept = 1'b0;",
                )
            )
        self.lines.append("end")

    @staticmethod
    def _fault_latency_bound(operation: Instruction, registers: list[int]) -> int | None:
        instruction_class = int(operation.instruction_class)
        opcode = int(operation.opcode)
        if instruction_class == InstructionClass.BITSTREAM:
            if opcode in (BitstreamOpcode.PEEK, BitstreamOpcode.GET, BitstreamOpcode.SKIP):
                return 1
            if opcode == BitstreamOpcode.FRAME_SYNC:
                return 2 + 2 * operation.immediate
        if instruction_class == InstructionClass.ENTROPY:
            if opcode == EntropyOpcode.UNARY:
                return 2 + operation.immediate
            if opcode == EntropyOpcode.SIGN_RESTORE:
                return 3 + (registers[operation.src1] & 0x1F)
        if instruction_class == InstructionClass.LOCAL:
            return 2 if opcode in (
                LocalOpcode.LD32,
                LocalOpcode.TABLE8,
                LocalOpcode.TABLE16,
                LocalOpcode.TABLE32,
            ) else 1
        return None

    def _append_stream_state_checks(self, name: str, bam: PrimitiveBam) -> None:
        self.lines.extend(
            (
                "  @(negedge clk_i);",
                f"  if (input_count != 7'd{len(bam.input_fifo.words)} || "
                f"output_count != 7'd{len(bam.output_fifo.words)}) "
                f"$fatal(1, \"shared corpus {name} FIFO mutation mismatch\");",
                f"  if (u_dut.s_available_bits != 7'd{len(bam.bits)} || "
                f"u_dut.u_bitstream_engine.s_eof_q != 1'b{int(bam.eof)} || "
                f"u_dut.u_bitstream_engine.s_bit_position_q != 3'd{bam.bit_position}) "
                f"$fatal(1, \"shared corpus {name} reservoir mutation mismatch "
                f"got=%0d/%0d/%0d expected={len(bam.bits)}/{int(bam.eof)}/"
                f"{bam.bit_position}\", u_dut.s_available_bits, "
                "u_dut.u_bitstream_engine.s_eof_q, "
                "u_dut.u_bitstream_engine.s_bit_position_q);",
            )
        )

    def write(self, path: Path) -> None:
        path.write_text("\n".join(self.lines) + "\n", encoding="utf-8")


RTL_CORPUS_ENTRY = Entry(0, 0, 0, 0, 1, 0xFFFFFF, 0x2000, 0x4000, 0xFFFF, 0, 0x1800)


def _word_map(base: int, values: list[int]) -> dict[int, int]:
    return {base + index * 4: value for index, value in enumerate(values)}


def _shared_primitive_corpus(tmp_path: Path) -> tuple[Path, int]:
    random_source = random.Random(0x5044434F)
    corpus = _SharedCorpus()

    random_word = random_source.getrandbits(32)
    input_word = _fifo_word(random_word.to_bytes(4, "little"))
    corpus.add("refill_boundary", [instruction(2, BitstreamOpcode.REFILL, dst=0, immediate=32)], input_words=[input_word])
    corpus.add("peek_random", [instruction(2, BitstreamOpcode.PEEK, dst=1, immediate=32)], input_words=[input_word])
    corpus.add("get_random", [instruction(2, BitstreamOpcode.GET, dst=1, immediate=32)], input_words=[input_word])
    corpus.add("skip_boundary", [instruction(2, BitstreamOpcode.SKIP, immediate=32)], input_words=[input_word])
    corpus.add(
        "align_after_partial_get",
        [
            instruction(2, BitstreamOpcode.GET, dst=0, immediate=3),
            instruction(2, BitstreamOpcode.ALIGN),
        ],
        input_words=[input_word],
    )
    sync_prefix = random_source.randrange(0x100)
    corpus.add(
        "frame_sync_masked",
        [instruction(2, BitstreamOpcode.FRAME_SYNC, dst=4, src0=2, src1=3, aux=16, immediate=3)],
        registers={2: 0xABCD, 3: 0xFFFF},
        input_words=[_fifo_word(bytes((sync_prefix, 0xAB, 0xCD)))],
    )
    corpus.add(
        "crc8_random",
        [instruction(2, BitstreamOpcode.CRC8, dst=7, src0=5, src1=6)],
        registers={5: random_source.randrange(0x100), 6: 0xFF},
    )
    corpus.add(
        "crc16_random",
        [instruction(2, BitstreamOpcode.CRC16, dst=7, src0=5, src1=6)],
        registers={5: random_source.randrange(0x10000), 6: 0xFF},
    )
    for opcode in (BitstreamOpcode.PEEK, BitstreamOpcode.GET, BitstreamOpcode.SKIP):
        corpus.add(
            f"{opcode.name.lower()}_truncated",
            [instruction(2, opcode, dst=1 if opcode != BitstreamOpcode.SKIP else 0, immediate=16)],
            input_words=[_fifo_word(bytes((random_source.randrange(0x100),)))],
        )
    corpus.add(
        "frame_sync_not_found",
        [instruction(2, BitstreamOpcode.FRAME_SYNC, dst=4, src0=2, src1=3, aux=8, immediate=1)],
        registers={2: 0xFF, 3: 0xFF},
        input_words=[_fifo_word(b"\x00")],
    )

    for opcode in (
        EntropyOpcode.HUFF_SYMBOL,
        EntropyOpcode.HUFF_PAIR,
        EntropyOpcode.HUFF_QUAD,
    ):
        symbol = random_source.getrandbits(16)
        corpus.add(
            f"{opcode.name.lower()}_canonical",
            [instruction(3, opcode, dst=4, src0=0, src1=1, aux=1)],
            registers={0: 0, 1: 1},
            table_words={0: symbol | (1 << 16)},
            input_words=[_fifo_word(bytes((random_source.randrange(0x80),)))],
        )
        corpus.add(
            f"{opcode.name.lower()}_empty_table",
            [instruction(3, opcode, dst=4, src0=0, src1=1, aux=1)],
            registers={0: 0, 1: 0},
        )
    corpus.add(
        "unary_boundary",
        [instruction(3, EntropyOpcode.UNARY, dst=2, aux=0, immediate=5)],
        input_words=[_fifo_word(bytes((0x04 | random_source.randrange(4),)))],
    )
    corpus.add(
        "rice4_random",
        [instruction(3, EntropyOpcode.RICE4, dst=2, src0=0, src1=1)],
        registers={0: 2},
        input_words=[_fifo_word(bytes((0x28 | random_source.randrange(8),)))],
    )
    corpus.add(
        "rice5_random",
        [instruction(3, EntropyOpcode.RICE5, dst=2, src0=0, src1=1)],
        registers={0: 3},
        input_words=[_fifo_word(bytes((0x68 | random_source.randrange(8),)))],
    )
    corpus.add(
        "sign_restore_random",
        [instruction(3, EntropyOpcode.SIGN_RESTORE, dst=2, src0=0, src1=1)],
        registers={0: 0x7FFFFFF8, 1: 3},
        input_words=[_fifo_word(bytes((0xB0 | random_source.randrange(16),)))],
    )
    for opcode, escape in ((EntropyOpcode.RICE4, 15), (EntropyOpcode.RICE5, 31)):
        corpus.add(
            f"{opcode.name.lower()}_escape_extreme",
            [instruction(3, opcode, dst=2, src0=0, src1=1)],
            registers={0: escape, 1: 32},
            input_words=[_fifo_word(b"\x80\x00\x00\x00")],
        )
    corpus.add(
        "unary_declared_limit",
        [instruction(3, EntropyOpcode.UNARY, dst=2, aux=0, immediate=1)],
        input_words=[_fifo_word(b"\x00")],
    )
    for opcode, escape in ((EntropyOpcode.RICE4, 15), (EntropyOpcode.RICE5, 31)):
        corpus.add(
            f"{opcode.name.lower()}_invalid_escape_width",
            [instruction(3, opcode, dst=2, src0=0, src1=1)],
            registers={0: escape, 1: 0},
        )
    corpus.add(
        "sign_restore_truncated",
        [instruction(3, EntropyOpcode.SIGN_RESTORE, dst=2, src0=0, src1=1)],
        registers={0: 7, 1: 8},
        input_words=[_fifo_word(b"\xa5")],
    )

    local_value = random_source.getrandbits(32)
    corpus.add(
        "local_load_boundary",
        [instruction(4, LocalOpcode.LD32, dst=2, src0=0)],
        registers={0: 0x3FFC},
        scratch_words={0x5FFC: local_value},
    )
    corpus.add(
        "local_store_boundary",
        [instruction(4, LocalOpcode.ST32, src0=0, src1=1)],
        registers={0: 0x3FFC, 1: local_value},
        check_words=[0x5FFC],
    )
    table_value = random_source.getrandbits(32)
    for opcode, index, expected_address in (
        (LocalOpcode.TABLE8, 3, 0x103),
        (LocalOpcode.TABLE16, 1, 0x102),
        (LocalOpcode.TABLE32, 0, 0x100),
    ):
        corpus.add(
            f"{opcode.name.lower()}_random",
            [instruction(4, opcode, dst=2, src0=0, src1=1)],
            registers={0: 0x100, 1: index},
            table_words={0x100: table_value},
        )
        corpus.add(
            f"{opcode.name.lower()}_range_fault",
            [instruction(4, opcode, dst=2, src0=0, src1=1)],
            registers={0: 0x1800, 1: index},
        )
        assert expected_address < 0x1800
    corpus.add(
        "fifo_pop_boundary",
        [instruction(4, LocalOpcode.FIFO_POP, dst=4)],
        input_words=[_fifo_word(random_source.getrandbits(32).to_bytes(4, "little"))],
    )
    corpus.add(
        "fifo_push_random",
        [instruction(4, LocalOpcode.FIFO_PUSH, src0=4, src1=5)],
        registers={4: random_source.getrandbits(32), 5: 0x104},
        check_output_fifo=True,
    )
    corpus.add(
        "local_load_range_fault",
        [instruction(4, LocalOpcode.LD32, dst=2, src0=0)],
        registers={0: 0x4000},
    )
    corpus.add(
        "local_store_range_fault",
        [instruction(4, LocalOpcode.ST32, src0=0, src1=1)],
        registers={0: 0x4000, 1: local_value},
    )
    corpus.add(
        "local_load_address_overflow",
        [instruction(4, LocalOpcode.LD32, dst=2, src0=0, immediate=1)],
        registers={0: 0xFFFFFFFF},
    )
    corpus.add(
        "local_store_address_overflow",
        [instruction(4, LocalOpcode.ST32, src0=0, src1=1, immediate=1)],
        registers={0: 0xFFFFFFFF, 1: local_value},
    )
    corpus.add(
        "table8_address_overflow",
        [instruction(4, LocalOpcode.TABLE8, dst=2, src0=0, src1=1)],
        registers={0: 0xFFFFFFFF, 1: 0x2001},
    )
    corpus.add(
        "table16_scaled_address_overflow",
        [instruction(4, LocalOpcode.TABLE16, dst=2, src0=0, src1=1)],
        registers={0: 2, 1: 0xFFFFFFFF},
    )
    corpus.add(
        "table32_scaled_address_overflow",
        [instruction(4, LocalOpcode.TABLE32, dst=2, src0=0, src1=1)],
        registers={0: 0, 1: 0x80000000},
    )
    corpus.add(
        "fifo_push_metadata_fault",
        [instruction(4, LocalOpcode.FIFO_PUSH, src0=4, src1=5)],
        registers={4: local_value, 5: 0},
    )

    sample0 = random_source.randint(-0x80000000, 0x7FFFFFFF)
    sample1 = random_source.randint(-0x80000000, 0x7FFFFFFF)
    corpus.add(
        "requant_shared_extreme",
        [instruction(5, KernelOpcode.REQUANT, dst=2, src0=0, src1=1, aux=0xA0, immediate=2)],
        registers={0: 0x100, 1: 0x180, 2: 0x200},
        scratch_words={
            **_word_map(0x2100, [sample0, -0x80000000]),
            **_word_map(0x2180, [0x300]),
            **_word_map(0x2300, [1 << 29, 0x7FFFFFFF]),
        },
        check_words=[0x2200, 0x2204],
    )
    corpus.add(
        "stereo_shared_extreme",
        [instruction(5, KernelOpcode.STEREO, dst=2, src0=0, src1=1, aux=2, immediate=2)],
        registers={0: 0x100, 1: 0x180, 2: 0x200},
        scratch_words={
            **_word_map(0x2100, [sample0, 0x7FFFFFFF]),
            **_word_map(0x2180, [0x300]),
            **_word_map(0x2300, [sample1, 1]),
        },
        check_words=[0x2200, 0x2204, 0x2208, 0x220C],
    )

    imdct6_matrix = [0] * 72
    for index in range(6):
        imdct6_matrix[index * 6 + index] = 1 << 30
    corpus.add(
        "imdct6_shared_extreme",
        [instruction(5, KernelOpcode.IMDCT6, dst=2, src0=0, src1=1, immediate=1)],
        registers={0: 0x100, 1: 0x180, 2: 0x200},
        table_words=_word_map(0, imdct6_matrix),
        scratch_words={
            **_word_map(0x2100, [sample0, sample1, -0x80000000, 0x7FFFFFFF, -1, 1]),
            **_word_map(0x2180, [0x80000000]),
        },
        check_words=[0x2200 + index * 4 for index in range(12)],
    )

    imdct18_matrix = [0] * 648
    for index in range(18):
        imdct18_matrix[index * 18 + index] = 1 << 30
    imdct18_inputs = [
        -0x80000000,
        0x7FFFFFFF,
        *(random_source.randint(-0x80000000, 0x7FFFFFFF) for _ in range(16)),
    ]
    corpus.add(
        "imdct18_shared_random",
        [instruction(5, KernelOpcode.IMDCT18, dst=2, src0=0, src1=1, immediate=1)],
        registers={0: 0x100, 1: 0x180, 2: 0x200},
        table_words=_word_map(0x200, imdct18_matrix),
        scratch_words={
            **_word_map(0x2100, imdct18_inputs),
            **_word_map(0x2180, [0x80000200]),
        },
        check_words=[0x2200 + index * 4 for index in range(36)],
    )

    dct_matrix = [0] * 1024
    dct_window = [0] * 512
    for index in range(32):
        dct_matrix[index * 32 + index] = 1 << 30
        dct_window[index] = 1 << 30
    dct_inputs = [
        -0x80000000,
        0x7FFFFFFF,
        *(random_source.randint(-0x100000, 0x100000) for _ in range(30)),
    ]
    corpus.add(
        "dct32_shared_random",
        [instruction(5, KernelOpcode.DCT32_POLY, dst=2, src0=0, src1=1, immediate=1)],
        registers={0: 0x100, 1: 0x180, 2: 0x200},
        table_words={**_word_map(0, dct_matrix), **_word_map(0x1000, dct_window)},
        scratch_words={
            **_word_map(0x2100, dct_inputs),
            **_word_map(0x2180, [0x80000000, 0x80001000, 0x300, 0]),
            **_word_map(0x2300, [0] * 512),
        },
        check_words=[0x2200 + index * 4 for index in range(32)] + [0x218C],
    )

    corpus.add(
        "fixed_shared_random",
        [instruction(5, KernelOpcode.FIXED, dst=2, src0=0, src1=1, aux=0, immediate=3)],
        registers={0: 0x100, 1: 0x180, 2: 0x200},
        scratch_words={
            **_word_map(0x2100, [-0x80000000, 0x7FFFFFFF, sample0]),
            **_word_map(0x2180, [0x300]),
            **_word_map(0x2300, [random_source.getrandbits(32)]),
        },
        check_words=[0x2200, 0x2204, 0x2208],
    )
    corpus.add(
        "fixed_shared_history_retention",
        [
            instruction(5, KernelOpcode.FIXED, dst=2, src0=0, src1=1, aux=2, immediate=2),
            instruction(5, KernelOpcode.FIXED, dst=4, src0=3, src1=1, aux=2, immediate=2),
        ],
        registers={0: 0x100, 1: 0x180, 2: 0x200, 3: 0x400, 4: 0x500},
        scratch_words={
            **_word_map(0x2100, [13, -7]),
            **_word_map(0x2180, [0x300]),
            **_word_map(0x2300, [5, -3]),
            **_word_map(0x2400, [1, -2]),
        },
        check_words=[0x2200, 0x2204, 0x2300, 0x2304, 0x2500, 0x2504],
    )
    corpus.add(
        "lpc_shared_random",
        [instruction(5, KernelOpcode.LPC, dst=2, src0=0, src1=1, aux=2, immediate=2)],
        registers={0: 0x100, 1: 0x180, 2: 0x200},
        table_words=_word_map(0x1400, [1, -1]),
        scratch_words={
            **_word_map(0x2100, [sample0 >> 4, sample1 >> 4]),
            **_word_map(0x2180, [0x80001400, 0x300, 0]),
            **_word_map(0x2300, [5, -3]),
        },
        check_words=[0x2200, 0x2204, 0x2300, 0x2304],
    )
    corpus.add(
        "lpc_shared_extreme",
        [instruction(5, KernelOpcode.LPC, dst=2, src0=0, src1=1, aux=2, immediate=2)],
        registers={0: 0x100, 1: 0x180, 2: 0x200},
        table_words=_word_map(0x1400, [0, 0]),
        scratch_words={
            **_word_map(0x2100, [-0x80000000, 0x7FFFFFFF]),
            **_word_map(0x2180, [0x80001400, 0x300, 0]),
            **_word_map(0x2300, [sample0, sample1]),
        },
        check_words=[0x2200, 0x2204, 0x2300, 0x2304],
    )
    corpus.add(
        "decorrelate_shared_extreme",
        [instruction(5, KernelOpcode.DECORRELATE, dst=2, src0=0, src1=1, aux=1, immediate=3)],
        registers={0: 0x100, 1: 0x180, 2: 0x200},
        scratch_words={
            **_word_map(0x2100, [-0x80000000, 0x7FFFFFFF, sample0]),
            **_word_map(0x2180, [0x300]),
            **_word_map(0x2300, [0, 0, 0]),
        },
        check_words=[0x2200 + index * 4 for index in range(6)],
    )

    resample_coefficients = [0] * 512
    for phase in range(32):
        resample_coefficients[phase * 16 + 7] = 1 << 30
    corpus.add(
        "resample_shared_profile3",
        [instruction(5, KernelOpcode.RESAMPLE, dst=2, src0=0, src1=1, aux=3, immediate=1)],
        registers={0: 0x100, 1: 0x180, 2: 0x200},
        table_words=_word_map(0, resample_coefficients),
        scratch_words={
            **_word_map(
                0x20E4,
                [0] * 7
                + [-0x80000000]
                + [random_source.randint(-1000, 1000) for _ in range(9)],
            ),
            **_word_map(0x2180, [0x80000000, 0x80000800, 0x80001000, 0, 0, 0, 0, 1]),
        },
        check_words=[0x2200, 0x2204, 0x218C, 0x2190, 0x2194, 0x2198],
    )
    corpus.add(
        "pcm_pack_shared_extreme",
        [instruction(5, KernelOpcode.PCM_PACK, dst=2, src0=0, src1=1, aux=0, immediate=2)],
        registers={0: 0x100, 1: 0x180, 2: 0x200},
        scratch_words={
            **_word_map(0x2100, [-0x80000000, 0x7FFFFFFF, sample0, sample1]),
            **_word_map(0x2180, [1 << 30, 2]),
        },
        check_words=[0x2200, 0x2204],
    )

    parameter_words = {
        KernelOpcode.REQUANT: [0],
        KernelOpcode.STEREO: [0],
        KernelOpcode.IMDCT6: [0],
        KernelOpcode.IMDCT18: [0],
        KernelOpcode.DCT32_POLY: [0, 0, 0, 0],
        KernelOpcode.FIXED: [0],
        KernelOpcode.LPC: [0, 0, 0],
        KernelOpcode.DECORRELATE: [0],
        KernelOpcode.RESAMPLE: [0, 0, 0, 0, 0, 0, 0, 1],
        KernelOpcode.PCM_PACK: [1 << 30, 1],
    }
    fault_aux = {
        KernelOpcode.REQUANT: 0x80,
        KernelOpcode.STEREO: 0,
        KernelOpcode.IMDCT6: 0,
        KernelOpcode.IMDCT18: 0,
        KernelOpcode.DCT32_POLY: 0,
        KernelOpcode.FIXED: 2,
        KernelOpcode.LPC: 2,
        KernelOpcode.DECORRELATE: 0,
        KernelOpcode.RESAMPLE: 0,
        KernelOpcode.PCM_PACK: 0,
    }
    for opcode in KernelOpcode:
        corpus.add(
            f"{opcode.name.lower()}_alignment_fault",
            [instruction(5, opcode, dst=2, src0=0, src1=1, aux=fault_aux[opcode], immediate=1)],
            registers={0: 0x101, 1: 0x180, 2: 0x200},
            scratch_words=_word_map(0x2180, parameter_words[opcode]),
        )

    expected_opcodes = {
        *((2, int(opcode)) for opcode in BitstreamOpcode),
        *((3, int(opcode)) for opcode in EntropyOpcode),
        *((4, int(opcode)) for opcode in LocalOpcode),
        *((5, int(opcode)) for opcode in KernelOpcode),
    }
    assert corpus.covered == expected_opcodes
    path = tmp_path / "apu_p4_corpus_generated.svh"
    corpus.write(path)
    return path, corpus.case_index


def test_p4_production_primitives_icarus_and_verilator(tmp_path: Path) -> None:
    iverilog = shutil.which("iverilog")
    vvp = shutil.which("vvp")
    sv2v = shutil.which("sv2v")
    verilator = shutil.which("verilator")
    sources = _p4_rtl_sources()
    include = ROOT / "rtl/ip/multimedia"
    vector_path, vector_count = _requant_corpus(tmp_path)
    shared_corpus_path, shared_case_count = _shared_primitive_corpus(tmp_path)
    assert shared_case_count >= 32
    assert shared_corpus_path.is_file()

    if iverilog is not None and vvp is not None and sv2v is not None:
        source_list = tmp_path / "apu_p4_primitives.fl"
        source_list.write_text(
            "\n".join(
                [
                    "+define+APU_P4_SHARED_CORPUS",
                    f"+incdir+{include}",
                    f"+incdir+{tmp_path}",
                    *(str(path) for path in sources),
                    "",
                ]
            ),
            encoding="utf-8",
        )
        converted = tmp_path / "apu_p4_primitives.v"
        subprocess.run(
            [
                sys.executable,
                str(ROOT / "rtl/mini/script/convt_sv2v.py"),
                "-f",
                str(source_list),
                "--output",
                str(converted),
            ],
            check=True,
        )
        simulation = tmp_path / "apu_p4_iverilog"
        subprocess.run(
            [iverilog, "-g2012", "-s", "apu_p4_primitives_tb", "-o", str(simulation), str(converted)],
            check=True,
        )
        result = subprocess.run(
            [vvp, str(simulation), f"+VECTORS={vector_path}", f"+VECTOR_COUNT={vector_count}"],
            check=True,
            text=True,
            capture_output=True,
        )
        assert "APU_P4_PRIMITIVES_PASS" in result.stdout

    if verilator is not None:
        object_dir = tmp_path / "verilator_obj"
        ccache_dir = tmp_path / "ccache"
        ccache_dir.mkdir()
        subprocess.run(
            [
                verilator,
                "--binary",
                "--timing",
                "-Wno-fatal",
                "--top-module",
                "apu_p4_primitives_tb",
                "-DAPU_P4_SHARED_CORPUS",
                f"-I{include}",
                f"-I{tmp_path}",
                "-Mdir",
                str(object_dir),
                "-o",
                "simv",
                *(str(path) for path in sources),
            ],
            check=True,
            text=True,
            capture_output=True,
            env={
                **os.environ,
                "CCACHE_DIR": str(ccache_dir),
                "CCACHE_TEMPDIR": str(ccache_dir),
            },
        )
        result = subprocess.run(
            [
                str(object_dir / "simv"),
                f"+VECTORS={vector_path}",
                f"+VECTOR_COUNT={vector_count}",
            ],
            check=True,
            text=True,
            capture_output=True,
        )
        assert "APU_P4_PRIMITIVES_PASS" in result.stdout


def test_p4_loader_publishes_control_and_table_atomically(tmp_path: Path) -> None:
    iverilog = shutil.which("iverilog")
    vvp = shutil.which("vvp")
    sv2v = shutil.which("sv2v")
    if iverilog is None or vvp is None or sv2v is None:
        return

    program = [
        instruction(InstructionClass.CONTROL, ControlOpcode.WAIT, aux=1),
        instruction(InstructionClass.CONTROL, ControlOpcode.END),
    ]
    entries = [
        Entry(index, 0, 0, 1, 1, 2, 0x1000, 0x1000, 0x40, 0, 4)
        for index in range(3)
    ]
    bundle = build_apumc(
        program,
        entries,
        build_id=0x1234,
        target="p4",
        table_payload=struct.pack("<I", 0x00010001),
    )
    image = tmp_path / "apu_p4_loader.hex"
    image.write_text(
        "\n".join(f"{word:08x}" for (word,) in struct.iter_unpack("<I", bundle)) + "\n",
        encoding="utf-8",
    )
    invalid_bundle = bytearray(bundle)
    struct.pack_into("<I", invalid_bundle, 64 + 28, 8)
    struct.pack_into("<I", invalid_bundle, 44, 0)
    struct.pack_into("<I", invalid_bundle, 44, binascii.crc32(invalid_bundle[64:]))
    invalid_image = tmp_path / "apu_p4_loader_invalid.hex"
    invalid_image.write_text(
        "\n".join(
            f"{word:08x}" for (word,) in struct.iter_unpack("<I", invalid_bundle)
        )
        + "\n",
        encoding="utf-8",
    )
    multimedia = ROOT / "rtl/ip/multimedia"
    source_list = tmp_path / "apu_p4_loader.fl"
    source_list.write_text(
        "\n".join(
            [
                f"+incdir+{multimedia}",
                str(ROOT / "rtl/tech/tc_sram.sv"),
                str(multimedia / "apu_microcode_pkg.sv"),
                str(multimedia / "apu_control_store.sv"),
                str(multimedia / "apu_local_sram.sv"),
                str(multimedia / "apu_microcode_loader.sv"),
                str(ROOT / "tests/rtl/apu_p4_loader_tb.sv"),
                "",
            ]
        ),
        encoding="utf-8",
    )
    converted = tmp_path / "apu_p4_loader.v"
    subprocess.run(
        [
            sys.executable,
            str(ROOT / "rtl/mini/script/convt_sv2v.py"),
            "-f",
            str(source_list),
            "--output",
            str(converted),
        ],
        check=True,
    )
    simulation = tmp_path / "apu_p4_loader"
    subprocess.run(
        [iverilog, "-g2012", "-s", "apu_p4_loader_tb", "-o", str(simulation), str(converted)],
        check=True,
    )
    result = subprocess.run(
        [vvp, str(simulation), f"+IMAGE={image}", f"+INVALID_IMAGE={invalid_image}"],
        check=True,
        text=True,
        capture_output=True,
    )
    assert "APU_P4_LOADER_PASS" in result.stdout


def test_p4_sequencer_kernel_pending_and_wait(tmp_path: Path) -> None:
    iverilog = shutil.which("iverilog")
    vvp = shutil.which("vvp")
    sv2v = shutil.which("sv2v")
    if iverilog is None or vvp is None or sv2v is None:
        return
    multimedia = ROOT / "rtl/ip/multimedia"
    sources = [
        ROOT / "rtl/managed/clusterip/common/rtl/utils/fifo.sv",
        multimedia / "apu_microcode_pkg.sv",
        multimedia / "apu_control_store.sv",
        multimedia / "apu_local_sram.sv",
        multimedia / "apu_bitstream_engine.sv",
        multimedia / "apu_entropy_engine.sv",
        multimedia / "apu_reconstruction_engine.sv",
        multimedia / "apu_transform_engine.sv",
        multimedia / "apu_resampler.sv",
        multimedia / "apu_kernel_engine.sv",
        multimedia / "apu_primitive_dispatcher.sv",
        multimedia / "apu_codec_sequencer.sv",
        ROOT / "tests/rtl/apu_p4_sequencer_tb.sv",
    ]
    source_list = tmp_path / "apu_p4_sequencer.fl"
    source_list.write_text(
        "\n".join([f"+incdir+{multimedia}", *(str(path) for path in sources), ""]),
        encoding="utf-8",
    )
    converted = tmp_path / "apu_p4_sequencer.v"
    subprocess.run(
        [
            sys.executable,
            str(ROOT / "rtl/mini/script/convt_sv2v.py"),
            "-f",
            str(source_list),
            "--output",
            str(converted),
        ],
        check=True,
    )
    simulation = tmp_path / "apu_p4_sequencer"
    subprocess.run(
        [iverilog, "-g2012", "-s", "apu_p4_sequencer_tb", "-o", str(simulation), str(converted)],
        check=True,
    )
    result = subprocess.run([vvp, str(simulation)], check=True, text=True, capture_output=True)
    assert "APU_P4_SEQUENCER_PASS" in result.stdout
