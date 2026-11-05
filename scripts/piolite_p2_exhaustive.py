#!/usr/bin/env python3
"""Generate one-tick P1 differential records for all 65536 PIO-lite instruction words."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

from piolite_isa import Instruction, PinWindow  # noqa: E402
from piolite_model import Machine, SMConfig  # noqa: E402

RECORD_WORDS = 23
LEGAL_COUNT = 22257
REJECTED_COUNT = 43279
TX_WORD = 0xD31A5A69


def config() -> SMConfig:
    return SMConfig(
        base=0,
        length=1,
        entry=0,
        wrap_bottom=0,
        wrap_top=0,
        divider=1,
        autopull=True,
        autopush=True,
        tx_right=True,
        rx_right=True,
        tx_bits=32,
        rx_bits=8,
        in_window=PinWindow(0, 32),
        out_window=PinWindow(0, 32),
        set_window=PinWindow(0, 8),
        claim_mask=0xFFFFFFFF,
        output_mask=0xFFFFFFFF,
        initial_value=0,
        initial_oe=0,
        initial_x=1,
        initial_y=0,
        test_pin_enable=True,
        test_pin=0,
        test_flag=0,
    )


def record(word: int) -> tuple[list[int], bool]:
    try:
        Instruction.decode(word)
        legal = True
    except ValueError:
        legal = False
    machine = Machine([config(), SMConfig(0, 1, 0, 0, 0)])
    machine.imem[0] = word
    machine.imem_valid = 1
    machine.flags = 1
    machine.pin_inputs = 1
    machine.write_tx(0, TX_WORD)
    machine.start(1)
    set_mask, clear_mask, _ = machine._execution_tick(0, machine.flags, machine.pin_inputs)
    sm = machine.sms[0]
    sm.tick_count = 1
    machine.flags = (machine.flags & ~clear_mask) | set_mask
    values = [
        word,
        int(legal),
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
        sm.events,
        sm.output_value,
        sm.output_oe,
        machine.flags,
        set_mask,
        clear_mask,
        int(not sm.tx.items),
        len(sm.rx.items),
        sm.rx.items[0] if sm.rx.items else 0,
    ]
    assert len(values) == RECORD_WORDS
    return values, legal


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    legal_count = 0
    digest = hashlib.sha256()
    with (args.output / "exhaustive.hex").open("w", encoding="ascii", newline="\n") as stream:
        for word in range(65536):
            values, legal = record(word)
            legal_count += int(legal)
            text = "".join(f"{value & 0xFFFFFFFF:08x}\n" for value in values)
            stream.write(text)
            digest.update(text.encode("ascii"))
    rejected_count = 65536 - legal_count
    if (legal_count, rejected_count) != (LEGAL_COUNT, REJECTED_COUNT):
        raise ValueError(f"unexpected ISA partition: {legal_count}/{rejected_count}")
    metadata = {
        "total": 65536,
        "legal": legal_count,
        "rejected": rejected_count,
        "record_words": RECORD_WORDS,
        "records": 65536,
        "sha256": digest.hexdigest(),
        "context": {
            "autopull": True, "autopush": True, "tx_bits": 32, "rx_bits": 8,
            "tx_word": TX_WORD, "initial_x": 1, "initial_y": 0, "flags": 1, "pins": 1,
        },
    }
    (args.output / "exhaustive.json").write_text(json.dumps(metadata, indent=2) + "\n")
    print(f"PIOLITE_P2_EXHAUSTIVE_VECTORS legal={legal_count} rejected={rejected_count} total=65536")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
