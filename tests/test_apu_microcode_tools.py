"""APU-P3 assembler, APUMC, and reference-interpreter coverage."""

from __future__ import annotations

import struct
import subprocess
import sys
from pathlib import Path

import pytest


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

from apu_interpreter import Machine, PredicateInputs, SequencerTrap  # noqa: E402
from apu_isa import (  # noqa: E402
    APUMC_ABI,
    APUMC_MAGIC,
    ControlOpcode,
    Entry,
    Instruction,
    InstructionClass,
    ScalarOpcode,
    crc32_iso_hdlc,
    control_flow_report,
    parse_apumc,
    validate_p3_instruction,
)
from apu_mcasm import assemble  # noqa: E402


PROGRAM = """
.build_id 0x1122334455667788
.entry 0 wav wav done 16 64
.entry 1 mp3 mp3 done 16 64
.entry 2 flac flac done 16 64
wav:
  movi r0, 2
  movi r1, 3
  add r2, r0, r1
  cmp r2, r1
  movi r3, 0x55 if=ne
  jump_fwd done
mp3:
  movi r4, 0xffffffff
  sat r5, r4, 40
  jump_fwd done
flac:
  movi r6, 2
  loop_setup 0, r6
body:
  add r7, r7, r0
  loop_back 0, body
done:
  end
"""


def test_apumc_bundle_layout_crc_and_determinism() -> None:
    first = assemble(PROGRAM)
    second = assemble(PROGRAM)
    assert first.bundle == second.bundle
    header = struct.unpack_from("<16I", first.bundle)
    assert header[0] == APUMC_MAGIC
    assert header[1] == APUMC_ABI
    assert header[2] == len(first.bundle)
    assert header[4] == 192
    assert header[7] == 64
    assert header[8] == 3
    assert header[9] == header[10] == 0
    assert header[11] == crc32_iso_hdlc(first.bundle[64:])
    assert header[12:14] == (0x55667788, 0x11223344)
    assert first.bundle[160:192] == bytes(32)
    instructions, entries, parsed_header = parse_apumc(first.bundle)
    assert instructions == first.instructions
    assert entries == first.entries
    assert parsed_header == header


def test_apumc_parser_rejects_reserved_descriptor_and_padding_bits() -> None:
    for byte_offset in (64 + 3, 160):
        bundle = bytearray(assemble(PROGRAM).bundle)
        bundle[byte_offset] ^= 0x80
        struct.pack_into("<I", bundle, 44, crc32_iso_hdlc(bundle[64:]))
        with pytest.raises(ValueError):
            parse_apumc(bundle)


@pytest.mark.parametrize(
    "instruction",
    [
        Instruction(0, 0, immediate=1),
        Instruction(0, ControlOpcode.RET, predicate=1),
        Instruction(0, ControlOpcode.JUMP_FWD, immediate=0),
        Instruction(0, ControlOpcode.WAIT, aux=0),
        Instruction(1, 14),
        Instruction(1, ScalarOpcode.SAT, aux=7),
        Instruction(2, 0),
        Instruction(7, 0),
    ],
)
def test_p3_rejects_reserved_and_deferred_encodings(instruction: Instruction) -> None:
    with pytest.raises(ValueError):
        validate_p3_instruction(instruction)


def test_reference_interpreter_scalar_predicate_and_terminal_retention() -> None:
    assembly = assemble(PROGRAM)
    result = Machine(assembly.instructions, assembly.entries[0]).run()
    assert result["registers"][2] == 5
    assert result["registers"][3] == 0x55
    assert result["retired"] == 7
    assert result["pc"] == assembly.symbols["done"]


def test_reference_interpreter_call_loop_and_traps() -> None:
    source = """
.entry 0 start start end 4 32
.entry 1 start start end 4 32
.entry 2 start start end 4 32
start:
  movi r0, 3
  loop_setup 0, r0
body:
  add r1, r1, r0
  loop_back 0, body
  call_fwd sub
  end
sub:
  movi r2, 9
  ret
end:
  end
"""
    assembly = assemble(source)
    result = Machine(assembly.instructions, assembly.entries[0]).run()
    assert result["registers"][1] == 9
    assert result["registers"][2] == 9

    trapping = [Instruction(InstructionClass.CONTROL, ControlOpcode.TRAP, immediate=0xA5)]
    entry = assembly.entries[0].__class__(0, 0, 0, 0, 1, 1)
    with pytest.raises(SequencerTrap) as caught:
        Machine(trapping, entry).run()
    assert caught.value.reason == 10
    assert caught.value.detail == 0xA5


def test_reference_interpreter_external_predicates_and_watchdog() -> None:
    instructions = [
        Instruction(1, ScalarOpcode.MOVI, predicate=8, dst=0, immediate=0x55),
        Instruction(0, ControlOpcode.END),
    ]
    entry = Entry(0, 0, 0, 1, 1, 4)
    false_result = Machine(instructions, entry, fetch_no_retirement_cycles=0).run()
    true_result = Machine(
        instructions,
        entry,
        predicate_inputs=PredicateInputs(input_ready=True),
        fetch_no_retirement_cycles=0,
    ).run()
    assert false_result["registers"][0] == 0
    assert true_result["registers"][0] == 0x55

    with pytest.raises(SequencerTrap) as caught:
        Machine(instructions, entry, timeout=1).run()
    assert caught.value.reason == 7
    assert caught.value.pc == 0


def test_assembler_rejects_host_execution_inputs_and_bad_contracts() -> None:
    with pytest.raises(ValueError, match="exactly three"):
        assemble("start:\n  end\n")
    with pytest.raises(ValueError, match="unknown mnemonic"):
        assemble(
            ".entry 0 x x x 1 1\n.entry 1 x x x 1 1\n.entry 2 x x x 1 1\n"
            "x:\n  rv32_addi r0, r0, 1\n"
        )


@pytest.mark.parametrize(
    "body, message",
    [
        ("start:\n  jump_fwd start\n", "forward branch delta"),
        ("start:\n  ret\n", "empty stack"),
        ("start:\n  movi r0, 2\n  loop_back 0, start\n  end\n", "no setup"),
        ("start:\n  nop\n", "outside its program range"),
    ],
)
def test_assembler_rejects_invalid_control_flow(body: str, message: str) -> None:
    source = (
        ".entry 0 start start last 4 32\n"
        ".entry 1 start start last 4 32\n"
        ".entry 2 start start last 4 32\n"
        f"{body}"
        "last:\n  nop\n"
    )
    with pytest.raises(ValueError, match=message):
        assemble(source)


def test_path_sensitive_call_proof_rejects_predicated_empty_return() -> None:
    instructions = [
        Instruction(0, ControlOpcode.CALL_FWD, predicate=1, immediate=1),
        Instruction(0, ControlOpcode.NOP),
        Instruction(0, ControlOpcode.RET),
        Instruction(0, ControlOpcode.END),
    ]
    entry = Entry(0, 0, 0, 3, 1, 16)
    with pytest.raises(ValueError, match="empty stack"):
        control_flow_report(instructions, entry)


def test_assembler_cli_emits_all_canonical_artifacts(tmp_path: Path) -> None:
    source = tmp_path / "dummy.apus"
    source.write_text(PROGRAM, encoding="utf-8")
    outputs = {
        "-o": tmp_path / "dummy.apumc",
        "--symbols": tmp_path / "symbols.json",
        "--cfg-report": tmp_path / "cfg.json",
        "--primitive-manifest": tmp_path / "primitives.json",
        "--trace-input": tmp_path / "trace.json",
        "--abi-input-manifest": tmp_path / "abi.json",
    }
    command = [sys.executable, str(ROOT / "scripts/apu_mcasm.py"), str(source)]
    for option, path in outputs.items():
        command.extend((option, str(path)))
    subprocess.run(command, check=True)
    assert outputs["-o"].read_bytes() == assemble(PROGRAM).bundle
    for option, path in outputs.items():
        assert path.stat().st_size > 0, option
    cfg = __import__("json").loads(outputs["--cfg-report"].read_text(encoding="utf-8"))
    assert len(cfg["control_flow"]) == 3
    assert all(report["proof"] == "passed" for report in cfg["control_flow"])
    assert any(report["loops"] for report in cfg["control_flow"])
    assert any(report["edges"] for report in cfg["control_flow"])
