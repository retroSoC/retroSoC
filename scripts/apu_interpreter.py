"""Reference interpreter for the enabled APU-P3/P4/P5 microcode targets."""

from __future__ import annotations

import argparse
import json
from dataclasses import dataclass, field
from pathlib import Path

from apu_isa import (
    APUMC_TARGETS,
    BitstreamOpcode,
    ControlOpcode,
    EntropyOpcode,
    Entry,
    Instruction,
    InstructionClass,
    LocalOpcode,
    ScalarOpcode,
    TransportOpcode,
    parse_apumc,
    trap_detail,
    validate_instruction,
)
from apu_primitives import PrimitiveBam, PrimitiveFault, PrimitiveResult


class SequencerTrap(RuntimeError):
    def __init__(self, reason: int, pc: int, instruction: Instruction, detail: int | None = None):
        self.reason = reason
        self.pc = pc
        self.instruction = instruction
        self.detail = trap_detail(reason, pc, instruction) if detail is None else detail
        super().__init__(f"APU sequencer trap {reason} at PC {pc}")


@dataclass
class PredicateInputs:
    input_exhausted: bool = False
    input_ready: bool = False
    output_ready: bool = False
    kernel_done: bool = False
    transport_done: bool = False


@dataclass
class TransportCommand:
    opcode: TransportOpcode
    destination: int
    offset: int
    count: int
    payload: bytes
    cycles: int


@dataclass
class TransportModel:
    input_data: bytes = b""
    output_capacity: int = 0xFFFFFFFF
    stream_output: bool = False
    latency: int = 2
    output_frame_bytes: int = 4
    input_cursor: int = 0
    output: bytearray = field(default_factory=bytearray)
    frames: int = 0
    logical_input: int = 0
    logical_output: int = 0
    result_code: int = 0
    result_stage: int = 0
    result_detail: int = 0
    events: int = 0
    pending: list[TransportCommand] = field(default_factory=list)
    completed: list[tuple[int, int]] = field(default_factory=list)

    @property
    def idle(self) -> bool:
        return not self.pending

    def reset(self) -> None:
        self.input_cursor = 0
        self.output.clear()
        self.frames = 0
        self.logical_input = 0
        self.logical_output = 0
        self.result_code = 0
        self.result_stage = 0
        self.result_detail = 0
        self.events = 0
        self.pending.clear()
        self.completed.clear()

    def abort(self) -> None:
        self.pending.clear()
        self.completed.clear()

    def issue(
        self,
        instruction: Instruction,
        registers: list[int],
        entry: Entry,
        primitives: PrimitiveBam,
    ) -> bool:
        opcode = TransportOpcode(instruction.opcode)
        offset = registers[instruction.src0]
        count = registers[instruction.src1]
        if opcode == TransportOpcode.INPUT_REFILL:
            if (
                count < 4
                or count > 256
                or count & 3
                or offset & 3
                or offset + count > entry.scratch_bytes
            ):
                raise PrimitiveFault(11, 11, 5)
            actual = min(count, len(self.input_data) - self.input_cursor)
            needed = (actual + 3) // 4
            if any(command.opcode == TransportOpcode.INPUT_REFILL for command in self.pending):
                return False
            if len(primitives.input_fifo.words) + needed > 64:
                return False
            payload = self.input_data[self.input_cursor : self.input_cursor + actual]
            self.pending.append(
                TransportCommand(
                    opcode, instruction.dst, offset, actual, payload, max(1, self.latency)
                )
            )
            return True
        if opcode in (TransportOpcode.OUTPUT_COMMIT, TransportOpcode.OUTPUT_STREAM):
            if count < 1 or count > 256 or offset & 3 or offset + count > entry.scratch_bytes:
                raise PrimitiveFault(11, 11, 5)
            if count % self.output_frame_bytes or (
                (opcode == TransportOpcode.OUTPUT_STREAM) != self.stream_output
            ):
                raise PrimitiveFault(11, 11, 5)
            if not primitives.output_fifo.empty:
                raise PrimitiveFault(11, 11, 5)
            if any(
                command.opcode in (TransportOpcode.OUTPUT_COMMIT, TransportOpcode.OUTPUT_STREAM)
                for command in self.pending
            ):
                return False
            if (
                opcode == TransportOpcode.OUTPUT_COMMIT
                and len(self.output) + count > self.output_capacity
            ):
                raise PrimitiveFault(8, 8, 9)
            address = entry.scratch_base + offset
            payload = primitives.memory.read(address, count, entry)
            self.pending.append(
                TransportCommand(
                    opcode, instruction.dst, offset, count, payload, max(1, self.latency)
                )
            )
            return True
        if opcode == TransportOpcode.DMA_WAIT:
            if not self.idle:
                return False
            self.completed.append((instruction.dst, 0))
        elif opcode == TransportOpcode.FRAME_COMMIT:
            if (
                count != self.output_frame_bytes
                or self.logical_input + offset > self.input_cursor
                or self.logical_output + count > len(self.output)
            ):
                raise PrimitiveFault(11, 11, 9)
            self.logical_input = min(0xFFFFFFFF, self.logical_input + offset)
            self.logical_output = min(0xFFFFFFFF, self.logical_output + count)
            self.frames = min(0xFFFFFFFF, self.frames + 1)
            self.completed.append((instruction.dst, 0))
        elif opcode == TransportOpcode.JOB_RESULT:
            code = offset & 0x3F
            if offset >> 6 or code > 22:
                raise PrimitiveFault(11, 11, 1)
            self.result_code = code
            self.result_stage = instruction.aux & 0xF
            self.result_detail = count
            self.completed.append((instruction.dst, 0))
        else:
            self.events |= instruction.immediate & 0x0C0
            self.completed.append((instruction.dst, 0))
        return True

    def tick(self, entry: Entry, primitives: PrimitiveBam) -> None:
        if not self.pending:
            return
        for command in self.pending:
            command.cycles -= 1
        ready = [command for command in self.pending if command.cycles == 0]
        for command in ready:
            if command.opcode == TransportOpcode.INPUT_REFILL:
                primitives.memory.write(entry.scratch_base + command.offset, command.payload, entry)
                for position in range(0, command.count, 4):
                    data = command.payload[position : position + 4]
                    last = self.input_cursor + position + len(data) == len(self.input_data)
                    primitives.input_fifo.push(
                        int.from_bytes(data.ljust(4, b"\0"), "little")
                        | (len(data) << 32)
                        | (int(last) << 40)
                    )
                self.input_cursor += command.count
            else:
                self.output.extend(command.payload)
            self.completed.append((command.destination, command.count))
            self.pending.remove(command)


@dataclass
class Machine:
    instructions: list[Instruction]
    entry: Entry
    predicate_inputs: PredicateInputs = field(default_factory=PredicateInputs)
    timeout: int = 0xFFFF
    fetch_no_retirement_cycles: int = 2
    stall_cycles: dict[int, int] = field(default_factory=dict)
    registers: list[int] = field(default_factory=lambda: [0] * 16)
    eq: bool = False
    signed_lt: bool = False
    unsigned_lt: bool = False
    pc: int = 0
    retired: int = 0
    return_stack: list[int] = field(default_factory=list)
    loops: dict[int, tuple[int, int]] = field(default_factory=dict)
    watchdog: int = 0
    trace: list[dict[str, object]] = field(default_factory=list)
    target: str = "p3"
    primitives: PrimitiveBam | None = None
    transport: TransportModel | None = None
    primitive_cycles: list[int] = field(default_factory=list)
    kernel_result: PrimitiveResult | None = field(default=None, init=False)
    kernel_fault: PrimitiveFault | None = field(default=None, init=False)
    kernel_pending_fault: PrimitiveFault | None = field(default=None, init=False)
    kernel_pending_dst: int | None = field(default=None, init=False)
    kernel_cycles_remaining: int = field(default=0, init=False)
    transport_pending_dst: set[int] = field(default_factory=set, init=False)
    transport_fault: PrimitiveFault | None = field(default=None, init=False)

    def __post_init__(self) -> None:
        self.begin_entry(self.entry)

    @staticmethod
    def _signed(value: int) -> int:
        return value if value < 0x80000000 else value - 0x100000000

    def _predicate(self, predicate: int) -> bool:
        input_ready = self.predicate_inputs.input_ready
        output_ready = self.predicate_inputs.output_ready
        kernel_done = self.predicate_inputs.kernel_done
        input_exhausted = self.predicate_inputs.input_exhausted
        if self.target in ("p4", "p5") and self.primitives is not None:
            input_ready = not self.primitives.input_fifo.empty
            output_ready = not self.primitives.output_fifo.full
            kernel_done = self.primitives.kernel_done
            input_exhausted = (
                self.primitives.eof
                and self.primitives.input_fifo.empty
                and not self.primitives.bits
            )
        values = (
            True,
            self.eq,
            not self.eq,
            self.signed_lt,
            not self.signed_lt,
            self.unsigned_lt,
            not self.unsigned_lt,
            input_exhausted,
            input_ready,
            output_ready,
            kernel_done,
            self.transport.idle
            if self.transport is not None
            else self.predicate_inputs.transport_done,
        )
        if predicate >= len(values):
            raise SequencerTrap(1, self.pc, self.instructions[self.pc])
        return values[predicate]

    def _write(self, register: int, value: int) -> None:
        self.registers[register] = value & 0xFFFFFFFF

    def _complete_kernel(self) -> None:
        if self.kernel_pending_fault is not None:
            self.kernel_fault = self.kernel_pending_fault
        elif self.kernel_result is not None:
            for register, value in self.kernel_result.writes.items():
                self._write(register, value)
            if self.primitives is not None:
                self.primitives.kernel_done = True
        self.kernel_result = None
        self.kernel_pending_fault = None
        self.kernel_pending_dst = None
        self.kernel_cycles_remaining = 0

    def _tick_kernel(self) -> None:
        if self.kernel_pending_dst is None:
            return
        if self.kernel_cycles_remaining > 0:
            self.kernel_cycles_remaining -= 1
        if self.kernel_cycles_remaining == 0:
            self._complete_kernel()

    def _tick_transport(self) -> None:
        if self.transport is None or self.primitives is None:
            return
        try:
            self.transport.tick(self.entry, self.primitives)
        except PrimitiveFault as error:
            self.transport_fault = error
            return
        while self.transport.completed:
            register, value = self.transport.completed.pop(0)
            self._write(register, value)
            self.transport_pending_dst.discard(register)

    def _pending_dependency(self, instruction: Instruction) -> bool:
        pending_registers = set(self.transport_pending_dst)
        if self.kernel_pending_dst is not None:
            pending_registers.add(self.kernel_pending_dst)
        return any(
            self._uses_pending_register(instruction, pending) for pending in pending_registers
        )

    @staticmethod
    def _uses_pending_register(instruction: Instruction, pending: int) -> bool:
        instruction_class = instruction.instruction_class
        opcode = instruction.opcode
        if instruction_class == InstructionClass.CONTROL:
            if opcode == ControlOpcode.END:
                return True
            return opcode == ControlOpcode.LOOP_SETUP and instruction.src0 == pending
        if instruction_class == InstructionClass.SCALAR:
            if opcode == ScalarOpcode.MOV:
                return instruction.src0 == pending or instruction.dst == pending
            if opcode == ScalarOpcode.MOVI:
                return instruction.dst == pending
            if opcode == ScalarOpcode.CMP:
                return instruction.src0 == pending or instruction.src1 == pending
            if opcode == ScalarOpcode.SAT:
                return instruction.src0 == pending or instruction.dst == pending
            return (
                instruction.src0 == pending
                or instruction.src1 == pending
                or instruction.dst == pending
            )
        return True

    def begin_entry(self, entry: Entry | None = None) -> None:
        if entry is not None:
            self.entry = entry
        self.pc = self.entry.entry_pc
        self.retired = 0
        self.registers = [0] * 16
        self.eq = False
        self.signed_lt = False
        self.unsigned_lt = False
        self.return_stack.clear()
        self.loops.clear()
        self.watchdog = 0
        self.kernel_result = None
        self.kernel_fault = None
        self.kernel_pending_fault = None
        self.kernel_pending_dst = None
        self.kernel_cycles_remaining = 0
        self.transport_pending_dst.clear()
        self.transport_fault = None
        if self.primitives is not None:
            self.primitives.reset_mutable()
        if self.transport is not None:
            self.transport.reset()

    def abort(self) -> None:
        self.kernel_result = None
        self.kernel_fault = None
        self.kernel_pending_fault = None
        self.kernel_pending_dst = None
        self.kernel_cycles_remaining = 0
        self.transport_pending_dst.clear()
        self.transport_fault = None
        if self.transport is not None:
            self.transport.abort()
        self.watchdog = 0
        if self.primitives is not None:
            self.primitives.reset_mutable()

    def reset(self) -> None:
        self.begin_entry(self.entry)

    def _retire(self, instruction: Instruction, predicate_true: bool) -> None:
        self.retired += 1
        self.watchdog = 0
        self.trace.append(
            {
                "pc": self.pc,
                "instruction": f"0x{instruction.encode():016x}",
                "predicate": predicate_true,
                "retired": self.retired,
            }
        )

    def _no_retirement_cycle(
        self, instruction: Instruction, *, tick_kernel: bool = True, tick_transport: bool = True
    ) -> None:
        if tick_kernel:
            self._tick_kernel()
        if tick_transport:
            self._tick_transport()
        self.watchdog += 1
        if self.timeout <= 0 or self.watchdog >= self.timeout:
            raise SequencerTrap(7, self.pc, instruction)

    def _saturate(self, value: int, width: int, signed: bool) -> int:
        width = 32 if width == 0 else width
        if signed:
            signed_value = self._signed(value)
            maximum = (1 << (width - 1)) - 1
            minimum = -(1 << (width - 1))
            return min(max(signed_value, minimum), maximum) & 0xFFFFFFFF
        return min(value, (1 << width) - 1)

    def step(self) -> bool:
        if self.pc < self.entry.first_pc or self.pc > self.entry.last_pc:
            raise SequencerTrap(2, self.pc, Instruction(0, 0))
        instruction = self.instructions[self.pc]
        self._tick_kernel()
        self._tick_transport()
        if self.kernel_fault is not None:
            fault = self.kernel_fault
            self.kernel_fault = None
            raise SequencerTrap(fault.reason, self.pc, instruction)
        if self.transport_fault is not None:
            fault = self.transport_fault
            self.transport_fault = None
            raise SequencerTrap(fault.reason, self.pc, instruction)
        try:
            validate_instruction(instruction, self.target)
        except ValueError as error:
            raise SequencerTrap(1, self.pc, instruction) from error
        if self.retired >= self.entry.max_retired:
            raise SequencerTrap(8, self.pc, instruction)
        predicate_true = self._predicate(instruction.predicate)
        if not predicate_true:
            if self.pc == self.entry.last_pc or self.pc == 0x7FF:
                raise SequencerTrap(2, self.pc, instruction)
            self._retire(instruction, predicate_true)
            self.pc += 1
            return False

        if self._pending_dependency(instruction):
            self._no_retirement_cycle(instruction, tick_kernel=False, tick_transport=False)
            return False

        next_pc = self.pc + 1
        terminal = False
        if instruction.instruction_class == InstructionClass.CONTROL:
            opcode = ControlOpcode(instruction.opcode)
            if opcode == ControlOpcode.END:
                if self.transport is not None and not self.transport.idle:
                    self._no_retirement_cycle(instruction, tick_kernel=False, tick_transport=False)
                    return False
                terminal = True
            elif opcode == ControlOpcode.TRAP:
                raise SequencerTrap(10, self.pc, instruction, instruction.immediate)
            elif opcode == ControlOpcode.JUMP_FWD:
                next_pc += instruction.immediate
            elif opcode == ControlOpcode.CALL_FWD:
                if len(self.return_stack) == 4:
                    raise SequencerTrap(3, self.pc, instruction)
                self.return_stack.append(next_pc)
                next_pc += instruction.immediate
            elif opcode == ControlOpcode.RET:
                if not self.return_stack:
                    raise SequencerTrap(3, self.pc, instruction)
                next_pc = self.return_stack.pop()
            elif opcode == ControlOpcode.LOOP_SETUP:
                slot = instruction.aux & 3
                count = self.registers[instruction.src0] & 0xFFFF
                if slot in self.loops or count == 0 or count > self.entry.max_loop_count:
                    raise SequencerTrap(4, self.pc, instruction)
                self.loops[slot] = (count, next_pc)
            elif opcode == ControlOpcode.LOOP_BACK:
                slot = instruction.aux & 3
                if slot not in self.loops:
                    raise SequencerTrap(4, self.pc, instruction)
                count, start = self.loops[slot]
                target = next_pc - instruction.immediate
                if target != start or target < self.entry.first_pc:
                    raise SequencerTrap(4, self.pc, instruction)
                if count > 1:
                    self.loops[slot] = (count - 1, start)
                    next_pc = target
                else:
                    del self.loops[slot]
            elif opcode == ControlOpcode.WAIT:
                ready = False
                if self.primitives is not None:
                    ready = (
                        (
                            instruction.aux == 0
                            and self.transport is not None
                            and self.transport.idle
                        )
                        or (instruction.aux == 1 and self.primitives.kernel_done)
                        or (instruction.aux == 2 and not self.primitives.input_fifo.empty)
                        or (instruction.aux == 3 and not self.primitives.output_fifo.full)
                        or (
                            instruction.aux == 4
                            and self.transport is not None
                            and self.transport.idle
                        )
                        or (
                            instruction.aux == 5
                            and self.transport is not None
                            and self.transport.idle
                        )
                    )
                if not ready:
                    self._no_retirement_cycle(instruction, tick_kernel=False, tick_transport=False)
                    return False
        elif instruction.instruction_class == InstructionClass.SCALAR:
            opcode = ScalarOpcode(instruction.opcode)
            source0 = self.registers[instruction.src0]
            source1 = self.registers[instruction.src1]
            if opcode == ScalarOpcode.MOV:
                self._write(instruction.dst, source0)
            elif opcode == ScalarOpcode.MOVI:
                self._write(instruction.dst, instruction.immediate)
            elif opcode == ScalarOpcode.ADD:
                self._write(instruction.dst, source0 + source1)
            elif opcode == ScalarOpcode.SUB:
                self._write(instruction.dst, source0 - source1)
            elif opcode == ScalarOpcode.AND:
                self._write(instruction.dst, source0 & source1)
            elif opcode == ScalarOpcode.OR:
                self._write(instruction.dst, source0 | source1)
            elif opcode == ScalarOpcode.XOR:
                self._write(instruction.dst, source0 ^ source1)
            elif opcode == ScalarOpcode.SHL:
                self._write(instruction.dst, source0 << (source1 & 31))
            elif opcode == ScalarOpcode.SHR:
                self._write(instruction.dst, source0 >> (source1 & 31))
            elif opcode == ScalarOpcode.SAR:
                self._write(instruction.dst, self._signed(source0) >> (source1 & 31))
            elif opcode == ScalarOpcode.CMP:
                self.eq = source0 == source1
                self.signed_lt = self._signed(source0) < self._signed(source1)
                self.unsigned_lt = source0 < source1
            elif opcode in (ScalarOpcode.MIN, ScalarOpcode.MAX):
                left = self._signed(source0) if instruction.aux else source0
                right = self._signed(source1) if instruction.aux else source1
                result = min(left, right) if opcode == ScalarOpcode.MIN else max(left, right)
                self._write(instruction.dst, result)
            elif opcode == ScalarOpcode.SAT:
                self._write(
                    instruction.dst,
                    self._saturate(source0, instruction.aux & 0x1F, bool(instruction.aux & 0x20)),
                )
        elif instruction.instruction_class == InstructionClass.TRANSPORT:
            if self.transport is None or self.primitives is None:
                raise SequencerTrap(6, self.pc, instruction)
            try:
                accepted = self.transport.issue(
                    instruction, self.registers, self.entry, self.primitives
                )
            except PrimitiveFault as error:
                raise SequencerTrap(error.reason, self.pc, instruction) from error
            if not accepted:
                self._no_retirement_cycle(instruction, tick_kernel=False, tick_transport=False)
                return False
            if instruction.opcode <= TransportOpcode.OUTPUT_STREAM:
                self.transport_pending_dst.add(instruction.dst)
            else:
                self._tick_transport()
        else:
            if self.primitives is None:
                raise SequencerTrap(6, self.pc, instruction)
            if instruction.instruction_class == InstructionClass.LOCAL:
                opcode = LocalOpcode(instruction.opcode)
                if (opcode == LocalOpcode.FIFO_POP and self.primitives.input_fifo.empty) or (
                    opcode == LocalOpcode.FIFO_PUSH and self.primitives.output_fifo.full
                ):
                    self._no_retirement_cycle(instruction, tick_kernel=False, tick_transport=False)
                    return False
            if instruction.instruction_class == InstructionClass.BITSTREAM:
                opcode = BitstreamOpcode(instruction.opcode)
                required = (
                    instruction.immediate & 0x3F
                    if opcode
                    in (
                        BitstreamOpcode.REFILL,
                        BitstreamOpcode.PEEK,
                        BitstreamOpcode.GET,
                        BitstreamOpcode.SKIP,
                    )
                    else 1
                )
                self.primitives._refill(required)
                if len(self.primitives.bits) < required and not self.primitives.eof:
                    self._no_retirement_cycle(instruction, tick_kernel=False, tick_transport=False)
                    return False
            if instruction.instruction_class == InstructionClass.ENTROPY:
                opcode = EntropyOpcode(instruction.opcode)
                if opcode <= EntropyOpcode.HUFF_QUAD:
                    required = instruction.aux
                elif opcode == EntropyOpcode.UNARY:
                    required = instruction.immediate + 1
                elif opcode == EntropyOpcode.SIGN_RESTORE:
                    required = (
                        0
                        if self.registers[instruction.src0] == 0
                        else (self.registers[instruction.src1] & 0x1F) + 1
                    )
                else:
                    required = 1
                self.primitives._refill(required)
                if len(self.primitives.bits) < required and not self.primitives.eof:
                    self._no_retirement_cycle(instruction, tick_kernel=False, tick_transport=False)
                    return False
            try:
                if instruction.instruction_class == InstructionClass.KERNEL:
                    self.primitives.kernel_done = False
                result = self.primitives.execute(instruction, self.registers, self.entry)
            except PrimitiveFault as error:
                if instruction.instruction_class != InstructionClass.KERNEL or error.reason == 5:
                    raise SequencerTrap(error.reason, self.pc, instruction) from error
                result = PrimitiveResult(cycles=1, kernel_done=True)
                self.kernel_pending_fault = error
            self.primitive_cycles.append(result.cycles)
            if instruction.instruction_class == InstructionClass.KERNEL:
                self.primitives.kernel_done = False
                self.kernel_result = result
                self.kernel_pending_dst = instruction.dst
                self.kernel_cycles_remaining = max(result.cycles - 1, 0)
                if self.kernel_cycles_remaining == 0:
                    self._complete_kernel()
            else:
                for register, value in result.writes.items():
                    self._write(register, value)
                for _ in range(max(result.cycles - 1, 0)):
                    self._no_retirement_cycle(instruction)

        self._retire(instruction, predicate_true)
        if not terminal:
            if next_pc < self.entry.first_pc or next_pc > self.entry.last_pc:
                raise SequencerTrap(2, self.pc, instruction)
            self.pc = next_pc
        return terminal

    def run(self) -> dict[str, object]:
        fetch_required = True
        while True:
            if self.pc < self.entry.first_pc or self.pc > self.entry.last_pc:
                raise SequencerTrap(2, self.pc, Instruction(0, 0))
            instruction = self.instructions[self.pc]
            if fetch_required:
                for _ in range(self.fetch_no_retirement_cycles):
                    self._no_retirement_cycle(instruction)
                remaining_stalls = self.stall_cycles.get(self.pc, 0)
                while remaining_stalls > 0:
                    self._no_retirement_cycle(instruction)
                    remaining_stalls -= 1
                self.stall_cycles[self.pc] = 0
            retired_before = self.retired
            if self.step():
                break
            fetch_required = self.retired != retired_before
        return {
            "pc": self.pc,
            "retired": self.retired,
            "registers": self.registers,
            "trace": self.trace,
            "primitive_cycles": self.primitive_cycles,
            "transport": None
            if self.transport is None
            else {
                "input_used": self.transport.input_cursor,
                "output": bytes(self.transport.output).hex(),
                "frames": self.transport.frames,
                "result_code": self.transport.result_code,
                "result_stage": self.transport.result_stage,
                "result_detail": self.transport.result_detail,
                "events": self.transport.events,
            },
        }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("bundle", type=Path)
    parser.add_argument("--target", choices=APUMC_TARGETS, default="p3")
    parser.add_argument("--entry", type=int, choices=range(3), default=0)
    parser.add_argument("--timeout", type=int, default=0xFFFF)
    parser.add_argument("--input-exhausted", action="store_true")
    parser.add_argument("--input-ready", action="store_true")
    parser.add_argument("--output-ready", action="store_true")
    parser.add_argument("--kernel-done", action="store_true")
    parser.add_argument("--transport-done", action="store_true")
    args = parser.parse_args()
    instructions, entries, header = parse_apumc(args.bundle.read_bytes(), args.target)
    inputs = PredicateInputs(
        input_exhausted=args.input_exhausted,
        input_ready=args.input_ready,
        output_ready=args.output_ready,
        kernel_done=args.kernel_done,
        transport_done=args.transport_done,
    )
    print(
        json.dumps(
            Machine(
                instructions,
                entries[args.entry],
                inputs,
                args.timeout,
                target=args.target,
                primitives=PrimitiveBam() if args.target in ("p4", "p5") else None,
                transport=TransportModel() if args.target == "p5" else None,
            ).run(),
            sort_keys=True,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
