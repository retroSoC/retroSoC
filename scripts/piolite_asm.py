"""Strict deterministic assembler and C-object emitter for PIO-lite ISA1.0."""

from __future__ import annotations

import argparse
import os
import re
import stat
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path

from piolite_isa import (
    BRANCH_CONDITIONS,
    CTRL_COMMANDS,
    FIFO_MODES,
    FIFO_OPERATIONS,
    FLAG_ACTIONS,
    IN_SOURCES,
    INSTRUCTION_WORDS,
    ISA_VERSION,
    MOVE_REGISTERS,
    MOVE_SOURCES,
    OUT_DESTINATIONS,
    WAIT_SOURCES,
    Instruction,
    ISAError,
    Opcode,
    PackingSpec,
    PinWindow,
    Program,
    ShiftSpec,
    TestSpec,
    TimingSpec,
    referenced_resources,
    test_pin_is_used,
)


IDENTIFIER = re.compile(r"[A-Za-z_][A-Za-z0-9_]*\Z", re.ASCII)
NUMBER = re.compile(r"(?:0x[0-9a-fA-F]+|[0-9]+)\Z", re.ASCII)
DIRECTIVES = (
    ".program",
    ".entry",
    ".wrap_bottom",
    ".wrap_top",
    ".in",
    ".out",
    ".set",
    ".tx_bits",
    ".rx_bits",
    ".test",
    ".packing",
    ".clock_ticks",
)
DIRECTIVE_OPERANDS = {
    ".program": 1,
    ".entry": 1,
    ".wrap_bottom": 1,
    ".wrap_top": 1,
    ".in": 2,
    ".out": 2,
    ".set": 2,
    ".tx_bits": 3,
    ".rx_bits": 3,
    ".test": 2,
    ".packing": 3,
    ".clock_ticks": 2,
}
INSTRUCTION_OPERANDS = {
    Opcode.CTRL: 1,
    Opcode.SET_PIN: 1,
    Opcode.SET_DIR: 1,
    Opcode.SET_COUNT: 2,
    Opcode.IN: 2,
    Opcode.OUT: 2,
    Opcode.MOVE: 2,
    Opcode.FIFO: 2,
    Opcode.WAIT: 3,
    Opcode.BRANCH: 2,
    Opcode.FLAG: 2,
}
MNEMONICS = {opcode.name: opcode for opcode in Opcode}


class AssemblyError(ValueError):
    """A source error with a deterministic one-based source line."""

    def __init__(self, line: int, message: str):
        super().__init__(f"line {line}: {message}")
        self.line = line
        self.message = message


@dataclass(frozen=True)
class _Statement:
    line: int
    opcode: Opcode
    args: tuple[str, ...]
    delay: int


def _number(token: str, line: int, name: str, minimum: int, maximum: int) -> int:
    if NUMBER.fullmatch(token) is None:
        raise AssemblyError(line, f"{name} must be unsigned decimal or 0x hexadecimal")
    try:
        value = int(token, 16) if token.startswith("0x") else int(token, 10)
    except ValueError as exc:
        raise AssemblyError(line, f"{name} exceeds the supported integer conversion") from exc
    if not minimum <= value <= maximum:
        raise AssemblyError(line, f"{name} must be in {minimum}..{maximum}")
    return value


def _identifier(token: str, line: int, name: str) -> str:
    if IDENTIFIER.fullmatch(token) is None:
        raise AssemblyError(line, f"{name} must be an ASCII identifier")
    return token


def _symbol(token: str, symbols: dict[str, int], line: int, name: str) -> int:
    if token not in symbols:
        raise AssemblyError(line, f"unknown {name} symbol {token!r}")
    return symbols[token]


def _args(text: str, count: int, line: int, construct: str) -> tuple[str, ...]:
    if count == 1:
        if "," in text or not text or len(text.split()) != 1:
            raise AssemblyError(line, f"{construct} requires exactly one operand")
        return (text,)
    args = tuple(item.strip() for item in text.split(","))
    if len(args) != count or any(not item or len(item.split()) != 1 for item in args):
        raise AssemblyError(line, f"{construct} requires {count} comma-separated operands")
    return args


def _delay(text: str, line: int) -> tuple[str, int]:
    if "[" not in text and "]" not in text:
        return text, 0
    match = re.fullmatch(r"(.*?)\s*\[([^\[\]]+)\]", text)
    if match is None or not match.group(1).strip():
        raise AssemblyError(line, "delay must be one trailing unsigned value in brackets")
    return match.group(1).strip(), _number(match.group(2).strip(), line, "delay", 0, 15)


def _instruction(statement: _Statement, labels: dict[str, int]) -> Instruction:
    line = statement.line
    args = statement.args
    opcode = statement.opcode
    operand = 0
    if opcode == Opcode.CTRL:
        operand = _symbol(args[0], CTRL_COMMANDS, line, "CTRL") << 5
    elif opcode in (Opcode.SET_PIN, Opcode.SET_DIR):
        operand = _number(args[0], line, "SET immediate", 0, 0xFF)
    elif opcode == Opcode.SET_COUNT:
        destination = _symbol(args[0], {"X": 0, "Y": 1}, line, "SET_COUNT destination")
        operand = (destination << 7) | _number(args[1], line, "SET_COUNT immediate", 0, 127)
    elif opcode == Opcode.IN:
        source = _symbol(args[0], IN_SOURCES, line, "IN source")
        count = _number(args[1], line, "IN count", 1, 32)
        operand = (source << 5) | (count & 0x1F)
    elif opcode == Opcode.OUT:
        destination = _symbol(args[0], OUT_DESTINATIONS, line, "OUT destination")
        count = _number(args[1], line, "OUT count", 1, 32)
        operand = (destination << 5) | (count & 0x1F)
    elif opcode == Opcode.MOVE:
        destination = _symbol(args[0], MOVE_REGISTERS, line, "MOVE destination")
        source = _symbol(args[1], MOVE_SOURCES, line, "MOVE source")
        operand = (destination << 6) | (source << 3)
    elif opcode == Opcode.FIFO:
        operation = _symbol(args[0], FIFO_OPERATIONS, line, "FIFO operation")
        mode = _symbol(args[1], FIFO_MODES, line, "FIFO mode")
        operand = (operation << 7) | (mode << 6)
    elif opcode == Opcode.WAIT:
        source = _symbol(args[0], WAIT_SOURCES, line, "WAIT source")
        level = _number(args[1], line, "WAIT level", 0, 1)
        maximum_index = 31 if source == WAIT_SOURCES["PIN"] else 3
        index = _number(args[2], line, "WAIT index", 0, maximum_index)
        operand = (source << 7) | (level << 6) | (index << 1)
    elif opcode == Opcode.BRANCH:
        condition = _symbol(args[0], BRANCH_CONDITIONS, line, "branch condition")
        label = _identifier(args[1], line, "branch target")
        if label not in labels:
            raise AssemblyError(line, f"unknown label {label!r}")
        operand = (condition << 5) | labels[label]
    elif opcode == Opcode.FLAG:
        action = _symbol(args[0], FLAG_ACTIONS, line, "FLAG action")
        index = _number(args[1], line, "FLAG index", 0, 3)
        operand = (action << 7) | (index << 5)
    instruction = Instruction(opcode, statement.delay, operand)
    try:
        instruction.validate()
    except ISAError as exc:
        raise AssemblyError(line, str(exc)) from exc
    return instruction


def assemble(source: str) -> Program:
    """Assemble one strict .piolite source string into an unrelocated program."""

    if not isinstance(source, str):
        raise TypeError("assembly source must be text")
    labels: dict[str, int] = {}
    statements: list[_Statement] = []
    directives: dict[str, tuple[tuple[str, ...], int]] = {}
    lines = source.splitlines()
    for line_number, raw_line in enumerate(lines, 1):
        text = raw_line.split(";", 1)[0].strip()
        if not text:
            continue
        label_match = re.match(r"([A-Za-z_][A-Za-z0-9_]*):(.*)\Z", text, re.ASCII)
        if label_match is not None:
            label = label_match.group(1)
            if label in labels:
                raise AssemblyError(line_number, f"duplicate label {label!r}")
            text = label_match.group(2).strip()
            if not text:
                raise AssemblyError(line_number, "a label requires an instruction on the same line")
            if text.startswith("."):
                raise AssemblyError(line_number, "a label cannot prefix a directive")
            labels[label] = len(statements)
        elif ":" in text:
            raise AssemblyError(line_number, "malformed label")

        if text.startswith("."):
            parts = text.split(None, 1)
            directive = parts[0]
            if directive not in DIRECTIVES:
                raise AssemblyError(line_number, f"unknown directive {directive!r}")
            if directive in directives:
                raise AssemblyError(line_number, f"duplicate directive {directive}")
            operand_text = parts[1].strip() if len(parts) == 2 else ""
            args = _args(
                operand_text,
                DIRECTIVE_OPERANDS[directive],
                line_number,
                directive,
            )
            directives[directive] = (args, line_number)
            continue

        if len(statements) >= INSTRUCTION_WORDS:
            raise AssemblyError(line_number, "program exceeds 32 instruction words")
        body, delay = _delay(text, line_number)
        parts = body.split(None, 1)
        mnemonic = parts[0]
        if mnemonic not in MNEMONICS:
            raise AssemblyError(line_number, f"unknown instruction mnemonic {mnemonic!r}")
        opcode = MNEMONICS[mnemonic]
        operand_text = parts[1].strip() if len(parts) == 2 else ""
        args = _args(operand_text, INSTRUCTION_OPERANDS[opcode], line_number, mnemonic)
        statements.append(_Statement(line_number, opcode, args, delay))

    fallback_line = len(lines) if lines else 1
    if not statements:
        raise AssemblyError(fallback_line, "program has no instructions")
    for directive in DIRECTIVES:
        if directive not in directives:
            raise AssemblyError(fallback_line, f"missing required directive {directive}")

    def label_offset(directive: str) -> int:
        args, line = directives[directive]
        label = _identifier(args[0], line, f"{directive} label")
        if label not in labels:
            raise AssemblyError(line, f"unknown label {label!r}")
        return labels[label]

    def window(directive: str, maximum_width: int) -> PinWindow:
        args, line = directives[directive]
        return PinWindow(
            _number(args[0], line, f"{directive} base", 0, 31),
            _number(args[1], line, f"{directive} width", 0, maximum_width),
        )

    def shift(directive: str) -> ShiftSpec:
        args, line = directives[directive]
        return ShiftSpec(
            _number(args[0], line, f"{directive} count", 1, 32),
            _choice(args[1], ("left", "right"), line, f"{directive} direction"),
            _choice(args[2], ("manual", "auto"), line, f"{directive} mode"),
        )

    program_args, program_line = directives[".program"]
    name = _identifier(program_args[0], program_line, "program name")
    test_args, test_line = directives[".test"]
    if test_args[0] == "none":
        test_pin = None
    else:
        test_pin = _number(test_args[0], test_line, "test pin", 0, 31)
    test = TestSpec(test_pin, _number(test_args[1], test_line, "test flag", 0, 3))
    packing_args, packing_line = directives[".packing"]
    packing = PackingSpec(
        _number(packing_args[0], packing_line, "TX_ITEMS", 0, 0xFFFFFFFF),
        _number(packing_args[1], packing_line, "RX_ITEMS", 0, 0xFFFFFFFF),
        _number(packing_args[2], packing_line, "ITEM_BITS", 1, 32),
    )
    timing_args, timing_line = directives[".clock_ticks"]
    timing = TimingSpec(
        _number(timing_args[0], timing_line, "clock_ticks", 1, 0xFFFFFFFF),
        _choice(timing_args[1], ("fixed", "stretchable"), timing_line, "timing behavior"),
    )
    in_window = window(".in", 32)
    out_window = window(".out", 32)
    set_window = window(".set", 8)
    tx = shift(".tx_bits")
    rx = shift(".rx_bits")
    instructions = tuple(_instruction(statement, labels) for statement in statements)
    try:
        claim_mask, flag_mask = referenced_resources(
            instructions, in_window, out_window, set_window, test
        )
    except ISAError as exc:
        line = next(
            statement.line
            for statement in statements
            if statement.opcode == Opcode.BRANCH
            and statement.args[0] == "TEST_PIN_HIGH"
        )
        raise AssemblyError(line, str(exc)) from exc
    program = Program(
        name=name,
        instructions=instructions,
        entry=label_offset(".entry"),
        wrap_bottom=label_offset(".wrap_bottom"),
        wrap_top=label_offset(".wrap_top"),
        in_window=in_window,
        out_window=out_window,
        set_window=set_window,
        tx=tx,
        rx=rx,
        test=test,
        packing=packing,
        timing=timing,
        claim_mask=claim_mask,
        flag_mask=flag_mask,
        source_lines=tuple(statement.line for statement in statements),
    )
    try:
        program.validate()
    except ISAError as exc:
        match = re.search(r"instruction (\d+)", str(exc))
        line = program.source_lines[int(match.group(1))] if match else program_line
        raise AssemblyError(line, str(exc)) from exc
    return program


def _choice(token: str, choices: tuple[str, ...], line: int, name: str) -> str:
    if token not in choices:
        raise AssemblyError(line, f"{name} must be {' or '.join(choices)}")
    return token


def emit_c(program: Program) -> str:
    """Emit a self-contained deterministic P1 C object, not a future HAL ABI."""

    program.validate()
    symbol = f"piolite_p1_{program.name}"
    words = program.words
    sites = program.relocation_sites
    lines = [
        "/* Deterministic PIO-lite P1 program object; no HAL ABI is implied. */",
        "#include <stdint.h>",
        "",
        "typedef struct {",
        "    uint32_t isa_version;",
        "    const uint16_t *words;",
        "    uint32_t word_count;",
        "    uint8_t entry;",
        "    uint8_t wrap_bottom;",
        "    uint8_t wrap_top;",
        "    const uint8_t *relocation_sites;",
        "    uint32_t relocation_count;",
        "    uint8_t in_base;",
        "    uint8_t in_width;",
        "    uint8_t out_base;",
        "    uint8_t out_width;",
        "    uint8_t set_base;",
        "    uint8_t set_width;",
        "    uint8_t tx_bits;",
        "    uint8_t tx_right;",
        "    uint8_t autopull;",
        "    uint8_t rx_bits;",
        "    uint8_t rx_right;",
        "    uint8_t autopush;",
        "    uint8_t test_pin;",
        "    uint8_t test_flag;",
        "    uint8_t test_pin_enable;",
        "    uint32_t claim_mask;",
        "    uint32_t flag_mask;",
        "    uint32_t tx_items;",
        "    uint32_t rx_items;",
        "    uint8_t item_bits;",
        "    uint32_t clock_ticks;",
        "    uint8_t stretchable;",
        "} piolite_p1_program_object_t;",
        "",
        f"static const uint16_t {symbol}_words[{len(words)}] = {{",
    ]
    lines.extend(f"    0x{word:04X}u," for word in words)
    lines.extend(
        [
            "};",
            f"static const uint8_t {symbol}_relocation_sites[{max(1, len(sites))}] = {{",
        ]
    )
    if sites:
        lines.extend(f"    {site}u," for site in sites)
    else:
        lines.append("    0u,")
    lines.extend(
        [
            "};",
            f"static const piolite_p1_program_object_t {symbol} = {{",
            f"    .isa_version = 0x{ISA_VERSION:08X}u,",
            f"    .words = {symbol}_words,",
            f"    .word_count = {len(words)}u,",
            f"    .entry = {program.entry}u,",
            f"    .wrap_bottom = {program.wrap_bottom}u,",
            f"    .wrap_top = {program.wrap_top}u,",
            f"    .relocation_sites = {symbol}_relocation_sites,",
            f"    .relocation_count = {len(sites)}u,",
            f"    .in_base = {program.in_window.base}u,",
            f"    .in_width = {program.in_window.width}u,",
            f"    .out_base = {program.out_window.base}u,",
            f"    .out_width = {program.out_window.width}u,",
            f"    .set_base = {program.set_window.base}u,",
            f"    .set_width = {program.set_window.width}u,",
            f"    .tx_bits = {program.tx.bits}u,",
            f"    .tx_right = {int(program.tx.direction == 'right')}u,",
            f"    .autopull = {int(program.tx.mode == 'auto')}u,",
            f"    .rx_bits = {program.rx.bits}u,",
            f"    .rx_right = {int(program.rx.direction == 'right')}u,",
            f"    .autopush = {int(program.rx.mode == 'auto')}u,",
            f"    .test_pin = {0xFF if program.test.pin is None else program.test.pin}u,",
            f"    .test_flag = {program.test.flag}u,",
            f"    .test_pin_enable = {int(test_pin_is_used(program.instructions))}u,",
            f"    .claim_mask = 0x{program.claim_mask:08X}u,",
            f"    .flag_mask = 0x{program.flag_mask:X}u,",
            f"    .tx_items = {program.packing.tx_items}u,",
            f"    .rx_items = {program.packing.rx_items}u,",
            f"    .item_bits = {program.packing.item_bits}u,",
            f"    .clock_ticks = {program.timing.clock_ticks}u,",
            f"    .stretchable = {int(program.timing.behavior == 'stretchable')}u,",
            "};",
            "",
        ]
    )
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path, help="strict .piolite source")
    parser.add_argument("output", type=Path, help="generated C object below a build/test directory")
    args = parser.parse_args(argv)
    try:
        source = args.input.read_text(encoding="utf-8")
        program = assemble(source)
        generated = emit_c(program)
    except (OSError, UnicodeError, AssemblyError, ISAError) as exc:
        print(f"{args.input}: {exc}", file=sys.stderr)
        return 2
    temp_path = None
    try:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        if args.output.exists():
            destination_mode = stat.S_IMODE(args.output.stat().st_mode)
        else:
            current_umask = os.umask(0)
            os.umask(current_umask)
            destination_mode = 0o666 & ~current_umask
        with tempfile.NamedTemporaryFile(
            "w",
            encoding="utf-8",
            newline="\n",
            dir=args.output.parent,
            prefix=".piolite-",
            suffix=".tmp",
            delete=False,
        ) as stream:
            temp_path = Path(stream.name)
            stream.write(generated)
        os.chmod(temp_path, destination_mode)
        os.replace(temp_path, args.output)
    except OSError as exc:
        if temp_path is not None:
            try:
                temp_path.unlink(missing_ok=True)
            except OSError:
                pass
        print(f"{args.output}: {exc}", file=sys.stderr)
        return 2
    print(
        f"{program.name}: {len(program.instructions)} words, "
        f"{len(program.relocation_sites)} relocation sites, ISA 0x{ISA_VERSION:08X}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
