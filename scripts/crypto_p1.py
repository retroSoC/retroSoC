#!/usr/bin/env python3
"""Focused CRYPTO-P1 evidence; all artifacts are separate from frozen P0."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import struct
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from scripts.crypto_constants import compact_header, pack, validate  # noqa: E402
from scripts.crypto_p0 import (  # noqa: E402
    COMMON, INTERFACES, RTL, UTILITIES, digest, dump, execute, inventory, oracle,
    synthesis_metrics,
)


def input_hashes(sources: list[Path]) -> dict[str, str]:
    # Compilation lists exclude include-only SVH files; their contents still
    # affect the compiled design and must participate in stale-evidence checks.
    paths = set(sources) | set((ROOT / "rtl/ip/security").glob("*.svh"))
    paths |= {ROOT / "dependencies/dependencies.lock.json", ROOT / "rtl/mini/filelist/ip.fl"}
    return {str(p.relative_to(ROOT)): digest(p) for p in sorted(paths)}


def firmware_inputs() -> dict[str, str]:
    names = subprocess.check_output(["git", "ls-files", "--cached", "--others", "--exclude-standard",
        "--", "rtl", "crt", "app", "scripts", "configs", "dependencies", "Makefile",
        "tests/c/crypto_firmware.c"], cwd=ROOT, text=True).splitlines()
    return {name: digest(ROOT / name) for name in sorted(set(names))
            if (ROOT / name).is_file() and not name.endswith((".md", ".png", ".jpg"))
            and not name.startswith("rtl/mini/formal/")}


def firmware_runtime_inputs(variant: Path) -> dict[str, str]:
    """Include generated CPU outputs and selected PDK models used by the run."""
    variant = variant.resolve()
    inputs = firmware_inputs()
    generated = variant / "generated/vexiiriscv"
    if generated.is_dir():
        for path in sorted(generated.rglob("*")):
            if path.is_file():
                inputs[str(path.relative_to(ROOT))] = digest(path)
        pdk = ROOT / "physical/pdk/IHP-Open-PDK/ihp-sg13g2/libs.ref/sg13g2_sram/verilog"
        for path in sorted(pdk.glob("RM_IHPSG13_1P_1024x32_c2_bm_bist.v")):
            inputs[str(path.relative_to(ROOT))] = digest(path)
        for path in sorted(pdk.glob("RM_IHPSG13_1P_core_behavioral_bm_bist.v")):
            inputs[str(path.relative_to(ROOT))] = digest(path)
    return inputs


def firmware_run(variant: Path, kind: str) -> None:
    """Capture the inputs before building/running, never at report assembly."""
    output = variant / "crypto/p1/firmware-run.json"
    manifest = json.loads((variant / "meta/manifest.json").read_text())
    cfg = manifest["configuration"]
    expected = {"PDK": "IHP130", "SIMU": "VERILATOR", "LINK_TYPE": "ld2_all_sram",
                "HAVE_SVA": "YES", "APP": "ci_smoke" if kind == "ci" else "bringup"}
    if kind == "ci":
        expected["HAVE_CSR"] = "YES"
    if any(cfg.get(k) != v for k, v in expected.items()):
        raise ValueError(f"firmware variant configuration does not match {expected}")
    timestamp = re.fullmatch(r"ihp130-(\d{4}-\d{2}-\d{2}-\d{2}-\d{2})-[0-9a-f]+", variant.name)
    if timestamp is None:
        raise ValueError("expected canonical IHP130 variant path")
    command = ["make", "CONFIG=configs/ci/ihp130.mk", f"BUILD_TIMESTAMP={timestamp[1]}",
               *[f"{k}={v}" for k, v in cfg.items()], "VERILATOR_SIM_ARGS=--fast-flash", "SOC_SIM_TIME=1800"]
    if kind == "lp":
        command += [f"APP_SRCS={ROOT / 'tests/c/crypto_firmware.c'}"]
    command += ["firmware", "sim"]
    tracked_inputs = firmware_inputs()
    record = {"status": "running", "kind": kind, "manifest": manifest,
              "source_sha256": tracked_inputs, "command": command}
    dump(output, record)
    try:
        record["flow"] = execute(output.parent, "firmware-flow", command, timeout=3600)
        current_tracked = firmware_inputs()
        if current_tracked != tracked_inputs:
            raise ValueError("tracked firmware inputs changed during the run")
        runtime_inputs = firmware_runtime_inputs(variant)
        result = variant / "sim/verilator/result-sim-check.json"
        simulation = json.loads(result.read_text())
        if simulation["status"] != "passed":
            raise ValueError("firmware simulation did not pass")
        paths = [result, Path(simulation["log"]), variant / "sw/firmware", variant / "meta/manifest.json"]
        record.update(status="passed", source_sha256=runtime_inputs, simulation=simulation,
                      artifacts_sha256={str(p): digest(p) for p in paths})
    except (OSError, ValueError, RuntimeError) as error:
        record.update(status="failed", error=str(error))
        raise
    finally:
        dump(output, record)


def checked_firmware(variant: Path, kind: str) -> dict:
    path = variant / "crypto/p1/firmware-run.json"
    record = json.loads(path.read_text())
    if record.get("status") != "passed" or record.get("kind") != kind:
        raise ValueError(f"missing successful {kind} run identity: {path}")
    if record.get("source_sha256") != firmware_runtime_inputs(variant):
        raise ValueError(f"stale firmware inputs: {path}")
    for name, value in record["artifacts_sha256"].items():
        if not Path(name).exists() or digest(Path(name)) != value:
            raise ValueError(f"stale firmware artifact: {name}")
    flow = json.loads(Path(record["flow"]["result"]).read_text())
    if flow.get("status") != "passed" or flow.get("exit_code") != 0:
        raise ValueError(f"firmware command did not succeed: {path}")
    return {**record, "variant": str(variant), "run_record": str(path), "run_record_sha256": digest(path)}


def quality(output: Path) -> None:
    paths = sorted({*RTL, *(ROOT / "rtl/mini/formal").glob("crypto_*.sv"),
                    *(ROOT / "tests/rtl").glob("crypto_*_tb.sv")} -
                   {ROOT / "tests/rtl/crypto_stream_tb.sv", ROOT / "tests/rtl/crypto_primitives_tb.sv",
                    ROOT / "tests/rtl/crypto_apb_tb.sv", ROOT / "tests/rtl/crypto_dma_tb.sv"})
    results = []
    for path in paths:
        command = ["verible-verilog-format", "--flagfile=.verible-format", "--failsafe_success=false",
                   "--verify", str(path)]
        result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, check=False)
        results.append({"command": command, "exit_code": result.returncode,
                        "diagnostic": result.stdout + result.stderr})
    passed = all(item["exit_code"] == 0 for item in results)
    dump(output / "format.json", {"status": "passed" if passed else "failed", "checks": results,
                                  "source_sha256": input_hashes(paths)})
    if not passed:
        raise ValueError(f"Crypto formatting failed: {output / 'format.json'}")
    execute(output, "ruff", ["ruff", "check", "."])
    execute(output, "quality-gates", ["make", "sw-format-check", "sw-policy-check", "sw-host-test",
                                      "rtl-style-check", "rtl-readiness-check"])
    dump(output / "quality-inputs.json", {"source_sha256": firmware_inputs()})


def inputs(output: Path) -> None:
    output.mkdir(parents=True, exist_ok=True)
    payload = pack(ROOT)
    if payload != oracle().constant_image() or payload != pack(ROOT):
        raise ValueError("CRYC1 independent oracle/reproducibility failure")
    (output / "crypto.cryc").write_bytes(payload)
    (output / "constants.hex").write_text(
        "".join(f"{word:08x}\n" for (word,) in struct.iter_unpack("<I", payload)))
    (output / "crypto_constants.h").write_text(compact_header(payload))
    lengths = (0, 1, 3, 55, 56, 63, 64, 65, 127, 128, 129)
    (output / "sha.hex").write_text("".join(
        hashlib.new(name, bytes(range(length))).hexdigest().ljust(64, "0") + "\n"
        for name in ("sha224", "sha256") for length in lengths))
    fixture = oracle().rsa_fixture()
    (output / "rsa.hex").write_text("".join(f"{fixture[key]:0512x}\n" for key in
        ("modulus", "private", "message", "ciphertext", "n0_prime", "montgomery")))
    dump(output / "constants.json", {**validate(payload), "status": "passed",
         "compact_bytes": 848, "oracle": "tests/crypto_reference.py"})


def rtl(output: Path, full_rsa: bool, macro: bool, jobs: int, top: str = "crypto_v2_tb",
        simulator: str = "verilator", response_delay: int = 0,
        duplicate_response: bool = False, drop_response_mask: int = 0) -> None:
    inputs(output)
    case = output / ("ihp-functional" if macro else "fallback")
    if top != "crypto_v2_tb":
        case = case / top
    if simulator == "icarus":
        case = case / "icarus"
    case.mkdir(parents=True, exist_ok=True)
    (case / "ccache-tmp").mkdir(exist_ok=True)
    sources = [*INTERFACES, *UTILITIES, *[p for p in RTL if p.suffix == ".sv"]]
    defines = ["-DSV_ASSRT_DISABLE"]
    if response_delay:
        defines += [f"-DCRYPTO_RESPONSE_DELAY={response_delay}"]
    if duplicate_response:
        defines += ["-DCRYPTO_RESPONSE_DUPLICATE"]
    if drop_response_mask:
        defines += [f"-DCRYPTO_RESPONSE_DROP_MASK={drop_response_mask}"]
    includes = [ROOT / "rtl/ip/security", COMMON]
    if top == "crypto_dma_v2_tb":
        generated = case / "memory_map"
        execute(case, "memory-map", [sys.executable, str(ROOT / "rtl/mini/address_map/generate_memory_map.py"),
            "--map", str(ROOT / "rtl/mini/address_map/memory_map.json"),
            "--output-dir", str(generated), "--have-sram-if", "NO"])
        includes += [generated / "rtl", COMMON / "interface", COMMON / "stream", COMMON / "utils"]
        sources = [COMMON / "interface/axi4_if.sv", *sources, COMMON / "stream/round_robin_arbiter.sv"]
        sources += [ROOT / "rtl/ip/peripheral" / name for name in
                    ("dma_pkg.sv", "dma_req_if.sv", "dma_axi4_master.sv", "dma_core.sv")]
    if macro:
        sources += [ROOT / "rtl/tech/tc_sram.sv"]
        models = list((ROOT / "physical/pdk").rglob("RM_IHPSG13_1P_1024x32_c2_bm_bist.v"))
        if len(models) != 1:
            raise ValueError(f"expected exactly one IHP130 1024x32 model, found {models}")
        sources += [*models, models[0].with_name("RM_IHPSG13_1P_core_behavioral_bm_bist.v")]
        # SYNTHESIS omits the vendor's unsupported Verilator #0 A_DLY probe;
        # the actual FUNCTIONAL array/bit-mask model remains fully enabled.
        defines += ["-DPDK_IHP130", "-DHAVE_SRAM_MACRO", "-DFUNCTIONAL"]
        if simulator == "verilator":
            defines += ["-DSYNTHESIS"]
    sources += [ROOT / "tests/rtl" / f"{top}.sv"]
    command = ["verilator", "--binary", "--timing", "-Wno-fatal", "--timescale", "1ns/1ps", "--top-module", top,
               "--Mdir", str(case / "obj"), "-j", str(jobs), *defines,
               *[f"-I{path}" for path in includes], *map(str, sources)]
    evidence = {"status": "running", "full_rsa": full_rsa, "macro": macro, "simulator": simulator,
                "production_sha256": input_hashes(sources)}
    dump(case / "functional.json", evidence)
    try:
        if simulator == "icarus":
            fl = case / "sources.fl"
            fl.write_text("\n".join([*[f"+define+{item[2:]}" for item in defines],
                *[f"+incdir+{path}" for path in includes], *map(str, sources)]) + "\n")
            converted = case / "test.v"
            evidence["convert"] = execute(case, "convert", [sys.executable,
                str(ROOT / "rtl/mini/script/convt_sv2v.py"), "-f", str(fl), "--output", str(converted)])
            evidence["compile"] = execute(case, "compile", ["iverilog", "-g2012", "-s", top,
                "-o", str(case / "test.vvp"), str(converted)])
            simulation = ["vvp", str(case / "test.vvp")]
        else:
            evidence["compile"] = execute(case, "compile", command, env={
                "CCACHE_DIR": str(case / "ccache"), "CCACHE_TEMPDIR": str(case / "ccache-tmp")})
            simulation = [str(case / "obj" / f"V{top}")]
        simulation += [f"+constants={output / 'constants.hex'}",
                       f"+sha={output / 'sha.hex'}", f"+rsa={output / 'rsa.hex'}"]
        if full_rsa:
            simulation += ["+full_rsa"]
        markers = {"crypto_dma_v2_tb": "CRYPTO_V2_DMA_PASS", "crypto_storage_tb": "CRYPTO_V2_STORAGE_PASS",
                   "crypto_concurrent_tb": "CRYPTO_V2_CONCURRENT_PASS",
                   "crypto_response_fault_tb": "CRYPTO_V2_RESPONSE_FAULT_PASS",
                   "crypto_v2_tb": "CRYPTO_V2_PASS"}
        evidence["simulation"] = execute(case, "simulation", simulation, timeout=3600, marker=markers[top])
        if top == "crypto_dma_v2_tb":
            evidence["error_simulations"] = {name: execute(case, name, [*simulation, f"+{name}"],
                marker="CRYPTO_V2_DMA_ERROR_PASS") for name in ("dma_read_error", "dma_write_error")}
        evidence["status"] = "passed"
    except (OSError, ValueError, RuntimeError) as error:
        evidence.update(status="failed", error=str(error))
        raise
    finally:
        dump(case / "functional.json", evidence)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("constants", "rtl", "synth", "formal", "report", "firmware", "quality"))
    parser.add_argument("--variant-root", type=Path, required=True)
    parser.add_argument("--full-rsa", action="store_true")
    parser.add_argument("--macro", action="store_true")
    parser.add_argument("--jobs", type=int, default=4)
    parser.add_argument("--case", choices=("crypto_v2_tb", "crypto_dma_v2_tb", "crypto_storage_tb", "crypto_concurrent_tb", "crypto_response_fault_tb"), default="crypto_v2_tb")
    parser.add_argument("--simulator", choices=("verilator", "icarus"), default="verilator")
    parser.add_argument("--response-delay", type=int, default=0)
    parser.add_argument("--duplicate-response", action="store_true")
    parser.add_argument("--drop-response-mask", type=lambda value: int(value, 0), default=0)
    parser.add_argument("--baseline-root", type=Path)
    parser.add_argument("--lp-variant-root", type=Path)
    parser.add_argument("--ci-variant-root", type=Path)
    parser.add_argument("--firmware-kind", choices=("lp", "ci"), default="lp")
    args = parser.parse_args()
    variant = args.variant_root.resolve()
    manifest = json.loads((variant / "meta/manifest.json").read_text())
    if manifest["profile"] != "ihp130":
        raise ValueError("use configs/ci/ihp130.mk")
    output = variant / "crypto/p1"
    if args.command == "constants":
        inputs(output)
    elif args.command == "synth":
        synth(variant, output)
    elif args.command == "formal":
        formal(output)
    elif args.command == "firmware":
        firmware_run(variant, args.firmware_kind)
    elif args.command == "quality":
        quality(output)
    elif args.command == "report":
        if args.baseline_root is None or args.lp_variant_root is None:
            parser.error("report requires --baseline-root and --lp-variant-root")
        report_all(variant, output, args.baseline_root.resolve(), args.lp_variant_root.resolve(),
                   args.ci_variant_root.resolve() if args.ci_variant_root else None)
    else:
        rtl(output, args.full_rsa, args.macro, args.jobs, args.case, args.simulator,
            args.response_delay, args.duplicate_response, args.drop_response_mask)


def report_all(variant: Path, output: Path, baseline: Path, lp_variant: Path,
               ci_variant: Path | None = None) -> None:
    """Summarize evidence without upgrading focused tests to release acceptance."""
    manifest = json.loads((variant / "meta/manifest.json").read_text())
    source_files = [*RTL, ROOT / "scripts/data/crypto_constants.json",
                    ROOT / "scripts/crypto_constants.py", ROOT / "scripts/crypto_p1.py",
                    ROOT / "crt/src/hal/crypto.c", ROOT / "crt/src/hal/crypto_lifecycle.c",
                    ROOT / "crt/include/retrosoc/hal/crypto.h", ROOT / "crt/include/retrosoc/hal/crypto_regs.h"]
    identity = {"schema_version": 1, "feature": "crypto", "phase": "CRYPTO-P1",
                "manifest": manifest, "report_command": sys.argv,
                "source_snapshot_sha256": {str(p.relative_to(ROOT)): digest(p) for p in source_files}}
    dump(output / "p1-report.json", {**identity, "status": "running"})
    paths = ("ihp-functional", "ihp-functional/crypto_dma_v2_tb", "ihp-functional/crypto_storage_tb",
             "ihp-functional/crypto_concurrent_tb", "ihp-functional/crypto_response_fault_tb",
             "ihp-functional/icarus", "fallback", "fallback/crypto_storage_tb")
    cases = {}
    for name in paths:
        path = output / name / "functional.json"
        case = json.loads(path.read_text()) if path.exists() else {"status": "NOT_RUN"}
        stale = [p for p, value in case.get("production_sha256", {}).items()
                 if not (ROOT / p).exists() or digest(ROOT / p) != value]
        if stale:
            case = {"status": "stale", "paths": stale}
        cases[name] = {"path": str(path), "sha256": digest(path) if path.exists() else None, **case}
    functional_pass = all(case.get("status") == "passed" for case in cases.values())
    functional_pass &= cases["ihp-functional"].get("full_rsa") is True
    dump(output / "functional.json", {**identity, "status": "passed" if functional_pass else "incomplete", "cases": cases})
    cycle_values = {}
    for name in ("ihp-functional", "ihp-functional/crypto_dma_v2_tb"):
        log = output / name / "simulation.log"
        if log.exists():
            cycle_values.update({key: int(value) for key, value in re.findall(
                r"CRYPTO_CYCLES operation=(\w+) cycles=(\d+)", log.read_text())})
    dump(output / "cycles.json", {**identity, "status": "passed" if functional_pass else "incomplete",
         "pclk_cycles": cycle_values, "counter_policy": "32-bit hardware counters; testbench bounds below wrap",
         "evidence": [str(output / name / "simulation.log") for name in paths]})
    proofs = json.loads((output / "formal.json").read_text())
    formal_stale = [p for proof in proofs.get("proofs", {}).values()
                    for p, value in proof.get("source_sha256", {}).items() if digest(ROOT / p) != value]
    proof_pass = proofs.get("status") == "passed" and len(proofs.get("proofs", {})) == 5 and not formal_stale
    dump(output / "lifecycle.json", {**identity,
        "status": "passed" if functional_pass and proof_pass else "incomplete",
        "formal": str(output / "formal.json"), "stale_formal_sources": formal_stale,
        "directed_coverage": ["boot scrub", "short/partial/CRC/padding rejection", "readback corruption/retry/lock",
            "all-key-size AES directions and multi-block/tails", "22 SHA padding cases", "held DMA output abort",
            "simultaneous AES/SHA/RSA", "FIFO and all mutable rows inspected after erase", "scrub fault/fatal latch",
            "reset during load/verify", "private RSA verify success/failure with equal cycles"],
        "coverage_limit": "Universal control interruption properties plus directed physical erasure/fault tests; see coverage.json for the exact decomposition."})
    dma = cases["ihp-functional/crypto_dma_v2_tb"].get("error_simulations", {})
    boundary_log = (output / "ihp-functional/simulation.log").read_text()
    coverage = {
        "command_completion": {"evidence": "crypto_v2_tb + crypto_apb_formal", "passed": functional_pass and proof_pass},
        "padding_readback": {"evidence": "CRC-neutral bank-0 rows 528/529 corruption", "passed": functional_pass},
        "timeout_lock_boundary": {"evidence": "six public-APB zeroize/COMMIT boundary cases",
                                  "passed": "CRYPTO_V2_CANCEL_BOUNDARIES_PASS" in boundary_log},
        "fatal_stream_drain": {"evidence": "crypto_stream_formal + SHA FIFO fault with held AES output",
                               "passed": proof_pass and "CRYPTO_V2_FATAL_DMA_DRAIN_PASS" in boundary_log},
        "dma_axi_errors": {"evidence": dma, "passed": len(dma) == 2},
        "response_fault_model": {"evidence": "crypto_response_fault_tb", "passed":
                                  cases["ihp-functional/crypto_response_fault_tb"].get("status") == "passed"},
        "state_interruption": {"evidence": "universal engine next-state abort/zeroize assertions, arbitrary lifecycle reset, bounded scrub proof, physical bank/FIFO inspections",
                               "passed": functional_pass and proof_pass},
    }
    coverage_pass = all(case["passed"] for case in coverage.values())
    dump(output / "coverage.json", {**identity, "status": "passed" if coverage_pass else "incomplete",
        "requirements": coverage, "method": "Proofs quantify over reachable states; physical data tests inspect all rows/slots. This does not claim arbitrary silicon fault or analog SRAM coverage."})
    old = json.loads((baseline / "crypto/p0/baseline-synthesis.json").read_text())
    new = json.loads((output / "candidate-synthesis.json").read_text())
    old_inventory = json.loads((baseline / "crypto/p0/storage-inventory.json").read_text())["checkpoints"]["pre_memory_design"]
    new_inventory = json.loads((output / "storage-inventory.json").read_text())["checkpoints"]["pre_memory_design"]
    recipe_equal = old["recipe_sha256"] == new["recipe_sha256"]
    for field in ("YOSYS_TARGET_PERIOD_PS", "YOSYS_FLATTEN_HIER", "SYNTH_RECIPE", "HAVE_SRAM_MACRO", "PDK"):
        recipe_equal &= old["environment"][field] == new["environment"][field]
    synthesis_stale = [p for p, value in new["production_sha256"].items() if digest(ROOT / p) != value]
    synthesis_pass = new["status"] == "passed" and recipe_equal and not synthesis_stale
    dump(output / "memory-synthesis-ab.json", {**identity,
        "status": "passed" if synthesis_pass else "incomplete", "scope": "block observations",
        "qualification": "P2 must repeat isolated clean-revision A/B; unrelated jobs overlapped these runs",
        "same_recipe_and_target": recipe_equal, "stale_sources": synthesis_stale,
        "baseline": {"report": str(baseline / "crypto/p0/baseline-synthesis.json"), "flow": old["flow"],
                     "inferred_bits": old_inventory["inferred_bits"], "register_bits": old_inventory["register_bits"]},
        "candidate": {"report": str(output / "candidate-synthesis.json"), "flow": new["flow"],
                     "inferred_bits": new_inventory["inferred_bits"], "register_bits": new_inventory["register_bits"],
                     "macros": new_inventory["macros"]},
        "duration_ratio": new["flow"]["duration_seconds"] / old["flow"]["duration_seconds"],
        "rss_ratio": new["flow"]["peak_rss_kib"] / old["flow"]["peak_rss_kib"]})
    try:
        firmware = checked_firmware(lp_variant, "lp")
    except (OSError, ValueError) as error:
        firmware = {"status": "stale", "error": str(error), "variant": str(lp_variant)}
    if ci_variant:
        try:
            ci = checked_firmware(ci_variant, "ci")
        except (OSError, ValueError) as error:
            ci = {"status": "stale", "error": str(error), "variant": str(ci_variant)}
    else:
        ci = {"status": "NOT_RUN"}
    dump(output / "ci-smoke.json", {"schema_version": 1, "feature": "crypto", "phase": "CRYPTO-P1", **ci})
    quality_path = output / "quality-gates.json"
    quality = json.loads(quality_path.read_text()) if quality_path.exists() else {"status": "NOT_RUN"}
    quality_identity = output / "quality-inputs.json"
    if not quality_identity.exists() or json.loads(quality_identity.read_text())["source_sha256"] != firmware_inputs():
        quality = {"status": "stale", "reason": "quality inputs missing or changed"}
    warning_path = lp_variant / "meta/rtl-lint-warnings.json"
    warnings = json.loads(warning_path.read_text()) if warning_path.exists() else {"status": "NOT_RUN"}
    dump(output / "quality.json", {**identity, "gates": quality, "rtl_lint_warnings": warnings,
        "format": json.loads((output / "format.json").read_text()) if (output / "format.json").exists() else {"status": "NOT_RUN"},
        "pytest": "NOT_RUN (maintainer instruction)", "misra_deviations": []})
    dump(output / "firmware.json", {"schema_version": 1, "feature": "crypto", "phase": "CRYPTO-P1", **firmware,
        "scope": "Full SoC, focused LP public HAL initialization/AES/SHA/DMA/timeout/zeroize image"})
    dump(output / "physical.json", {**identity, "status": "NOT_RUN", "phase": "CRYPTO-P2",
        "gaps": ["whole-chip synthesis", "functional gate simulation", "STA", "macro placement and physical views",
                 "remaining PDK qualification", "isolated clean-revision synthesis A/B"]})
    focused_pass = (functional_pass and proof_pass and coverage_pass and synthesis_pass and
                    firmware["status"] == "passed" and ci["status"] == "passed" and quality["status"] == "passed")
    dump(output / "p1-report.json", {**identity, "status": "incomplete",
        "focused_gates_status": "passed" if focused_pass else "incomplete",
        "gates": {"functional": functional_pass, "formal": proof_pass, "block_synthesis": synthesis_pass,
                  "lp_firmware": firmware["status"] == "passed", "focused_quality": quality["status"] == "passed",
                  "ci_smoke": ci["status"] == "passed"},
        "acceptance_gaps": ([] if ci["status"] == "passed" else [
            "CI firmware provenance is stale or missing; rerun the locked profile with generated-input hashes"
            if ci["status"] == "stale" else "Correctly configured ci_smoke has not passed"]) + [
            "Independent review of the P1 fixes remains required",
            "Whole-repository formatting and warning baseline results are separate from focused Crypto gates",
            "Pytest not run by maintainer instruction; P2 qualification not started"],
        "physical": "NOT_RUN (P2)",
        "p0_report_matches_archive": (digest(output / "archive/p0-report.json") ==
            digest(baseline / "crypto/p0/p0-report.json")) if (output / "archive/p0-report.json").exists() else None})
    if not focused_pass:
        raise ValueError("focused P1 evidence is missing/stale/failed; see p1-report.json")


def formal(output: Path) -> None:
    solver = shutil.which("bitwuzla")
    if solver is None:
        raise FileNotFoundError("bitwuzla is required")
    binary_dir = output / "formal/bin"
    binary_dir.mkdir(parents=True, exist_ok=True)
    wrapper = binary_dir / "bitwuzla"
    shutil.copyfile(ROOT / "scripts/bitwuzla_smt2.py", wrapper)
    wrapper.chmod(0o755)
    report = {"status": "running", "proofs": {}}
    dump(output / "formal.json", report)
    try:
        for top in ("crypto_control_formal", "crypto_rsa_release_formal", "crypto_scrub_progress_formal", "crypto_apb_formal", "crypto_stream_formal"):
            case = output / "formal" / top
            case.mkdir(parents=True, exist_ok=True)
            names = ["crypto_mem_pkg.sv", "crypto_scrubber.sv"]
            if top == "crypto_control_formal":
                names += ["crypto_mem_ctrl.sv"]
            elif top == "crypto_rsa_release_formal":
                names += ["crypto_montgomery_sram.sv", "crypto_rsa_sram_core.sv"]
            sources = [COMMON / "utils/register.sv", *[ROOT / "rtl/ip/security" / name for name in names],
                       ROOT / "rtl/mini/formal" / f"{top}.sv"]
            if top == "crypto_apb_formal":
                sources = [*INTERFACES, *UTILITIES, *[p for p in RTL if p.suffix == ".sv"],
                           ROOT / "rtl/mini/formal" / f"{top}.sv"]
            elif top == "crypto_stream_formal":
                sources = [*UTILITIES, *[ROOT / "rtl/ip/security" / name for name in
                    ("crypto_pkg.sv", "crypto_mem_pkg.sv", "crypto_scrubber.sv", "crypto_clearable_fifo.sv",
                     "crypto_aes_sram_core.sv", "crypto_aes_sram_engine.sv")],
                    ROOT / "rtl/mini/formal" / f"{top}.sv"]
            config = case / "prove.sby"
            config.write_text("[options]\nmode prove\ndepth 24\n\n[engines]\n"
                "smtbmc --presat --nounroll bitwuzla\n\n[script]\n"
                f"read_slang -DSV_ASSRT_DISABLE -DFORMAL -USYNTHESIS -I{COMMON} --top {top} " + " ".join(map(str, sources)) +
                ("\nselect -assert-count 10 t:$check" if top == "crypto_rsa_release_formal" else "") +
                f"\nprep -top {top}\nasync2sync\ndffunmap\nopt_clean\n")
            hashes = input_hashes(sources)
            result = execute(case, "proof", ["sby", "-f", "-d", str(case / "work"), str(config)],
                timeout=600, env={"PATH": str(binary_dir) + os.pathsep + os.environ["PATH"],
                                  "RETROSOC_BITWUZLA": solver})
            if (case / "work/status").read_text().split()[0] != "PASS":
                raise ValueError(f"{top} did not prove")
            if hashes != input_hashes(sources):
                raise ValueError(f"{top} sources changed during proof")
            report["proofs"][top] = {**result, "status": "passed",
                "source_sha256": hashes}
        report["status"] = "passed"
    except (OSError, ValueError, RuntimeError) as error:
        report.update(status="failed", error=str(error))
        raise
    finally:
        dump(output / "formal.json", report)


def synth(variant: Path, output: Path) -> None:
    manifest = json.loads((variant / "meta/manifest.json").read_text())
    cfg = manifest["configuration"]
    if any(cfg[key] != value for key, value in {
        "HAVE_SRAM_MACRO": "YES", "PDK_BEHAV": "NO", "SYNTH": "YOSYS",
        "SYNTH_RECIPE": "balanced", "PDK": "IHP130",
    }.items()):
        raise ValueError("P1 block synthesis requires the unchanged IHP130 macro/balanced profile")
    output.mkdir(parents=True, exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix="synth-", dir=output))
    for name in ("out", "tmp", "rpt"):
        (work / name).mkdir()
    sources = [*INTERFACES, *UTILITIES, ROOT / "rtl/tech/tc_sram.sv",
               *[p for p in RTL if p.suffix == ".sv"]]
    fl = work / "crypto.fl"
    fl.write_text("+define+PDK_IHP130\n+define+HAVE_SRAM_MACRO\n+define+SYNTHESIS\n+define+SV_ASSRT_DISABLE\n" +
                  f"+incdir+{ROOT / 'rtl/ip/security'}\n+incdir+{COMMON}\n" +
                  f"+incdir+{COMMON / 'interface'}\n" + "\n".join(map(str, sources)) + "\n")
    directory = ROOT / "physical/smoke/syn/yosys/script"
    period = subprocess.check_output([sys.executable, str(ROOT / "scripts/yosys_period.py"),
        "--domains", str(ROOT / "rtl/mini/integration/clock_reset_domains.json"),
        "--domain", "pclk"], text=True).strip()
    env = {"PDK": "IHP130", "SOC": "MINI", "SYNTH_RECIPE": "balanced", "HAVE_SRAM_MACRO": "YES",
           "SRAM_SIZE_KIB": "32", "SV_FLIST": str(fl), "TOP_DESIGN": "apb4_crypto",
           "PROJ_NAME": "apb4_crypto", "WORK": str(work / "tmp"), "BUILD": str(work / "out"),
           "REPORTS": str(work / "rpt"), "NETLIST": str(work / "out/crypto.v"),
           "CONFIG": str(work / "out/crypto.config"), "YOSYS_TARGET_PERIOD_PS": period,
           "YOSYS_FLATTEN_HIER": "1", "YOSYS_KEEP_HIER_INST": '"t:tc_sram*$*"',
           "YOSYS_REPORT_INSTS": ""}
    report = {"status": "running", "scope": "crypto_block", "manifest": manifest,
              "environment": env, "production_sha256": input_hashes(sources),
              "recipe_sha256": {p.name: digest(p) for p in
                  (directory / "synth.tcl", directory / "abc_balanced.script", directory / "crypto_block_synth.tcl")}}
    dump(output / "candidate-synthesis.json", report)
    try:
        report["flow"] = execute(work, "yosys", ["yosys", "-t", "--perffile", str(work / "yosys-perf.json"),
            "-c", str(directory / "crypto_block_synth.tcl")], timeout=10800, env=env)
        report["metrics"] = synthesis_metrics(work / "rpt")
        checkpoints = {p.stem: inventory(p) for p in (work / "rpt").glob("*_design.json")}
        pre_memory = checkpoints["pre_memory_design"]
        if (sum(pre_memory["macros"].values()) != 6 or pre_memory["rom_bits"] != 0 or
                pre_memory["ram_bits"] > 1184):
            raise ValueError("Crypto macro/inferred-storage contract failed")
        report["status"] = "passed"
    except (OSError, ValueError, RuntimeError, subprocess.CalledProcessError) as error:
        report.update(status="failed", error=str(error))
        raise
    finally:
        dump(output / "candidate-synthesis.json", report)
        dump(output / "storage-inventory.json", {"status": report["status"],
            "production_sha256": report["production_sha256"],
            "checkpoints": {p.stem: inventory(p) for p in (work / "rpt").glob("*_design.json")},
            "whole_soc": "NOT_RUN (P2)", "physical": "NOT_RUN (P2)"})


if __name__ == "__main__":
    main()
