#!/usr/bin/env python3
"""Generate fixed-seed P1-model differential records for standalone PIO-lite P2 RTL."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

from piolite_model import Machine, SMConfig  # noqa: E402
from piolite_isa import PinWindow  # noqa: E402

SEED = 0x50494F32
RECORD_WORDS = 78


def instruction(opcode: int, operand: int = 0, delay: int = 0) -> int:
    return (opcode << 12) | (delay << 8) | operand


def pack_window(window: PinWindow) -> int:
    return (window.width << 8) | window.base


def generate() -> tuple[list[int], list[dict]]:
    records: list[int] = []
    metadata: list[dict] = []

    def add(
        name: str,
        words: list[int],
        steps: int,
        *,
        divider: int = 1,
        wrap_bottom: int = 0,
        wrap_top: int | None = None,
        autopull: bool = False,
        autopush: bool = False,
        tx_right: bool = True,
        rx_right: bool = True,
        tx_bits: int = 32,
        rx_bits: int = 32,
        in_window: PinWindow = PinWindow(0, 0),
        out_window: PinWindow = PinWindow(0, 0),
        set_window: PinWindow = PinWindow(0, 0),
        claim_mask: int = 0,
        output_mask: int = 0,
        initial_value: int = 0,
        initial_oe: int = 0,
        initial_x: int = 0,
        initial_y: int = 0,
        tx_words: list[int] | None = None,
        pin_inputs: int = 0,
        image_count: int | None = None,
    ) -> None:
        cfg = SMConfig(
            base=0,
            length=len(words),
            entry=0,
            wrap_bottom=wrap_bottom,
            wrap_top=len(words) - 1 if wrap_top is None else wrap_top,
            divider=divider,
            autopull=autopull,
            autopush=autopush,
            tx_right=tx_right,
            rx_right=rx_right,
            tx_bits=tx_bits,
            rx_bits=rx_bits,
            in_window=in_window,
            out_window=out_window,
            set_window=set_window,
            claim_mask=claim_mask,
            output_mask=output_mask,
            initial_value=initial_value,
            initial_oe=initial_oe,
            initial_x=initial_x,
            initial_y=initial_y,
        )
        machine = Machine([cfg, SMConfig(0, 1, 0, 0, 0)])
        for index, word in enumerate(words):
            machine.imem[index] = word
            machine.imem_valid |= 1 << index
        for word in tx_words or []:
            machine.write_tx(0, word)
        machine.pin_inputs = pin_inputs
        machine.start(1)
        if image_count is not None and image_count < len(words):
            machine.imem_valid = (1 << image_count) - 1
        for _ in range(steps):
            machine.step()
        sm = machine.sms[0]
        options = (
            int(autopull)
            | (int(autopush) << 1)
            | (int(tx_right) << 2)
            | (int(rx_right) << 3)
        )
        rx_words = list(sm.rx.items) + [0] * (8 - len(sm.rx.items))
        record = [
            divider,
            (len(words) << 8),
            (wrap_top << 8) | wrap_bottom if wrap_top is not None else ((len(words) - 1) << 8),
            options,
            pack_window(in_window),
            pack_window(out_window),
            pack_window(set_window),
            claim_mask,
            output_mask,
            initial_value,
            initial_oe,
            (initial_y << 16) | initial_x,
            (rx_bits << 8) | tx_bits,
            0,
            (tx_words or [0])[0],
            (tx_words or [0, 0])[1] if len(tx_words or []) > 1 else 0,
            len(tx_words or []),
            pin_inputs,
            steps,
            (int(sm.last_fifo_failed) << 8) | (int(sm.stall) << 4) | int(sm.state),
            (sm.fault_pc << 8) | int(sm.fault_code),
            sm.pc,
            sm.isr,
            sm.osr,
            (sm.y << 16) | sm.x,
            (sm.osr_count << 8) | sm.isr_count,
            sm.tick_count,
            sm.tx_stall_count,
            sm.rx_stall_count,
            sm.retired_count,
            (sm.delay_remaining << 16) | sm.divider_remaining,
            len(sm.tx.items),
            len(sm.rx.items),
            sm.events,
            machine.flags,
            sm.output_value,
            sm.output_oe,
            len(words) if image_count is None else image_count,
        ]
        assert len(record) == 37 + 1
        record += words + [0] * (32 - len(words)) + rx_words
        assert len(record) == RECORD_WORDS
        records.extend(record)
        metadata.append(
            {
                "name": name,
                "index": len(metadata),
                "steps": steps,
                "expected": {
                    "status": record[19],
                    "fault": record[20],
                    "pc": record[21],
                    "isr": record[22],
                    "osr": record[23],
                    "xy": record[24],
                    "tick_count": record[26],
                    "retired_count": record[29],
                    "rx_words": list(sm.rx.items),
                },
            }
        )

    halt = instruction(0, 0x20)
    add("nop_halt", [instruction(0), halt], 2)
    add("delay_15", [instruction(0, delay=15), halt], 17)
    add(
        "counters_and_move",
        [instruction(3, 127), instruction(3, 0x85), instruction(6, 0x10), instruction(6, 0x48), halt],
        5,
    )
    add(
        "pull_out_right",
        [instruction(7, 0x40), instruction(5, 4), halt],
        3,
        out_window=PinWindow(4, 4),
        claim_mask=0xF0,
        output_mask=0xF0,
        tx_words=[0x12345678],
    )
    add(
        "in_right_autopush",
        [instruction(4, 8), instruction(4, 0x28), instruction(4, 0x68), instruction(4, 0x48), halt],
        5,
        autopush=True,
        rx_bits=8,
        in_window=PinWindow(0, 8),
        claim_mask=0xFF,
        initial_x=0xA5,
        initial_y=0x5A,
        pin_inputs=0x3C,
    )
    add(
        "decrement_loop",
        [instruction(3, 2), instruction(0), instruction(9, 0x61), halt],
        6,
    )
    add(
        "nonblocking_fifo_failure",
        [instruction(7, 0), instruction(9, 0xC3), instruction(0), halt],
        3,
    )
    add("reserved_opcode", [0xB000], 1)
    add("taken_branch_then_halt", [instruction(9, 1), halt], 2, wrap_top=0)
    add("false_branch_target_bounds", [instruction(9, 0x22), halt], 1, initial_x=1)
    add("empty_manual_out", [instruction(5, 0x80)], 1)
    add(
        "partial_push_right",
        [instruction(4, 0x28), instruction(7, 0x80), halt],
        3,
        initial_x=0xAB,
    )
    add("move_ones_zero", [instruction(6, 0xA8), instruction(6, 0xE0), halt], 3)
    add("div_3_delay", [instruction(0, delay=1), halt], 9, divider=3)
    add("div_65535", [halt], 65535, divider=65535)
    add(
        "left_pack_tail",
        [instruction(4, 0x28), instruction(4, 0x48), instruction(7, 0x80), halt],
        4,
        rx_right=False,
        initial_x=0x12,
        initial_y=0x34,
    )
    add(
        "left_out_chunks",
        [instruction(7, 0x40), instruction(5, 0x48), instruction(5, 0x68), halt],
        4,
        tx_right=False,
        tx_bits=16,
        tx_words=[0x1234],
    )
    add(
        "zero_is_valid_fifo_data",
        [instruction(4, 0x68), instruction(7, 0x80), halt],
        3,
    )
    add("decrement_zero_saturates", [instruction(3, 0), instruction(9, 0x62), halt], 3)
    add("invalid_fetch", [instruction(0), halt], 2, image_count=1)
    add("reserved_fifo_bits", [instruction(7, 1)], 1)
    add(
        "partial_osr_underrun_atomic",
        [instruction(7, 0x40), instruction(5, 0x50), halt],
        2,
        tx_bits=8,
        tx_words=[0xA5],
    )
    add(
        "autopull_impossible_width_no_dequeue",
        [instruction(5, 0x50)],
        1,
        autopull=True,
        tx_bits=8,
        tx_words=[0x5A],
    )
    for name, count, value in (("right_1", 1, 1), ("right_16", 16, 0xBEEF),
                               ("right_31", 31, 0x7FFF)):
        add(
            f"pack_{name}",
            [instruction(4, 0x20 | (count & 0x1F)), instruction(7, 0x80), halt],
            3,
            initial_x=value,
        )
    add(
        "pack_left_31",
        [instruction(4, 0x3F), instruction(7, 0x80), halt],
        3,
        rx_right=False,
        initial_x=0x7FFF,
    )
    add(
        "out_discard_count_32",
        [instruction(7, 0x40), instruction(5, 0x80), halt],
        3,
        tx_words=[0xDEADBEEF],
    )
    add(
        "in_zero_count_32",
        [instruction(4, 0x60), instruction(7, 0x80), halt],
        3,
    )
    return [len(metadata), *records], metadata


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    words, metadata = generate()
    args.output.mkdir(parents=True, exist_ok=True)
    (args.output / "vectors.hex").write_text("".join(f"{word & 0xFFFFFFFF:08x}\n" for word in words))
    (args.output / "vectors.json").write_text(
        json.dumps({"seed": SEED, "record_words": RECORD_WORDS, "cases": metadata}, indent=2) + "\n"
    )
    print(f"PIOLITE_P2_VECTORS cases={len(metadata)} seed=0x{SEED:08X}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
