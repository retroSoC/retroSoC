"""Snapshot-bound publication facts; compilation is distinct from hardware qualification."""
from __future__ import annotations

from datetime import date, datetime
import json
from pathlib import Path
import re
import subprocess
import sys

from publications.storage_reference import constants
from publications.software_reference import function_body
from publications.waveform_reference import uncomment

APU_CONFIGURATION_SOURCES = (
    "Makefile", "configs/ci/ihp130.mk", "configs/ci/ihp130-apu.mk",
    "rtl/mini/top/retrosoc.sv", "rtl/mini/top/apb4_periph.sv",
    "rtl/ip/multimedia/apb4_apu.sv", "rtl/ip/multimedia/apu_reg.sv",
    "rtl/ip/multimedia/apu_define.svh", "crt/include/retrosoc/hal/apu_regs.h",
)

APU_SOURCES = (
    "scripts/apu_mcasm.py", "scripts/apu_isa.py", "scripts/apu_p5_coefficients.py",
    "scripts/apu_kws.py", "scripts/build_apu_p5_bundle.py",
    "rtl/ip/multimedia/apu_p5_codecs.apus", "rtl/ip/multimedia/apu_define.svh",
    "rtl/ip/multimedia/apb4_apu.sv", "rtl/ip/multimedia/apu_local_sram.sv",
    "rtl/ip/multimedia/apu_kws_sram_client.sv",
    "rtl/ip/multimedia/apu_reg.sv", "crt/include/retrosoc/hal/apu_regs.h",
    "scripts/apu_abi_digest.py", "app/apps/apu_release/main.c",
    *APU_CONFIGURATION_SOURCES,
)

NPU_SOURCES = (
    "rtl/ip/multimedia/npu_pkg.sv", "rtl/ip/multimedia/npu_define.svh",
    "rtl/ip/multimedia/npu_reg.sv", "rtl/ip/multimedia/apb4_npu.sv",
    "rtl/ip/multimedia/npu_scheduler.sv", "rtl/ip/multimedia/npu_job_decoder.sv",
    "rtl/ip/multimedia/npu_local_sram.sv", "rtl/ip/multimedia/npu_accumulator.sv",
    "crt/include/retrosoc/hal/npu.h", "crt/include/retrosoc/hal/npu_regs.h", "crt/src/hal/npu.c",
    "scripts/npu_descriptors.py", "scripts/npu_compiler.py", "scripts/npu_compiler_p0.py",
)


def validate_ci_state(record: dict, subject: str) -> None:
    status, conclusion = record.get("status"), record.get("conclusion")
    if status not in {"queued", "in_progress", "completed", "waiting", "requested", "pending"}:
        raise ValueError(f"invalid {subject} status")
    if status == "completed":
        if conclusion not in {"success", "failure", "cancelled", "skipped", "timed_out", "neutral", "action_required", "stale", "startup_failure"}:
            raise ValueError(f"invalid completed {subject} outcome")
    elif conclusion is not None:
        raise ValueError(f"unfinished {subject} cannot have a conclusion")


def validate_ci_snapshot(snapshot: dict, revision: str) -> None:
    if snapshot.get("revision") != revision or not snapshot.get("boundary"):
        raise ValueError("CI snapshot must identify the reviewed revision and evidence boundary")
    date.fromisoformat(snapshot["checked_date"])
    checked_at = snapshot.get("checked_at", "")
    if not re.fullmatch(r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z", checked_at):
        raise ValueError("CI snapshot requires an exact UTC sampling time")
    datetime.strptime(checked_at, "%Y-%m-%dT%H:%M:%SZ")
    if checked_at[:10] != snapshot["checked_date"]:
        raise ValueError("CI snapshot date differs from its UTC sampling time")
    ids = set()
    for run in snapshot["runs"]:
        identifier = run["run_id"]
        if type(identifier) is not int or identifier < 1 or identifier in ids:
            raise ValueError("invalid or duplicate CI run")
        ids.add(identifier)
        validate_ci_state(run, "CI run")
        if run["url"] != f"https://github.com/retroSoC/retroSoC/actions/runs/{identifier}":
            raise ValueError("CI run URL does not match its recorded identifier")
        if not all(run.get(key) for key in ("name", "scope", "note")):
            raise ValueError("CI outcome lacks scope or qualification")
        for stage in run.get("observations", []):
            validate_ci_state(stage, "CI stage")
            if not stage.get("name") or stage.get("scope") not in {
                "installation", "environment-check", "runtime-regression"
            }:
                raise ValueError("CI stage lacks its installation/check/runtime boundary")
            if not re.fullmatch(re.escape(run["url"]) + r"/job/\d+", stage.get("url", "")):
                raise ValueError("CI stage URL does not belong to its recorded run")


def apu_configurations(root: Path) -> list[dict]:
    """Follow the committed Make selection through deployed instance parameters."""
    def read(path: str) -> str:
        return uncomment((root / path).read_text(encoding="utf-8"))

    def parameter(source: str, module: str, instance: str, name: str) -> str:
        blocks = re.findall(r"\b" + re.escape(module) + r"\s*#\((.*?)\)\s*"
                            + re.escape(instance) + r"\s*\(", source, re.S)
        values = re.findall(r"\." + re.escape(name) + r"\s*\(([^()]*)\)", blocks[0]) if len(blocks) == 1 else []
        if len(values) != 1:
            raise ValueError(f"APU deployed parameter missing or ambiguous: {instance}.{name}")
        return re.sub(r"\s+", "", values[0])

    make = (root / "Makefile").read_text(encoding="utf-8")
    defaults = re.findall(r"^APU_ENABLE_P7\s*\?=\s*(YES|NO)\s*$", make, re.M)
    if len(defaults) != 1 or not re.search(
            r"ifeq\s*\(\$\(APU_ENABLE_P7\),\s*YES\)\s*DEF_LIST\s*\+=\s*\+define\+APU_ENABLE_P7\s*endif", make):
        raise ValueError("APU P7 Make selection changed")
    soc = read("rtl/mini/top/retrosoc.sv")
    if not re.search(r"`ifdef\s+APU_ENABLE_P7\s+localparam\s+bit\s+ApuEnableP7\s*=\s*1'b1\s*;\s*"
                     r"`else\s+localparam\s+bit\s+ApuEnableP7\s*=\s*1'b0\s*;\s*`endif", soc):
        raise ValueError("APU P7 top-level selection changed")
    peripheral = read("rtl/mini/top/apb4_periph.sv")
    top = read("rtl/ip/multimedia/apb4_apu.sv")
    if (parameter(soc, "apb4_periph", "u_apb4_periph", "EnableP7") != "ApuEnableP7"
            or parameter(peripheral, "apb4_apu", "u_apb4_apu", "EnableP7") != "EnableP7"
            or parameter(top, "apu_reg", "u_apu_reg", "EnableP7") != "EnableP7"):
        raise ValueError("APU P7 deployed propagation changed")
    for module, instance in (("apu_reg", "u_apu_reg"), ("apu_microcode_loader", "u_microcode_loader"),
                             ("apu_codec_sequencer", "u_codec_sequencer")):
        if parameter(top, module, instance, "EnableP5") != "1'b1":
            raise ValueError("APU deployed WAV/FLAC EnableP5 path changed")

    regs = read("rtl/ip/multimedia/apu_reg.sv")
    p5 = re.findall(r"P5Capability0\s*=\s*EnableP5\s*\?\s*32'h([\da-fA-F_]+)", regs)
    p7 = re.findall(r"\bCapability0\s*=\s*EnableP7\s*\?\s*32'h([\da-fA-F_]+)\s*:\s*P5Capability0", regs)
    digest = re.findall(r"AbiDigest\s*=\s*EnableP7\s*\?\s*32'h([\da-fA-F_]+)\s*:\s*32'd0", regs)
    if len(p5) != 1 or len(p7) != 1 or len(digest) != 1:
        raise ValueError("APU configured capability/digest selection changed")
    bits = constants(root, "rtl/ip/multimedia/apu_define.svh")
    rows = []
    for name, profile in (("Default PRODUCT", "configs/ci/ihp130.mk"),
                          ("P7 acceptance", "configs/ci/ihp130-apu.mk")):
        source = (root / profile).read_text(encoding="utf-8")
        assignments = re.findall(r"^APU_ENABLE_P7\s*[:?+]?=\s*([^\n#]+)", source, re.M)
        if len(assignments) > 1 or (assignments and assignments[0].strip() not in {"YES", "NO"}):
            raise ValueError("APU publication requires a literal committed P7 selection")
        enabled = (assignments[0].strip() if assignments else defaults[0]) == "YES"
        capability = int((p7 if enabled else p5)[0].replace("_", ""), 16)
        rows.append({"name": name, "profile": profile, "enabled": enabled,
                     "capability": capability, "digest": int(digest[0].replace("_", ""), 16) if enabled else 0,
                     "formats": {codec: bool(capability & (1 << bits["APB4_APU__CAPABILITY0_" + codec]))
                                 for codec in ("WAV", "FLAC", "MP3", "KWS")}})
        if rows[-1]["formats"] != {"WAV": True, "FLAC": True, "MP3": False, "KWS": enabled}:
            raise ValueError("APU deployed format capability meanings changed")
        if name == "P7 acceptance" and (re.findall(r"^APP\s*:=\s*(\w+)\s*$", source, re.M) != ["apu_release"]
                        or re.findall(r"^HAVE_CSR\s*:=\s*(\w+)\s*$", source, re.M) != ["YES"]):
            raise ValueError("APU P7 acceptance application or IRQ configuration changed")
    if [(r["enabled"], r["capability"], r["digest"]) for r in rows] != [
            (False, 0x1BD, 0), (True, 0x1FD, 0xF5005D7C)]:
        raise ValueError("review APU configuration identities")
    values = constants(root, "crt/include/retrosoc/hal/apu_regs.h")
    if (values.get("RS_APU_DIGEST_P7_IMPLEMENTED"), values.get("RS_APU_CAPABILITY0_P5_IMPLEMENTED"),
            values.get("RS_APU_CAPABILITY0_P7_IMPLEMENTED")) != (rows[1]["digest"], rows[0]["capability"], rows[1]["capability"]):
        raise ValueError("APU published digest differs from the HAL")
    return rows


def apu_acceptance_steps(root: Path) -> list[dict]:
    """Bind the rendered LP procedure to ordered, failure-checked application calls."""
    source = "app/apps/apu_release/main.c"
    text = (root / source).read_text(encoding="utf-8")
    body = function_body(text, "rs_apu_release_run")
    stages = (
        ("probe", "rs_apu_probe", 5, "After holding HP in reset, waiting for SDRAM and loading the HP bundle, LP checks the P7 capability and ABI digest."),
        ("quiesce", "rs_apu_release_quiesce", 6, "LP quiesces the APU resource and waits for LP ownership, asserted quiesce, reset released and engine idle."),
        ("stage", "rs_apu_release_stage_assets", 7, "With the resource quiesced, LP stages the APUMC image, APUM model, WAV input and KWS PCM window in SDRAM."),
        ("acl", "rs_apu_set_acl", 8, "LP configures the permitted read and write address ranges before requesting either image load."),
        ("load", "rs_apu_release_load_images", 9, "LP loads the microcode, checks its valid/lock state and CRC, then loads the model and checks its status and CRC."),
        ("handoff", "rs_apu_release_handoff", 10, "LP hands ownership to HP after successful image loading, then publishes the shared page and mailbox request before releasing HP."),
    )
    calls = list(re.finditer(r"\b(" + "|".join(row[1] for row in stages) + r")\s*\(", body))
    if [match[1] for match in calls] != [row[1] for row in stages]:
        raise ValueError("APU acceptance call order changed")
    for index, (match, stage) in enumerate(zip(calls, stages, strict=True)):
        stop = calls[index + 1].start() if index + 1 < len(calls) else body.index("rs_apu_release_fill_page", match.end())
        failures = re.findall(r"rs_apu_release_fail\(\s*UINT8_C\((\d+)\)\s*\)", body[match.end():stop])
        if failures != [str(stage[2])]:
            raise ValueError("APU acceptance failure checkpoint changed")
    loads = function_body(text, "rs_apu_release_load_images")
    if re.findall(r"\b(rs_apu_(?:microcode|kws_model)_load)\s*\(", loads) != [
            "rs_apu_microcode_load", "rs_apu_kws_model_load"]:
        raise ValueError("APU acceptance image-load order changed")
    tail = body[calls[-1].end():]
    if re.findall(r"\b(rs_apu_release_fill_page|rs_hp_mailbox_clear_lp_interrupt|rs_hp_mailbox_send_to_hp|"
                  r"rs_sysctrl_set_hp_release)\s*\(", tail) != [
            "rs_apu_release_fill_page", "rs_hp_mailbox_clear_lp_interrupt", "rs_hp_mailbox_send_to_hp",
            "rs_sysctrl_set_hp_release"] or not re.search(r"rs_sysctrl_set_hp_release\(\s*true\s*\)", tail):
        raise ValueError("APU acceptance HP publication/release order changed")
    return [{"id": identifier, "call": call, "failure_code": failure, "description": description,
             "source": source, "function": "rs_apu_release_run"}
            for identifier, call, failure, description in stages]


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
    result["profiles"] = apu_configurations(root)
    result["acceptance_steps"] = apu_acceptance_steps(root)
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
    apu = reference["apu_implementation"]
    texts = [row["summary"] for row in catalog if row["id"] == "apu"]
    texts += features["apu"] + content["apu"]["notes"]
    for text in texts:
        if (all(row["formats"]["WAV"] and row["formats"]["FLAC"] for row in apu["profiles"])
                and re.search(r"(?:codec jobs|WAV[/ ]FLAC).*remain(?:s)? disabled", text, re.I)):
            raise ValueError("APU publication contradicts deployed WAV/FLAC capability")
        if (re.search(r"MP3(?: and |/)KWS.*not advertised", text, re.I)
                and not re.search(r"default|P7|configuration", text, re.I)):
            raise ValueError("APU publication loses the configured KWS distinction")
