"""APU V1 ABI digest tool: canonical table inventory, serialization, and CRC-32.

Per docs/ip/apu.md (ABI_DIGEST at offset 0x054 and the Phase8 completion
contract) the digest is the nonzero CRC-32 over the complete frozen V1 tables:

- the APB V1 register/field table and the 128-byte job-descriptor layout
  (canonical source rtl/ip/multimedia/apu_define.svh, mirrored by
  crt/include/retrosoc/hal/apu_regs.h; both sides are re-verified equal here),
- the hardware discovery values (IP_ID, IP_VERSION, CAPABILITY0/1, IRQ mask)
  reported by the current release (P7-qualified configuration),
- the format/output-mode/PCM-format/operation identifier tables
  (crt/include/retrosoc/hal/apu.h enums; operation IDs 0/1 are the frozen V1
  contract values of docs/ip/apu.md "Descriptor ABI" and have no named code
  constant),
- the supported APUMC V1/V2 container constants (scripts/apu_isa.py),
- the APUM model container constants (scripts/apu_kws.py),
- the microcode class/opcode/predicate/wait-source/primitive/trap tables, the
  instruction field positions, the entry word layout, and the P3/P4/P5
  primitive masks (scripts/apu_isa.py abi_manifest()),
- the reserved MP3 identifiers: format ID 1, capability bit 1, the three-entry
  APUMC layout whose entry 1 is the unsupported-MP3 trap stub
  (rtl/ip/multimedia/apu_p5_codecs.apus), the trap instruction/detail, and the
  P5 rejection tuple (code 3/stage 2/detail 0x01000001).

The deferred P6 design archive is documentation-only and contributes nothing;
no P6 constant exists in any parsed source.

Serialization (the release identity; keep stable): canonical ASCII JSON with
recursively sorted keys, separators `,` and `:`, no insignificant whitespace,
no terminal newline, and every integer encoded as a JSON decimal number. The
digest is the reflected CRC-32/ISO-HDLC (binascii.crc32, the same variant as
apu_isa.crc32_iso_hdlc) over that complete byte stream.

CLI: default prints the digest and section summary; --check compares the
computed digest against the handwritten rtl/ip/multimedia/apu_reg.sv AbiDigest
localparam and the crt/include/retrosoc/hal/apu_regs.h RS_APU_DIGEST_IMPLEMENTED
define, requiring all three to match and be nonzero; --json PATH dumps the
canonical inventory for review.
"""

from __future__ import annotations

import argparse
import binascii
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

import apu_kws  # noqa: E402
import apu_kws_coeff  # noqa: E402
from apu_isa import (  # noqa: E402
    APUMC_ABI_V2,
    ControlOpcode,
    Entry,
    Instruction,
    InstructionClass,
    abi_manifest,
)

RTL_DEFINE = ROOT / "rtl/ip/multimedia/apu_define.svh"
RTL_REGISTER = ROOT / "rtl/ip/multimedia/apu_reg.sv"
RTL_MICROCODE = ROOT / "rtl/ip/multimedia/apu_p5_codecs.apus"
C_HEADER = ROOT / "crt/include/retrosoc/hal/apu_regs.h"
C_HAL = ROOT / "crt/include/retrosoc/hal/apu.h"

SECTION_ORDER = (
    "discovery",
    "apb",
    "kws_model",
    "formats",
    "apumc",
    "apum",
    "apuc",
    "isa",
    "mp3_stub",
)


def _rtl_defines() -> dict[str, int]:
    """Parse every `define in the canonical hardware/software ABI header."""

    values: dict[str, int] = {}
    pattern = re.compile(
        r"^`define\s+((?:APB4_APU__|RETROSOC_APU_KWS__)\w+)\s+"
        r"((?:\d+)'[hHdDbB][0-9a-fA-F_]+|\d+)\s*$"
    )
    for line in RTL_DEFINE.read_text(encoding="utf-8").splitlines():
        match = pattern.match(line)
        if match is None:
            continue
        name, literal = match.groups()
        if "'" in literal:
            _, value = literal.split("'", maxsplit=1)
            radix = {"h": 16, "d": 10, "b": 2}[value[0].lower()]
            values[name] = int(value[1:].replace("_", ""), radix)
        else:
            values[name] = int(literal, 10)
    return values


def _c_abi_defines() -> dict[str, int]:
    """Parse the handwritten RS_APU_ABI_* mirror of the SVH define file."""

    values: dict[str, int] = {}
    pattern = re.compile(
        r"^#define\s+RS_APU_ABI_(\w+)\s+"
        r"(?:UINT32_C\((0[xX][0-9a-fA-F]+)\)|(\d+)[uU]?)\s*$"
    )
    for line in C_HEADER.read_text(encoding="utf-8").splitlines():
        match = pattern.match(line)
        if match is None:
            continue
        name, hexadecimal, decimal = match.groups()
        values[name] = int(hexadecimal, 16) if hexadecimal is not None else int(decimal, 10)
    return values


def _c_discovery_defines() -> dict[str, int]:
    """Parse the implemented hardware discovery values from the C header."""

    values: dict[str, int] = {}
    pattern = re.compile(
        r"^#define\s+RS_APU_(IP_ID_VALUE|IP_VERSION_VALUE|IRQ_ALL"
        r"|CAPABILITY0_IMPLEMENTED|CAPABILITY0_P7_IMPLEMENTED"
        r"|CAPABILITY1_IMPLEMENTED|CAPABILITY1_P7_IMPLEMENTED)"
        r"\s+UINT32_C\((0[xX][0-9a-fA-F]+)\)\s*$"
    )
    for line in C_HEADER.read_text(encoding="utf-8").splitlines():
        match = pattern.match(line)
        if match is not None:
            values[match.group(1)] = int(match.group(2), 16)
    values["CAPABILITY0_IMPLEMENTED"] = values["CAPABILITY0_P7_IMPLEMENTED"]
    values["CAPABILITY1_IMPLEMENTED"] = values["CAPABILITY1_P7_IMPLEMENTED"]
    return values


def _hex_literal(pattern: str, text: str) -> int:
    match = re.search(pattern, text)
    if match is None:
        raise ValueError(f"pattern not found in {RTL_REGISTER.name}: {pattern}")
    return int(match.group(1).replace("_", ""), 16)


def _rtl_discovery_values() -> dict[str, int]:
    """Extract the release-selected discovery localparams from apu_reg.sv."""

    text = RTL_REGISTER.read_text(encoding="utf-8")
    return {
        "IP_ID_VALUE": _hex_literal(
            r"localparam logic \[31:0\] IpId = 32'h([0-9a-fA-F_]+);", text
        ),
        "IP_VERSION_VALUE": _hex_literal(
            r"localparam logic \[31:0\] IpVersion = EnableP7 \? 32'h([0-9a-fA-F_]+) :",
            text,
        ),
        "CAPABILITY0_IMPLEMENTED": _hex_literal(
            r"localparam logic \[31:0\] Capability0 = EnableP7 \? 32'h([0-9a-fA-F_]+) :",
            text,
        ),
        "CAPABILITY1_IMPLEMENTED": _hex_literal(
            r"localparam logic \[31:0\] Capability1 = \(EnableP5 \|\| EnableP7\) \? "
            r"32'h([0-9a-fA-F_]+) :",
            text,
        ),
        "IRQ_ALL": _hex_literal(
            r"localparam logic \[11:0\] IrqMask = EnableP7 \? 12'h([0-9a-fA-F_]+) :",
            text,
        ),
    }


def _c_enum_values(enum_name: str) -> dict[str, int]:
    """Parse a simple `typedef enum { NAME = n, ... } name;` block from apu.h."""

    text = C_HAL.read_text(encoding="utf-8")
    match = re.search(r"typedef enum \{([^}]*)\}\s+" + enum_name + r"\s*;", text)
    if match is None:
        raise ValueError(f"enum {enum_name} not found in {C_HAL.name}")
    return {
        name: int(value)
        for name, value in re.findall(r"(\w+)\s*=\s*(\d+)\s*,?", match.group(1))
    }


def _manifest_rtl_exact() -> dict[str, int]:
    """Map every apu_isa manifest value to its handwritten SVH define name."""

    manifest = abi_manifest()
    exact = {
        "APUMC_MAGIC": manifest["apumc"]["magic"],
        "APUMC_ABI": manifest["apumc"]["abi"],
        "APUMC_ABI_V1": manifest["apumc"]["abi_v1"],
        "APUMC_ABI_V2": manifest["apumc"]["abi_v2"],
        "APUMC_V1": manifest["apumc"]["abi_v1"],
        "APUMC_V2": manifest["apumc"]["abi_v2"],
        "APUMC_HEADER_BYTES": manifest["apumc"]["header_bytes"],
        "APUMC_ENTRY_BYTES": manifest["apumc"]["entry_bytes"],
        "APUMC_ENTRY_COUNT": manifest["apumc"]["entry_count"],
        "APUMC_MAX_INSTRUCTIONS": manifest["apumc"]["max_instructions"],
        "APUMC_MAX_INSTRUCTIONS_V1": manifest["apumc"]["max_instructions_v1"],
        "APUMC_MAX_INSTRUCTIONS_V2": manifest["apumc"]["max_instructions_v2"],
        "APUMC_P3_PRIMITIVE_MASK": manifest["p3_implemented_primitive_mask"],
        "APUMC_P4_PRIMITIVE_MASK": manifest["p4_implemented_primitive_mask"],
        "APUMC_P5_PRIMITIVE_MASK": manifest["p5_implemented_primitive_mask"],
        "LOCAL_DATA_BYTES": manifest["p4_local_data_bytes"],
        "LOCAL_TABLE_SCRATCH_BYTES": manifest["p4_local_table_scratch_bytes"],
    }
    for name, value in manifest["classes"].items():
        exact[f"MC_CLASS_{name.upper()}"] = value
    for name, value in manifest["control_opcodes"].items():
        exact[f"MC_CONTROL_{name.upper()}"] = value
    for name, value in manifest["scalar_opcodes"].items():
        exact[f"MC_SCALAR_{name.upper()}"] = value
    for class_name, opcodes in manifest["deferred_opcodes"].items():
        for name, value in opcodes.items():
            exact[f"MC_{class_name.upper()}_{name.upper()}"] = value
    predicate_names = {
        "always": "ALWAYS",
        "eq": "EQ",
        "ne": "NE",
        "slt": "SIGNED_LT",
        "sge": "SIGNED_GE",
        "ult": "UNSIGNED_LT",
        "uge": "UNSIGNED_GE",
        "input_exhausted": "INPUT_EXHAUSTED",
        "input_ready": "INPUT_READY",
        "output_ready": "OUTPUT_READY",
        "kernel_done": "KERNEL_DONE",
        "transport_done": "TRANSPORT_DONE",
    }
    for name, value in manifest["predicates"].items():
        exact[f"MC_PRED_{predicate_names[name]}"] = value
    for name, value in manifest["wait_sources"].items():
        exact[f"MC_WAIT_{name.upper()}"] = value
    for name, value in manifest["primitives"].items():
        exact[f"MC_PRIMITIVE_{name.upper()}"] = value
    for name, value in manifest["instruction_fields"].items():
        exact[f"MC_INSTRUCTION_{name.upper()}"] = value
    for name, value in manifest["entry_words"].items():
        exact[f"APUMC_ENTRY_{name.upper()}"] = value
    trap_names = {
        "illegal": "ILLEGAL",
        "pc_range": "PC_RANGE",
        "call_stack": "CALL_STACK",
        "loop": "LOOP",
        "local_range": "LOCAL_RANGE",
        "unavailable": "UNAVAILABLE",
        "watchdog": "WATCHDOG",
        "retired_budget": "RETIRED_BUDGET",
        "engine": "ENGINE",
        "explicit": "EXPLICIT",
    }
    for name, value in manifest["trap_reasons"].items():
        if name != "reserved":
            exact[f"MC_TRAP_{trap_names[name]}"] = value
    return exact


def _require_equal(what: str, left: dict[str, int], right: dict[str, int]) -> None:
    if left != right:
        only_left = sorted(set(left) - set(right))
        only_right = sorted(set(right) - set(left))
        differ = sorted(key for key in set(left) & set(right) if left[key] != right[key])
        raise ValueError(f"{what} drift: only-left {only_left}, only-right {only_right}, "
                         f"differing {[(key, left[key], right[key]) for key in differ]}")


def _mp3_stub_section(apb: dict[str, int]) -> dict[str, int]:
    """Reconstruct the reserved-MP3 APUMC stub contract from the released image."""

    lines = RTL_MICROCODE.read_text(encoding="utf-8").splitlines()
    entry_lines = [line for line in lines if line.startswith(".entry ")]
    if len(entry_lines) != 3:
        raise ValueError(f"{RTL_MICROCODE.name} must declare exactly three .entry lines")
    mp3_tokens = entry_lines[1].split()
    if mp3_tokens[:5] != [".entry", "1", "mp3", "mp3", "mp3"]:
        raise ValueError(f"unexpected MP3 entry directive: {entry_lines[1]}")
    numbers = [int(token, 0) for token in mp3_tokens[5:]]
    if numbers != [1, 1, 0, 0, 0, 0, 0]:
        raise ValueError(f"unexpected MP3 stub entry fields: {entry_lines[1]}")
    try:
        label_index = lines.index("mp3:")
    except ValueError as error:
        raise ValueError("mp3 label missing from released microcode image") from error
    body = [line.strip() for line in lines[label_index + 1:] if line.strip()]
    trap_match = re.fullmatch(r"trap 0x([0-9a-fA-F]+)", body[0])
    if trap_match is None:
        raise ValueError(f"mp3 label must be followed by its trap stub, found: {body[0]}")
    trap_detail = int(trap_match.group(1), 16)
    if trap_detail != 0x01000001:
        raise ValueError(f"unexpected MP3 stub trap detail 0x{trap_detail:08x}")

    stub = Entry(
        format_id=1,
        entry_pc=0,
        first_pc=0,
        last_pc=0,
        max_loop_count=numbers[0],
        max_retired=numbers[1],
        scratch_base=numbers[2],
        scratch_bytes=numbers[3],
        primitive_mask=numbers[4],
        table_offset=numbers[5],
        table_bytes=numbers[6],
    )
    words = stub.words(APUMC_ABI_V2)
    if words != (0x00000001, 0, 0, 0, 1, 1, 0, 0):
        raise ValueError(f"MP3 stub entry words drifted: {[hex(word) for word in words]}")
    trap_instruction = Instruction(
        instruction_class=int(InstructionClass.CONTROL),
        opcode=int(ControlOpcode.TRAP),
        immediate=trap_detail,
    ).encode()
    if trap_instruction != 0x0200000001000001:
        raise ValueError(f"MP3 stub trap instruction drifted: 0x{trap_instruction:016x}")

    section = {
        "format_id": 1,
        "capability_bit": apb["CAPABILITY0_MP3"],
        "entry_count": apb["APUMC_ENTRY_COUNT"],
        "entry_index": 1,
        "trap_instruction": trap_instruction,
        "trap_detail": trap_detail,
        "rejection_error_code": apb["ERROR_CODE_UNSUPPORTED"],
        "rejection_error_stage": apb["ERROR_STAGE_RING"],
        "rejection_detail": trap_detail,
    }
    for index, word in enumerate(words):
        section[f"entry_words[{index}]"] = word
    return section


def canonical_inventory() -> dict[str, dict[str, int]]:
    """Build the complete frozen V1 table inventory, failing on any drift."""

    rtl = _rtl_defines()
    apb = {
        name.removeprefix("APB4_APU__"): value
        for name, value in rtl.items()
        if name.startswith("APB4_APU__")
    }
    kws_model = {
        name.removeprefix("RETROSOC_APU_KWS__"): value
        for name, value in rtl.items()
        if name.startswith("RETROSOC_APU_KWS__")
    }
    _require_equal("APB define/C mirror", apb, _c_abi_defines())
    _require_equal("ISA manifest/SVH", _manifest_rtl_exact(),
                   {name: apb[name] for name in _manifest_rtl_exact()})
    _require_equal(
        "APUM container/SVH",
        {
            "APUM_MAGIC": apu_kws.APUM_MAGIC,
            "APUM_ABI": apu_kws.APUM_ABI,
            "APUM_IMAGE_BYTES": apu_kws.APUM_BYTES,
            "APUM_PAYLOAD_CRC": apu_kws.APUM_PAYLOAD_CRC,
        },
        {name: apb[name] for name in ("APUM_MAGIC", "APUM_ABI", "APUM_IMAGE_BYTES",
                                      "APUM_PAYLOAD_CRC")},
    )
    _require_equal(
        "APUC container/SVH",
        {
            "APUC_MAGIC": apu_kws_coeff.APUC_MAGIC,
            "APUC_ABI": apu_kws_coeff.APUC_ABI,
            "APUC_IMAGE_BYTES": apu_kws_coeff.APUC_BYTES,
            "APUC_HEADER_BYTES": apu_kws_coeff.APUC_HEADER_BYTES,
            "APUC_PAYLOAD_BYTES": apu_kws_coeff.APUC_PAYLOAD_BYTES,
            "APUC_PAYLOAD_CRC": apu_kws_coeff.APUC_PAYLOAD_CRC,
            "APUC_COEFFICIENT_ID_LO": apu_kws_coeff.APUC_COEFFICIENT_ID[0],
            "APUC_COEFFICIENT_ID_HI": apu_kws_coeff.APUC_COEFFICIENT_ID[1],
        },
        {
            name: apb[name]
            for name in (
                "APUC_MAGIC",
                "APUC_ABI",
                "APUC_IMAGE_BYTES",
                "APUC_HEADER_BYTES",
                "APUC_PAYLOAD_BYTES",
                "APUC_PAYLOAD_CRC",
                "APUC_COEFFICIENT_ID_LO",
                "APUC_COEFFICIENT_ID_HI",
            )
        },
    )
    discovery_c = _c_discovery_defines()
    discovery_rtl = _rtl_discovery_values()
    _require_equal("discovery C/RTL", discovery_rtl,
                   {name: discovery_c[name] for name in discovery_rtl})

    formats = {name.lower().removeprefix("rs_apu_"): value
               for name, value in _c_enum_values("rs_apu_format_t").items()}
    output_modes = {name.lower().removeprefix("rs_apu_"): value
                    for name, value in _c_enum_values("rs_apu_output_t").items()}
    pcm_formats = {name.lower().removeprefix("rs_apu_"): value
                   for name, value in _c_enum_values("rs_apu_pcm_t").items()}
    _require_equal(
        "format ID/capability bit",
        {name: formats[name] for name in ("wav", "mp3", "flac")},
        {name: apb[f"CAPABILITY0_{name.upper()}"] for name in ("wav", "mp3", "flac")},
    )

    manifest = abi_manifest()
    isa: dict[str, int] = {}
    for group in ("classes", "control_opcodes", "scalar_opcodes", "predicates",
                  "wait_sources", "primitives", "trap_reasons", "instruction_fields",
                  "entry_words"):
        for name, value in manifest[group].items():
            isa[f"{group}.{name}"] = value
    for class_name, opcodes in manifest["deferred_opcodes"].items():
        for name, value in opcodes.items():
            isa[f"deferred_opcodes.{class_name}.{name}"] = value
    for phase in ("p3", "p4", "p5"):
        isa[f"implemented_primitive_mask.{phase}"] = manifest[
            f"{phase}_implemented_primitive_mask"]
    isa["local_memory.p4_data_bytes"] = manifest["p4_local_data_bytes"]
    isa["local_memory.p4_table_scratch_bytes"] = manifest["p4_local_table_scratch_bytes"]

    apumc = {name: value for name, value in manifest["apumc"].items()}
    apum = {
        "magic": apu_kws.APUM_MAGIC,
        "abi": apu_kws.APUM_ABI,
        "image_bytes": apu_kws.APUM_BYTES,
        "header_bytes": apu_kws.APUM_HEADER_BYTES,
        "operator_offset": apu_kws.APUM_OPERATOR_OFFSET,
        "operator_count": apu_kws.APUM_OPERATOR_COUNT,
        "operator_bytes": apu_kws.APUM_OPERATOR_BYTES,
        "tensor_offset": apu_kws.APUM_TENSOR_OFFSET,
        "tensor_count": apu_kws.APUM_TENSOR_COUNT,
        "tensor_bytes": apu_kws.APUM_TENSOR_BYTES,
        "parameter_offset": apu_kws.APUM_PARAMETER_OFFSET,
        "parameter_bytes": apu_kws.APUM_PARAMETER_BYTES,
        "parameter_end": apu_kws.APUM_PARAMETER_END,
        "payload_crc": apu_kws.APUM_PAYLOAD_CRC,
    }
    apuc = {
        "magic": apu_kws_coeff.APUC_MAGIC,
        "abi": apu_kws_coeff.APUC_ABI,
        "image_bytes": apu_kws_coeff.APUC_BYTES,
        "header_bytes": apu_kws_coeff.APUC_HEADER_BYTES,
        "payload_bytes": apu_kws_coeff.APUC_PAYLOAD_BYTES,
        "profile": apu_kws_coeff.APUC_PROFILE,
        "layout_id": apu_kws_coeff.APUC_LAYOUT_ID,
        "bank_count": apu_kws_coeff.APUC_BANK_COUNT,
        "table_count": apu_kws_coeff.APUC_TABLE_COUNT,
        "payload_crc": apu_kws_coeff.APUC_PAYLOAD_CRC,
        "coefficient_id_low": apu_kws_coeff.APUC_COEFFICIENT_ID[0],
        "coefficient_id_high": apu_kws_coeff.APUC_COEFFICIENT_ID[1],
        "associated_apum_crc": apu_kws_coeff.APUC_APUM_PAYLOAD_CRC,
        "ln2_q24": apu_kws_coeff.APUC_LN2_Q24,
    }

    discovery = {
        "ip_id": discovery_c["IP_ID_VALUE"],
        "ip_version": discovery_c["IP_VERSION_VALUE"],
        "capability0": discovery_c["CAPABILITY0_IMPLEMENTED"],
        "capability0_p7": discovery_c["CAPABILITY0_P7_IMPLEMENTED"],
        "capability1": discovery_c["CAPABILITY1_IMPLEMENTED"],
        "capability1_p7": discovery_c["CAPABILITY1_P7_IMPLEMENTED"],
        "irq_all": discovery_c["IRQ_ALL"],
    }
    format_section = {f"format.{name}": value for name, value in formats.items()}
    format_section.update({f"output_mode.{name}": value
                           for name, value in output_modes.items()})
    format_section.update({f"pcm_format.{name}": value
                           for name, value in pcm_formats.items()})
    format_section["operation.file_decode"] = 0
    format_section["operation.kws_memory_window"] = 1

    inventory = {
        "discovery": discovery,
        "apb": apb,
        "kws_model": kws_model,
        "formats": format_section,
        "apumc": apumc,
        "apum": apum,
        "apuc": apuc,
        "isa": isa,
        "mp3_stub": _mp3_stub_section(apb),
    }
    if tuple(inventory) != SECTION_ORDER:
        raise ValueError("section order drift")
    return inventory


def serialize_inventory(inventory: dict[str, dict[str, int]]) -> bytes:
    """Serialize the inventory to the documented release-identity byte stream."""

    return json.dumps(
        inventory,
        ensure_ascii=True,
        separators=(",", ":"),
        sort_keys=True,
    ).encode("ascii")


def compute_abi_digest() -> int:
    """Return the CRC-32/ISO-HDLC digest over the serialized V1 tables."""

    return binascii.crc32(serialize_inventory(canonical_inventory())) & 0xFFFFFFFF


def rtl_implemented_digest() -> int:
    """Extract the handwritten AbiDigest localparam from apu_reg.sv."""

    text = RTL_REGISTER.read_text(encoding="utf-8")
    match = re.search(
        r"localparam logic \[31:0\] AbiDigest = EnableP7 \? "
        r"32'h([0-9a-fA-F_]+) : 32'd0;",
        text,
    )
    if match is None:
        raise ValueError(f"AbiDigest localparam not found in {RTL_REGISTER.name}")
    return int(match.group(1).replace("_", ""), 16)


def c_implemented_digest() -> int:
    """Extract the handwritten P9 release digest from apu_regs.h."""

    text = C_HEADER.read_text(encoding="utf-8")
    match = re.search(
        r"^#define\s+RS_APU_DIGEST_P9_IMPLEMENTED\s+UINT32_C\((0[xX][0-9a-fA-F]+)\)\s*$",
        text,
        re.MULTILINE,
    )
    if match is None:
        raise ValueError(f"RS_APU_DIGEST_P9_IMPLEMENTED not found in {C_HEADER.name}")
    return int(match.group(1), 16)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--check", action="store_true",
                        help="require RTL/C handwritten constants to match the computed digest")
    parser.add_argument("--json", metavar="PATH",
                        help="dump the canonical inventory as JSON for review")
    args = parser.parse_args(argv)

    try:
        inventory = canonical_inventory()
        digest = binascii.crc32(serialize_inventory(inventory)) & 0xFFFFFFFF
    except ValueError as error:
        print(f"apu_abi_digest: error: {error}", file=sys.stderr)
        return 1

    if args.json is not None:
        payload = {
            "digest": f"0x{digest:08x}",
            "serialization": "canonical ASCII JSON; recursively sorted keys; compact "
                             "separators; decimal integers; no terminal newline; "
                             "CRC-32/ISO-HDLC",
            "sections": {
                name: {key: f"0x{value:016x}" for key, value in sorted(entries.items())}
                for name, entries in inventory.items()
            },
        }
        Path(args.json).write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
        print(f"wrote canonical inventory to {args.json}")

    print(f"0x{digest:08x}")
    for name in SECTION_ORDER:
        print(f"  {name}: {len(inventory[name])} entries")
    print(f"  serialized: {len(serialize_inventory(inventory))} bytes")

    if args.check:
        try:
            rtl_digest = rtl_implemented_digest()
            c_digest = c_implemented_digest()
        except ValueError as error:
            print(f"apu_abi_digest: error: {error}", file=sys.stderr)
            return 1
        ok = digest != 0 and rtl_digest == digest and c_digest == digest
        print(f"  computed:   0x{digest:08x}")
        print(f"  apu_reg.sv: 0x{rtl_digest:08x}")
        print(f"  apu_regs.h: 0x{c_digest:08x}")
        if not ok:
            print("apu_abi_digest: FAIL: digest mismatch or zero digest", file=sys.stderr)
            return 1
        print("apu_abi_digest: OK: computed digest matches both handwritten constants")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
