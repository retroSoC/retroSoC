#!/usr/bin/env python3
"""Retain and replay the Tiny R2-P1 workload without changing product policy."""

from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from scripts.check_simulation import DEFAULT_FAILURE  # noqa: E402
from scripts.manifest import git_info  # noqa: E402
from scripts.rtl.filelist import parse_filelists  # noqa: E402
from scripts.setup_helpers import atomic_write, sha256  # noqa: E402
from scripts.setup_tiny import TINY_SOURCES  # noqa: E402

PHASE = "TINY-R2-P1"
CASES = ("empty", "cpu", "memory", "dma1", "dma16", "contention", "tcd")
PARAMETERS = {"version": 1, "cpu_hz": 24000000, "words": 1024, "jobs": 16,
              "iterations": 4096, "seed": 0x12345678}
COMPATIBILITY = {"SOC": "TINY", "PDK": "IHP130", "HAVE_PLL": "NO",
                 "SRAM_SIZE_KIB": "128", "EXT_CLK_HZ": "24000000", "ISA": "RV32IM",
                 "HAVE_CSR": "YES", "LINK_TYPE": "ld2_all_sram", "PDK_BEHAV": "NO"}
TOOL_PROGRAMS = {"verilator": "verilator", "verible": "verible-verilog-format",
                 "sv2v": "sv2v", "iverilog": "iverilog", "yosys": "yosys",
                 "opensta": "sta", "riscv_gnu": "riscv32-unknown-elf-gcc"}
SOURCE_PATHS = ("Makefile", "configs/ci/ihp130-tiny.mk", "dependencies/dependencies.lock.json",
                "requirements", "rtl/tiny", "rtl/ip", "rtl/tech", "rtl/mk/software.mk",
                "crt", "app/apps/ci_smoke", "app/apps/bringup", "scripts",
                "physical/smoke", "physical/librelane/tiny")
CASE_FIELDS = {"id", "name", "cycles", "instructions", "kernel_cycles", "kernel_calls",
               "payload_bytes", "checksum", "cpu_wait", "dma_wait", "sram_reads",
               "sram_writes", "sram_rbeats", "sram_wbeats", "sram_stalls", "sram_errors"}
AXI_FIELDS = {"window", "owner", "cycles", "reads", "writes", "read_done", "write_done",
              "read_bytes", "write_bytes", "descriptor_bytes", "read_latency_max",
              "write_latency_max", "aw_stall_max", "w_stall_max", "b_stall_max",
              "ar_stall_max", "r_stall_max", "pending_reads", "pending_writes"}
AHB_FIELDS = {"window", "kind", "accepted", "completed", "latency_max"}


def dump(path: Path, value: object) -> None:
    atomic_write(path, json.dumps(value, sort_keys=True, indent=2) + "\n")


def read_json(path: Path) -> dict:
    result = json.loads(path.read_text())
    if not isinstance(result, dict):
        raise ValueError(f"expected JSON object: {path}")
    return result


def artifact(path: Path) -> dict:
    return {"path": str(path.resolve()), "sha256": sha256(path), "bytes": path.stat().st_size}


def check_artifact(value: dict) -> Path:
    path = Path(value["path"])
    if not path.is_file() or artifact(path) != value:
        raise ValueError(f"missing or changed artifact: {path}")
    return path


def digest_map(value: dict) -> str:
    return hashlib.sha256(json.dumps(value, sort_keys=True).encode()).hexdigest()


def source_inputs(root: Path) -> dict[str, str]:
    names = subprocess.check_output(
        ["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z", "--",
         *SOURCE_PATHS], cwd=root,
    ).decode().split("\0")
    paths = {root / name for name in names if name and not name.endswith(
        (".md", ".png", ".jpg", ".svg", ".pdf"))}
    lock = read_json(root / "dependencies/dependencies.lock.json")
    for name in TINY_SOURCES:
        spec = lock["sources"][name]
        checkout = root / spec["destination"]
        revision = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=checkout,
                                           text=True).strip()
        dirty = subprocess.check_output(["git", "status", "--porcelain"], cwd=checkout,
                                        text=True).strip()
        if revision != spec["revision"] or dirty:
            raise ValueError(f"managed input is not clean at its lock: {name}")
        # Source inputs plus the three SRAM views and exact core-STA libraries.
        if name == "pdk_ihp130":
            base = checkout / "ihp-sg13g2/libs.ref"
            paths.update((base / "sg13g2_sram/lib").glob(
                "RM_IHPSG13_1P_1024x32_c2_bm_bist_*.lib"))
            paths.update((base / "sg13g2_stdcell/lib").glob("*slow_1p08V_125C.lib"))
            paths.update((base / "sg13g2_io/lib").glob("*slow_1p08V_3p0V_125C.lib"))
        else:
            for suffix in ("*.v", "*.sv", "*.vh", "*.svh", "*.c", "*.h"):
                paths.update(checkout.rglob(suffix))
    return {str(path.relative_to(root)): sha256(path) for path in sorted(paths) if path.is_file()}


def runtime_inputs(root: Path, variant: Path, simulator: str) -> dict[str, str]:
    paths = set((variant / "generated/tiny").rglob("*"))
    filelists = sorted((variant / "sim" / simulator / "filelists").glob("*.fl"))
    if not filelists:
        raise ValueError("missing generated simulator filelists")
    resolved = parse_filelists(filelists)
    paths.update(filelists)
    paths.update(resolved.files)
    paths.update(resolved.library_files)
    for directory in resolved.incdirs:
        for suffix in ("*.svh", "*.vh"):
            paths.update(directory.rglob(suffix))
    converted = variant / "sim" / simulator / "converted_soc.v"
    if converted.exists():
        paths.add(converted)
    return {str(path.relative_to(root)): sha256(path) for path in sorted(paths) if path.is_file()}


def configuration(variant: Path) -> dict:
    manifest = read_json(variant / "meta/manifest.json")
    config = manifest["configuration"]
    if manifest["profile"] != "ihp130-tiny" or any(
        config.get(key) != expected for key, expected in COMPATIBILITY.items()
    ):
        raise ValueError("baseline requires the committed Tiny/IHP130 24 MHz macro profile")
    return manifest


def tools_identity(root: Path) -> dict:
    cache_value = os.environ.get("RETROSOC_DEVELOPMENT_CACHE")
    if not cache_value:
        raise ValueError("activate the verified locked development environment first")
    cache = Path(cache_value).resolve()
    lock = read_json(root / "dependencies/dependencies.lock.json")["toolchains"]["ubuntu-22.04"]
    result = {}
    for name, program in TOOL_PROGRAMS.items():
        spec = lock[name]
        installed = cache / "toolchains" / f"{name}-{spec['version']}"
        archive = cache / "downloads" / spec["archive"]
        executable = shutil.which(program)
        if (not executable or Path(executable).resolve() != (installed / spec["path"] / program).resolve()
                or (installed / ".complete").read_text().strip() != spec["sha256"]
                or sha256(archive) != spec["sha256"]):
            raise ValueError(f"tool path/archive is not the locked installation: {name}")
        option = "-version" if name == "opensta" else "-V" if name == "iverilog" else "--version"
        version = subprocess.run([executable, option], text=True, capture_output=True, check=True)
        result[name] = {"locked_version": spec["version"], "archive": artifact(archive),
                        "executable": artifact(Path(executable)),
                        "version": (version.stdout or version.stderr).splitlines()[0]}
    return result


def vvp_identity(selected: str, compiler: dict) -> dict:
    """Bind the selected runtime to the already verified Icarus installation."""
    expected = Path(compiler["executable"]["path"]).with_name("vvp").resolve()
    executable = shutil.which(selected)
    if not executable or Path(executable).resolve() != expected:
        raise ValueError("selected vvp is not the locked Icarus runtime")
    version = subprocess.run([str(expected), "-V"], text=True, capture_output=True, check=True)
    version_lines = (version.stdout or version.stderr).splitlines()
    if not version_lines:
        raise ValueError("locked vvp did not report its version")
    return {"locked_version": compiler["locked_version"], "archive": compiler["archive"],
            "executable": artifact(expected),
            "version": version_lines[0]}


def validate_runtime_tool(root: Path, attempt: dict) -> None:
    if attempt["simulator"] != "iverilog":
        return
    runtime = attempt.get("runtime_tool")
    if not isinstance(runtime, dict):
        raise ValueError("missing locked vvp runtime identity")
    spec = read_json(root / "dependencies/dependencies.lock.json")["toolchains"]["ubuntu-22.04"]["iverilog"]
    compiler = attempt["tools"]["iverilog"]
    executable = check_artifact(runtime["executable"])
    expected = Path(compiler["executable"]["path"]).with_name("vvp").resolve()
    check_artifact(runtime["archive"])
    if (executable != expected or runtime["archive"] != compiler["archive"]
            or runtime["archive"]["sha256"] != spec["sha256"]
            or runtime["locked_version"] != spec["version"] or not runtime.get("version")
            or attempt["command"][0] != str(executable)):
        raise ValueError("vvp runtime does not match its locked identity and launch command")
    for run in attempt["runs"]:
        command = read_json(check_artifact(run["flow"]))["command"]
        if command != ["timeout", "--foreground", f"{attempt['timeout_seconds']}s", *attempt["command"]]:
            raise ValueError("simulation did not launch the recorded locked vvp runtime")


def snapshot(root: Path, destination: Path, inputs: dict[str, str]) -> dict:
    destination.mkdir(parents=True, exist_ok=True)
    with tarfile.open(destination / "inputs.tar.gz", "w:gz", dereference=True) as archive:
        for name in inputs:
            archive.add(root / name, arcname=name, recursive=False)
    diff = subprocess.check_output(["git", "diff", "HEAD", "--binary"], cwd=root, text=True)
    atomic_write(destination / "worktree.patch", diff)
    dump(destination / "input-hashes.json", inputs)
    return {"repository": git_info(root), "input_digest": digest_map(inputs),
            "inputs": artifact(destination / "input-hashes.json"),
            "snapshot": artifact(destination / "inputs.tar.gz"),
            "patch": artifact(destination / "worktree.patch")}


def execute(root: Path, directory: Path, label: str, command: list[str], *,
            cwd: Path | None = None, quiet: bool = False) -> dict:
    result = directory / f"{label}.json"
    invocation = [sys.executable, str(root / "scripts/run_flow.py"), "--tool", label,
                  "--log", str(directory / f"{label}.log"), "--result", str(result)]
    if cwd is not None:
        invocation += ["--cwd", str(cwd)]
    completed = subprocess.run([*invocation, "--", *command], check=False,
                               stdout=subprocess.PIPE if quiet else None)
    record = read_json(result)
    if completed.returncode != 0 or record.get("status") != "passed":
        raise ValueError(f"command failed; retained result: {result}")
    return record


def new_attempt(parent: Path, prefix: str) -> Path:
    parent.mkdir(parents=True, exist_ok=True)
    return Path(tempfile.mkdtemp(prefix=prefix, dir=parent))


def payload_checksum() -> int:
    value = 2166136261
    for _ in range(16):
        for index in range(1024):
            value = ((value ^ (0xA519C300 ^ index)) * 16777619) & 0xFFFFFFFF
    return value


def cpu_checksum() -> int:
    value = PARAMETERS["seed"]
    for _ in range(PARAMETERS["iterations"]):
        value ^= (value << 13) & 0xFFFFFFFF
        value ^= value >> 17
        value ^= (value << 5) & 0xFFFFFFFF
    return value


def parse_fields(line: str, expected: set[str], *, strings: set[str] = frozenset()) -> dict:
    fields = {}
    for token in line.split()[1:]:
        key, separator, raw = token.partition("=")
        if not separator or key in fields or key not in expected:
            raise ValueError(f"malformed or duplicate record field: {line}")
        value = raw if key in strings else int(raw, 0)
        if key not in strings and not 0 <= value < (1 << 64):
            raise ValueError(f"counter outside unsigned 64-bit range: {key}")
        fields[key] = value
    if set(fields) != expected:
        raise ValueError(f"incomplete record: {line}")
    return fields


def parse_log(content: str, flow_result: dict) -> dict:
    if flow_result.get("exit_code") != 0 or flow_result.get("status") != "passed":
        raise ValueError("simulation command did not succeed")
    if DEFAULT_FAILURE.search(content) or "R2_ERROR" in content or "SIM_TEST_PASS Tiny" not in content:
        raise ValueError("missing Tiny terminal pass or forbidden failure marker")
    records: dict[str, list[dict]] = {name: [] for name in ("header", "case", "axi", "ahb", "complete")}
    definitions = {"R2_HEADER": ("header", set(PARAMETERS)), "R2_CASE": ("case", CASE_FIELDS),
                   "R2_AXI": ("axi", AXI_FIELDS), "R2_AHB": ("ahb", AHB_FIELDS),
                   "R2_COMPLETE": ("complete", {"version", "cases"})}
    for line in content.splitlines():
        prefix = line.split(maxsplit=1)[0] if line.strip() else ""
        if prefix in definitions:
            name, fields = definitions[prefix]
            records[name].append(parse_fields(line, fields, strings={"name"} if name == "case" else set()))
    if records["header"] != [PARAMETERS] or records["complete"] != [{"version": 1, "cases": 7}]:
        raise ValueError("missing, duplicate or incompatible workload identity")
    if [(row["id"], row["name"]) for row in records["case"]] != list(enumerate(CASES)):
        raise ValueError("workload cases are missing, duplicated or reordered")
    for name, field in (("axi", "owner"), ("ahb", "kind")):
        keys = [(row["window"], row[field]) for row in records[name]]
        if sorted(keys) != [(window, index) for window in range(1, 8) for index in range(2)]:
            raise ValueError(f"missing or duplicate {name} observations")
        # Independent always blocks need not print in the same scheduler order.
        records[name].sort(key=lambda row: (row["window"], row[field]))
    axi = {(row["window"], row["owner"]): row for row in records["axi"]}
    for index, row in enumerate(records["case"]):
        expected_checksum = 0 if index == 0 else cpu_checksum() if index == 1 else payload_checksum()
        expected_calls = 1 if index == 1 else 16 if index >= 5 else 0
        if (row["checksum"] != expected_checksum or row["kernel_calls"] != expected_calls
                or row["payload_bytes"] != (65536 if index >= 2 else 0)
                or row["cycles"] <= 0 or row["instructions"] <= 0 or row["sram_errors"] != 0
                or row["kernel_cycles"] > row["cycles"]
                or (expected_calls > 0) != (row["kernel_cycles"] > 0)):
            raise ValueError(f"invalid workload result: {row['name']}")
        dma = axi[(index + 1, 1)]
        expected_bytes = 65536 if index >= 3 else 0
        if (dma["read_bytes"] != expected_bytes or dma["write_bytes"] != expected_bytes
                or dma["descriptor_bytes"] != (4096 if index == 6 else 0)
                or dma["pending_reads"] or dma["pending_writes"]):
            raise ValueError(f"DMA payload/descriptor/drain accounting mismatch: {row['name']}")
        for owner in range(2):
            observed = axi[(index + 1, owner)]
            if (observed["reads"] != observed["read_done"] + observed["pending_reads"]
                    or observed["writes"] != observed["write_done"] + observed["pending_writes"]):
                raise ValueError("AXI accepted/completed accounting mismatch")
        row["cpi"] = row["cycles"] / row["instructions"]
        row["payload_bytes_per_cycle"] = row["payload_bytes"] / row["cycles"]
    for row in records["ahb"]:
        if row["completed"] > row["accepted"] or row["accepted"] - row["completed"] > 1:
            raise ValueError("AHB accepted/completed accounting mismatch")
    return records


def build_image(args: argparse.Namespace) -> int:
    root, variant = args.root.resolve(), args.variant_root.resolve()
    evidence = variant / "meta/tiny-r2-p1"
    directory = new_attempt(evidence / "binaries", "image-")
    output = directory / "image.json"
    # Move the pointer before starting: a failed attempt must not expose an old success.
    dump(evidence / "binaries/latest.json", {"path": str(output)})
    record = {"schema_version": 1, "phase": PHASE, "status": "running"}
    dump(output, record)
    try:
        manifest = configuration(variant)
        tools = tools_identity(root)
        before = source_inputs(root)
        # Archive generated C headers and the preprocessed flat linker input too.
        generated = {str(path.relative_to(root)): sha256(path)
                     for path in (variant / "generated/tiny").rglob("*") if path.is_file()}
        for path in (variant / "sw").rglob("*"):
            if path.is_file() and path.suffix in (".h", ".lds", ".ld"):
                generated[str(path.relative_to(root))] = sha256(path)
        record.update(manifest=manifest, tools=tools, source=snapshot(root, directory / "inputs", before | generated),
                      parameters=PARAMETERS, created_at=datetime.now(timezone.utc).isoformat())
        elf = directory / "tiny_baseline.elf"
        compiler_command = list(args.command[1:] if args.command[:1] == ["--"] else args.command)
        if not compiler_command:
            raise ValueError("image compiler command is required")
        compiler_command += ["-Wl,-Map," + str(directory / "tiny_baseline.map"), "-o", str(elf)]
        execute(root, directory, "compile", compiler_command, cwd=variant / "sw")
        for name, form in (("hex", "verilog"), ("bin", "binary")):
            execute(root, directory, f"objcopy-{name}", [args.objcopy, "-O", form, str(elf),
                                                         str(directory / f"tiny_baseline.{name}")])
        for label, command in (("disassembly", [args.objdump, "-d", str(elf)]),
                               ("symbols", [args.nm, "-n", "-S", str(elf)]),
                               ("size", [args.size, "-A", str(elf)])):
            execute(root, directory, label, command, quiet=True)
        symbols = (directory / "symbols.log").read_text()
        match = re.search(r"^([0-9a-f]+) ([0-9a-f]+) [bBdD] rs_baseline_tcds$", symbols, re.MULTILINE)
        if match is None or int(match[2], 16) != 4096:
            raise ValueError("missing complete 64-descriptor SRAM symbol")
        base = int(match[1], 16)
        ebss = re.search(r"^([0-9a-f]+)(?: [0-9a-f]+)? [A-Za-z] _ebss$", symbols, re.MULTILINE)
        if ebss is None or not 0x30000000 <= int(ebss[1], 16) <= 0x3001F000:
            raise ValueError("image does not preserve at least 4 KiB of stack headroom")
        if before != source_inputs(root):
            raise ValueError("source changed while compiling the retained image")
        if any(not (root / name).is_file() or sha256(root / name) != digest
               for name, digest in generated.items()):
            raise ValueError("generated software inputs changed during compilation")
        record.update(status="passed", compiler_command=compiler_command,
                      descriptor_range=[base, base + 4096], stack_headroom=0x30020000-int(ebss[1], 16),
                      artifacts={p.name: artifact(p) for p in directory.iterdir()
                                 if p.is_file() and p != output})
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        record.update(status="failed", error=str(error))
        raise
    finally:
        dump(output, record)
    print(f"retained Tiny baseline: {directory / 'tiny_baseline.hex'}")
    return 0


def retained_image(evidence: Path, selected: Path | None) -> tuple[Path, dict]:
    manifest_path = selected.resolve().parent / "image.json" if selected else Path(
        read_json(evidence / "binaries/latest.json")["path"])
    value = read_json(manifest_path)
    if value.get("status") != "passed" or value.get("phase") != PHASE or value.get("parameters") != PARAMETERS:
        raise ValueError("retained image lacks successful compatible build provenance")
    image = check_artifact(value["artifacts"]["tiny_baseline.hex"])
    if selected and image != selected.resolve():
        raise ValueError("selected image does not match its original manifest")
    for identity in value["artifacts"].values():
        check_artifact(identity)
    for identity in (value["source"][key] for key in ("inputs", "snapshot", "patch")):
        check_artifact(identity)
    return manifest_path, value


def validate_runs(runs: list[dict]) -> None:
    """Recheck acceptance from retained logs, never just a producer's label."""
    if [run.get("repetition") for run in runs] != [1, 2, 3]:
        raise ValueError("expected three distinct ordered cold-start repetitions")
    for run in runs:
        log = check_artifact(run["log"])
        flow = read_json(check_artifact(run["flow"]))
        verdict = read_json(check_artifact(run["verdict"]))
        if (not flow.get("command") or Path(flow.get("log", "")).resolve() != log.resolve()
                or verdict.get("status") != "passed"
                or Path(verdict.get("log", "")).resolve() != log.resolve()
                or parse_log(log.read_text(), flow) != run["samples"]):
            raise ValueError("changed or invalid simulation verdict")
    if any(run["samples"] != runs[0]["samples"] for run in runs[1:]):
        raise ValueError("cold-start repetitions were not deterministic")


def simulate(args: argparse.Namespace) -> int:
    root, variant = args.root.resolve(), args.variant_root.resolve()
    evidence = variant / "meta/tiny-r2-p1"
    directory = new_attempt(evidence / "workloads" / args.simulator, "attempt-")
    output = directory / "attempt.json"
    dump(directory.parent / "latest.json", {"path": str(output)})
    record = {"schema_version": 1, "phase": PHASE, "status": "running", "runs": [],
              "simulator": args.simulator}
    dump(output, record)
    try:
        image_path, image = retained_image(evidence, args.hex)
        record.update(image_manifest=artifact(image_path), image_sha256=image["artifacts"]["tiny_baseline.hex"]["sha256"],
                      firmware_source=image["source"], manifest=configuration(variant), tools=tools_identity(root))
        if args.simulator == "iverilog":
            record["runtime_tool"] = vvp_identity(args.vvp, record["tools"]["iverilog"])
        before = source_inputs(root)
        command = args.command[1:] if args.command[:1] == ["--"] else args.command
        if not command:
            raise ValueError("a fresh simulator compilation command is required")
        execute(root, directory, "compile-model", command, quiet=True)
        if before != source_inputs(root):
            raise ValueError("source changed while compiling the simulator")
        runtime = runtime_inputs(root, variant, args.simulator)
        record["rtl_source"] = snapshot(root, directory / "inputs", before | runtime)
        model = variant / "sim" / args.simulator / ("emu" if args.simulator == "verilator" else "simv")
        record["model"] = artifact(model)
        launch = [str(model)] if args.simulator == "verilator" else [record["runtime_tool"]["executable"]["path"], str(model)]
        base, end = image["descriptor_range"]
        launch += ["+firmware=" + image["artifacts"]["tiny_baseline.hex"]["path"],
                   "+tiny_r2_baseline", f"+baseline_tcd_base={base:x}", f"+baseline_tcd_end={end:x}",
                   f"+max_cycles={args.max_cycles}"]
        record.update(command=launch, timeout_seconds=args.timeout, max_cycles=args.max_cycles,
                      simulation_jobs=min(args.jobs, 3))

        def run_once(repetition: int) -> dict:
            label = f"run-{repetition}"
            if args.simulator == "iverilog":
                check_artifact(record["runtime_tool"]["executable"])
            flow = execute(root, directory, label,
                           ["timeout", "--foreground", f"{args.timeout}s", *launch], quiet=True)
            log = directory / f"{label}.log"
            execute(root, directory, f"{label}-check", [sys.executable, str(root / "scripts/check_simulation.py"),
                    "--log", str(log), "--result", str(directory / f"{label}-verdict.json"),
                    "--require", "SIM_TEST_PASS"], quiet=True)
            samples = parse_log(log.read_text(), flow)
            return {"repetition": repetition, "samples": samples,
                    "log": artifact(log), "flow": artifact(directory / f"{label}.json"),
                    "verdict": artifact(directory / f"{label}-verdict.json")}

        # Each child has its own reset state and logs; only immutable model and
        # firmware inputs are shared. Host scheduling cannot advance HDL clocks.
        errors = []
        with ThreadPoolExecutor(max_workers=min(args.jobs, 3)) as executor:
            futures = [executor.submit(run_once, repetition) for repetition in range(1, 4)]
            for future in as_completed(futures):
                try:
                    run = future.result()
                    record["runs"].append(run)
                    record["runs"].sort(key=lambda value: value["repetition"])
                    print(f"{args.simulator} repetition {run['repetition']}: passed", flush=True)
                except (OSError, ValueError, subprocess.SubprocessError) as error:
                    errors.append(str(error))
                    record["run_errors"] = errors
                dump(output, record)
        if errors:
            raise ValueError("; ".join(errors))
        if before != source_inputs(root) or runtime != runtime_inputs(root, variant, args.simulator):
            raise ValueError("source or generated inputs changed during simulation")
        validate_runs(record["runs"])
        validate_runtime_tool(root, record)
        # Retention is part of acceptance: a binary changed after launch is
        # still a failed evidence bundle even if the loaded model completed.
        check_artifact(record["image_manifest"])
        retained_image(evidence, Path(image["artifacts"]["tiny_baseline.hex"]["path"]))
        record["status"] = "passed"
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        record.update(status="failed", error=str(error))
        raise
    finally:
        dump(output, record)
    print(f"Tiny baseline {args.simulator}: 3 reproducible runs ({output})")
    return 0


def report(args: argparse.Namespace) -> int:
    root, variant = args.root.resolve(), args.variant_root.resolve()
    evidence = variant / "meta/tiny-r2-p1"
    output = evidence / "baseline-report.json"
    result = {"schema_version": 1, "phase": PHASE, "status": "incomplete", "simulators": {},
              "qualification": "functional and simulated workload evidence only; not physical qualification"}
    try:
        for simulator in ("verilator", "iverilog"):
            path = Path(read_json(evidence / "workloads" / simulator / "latest.json")["path"])
            attempt = read_json(path)
            if attempt.get("status") != "passed" or len(attempt.get("runs", [])) != 3:
                raise ValueError(f"incomplete {simulator} baseline")
            validate_runtime_tool(root, attempt)
            image_path = check_artifact(attempt["image_manifest"])
            image = read_json(image_path)
            selected, _ = retained_image(evidence, Path(image["artifacts"]["tiny_baseline.hex"]["path"]))
            if selected != image_path:
                raise ValueError("image provenance points to a different retained manifest")
            check_artifact(attempt["model"])
            source = attempt["rtl_source"]
            inputs = read_json(check_artifact(source["inputs"]))
            if inputs != source_inputs(root) | runtime_inputs(root, variant, simulator):
                raise ValueError(f"stale {simulator} source inputs")
            check_artifact(source["snapshot"])
            validate_runs(attempt["runs"])
            result["simulators"][simulator] = {"attempt": artifact(path), **attempt}
        first, second = (result["simulators"][name] for name in ("verilator", "iverilog"))
        if first["image_sha256"] != second["image_sha256"]:
            raise ValueError("simulators did not replay an identical binary")
        if first["runs"][0]["samples"] != second["runs"][0]["samples"]:
            raise ValueError("simulators disagree on workload or cycle measurements")
        result["status"] = "passed"
    except (OSError, ValueError, KeyError) as error:
        result["error"] = str(error)
    dump(output, result)
    print(f"Tiny baseline report: {result['status']} ({output})")
    return int(result["status"] != "passed")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=ROOT)
    parser.add_argument("--variant-root", type=Path, required=True)
    commands = parser.add_subparsers(dest="action", required=True)
    image = commands.add_parser("image")
    for name in ("objcopy", "objdump", "nm", "size"):
        image.add_argument("--" + name, default="riscv32-unknown-elf-" + name)
    image.add_argument("command", nargs=argparse.REMAINDER)
    simulation = commands.add_parser("simulate")
    simulation.add_argument("--simulator", choices=("verilator", "iverilog"), required=True)
    simulation.add_argument("--hex", type=Path)
    simulation.add_argument("--timeout", type=int, default=1800)
    simulation.add_argument("--max-cycles", type=int, default=100000000)
    simulation.add_argument("--jobs", type=int, default=1)
    simulation.add_argument("--vvp", default="vvp")
    simulation.add_argument("command", nargs=argparse.REMAINDER)
    commands.add_parser("report")
    args = parser.parse_args()
    if args.action == "simulate" and min(args.jobs, args.timeout, args.max_cycles) <= 0:
        parser.error("simulation jobs, timeout and cycle limit must be positive")
    variant = args.variant_root.resolve()
    if not variant.is_relative_to(args.root.resolve() / "build"):
        parser.error("baseline evidence must be below this repository's build variants")
    try:
        return {"image": build_image, "simulate": simulate, "report": report}[args.action](args)
    except (OSError, ValueError, KeyError, subprocess.SubprocessError) as error:
        print(f"Tiny R2 baseline: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
