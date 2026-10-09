#!/usr/bin/env python3
"""Source-bound Tiny P3 compiler/placement experiments, separate from P1 replay."""

from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
import re
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from scripts import tiny_r2_baseline as baseline  # noqa: E402
from scripts.check_simulation import DEFAULT_FAILURE  # noqa: E402
from scripts.check_c_warnings import self_owned_warnings  # noqa: E402
from scripts.setup_helpers import sha256  # noqa: E402

PHASE = "TINY-R2-P3"
CASES = (*baseline.CASES, "chunk256")
PARAMETERS = dict(baseline.PARAMETERS, version=3, jobs=4)
MATRIX = [("compat-os-flat", "COMPAT", "Os", "NO", "ld2_all_sram")]
MATRIX += [(f"perf-{opt.lower()}-{'lto' if lto == 'YES' else 'plain'}-flat",
            "TINY_PERF", opt, lto, "ld2_all_sram")
           for opt in ("O2", "O3", "Os") for lto in ("NO", "YES")]
MATRIX += [("perf-o2-plain-banked", "TINY_PERF", "O2", "NO", "ld2_tiny_banked")]
ICARUS_CASES = {"compat-os-flat", "perf-o2-lto-flat", "perf-o2-plain-banked"}
dump, artifact, read_json = baseline.dump, baseline.artifact, baseline.read_json
execute, check_artifact = baseline.execute, baseline.check_artifact


def execute_make(root: Path, directory: Path, label: str, command: list[str]) -> dict:
    """Run a Make flow directly; avoid nesting run_flow around Make's own flows."""
    log = directory / (label + ".log")
    result = directory / (label + ".json")
    completed = subprocess.run(command, cwd=root, text=True, capture_output=True, check=False)
    log.write_text(completed.stdout + completed.stderr, encoding="utf-8")
    warnings = self_owned_warnings(root, completed.stdout + completed.stderr)
    record = {"status": "passed" if completed.returncode == 0 and not warnings else "failed",
              "exit_code": completed.returncode, "command": command,
              "self_owned_warnings": warnings}
    dump(result, record)
    if completed.returncode != 0:
        raise ValueError(f"Make flow failed; retained result: {result}")
    if warnings:
        raise ValueError(f"self-owned compiler warnings; retained result: {result}")
    return record


def configuration(variant: Path) -> dict:
    manifest = read_json(variant / "meta/manifest.json")
    cfg = manifest["configuration"]
    required = dict(baseline.COMPATIBILITY)
    required.pop("LINK_TYPE")
    if cfg.get("PDK") == "ICS55":
        required.update(PDK="ICS55", HAVE_PLL="YES")
    if any(cfg.get(k) != v for k, v in required.items()) or cfg.get("LINK_TYPE") not in (
        "ld2_all_sram", "ld2_tiny_banked"
    ):
        raise ValueError("P3 requires an explicit Tiny SAFE24 macro configuration")
    if cfg.get("SW_ISA_PROFILE", "COMPAT") not in ("COMPAT", "TINY_PERF"):
        raise ValueError("unknown P3 ISA selection")
    return manifest


def inputs(root: Path, variant: Path) -> dict:
    result = baseline.source_inputs(root, configuration(variant)["configuration"]["PDK"])
    for path in (root / "configs").rglob("*.mk"):
        result[str(path.relative_to(root))] = sha256(path)
    result["docs/ip/tiny-soc.md"] = sha256(root / "docs/ip/tiny-soc.md")
    extra = subprocess.check_output(
        ["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z", "--", "rtl/mini", "tests"],
        cwd=root).decode().split("\0")
    for name in extra:
        path = root / name
        if name and path.is_file() and path.suffix not in (".md", ".png", ".pdf"):
            result[name] = sha256(path)
    return result


def evidence(variant: Path) -> Path:
    return variant / "meta/tiny-r2-p3"


def new_record(variant: Path, group: str) -> tuple[Path, dict]:
    directory = baseline.new_attempt(evidence(variant) / group, "attempt-")
    dump(directory.parent / "latest.json", {"path": str(directory / "record.json")})
    record = {"schema_version": 1, "phase": PHASE, "status": "running"}
    dump(directory / "record.json", record)
    return directory, record


def selected(variant: Path, group: str) -> Path:
    return Path(read_json(evidence(variant) / group / "latest.json")["path"])


def symbol(symbols: str, name: str) -> tuple[int, int]:
    match = re.search(r"^([0-9a-f]+)(?: ([0-9a-f]+))? [A-Za-z] " + re.escape(name)
                      + r"(?:\.lto_priv\.\d+)?$", symbols, re.M)
    if match is None:
        raise ValueError(f"missing ELF symbol: {name}")
    return int(match[1], 16), int(match[2] or "0", 16)


def check_layout(symbols: str, banked: bool, stack_point_override: int | None = None) -> dict:
    names = ("rs_p3_source", "rs_p3_destinations", "rs_p3_tcds", "rs_p3_dma_cookie")
    locations = {name: symbol(symbols, name) for name in names}
    low, high = (0x30018000, 0x30020000) if banked else (0x30000000, 0x30020000)
    for name, (address, size) in locations.items():
        if size == 0 or address < low or address + size > high:
            raise ValueError(f"DMA placement outside declared aperture: {name}")
        if name != "rs_p3_dma_cookie" and address % 64:
            raise ValueError(f"DMA buffer/TCD alignment: {name}")
    tcd, length = locations["rs_p3_tcds"]
    if length != 1024:
        raise ValueError("P3 requires exactly sixteen 64-byte descriptors")
    stack = stack_point_override if stack_point_override is not None else symbol(symbols, "_stack_point")[0]
    end, _ = symbol(symbols, "_ebss")
    if stack != (0x30018000 if banked else 0x30020000) or end > stack - 4096:
        raise ValueError("missing 4 KiB stack reserve")
    if banked:
        for name in ("main", "system_trap_entry", "rs_p3_isa_check", "rs_p3_patch_target"):
            address, _ = symbol(symbols, name)
            if not 0x30000000 <= address < 0x30010000:
                raise ValueError(f"hot code outside B0/B1: {name}")
        for start, stop in (("_copy_table_start", "_copy_table_end"),
                            ("_zero_table_start", "_zero_table_end")):
            if symbol(symbols, stop)[0] <= symbol(symbols, start)[0]:
                raise ValueError("empty startup initialization table")
    return {"placements": locations, "descriptor_range": [tcd, tcd + length],
            "stack_reserved": 4096, "stack_headroom": stack - end}


def check_exception_probe(disassembly: str) -> None:
    probe = re.search(r"<rs_mcu_unmapped_probe>:\n(.*?)(?:\n\n|\Z)", disassembly, re.S)
    if probe is None or not re.search(r"\b00052503\s+lw\s+a0,0\(a0\)", probe[1]):
        raise ValueError("exception probe must retain a 32-bit faulting load for MEPC += 4")


def image(args: argparse.Namespace) -> int:
    root, variant = args.root, args.variant_root
    directory, record = new_record(variant, "images")
    try:
        before = inputs(root, variant)
        generated = {str(p.relative_to(root)): sha256(p)
                     for folder in (variant / "generated/tiny", variant / "sw/include")
                     for p in folder.rglob("*") if p.is_file()}
        record.update(configuration=configuration(variant), tools=baseline.tools_identity(root),
                      source_digest=baseline.digest_map(before),
                      source=baseline.snapshot(root, directory / "inputs", before | generated))
        elf = directory / "tiny_p3.elf"
        command = args.command[1:] if args.command[:1] == ["--"] else args.command
        if not command:
            raise ValueError("compiler command required")
        if Path(shutil.which(command[0]) or command[0]).resolve() != Path(
            record["tools"]["riscv_gnu"]["executable"]["path"]
        ).resolve():
            raise ValueError("compiler command does not use the locked GNU executable")
        command = [*command, "-Wl,-Map," + str(directory / "tiny_p3.map"), "-o", str(elf)]
        execute(root, directory, "compile", command, cwd=variant / "sw", quiet=True)
        if self_owned_warnings(root, (directory / "compile.log").read_text()):
            raise ValueError("self-owned compiler warnings")
        for suffix, form in (("hex", "verilog"), ("bin", "binary")):
            execute(root, directory, "objcopy-" + suffix,
                    ["riscv32-unknown-elf-objcopy", "-O", form, str(elf),
                     str(directory / ("tiny_p3." + suffix))], quiet=True)
        for label, tool, flags in (("symbols", "nm", ["-S", "-n"]),
                                    ("disassembly", "objdump", ["-d"]),
                                    ("sections", "objdump", ["-h"]),
                                    ("attributes", "readelf", ["-A"]),
                                    ("size", "size", ["-A"])):
            execute(root, directory, label, ["riscv32-unknown-elf-" + tool, *flags, str(elf)], quiet=True)
        execute(root, directory, "normal-disassembly",
                ["riscv32-unknown-elf-objdump", "-d", str(variant / "sw/firmware")], quiet=True)
        check_exception_probe((directory / "normal-disassembly.log").read_text())
        cfg = record["configuration"]["configuration"]
        symbols_text = (directory / "symbols.log").read_text()
        banked = cfg["LINK_TYPE"] == "ld2_tiny_banked"
        try:
            layout = check_layout(symbols_text, banked)
        except ValueError as error:
            if banked or "_stack_point" not in str(error):
                raise
            map_text = (directory / "tiny_p3.map").read_text()
            stack_match = re.search(r"0x([0-9a-fA-F]+)\s+PROVIDE \(_stack_point = \.\)", map_text)
            if stack_match is None:
                raise
            layout = check_layout(symbols_text, False, int(stack_match.group(1), 16))
        disassembly = (directory / "disassembly.log").read_text()
        if cfg.get("SW_ISA_PROFILE") == "TINY_PERF":
            for mnemonic in ("sh1add", "clz", "clmul", "pack", "xperm4", "bset"):
                if not re.search(r"\s" + mnemonic + r"\s", disassembly):
                    raise ValueError(f"missing instruction evidence: {mnemonic}")
        if before != inputs(root, variant) or any(sha256(root / p) != h for p, h in generated.items()):
            raise ValueError("inputs changed during compilation")
        record.update(status="passed", compiler_command=command, parameters=PARAMETERS,
                      layout=layout, artifacts={p.name: artifact(p) for p in directory.iterdir()
                                               if p.is_file() and p.name != "record.json"})
        (directory / "normal").mkdir()
        for name in ("firmware", "retrosoc_fw.hex", "retrosoc_fw.map"):
            shutil.copyfile(variant / "sw" / name, directory / "normal" / name)
        record["normal_firmware"] = {name: artifact(directory / "normal" / name)
                                     for name in ("firmware", "retrosoc_fw.hex", "retrosoc_fw.map")}
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        record.update(status="failed", error=str(error))
        raise
    finally:
        dump(directory / "record.json", record)
    print(f"P3 image retained: {directory}", flush=True)
    return 0


def parse_log(log: str, flow: dict) -> dict:
    if flow.get("status") != "passed" or flow.get("exit_code") != 0 or DEFAULT_FAILURE.search(log):
        raise ValueError("failed simulator command or forbidden marker")
    if "SIM_TEST_PASS Tiny" not in log or "P3_ERROR" in log or log.count("P3_ISA PASS") != 1:
        raise ValueError("missing strict Tiny/ISA acceptance")
    parsed = {"cases": [], "axi": [], "ahb": []}
    headers = re.findall(r"^P3_HEADER (.+)$", log, re.M)
    if len(headers) != 1 or baseline.parse_fields("P3_HEADER " + headers[0], set(PARAMETERS)) != PARAMETERS:
        raise ValueError("wrong experiment parameters")
    for line in log.splitlines():
        for prefix, key, fields, strings in (
            ("P3_CASE ", "cases", baseline.CASE_FIELDS, {"name"}),
            ("R2_AXI ", "axi", baseline.AXI_FIELDS, set()),
            ("R2_AHB ", "ahb", baseline.AHB_FIELDS, set()),
        ):
            if line.startswith(prefix):
                parsed[key].append(baseline.parse_fields(line, fields, strings=strings))
    parsed["cases"].sort(key=lambda row: row["id"])
    if len(parsed["cases"]) != 8 or log.count("P3_COMPLETE version=3 cases=8") != 1:
        raise ValueError("incomplete experiment")
    for index, row in enumerate(parsed["cases"]):
        if row["id"] != index or row["name"] != CASES[index] or row["sram_errors"]:
            raise ValueError("wrong case or SRAM error")
        checksum = 0 if index == 0 else 0xf6e37410 if index == 1 else 0xc4a58dc5
        calls = 1 if index == 1 else 4 if index in (5, 6, 7) else 0
        if (row["checksum"] != checksum or row["payload_bytes"] != (16384 if index >= 2 else 0)
                or row["kernel_calls"] != calls or not row["cycles"] or not row["instructions"]):
            raise ValueError("data/workload accounting mismatch")
    for key, kind in (("axi", "owner"), ("ahb", "kind")):
        parsed[key].sort(key=lambda row: (row["window"], row[kind]))
        if [(r["window"], r[kind]) for r in parsed[key]] != [(w, k) for w in range(1, 9) for k in range(2)]:
            raise ValueError("missing or duplicate observer records")
    for row in parsed["axi"]:
        if row["owner"] == 1:
            payload = 16384 if row["window"] >= 4 else 0
            descriptors = 1024 if row["window"] == 7 else 0
            if (row["read_bytes"] != payload or row["write_bytes"] != payload
                    or row["descriptor_bytes"] != descriptors or row["pending_reads"]
                    or row["pending_writes"] or row["reads"] != row["read_done"]
                    or row["writes"] != row["write_done"]):
                raise ValueError("DMA payload/descriptor/drain accounting mismatch")
    stack = re.findall(r"^P3_STACK reserved=4096 observed=(\d+)$", log, re.M)
    if len(stack) != 1 or not 0 < int(stack[0]) < 4096:
        raise ValueError("missing stack observation or exhausted stack")
    parsed["stack_observed"] = int(stack[0])
    return parsed


def validate_image(path: Path) -> dict:
    image_record = read_json(path)
    if image_record.get("phase") != PHASE or image_record.get("status") != "passed":
        raise ValueError("not a completed P3 image")
    for item in image_record["artifacts"].values():
        check_artifact(item)
    for item in image_record.get("normal_firmware", {}).values():
        check_artifact(item)
    for name in ("inputs", "snapshot", "patch"):
        check_artifact(image_record["source"][name])
    if read_json(path.parent / "compile.json")["command"] != image_record["compiler_command"]:
        raise ValueError("compiler command provenance mismatch")
    return image_record


def simulate(args: argparse.Namespace) -> int:
    root, variant = args.root, args.variant_root
    directory, record = new_record(variant, "runs/" + args.simulator)
    try:
        image_path = args.image or selected(variant, "images")
        if image_path.suffix == ".hex":
            image_path = image_path.parent / "record.json"
        image_record = validate_image(image_path)
        cfg = configuration(variant)
        if image_record["configuration"]["configuration"] != cfg["configuration"]:
            # Simulator selection is a flow, not an architecture/compiler input.
            a, b = (dict(c["configuration"]) for c in (image_record["configuration"], cfg))
            for key in ("SIMU", "SYNTH", "STA", "SYNTH_RECIPE"):
                a.pop(key, None)
                b.pop(key, None)
            if a != b:
                raise ValueError("image and model configurations differ")
        before = inputs(root, variant)
        captured = read_json(check_artifact(image_record["source"]["inputs"]))
        if any(captured.get(name) != digest for name, digest in before.items()):
            raise ValueError("P3 image was not compiled from the current experiment source")
        tools = baseline.tools_identity(root)
        command = args.command[1:] if args.command[:1] == ["--"] else args.command
        if not command:
            raise ValueError("fresh model compilation command required")
        execute_make(root, directory, "compile-model", command)
        if before != inputs(root, variant):
            raise ValueError("source changed while compiling model")
        runtime = baseline.runtime_inputs(root, variant, args.simulator)
        record.update(image=artifact(image_path), configuration=cfg, tools=tools,
                      source_digest=baseline.digest_map(before),
                      source=baseline.snapshot(root, directory / "inputs", before | runtime), runs=[])
        record["compilation"] = {suffix: artifact(directory / ("compile-model." + suffix))
                                 for suffix in ("log", "json")}
        model = variant / "sim" / args.simulator / ("emu" if args.simulator == "verilator" else "simv")
        record["model"] = artifact(model)
        launch = [str(model)]
        if args.simulator == "iverilog":
            record["runtime_tool"] = baseline.vvp_identity("vvp", tools["iverilog"])
            launch.insert(0, record["runtime_tool"]["executable"]["path"])
        start, end = image_record["layout"]["descriptor_range"]
        launch += ["+firmware=" + image_record["artifacts"]["tiny_p3.hex"]["path"],
                   "+tiny_r2_p3", f"+baseline_tcd_base={start:x}", f"+baseline_tcd_end={end:x}",
                   "+max_cycles=100000000"]
        record.update(command=launch, timeout_seconds=args.timeout)

        def once(repetition: int) -> dict:
            label = f"run-{repetition}"
            check_artifact(record["model"])
            validate_image(image_path)
            flow = execute(root, directory, label,
                           ["timeout", "--foreground", f"{args.timeout}s", *launch], quiet=True)
            log = directory / (label + ".log")
            samples = parse_log(log.read_text(), flow)
            return {"repetition": repetition, "log": artifact(log),
                    "flow": artifact(directory / (label + ".json")), "samples": samples}

        with ThreadPoolExecutor(max_workers=min(args.jobs, 3)) as pool:
            futures = [pool.submit(once, repeat) for repeat in (1, 2, 3)]
            errors = []
            for future in as_completed(futures):
                try:
                    record["runs"].append(future.result())
                except (OSError, ValueError, subprocess.SubprocessError) as error:
                    errors.append(str(error))
                dump(directory / "record.json", record)
            if errors:
                raise ValueError("; ".join(errors))
        record["runs"].sort(key=lambda run: run["repetition"])
        if any(run["samples"] != record["runs"][0]["samples"] for run in record["runs"]):
            raise ValueError("cold-start samples are not deterministic")
        if before != inputs(root, variant) or runtime != baseline.runtime_inputs(root, variant, args.simulator):
            raise ValueError("source/model inputs changed during execution")
        check_artifact(record["model"])
        validate_image(image_path)
        record["status"] = "passed"
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        record.update(status="failed", error=str(error))
        raise
    finally:
        dump(directory / "record.json", record)
    print(f"P3 {args.simulator}: three deterministic runs at {directory}", flush=True)
    return 0


def validate_simulation(descriptor: dict, image_descriptor: dict, simulator: str) -> dict:
    run = read_json(check_artifact(descriptor))
    image_record = validate_image(check_artifact(image_descriptor))
    if (run.get("status") != "passed" or run.get("phase") != PHASE or run["image"] != image_descriptor
            or run["source_digest"] != image_record["source_digest"]):
        raise ValueError("failed or mismatched simulation source/image")
    check_artifact(run["model"])
    for item in run["compilation"].values():
        check_artifact(item)
    if read_json(check_artifact(run["compilation"]["json"]))["status"] != "passed":
        raise ValueError("unsuccessful model compilation")
    source_map = read_json(check_artifact(run["source"]["inputs"]))
    if baseline.digest_map(source_map) != run["source"]["input_digest"]:
        raise ValueError("model input digest mismatch")
    for name in ("snapshot", "patch"):
        check_artifact(run["source"][name])
    for tool in run["tools"].values():
        check_artifact(tool["executable"])
        check_artifact(tool["archive"])
    expected = [run["model"]["path"]]
    if simulator == "iverilog":
        runtime = check_artifact(run["runtime_tool"]["executable"])
        if runtime.resolve().parent != Path(run["tools"]["iverilog"]["executable"]["path"]).resolve().parent:
            raise ValueError("mixed Icarus runtime installation")
        expected.insert(0, str(runtime))
    first, end = image_record["layout"]["descriptor_range"]
    expected += ["+firmware=" + image_record["artifacts"]["tiny_p3.hex"]["path"], "+tiny_r2_p3",
                 f"+baseline_tcd_base={first:x}", f"+baseline_tcd_end={end:x}", "+max_cycles=100000000"]
    if run["command"] != expected or run["timeout_seconds"] <= 0:
        raise ValueError("wrong model/image/observer launch")
    if sorted(r["repetition"] for r in run["runs"]) != [1, 2, 3]:
        raise ValueError("missing/duplicate cold start")
    samples = None
    for repetition in run["runs"]:
        flow = read_json(check_artifact(repetition["flow"]))
        if flow["command"] != ["timeout", "--foreground", f"{run['timeout_seconds']}s", *expected]:
            raise ValueError("launch provenance mismatch")
        parsed = parse_log(check_artifact(repetition["log"]).read_text(), flow)
        if parsed != repetition["samples"] or (samples is not None and samples != parsed):
            raise ValueError("changed or mismatched samples")
        samples = parsed
    return samples


def check_acceptance(entry: dict) -> None:
    flow = read_json(check_artifact(entry["acceptance"]["flow"]))
    log = check_artifact(entry["acceptance"]["log"]).read_text()
    if (flow.get("exit_code") != 0 or flow.get("status") != "passed" or DEFAULT_FAILURE.search(log)
            or "SIM_TEST_PASS Tiny" not in log):
        raise ValueError("normal Tiny application did not pass")


def matrix(args: argparse.Namespace) -> int:
    source_digest = baseline.digest_map(inputs(args.root, args.variant_root))
    if args.resume:
        path = selected(args.variant_root, "matrix")
        directory, record = path.parent, read_json(path)
        if record.get("source_digest") != source_digest or record.get("phase") != PHASE:
            raise ValueError("resume requires identical source/specification/inputs")
        record["status"] = "running"
    else:
        directory, record = new_record(args.variant_root, "matrix")
        record.update(cases=[], source_digest=source_digest)
    try:
        if configuration(args.variant_root)["configuration"]["PDK"] != "ICS55":
            raise ValueError("P3 compiler matrix uses the ICS55 default platform")
        for name, isa, opt, lto, layout in MATRIX:
            print(f"P3 matrix case={name} isa={isa} opt={opt} lto={lto} layout={layout}", flush=True)
            command = ["make", "--no-print-directory", "CONFIG=configs/benchmark/ics55-tiny-performance.mk",
                       "SOC=TINY", "PDK=ICS55", "BUILD_TIMESTAMP=" + args.timestamp,
                       "SW_ISA_PROFILE=" + isa, "SW_OPT=" + opt, "SW_LTO=" + lto,
                       "LINK_TYPE=" + layout, "SOC_SIM_TIME=" + str(args.timeout),
                       "JOBS=" + str(args.jobs)]
            config = subprocess.check_output([*command, "-s", "config"], cwd=args.root, text=True)
            variant = Path(re.search(r"^VARIANT_ROOT\s+(.+)$", config, re.M)[1])
            entry = next((c for c in record["cases"] if c["name"] == name), None)
            if entry is None:
                entry = {"name": name, "variant": str(variant), "simulations": {}, "command": command}
                record["cases"].append(entry)
            if "image" not in entry:
                print(f"P3 matrix {name}: image", flush=True)
                execute_make(args.root, directory, name + "-image", [*command, "tiny-r2-p3-image"])
                entry["image"] = artifact(selected(variant, "images"))
            validate_image(check_artifact(entry["image"]))
            if "acceptance" not in entry:
                print(f"P3 matrix {name}: acceptance", flush=True)
                execute_make(args.root, directory, name + "-acceptance",
                             [*command, "SIMU=VERILATOR", "firmware", "sim"])
                entry["acceptance"] = {"flow": artifact(variant / "sim/verilator/result-sim.json"),
                                       "log": artifact(variant / "sim/verilator/sim.log")}
            check_acceptance(entry)
            if "verilator" not in entry["simulations"]:
                print(f"P3 matrix {name}: verilator", flush=True)
                execute_make(args.root, directory, name + "-verilator",
                             [*command, "SIMU=VERILATOR", "tiny-r2-p3-sim"])
                entry["simulations"]["verilator"] = artifact(selected(variant, "runs/verilator"))
            validate_simulation(entry["simulations"]["verilator"], entry["image"], "verilator")
            dump(directory / "record.json", record)
            print("P3 matrix completed: " + name, flush=True)
        # Finish fast coverage before the three long native Icarus groups.
        for entry in record["cases"]:
            if entry["name"] not in ICARUS_CASES:
                continue
            if "iverilog" not in entry["simulations"]:
                print(f"P3 matrix {entry['name']}: iverilog", flush=True)
                execute_make(args.root, directory, entry["name"] + "-iverilog",
                             [*entry["command"], "SIMU=IVERILOG", "tiny-r2-p3-sim"])
                entry["simulations"]["iverilog"] = artifact(selected(Path(entry["variant"]), "runs/iverilog"))
            validate_simulation(entry["simulations"]["iverilog"], entry["image"], "iverilog")
            dump(directory / "record.json", record)
        record["status"] = "passed"
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        record.update(status="failed", error=str(error))
        raise
    finally:
        dump(directory / "record.json", record)
    return 0


def report(args: argparse.Namespace) -> int:
    matrix_path = selected(args.variant_root, "matrix")
    campaign = read_json(matrix_path)
    if campaign.get("status") != "passed" or [c["name"] for c in campaign["cases"]] != [c[0] for c in MATRIX]:
        raise ValueError("incomplete compiler matrix")
    if campaign.get("source_digest") != baseline.digest_map(inputs(args.root, args.variant_root)):
        raise ValueError("experiment source changed since matrix execution")
    summary = []
    for case in campaign["cases"]:
        image_record = validate_image(check_artifact(case["image"]))
        check_acceptance(case)
        samples = None
        required = {"verilator", "iverilog"} if case["name"] in ICARUS_CASES else {"verilator"}
        if set(case["simulations"]) != required:
            raise ValueError("missing selected simulator")
        for selected_sim, descriptor in case["simulations"].items():
            parsed = validate_simulation(descriptor, case["image"], selected_sim)
            if samples is not None and samples != parsed:
                raise ValueError("cross-simulator samples differ")
            samples = parsed
        summary.append({"name": case["name"], "image": case["image"], "layout": image_record["layout"],
                        "samples": samples,
                        "cpi": [r["cycles"] / r["instructions"] for r in samples["cases"]]})
    output = evidence(args.variant_root) / "report.json"
    dump(output, {"phase": PHASE, "status": "measurement_complete", "matrix": artifact(matrix_path),
                  "cases": summary, "qualification": "Software experiments only; phase gates remain in ledger",
                  "bank_conflicts": "unavailable: P4 hardware is not implemented"})
    print(output)
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=ROOT)
    parser.add_argument("--variant-root", type=Path, required=True)
    commands = parser.add_subparsers(dest="action", required=True)
    image_parser = commands.add_parser("image")
    image_parser.add_argument("command", nargs=argparse.REMAINDER)
    sim = commands.add_parser("simulate")
    sim.add_argument("--simulator", choices=("verilator", "iverilog"), required=True)
    sim.add_argument("--image", type=Path)
    sim.add_argument("--timeout", type=int, default=21600)
    sim.add_argument("--jobs", type=int, default=3)
    sim.add_argument("command", nargs=argparse.REMAINDER)
    campaign = commands.add_parser("matrix")
    campaign.add_argument("--timestamp", required=True)
    campaign.add_argument("--timeout", type=int, default=21600)
    campaign.add_argument("--jobs", type=int, default=3)
    campaign.add_argument("--resume", action="store_true")
    commands.add_parser("report")
    args = parser.parse_args()
    args.root, args.variant_root = args.root.resolve(), args.variant_root.resolve()
    if not args.variant_root.is_relative_to(args.root / "build"):
        parser.error("P3 evidence must be below repository build/")
    if getattr(args, "timeout", 1) <= 0 or getattr(args, "jobs", 1) <= 0:
        parser.error("positive timeout/jobs required")
    try:
        return {"image": image, "simulate": simulate, "matrix": matrix, "report": report}[args.action](args)
    except (OSError, ValueError, KeyError, subprocess.SubprocessError) as error:
        print(f"P3: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
