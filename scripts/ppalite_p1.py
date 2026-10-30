#!/usr/bin/env python3
"""Fail-closed standalone PPALITE-P1 flows; no Tiny integration is implied."""
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
IP = ROOT / "rtl/ip/ppalite"
TB = ROOT / "tests/rtl"
TOP = "apb4_ppalite_block_top"
WRAPPER = ROOT / f"physical/smoke/syn/yosys/{TOP}.sv"
RTL_SOURCES = [
    COMMON / "interface/apb4_if.sv", COMMON / "utils/register.sv",
    ROOT / "rtl/ip/util/soc_common_fifo.sv",
    *[IP / f"{name}.sv" for name in (
        "ppalite_if", "ppalite_fifo", "ppalite_decimator", "ppalite_packer",
        "ppalite_stream_guard", "ppalite_core", "ppalite_reg", "apb4_ppalite")],
]
SOURCES = [*RTL_SOURCES, WRAPPER]
INCLUDES = [COMMON, COMMON / "utils", IP, TB, ROOT / "physical/smoke/syn/yosys"]
CASES = ("ppalite_core_tb", "ppalite_stream_tb", "ppalite_apb_tb", "ppalite_fifo_tb",
         "ppalite_bfm_selftest_tb")
COVERAGE = {
    "PPL-V01": ("PPL-V01 scalar-pixel-format-matrix",),
    "PPL-V02": ("PPL-V02 step-phase-and-geometry-matrix",),
    "PPL-V03": ("PPL-V03 dvp-byte-lane-and-row-padding",),
    "PPL-V04": ("PPL-V04 checked-layout-capacity-and-atomic-ARM",),
    "PPL-V05": ("PPL-V05 malformed-sof-eol-keep-strb-id-dest",
                "PPL-V05 source-done-short-count-and-duplicate-faults",
                "PPL-V05 source-done-requires-event",
                "PPL-V05 excess-valid-while-input-ready-low",
                "PPL-V05 late-source-error-and-finalize-race",
                "PPL-V05 finalize-release-excess-race",
                "PPL-V05 detection-edge-framing-no-transform",
                "PPL-V05 live-framing-priority-over-dma",
                "PPL-V05 live-output-priority-over-dma"),
    "PPL-V06": ("PPL-V06 dropped-rows-and-post-output-input-drain",),
    "PPL-V07": ("PPL-V07 randomized-gaps-backpressure-and-stability",
                "PPL-V07 randomized-preedge-fifo-conservation",
                "PPL-V07 four-state-sideband-rejection"),
    "PPL-V15": ("PPL-V15 csr-access-errors-lifecycle-and-parity",
                "PPL-V15 finalize-release-live-error-atomicity",
                "PPL-V15 abort-held-output-drain-and-w1c",
                "PPL-V15 abort-queued-input-cleanup-and-fifo-fields",
                "PPL-V15 simultaneous-code4-code5-priority",
                "PPL-V15 partial-packer-abort-recovery",
                "PPL-V15 idle-excess-then-legal-arm",
                "PPL-V15 release-source-statistics",
                "PPL-V15 recover-reset-irq-and-clean-arm-epoch"),
}


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def dump(path: Path, data: dict) -> None:
    atomic_write(path, json.dumps(data, indent=2, sort_keys=True) + "\n")


def inputs() -> dict[str, str]:
    files = set(SOURCES) | {
        COMMON / "utils/fifo.sv", COMMON / "config.svh", IP / "ppalite_define.svh",
        ROOT / "Makefile", ROOT / "scripts/ppalite_p1.py", ROOT / "scripts/run_flow.py",
        ROOT / "scripts/check_simulation.py", ROOT / "scripts/setup_helpers.py",
        ROOT / "scripts/ppalite_model.py", ROOT / "scripts/ppalite_p1_vectors.py",
        ROOT / "scripts/yosys_period.py", ROOT / "dependencies/dependencies.lock.json",
        ROOT / "docs/ip/ppalite.md", ROOT / "docs/ip/ppalite-verification.md",
        ROOT / "configs/ci/ics55-tiny.mk",
        ROOT / "configs/ci/ihp130-tiny.mk", ROOT / "crt/include/retrosoc/hal/ppalite_regs.h",
        ROOT / "tests/test_ppalite_model.py", ROOT / "tests/test_ppalite_register_parity.py",
        ROOT / "tests/test_ppalite_p1.py", ROOT / "rtl/rtl_style_audit.json",
        ROOT / "rtl/rtl_readiness.json", ROOT / "rtl/rtl_style_manifest.json",
        ROOT / "rtl/tiny/integration/clock_reset_domains.json",
        ROOT / "physical/smoke/sta/opensta/ppalite_block.tcl",
        ROOT / "physical/smoke/sta/opensta/ppalite_block.sdc",
    }
    files.update(TB.glob("ppalite_*"))
    files.update((ROOT / "physical/smoke/syn/yosys/script").glob("*"))
    return {str(path.relative_to(ROOT)): digest(path) for path in sorted(files) if path.is_file()}


def tool_inputs() -> dict[str, dict[str, str]]:
    result = {}
    for name in ("verilator", "iverilog", "vvp", "sv2v", "yosys", "sby", "bitwuzla", "sta"):
        executable = shutil.which(name)
        if executable is None:
            raise ValueError(f"missing PPALite tool: {name}")
        path = Path(executable).resolve()
        version = subprocess.run([str(path), "-V" if name in {"iverilog", "vvp"} else "--version"],
                                 text=True, capture_output=True, check=False, timeout=30)
        result[name] = {"path": str(path), "sha256": digest(path),
                        "version": (version.stdout + version.stderr).splitlines()[0]}
    result["python3"] = {"path": str(Path(sys.executable).resolve()),
                         "sha256": digest(Path(sys.executable).resolve()),
                         "version": sys.version.splitlines()[0]}
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
        f'lint_off -rule UNUSEDSIGNAL -file "{COMMON}/interface/apb4_if.sv"\n')
    return str(path)


def vector_file(directory: Path) -> Path:
    if not (directory / "vectors").exists():
        execute(directory, "vectors", [sys.executable, str(ROOT / "scripts/ppalite_p1_vectors.py"),
                                       str(directory / "vectors")])
    metadata = json.loads((directory / "vectors/vectors.json").read_text())
    if metadata.get("count") != 97 or len(metadata.get("cases", [])) != 97:
        raise ValueError("PPALite vector corpus count mismatch")
    return directory / "vectors/vectors.hex"


def simulate(directory: Path, simulator: str, top: str, jobs: int) -> None:
    vectors = vector_file(directory) if top in {"ppalite_core_tb", "ppalite_stream_tb"} else None
    if top == "ppalite_fifo_tb":
        sources = [COMMON / "utils/register.sv", ROOT / "rtl/ip/util/soc_common_fifo.sv",
                   IP / "ppalite_fifo.sv"]
        extra = []
    else:
        sources = RTL_SOURCES
        extra = [TB / "ppalite_stream_bfm.sv"]
    extra.append(TB / f"{top}.sv")
    model = directory / top
    defines = [f"-I{path}" for path in INCLUDES]
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
        launch.append(f"+PPALITE_VECTORS={vectors}")
    result, log = execute(directory, top, launch, timeout=600)
    require_pass(log, result, f"PPALITE_P1_PASS {top}")


def require_vector_execution(content: str, top: str) -> None:
    position = 0
    for index in range(97):
        marker = f"PPALITE_P1_VECTOR {index}\n"
        found = content.find(marker, position)
        if found < 0 or content.count(marker) != 1:
            raise ValueError(f"missing/duplicate/out-of-order vector execution marker {index}: {top}")
        position = found + len(marker)


def check_coverage(directory: Path, simulator: str) -> None:
    logs = {case: (directory / f"{case}.log").read_text() for case in CASES}
    for case in ("ppalite_core_tb", "ppalite_stream_tb"):
        require_vector_execution(logs[case], case)
    rows = []
    for requirement, markers in COVERAGE.items():
        for marker in markers:
            if marker == "PPL-V07 four-state-sideband-rejection" and simulator == "VERILATOR":
                rows.append({"requirement": requirement, "marker": marker,
                             "status": "not_applicable_two_state", "evidence": []})
                continue
            full_marker = f"PPALITE_P1_COVER {marker}"
            evidence = [case for case, content in logs.items() if full_marker in content]
            count = sum(content.count(full_marker) for content in logs.values())
            if count != 1:
                raise ValueError(f"coverage marker count {count}, expected 1: {full_marker}")
            rows.append({"requirement": requirement, "marker": marker,
                         "status": "passed", "evidence": evidence})
    dump(directory / "ppl-v-checklist.json", {
        "requirements": sorted(COVERAGE), "rows": rows,
        "p1_scope_only": True, "later_phase_rows_open": True, "phase_accepted": False,
    })


def formal_model_counts(path: Path) -> dict[str, int]:
    content = path.read_text()
    return {kind: len(re.findall(rf"^; yosys-smt2-{kind}\b", content, re.M))
            for kind in ("assert", "assume", "cover")}


def assertion_digest(path: Path) -> str:
    lines = [line for line in path.read_text().splitlines() if line.startswith("; yosys-smt2-assert ")]
    if not lines:
        raise ValueError("formal model has no named assertion identities")
    return hashlib.sha256("\n".join(lines).encode()).hexdigest()


def formal_task(directory: Path, label: str, mode: str, depth: int, timeout: int,
                sources: list[Path], top: bool) -> dict:
    converted = directory / f"{label}.v"
    defines = ["-DFORMAL", "-DSV_ASSRT_DISABLE"] + (["-DPPALITE_FORMAL_TOP"] if top else [])
    conversion = subprocess.run(["sv2v", "-E", "Assert", *defines,
                                 *[f"-I{path}" for path in INCLUDES], *map(str, sources)],
                                capture_output=True, text=True, timeout=180, check=False)
    atomic_write(directory / f"{label}-sv2v.log", conversion.stderr)
    if conversion.returncode or not re.search(r"\bassert\s*\(", conversion.stdout):
        raise RuntimeError(f"PPALITE {label} formal conversion removed assertions")
    if mode == "cover" and not re.search(r"\bcover\s*\(", conversion.stdout):
        raise RuntimeError(f"PPALITE {label} formal conversion removed cover goals")
    atomic_write(converted, conversion.stdout)
    config = directory / f"{label}.sby"
    engine = "smtbmc --nopresat bitwuzla" if mode == "cover" else "smtbmc bitwuzla"
    waveform = "vcd off\n" if mode == "cover" else ""
    atomic_write(config, f"[options]\nmode {mode}\ndepth {depth}\ntimeout {timeout}\n{waveform}"
        f"[engines]\n{engine}\n\n[script]\n"
        f"read_verilog -formal -sv {label}.v\nprep -top ppalite_formal\nasync2sync\ndffunmap\n\n"
        f"[files]\n{label}.v {converted}\n")
    execute(directory, label, ["sby", "-d", str(directory / label), str(config)], timeout + 60)
    if (directory / label / "status").read_text().split()[0] != "PASS":
        raise ValueError(f"PPALITE {label} formal proof did not pass")
    model = directory / label / "model/design_smt2.smt2"
    counts = formal_model_counts(model)
    required = "cover" if mode == "cover" else "assert"
    if counts[required] == 0:
        raise ValueError(f"PPALITE {label} has no active {required} properties")
    if mode != "cover":
        counts["assertion_sha256"] = assertion_digest(model)
    if mode == "cover":
        witnesses = []
        for witness in sorted((directory / label / "engine_0").glob("trace*.yw")):
            data = json.loads(witness.read_text())
            if data.get("format") != "Yosys Witness Trace" or not data.get("steps"):
                raise ValueError(f"invalid PPALite cover witness: {witness}")
            witnesses.append({"path": witness.name, "steps": len(data["steps"])})
        if len(witnesses) < 4:
            raise ValueError("PPALITE top cover lost named goals")
        counts["witnesses"] = witnesses
    return counts


def formal(directory: Path) -> None:
    fifo_sources = [COMMON / "utils/register.sv", ROOT / "rtl/ip/util/soc_common_fifo.sv",
                    IP / "ppalite_fifo.sv", TB / "ppalite_formal_props.sv", TB / "ppalite_formal.sv"]
    results = {"fifo_prove": formal_task(directory, "fifo_prove", "prove", 16, 300,
                                         fifo_sources, False)}
    top_sources = [*SOURCES, TB / "ppalite_formal.sv"]
    results["top_bmc"] = formal_task(directory, "top_bmc", "bmc", 24, 600, top_sources, True)
    results["top_cover"] = formal_task(directory, "top_cover", "cover", 32, 1200, top_sources, True)
    original = directory / "top_bmc/model/design_smt2.smt2"
    altered = directory / "deleted-assertion.smt2"
    lines = original.read_text().splitlines()
    removed = next(line for line in lines if line.startswith("; yosys-smt2-assert "))
    altered.write_text("\n".join(line for line in lines if line != removed) + "\n")
    if assertion_digest(altered) == assertion_digest(original):
        raise ValueError("PPALITE selfcheck accepted a deleted assertion")
    dump(directory / "formal-bounds.json", {
        "models": results, "bounds": {"fifo_prove": 16, "top_bmc": 24, "top_cover": 32},
        "negative_selfcheck": "deleted assertion identity rejected",
        "assumptions": [
            "reset is low for the first edge then high",
            "APB offsets are aligned and restricted to the implemented window",
            "write strobes are full-word when PWRITE is asserted",
            "source/transport guards and streams are symbolic standalone inputs",
            "bounded proofs do not establish sensor liveness, DVP/DMA integration or timing",
        ],
        "phase_accepted": False,
    })


def yosys_json(path: Path) -> dict:
    return json.loads(re.sub(r"^\[\d+\.\d+\]\s?", "", path.read_text(), flags=re.M))


def storage_geometry(memory: dict) -> tuple[list[int], int]:
    storage = {name: item.get("num_memory_bits", 0) for name, item in memory.items()
               if item.get("num_memory_bits", 0)}
    if (len(storage) != 2 or any(not name.startswith("\\fifo$") for name in storage) or
            sorted(storage.values()) != [66, 272]):
        raise ValueError(f"unexpected PPALITE memory/storage mapping: {storage}")
    return sorted(storage.values()), len(storage)


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
        raise ValueError("foreign, unresolved or macro cell in PPALITE block netlist")
    generic = (directory / f"rpt/{TOP}_generic.rpt").read_text()
    if "$dlatch" in generic.lower() or "$_dlatch" in generic.lower():
        raise ValueError("PPALITE inferred latch")
    if "Found and reported 0 problems." not in (directory / f"rpt/{TOP}_synth.rpt").read_text():
        raise ValueError("PPALITE netlist structural check did not pass")
    memory = yosys_json(directory / f"rpt/{TOP}_pre_memory.json")["modules"]
    fifo_bits, fifo_instances = storage_geometry(memory)
    area = yosys_json(directory / f"rpt/{TOP}_area.json")["design"]["area"]
    dump(directory / "mapping.json", {"top": TOP, "pdk": pdk, "period_ps": period,
         "fifo_instances": fifo_instances, "fifo_memory_types": fifo_bits,
         "packing_register_bits": 32, "line_frame_ram": 0,
         "cells": len(cells), "area": area, "sram_macros": 0})


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
    atomic_write(path, "module ppalite_netlist_adapter(\n" + ",\n".join(declarations) + ");\n" +
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
    top = "ppalite_netlist_tb"
    model = directory / top
    vectors = vector_file(directory)
    command = ["iverilog", "-g2012", "-gno-specify", "-s", top, "-o", str(model),
               "-DPPALITE_DUT=ppalite_netlist_adapter", "-DPPALITE_SCALAR_APB",
               *[f"-I{path}" for path in INCLUDES],
               *map(str, [COMMON / "interface/apb4_if.sv"] + models +
                    [netlist, adapter, TB / "ppalite_stream_bfm.sv", TB / f"{top}.sv"])]
    execute(directory, f"{top}-compile", command, timeout=600)
    result, log = execute(directory, top, ["vvp", str(model), f"+PPALITE_VECTORS={vectors}"], timeout=1800)
    require_pass(log, result, f"PPALITE_P1_PASS {top}")
    require_vector_execution(log, top)


def checked_record(path: Path, source: dict) -> dict:
    data = json.loads(path.read_text())
    if data.get("status") != "passed" or data.get("source") != source:
        raise ValueError(f"incomplete or stale PPALITE evidence: {path}")
    for name, value in data.get("artifacts", {}).items():
        if digest(Path(name)) != value:
            raise ValueError(f"changed PPALITE artifact: {name}")
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
    phase = variant / "meta/ppalite-p1"
    suffix = args.stage + (f"-{args.simulator.lower()}" if args.stage == "rtl" else "")
    directory = phase / suffix
    if directory.exists():
        raise ValueError(f"existing attempt: {directory}; use a fresh timestamp")
    directory.mkdir(parents=True)
    source = inputs()
    record = {"phase": "PPALITE-P1", "stage": args.stage, "status": "running",
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
            check_coverage(directory, args.simulator)
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
                    "physical/smoke/sta/opensta/ppalite_block.tcl")], environment={
                    "PPALITE_NETLIST": str(netlist), "PPALITE_LIBERTY": str(liberty),
                    "PPALITE_REPORT_DIR": str(directory)})
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
