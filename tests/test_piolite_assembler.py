"""Strict-source, deterministic-object, allocation, and footprint tests for PIO-lite."""

from __future__ import annotations

import hashlib
import os
import subprocess
import sys
import tempfile
from dataclasses import replace
from pathlib import Path

import pytest


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

import piolite_asm  # noqa: E402
import piolite_isa  # noqa: E402
from piolite_asm import AssemblyError, assemble, emit_c  # noqa: E402
from piolite_isa import AllocationError, InstructionAllocator, ISAError  # noqa: E402


SOURCE = """.program demo
.entry start
.wrap_bottom start
.wrap_top done
.in 2, 1
.out 4, 2
.set 6, 3
.tx_bits 8, right, auto
.rx_bits 16, left, manual
.test 2, 1
.packing 4, 0, 8
.clock_ticks 7, stretchable
start: CTRL NOP [1]
done: CTRL HALT
"""


def make_source(name: str, body: str, *, top: str = "start") -> str:
    return f""".program {name}
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


def sized_program(name: str, length: int) -> piolite_isa.Program:
    if length == 1:
        return assemble(make_source(name, "start: CTRL HALT"))
    lines = ["start: CTRL NOP"]
    lines.extend("CTRL NOP" for _ in range(length - 2))
    lines.append("last: CTRL HALT")
    return assemble(make_source(name, "\n".join(lines), top="last"))


def test_deterministic_assembly_and_independent_c_object_golden() -> None:
    first = assemble(SOURCE)
    second = assemble(SOURCE)
    assert first == second
    assert first.words == (0x0100, 0x0020)
    assert first.relocation_sites == ()
    assert first.claim_mask == 0x000001F4
    assert first.flag_mask == 0
    generated = emit_c(first).encode("utf-8")
    assert generated == emit_c(second).encode("utf-8")
    assert len(generated) == 1780
    assert hashlib.sha256(generated).hexdigest() == (
        "07c41f5875b17c8d9fb439d4b6169c26ef47739eca44af35dd9ee61783d675f6"
    )
    assert b"0x00010000u" in generated
    assert b".test_pin_enable = 0u" in generated
    assert b"0x0100u,\n    0x0020u," in generated
    assert b".entry = 0u" in generated
    assert b".wrap_top = 1u" in generated
    assert str(ROOT).encode() not in generated


def test_resource_metadata_tracks_actual_wait_flag_and_test_references() -> None:
    program = assemble(
        """.program resources
.entry start
.wrap_bottom start
.wrap_top last
.in 0, 0
.out 0, 0
.set 0, 0
.tx_bits 32, right, manual
.rx_bits 32, right, manual
.test 31, 2
.packing 0, 0, 8
.clock_ticks 1, stretchable
start: WAIT PIN, 1, 7
WAIT FLAG, 0, 3
FLAG SET, 1
BRANCH TEST_PIN_HIGH, start
BRANCH TEST_FLAG_SET, start
last: CTRL HALT
"""
    )
    assert program.claim_mask == (1 << 31) | (1 << 7)
    assert program.flag_mask == (1 << 3) | (1 << 2) | (1 << 1)
    assert program.relocation_sites == (3, 4)


BAD_SOURCES = (
    ("duplicate label", make_source("p", "start: CTRL NOP\nstart: CTRL HALT"), "duplicate label"),
    ("unknown label", make_source("p", "start: BRANCH ALWAYS, missing"), "unknown label"),
    ("label only", make_source("p", "start:"), "same line"),
    ("label directive", ".entry x\nstart: .program p", "cannot prefix"),
    ("lowercase mnemonic", make_source("p", "start: ctrl NOP"), "unknown instruction"),
    ("lowercase operand", make_source("p", "start: CTRL nop"), "unknown CTRL"),
    ("raw branch", make_source("p", "start: BRANCH ALWAYS, 0"), "ASCII identifier"),
    ("signed number", make_source("p", "start: SET_PIN -1"), "unsigned decimal"),
    ("expression", make_source("p", "start: SET_PIN 1 + 1"), "exactly one operand"),
    ("uppercase hex introducer", make_source("p", "start: SET_PIN 0X1"), "unsigned decimal"),
    ("hash comment", make_source("p", "start: CTRL HALT # no"), "exactly one operand"),
    ("missing comma", make_source("p", "start: WAIT PIN 1 2"), "comma-separated"),
    ("delay range", make_source("p", "start: CTRL NOP [16]"), "0..15"),
    ("signed delay", make_source("p", "start: CTRL NOP [-1]"), "unsigned decimal"),
    ("include", ".include other\n", "unknown directive"),
    ("missing metadata", SOURCE.replace(".test 2, 1\n", ""), "missing required directive .test"),
    ("duplicate metadata", SOURCE.replace(".out 4, 2", ".out 4, 2\n.in 2, 1"), "duplicate directive .in"),
    ("bad wrap", make_source("p", "start: CTRL HALT", top="missing"), "unknown label"),
    ("disabled input", make_source("p", "start: IN PINS, 1"), "exceeds the configured input"),
    ("wide counter OUT", make_source("p", "start: OUT X, 32"), "limited to 16"),
    ("counter immediate", make_source("p", "start: SET_COUNT X, 128"), "0..127"),
    ("missing test pin", make_source("p", "start: BRANCH TEST_PIN_HIGH, start"), "selected test pin"),
)


@pytest.mark.parametrize(("name", "source", "message"), BAD_SOURCES, ids=[case[0] for case in BAD_SOURCES])
def test_strict_source_rejection(name: str, source: str, message: str) -> None:
    del name
    with pytest.raises(AssemblyError, match=message):
        assemble(source)


def test_oversize_and_line_diagnostics_are_deterministic() -> None:
    with pytest.raises(AssemblyError) as caught:
        sized_program("too_large", 33)
    assert caught.value.line == 45
    assert "exceeds 32" in str(caught.value)
    with pytest.raises(AssemblyError) as duplicate:
        assemble(make_source("p", "start: CTRL NOP\nstart: CTRL HALT"))
    assert str(duplicate.value) == "line 14: duplicate label 'start'"


def test_allocator_relocation_exhaustion_fragmentation_and_sharing() -> None:
    at_zero = InstructionAllocator()
    at_31 = InstructionAllocator()
    branch = assemble(make_source("branch", "start: BRANCH ALWAYS, start"))
    assert at_zero.load(branch, 0).words == (0x9000,)
    assert at_31.load(branch, 31).words == (0x901F,)

    full = InstructionAllocator()
    for index in range(32):
        full.load(sized_program(f"p{index}", 1))
    assert full.valid_bitmap == 0xFFFFFFFF
    with pytest.raises(AllocationError, match="no contiguous"):
        full.load(sized_program("overflow", 1))

    fragmented = InstructionAllocator()
    for index, base in enumerate(range(0, 32, 2)):
        fragmented.load(sized_program(f"f{index}", 1), base)
    assert fragmented.valid_bitmap == 0x55555555
    with pytest.raises(AllocationError, match="no contiguous"):
        fragmented.load(sized_program("pair", 2))

    shared = InstructionAllocator()
    program = sized_program("shared", 3)
    first = shared.load(program)
    second = shared.load(program)
    assert first == second
    assert shared.valid_bitmap == 0b111
    shared.unload(first)
    assert shared.valid_bitmap == 0b111
    shared.unload(second)
    assert shared.valid_bitmap == 0


def test_invalid_regions_and_interrupted_load_do_not_publish(monkeypatch: pytest.MonkeyPatch) -> None:
    allocator = InstructionAllocator()
    valid = sized_program("valid", 2)
    for invalid in (
        replace(valid, entry=2),
        replace(valid, wrap_bottom=1, wrap_top=0),
        replace(valid, wrap_top=2),
        replace(valid, isa_version=0x00020000),
    ):
        with pytest.raises(ISAError):
            allocator.load(invalid)
        assert allocator.valid_bitmap == 0

    def interrupt(program: piolite_isa.Program, base: int) -> piolite_isa.RelocatedProgram:
        del program, base
        raise KeyboardInterrupt

    monkeypatch.setattr(piolite_isa, "relocate_program", interrupt)
    with pytest.raises(KeyboardInterrupt):
        allocator.load(valid)
    assert allocator.valid_bitmap == 0
    assert allocator.allocations == ()


def test_cli_emits_byte_identical_files_and_source_diagnostics(tmp_path: Path) -> None:
    source_path = tmp_path / "demo.piolite"
    source_path.write_text(SOURCE, encoding="utf-8")
    outputs = []
    for index in range(2):
        output = tmp_path / f"demo-{index}.c"
        result = subprocess.run(
            [sys.executable, str(ROOT / "scripts" / "piolite_asm.py"), str(source_path), str(output)],
            cwd=ROOT,
            check=False,
            capture_output=True,
            text=True,
        )
        assert result.returncode == 0, result.stderr
        assert "demo: 2 words, 0 relocation sites" in result.stdout
        outputs.append(output.read_bytes())
    assert outputs[0] == outputs[1]

    bad_path = tmp_path / "bad.piolite"
    bad_path.write_text(make_source("bad", "start: BRANCH ALWAYS, nowhere"), encoding="utf-8")
    failed = subprocess.run(
        [sys.executable, str(ROOT / "scripts" / "piolite_asm.py"), str(bad_path), str(tmp_path / "bad.c")],
        cwd=ROOT,
        check=False,
        capture_output=True,
        text=True,
    )
    assert failed.returncode == 2
    assert "line 13: unknown label 'nowhere'" in failed.stderr
    assert not (tmp_path / "bad.c").exists()


@pytest.mark.parametrize("preexisting", (False, True), ids=("new-destination", "existing-destination"))
def test_cli_write_failure_cleans_temporary_and_preserves_destination(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
    preexisting: bool,
) -> None:
    source_path = tmp_path / "input.piolite"
    output_path = tmp_path / "result.c"
    source_path.write_text(SOURCE, encoding="utf-8")
    original = b"known-good\n"
    if preexisting:
        output_path.write_bytes(original)
    real_factory = tempfile.NamedTemporaryFile

    class FailingStream:
        def __init__(self, stream):
            self.stream = stream
            self.name = stream.name

        def __enter__(self):
            self.stream.__enter__()
            return self

        def __exit__(self, exc_type, exc_value, traceback):
            return self.stream.__exit__(exc_type, exc_value, traceback)

        def write(self, text):
            self.stream.write(text[:32])
            self.stream.flush()
            raise OSError("injected write failure")

    monkeypatch.setattr(
        piolite_asm.tempfile,
        "NamedTemporaryFile",
        lambda *args, **kwargs: FailingStream(real_factory(*args, **kwargs)),
    )
    result = piolite_asm.main([str(source_path), str(output_path)])
    assert result == 2
    assert "injected write failure" in capsys.readouterr().err
    if preexisting:
        assert output_path.read_bytes() == original
    else:
        assert not output_path.exists()
    assert list(tmp_path.glob(".piolite-*.tmp")) == []


@pytest.mark.parametrize("name_length", (242, 255))
def test_cli_near_name_max_output_uses_bounded_temporary_name(
    tmp_path: Path, name_length: int
) -> None:
    source_path = tmp_path / "input.piolite"
    output_path = tmp_path / ("p" * name_length)
    source_path.write_text(SOURCE, encoding="utf-8")
    result = piolite_asm.main([str(source_path), str(output_path)])
    assert result == 0
    assert output_path.read_bytes() == emit_c(assemble(SOURCE)).encode("utf-8")
    assert list(tmp_path.glob(".piolite-*.tmp")) == []


def test_cli_new_output_mode_follows_umask(tmp_path: Path) -> None:
    source_path = tmp_path / "input.piolite"
    output_path = tmp_path / "new.c"
    source_path.write_text(SOURCE, encoding="utf-8")
    previous_umask = os.umask(0o022)
    try:
        result = piolite_asm.main([str(source_path), str(output_path)])
    finally:
        os.umask(previous_umask)
    assert result == 0
    assert output_path.stat().st_mode & 0o777 == 0o644


@pytest.mark.parametrize("mode", (0o644, 0o444))
def test_cli_existing_output_mode_is_preserved(tmp_path: Path, mode: int) -> None:
    source_path = tmp_path / "input.piolite"
    output_path = tmp_path / "existing.c"
    source_path.write_text(SOURCE, encoding="utf-8")
    output_path.write_bytes(b"old\n")
    os.chmod(output_path, mode)
    result = piolite_asm.main([str(source_path), str(output_path)])
    assert result == 0
    assert output_path.stat().st_mode & 0o777 == mode
    assert output_path.read_bytes() == emit_c(assemble(SOURCE)).encode("utf-8")


def test_foreign_allocation_handle_collision_is_rejected_atomically() -> None:
    allocator_a = InstructionAllocator()
    allocator_b = InstructionAllocator()
    program_a = sized_program("allocator_a", 2)
    program_b = sized_program("allocator_b", 1)
    allocation_a = allocator_a.load(program_a, 0)
    allocation_b = allocator_b.load(program_b, 5)
    assert allocation_a.handle == allocation_b.handle
    before = (
        allocator_a.valid_bitmap,
        allocator_a.allocations,
        dict(allocator_a._references),
    )

    with pytest.raises(AllocationError, match="foreign allocation"):
        allocator_a.unload(allocation_b)
    assert (
        allocator_a.valid_bitmap,
        allocator_a.allocations,
        dict(allocator_a._references),
    ) == before
    assert allocator_b.valid_bitmap == 1 << 5

    allocator_a.unload(allocation_a)
    assert allocator_a.valid_bitmap == 0
    replacement = allocator_a.load(program_a, 0)
    assert replacement.base == 0
    assert allocator_a.valid_bitmap == 0b11
    allocator_b.unload(allocation_b)
    assert allocator_b.valid_bitmap == 0


PATHOLOGICAL_NUMBERS = ("9" * 5000, "0x" + "F" * 5000)


@pytest.mark.parametrize("token", PATHOLOGICAL_NUMBERS, ids=("long-decimal", "long-hexadecimal"))
def test_pathological_numbers_have_normal_assembly_diagnostics(token: str) -> None:
    with pytest.raises(AssemblyError) as caught:
        assemble(make_source("p", f"start: SET_PIN {token}"))
    assert caught.value.line == 13
    assert "SET immediate" in caught.value.message


@pytest.mark.parametrize("token", PATHOLOGICAL_NUMBERS, ids=("long-decimal", "long-hexadecimal"))
def test_cli_pathological_numbers_have_normal_diagnostics(tmp_path: Path, token: str) -> None:
    source_path = tmp_path / "pathological.piolite"
    output_path = tmp_path / "pathological.c"
    source_path.write_text(make_source("p", f"start: SET_PIN {token}"), encoding="utf-8")
    result = subprocess.run(
        [sys.executable, str(ROOT / "scripts" / "piolite_asm.py"), str(source_path), str(output_path)],
        cwd=ROOT,
        check=False,
        capture_output=True,
        text=True,
    )
    assert result.returncode == 2
    assert "line 13: SET immediate" in result.stderr
    assert "Traceback" not in result.stderr
    assert not output_path.exists()


EXPECTED_FOOTPRINTS = {
    "logic_capture": 9,
    "pulse_generate": 12,
    "pulse_capture": 8,
    "uart_tx": 12,
    "uart_rx": 12,
    "spi_master": 15,
    "ir_tx": 10,
    "ir_rx": 13,
    "led_scan": 14,
    "gamepad": 11,
}


@pytest.mark.parametrize(("name", "words"), sorted(EXPECTED_FOOTPRINTS.items()))
def test_actual_application_footprint(name: str, words: int) -> None:
    source = (ROOT / "app" / "asm" / "piolite" / f"{name}.piolite").read_text(encoding="utf-8")
    program = assemble(source)
    assert len(program.instructions) == words
    assert emit_c(program).encode("utf-8") == emit_c(assemble(source)).encode("utf-8")


def test_logic_capture_metadata_describes_application_samples() -> None:
    source = (ROOT / "app" / "asm" / "piolite" / "logic_capture.piolite").read_text(
        encoding="utf-8"
    )
    program = assemble(source)
    assert program.packing.rx_items == 32768
    assert program.packing.item_bits == 8
    assert program.timing.clock_ticks == 2
    generated = emit_c(program)
    assert ".rx_items = 32768u" in generated
    assert ".item_bits = 8u" in generated
    assert ".clock_ticks = 2u" in generated


@pytest.mark.parametrize(
    ("first", "second", "total"),
    (("pulse_generate", "pulse_capture", 20), ("uart_tx", "uart_rx", 24), ("ir_tx", "ir_rx", 23)),
)
def test_required_dual_sm_images_fit_together(first: str, second: str, total: int) -> None:
    allocator = InstructionAllocator()
    for name in (first, second):
        source = (ROOT / "app" / "asm" / "piolite" / f"{name}.piolite").read_text(encoding="utf-8")
        allocator.load(assemble(source))
    assert sum(len(allocation.words) for allocation in allocator.allocations) == total
    assert allocator.valid_bitmap == (1 << total) - 1
    for allocation in allocator.allocations:
        for word in allocation.words:
            piolite_isa.Instruction.decode(word)
