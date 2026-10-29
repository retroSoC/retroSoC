#!/usr/bin/env python3
"""Fail-closed standalone PIOLITE-P2 flows; no Tiny integration is implied."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from scripts.check_simulation import DEFAULT_FAILURE  # noqa: E402
from scripts.setup_helpers import atomic_write  # noqa: E402
from scripts.yosys_period import period_ps  # noqa: E402

COMMON = ROOT / "rtl/managed/clusterip/common/rtl"
IP = ROOT / "rtl/ip/piolite"
TB = ROOT / "tests/rtl"
TOP = "apb4_piolite_block_top"
WRAPPER = ROOT / f"physical/smoke/syn/yosys/{TOP}.sv"
RTL_SOURCES = [
    COMMON / "interface/apb4_if.sv",
    COMMON / "utils/register.sv",
    ROOT / "rtl/ip/util/soc_common_fifo.sv",
    *[
        IP / f"{name}.sv"
        for name in (
            "piolite_pkg", "piolite_if", "piolite_imem", "piolite_fifo", "piolite_sm",
            "piolite_core", "piolite_gpio_guard", "piolite_dma_adapter", "piolite_reg",
            "apb4_piolite",
        )
    ],
]
SOURCES = [*RTL_SOURCES, WRAPPER]
INCLUDES = [COMMON, COMMON / "utils", IP, TB, ROOT / "physical/smoke/syn/yosys"]
CASES = ("piolite_exhaustive_tb", "piolite_isa_tb", "piolite_core_tb", "piolite_fifo_tb",
         "piolite_apb_tb", "piolite_lifecycle_tb")
COVERAGE = {
    "PL-V01": ("PL-V01 exhaustive-legal-and-reserved-semantics",),
    "PL-V03": ("PL-V03 dual-tick-divider-delay-and-pause-resume",),
    "PL-V04": ("PL-V04 counters-move-wrap-and-branches",),
    "PL-V05": ("PL-V05 exact-autopush-threshold-and-atomic-stall",),
    "PL-V06": ("PL-V06 pre-sample-backpressure-and-stall-accounting",
               "PL-V06 randomized-preedge-fifo-conservation"),
    "PL-V07": ("PL-V07 all-csr-reset-access-fields-and-errors",
               "PL-V07 live-config-imem-write-atomicity"),
    "PL-V08": ("PL-V08 same-edge-command-commit-and-set-wins-w1c",
               "PL-V08 pause-suppresses-all-candidate-side-effects",
               "PL-V08 first-fault-priority-and-retention",
               "PL-V08 saturating-tick-stall-retired-counters",
               "PL-V08 paused-snapshot-while-dma-progresses"),
}


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def dump(path: Path, data: dict) -> None:
    atomic_write(path, json.dumps(data, indent=2, sort_keys=True) + "\n")


def inputs() -> dict[str, str]:
    files = set(SOURCES) | {
        COMMON / "utils/fifo.sv", COMMON / "config.svh", IP / "piolite_define.svh",
        ROOT / "Makefile", ROOT / "scripts/piolite_p2.py", ROOT / "scripts/run_flow.py",
        ROOT / "scripts/check_simulation.py", ROOT / "scripts/setup_helpers.py",
        ROOT / "scripts/piolite_model.py",
        ROOT / "scripts/piolite_isa.py", ROOT / "scripts/piolite_asm.py",
        ROOT / "scripts/piolite_p2_vectors.py", ROOT / "scripts/piolite_p2_exhaustive.py",
        ROOT / "scripts/yosys_period.py", ROOT / "dependencies/dependencies.lock.json",
        ROOT / "docs/ip/piolite.md", ROOT / "configs/ci/ics55-tiny.mk",
        ROOT / "configs/ci/ihp130-tiny.mk", ROOT / "crt/include/retrosoc/hal/piolite_regs.h",
        ROOT / "tests/test_piolite_register_parity.py", ROOT / "rtl/rtl_style_audit.json",
        ROOT / "rtl/rtl_readiness.json", ROOT / "rtl/rtl_style_manifest.json",
        ROOT / "rtl/tiny/integration/clock_reset_domains.json",
        ROOT / "physical/smoke/sta/opensta/piolite_block.tcl",
        ROOT / "physical/smoke/sta/opensta/piolite_block.sdc",
    }
    # The normative contract is a producer input. The verification ledger is
    # post-run reporting output, so updating it cannot invalidate producer hashes.
    files.update(TB.glob("piolite_*"))
    files.update((ROOT / "physical/smoke/syn/yosys/script").glob("*"))
    return {str(path.relative_to(ROOT)): digest(path) for path in sorted(files) if path.is_file()}


def tool_inputs() -> dict[str, dict[str, str]]:
    result = {}
    for name in ("verilator", "iverilog", "vvp", "sv2v", "yosys", "sby", "bitwuzla", "sta"):
        executable = shutil.which(name)
        if executable is None:
            raise ValueError(f"missing PIOLITE tool: {name}")
        path = Path(executable).resolve()
        version_arg = "-V" if name in {"iverilog", "vvp"} else "--version"
        version = subprocess.run([str(path), version_arg], text=True, capture_output=True,
                                 check=False, timeout=30)
        result[name] = {
            "path": str(path), "sha256": digest(path),
            "version": (version.stdout + version.stderr).splitlines()[0],
        }
    result["python3"] = {
        "path": str(Path(sys.executable).resolve()),
        "sha256": digest(Path(sys.executable).resolve()),
        "version": sys.version.splitlines()[0],
    }
    return result


def execute(directory: Path, name: str, command: list[str], timeout: int = 300,
            environment: dict | None = None) -> tuple[dict, str]:
    log = directory / f"{name}.log"
    result_path = directory / f"{name}.json"
    args = [sys.executable, str(ROOT / "scripts/run_flow.py"), "--tool", name,
            "--log", str(log), "--result", str(result_path), "--cwd", str(ROOT)]
    for key, value in (environment or {}).items():
        args += ["--env", f"{key}={value}"]
    args += ["--", "timeout", "--foreground", "--kill-after=5s", f"{timeout}s", *command]
    completed = subprocess.run(args, cwd=ROOT, check=False)
    data = json.loads(result_path.read_text())
    content = log.read_text(errors="replace")
    if completed.returncode != 0 or data.get("exit_code") != 0 or data.get("status") != "passed":
        raise RuntimeError(f"{name} failed; see {log}")
    if re.search(r"(?im)^Error:", content):
        raise RuntimeError(f"{name} reported a tool error; see {log}")
    return data, content


def require_pass(content: str, result: dict, marker: str) -> None:
    if result.get("status") != "passed" or result.get("exit_code") != 0:
        raise ValueError("command did not pass")
    if content.count(marker) != 1 or DEFAULT_FAILURE.search(content):
        raise ValueError(f"missing/duplicate success or forbidden marker: {marker}")


def verilator_config(directory: Path) -> str:
    path = directory / "common.vlt"
    atomic_write(path, "`verilator_config\n"
        f'lint_off -rule DECLFILENAME -file "{COMMON}/utils/register.sv"\n'
        f'lint_off -rule DECLFILENAME -file "{COMMON}/utils/fifo.sv"\n'
        f'lint_off -rule UNUSEDSIGNAL -file "{COMMON}/interface/apb4_if.sv"\n'
        f'lint_off -rule UNUSEDSIGNAL -file "{IP}/piolite_pkg.sv"\n')
    return str(path)


def vector_file(directory: Path, top: str) -> Path:
    if top == "piolite_exhaustive_tb":
        execute(directory, "exhaustive-vectors",
                [sys.executable, str(ROOT / "scripts/piolite_p2_exhaustive.py"),
                 str(directory / "exhaustive")])
        return directory / "exhaustive/exhaustive.hex"
    execute(directory, "vectors", [sys.executable, str(ROOT / "scripts/piolite_p2_vectors.py"),
                                   str(directory / "vectors")])
    return directory / "vectors/vectors.hex"


def simulate(directory: Path, simulator: str, top: str, jobs: int) -> None:
    vectors = vector_file(directory, top) if top in {"piolite_exhaustive_tb", "piolite_isa_tb"} else None
    if top == "piolite_exhaustive_tb":
        sources = [COMMON / "utils/register.sv", IP / "piolite_pkg.sv", IP / "piolite_sm.sv"]
        extra = []
    elif top == "piolite_fifo_tb":
        sources = [COMMON / "utils/register.sv", ROOT / "rtl/ip/util/soc_common_fifo.sv",
                   IP / "piolite_fifo.sv"]
        extra = []
    else:
        sources = RTL_SOURCES
        extra = [TB / "piolite_pin_bfm.sv", TB / "piolite_stream_bfm.sv"]
    extra.append(TB / f"{top}.sv")
    model = directory / top
    defines = [f"-I{path}" for path in INCLUDES]
    if top == "piolite_exhaustive_tb":
        defines.append("-DPIOLITE_EXHAUSTIVE_DV")
    if simulator == "VERILATOR":
        command = ["verilator", "--binary", "--timing", "--timescale", "1ns/1ps",
                   verilator_config(directory), "--assert", "-j", str(jobs), "--top-module", top,
                   "--Mdir", str(directory / f"obj-{top}"), "-o", str(model), *defines,
                   *map(str, sources + extra)]
    else:
        converted = directory / f"{top}.v"
        conversion = subprocess.run(["sv2v", "-DSV_ASSRT_DISABLE", *defines,
                                     *map(str, sources + extra)], capture_output=True, text=True,
                                    timeout=180, check=False)
        atomic_write(directory / f"{top}-sv2v.log", conversion.stderr)
        if conversion.returncode:
            raise RuntimeError(conversion.stderr)
        atomic_write(converted, "`timescale 1ns/1ps\n" + conversion.stdout)
        command = ["iverilog", "-g2012", "-s", top, "-o", str(model), str(converted)]
    execute(directory, f"{top}-compile", command, environment={"CCACHE_DISABLE": "1"})
    launch = [str(model)] if simulator == "VERILATOR" else ["vvp", str(model)]
    if vectors is not None:
        launch.append(f"+PIOLITE_{'EXHAUSTIVE' if top == 'piolite_exhaustive_tb' else 'VECTORS'}={vectors}")
    result, log = execute(directory, top, launch, timeout=600)
    require_pass(log, result, f"PIOLITE_P2_PASS {top}")
    if top == "piolite_exhaustive_tb":
        if "PIOLITE_P2_EXHAUSTIVE legal=22257 rejected=43279 total=65536" not in log:
            raise ValueError("PIOLITE exhaustive count marker is missing or incorrect")
        counts = json.loads((directory / "exhaustive/exhaustive.json").read_text())
        if (counts["legal"], counts["rejected"], counts["total"]) != (22257, 43279, 65536):
            raise ValueError("PIOLITE exhaustive vector counts are incorrect")
        dump(directory / "exhaustive-counts.json", counts)


def check_coverage(directory: Path) -> None:
    logs = {case: (directory / f"{case}.log").read_text() for case in CASES}
    rows = []
    for requirement, markers in COVERAGE.items():
        for marker in markers:
            full_marker = f"PIOLITE_P2_COVER {marker}"
            evidence = [case for case, content in logs.items() if full_marker in content]
            count = sum(content.count(full_marker) for content in logs.values())
            if count != 1:
                raise ValueError(f"coverage marker count {count}, expected 1: {full_marker}")
            rows.append({"requirement": requirement, "marker": marker,
                         "status": "passed", "evidence": evidence})
    dump(directory / "pl-v-checklist.json", {
        "requirements": sorted(COVERAGE), "rows": rows,
        "all_p2_rows_closed": True, "phase_accepted": False,
    })


EXPECTED_ASSERTIONS = {
    "fifo_prove": (17, "76f37737c5e120b5eeec892966ba2a055670831c9a49111baa8d58a08b5096c0"),
    "top_bmc": (28, "0a1313b860da992ffb6593959b8aa5e90bacfd4f22538833146eb1bc5bc1a140"),
}
EXPECTED_COVERS = [
    "pready",
    "formal_sm0[43:41] == 3'd1",
    "formal_sm0[40]",
    "formal_sm0[43:41] == 3'd4",
    "formal_sm0[39:32] != 8'd0",
    "formal_sm0[31:0] != 32'd0",
]


def formal_model_counts(path: Path) -> dict[str, int]:
    content = path.read_text()
    return {kind: len(re.findall(rf"^; yosys-smt2-{kind}\b", content, re.M))
            for kind in ("assert", "assume", "cover")}


def validate_assertions(path: Path, label: str) -> str:
    lines = [line for line in path.read_text().splitlines()
             if line.startswith("; yosys-smt2-assert ")]
    actual = hashlib.sha256("\n".join(lines).encode()).hexdigest()
    expected_count, expected_digest = EXPECTED_ASSERTIONS[label]
    if len(lines) != expected_count or actual != expected_digest:
        raise ValueError(f"PIOLITE {label} assertion set changed: count={len(lines)}, sha256={actual}")
    return actual


def validate_cover(directory: Path, label: str, converted: Path, model: Path) -> list[dict]:
    expressions = re.findall(r"^\s*cover\s*\((.*?)\);", converted.read_text(), re.M)
    expected_present = [expression for expression in expressions if expression in EXPECTED_COVERS]
    if expected_present != EXPECTED_COVERS:
        raise ValueError(f"PIOLITE {label} cover goals changed: {expected_present}")
    comments = re.findall(r"^; yosys-smt2-cover\s+(\d+)\s+(\S+)", model.read_text(), re.M)
    if [int(index) for index, _ in comments] != list(range(len(EXPECTED_COVERS))):
        raise ValueError(f"PIOLITE {label} cover-site indices changed: {comments}")
    sites = []
    for index, name in comments:
        goal = EXPECTED_COVERS[int(index)]
        witness = directory / label / "engine_0" / f"trace{index}.yw"
        if not witness.is_file():
            raise ValueError(f"PIOLITE cover goal has no witness: {goal} ({witness})")
        data = json.loads(witness.read_text())
        if data.get("format") != "Yosys Witness Trace" or not data.get("steps"):
            raise ValueError(f"PIOLITE cover witness is empty/invalid: {witness}")
        sites.append({"goal": goal, "smt2_site": name, "witness": witness.name,
                      "steps": len(data["steps"])})
    if len(sites) != len(EXPECTED_COVERS):
        raise ValueError(f"PIOLITE {label} cover witness count changed")
    return sites


def formal_task(directory: Path, label: str, mode: str, depth: int, timeout: int,
                sources: list[Path], top: bool) -> dict[str, int]:
    converted = directory / f"{label}.v"
    defines = ["-DFORMAL", "-DSV_ASSRT_DISABLE"] + (["-DPIOLITE_FORMAL_TOP"] if top else [])
    conversion = subprocess.run(["sv2v", "-E", "Assert", *defines,
                                 *[f"-I{path}" for path in INCLUDES], *map(str, sources)],
                                capture_output=True, text=True, timeout=180, check=False)
    atomic_write(directory / f"{label}-sv2v.log", conversion.stderr)
    if conversion.returncode or not re.search(r"\bassert\s*\(", conversion.stdout):
        raise RuntimeError(f"PIOLITE {label} formal conversion removed assertions")
    if mode == "cover" and not re.search(r"\bcover\s*\(", conversion.stdout):
        raise RuntimeError(f"PIOLITE {label} formal conversion removed cover goals")
    atomic_write(converted, conversion.stdout)
    config = directory / f"{label}.sby"
    engine = "smtbmc --nopresat bitwuzla" if mode == "cover" else "smtbmc bitwuzla"
    waveform = "vcd off\n" if mode == "cover" else ""
    atomic_write(config, f"[options]\nmode {mode}\ndepth {depth}\ntimeout {timeout}\n{waveform}\n"
        f"[engines]\n{engine}\n\n[script]\n"
        f"read_verilog -formal -sv {label}.v\nprep -top piolite_formal\nasync2sync\ndffunmap\n\n"
        f"[files]\n{label}.v {converted}\n")
    execute(directory, label, ["sby", "-d", str(directory / label), str(config)], timeout + 60)
    if (directory / label / "status").read_text().split()[0] != "PASS":
        raise ValueError(f"PIOLITE {label} formal proof did not pass")
    model = directory / label / "model/design_smt2.smt2"
    counts = formal_model_counts(model)
    required = "cover" if mode == "cover" else "assert"
    if counts[required] == 0:
        raise ValueError(f"PIOLITE {label} has no active {required} properties")
    if mode == "cover":
        counts["sites"] = validate_cover(directory, label, converted, model)
        counts["witnesses"] = len(counts["sites"])
    else:
        counts["assertion_sha256"] = validate_assertions(model, label)
    return counts


def formal_selfcheck(directory: Path) -> None:
    negative = directory / "selfcheck"
    negative.mkdir()
    original = directory / "top_bmc/model/design_smt2.smt2"
    lines = original.read_text().splitlines()
    removed = next(line for line in lines if line.startswith("; yosys-smt2-assert "))
    (negative / "deleted-assertion.smt2").write_text("\n".join(
        line for line in lines if line != removed) + "\n")
    try:
        validate_assertions(negative / "deleted-assertion.smt2", "top_bmc")
    except ValueError:
        pass
    else:
        raise ValueError("PIOLITE selfcheck accepted a deleted assertion")

    converted = negative / "top_cover.v"
    model = negative / "design_smt2.smt2"
    engine = negative / "engine_0"
    engine.mkdir()
    shutil.copy(directory / "top_cover.v", converted)
    shutil.copy(directory / "top_cover/model/design_smt2.smt2", model)
    for index in range(6):
        shutil.copy(directory / f"top_cover/engine_0/trace{index}.yw", engine / f"trace{index}.yw")
    (engine / "trace5.yw").unlink()
    try:
        validate_cover(negative, "", converted, model)
    except (ValueError, FileNotFoundError):
        pass
    else:
        raise ValueError("PIOLITE selfcheck accepted a missing named cover witness")
    dump(negative / "verdict.json", {
        "deleted_assertion_rejected": True,
        "missing_named_witness_rejected": True,
        "status": "passed",
    })


def formal(directory: Path) -> None:
    fifo_sources = [COMMON / "utils/register.sv", ROOT / "rtl/ip/util/soc_common_fifo.sv",
                    IP / "piolite_fifo.sv", TB / "piolite_formal_props.sv", TB / "piolite_formal.sv"]
    results = {"fifo_prove": formal_task(directory, "fifo_prove", "prove", 16, 300,
                                         fifo_sources, False)}
    top_sources = [*SOURCES, TB / "piolite_formal_props.sv", TB / "piolite_formal.sv"]
    results["top_bmc"] = formal_task(directory, "top_bmc", "bmc", 12, 600, top_sources, True)
    results["top_cover"] = formal_task(directory, "top_cover", "cover", 24, 1800,
                                       top_sources, True)
    formal_selfcheck(directory)
    dump(directory / "formal-bounds.json", {
        "models": results,
        "bounds": {"fifo_prove": 16, "top_bmc": 12, "top_cover": 24},
        "assumptions": [
            "reset is low for the first edge then high",
            "APB addresses are aligned and restricted to the implemented 4 KiB window",
            "write strobes are full-word when PWRITE is asserted",
            "GPIO readiness/filter inputs are stable; USER ownership may be lost arbitrarily",
            "DMA job-owned inputs are inactive; stream validity and sidebands are symbolic",
            "bounded proofs do not establish external liveness, analog CDC, or product timing",
        ],
        "required_top_witnesses": [
            "APB PREADY", "SM RUNNING", "SM commit", "CLOSING", "nonzero fault", "nonzero OE"
        ],
        "phase_accepted": False,
    })


def synth(directory: Path, pdk: str) -> None:
    period = period_ps(json.loads((ROOT / "rtl/tiny/integration/clock_reset_domains.json").read_text()),
                       "peripheral")
    for name in ("out", "tmp", "rpt"):
        (directory / name).mkdir()
    filelist = directory / "source.fl"
    atomic_write(filelist, "\n".join([*[f"+incdir+{path}" for path in INCLUDES],
                                     *map(str, SOURCES)]) + "\n")
    execute(directory, "yosys", ["yosys", "-t", "--perffile", str(directory / "yosys-perf.json"),
        "-c", str(ROOT / "physical/smoke/syn/yosys/script/synth.tcl")], 10800, {
        "PDK": pdk, "SOC": "TINY", "SYNTH_RECIPE": "balanced", "HAVE_SRAM_MACRO": "NO",
        "YOSYS_TARGET_PERIOD_PS": str(period), "SRAM_SIZE_KIB": "128", "SV_FLIST": str(filelist),
        "TOP_DESIGN": TOP, "PROJ_NAME": TOP, "WORK": str(directory / "tmp"),
        "BUILD": str(directory / "out"), "REPORTS": str(directory / "rpt"),
        "NETLIST": str(directory / "out/netlist.v"), "CONFIG": str(directory / "out/config"),
        "YOSYS_KEEP_HIER_INST": "", "YOSYS_REPORT_INSTS": "", "YOSYS_FLATTEN_HIER": "1"})
    mapped = json.loads((directory / "out/netlist.v.json").read_text())["modules"][TOP]
    cells = [cell["type"] for cell in mapped["cells"].values()]
    if any(not (cell.startswith("sg13g2_") if pdk == "IHP130" else cell.endswith("H7R"))
           for cell in cells):
        raise ValueError("foreign, unresolved or macro cell in PIOLITE block netlist")
    generic = (directory / f"rpt/{TOP}_generic.rpt").read_text()
    if "$dlatch" in generic.lower() or "$_dlatch" in generic.lower():
        raise ValueError("PIOLITE inferred latch")
    check = (directory / f"rpt/{TOP}_synth.rpt").read_text()
    if "Found and reported 0 problems." not in check:
        raise ValueError("PIOLITE netlist structural check did not pass")
    memory_text = (directory / f"rpt/{TOP}_pre_memory.json").read_text()
    memory = json.loads(re.sub(r"^\[\d+\.\d+\]\s?", "", memory_text, flags=re.M))["modules"]
    imem_bits = sum(item.get("num_memory_bits", 0) for name, item in memory.items()
                    if "piolite_imem" in name)
    fifo_bits = sorted(item.get("num_memory_bits", 0) for name, item in memory.items()
                       if name.startswith("\\fifo$") and item.get("num_memory_bits", 0))
    sm_instances = sum(name.startswith("\\piolite_sm$") for name in memory)
    fifo_instances = sum(name.startswith("\\fifo$") for name in memory)
    if (imem_bits != 512 or fifo_bits != [256, 256, 256, 256] or
            sm_instances != 2 or fifo_instances != 4):
        raise ValueError(f"PIOLITE geometry/mapping differs: sm={sm_instances}, "
                         f"fifo={fifo_instances}/{fifo_bits}, imem={imem_bits}")
    area_text = (directory / f"rpt/{TOP}_area.json").read_text()
    area = json.loads(re.sub(r"^\[\d+\.\d+\]\s?", "", area_text, flags=re.M))["design"]["area"]
    dump(directory / "mapping.json", {"top": TOP, "pdk": pdk, "period_ps": period,
         "sm_instances": sm_instances, "fifo_instances": fifo_instances, "imem_bits": imem_bits,
         "fifo_memory_types": fifo_bits, "cells": len(cells), "area": area, "sram_macros": 0})


def netlist_adapter(netlist: Path, directory: Path) -> Path:
    ports = json.loads(Path(str(netlist) + ".json").read_text())["modules"][TOP]["ports"]
    groups = {}
    connections = []
    for name, value in ports.items():
        match = re.fullmatch(r"(.*?)(?:__v(\d+)|_(\d+)_|\[(\d+)\])", name)
        if match:
            base = match[1]
            index = int(next(item for item in match.groups()[1:] if item is not None))
            group = groups.setdefault(base, {"direction": value["direction"], "indices": []})
            if group["direction"] != value["direction"] or len(value["bits"]) != 1:
                raise ValueError("invalid split-port direction/width")
            group["indices"].append(index)
            target = f"{base}[{index}]"
        else:
            base = name
            groups[base] = {"direction": value["direction"], "indices": list(range(len(value["bits"])))}
            target = name
        escaped = f"\\{name} " if not re.fullmatch(r"[A-Za-z_]\w*", name) else name
        connections.append(f".{escaped}({target})")
    declarations = []
    for name, value in groups.items():
        indices = sorted(value["indices"])
        if indices != list(range(len(indices))):
            raise ValueError("noncontiguous split port")
        width = "" if len(indices) == 1 else f"[{len(indices)-1}:0] "
        declarations.append(f'{value["direction"]} wire {width}{name}')
    path = directory / "adapter.v"
    atomic_write(path, "module piolite_netlist_adapter(\n" + ",\n".join(declarations) + ");\n" +
                 f"{TOP} u_mapped(\n" + ",\n".join(connections) + ");\nendmodule\n")
    return path


def technology(pdk: str) -> tuple[Path, list[Path]]:
    if pdk == "ICS55":
        return (ROOT / ".cache/retrosoc/pdk/ics55/ics55_h7cr_ss.lib",
                [ROOT / ".cache/retrosoc/pdk/ics55/ics55_h7cr_functional.v"])
    base = ROOT / "physical/pdk/IHP-Open-PDK/ihp-sg13g2/libs.ref/sg13g2_stdcell"
    return base / "lib/sg13g2_stdcell_slow_1p08V_125C.lib", [
        base / "verilog/sg13g2_udp.v", base / "verilog/sg13g2_stdcell.v"]


def netsim(directory: Path, netlist: Path, pdk: str) -> None:
    _, models = technology(pdk)
    adapter = netlist_adapter(netlist, directory)
    top = "piolite_netlist_tb"
    model = directory / top
    command = ["iverilog", "-g2012", "-gno-specify", "-s", top, "-o", str(model),
               "-DPIOLITE_DUT=piolite_netlist_adapter", "-DPIOLITE_SCALAR_APB",
               *[f"-I{path}" for path in INCLUDES],
               *map(str, [COMMON / "interface/apb4_if.sv"] + models +
                    [netlist, adapter, TB / "piolite_pin_bfm.sv",
                     TB / "piolite_stream_bfm.sv", TB / f"{top}.sv"])]
    execute(directory, f"{top}-compile", command)
    result, log = execute(directory, top, ["vvp", str(model)], timeout=600)
    require_pass(log, result, f"PIOLITE_P2_PASS {top}")


def checked_record(path: Path, source: dict) -> dict:
    data = json.loads(path.read_text())
    if data.get("status") != "passed" or data.get("source") != source:
        raise ValueError(f"incomplete or stale PIOLITE evidence: {path}")
    for name, value in data.get("artifacts", {}).items():
        if digest(Path(name)) != value:
            raise ValueError(f"changed PIOLITE artifact: {name}")
    return data


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("stage", choices=("lint", "rtl", "formal", "synth", "netsim", "sta", "report"))
    parser.add_argument("--variant-root", type=Path, required=True)
    parser.add_argument("--pdk", choices=("ICS55", "IHP130"), required=True)
    parser.add_argument("--simulator", choices=("VERILATOR", "IVERILOG"), default="VERILATOR")
    parser.add_argument("--jobs", type=int, default=4)
    args = parser.parse_args()
    variant = args.variant_root.resolve()
    variant.relative_to(ROOT / "build")
    manifest = json.loads((variant / "meta/manifest.json").read_text())
    if manifest["configuration"]["SOC"] != "TINY" or manifest["configuration"]["PDK"] != args.pdk:
        raise ValueError("profile/PDK mismatch")
    phase = variant / "meta/piolite-p2"
    suffix = args.stage + (f"-{args.simulator.lower()}" if args.stage == "rtl" else "")
    directory = phase / suffix
    if directory.exists():
        raise ValueError(f"existing attempt: {directory}; use a fresh timestamp")
    directory.mkdir(parents=True)
    source = inputs()
    record = {"phase": "PIOLITE-P2", "stage": args.stage, "status": "running",
              "source": source, "manifest": manifest, "phase_accepted": False}
    if args.stage == "rtl":
        record["cases"] = list(CASES)
    dump(directory / "record.json", record)
    try:
        record["tools"] = tool_inputs()
        if args.stage == "lint":
            execute(directory, "lint", ["verilator", "--lint-only", "--Wall", verilator_config(directory),
                    "--top-module", TOP, *[f"-I{path}" for path in INCLUDES], *map(str, SOURCES)])
        elif args.stage == "rtl":
            for top in CASES:
                simulate(directory, args.simulator, top, args.jobs)
            check_coverage(directory)
        elif args.stage == "formal":
            formal(directory)
        elif args.stage == "synth":
            synth(directory, args.pdk)
        elif args.stage in ("netsim", "sta"):
            checked_record(phase / "synth/record.json", source)
            netlist = phase / "synth/out/netlist.v"
            if args.stage == "netsim":
                netsim(directory, netlist, args.pdk)
            else:
                liberty, _ = technology(args.pdk)
                execute(directory, "sta", ["sta", "-exit", str(ROOT /
                    "physical/smoke/sta/opensta/piolite_block.tcl")], environment={
                    "PIOLITE_NETLIST": str(netlist), "PIOLITE_LIBERTY": str(liberty),
                    "PIOLITE_REPORT_DIR": str(directory)})
        else:
            record["stages"] = {name: checked_record(phase / name / "record.json", source)
                for name in ("lint", "rtl-verilator", "rtl-iverilog", "formal", "synth", "netsim", "sta")}
        if source != inputs():
            raise ValueError("source changed during execution")
        record["status"] = "passed"
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        record.update(status="failed", error=str(error))
        print(error, file=sys.stderr)
        return 1
    finally:
        record["artifacts"] = {str(path): digest(path) for path in directory.rglob("*")
                               if path.is_file() and path.name != "record.json"}
        dump(directory / "record.json", record)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
