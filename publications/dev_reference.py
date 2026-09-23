"""Snapshot-bound publication facts; compilation is distinct from hardware qualification."""
from __future__ import annotations

from datetime import date
import json
from pathlib import Path
import re
import subprocess
import sys

from publications.storage_reference import constants
from publications.waveform_reference import uncomment

APU_SOURCES = (
    "scripts/apu_mcasm.py", "scripts/apu_isa.py", "scripts/apu_p5_coefficients.py",
    "scripts/apu_kws.py", "scripts/build_apu_p5_bundle.py",
    "rtl/ip/multimedia/apu_p5_codecs.apus", "rtl/ip/multimedia/apu_define.svh",
    "rtl/ip/multimedia/apb4_apu.sv", "rtl/ip/multimedia/apu_local_sram.sv",
    "rtl/ip/multimedia/apu_kws_sram_client.sv",
    "rtl/ip/multimedia/apu_reg.sv", "crt/include/retrosoc/hal/apu_regs.h",
    "configs/ci/ihp130-apu.mk", "Makefile", "scripts/apu_abi_digest.py",
)

NPU_SOURCES = (
    "rtl/ip/multimedia/npu_pkg.sv", "rtl/ip/multimedia/npu_define.svh",
    "rtl/ip/multimedia/npu_reg.sv", "rtl/ip/multimedia/apb4_npu.sv",
    "rtl/ip/multimedia/npu_scheduler.sv", "rtl/ip/multimedia/npu_job_decoder.sv",
    "rtl/ip/multimedia/npu_local_sram.sv", "rtl/ip/multimedia/npu_accumulator.sv",
    "crt/include/retrosoc/hal/npu.h", "crt/include/retrosoc/hal/npu_regs.h", "crt/src/hal/npu.c",
    "scripts/npu_descriptors.py", "scripts/npu_compiler.py", "scripts/npu_compiler_p0.py",
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
        status, conclusion = run.get("status"), run.get("conclusion")
        if status not in {"queued", "in_progress", "completed", "waiting", "requested", "pending"}:
            raise ValueError("invalid CI run status")
        if status == "completed":
            if conclusion not in {"success", "failure", "cancelled", "skipped", "timed_out", "neutral", "action_required", "stale", "startup_failure"}:
                raise ValueError("invalid completed CI outcome")
        elif conclusion is not None:
            raise ValueError("unfinished CI run cannot have a conclusion")
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
    regs = uncomment((root / "rtl/ip/multimedia/apu_reg.sv").read_text(encoding="utf-8"))
    values = constants(root, "crt/include/retrosoc/hal/apu_regs.h")
    p5 = re.findall(r"P5Capability0\s*=\s*EnableP5\s*\?\s*32'h([\da-fA-F_]+)", regs)
    p7 = re.findall(r"\bCapability0\s*=\s*EnableP7\s*\?\s*32'h([\da-fA-F_]+)\s*:\s*P5Capability0", regs)
    digest = re.findall(r"AbiDigest\s*=\s*EnableP7\s*\?\s*32'h([\da-fA-F_]+)\s*:\s*32'd0", regs)
    if len(p5) != 1 or len(p7) != 1 or len(digest) != 1:
        raise ValueError("APU configured capability/digest selection changed")
    result["profiles"] = [
        {"name": "Default PRODUCT", "profile": "configs/ci/ihp130.mk", "enabled": False,
         "capability": int(p5[0].replace("_", ""), 16), "digest": 0},
        {"name": "P7 acceptance", "profile": "configs/ci/ihp130-apu.mk", "enabled": True,
         "capability": int(p7[0].replace("_", ""), 16), "digest": int(digest[0].replace("_", ""), 16)},
    ]
    if [(r["capability"], r["digest"]) for r in result["profiles"]] != [(0x1BD, 0), (0x1FD, 0xF5005D7C)]:
        raise ValueError("review APU configuration identities")
    if (values.get("RS_APU_DIGEST_P7_IMPLEMENTED"), values.get("RS_APU_CAPABILITY0_P5_IMPLEMENTED"),
            values.get("RS_APU_CAPABILITY0_P7_IMPLEMENTED")) != (0xF5005D7C, 0x1BD, 0x1FD):
        raise ValueError("APU published digest differs from the HAL")
    if not re.search(r"APU_ENABLE_P7\s*:=\s*YES", (root / "configs/ci/ihp130-apu.mk").read_text()):
        raise ValueError("APU acceptance profile no longer enables P7")
    result["qualification"] = "Static assembly and source inspection only; no codec corpus, KWS accuracy or physical qualification."
    return result


def npu_implementation(root: Path) -> dict:
    """Read deployed parameters, not the dormant defaults of reusable modules."""
    values = constants(root, "rtl/ip/multimedia/npu_define.svh")
    geometry = constants(root, "rtl/ip/multimedia/npu_pkg.sv")
    reg = uncomment((root / "rtl/ip/multimedia/npu_reg.sv").read_text(encoding="utf-8"))
    top = uncomment((root / "rtl/ip/multimedia/apb4_npu.sv").read_text(encoding="utf-8"))
    if not re.search(r"ExecutionReady\s*=\s*1'b1", reg) or not re.search(r"\.ExecutionReady\s*\(1'b1\)", top):
        raise ValueError("NPU publication requires the deployed execution path")
    burst = re.findall(r"\.MaxBurstBeats\s*\((\d+)\)", top)
    if burst != ["8"]:
        raise ValueError("NPU integrated DMA burst limit changed")
    result = {key: values["APB4_NPU__" + name] for key, name in {
        "ip_id": "IP_ID_VALUE", "version": "IP_VERSION_VALUE", "capability": "CAPABILITY_P4",
        "op_mask": "OP_CAPABILITY_VALUE", "numeric_profile": "NUMERIC_PROFILE_VALUE",
        "descriptor_bytes": "DESCRIPTOR_BYTES_VALUE", "local_bytes": "LOCAL_BYTES_VALUE",
        "max_dimension": "MAX_DIMENSION_VALUE", "max_k_slice": "MAX_K_SLICE_VALUE"}.items()}
    result.update(dense_macs=geometry["DenseMacCount"], depthwise_macs=geometry["DepthwiseLanes"],
                  bank_count=geometry["BankCount"], bank_bytes=geometry["BankBytes"],
                  accumulator_contexts=geometry["AccContextCount"], accumulator_bytes=geometry["AccSumCount"] * 4,
                  max_burst_beats=int(burst[0]), geometry=geometry)
    if (result["capability"], result["op_mask"], result["local_bytes"], result["descriptor_bytes"]) != (0x7F, 0x1FE, 65536, 128):
        raise ValueError("review published NPU execution/ABI capabilities")
    if geometry["LocalBytes"] != result["local_bytes"]:
        raise ValueError("NPU scratch geometry differs from capability")
    return result


def validate_accelerator_claims(reference: dict, catalog: list, features: dict, content: dict,
                                annotations: dict, profiles: dict) -> None:
    """Reject stale live prose that declaration/port extraction cannot detect."""
    npu = reference["npu_implementation"]
    if npu["capability"] & 2:
        texts = [row["summary"] for row in catalog if row["id"] == "npu"]
        texts += features["npu"] + content["npu"]["notes"]
        texts += [row.get("qualification", "") for row in reference["retrieval"]["instances"]
                  if "npu" in json.dumps(row).lower()]
        texts += [json.dumps(annotations["npu"]), json.dumps(profiles["npu"])]
        stale = (r"phase 2.*(?:shell only|control shell)|p2 apb4 control shell|master is tied safely idle|"
                 r"execution_ready.*stay.*clear|no execution readiness|P2 never runs a job|"
                 r"implemented and verified|passed differential evidence")
        if any(re.search(stale, text, re.I) for text in texts):
            raise ValueError("NPU live publication claims contradict enabled execution")
    for text in features["apu"] + content["apu"]["notes"]:
        if (re.search(r"MP3(?: and |/)KWS.*not advertised", text, re.I)
                and not re.search(r"default|P7|configuration", text, re.I)):
            raise ValueError("APU publication loses the configured KWS distinction")
