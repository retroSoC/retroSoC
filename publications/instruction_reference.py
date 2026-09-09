"""Source-encoded APU instruction families; no hardware execution claims."""
from __future__ import annotations

from dataclasses import replace
import re

from publications.register_reference import number

FAMILIES = (
    ("CONTROL", "ControlOpcode", "Branches, bounded loops, termination and source-qualified waits."),
    ("SCALAR", "ScalarOpcode", "Register moves, immediate values, integer operations, compare and saturation."),
    ("BITSTREAM", "BitstreamOpcode", "Bit reservoir operations, synchronization and CRC. IMM is a width or bound where used."),
    ("ENTROPY", "EntropyOpcode", "Table-assisted Huffman and bounded unary/Rice operations. AUX selects a bounded mode/length."),
    ("LOCAL", "LocalOpcode", "Local scratch/table words and FIFO operations. Address/extent checks remain separate from bit encoding."),
    ("KERNEL", "KernelOpcode", "Bounded processing kernels. IMM carries the count; AUX selects an opcode-specific mode."),
    ("TRANSPORT", "TransportOpcode", "Input/output, DMA, stream, frame/job results and qualified software-visible events."),
)


def legal_sample(isa, family: str, opcode: int):
    values = {}
    name = getattr(isa, dict((family, enum) for family, enum, _ in FAMILIES)[family])(opcode).name
    if family == "CONTROL" and name in {"JUMP_FWD", "CALL_FWD", "LOOP_BACK"}:
        values["immediate"] = 1
    elif family == "SCALAR" and name == "MOVI":
        values.update(dst=1, immediate=0x12345678)
    elif family == "BITSTREAM":
        if name in {"REFILL", "PEEK", "GET", "SKIP"}:
            values["immediate"] = 8
        elif name == "FRAME_SYNC":
            values.update(aux=8, immediate=1)
    elif family == "ENTROPY":
        if name.startswith("HUFF_"):
            values["aux"] = 16
        elif name == "UNARY":
            values["immediate"] = 1
    elif family == "KERNEL":
        values["immediate"] = 1
        if name == "LPC":
            values["aux"] = 1
    elif family == "TRANSPORT" and name == "EVENT":
        values["immediate"] = 0x40
    instruction = isa.Instruction(int(getattr(isa.InstructionClass, family)), opcode, **values)
    isa.validate_instruction(instruction, "p5")
    return instruction


def instruction_families(isa, defines: str) -> list[dict]:
    result = []
    for family, enum_name, note in FAMILIES:
        class_id = int(getattr(isa.InstructionClass, family))
        classes = re.findall(r"^`define\s+APB4_APU__MC_CLASS_" + family + r"\s+(\S+)", defines, re.M)
        if len(classes) != 1 or number(classes[0]) != class_id:
            raise ValueError("APU instruction-class enumeration differs from RTL")
        expected = {opcode.name: int(opcode) for opcode in getattr(isa, enum_name)}
        actual = {name: number(value) for name, value in re.findall(
            r"^`define\s+APB4_APU__MC_" + family + r"_(\w+)\s+(\S+)", defines, re.M)}
        if expected != actual:
            raise ValueError("APU instruction-family opcode inventory differs from RTL")
        rows = []
        for opcode in getattr(isa, enum_name):
            sample = legal_sample(isa, family, int(opcode))
            word = sample.encode()
            if isa.Instruction.decode(word) != sample:
                raise ValueError("APU family example failed encode/decode round trip")
            targets = []
            for target in isa.APUMC_TARGETS:
                try:
                    isa.validate_instruction(sample, target)
                    targets.append(target.upper())
                except ValueError:
                    pass
            if family == "CONTROL" and opcode.name == "WAIT":
                targets = []
                for target in isa.APUMC_TARGETS:
                    for wait in range(len(isa.WAIT_SOURCES)):
                        try:
                            isa.validate_instruction(replace(sample, aux=wait), target)
                            targets.append(target.upper())
                            break
                        except ValueError:
                            pass
            # Observe the validator's exact whole-field zero requirements; do
            # not infer a reserved operand from a few rejected sample values.
            reserved = set()
            original_require_zero = isa._require_zero

            def record_zero(instruction, names):
                names = tuple(names)
                reserved.update(names)
                original_require_zero(instruction, names)

            try:
                isa._require_zero = record_zero
                isa.validate_instruction(sample, "p5")
            finally:
                isa._require_zero = original_require_zero
            predicates = []
            for value in range(12):
                try:
                    isa.validate_instruction(replace(sample, predicate=value), "p5")
                    predicates.append(value)
                except ValueError:
                    pass
            fixed = dict.fromkeys(sorted(reserved), 0)
            if predicates == [0]:
                fixed["predicate"] = 0
            active = [field for field in ("predicate", "dst", "src0", "src1", "aux", "immediate") if field not in fixed]
            aliases = {"predicate": "PRED", "dst": "DST", "src0": "S0", "src1": "S1", "aux": "AUX", "immediate": "IMM"}
            rows.append({"name": opcode.name, "opcode": int(opcode), "opcode_hex": f"0x{int(opcode):X}",
                         "active": active, "fixed": fixed, "slots": ", ".join(aliases[key] for key in active) or "None",
                         "targets": "/".join(targets), "predicates": predicates,
                         "zero_slots": ", ".join(aliases[key] for key in fixed) or "None",
                         "required_mask": f"0x{isa.instruction_required_mask(sample):08X}",
                         "word": f"0x{word:016X}", "values": {key: getattr(sample, key) for key in ("instruction_class", "opcode", *aliases)}})
        result.append({"name": family, "class": class_id, "note": note, "operations": rows,
                       "active": sorted({field for row in rows for field in row["active"]}),
                       "example": next((row for row in rows if row["name"] in {"MOVI", "WAIT", "GET", "RICE4", "LD32", "PCM_PACK", "OUTPUT_STREAM"}), rows[0])})
    if len(result) != 7 or sum(len(row["operations"]) for row in result) != 62:
        raise ValueError("APU frozen instruction-family coverage changed")
    return result
