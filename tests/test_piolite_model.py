"""Independent cycle and state traces for the two-SM PIO-lite reference model."""

from __future__ import annotations

import sys
from pathlib import Path

import pytest


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

from piolite_asm import assemble, emit_c  # noqa: E402
from piolite_model import (  # noqa: E402
    EVENT_FIFO_FAIL,
    ControlError,
    FaultCode,
    Machine,
    SMConfig,
    SMState,
    StallKind,
)
from piolite_isa import InstructionAllocator, PinWindow  # noqa: E402


def word(opcode: int, operand: int = 0, delay: int = 0) -> int:
    return (opcode << 12) | (delay << 8) | operand


HALT = word(0, 0x20)
NOP = word(0)


def config(length: int, base: int = 0, **changes: object) -> SMConfig:
    values = {
        "base": base,
        "length": length,
        "entry": base,
        "wrap_bottom": base,
        "wrap_top": base + length - 1,
    }
    values.update(changes)
    return SMConfig(**values)


def machine(
    programs: list[tuple[int, ...]], configs: list[SMConfig] | None = None
) -> Machine:
    if configs is None:
        configs = []
        base = 0
        for program in programs:
            configs.append(config(len(program), base))
            base += len(program)
    if len(configs) == 1:
        configs.append(config(1))
    result = Machine(configs)
    for program, sm_config in zip(programs, configs[: len(programs)], strict=True):
        result.imem[sm_config.base : sm_config.base + len(program)] = program
        result.imem_valid |= ((1 << len(program)) - 1) << sm_config.base
    return result


def application_program(name: str):
    source = (ROOT / "app" / "asm" / "piolite" / f"{name}.piolite").read_text(encoding="utf-8")
    return assemble(source)


def assembled_program(name: str, body: str, top: str = "start"):
    return assemble(
        f""".program {name}
.entry start
.wrap_bottom start
.wrap_top {top}
.in 0, 0
.out 0, 0
.set 0, 0
.tx_bits 32, right, manual
.rx_bits 32, right, manual
.test none, 0
.packing 0, 0, 8
.clock_ticks 1, fixed
{body}
"""
    )


def application_machine(name: str, divider: int = 1) -> Machine:
    allocation = InstructionAllocator().load(application_program(name))
    sm_config = SMConfig.from_allocation(allocation, divider=divider)
    result = Machine((sm_config, config(1)))
    result.publish(allocation)
    return result


def mask(width: int) -> int:
    return 0xFFFFFFFF if width == 32 else (1 << width) - 1


def test_same_tick_dual_sm_commit_and_synchronized_start() -> None:
    configs = [config(2, 0, divider=3), config(2, 2, divider=3)]
    dut = machine([(word(3, 7), HALT), (word(3, 0x89), HALT)], configs)
    dut.start(0b11)
    for _ in range(2):
        assert dut.step().committed == (False, False)
    assert dut.step().committed == (True, True)
    assert (dut.sms[0].x, dut.sms[1].y) == (7, 9)
    assert (dut.sms[0].pc, dut.sms[1].pc) == (1, 3)
    for _ in range(2):
        assert dut.step().committed == (False, False)
    assert dut.step().committed == (True, True)
    assert tuple(sm.state for sm in dut.sms) == (SMState.HALTED, SMState.HALTED)


@pytest.mark.parametrize("divider", (1, 65535))
def test_divider_first_instruction_after_exact_pclk_edges(divider: int) -> None:
    dut = machine([(word(3, 1), HALT)], [config(2, divider=divider)])
    dut.start(1)
    for _ in range(divider - 1):
        dut.step()
        assert dut.sms[0].retired_count == 0
    dut.step()
    assert dut.sms[0].x == 1
    assert dut.sms[0].tick_count == 1


@pytest.mark.parametrize("delay", range(16))
def test_instruction_delay_consumes_exact_additional_ticks(delay: int) -> None:
    dut = machine([(word(0, 0, delay), HALT)])
    dut.start(1)
    dut.step()
    assert dut.sms[0].retired_count == 1
    assert dut.sms[0].delay_remaining == delay
    for _ in range(delay):
        assert not dut.step().committed[0]
        assert dut.sms[0].retired_count == 1
    dut.step()
    assert dut.sms[0].state == SMState.HALTED
    assert dut.sms[0].tick_count == delay + 2


def test_pause_resume_retains_phase_and_disable_preempts_instruction() -> None:
    dut = machine([(word(3, 7), HALT)], [config(2, divider=2)])
    dut.start(1)
    dut.step()
    assert dut.sms[0].divider_remaining == 1
    dut.step(pause_mask=1)
    assert dut.sms[0].state == SMState.PAUSED
    assert dut.sms[0].divider_remaining == 1
    dut.step()
    assert dut.sms[0].retired_count == 0
    dut.step(resume_mask=1)
    assert dut.sms[0].x == 7
    assert dut.sms[0].retired_count == 1
    dut.step(disable_mask=1)
    assert dut.sms[0].state == SMState.DISABLED
    assert dut.sms[0].retired_count == 1


@pytest.mark.parametrize("counter", ("X", "Y"))
@pytest.mark.parametrize("initial", (0, 1, 65535))
def test_decrement_then_branch_nonzero(counter: str, initial: int) -> None:
    condition = 3 if counter == "X" else 4
    initial_values = {"initial_x": initial} if counter == "X" else {"initial_y": initial}
    dut = machine(
        [(word(9, condition << 5), HALT)],
        [config(2, **initial_values)],
    )
    dut.start(1)
    dut.step()
    sm = dut.sms[0]
    assert (sm.x if counter == "X" else sm.y) == (65534 if initial == 65535 else 0)
    assert sm.pc == (0 if initial == 65535 else 1)


def test_count_zero_means_32_for_in_out_but_not_counters() -> None:
    dut = machine([(word(4, 0x60), word(7, 0x40), word(5, 0x80), HALT)])
    dut.write_tx(0, 0x89ABCDEF)
    dut.start(1)
    dut.step()
    assert dut.sms[0].isr_count == 32
    dut.step()
    assert dut.sms[0].osr_count == 32
    dut.step()
    assert dut.sms[0].osr_count == 0

    counters = machine([(word(3, 0), word(3, 0x80), HALT)], [config(3, initial_x=9, initial_y=9)])
    counters.start(1)
    counters.step()
    counters.step()
    assert (counters.sms[0].x, counters.sms[0].y) == (0, 0)


def test_move_narrows_counters_and_move_to_shifters_creates_32_valid_bits() -> None:
    program = (
        word(7, 0x40),
        word(6, 0x88),
        word(6, 0x10),
        word(6, 0xE8),
        HALT,
    )
    dut = machine([program])
    dut.write_tx(0, 0x12345678)
    dut.start(1)
    for _ in range(4):
        dut.step()
    sm = dut.sms[0]
    assert sm.x == 0x5678
    assert sm.y == 0xFFFF
    assert sm.isr == 0x5678
    assert sm.isr_count == 32


def test_wrap_false_branch_and_taken_branch_precedence() -> None:
    words = (word(9, (1 << 5) | 6), NOP, HALT, HALT)
    for initial, expected_pc in ((0, 6), (1, 5)):
        dut = machine([words], [config(4, 4, wrap_top=5, initial_x=initial)])
        dut.start(1)
        dut.step()
        assert dut.sms[0].pc == expected_pc
        if initial:
            dut.step()
            assert dut.sms[0].pc == 4


def test_out_of_region_branch_is_atomic_even_when_counter_would_change() -> None:
    dut = machine(
        [(word(9, (3 << 5) | 2), HALT)],
        [config(2, 4, initial_x=7)],
    )
    dut.start(1)
    dut.step()
    sm = dut.sms[0]
    assert sm.fault_code == FaultCode.PROGRAM_BOUNDS
    assert sm.fault_pc == 4
    assert sm.x == 7
    assert sm.state == SMState.CLOSING


def test_fallthrough_fault_and_final_halt_outside_wrap() -> None:
    falling = machine([(word(9, 1), NOP)], [config(2, wrap_top=0)])
    falling.start(1)
    falling.step()
    falling.step()
    assert falling.sms[0].fault_code == FaultCode.PROGRAM_BOUNDS
    assert falling.sms[0].fault_pc == 1

    halted = machine([(word(9, 1), HALT)], [config(2, wrap_top=0)])
    halted.start(1)
    halted.step()
    halted.step()
    assert halted.sms[0].state == SMState.HALTED
    assert halted.sms[0].pc == 1
    assert halted.sms[0].fault_code == FaultCode.NONE


def test_illegal_and_invalid_fetch_faults_latch_until_sm_reset() -> None:
    illegal = machine([(0xB000,)])
    illegal.start(1)
    illegal.step()
    assert illegal.sms[0].fault_code == FaultCode.ILLEGAL_INSTRUCTION
    assert illegal.sms[0].fault_pc == 0
    illegal.step()
    assert illegal.sms[0].fault_pc == 0
    illegal.sm_reset(1)
    assert illegal.sms[0].fault_code == FaultCode.NONE
    assert illegal.sms[0].state == SMState.DISABLED

    invalid = machine([(HALT,)])
    invalid.start(1)
    invalid.imem_valid &= ~1
    assert invalid.read_imem(0) == 0
    invalid.step()
    assert invalid.sms[0].fault_code == FaultCode.INVALID_FETCH


@pytest.mark.parametrize("direction", ("right", "left"))
@pytest.mark.parametrize("sample_count", (2, 4))
def test_independent_shift_and_partial_push_traces(direction: str, sample_count: int) -> None:
    samples = (0x12, 0x34, 0x56, 0x78)[:sample_count]
    instructions = tuple(word(4, 8) for _ in samples) + (word(7, 0xC0), HALT)
    dut = machine(
        [instructions],
        [
            config(
                len(instructions),
                rx_right=direction == "right",
                in_window=PinWindow(0, 8),
                claim_mask=0xFF,
            )
        ],
    )
    dut.start(1)
    for sample in samples:
        dut.pin_inputs = sample
        dut.step()
    if direction == "right":
        expected = sum(sample << (8 * index) for index, sample in enumerate(samples))
    elif sample_count == 2:
        expected = (samples[0] << 8) | samples[1]
    else:
        expected = int.from_bytes(bytes(samples), "big")
    dut.step()
    assert dut.sms[0].rx.items[0] == expected
    assert dut.sms[0].isr_count == 0


@pytest.mark.parametrize("width", (1, 8, 16, 31, 32))
def test_autopush_exact_width_and_zero_valued_valid_word(width: int) -> None:
    dut = machine(
        [(word(4, 0x60 | (width & 31)), HALT)],
        [config(2, rx_bits=width, autopush=True)],
    )
    dut.start(1)
    dut.step()
    assert tuple(dut.sms[0].rx.items) == (0,)
    assert dut.sms[0].isr_count == 0


def test_autopush_threshold_and_full_fifo_stall_before_sampling() -> None:
    dut = machine(
        [(word(4, 4), word(4, 4), HALT)],
        [config(3, rx_bits=8, autopush=True, in_window=PinWindow(0, 4), claim_mask=0xF)],
    )
    dut.start(1)
    dut.pin_inputs = 0xA
    dut.step()
    assert dut.sms[0].isr_count == 4
    assert not dut.sms[0].rx.items
    dut.pin_inputs = 0xB
    dut.step()
    assert tuple(dut.sms[0].rx.items) == (0xBA,)

    full = machine(
        [(word(4, 8), HALT)],
        [config(2, rx_bits=8, autopush=True, in_window=PinWindow(0, 8), claim_mask=0xFF)],
    )
    full.start(1)
    for value in range(8):
        full.sms[0].rx.push(value)
    full.pin_inputs = 0x5A
    full.step()
    assert full.sms[0].stall == StallKind.RX
    assert full.sms[0].isr_count == 0
    result = full.step(rx_reads=[0])
    assert result.rx_read_values[0] == 0
    assert full.sms[0].isr_count == 0
    assert len(full.sms[0].rx.items) == 7
    full.step()
    assert full.sms[0].rx.items[-1] == 0x5A


@pytest.mark.parametrize("direction", ("right", "left"))
@pytest.mark.parametrize("width", (1, 8, 16, 31, 32))
def test_out_left_right_chunk_and_remainder(direction: str, width: int) -> None:
    value = 0x89ABCDEF
    program = (word(7, 0x40), word(5, width & 31), HALT)
    dut = machine(
        [program],
        [
            config(
                3,
                tx_right=direction == "right",
                out_window=PinWindow(0, 32),
                claim_mask=0xFFFFFFFF,
                output_mask=0xFFFFFFFF,
            )
        ],
    )
    dut.write_tx(0, value)
    dut.start(1)
    dut.step()
    dut.step()
    sm = dut.sms[0]
    if direction == "right":
        chunk = value & mask(width)
        remainder = value >> width
    else:
        chunk = value >> (32 - width)
        remainder = value & mask(32 - width)
    assert sm.output_value == chunk
    assert sm.osr == remainder
    assert sm.osr_count == 32 - width


def test_empty_out_impossible_autopull_and_partial_osr_have_no_partial_effects() -> None:
    empty = machine([(word(5, 0x88),)], [config(1, autopull=False)])
    empty.write_tx(0, 0x1234)
    empty.start(1)
    empty.step()
    assert empty.sms[0].fault_code == FaultCode.SHIFT_BOUNDS
    assert tuple(empty.sms[0].tx.items) == (0x1234,)

    impossible = machine([(word(5, 0x90),)], [config(1, autopull=True, tx_bits=8)])
    impossible.write_tx(0, 0x1234)
    impossible.start(1)
    impossible.step()
    assert impossible.sms[0].fault_code == FaultCode.SHIFT_BOUNDS
    assert tuple(impossible.sms[0].tx.items) == (0x1234,)

    partial = machine(
        [(word(7, 0x40), word(5, 0x90), HALT)],
        [config(3, autopull=True, tx_bits=8)],
    )
    partial.write_tx(0, 0xA5)
    partial.write_tx(0, 0x5A)
    partial.start(1)
    partial.step()
    partial.step()
    assert partial.sms[0].fault_code == FaultCode.SHIFT_BOUNDS
    assert partial.sms[0].osr == 0xA5
    assert partial.sms[0].osr_count == 8
    assert tuple(partial.sms[0].tx.items) == (0x5A,)


def test_legal_autopull_stall_then_atomic_pull_and_out_clears_failure() -> None:
    dut = machine(
        [(word(7, 0), word(5, 8), HALT)],
        [
            config(
                3,
                autopull=True,
                tx_bits=8,
                out_window=PinWindow(0, 8),
                claim_mask=0xFF,
                output_mask=0xFF,
            )
        ],
    )
    dut.start(1)
    dut.step()
    assert dut.sms[0].pc == 1
    assert dut.sms[0].last_fifo_failed
    dut.step()
    assert dut.sms[0].pc == 1
    assert dut.sms[0].stall == StallKind.TX
    dut.write_tx(0, 0xA5)
    dut.step()
    assert dut.sms[0].output_value == 0xA5
    assert dut.sms[0].osr_count == 0
    assert not dut.sms[0].last_fifo_failed


def test_in_exceeding_shift_limit_faults_before_sampling_or_partial_join() -> None:
    automatic = machine([(word(4, 0x70),)], [config(1, rx_bits=8, autopush=True)])
    automatic.start(1)
    automatic.step()
    assert automatic.sms[0].fault_code == FaultCode.SHIFT_BOUNDS
    assert automatic.sms[0].isr_count == 0
    assert not automatic.sms[0].rx.items

    manual = machine([(word(4, 0x60), word(4, 0x61), HALT)])
    manual.start(1)
    manual.step()
    manual.step()
    assert manual.sms[0].fault_code == FaultCode.SHIFT_BOUNDS
    assert manual.sms[0].isr_count == 32


def test_manual_partial_push_preserves_zero_as_valid_data() -> None:
    dut = machine([(word(4, 0x68), word(7, 0xC0), HALT)])
    dut.start(1)
    dut.step()
    assert dut.sms[0].isr_count == 8
    dut.step()
    assert tuple(dut.sms[0].rx.items) == (0,)
    assert dut.sms[0].isr_count == 0


@pytest.mark.parametrize("blocking", (False, True))
def test_pull_blocking_stall_is_not_nonblocking_failure(blocking: bool) -> None:
    operand = 0x40 if blocking else 0
    dut = machine([(word(7, operand), HALT)])
    dut.start(1)
    dut.step()
    sm = dut.sms[0]
    if blocking:
        assert sm.pc == 0
        assert sm.stall == StallKind.TX
        assert sm.tx_stall_count == 1
        assert not sm.last_fifo_failed
    else:
        assert sm.pc == 1
        assert sm.last_fifo_failed
        assert sm.events & EVENT_FIFO_FAIL
        assert sm.osr_count == 0


@pytest.mark.parametrize("blocking", (False, True))
def test_push_full_preserves_isr_and_distinguishes_stall_from_failure(blocking: bool) -> None:
    operand = 0xC0 if blocking else 0x80
    dut = machine([(word(4, 0x68), word(7, operand), HALT)])
    dut.start(1)
    dut.step()
    original_isr = dut.sms[0].isr
    for value in range(8):
        dut.sms[0].rx.push(value)
    dut.step()
    sm = dut.sms[0]
    assert sm.isr == original_isr
    assert sm.isr_count == 8
    assert tuple(sm.rx.items) == tuple(range(8))
    if blocking:
        assert sm.pc == 1
        assert sm.stall == StallKind.RX
        assert not sm.last_fifo_failed
    else:
        assert sm.pc == 2
        assert sm.last_fifo_failed


def test_tx_pre_edge_full_and_empty_rules() -> None:
    full = machine([(word(7, 0x40), HALT)])
    for value in range(8):
        full.write_tx(0, value)
    full.start(1)
    result = full.step(tx_writes={0: 99})
    assert result.tx_write_accepted == {0: False}
    assert full.sms[0].osr == 0
    assert tuple(full.sms[0].tx.items) == tuple(range(1, 8))

    empty = machine([(word(7, 0x40), HALT)])
    empty.start(1)
    result = empty.step(tx_writes={0: 0x55})
    assert result.tx_write_accepted == {0: True}
    assert empty.sms[0].pc == 0
    empty.step()
    assert empty.sms[0].osr == 0x55


def test_shared_flag_set_wins_clear_and_wait_observes_pre_edge_flags() -> None:
    racing = machine(
        [(word(10, 0x80), HALT), (word(10, 0), HALT)],
        [config(2, 0), config(2, 2)],
    )
    racing.start(0b11)
    racing.step()
    assert racing.flags == 1

    waiting = machine(
        [(word(10, 0xA0), HALT), (word(8, 0xC2), HALT)],
        [config(2, 0), config(2, 2)],
    )
    waiting.start(0b11)
    waiting.step()
    assert waiting.flags == 2
    assert waiting.sms[1].pc == 2
    assert waiting.sms[1].stall == StallKind.FLAG
    waiting.step()
    assert waiting.sms[1].pc == 3
    assert waiting.flags == 2


def test_wait_can_stall_forever_without_architectural_timeout() -> None:
    dut = machine([(word(8, 0x4A), HALT)], [config(2, claim_mask=1 << 5)])
    dut.start(1)
    for _ in range(100):
        dut.step()
    sm = dut.sms[0]
    assert sm.state == SMState.RUNNING
    assert sm.pc == 0
    assert sm.tick_count == 100
    assert sm.fault_code == FaultCode.NONE
    dut.pin_inputs = 1 << 5
    dut.step()
    assert dut.sms[0].pc == 1


def test_set_window_masks_high_bits_and_retains_other_pins() -> None:
    dut = machine(
        [(word(1, 0xFF), word(2, 0x05), HALT)],
        [
            config(
                3,
                set_window=PinWindow(4, 2),
                claim_mask=0x30,
                output_mask=0x30,
            )
        ],
    )
    dut.start(1)
    dut.step()
    assert dut.sms[0].output_value == 0x30
    dut.step()
    assert dut.sms[0].output_value == 0x30
    assert dut.sms[0].output_oe == 0x10


def test_wait_and_test_pin_authorization_faults() -> None:
    waiting = machine([(word(8, 0x4A),)])
    waiting.start(1)
    waiting.step()
    assert waiting.sms[0].fault_code == FaultCode.PIN_AUTHORIZATION

    testing = machine(
        [(word(9, (5 << 5) | 1), HALT)],
        [config(2, claim_mask=1 << 5, test_pin=5, test_pin_enable=False)],
    )
    testing.start(1)
    testing.step()
    assert testing.sms[0].fault_code == FaultCode.PIN_AUTHORIZATION


@pytest.mark.parametrize("sent", (0xA5, 0x00, 0xFF), ids=lambda value: f"{value:02X}")
def test_uart_rx_application_samples_independent_8n1_stimulus(sent: int) -> None:
    dut = application_machine("uart_rx")
    dut.start(1)
    sample_edges = []
    stop_edges = []
    for edge in range(78):
        if edge < 8:
            dut.pin_inputs = 0
        elif edge < 72:
            dut.pin_inputs = ((sent >> ((edge - 8) // 8)) & 1) << 1
        else:
            dut.pin_inputs = 1 << 1
        before_pc = dut.sms[0].pc
        result = dut.step()
        if result.committed[0] and 2 <= before_pc <= 9:
            sample_edges.append(edge)
        if result.committed[0] and before_pc == 10:
            stop_edges.append(edge)

    assert sample_edges == [12, 20, 28, 36, 44, 52, 60, 68]
    assert stop_edges == [76]
    assert dut.read_rx(0) == sent
    assert dut.sms[0].fault_code == FaultCode.NONE


@pytest.mark.parametrize(("high_ticks", "low_ticks"), ((3, 5), (8, 2)))
def test_pulse_generate_application_has_independent_exact_phase_durations(
    high_ticks: int, low_ticks: int
) -> None:
    dut = application_machine("pulse_generate")
    dut.write_tx(0, high_ticks)
    dut.write_tx(0, low_ticks)
    dut.start(1)
    transitions = []
    previous_level = 0
    for edge in range(6 + high_ticks + low_ticks + 2):
        dut.step()
        level = (dut.sms[0].output_value >> 2) & 1
        if level != previous_level:
            transitions.append((edge, level))
            previous_level = level

    assert transitions == [
        (6, 1),
        (6 + high_ticks, 0),
        (6 + high_ticks + low_ticks, 1),
    ]
    assert dut.sms[0].state == SMState.HALTED
    assert dut.sms[0].fault_code == FaultCode.NONE


@pytest.mark.parametrize("divider", (1, 3))
def test_logic_capture_application_uniform_cadence_and_exact_counts(divider: int) -> None:
    program = application_program("logic_capture")
    sample_count = program.packing.rx_items
    item_bits = program.packing.item_bits
    lanes_per_word = 32 // item_bits
    expected_word_count = (sample_count * item_bits) // 32
    assert sample_count * item_bits == expected_word_count * 32
    dut = application_machine("logic_capture", divider=divider)
    dut.start(1)
    sample_edges = []
    captured_words = []
    for edge in range((4 + 2 * sample_count + 1) * divider):
        dut.pin_inputs = ((edge // divider) & 0xFF) << 8
        before_pc = dut.sms[0].pc
        before_instruction = dut.imem[before_pc]
        result = dut.step(rx_reads=[0])
        if result.committed[0] and before_instruction >> 12 == 4:
            sample_edges.append(edge)
        captured = result.rx_read_values[0]
        if captured is not None:
            captured_words.append(captured)
        if dut.sms[0].state == SMState.HALTED:
            break

    assert sample_edges == [
        divider - 1 + divider * (4 + 2 * index) for index in range(sample_count)
    ]
    expected_words = []
    for word_index in range(expected_word_count):
        expected = 0
        for lane in range(lanes_per_word):
            sample_index = lanes_per_word * word_index + lane
            expected |= ((4 + 2 * sample_index) & 0xFF) << (item_bits * lane)
        expected_words.append(expected)
    assert captured_words == expected_words
    assert len(captured_words) == expected_word_count
    assert dut.sms[0].isr_count == 0
    assert dut.sms[0].isr == 0
    assert dut.sms[0].state == SMState.HALTED
    assert dut.sms[0].fault_code == FaultCode.NONE


@pytest.mark.parametrize("used", (False, True), ids=("selected-unused", "selected-used"))
def test_selected_test_pin_enable_follows_actual_branch_use(used: bool) -> None:
    body = "start: BRANCH TEST_PIN_HIGH, start\nhalt: CTRL HALT" if used else "start: CTRL HALT"
    top = "halt" if used else "start"
    source = f""".program selected_pin
.entry start
.wrap_bottom start
.wrap_top {top}
.in 0, 0
.out 0, 0
.set 0, 0
.tx_bits 32, right, manual
.rx_bits 32, right, manual
.test 5, 1
.packing 0, 0, 8
.clock_ticks 1, fixed
{body}
"""
    program = assemble(source)
    generated = emit_c(program)
    expected_claim = (1 << 5) if used else 0
    assert program.claim_mask == expected_claim
    assert f".test_pin_enable = {int(used)}u" in generated
    assert f".claim_mask = 0x{expected_claim:08X}u" in generated

    allocation = InstructionAllocator().load(program)
    sm_config = SMConfig.from_allocation(allocation)
    assert sm_config.test_pin_enable is used
    assert sm_config.claim_mask == expected_claim
    dut = Machine((sm_config, config(1)))
    dut.publish(allocation)
    dut.start(1)
    for _ in range(2):
        dut.step()
    assert dut.sms[0].state == SMState.HALTED
    assert dut.sms[0].fault_code == FaultCode.NONE


def test_false_condition_branch_still_checks_out_of_region_target() -> None:
    dut = machine(
        [(word(9, (1 << 5) | 2), HALT)],
        [config(2, 4, initial_x=1)],
    )
    dut.start(1)
    dut.step()
    assert dut.sms[0].fault_code == FaultCode.PROGRAM_BOUNDS
    assert dut.sms[0].fault_pc == 4
    assert dut.sms[0].x == 1


def test_start_preserves_prefill_and_sticky_history_and_loads_initial_state() -> None:
    dut = machine(
        [(NOP, HALT)],
        [
            config(
                2,
                claim_mask=1 << 2,
                output_mask=1 << 2,
                initial_value=1 << 2,
                initial_oe=1 << 2,
                initial_x=0x1234,
                initial_y=0xABCD,
            )
        ],
    )
    dut.sms[0].tx.push(0xDEADBEEF)
    dut.sms[0].events = EVENT_FIFO_FAIL
    dut.sms[0].last_fifo_failed = True
    dut.start(1)
    sm = dut.sms[0]
    assert tuple(sm.tx.items) == (0xDEADBEEF,)
    assert sm.events == EVENT_FIFO_FAIL
    assert not sm.last_fifo_failed
    assert (sm.x, sm.y) == (0x1234, 0xABCD)
    assert sm.output_value == 1 << 2
    assert sm.output_oe == 1 << 2


def test_start_rejects_nonempty_rx_and_partially_valid_imem() -> None:
    nonempty_rx = machine([(HALT,)])
    nonempty_rx.sms[0].rx.push(0)
    with pytest.raises(ControlError, match="empty RX FIFO"):
        nonempty_rx.start(1)
    assert nonempty_rx.sms[0].state == SMState.DISABLED
    assert tuple(nonempty_rx.sms[0].rx.items) == (0,)

    partial_imem = machine([(NOP, HALT)])
    partial_imem.imem_valid &= ~(1 << 1)
    with pytest.raises(ControlError, match="every configured instruction word"):
        partial_imem.start(1)
    assert partial_imem.sms[0].state == SMState.DISABLED


def test_automatic_push_clears_last_fifo_failure() -> None:
    dut = machine(
        [(word(7, 0), word(4, 0x68), HALT)],
        [config(3, rx_bits=8, autopush=True)],
    )
    dut.start(1)
    dut.step()
    assert dut.sms[0].last_fifo_failed
    dut.step()
    assert tuple(dut.sms[0].rx.items) == (0,)
    assert not dut.sms[0].last_fifo_failed


def test_pull_zeroes_unused_high_bits() -> None:
    dut = machine([(word(7, 0x40), HALT)], [config(2, tx_bits=8)])
    dut.write_tx(0, 0xFFFFFF5A)
    dut.start(1)
    dut.step()
    assert dut.sms[0].osr == 0x5A
    assert dut.sms[0].osr_count == 8


def test_pause_acceptance_during_stalled_wait_with_large_divider() -> None:
    dut = machine(
        [(word(8, 0x4A), HALT)],
        [config(2, divider=65535, claim_mask=1 << 5)],
    )
    dut.start(1)
    for _ in range(65535):
        dut.step()
    assert dut.sms[0].stall == StallKind.PIN
    assert dut.sms[0].retired_count == 0
    phase = dut.sms[0].divider_remaining
    ticks = dut.sms[0].tick_count
    dut.step(pause_mask=1)
    assert dut.sms[0].state == SMState.PAUSED
    assert dut.sms[0].divider_remaining == phase
    assert dut.sms[0].tick_count == ticks
    dut.pin_inputs = 1 << 5
    dut.step()
    assert dut.sms[0].retired_count == 0
    dut.step(resume_mask=1)
    assert dut.sms[0].state == SMState.RUNNING
    assert dut.sms[0].retired_count == 0
    assert dut.sms[0].divider_remaining == phase - 1


@pytest.mark.parametrize("operation", ("IN", "OUT"))
def test_runtime_pin_window_authorization_faults(operation: str) -> None:
    if operation == "IN":
        dut = machine(
            [(word(4, 8),)],
            [config(1, in_window=PinWindow(0, 4), claim_mask=0xF)],
        )
    else:
        dut = machine(
            [(word(7, 0x40), word(5, 8), HALT)],
            [config(3, out_window=PinWindow(0, 4), claim_mask=0xF, output_mask=0xF)],
        )
        dut.write_tx(0, 0xA5)
    dut.start(1)
    if operation == "OUT":
        dut.step()
    dut.step()
    assert dut.sms[0].fault_code == FaultCode.PIN_AUTHORIZATION
    assert dut.sms[0].output_value == 0
    if operation == "IN":
        assert dut.sms[0].isr_count == 0
    else:
        assert dut.sms[0].osr == 0xA5


@pytest.mark.parametrize("destination", ("PINS", "DIRECTIONS"))
def test_narrow_out_preserves_unrelated_output_bits(destination: str) -> None:
    destination_code = 0 if destination == "PINS" else 1
    dut = machine(
        [(word(7, 0x40), word(5, (destination_code << 5) | 1), HALT)],
        [
            config(
                3,
                out_window=PinWindow(4, 4),
                claim_mask=0xF0,
                output_mask=0xF0,
                initial_value=0xC0,
                initial_oe=0xC0,
            )
        ],
    )
    dut.write_tx(0, 1)
    dut.start(1)
    dut.step()
    dut.step()
    if destination == "PINS":
        assert dut.sms[0].output_value == 0xD0
        assert dut.sms[0].output_oe == 0xC0
    else:
        assert dut.sms[0].output_value == 0xC0
        assert dut.sms[0].output_oe == 0xD0


def test_publish_while_running_is_rejected_without_imem_state_change() -> None:
    allocator = InstructionAllocator()
    old = allocator.load(assembled_program("old", "start: CTRL NOP\nlast: CTRL HALT", "last"), 0)
    new = allocator.load(assembled_program("new", "start: CTRL HALT"), 2)
    dut = Machine((config(2), config(1)))
    dut.publish(old)
    dut.start(1)
    before = (tuple(dut.imem), dut.imem_valid, dut.sms[0].state)

    with pytest.raises(ControlError, match="all SMs DISABLED"):
        dut.publish(new)
    assert (tuple(dut.imem), dut.imem_valid, dut.sms[0].state) == before
    with pytest.raises(ControlError, match="all SMs DISABLED"):
        dut.unpublish(old)
    assert (tuple(dut.imem), dut.imem_valid, dut.sms[0].state) == before


def test_scoped_unpublish_and_smaller_replacement_clear_vacated_validity() -> None:
    allocator = InstructionAllocator()
    old = allocator.load(assembled_program("old", "start: CTRL NOP\nlast: CTRL HALT", "last"), 0)
    keeper = allocator.load(assembled_program("keeper", "start: SET_COUNT X, 1"), 4)
    new_program = assembled_program("new", "start: CTRL HALT")
    overlapping = InstructionAllocator().load(new_program, 0)
    dut = Machine((config(2), config(1)))
    dut.publish(old)
    dut.publish(keeper)
    before = (tuple(dut.imem), dut.imem_valid)
    with pytest.raises(ControlError, match="invalidated before replacement"):
        dut.publish(overlapping)
    assert (tuple(dut.imem), dut.imem_valid) == before

    dut.unpublish(old)
    allocator.unload(old)
    new = allocator.load(new_program, 0)
    assert dut.imem_valid == 1 << 4
    assert dut.read_imem(0) == 0
    assert dut.read_imem(1) == 0
    assert dut.read_imem(4) == 0x3001
    dut.publish(new)
    assert dut.imem_valid == (1 << 0) | (1 << 4)
    assert dut.read_imem(0) == 0x0020
    assert dut.read_imem(1) == 0
    assert dut.read_imem(4) == 0x3001

    dut.sms[0].state = SMState.RUNNING
    dut.sms[0].pc = 1
    dut.step()
    assert dut.sms[0].fault_code == FaultCode.INVALID_FETCH
    assert dut.sms[0].fault_pc == 1


def test_invalidate_imem_while_running_is_rejected_atomically() -> None:
    allocation = InstructionAllocator().load(
        assembled_program("running", "start: CTRL NOP\nlast: CTRL HALT", "last"), 0
    )
    dut = Machine((config(2), config(1)))
    dut.publish(allocation)
    dut.start(1)
    before = (tuple(dut.imem), dut.imem_valid)
    with pytest.raises(ControlError, match="all SMs DISABLED"):
        dut.invalidate_imem()
    assert (tuple(dut.imem), dut.imem_valid) == before
    assert dut.sms[0].state == SMState.RUNNING


def test_unpublish_rejects_partial_and_different_content_images() -> None:
    allocator = InstructionAllocator()
    old = allocator.load(assembled_program("old", "start: CTRL NOP\nlast: CTRL HALT", "last"), 0)
    foreign_short = InstructionAllocator().load(assembled_program("short", "start: CTRL HALT"), 0)
    foreign_content = InstructionAllocator().load(
        assembled_program("content", "start: SET_COUNT X, 1\nlast: CTRL HALT", "last"), 0
    )
    dut = Machine((config(2), config(1)))
    dut.publish(old)
    before = (tuple(dut.imem), dut.imem_valid)
    for foreign in (foreign_short, foreign_content):
        with pytest.raises(ControlError, match="unknown or foreign"):
            dut.unpublish(foreign)
        assert (tuple(dut.imem), dut.imem_valid) == before


def test_shared_image_stays_valid_until_last_publication_reference() -> None:
    allocator = InstructionAllocator()
    program = assembled_program("shared", "start: CTRL NOP\nlast: CTRL HALT", "last")
    first = allocator.load(program, 0)
    second = allocator.load(program)
    assert first is second
    dut = Machine((config(2), config(1)))
    dut.publish(first)
    dut.publish(second)
    assert dut.imem_valid == 0b11
    dut.unpublish(first)
    assert dut.imem_valid == 0b11
    dut.unpublish(second)
    assert dut.imem_valid == 0
    with pytest.raises(ControlError, match="unknown or foreign"):
        dut.unpublish(second)
    assert dut.imem_valid == 0


@pytest.mark.parametrize("opcode", (1, 2), ids=("SET_PIN", "SET_DIR"))
def test_set_with_disabled_window_faults_before_effects(opcode: int) -> None:
    dut = machine([(word(opcode, 0xFF), HALT)])
    dut.start(1)
    dut.step()
    assert dut.sms[0].fault_code == FaultCode.PIN_AUTHORIZATION
    assert dut.sms[0].output_value == 0
    assert dut.sms[0].output_oe == 0
    assert dut.sms[0].retired_count == 0


def test_start_disabled_sm_while_other_sm_remains_running() -> None:
    dut = machine(
        [(word(3, 1), HALT), (word(3, 0x82), HALT)],
        [config(2, 0), config(2, 2)],
    )
    dut.start(0b01)
    dut.step()
    first_pc = dut.sms[0].pc
    first_ticks = dut.sms[0].tick_count
    dut.start(0b10)
    assert dut.sms[0].state == SMState.RUNNING
    assert dut.sms[0].pc == first_pc
    assert dut.sms[0].tick_count == first_ticks
    assert dut.sms[1].state == SMState.RUNNING
    dut.step()
    assert dut.sms[0].state == SMState.HALTED
    assert dut.sms[1].y == 2


@pytest.mark.parametrize("field", ("initial_value", "initial_oe"))
def test_start_rejects_initial_output_on_unclaimed_or_nonoutput_pin(field: str) -> None:
    changes = {field: 1}
    if field == "initial_oe":
        changes["claim_mask"] = 1
    dut = machine([(HALT,)], [config(1, **changes)])
    with pytest.raises(ControlError, match="non-output"):
        dut.start(1)
    assert dut.sms[0].state == SMState.DISABLED
    assert dut.sms[0].output_value == 0
    assert dut.sms[0].output_oe == 0


@pytest.mark.parametrize("flag_index", range(4))
def test_wait_flag_pre_edge_and_nonclearing_for_every_flag(flag_index: int) -> None:
    dut = machine(
        [
            (word(10, 0x80 | (flag_index << 5)), HALT),
            (word(8, 0xC0 | (flag_index << 1)), HALT),
        ],
        [config(2, 0), config(2, 2)],
    )
    dut.start(0b11)
    dut.step()
    assert dut.flags == 1 << flag_index
    assert dut.sms[1].pc == 2
    assert dut.sms[1].stall == StallKind.FLAG
    dut.step()
    assert dut.sms[1].pc == 3
    assert dut.flags == 1 << flag_index


def test_delay_15_taken_branch_still_wins_over_wrap() -> None:
    dut = machine([(word(9, 1, 15), HALT)], [config(2, wrap_top=0)])
    dut.start(1)
    dut.step()
    assert dut.sms[0].pc == 1
    assert dut.sms[0].delay_remaining == 15
    for _ in range(15):
        dut.step()
        assert dut.sms[0].pc == 1
        assert dut.sms[0].retired_count == 1
    dut.step()
    assert dut.sms[0].state == SMState.HALTED
