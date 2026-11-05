"""Cycle-stepped host reference model for the frozen two-SM PIO-lite ISA."""

from __future__ import annotations

import copy
from collections import deque
from dataclasses import dataclass, field
from enum import IntEnum
from typing import Iterable, Mapping

from piolite_isa import (
    BRANCH_CONDITIONS,
    CTRL_COMMANDS,
    FIFO_DEPTH,
    FIFO_MODES,
    FIFO_OPERATIONS,
    FLAG_ACTIONS,
    IN_SOURCES,
    INSTRUCTION_WORDS,
    OUT_DESTINATIONS,
    SM_COUNT,
    WAIT_SOURCES,
    Allocation,
    Instruction,
    Opcode,
    PinWindow,
    encoded_count,
    test_pin_is_used,
)


class SMState(IntEnum):
    DISABLED = 0
    RUNNING = 1
    PAUSED = 2
    HALTED = 3
    CLOSING = 4


class FaultCode(IntEnum):
    NONE = 0
    ILLEGAL_INSTRUCTION = 1
    INVALID_FETCH = 2
    PROGRAM_BOUNDS = 3
    SHIFT_BOUNDS = 4
    PIN_AUTHORIZATION = 5


class StallKind(IntEnum):
    NONE = 0
    PIN = 1
    FLAG = 2
    TX = 3
    RX = 4


EVENT_HALT = 1 << 0
EVENT_ABORT = 1 << 1
EVENT_FAULT = 1 << 2
EVENT_TX_STALL = 1 << 3
EVENT_RX_STALL = 1 << 4
EVENT_FIFO_FAIL = 1 << 5


class FIFOError(ValueError):
    """An external FIFO access has no pre-edge space or data."""


class ControlError(ValueError):
    """A lifecycle command is invalid for the selected SM state."""


@dataclass
class FIFO:
    items: deque[int] = field(default_factory=deque)

    def __post_init__(self) -> None:
        if len(self.items) > FIFO_DEPTH or any(not 0 <= word <= 0xFFFFFFFF for word in self.items):
            raise FIFOError("FIFO contents exceed the 8x32 contract")

    def push(self, word: int) -> None:
        if not isinstance(word, int) or not 0 <= word <= 0xFFFFFFFF:
            raise FIFOError("FIFO word must be an unsigned 32-bit value")
        if len(self.items) >= FIFO_DEPTH:
            raise FIFOError("FIFO is full")
        self.items.append(word)

    def pop(self) -> int:
        if not self.items:
            raise FIFOError("FIFO is empty")
        return self.items.popleft()


@dataclass(frozen=True)
class SMConfig:
    base: int
    length: int
    entry: int
    wrap_bottom: int
    wrap_top: int
    divider: int = 1
    autopull: bool = False
    autopush: bool = False
    tx_right: bool = True
    rx_right: bool = True
    tx_bits: int = 32
    rx_bits: int = 32
    in_window: PinWindow = PinWindow(0, 0)
    out_window: PinWindow = PinWindow(0, 0)
    set_window: PinWindow = PinWindow(0, 0)
    claim_mask: int = 0
    output_mask: int = 0
    initial_value: int = 0
    initial_oe: int = 0
    initial_x: int = 0
    initial_y: int = 0
    test_pin_enable: bool = False
    test_pin: int | None = None
    test_flag: int = 0

    @classmethod
    def from_allocation(
        cls,
        allocation: Allocation,
        *,
        divider: int = 1,
        initial_value: int = 0,
        initial_oe: int = 0,
        initial_x: int = 0,
        initial_y: int = 0,
        claim_mask: int | None = None,
        output_mask: int | None = None,
        test_pin_enable: bool | None = None,
    ) -> SMConfig:
        image = allocation.image
        program = image.program
        return cls(
            base=image.base,
            length=len(image.words),
            entry=image.entry,
            wrap_bottom=image.wrap_bottom,
            wrap_top=image.wrap_top,
            divider=divider,
            autopull=program.tx.mode == "auto",
            autopush=program.rx.mode == "auto",
            tx_right=program.tx.direction == "right",
            rx_right=program.rx.direction == "right",
            tx_bits=program.tx.bits,
            rx_bits=program.rx.bits,
            in_window=program.in_window,
            out_window=program.out_window,
            set_window=program.set_window,
            claim_mask=program.claim_mask if claim_mask is None else claim_mask,
            output_mask=(program.out_window.mask() | program.set_window.mask())
            if output_mask is None
            else output_mask,
            initial_value=initial_value,
            initial_oe=initial_oe,
            initial_x=initial_x,
            initial_y=initial_y,
            test_pin_enable=(
                test_pin_is_used(program.instructions) if test_pin_enable is None else test_pin_enable
            ),
            test_pin=program.test.pin,
            test_flag=program.test.flag,
        )

    def validate(self) -> None:
        if not 0 <= self.base < INSTRUCTION_WORDS or not 1 <= self.length <= INSTRUCTION_WORDS:
            raise ControlError("program base/length is invalid")
        if self.base + self.length > INSTRUCTION_WORDS:
            raise ControlError("program region exceeds instruction storage")
        for name, value in (
            ("entry", self.entry),
            ("wrap_bottom", self.wrap_bottom),
            ("wrap_top", self.wrap_top),
        ):
            if not self.base <= value < self.base + self.length:
                raise ControlError(f"{name} is outside the program region")
        if self.wrap_bottom > self.wrap_top:
            raise ControlError("wrap_bottom exceeds wrap_top")
        if not 1 <= self.divider <= 65535:
            raise ControlError("divider must be in 1..65535")
        if not 1 <= self.tx_bits <= 32 or not 1 <= self.rx_bits <= 32:
            raise ControlError("shift limits must be in 1..32")
        self.in_window.validate("IN")
        self.out_window.validate("OUT")
        self.set_window.validate("SET", maximum_width=8)
        for name, value in (
            ("claim_mask", self.claim_mask),
            ("output_mask", self.output_mask),
            ("initial_value", self.initial_value),
            ("initial_oe", self.initial_oe),
        ):
            if not isinstance(value, int) or not 0 <= value <= 0xFFFFFFFF:
                raise ControlError(f"{name} must be an unsigned 32-bit value")
        if self.output_mask & ~self.claim_mask:
            raise ControlError("output pins are not claimed")
        windows = self.in_window.mask() | self.out_window.mask() | self.set_window.mask()
        if windows & ~self.claim_mask:
            raise ControlError("an enabled pin window is not claimed")
        if (self.out_window.mask() | self.set_window.mask()) & ~self.output_mask:
            raise ControlError("OUT/SET windows are not authorized outputs")
        if self.initial_value & ~self.output_mask or self.initial_oe & ~self.output_mask:
            raise ControlError("initial pin state names a non-output pin")
        if not 0 <= self.initial_x <= 0xFFFF or not 0 <= self.initial_y <= 0xFFFF:
            raise ControlError("initial X/Y values must fit 16 bits")
        if self.test_pin_enable:
            if self.test_pin is None or not 0 <= self.test_pin <= 31:
                raise ControlError("enabled test pin must be in 0..31")
            if not self.claim_mask & (1 << self.test_pin):
                raise ControlError("test pin is not claimed")
        if not 0 <= self.test_flag <= 3:
            raise ControlError("test flag must be in 0..3")


@dataclass
class SM:
    config: SMConfig
    state: SMState = SMState.DISABLED
    pc: int = 0
    isr: int = 0
    osr: int = 0
    isr_count: int = 0
    osr_count: int = 0
    x: int = 0
    y: int = 0
    tx: FIFO = field(default_factory=FIFO)
    rx: FIFO = field(default_factory=FIFO)
    last_fifo_failed: bool = False
    fault_code: FaultCode = FaultCode.NONE
    fault_pc: int = 0
    stall: StallKind = StallKind.NONE
    divider_remaining: int = 1
    delay_remaining: int = 0
    tick_count: int = 0
    tx_stall_count: int = 0
    rx_stall_count: int = 0
    retired_count: int = 0
    events: int = 0
    output_value: int = 0
    output_oe: int = 0


@dataclass(frozen=True)
class EdgeResult:
    committed: tuple[bool, bool]
    tx_write_accepted: dict[int, bool]
    rx_read_values: dict[int, int | None]


class _ExecutionFault(Exception):
    def __init__(self, code: FaultCode):
        super().__init__(code.name)
        self.code = code


class _ExecutionStall(Exception):
    def __init__(self, kind: StallKind):
        super().__init__(kind.name)
        self.kind = kind


class Machine:
    """Two independent SMs stepping on explicit PCLK edges, without a watchdog."""

    def __init__(self, configs: Iterable[SMConfig] | None = None) -> None:
        if configs is None:
            configs = (
                SMConfig(0, 1, 0, 0, 0),
                SMConfig(0, 1, 0, 0, 0),
            )
        config_tuple = tuple(configs)
        if len(config_tuple) != SM_COUNT:
            raise ControlError("Tiny PIO-lite has exactly two SM configurations")
        self.sms = [SM(config) for config in config_tuple]
        self.imem = [0] * INSTRUCTION_WORDS
        self.imem_valid = 0
        self._published_allocations: dict[int, Allocation] = {}
        self._published_references: dict[int, int] = {}
        self.flags = 0
        self.pin_inputs = 0
        self.pclk_edges = 0

    def publish(self, allocation: Allocation) -> None:
        if any(sm.state != SMState.DISABLED for sm in self.sms):
            raise ControlError("IMEM publication requires all SMs DISABLED")
        image = allocation.image
        staged = [Instruction.decode(word).encode() for word in image.words]
        if image.base + len(staged) > INSTRUCTION_WORDS:
            raise ControlError("published image exceeds instruction storage")
        key = id(allocation)
        if key in self._published_allocations:
            if self._published_allocations[key] is not allocation:
                raise ControlError("foreign published allocation identity")
            self._published_references[key] += 1
            return
        region_mask = ((1 << len(staged)) - 1) << image.base
        if self.imem_valid & region_mask:
            raise ControlError("published instruction slots must be invalidated before replacement")
        self.imem[image.base : image.base + len(staged)] = staged
        self.imem_valid |= region_mask
        self._published_allocations[key] = allocation
        self._published_references[key] = 1

    def unpublish(self, allocation: Allocation) -> None:
        if any(sm.state != SMState.DISABLED for sm in self.sms):
            raise ControlError("IMEM invalidation requires all SMs DISABLED")
        key = id(allocation)
        canonical = self._published_allocations.get(key)
        if canonical is None or canonical is not allocation:
            raise ControlError("unknown or foreign published allocation")
        if self._published_references[key] > 1:
            self._published_references[key] -= 1
            return
        image = canonical.image
        region_mask = ((1 << len(image.words)) - 1) << image.base
        del self._published_references[key]
        del self._published_allocations[key]
        self.imem_valid &= ~region_mask

    def invalidate_imem(self) -> None:
        if any(sm.state != SMState.DISABLED for sm in self.sms):
            raise ControlError("IMEM invalidation requires all SMs DISABLED")
        self.imem = [0] * INSTRUCTION_WORDS
        self.imem_valid = 0
        self._published_allocations.clear()
        self._published_references.clear()

    def read_imem(self, index: int) -> int:
        if not 0 <= index < INSTRUCTION_WORDS:
            raise ControlError("instruction index must be in 0..31")
        return self.imem[index] if self.imem_valid & (1 << index) else 0

    def write_tx(self, sm_index: int, word: int) -> None:
        self._sm(sm_index).tx.push(word)

    def read_rx(self, sm_index: int) -> int:
        return self._sm(sm_index).rx.pop()

    def start(self, mask: int) -> None:
        selected = self._validate_mask(mask)
        if not selected:
            return
        for index in selected:
            sm = self.sms[index]
            if sm.state != SMState.DISABLED or sm.fault_code != FaultCode.NONE:
                raise ControlError("START requires a clean DISABLED SM")
            sm.config.validate()
            if sm.rx.items:
                raise ControlError("START requires an empty RX FIFO")
            region = ((1 << sm.config.length) - 1) << sm.config.base
            if self.imem_valid & region != region:
                raise ControlError("START requires every configured instruction word to be valid")
        for first, second in ((0, 1),):
            if self.sms[first].config.output_mask & self.sms[second].config.output_mask:
                raise ControlError("SM output masks must be disjoint")
        for index in selected:
            sm = self.sms[index]
            config = sm.config
            sm.pc = config.entry
            sm.isr = sm.osr = 0
            sm.isr_count = sm.osr_count = 0
            sm.x = config.initial_x
            sm.y = config.initial_y
            sm.last_fifo_failed = False
            sm.stall = StallKind.NONE
            sm.divider_remaining = config.divider
            sm.delay_remaining = 0
            sm.tick_count = 0
            sm.tx_stall_count = sm.rx_stall_count = sm.retired_count = 0
            sm.output_value = config.initial_value
            sm.output_oe = config.initial_oe
            sm.state = SMState.RUNNING

    def sm_reset(self, mask: int) -> None:
        selected = self._validate_mask(mask)
        for index in selected:
            if self.sms[index].state not in (SMState.DISABLED, SMState.CLOSING):
                raise ControlError("SM_RESET requires DISABLED or CLOSING")
        for index in selected:
            sm = self.sms[index]
            config = sm.config
            self.sms[index] = SM(config=config, pc=config.entry, divider_remaining=config.divider)

    def step(
        self,
        *,
        pause_mask: int = 0,
        resume_mask: int = 0,
        disable_mask: int = 0,
        flag_set: int = 0,
        flag_clear: int = 0,
        tx_writes: Mapping[int, int] | None = None,
        rx_reads: Iterable[int] = (),
    ) -> EdgeResult:
        pauses = set(self._validate_mask(pause_mask))
        resumes = set(self._validate_mask(resume_mask))
        disables = set(self._validate_mask(disable_mask))
        if (pauses & resumes) or (pauses & disables) or (resumes & disables):
            raise ControlError("conflicting lifecycle commands for one SM")
        if not 0 <= flag_set <= 0xF or not 0 <= flag_clear <= 0xF:
            raise ControlError("flag masks must fit four bits")
        tx_writes = {} if tx_writes is None else dict(tx_writes)
        rx_indices = tuple(rx_reads)
        if any(index not in (0, 1) for index in (*tx_writes, *rx_indices)):
            raise ControlError("FIFO command names an unimplemented SM")
        if len(set(rx_indices)) != len(rx_indices):
            raise ControlError("only one external RX read is allowed per SM per edge")
        for word in tx_writes.values():
            if not isinstance(word, int) or not 0 <= word <= 0xFFFFFFFF:
                raise FIFOError("FIFO word must be an unsigned 32-bit value")
        for index in pauses:
            if self.sms[index].state != SMState.RUNNING:
                raise ControlError("PAUSE requires RUNNING")
        for index in resumes:
            if self.sms[index].state != SMState.PAUSED:
                raise ControlError("RESUME requires PAUSED")
        for index in disables:
            if self.sms[index].state == SMState.CLOSING:
                raise ControlError("DISABLE cannot escape CLOSING")

        flags_before = self.flags
        pins_before = self.pin_inputs
        tx_had_space = tuple(len(sm.tx.items) < FIFO_DEPTH for sm in self.sms)
        rx_had_data = tuple(bool(sm.rx.items) for sm in self.sms)

        for index in disables:
            sm = self.sms[index]
            sm.state = SMState.DISABLED
            sm.output_oe = 0
            sm.stall = StallKind.NONE
        for index in pauses:
            self.sms[index].state = SMState.PAUSED
            self.sms[index].stall = StallKind.NONE
        for index in resumes:
            self.sms[index].state = SMState.RUNNING

        committed = [False, False]
        instruction_flag_set = 0
        instruction_flag_clear = 0
        for index, sm in enumerate(tuple(self.sms)):
            if sm.state != SMState.RUNNING:
                continue
            sm.divider_remaining -= 1
            if sm.divider_remaining != 0:
                continue
            sm.divider_remaining = sm.config.divider
            sm.tick_count = _saturating_increment(sm.tick_count)
            set_mask, clear_mask, did_commit = self._execution_tick(index, flags_before, pins_before)
            committed[index] = did_commit
            instruction_flag_set |= set_mask
            instruction_flag_clear |= clear_mask

        self.flags = (flags_before & ~(flag_clear | instruction_flag_clear)) | flag_set | instruction_flag_set
        tx_accepted: dict[int, bool] = {}
        for index, word in tx_writes.items():
            accepted = tx_had_space[index]
            tx_accepted[index] = accepted
            if accepted:
                self.sms[index].tx.push(word)
        rx_values: dict[int, int | None] = {}
        for index in rx_indices:
            if rx_had_data[index]:
                rx_values[index] = self.sms[index].rx.pop()
            else:
                rx_values[index] = None
        self.pclk_edges += 1
        return EdgeResult(tuple(committed), tx_accepted, rx_values)

    def _execution_tick(self, index: int, flags_before: int, pins_before: int) -> tuple[int, int, bool]:
        sm = self.sms[index]
        if sm.delay_remaining:
            sm.delay_remaining -= 1
            sm.stall = StallKind.NONE
            return 0, 0, False
        if not sm.config.base <= sm.pc < sm.config.base + sm.config.length:
            self._fault(sm, FaultCode.PROGRAM_BOUNDS)
            return 0, 0, False
        if not self.imem_valid & (1 << sm.pc):
            self._fault(sm, FaultCode.INVALID_FETCH)
            return 0, 0, False
        try:
            instruction = Instruction.decode(self.imem[sm.pc])
        except ValueError:
            self._fault(sm, FaultCode.ILLEGAL_INSTRUCTION)
            return 0, 0, False

        candidate = copy.deepcopy(sm)
        try:
            set_mask, clear_mask = self._apply(candidate, instruction, flags_before, pins_before)
            try:
                next_pc, halted = self._successor(candidate, instruction, flags_before, pins_before)
            except _ExecutionFault:
                raise
        except _ExecutionStall as stall:
            sm.stall = stall.kind
            if stall.kind == StallKind.TX:
                sm.events |= EVENT_TX_STALL
                sm.tx_stall_count = _saturating_increment(sm.tx_stall_count)
            elif stall.kind == StallKind.RX:
                sm.events |= EVENT_RX_STALL
                sm.rx_stall_count = _saturating_increment(sm.rx_stall_count)
            return 0, 0, False
        except _ExecutionFault as primary:
            try:
                self._successor(candidate, instruction, flags_before, pins_before)
            except _ExecutionFault as successor_fault:
                self._fault(sm, FaultCode(min(primary.code, successor_fault.code)))
            else:
                self._fault(sm, primary.code)
            return 0, 0, False
        except _ExecutionFault:
            raise

        candidate.delay_remaining = instruction.delay
        if halted:
            candidate.state = SMState.HALTED
            candidate.events |= EVENT_HALT
        else:
            candidate.pc = next_pc
        candidate.stall = StallKind.NONE
        candidate.retired_count = _saturating_increment(candidate.retired_count)
        self.sms[index] = candidate
        return set_mask, clear_mask, True

    def _successor(
        self, sm: SM, instruction: Instruction, flags: int, pins: int
    ) -> tuple[int, bool]:
        operand = instruction.operand
        if instruction.opcode == Opcode.CTRL and operand >> 5 == CTRL_COMMANDS["HALT"]:
            return sm.pc, True
        if instruction.opcode == Opcode.BRANCH:
            target = operand & 0x1F
            if not sm.config.base <= target < sm.config.base + sm.config.length:
                raise _ExecutionFault(FaultCode.PROGRAM_BOUNDS)
            condition = operand >> 5
            if condition == BRANCH_CONDITIONS["ALWAYS"]:
                taken = True
            elif condition == BRANCH_CONDITIONS["X_ZERO"]:
                taken = sm.x == 0
            elif condition == BRANCH_CONDITIONS["Y_ZERO"]:
                taken = sm.y == 0
            elif condition == BRANCH_CONDITIONS["DEC_X_NONZERO"]:
                taken = sm.x != 0
            elif condition == BRANCH_CONDITIONS["DEC_Y_NONZERO"]:
                taken = sm.y != 0
            elif condition == BRANCH_CONDITIONS["TEST_PIN_HIGH"]:
                if not sm.config.test_pin_enable or sm.config.test_pin is None:
                    raise _ExecutionFault(FaultCode.PIN_AUTHORIZATION)
                if not sm.config.claim_mask & (1 << sm.config.test_pin):
                    raise _ExecutionFault(FaultCode.PIN_AUTHORIZATION)
                taken = bool(pins & (1 << sm.config.test_pin))
            elif condition == BRANCH_CONDITIONS["FIFO_FAILED"]:
                taken = sm.last_fifo_failed
            elif condition == BRANCH_CONDITIONS["TEST_FLAG_SET"]:
                taken = bool(flags & (1 << sm.config.test_flag))
            else:
                raise _ExecutionFault(FaultCode.ILLEGAL_INSTRUCTION)
            if taken:
                return target, False
        next_pc = sm.config.wrap_bottom if sm.pc == sm.config.wrap_top else sm.pc + 1
        if not sm.config.base <= next_pc < sm.config.base + sm.config.length:
            raise _ExecutionFault(FaultCode.PROGRAM_BOUNDS)
        return next_pc, False

    def _apply(
        self, sm: SM, instruction: Instruction, flags: int, pins: int
    ) -> tuple[int, int]:
        opcode = instruction.opcode
        operand = instruction.operand
        if opcode == Opcode.CTRL:
            command = operand >> 5
            if command == CTRL_COMMANDS["CLEAR_ISR"]:
                sm.isr = sm.isr_count = 0
            elif command == CTRL_COMMANDS["CLEAR_OSR"]:
                sm.osr = sm.osr_count = 0
            return 0, 0
        if opcode in (Opcode.SET_PIN, Opcode.SET_DIR):
            window = sm.config.set_window
            if window.width == 0:
                raise _ExecutionFault(FaultCode.PIN_AUTHORIZATION)
            self._require_output(sm, window)
            value = (operand & 0xFF) & ((1 << window.width) - 1) if window.width else 0
            aligned = value << window.base
            if opcode == Opcode.SET_PIN:
                sm.output_value = (sm.output_value & ~window.mask()) | aligned
            else:
                sm.output_oe = (sm.output_oe & ~window.mask()) | aligned
            return 0, 0
        if opcode == Opcode.SET_COUNT:
            if operand & 0x80:
                sm.y = operand & 0x7F
            else:
                sm.x = operand & 0x7F
            return 0, 0
        if opcode == Opcode.IN:
            self._apply_in(sm, operand, pins)
            return 0, 0
        if opcode == Opcode.OUT:
            self._apply_out(sm, operand)
            return 0, 0
        if opcode == Opcode.MOVE:
            source = (operand >> 3) & 0x7
            values = (sm.isr, sm.osr, sm.x, sm.y, 0, 0xFFFFFFFF)
            value = values[source] & 0xFFFFFFFF
            destination = operand >> 6
            if destination == 0:
                sm.isr = value
                sm.isr_count = 32
            elif destination == 1:
                sm.osr = value
                sm.osr_count = 32
            elif destination == 2:
                sm.x = value & 0xFFFF
            else:
                sm.y = value & 0xFFFF
            return 0, 0
        if opcode == Opcode.FIFO:
            self._apply_fifo(sm, operand)
            return 0, 0
        if opcode == Opcode.WAIT:
            source = (operand >> 7) & 1
            level = (operand >> 6) & 1
            index = (operand >> 1) & 0x1F
            if source == WAIT_SOURCES["PIN"]:
                if not sm.config.claim_mask & (1 << index):
                    raise _ExecutionFault(FaultCode.PIN_AUTHORIZATION)
                observed = int(bool(pins & (1 << index)))
                if observed != level:
                    raise _ExecutionStall(StallKind.PIN)
            else:
                observed = int(bool(flags & (1 << index)))
                if observed != level:
                    raise _ExecutionStall(StallKind.FLAG)
            return 0, 0
        if opcode == Opcode.BRANCH:
            condition = operand >> 5
            if condition == BRANCH_CONDITIONS["DEC_X_NONZERO"] and sm.x:
                sm.x -= 1
            elif condition == BRANCH_CONDITIONS["DEC_Y_NONZERO"] and sm.y:
                sm.y -= 1
            return 0, 0
        if opcode == Opcode.FLAG:
            index = (operand >> 5) & 0x3
            if operand >> 7 == FLAG_ACTIONS["SET"]:
                return 1 << index, 0
            return 0, 1 << index
        raise _ExecutionFault(FaultCode.ILLEGAL_INSTRUCTION)

    def _apply_fifo(self, sm: SM, operand: int) -> None:
        blocking = ((operand >> 6) & 1) == FIFO_MODES["BLOCKING"]
        if ((operand >> 7) & 1) == FIFO_OPERATIONS["PULL"]:
            if not sm.tx.items:
                if blocking:
                    raise _ExecutionStall(StallKind.TX)
                self._fifo_failed(sm)
                return
            word = sm.tx.pop()
            sm.osr = word & _mask(sm.config.tx_bits)
            sm.osr_count = sm.config.tx_bits
            sm.last_fifo_failed = False
            return

        if sm.isr_count == 0:
            raise _ExecutionFault(FaultCode.SHIFT_BOUNDS)
        word = _normalized_isr(sm)
        if len(sm.rx.items) >= FIFO_DEPTH:
            if blocking:
                raise _ExecutionStall(StallKind.RX)
            self._fifo_failed(sm)
            return
        sm.rx.push(word)
        sm.isr = sm.isr_count = 0
        sm.last_fifo_failed = False

    def _apply_out(self, sm: SM, operand: int) -> None:
        count = encoded_count(operand & 0x1F)
        if sm.osr_count == 0:
            if not sm.config.autopull or count > sm.config.tx_bits:
                raise _ExecutionFault(FaultCode.SHIFT_BOUNDS)
            if not sm.tx.items:
                raise _ExecutionStall(StallKind.TX)
            sm.osr = sm.tx.pop() & _mask(sm.config.tx_bits)
            sm.osr_count = sm.config.tx_bits
            sm.last_fifo_failed = False
        elif sm.osr_count < count:
            raise _ExecutionFault(FaultCode.SHIFT_BOUNDS)

        if sm.config.tx_right:
            chunk = sm.osr & _mask(count)
            sm.osr = (sm.osr >> count) & _mask(sm.osr_count - count)
        else:
            shift = sm.osr_count - count
            chunk = (sm.osr >> shift) & _mask(count)
            sm.osr &= _mask(shift)
        sm.osr_count -= count

        destination = operand >> 5
        if destination in (OUT_DESTINATIONS["PINS"], OUT_DESTINATIONS["DIRECTIONS"]):
            window = sm.config.out_window
            if count > window.width:
                raise _ExecutionFault(FaultCode.PIN_AUTHORIZATION)
            self._require_output(sm, window)
            aligned = chunk << window.base
            update_mask = _mask(count) << window.base
            if destination == OUT_DESTINATIONS["PINS"]:
                sm.output_value = (sm.output_value & ~update_mask) | aligned
            else:
                sm.output_oe = (sm.output_oe & ~update_mask) | aligned
        elif destination == OUT_DESTINATIONS["X"]:
            sm.x = chunk & 0xFFFF
        elif destination == OUT_DESTINATIONS["Y"]:
            sm.y = chunk & 0xFFFF

    def _apply_in(self, sm: SM, operand: int, pins: int) -> None:
        count = encoded_count(operand & 0x1F)
        resulting_count = sm.isr_count + count
        limit = sm.config.rx_bits if sm.config.autopush else 32
        if resulting_count > limit:
            raise _ExecutionFault(FaultCode.SHIFT_BOUNDS)
        if sm.config.autopush and resulting_count == sm.config.rx_bits and len(sm.rx.items) >= FIFO_DEPTH:
            raise _ExecutionStall(StallKind.RX)

        source = operand >> 5
        if source == IN_SOURCES["PINS"]:
            window = sm.config.in_window
            if count > window.width or window.mask() & ~sm.config.claim_mask:
                raise _ExecutionFault(FaultCode.PIN_AUTHORIZATION)
            value = (pins >> window.base) & _mask(count)
        elif source == IN_SOURCES["X"]:
            value = sm.x & _mask(count)
        elif source == IN_SOURCES["Y"]:
            value = sm.y & _mask(count)
        else:
            value = 0

        if sm.config.rx_right:
            sm.isr = ((sm.isr >> count) | (value << (32 - count))) & 0xFFFFFFFF
        else:
            sm.isr = ((sm.isr << count) | value) & 0xFFFFFFFF
        sm.isr_count = resulting_count
        if sm.config.autopush and resulting_count == sm.config.rx_bits:
            sm.rx.push(_normalized_isr(sm))
            sm.isr = sm.isr_count = 0
            sm.last_fifo_failed = False

    @staticmethod
    def _require_output(sm: SM, window: PinWindow) -> None:
        if window.mask() & ~sm.config.claim_mask or window.mask() & ~sm.config.output_mask:
            raise _ExecutionFault(FaultCode.PIN_AUTHORIZATION)

    @staticmethod
    def _fifo_failed(sm: SM) -> None:
        sm.last_fifo_failed = True
        sm.events |= EVENT_FIFO_FAIL

    @staticmethod
    def _fault(sm: SM, code: FaultCode) -> None:
        if sm.fault_code == FaultCode.NONE:
            sm.fault_code = code
            sm.fault_pc = sm.pc
        sm.state = SMState.CLOSING
        sm.output_oe = 0
        sm.stall = StallKind.NONE
        sm.events |= EVENT_FAULT

    def _sm(self, index: int) -> SM:
        if index not in (0, 1):
            raise ControlError("SM index must be zero or one")
        return self.sms[index]

    @staticmethod
    def _validate_mask(mask: int) -> tuple[int, ...]:
        if not isinstance(mask, int) or not 0 <= mask <= 0x3:
            raise ControlError("Tiny SM mask must contain only bits 0 and 1")
        return tuple(index for index in range(SM_COUNT) if mask & (1 << index))


def _normalized_isr(sm: SM) -> int:
    if sm.isr_count == 0:
        raise _ExecutionFault(FaultCode.SHIFT_BOUNDS)
    if sm.config.rx_right:
        return (sm.isr >> (32 - sm.isr_count)) & _mask(sm.isr_count)
    return sm.isr & _mask(sm.isr_count)


def _mask(width: int) -> int:
    return 0xFFFFFFFF if width == 32 else (1 << width) - 1


def _saturating_increment(value: int) -> int:
    return min(0xFFFFFFFF, value + 1)
