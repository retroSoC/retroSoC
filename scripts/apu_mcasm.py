"""Assemble and statically verify frozen APU-P3 microcode bundles."""

from __future__ import annotations

import argparse
import json
import re
from dataclasses import dataclass
from pathlib import Path

from apu_isa import (
    CONTROL_OPCODES,
    PREDICATES,
    SCALAR_OPCODES,
    ControlOpcode,
    Entry,
    Instruction,
    InstructionClass,
    ScalarOpcode,
    abi_manifest,
    build_apumc,
    control_flow_report,
    crc32_iso_hdlc,
)


@dataclass(frozen=True)
class Assembly:
    bundle: bytes
    symbols: dict[str, int]
    instructions: list[Instruction]
    entries: list[Entry]
    build_id: int


def _number(token: str) -> int:
    return int(token, 0)


def _register(token: str) -> int:
    match = re.fullmatch(r"[rR](\d+)", token)
    if match is None or int(match.group(1)) > 15:
        raise ValueError(f"invalid APU register {token}")
    return int(match.group(1))


def _tokens(line: str) -> list[str]:
    return [token for token in re.split(r"[\s,]+", line.strip()) if token]


def _predicate(tokens: list[str]) -> tuple[list[str], int]:
    if tokens and tokens[-1].startswith("if="):
        name = tokens[-1][3:].lower()
        if name not in PREDICATES:
            raise ValueError(f"unknown predicate {name}")
        return tokens[:-1], PREDICATES[name]
    return tokens, 0


def _encode_instruction(tokens: list[str], pc: int, labels: dict[str, int]) -> Instruction:
    tokens, predicate = _predicate(tokens)
    mnemonic = tokens[0].lower()
    args = tokens[1:]
    if mnemonic in CONTROL_OPCODES:
        opcode = ControlOpcode(CONTROL_OPCODES[mnemonic])
        values = {"predicate": predicate}
        if opcode in (ControlOpcode.NOP, ControlOpcode.END, ControlOpcode.RET):
            if args:
                raise ValueError(f"{mnemonic} takes no operands")
        elif opcode == ControlOpcode.TRAP:
            if len(args) != 1:
                raise ValueError("trap takes one immediate")
            values["immediate"] = _number(args[0])
        elif opcode in (ControlOpcode.JUMP_FWD, ControlOpcode.CALL_FWD):
            if len(args) != 1:
                raise ValueError(f"{mnemonic} takes one label")
            values["immediate"] = labels[args[0]] - pc - 1
        elif opcode == ControlOpcode.LOOP_SETUP:
            if len(args) != 2:
                raise ValueError("loop_setup takes a slot and count register")
            values["aux"] = _number(args[0])
            values["src0"] = _register(args[1])
        elif opcode == ControlOpcode.LOOP_BACK:
            if len(args) != 2:
                raise ValueError("loop_back takes a slot and label")
            values["aux"] = _number(args[0])
            values["immediate"] = pc + 1 - labels[args[1]]
        elif opcode == ControlOpcode.WAIT:
            if len(args) != 1:
                raise ValueError("wait takes one source")
            values["aux"] = _number(args[0])
        return Instruction(InstructionClass.CONTROL, opcode, **values)

    if mnemonic not in SCALAR_OPCODES:
        raise ValueError(f"unknown mnemonic {mnemonic}")
    opcode = ScalarOpcode(SCALAR_OPCODES[mnemonic])
    values = {"predicate": predicate}
    if opcode == ScalarOpcode.MOV:
        if len(args) != 2:
            raise ValueError("mov takes two registers")
        values.update(dst=_register(args[0]), src0=_register(args[1]))
    elif opcode == ScalarOpcode.MOVI:
        if len(args) != 2:
            raise ValueError("movi takes one register and one immediate")
        values.update(dst=_register(args[0]), immediate=_number(args[1]) & 0xFFFFFFFF)
    elif opcode == ScalarOpcode.CMP:
        if len(args) != 2:
            raise ValueError("cmp takes two registers")
        values.update(src0=_register(args[0]), src1=_register(args[1]))
    elif opcode in (ScalarOpcode.MIN, ScalarOpcode.MAX):
        if len(args) not in (3, 4):
            raise ValueError(f"{mnemonic} takes three registers and an optional signed selector")
        values.update(
            dst=_register(args[0]),
            src0=_register(args[1]),
            src1=_register(args[2]),
            aux=_number(args[3]) if len(args) == 4 else 0,
        )
    elif opcode == ScalarOpcode.SAT:
        if len(args) != 3:
            raise ValueError("sat takes a destination, source, and width/sign encoding")
        values.update(dst=_register(args[0]), src0=_register(args[1]), aux=_number(args[2]))
    else:
        if len(args) != 3:
            raise ValueError(f"{mnemonic} takes three registers")
        values.update(dst=_register(args[0]), src0=_register(args[1]), src1=_register(args[2]))
    return Instruction(InstructionClass.SCALAR, opcode, **values)


def assemble(source: str) -> Assembly:
    lines = []
    labels: dict[str, int] = {}
    directives: list[list[str]] = []
    pc = 0
    for line_number, raw_line in enumerate(source.splitlines(), start=1):
        line = raw_line.partition("#")[0].strip()
        if not line:
            continue
        if line.endswith(":"):
            label = line[:-1].strip()
            if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", label) or label in labels:
                raise ValueError(f"line {line_number}: invalid or duplicate label {label}")
            labels[label] = pc
        elif line.startswith("."):
            directives.append(_tokens(line))
        else:
            lines.append((line_number, _tokens(line)))
            pc += 1

    build_id = 0
    entry_directives = []
    for directive in directives:
        if directive[0] == ".build_id" and len(directive) == 2:
            build_id = _number(directive[1])
        elif directive[0] == ".entry" and len(directive) == 7:
            entry_directives.append(directive[1:])
        else:
            raise ValueError(f"invalid assembler directive {' '.join(directive)}")
    if len(entry_directives) != 3:
        raise ValueError("exactly three .entry directives are required")

    instructions = []
    for line_number, tokens in lines:
        try:
            instructions.append(_encode_instruction(tokens, len(instructions), labels))
        except (IndexError, KeyError, ValueError) as error:
            raise ValueError(f"line {line_number}: {error}") from error

    entries = []
    for values in entry_directives:
        try:
            entries.append(
                Entry(
                    format_id=_number(values[0]),
                    entry_pc=labels[values[1]],
                    first_pc=labels[values[2]],
                    last_pc=labels[values[3]],
                    max_loop_count=_number(values[4]),
                    max_retired=_number(values[5]),
                )
            )
        except KeyError as error:
            raise ValueError(f"unknown entry label {error.args[0]}") from error
    entries.sort(key=lambda entry: entry.format_id)
    bundle = build_apumc(instructions, entries, build_id)
    return Assembly(bundle, dict(sorted(labels.items())), instructions, entries, build_id)


def _artifact_data(assembly: Assembly) -> dict[str, object]:
    return {
        "abi": "1.0",
        "build_id": f"0x{assembly.build_id:016x}",
        "bundle_bytes": len(assembly.bundle),
        "instruction_count": len(assembly.instructions),
        "payload_crc32": f"0x{crc32_iso_hdlc(assembly.bundle[64:]):08x}",
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("-o", "--output", type=Path, required=True)
    parser.add_argument("--symbols", type=Path)
    parser.add_argument("--cfg-report", type=Path)
    parser.add_argument("--primitive-manifest", type=Path)
    parser.add_argument("--trace-input", type=Path)
    parser.add_argument("--abi-input-manifest", type=Path)
    args = parser.parse_args()
    assembly = assemble(args.source.read_text(encoding="utf-8"))
    args.output.write_bytes(assembly.bundle)
    artifacts = {
        args.symbols: assembly.symbols,
        args.cfg_report: {
            **_artifact_data(assembly),
            "entries": [entry.__dict__ for entry in assembly.entries],
            "control_flow": [
                control_flow_report(assembly.instructions, entry) for entry in assembly.entries
            ],
        },
        args.primitive_manifest: {
            "implemented_mask": 0,
            "required_mask": 0,
            "entry_masks": [entry.primitive_mask for entry in assembly.entries],
        },
        args.trace_input: {
            "entries": [entry.entry_pc for entry in assembly.entries],
            "instructions": [f"0x{item.encode():016x}" for item in assembly.instructions],
        },
        args.abi_input_manifest: {**_artifact_data(assembly), "canonical_abi": abi_manifest()},
    }
    for path, data in artifacts.items():
        if path is not None:
            path.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
