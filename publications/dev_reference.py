"""Snapshot-bound publication facts; compilation is distinct from hardware qualification."""
from __future__ import annotations

from datetime import date
import json
from pathlib import Path
import re
import subprocess
import sys

from publications.storage_reference import constants

APU_SOURCES = (
    "scripts/apu_mcasm.py", "scripts/apu_isa.py", "scripts/apu_p5_coefficients.py",
    "scripts/apu_kws.py", "scripts/build_apu_p5_bundle.py",
    "rtl/ip/multimedia/apu_p5_codecs.apus", "rtl/ip/multimedia/apu_define.svh",
    "rtl/ip/multimedia/apb4_apu.sv", "rtl/ip/multimedia/apu_local_sram.sv",
    "rtl/ip/multimedia/apu_kws_sram_client.sv",
)


def validate_ci_snapshot(snapshot: dict, revision: str) -> None:
    if snapshot.get("revision") != revision or not snapshot.get("boundary"):
        raise ValueError("CI snapshot must identify the reviewed revision and evidence boundary")
    date.fromisoformat(snapshot["checked_date"])
    ids = set()
    for run in snapshot["runs"]:
        identifier = run["run_id"]
        if type(identifier) is not int or identifier < 1 or identifier in ids:
            raise ValueError("invalid or duplicate CI run")
        ids.add(identifier)
        if run["result"] not in {"success", "failure", "cancelled", "skipped"}:
            raise ValueError("invalid CI outcome")
        if run["url"] != f"https://github.com/retroSoC/retroSoC/actions/runs/{identifier}":
            raise ValueError("CI run URL does not match its recorded identifier")
        if not all(run.get(key) for key in ("name", "scope", "note")):
            raise ValueError("CI outcome lacks scope or qualification")


def apu_implementation(root: Path) -> dict:
    """Use the checked-in assembler in isolation; do not execute codec or KWS hardware."""
    program = """
import hashlib,json
from pathlib import Path
from apu_mcasm import assemble
from apu_p5_coefficients import coefficient_bytes
import apu_kws
coefficients=coefficient_bytes()
assembly=assemble(Path('../rtl/ip/multimedia/apu_p5_codecs.apus').read_text(encoding='utf-8'),'p5',coefficients)
print(json.dumps({'abi':assembly.mc_abi,'instruction_words':len(assembly.instructions),
 'bundle_bytes':len(assembly.bundle),'table_bytes':len(coefficients),
 'bundle_sha256':hashlib.sha256(assembly.bundle).hexdigest(),
 'entry_formats':[entry.format_id for entry in assembly.entries],
 'kws_model_bytes':apu_kws.APUM_BYTES,'kws_header_bytes':apu_kws.APUM_HEADER_BYTES,
 'kws_operators':apu_kws.APUM_OPERATOR_COUNT,'kws_tensors':apu_kws.APUM_TENSOR_COUNT,
 'kws_parameter_bytes':apu_kws.APUM_PARAMETER_BYTES}))
"""
    result = json.loads(subprocess.check_output(
        [sys.executable, "-X", "utf8", "-c", program], cwd=root / "scripts", text=True, encoding="utf-8",
    ))
    values = constants(root, "rtl/ip/multimedia/apu_define.svh")
    result["maximum_instruction_words"] = values["APB4_APU__APUMC_MAX_INSTRUCTIONS_V2"]
    result["free_instruction_words"] = result["maximum_instruction_words"] - result["instruction_words"]
    if result["free_instruction_words"] < 0:
        raise ValueError("checked-in codec source exceeds the implemented control store")
    source = (root / "rtl/ip/multimedia/apb4_apu.sv").read_text(encoding="utf-8")
    enabled = re.findall(r"parameter\s+bit\s+EnableP7\s*=\s*1'b([01])", source)
    if len(enabled) != 1:
        raise ValueError("APU P7 default parameter is missing or ambiguous")
    result["p7_default_enabled"] = enabled[0] == "1"
    result["qualification"] = "Static assembly and source inspection only; no codec corpus, KWS accuracy or physical qualification."
    return result
