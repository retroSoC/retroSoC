"""Single-execution, source-bound Tiny P10 measurements; never phase signoff."""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from scripts import tiny_r2_baseline as b  # noqa: E402
from scripts import tiny_r2_p3 as p3  # noqa: E402
from scripts import tiny_r2_p4 as p4  # noqa: E402
from scripts import tiny_r2_p5 as p5  # noqa: E402
from scripts import tiny_r2_p6 as p6  # noqa: E402
from scripts.check_simulation import DEFAULT_FAILURE  # noqa: E402
from scripts.check_c_warnings import self_owned_warnings  # noqa: E402

PHASE = "TINY-R2-P10"
COLLECTOR_UPDATE_PATHS = {"scripts/tiny_r2_p10.py", "tests/test_tiny_r2_p10.py"}
STAGES = ("matched", "software", "audio", "camera", "backend", "report")
P1 = "build/ihp130-tiny-2026-10-05-20-02-fa1c4ce1e303/meta/tiny-r2-p1/baseline-report.json"
P3 = "build/ics55-tiny-performance-2026-10-09-17-10-53cc6674d532/meta/tiny-r2-p3/report.json"
P5 = "build/ics55-tiny-2026-10-10-18-58-b4aa59f3e5d9/meta/tiny-r2-p5/report.json"
MATCHED = ("perf-o2-plain-flat", "perf-o2-plain-banked")
BUS_FIELDS = set("window owner reads writes read_done write_done read_initial write_initial "
                 "read_pending write_pending read_bytes write_bytes errors read_latency_max "
                 "write_latency_max ar_max r_max aw_max w_max b_max".split())
CONCURRENCY_FIELDS = set("window active_targets_max bank_overlap dma_beat_overlap".split())
DEFERRED = ["full long Icarus firmware: maintainer deferred to final Tiny qualification",
            "complete PR/nightly: retained matrix includes deferred Icarus and P7 clock transitions",
            "fresh full-system VGA: historical evidence retained",
            "physical/PVT/board/sensor and higher-frequency qualification"]


def rows(content: str, prefix: str, fields: set[str]) -> list[dict]:
    return [b.parse_fields(line, fields) for line in content.splitlines()
            if line.startswith(prefix + " ")]


def require_terminal(content: str, flow: dict) -> None:
    if (flow.get("exit_code") != 0 or flow.get("status") != "passed" or
            DEFAULT_FAILURE.search(content) or len(re.findall(
                r"^SIM_TEST_PASS Tiny cycles=[1-9][0-9]*$", content, re.M)) != 1):
        raise ValueError("Tiny command/terminal/forbidden-marker verdict failed")


def golden() -> tuple[list[int], int]:
    """Independent byte/pixel oracle, not firmware's packed-word implementation."""
    histogram = [0] * 32
    checksum = 2166136261
    for row in range(240):
        pixels = [(((2 * x + 3 * row) & 255) << 8) | ((2 * x + 3 * row + 1) & 255)
                  for x in range(320)]
        for pixel in pixels:
            histogram[pixel >> 11] += 1
        for x in range(0, 320, 2):
            checksum = ((checksum ^ (pixels[x] | (pixels[x + 1] << 16))) * 16777619) & 0xffffffff
    return histogram, checksum


def check_observations(content: str, windows: int, targets: int) -> dict:
    bus = rows(content, "P10_BUS", BUS_FIELDS)
    concurrency = rows(content, "P10_CONCURRENCY", CONCURRENCY_FIELDS)
    if [(r["window"], r["owner"]) for r in bus] != [
            (window, owner) for window in range(1, windows + 1) for owner in range(3)]:
        raise ValueError("missing, reordered or duplicate bus observation")
    if [r["window"] for r in concurrency] != list(range(1, windows + 1)):
        raise ValueError("incomplete concurrency windows")
    for row in bus:
        for direction in ("read", "write"):
            initial, pending = row[direction + "_initial"], row[direction + "_pending"]
            if (initial > 1 or pending > 1 or row[direction + "s"] + initial !=
                    row[direction + "_done"] + pending):
                raise ValueError("transaction conservation mismatch")
        if row["errors"]:
            raise ValueError("bus error inside successful workload window")
    if any(r["active_targets_max"] > targets for r in concurrency):
        raise ValueError("concurrency exceeds canonical topology")
    return {"bus": bus, "concurrency": concurrency,
            "units": "SYS cycles; bytes from actual handshakes; censored CPU transactions retained"}


def camera_measurements(content: str, flow: dict, targets: int) -> dict:
    require_terminal(content, flow)
    histogram, checksum = golden()
    result = rows(content, "P10_RESULT", {"code", "pixels", "bytes", "sectors", "checksum"})
    if result != [dict(code=0, pixels=76800, bytes=153600, sectors=300, checksum=checksum)]:
        raise ValueError("camera pipeline did not complete exact work")
    if rows(content, "P10_HIST", {"bin", "pixels"}) != [
            {"bin": index, "pixels": value} for index, value in enumerate(histogram)]:
        raise ValueError("CPU histogram differs from independent oracle")
    phases = rows(content, "P10_PHASE", {"id", "calls", "bytes", "cycles", "instructions"})
    if len(phases) != 5:
        raise ValueError("missing pipeline phase measurements")
    for index, row in enumerate(phases):
        if (row["id"] != index or row["calls"] != (1 if index < 2 else 150) or
                row["bytes"] != 153600 or not 0 < row["instructions"] <= row["cycles"]):
            raise ValueError("invalid pipeline phase accounting")
    observed = check_observations(content, 452, targets)
    for row in observed["bus"]:
        if row["owner"] != 0 and (row["read_pending"] or row["write_pending"]):
            raise ValueError("DMA work not drained at pipeline boundary")
    # Capture uses DMA2, saving uses the independent SDIO master and SRAM bounce buffers.
    if observed["bus"][1]["write_bytes"] != 153600:
        raise ValueError("camera DMA byte count mismatch")
    sdio = [row for row in observed["bus"] if row["owner"] == 2]
    for sample in sdio:
        # Each HAL call fetches one 16-byte descriptor and writes back its
        # four-byte status. Preserve those bytes in the raw bus observations.
        expected = (0, 0)
        if sample["window"] >= 4 and (sample["window"] - 4) % 3 == 0:
            expected = (1040, 4)
        elif sample["window"] >= 5 and (sample["window"] - 5) % 3 == 0:
            expected = (16, 1028)
        if (sample["read_bytes"], sample["write_bytes"]) != expected:
            raise ValueError("SDIO payload/descriptor/writeback accounting mismatch")
    fifo = rows(content, "P9_OBSERVATION", {"version", "accepted_words", "delivered_words",
                                           "fifo_high_water", "backpressure", "pixel_half_ns"})
    if len(fifo) != 1:
        raise ValueError("missing pixel FIFO observations")
    row = fifo[0]
    available = 512 - 4 * row["fifo_high_water"] - 16
    if (row["version"] != 1 or row["accepted_words"] != 38400 or row["delivered_words"] != 38400 or
            row["fifo_high_water"] == 0 or available <= 0 or row["pixel_half_ns"] != 500 or
            row["backpressure"] >= available * 24):
        raise ValueError("capture FIFO/rate budget invalid")
    return {"phases": phases, "histogram": histogram, "checksum": checksum,
            "observations": observed, "fifo": row,
            "sdio_bytes": {"payload_read": 153600, "payload_write": 153600,
                           "descriptor_read": 4800, "descriptor_writeback": 1200,
                           "observed_read": sum(r["read_bytes"] for r in sdio),
                           "observed_write": sum(r["write_bytes"] for r in sdio)},
            "service_budget": {"payload_bytes": 512, "margin_bytes": 16,
                               "empty_no_service_us": 496, "pixel_hz": 1000000,
                               "high_water_no_service_us": available,
                               "observed_backpressure_us": row["backpressure"] / 24}}


def audio_measurements(content: str, flow: dict, targets: int) -> dict:
    require_terminal(content, flow)
    result = p6.parse_log(content, flow)
    result["window_observations"] = check_observations(content, 2, targets)
    if not any(r["bank_overlap"] for r in result["window_observations"]["concurrency"]):
        raise ValueError("no useful independent-bank overlap observed")
    return result


def sources(root: Path, pdk: str) -> dict:
    result = b.source_inputs(root, pdk)
    names = subprocess.check_output(["git", "ls-files", "--cached", "--others", "--exclude-standard",
                                     "-z", "--", "tests", "configs"], cwd=root, text=True).split("\0")
    for name in [*names, "docs/ip/tiny-soc.md"]:
        path = root / name
        if name and path.is_file():
            result[name] = b.sha256(path)
    return result


def make_command(args, stage: str) -> list[str]:
    command = ["make", "--no-print-directory", f"CONFIG=configs/ci/{args.pdk.lower()}-tiny.mk",
               "SOC=TINY", f"PDK={args.pdk}", "APP=ci_smoke", "SYNTH=NONE", "STA=NONE",
               f"BUILD_TIMESTAMP={args.timestamp}", f"JOBS={args.jobs}"]
    if stage in ("matched", "software"):
        command += ["SIMU=VERILATOR", "FIRMWARE_NAME=retrosoc_p10_replay"]
    elif stage in ("audio", "camera"):
        command += ["SIMU=VERILATOR", "HAVE_SVA=YES"]
        if stage == "camera":
            command.append("TINY_P10_ACCEPTANCE=YES")
    else:
        command += ["SIMU=IVERILOG"]
    return command


def variant_for(root: Path, command: list[str]) -> Path:
    output = subprocess.check_output([*command, "config"], cwd=root, text=True)
    values = dict(line.split(None, 1) for line in output.splitlines() if line.strip())
    variant = Path(values["VARIANT_ROOT"]).resolve()
    if not variant.is_relative_to(root / "build"):
        raise ValueError("P10 evidence must be below the repository build root")
    return variant


def location(args, stage: str) -> tuple[Path, Path]:
    variant = variant_for(args.root, make_command(args, stage))
    return variant, variant / "meta/tiny-r2-p10" / stage


def capture_artifacts(paths: list[Path]) -> dict:
    return {str(p): b.artifact(p) for p in paths}


def source_delta(record: dict, source: dict, allow_collector_update: bool = False) -> dict:
    original = record.get("source_inputs")
    if not original or not source or record.get("source_after") != original:
        raise ValueError("missing source identity or inputs changed during execution")
    changed = {name: {"before": original.get(name), "after": source.get(name)}
               for name in set(original) | set(source) if original.get(name) != source.get(name)}
    if changed and (not allow_collector_update or not set(changed) <= COLLECTOR_UPDATE_PATHS):
        raise ValueError("execution inputs changed beyond the explicit collector-only update")
    return changed


def checked_record(path: Path, source: dict, *, allow_collector_update: bool = False) -> dict:
    record = b.read_json(path)
    source_delta(record, source, allow_collector_update)
    if (record.get("phase") != PHASE or record.get("status") != "passed" or
            record.get("stage") not in STAGES[:-1] or record.get("stage") != path.parent.name or
            record.get("pdk") not in ("ICS55", "IHP130") or record.get("maximum_attempts") != 1 or
            not record.get("artifacts") or not record.get("tools") or
            not record.get("started_at") or not record.get("finished_at")):
        raise ValueError(f"cannot resume incomplete or changed P10 record: {path}")
    captured = record["source"]
    if (b.read_json(b.check_artifact(captured["inputs"])) != record["source_inputs"] or
            captured["input_digest"] != b.digest_map(record["source_inputs"])):
        raise ValueError("source snapshot differs from stage identity")
    configuration = record["configuration"]["configuration"]
    if (configuration["SOC"] != "TINY" or configuration["PDK"] != record["pdk"] or
            configuration["EXT_CLK_HZ"] != "24000000" or configuration["SRAM_SIZE_KIB"] != "128"):
        raise ValueError("stage is not the selected Tiny SAFE24 profile")
    for artifact in record["artifacts"].values():
        b.check_artifact(artifact)
    for artifact in record["source"].values():
        if isinstance(artifact, dict) and "sha256" in artifact:
            b.check_artifact(artifact)
    for tool in record.get("tools", {}).values():
        b.check_artifact(tool["executable"])
        b.check_artifact(tool["archive"])
    for tool in record.get("host_tools", {}).values():
        b.check_artifact(tool)
    if record.get("stage") in ("audio", "camera"):
        stage = record["stage"]
        flow = b.read_json(path.parent / f"{stage}.json")
        content = (path.parent / f"{stage}.log").read_text()
        parser = camera_measurements if stage == "camera" else audio_measurements
        if parser(content, flow, record["target_count"]) != record["measurements"]:
            raise ValueError("stored measurements differ from retained execution")
    for case in record.get("cases", []):
        label = case["name"]
        flow = b.read_json(path.parent / f"{label}.json")
        content = (path.parent / f"{label}.log").read_text()
        if label == "compat-p1":
            measured = b.parse_log(content, flow)
        else:
            measured = p4.parse_log(content, flow)
            measured["fabric"] = rows(content, "R2_P5_FABRIC", p5.FABRIC_FIELDS)
        if measured != case["samples"]:
            raise ValueError("stored replay measurements differ from execution")
        b.check_artifact(case["image"])
    if record["stage"] in ("matched", "software"):
        expected = set(MATCHED) if record["pdk"] == "ICS55" else {"compat-p1"}
        if record["stage"] == "software":
            expected = {case[0] for case in p3.MATRIX} - set(MATCHED)
        names = [case["name"] for case in record["cases"]]
        if set(names) != expected or len(names) != len(expected):
            raise ValueError("missing or duplicate replay images")
    if record["stage"] == "backend":
        for label in ("firmware-lint", "synthesis", "netlist-boot", "netlist-dvp", "sta"):
            flow = b.read_json(path.parent / f"{label}.json")
            if flow.get("exit_code") != 0 or flow.get("status") != "passed":
                raise ValueError("backend gate failed")
        variant = path.parents[3]
        runtime = b.read_json(path.parent / "vvp-pre-simulation.json")
        for key in ("executable", "archive"):
            b.check_artifact(runtime["runtime"][key])
        for sub in ("sim/iverilog/netl", "sim/iverilog/netl/dvp"):
            directory = variant / sub
            flow = b.read_json(directory / "result-sim.json")
            require_terminal((directory / "sim.log").read_text(), flow)
            if (runtime["runtime"]["executable"]["path"] not in flow["command"] or
                    runtime["captured_at"] > flow["started_at"]):
                raise ValueError("unbound or late-captured Icarus runtime")
        audit = b.read_json(variant / "syn/yosys/tiny-r2-p7-netlist.json")
        for artifact in audit["inputs"]:
            b.check_artifact(artifact)
        if (audit["status"] != "passed" or audit["pdk"] != record["pdk"] or
                audit["binding"]["main_macros"] != 32 or audit["binding"]["private_crypto_macros"] != 6 or
                audit["binding"]["pll_macros"] != int(record["pdk"] == "ICS55")):
            raise ValueError("macro binding audit failed")
    return record


def run_make(args, directory: Path, label: str, command: list[str], *, observation=False) -> dict:
    if (directory / f"{label}.json").exists():
        raise ValueError(f"attempt already exists: {label}")
    print(f"{args.pdk}/{args.stage}: {label}", flush=True)
    record = {"command": command, "status": "running",
              "started_at": datetime.now(timezone.utc).isoformat()}
    with (directory / f"{label}.log").open("w") as log:
        process = subprocess.Popen(command, cwd=args.root, stdout=log, stderr=subprocess.STDOUT)
        record["pid"] = process.pid
        b.dump(directory / f"{label}.json", record)
        code = process.wait()
    warnings = self_owned_warnings(args.root, (directory / f"{label}.log").read_text())
    record.update(exit_code=code, self_owned_warnings=warnings,
                  status="passed" if code == 0 and not warnings else "failed",
                  finished_at=datetime.now(timezone.utc).isoformat())
    b.dump(directory / f"{label}.json", record)
    if not observation and record["status"] != "passed":
        raise ValueError(f"Make gate failed: {directory / (label + '.json')}")
    return record


def simulate(args, directory: Path, label: str, model: Path, image: Path, flags: list[str],
             timeout: int, parse) -> tuple[dict, list[Path]]:
    paths = [model, image]
    identities = capture_artifacts(paths)
    command = ["timeout", "--foreground", "--kill-after=30s", f"{timeout}s", str(model),
               f"+firmware={image}", "+max_cycles=100000000", *flags]
    b.dump(directory / f"{label}-launch.json", {"command": command, "artifacts": identities,
                                               "maximum_attempts": 1})
    flow = b.execute(args.root, directory, label, command, cwd=args.root, quiet=True)
    content = (directory / f"{label}.log").read_text()
    require_terminal(content, flow)
    measurements = parse(content, flow)
    for artifact in identities.values():
        b.check_artifact(artifact)
    return measurements, [*paths, directory / f"{label}.log", directory / f"{label}.json",
                          directory / f"{label}-launch.json"]


def replay(args, variant: Path, directory: Path, record: dict) -> list[Path]:
    command = make_command(args, args.stage)
    model = variant / "sim/verilator/emu"
    artifacts = []
    if args.stage == "matched":
        if model.exists():
            raise ValueError("fresh replay model required")
        run_make(args, directory, "compile-model", [*command, "comp", "manifest"])
    else:
        _, previous = location(args, "matched")
        matched = checked_record(previous / "record.json", record["source_inputs"])
        artifacts += [previous / "record.json"]
        record["matched_stage"] = b.artifact(previous / "record.json")
        if matched["pdk"] != "ICS55":
            raise ValueError("compiler/placement comparison uses ICS55 only")
    configuration = b.read_json(variant / "meta/manifest.json")
    record["configuration"] = configuration
    runtime_before = b.runtime_inputs(args.root, variant, "verilator")
    record["runtime_inputs"] = runtime_before
    record["cases"] = []
    if args.pdk == "IHP130":
        reference = args.root / P1
        original = b.read_json(reference)["simulators"]["verilator"]
        b.validate_runs(original["runs"])
        image_path = b.check_artifact(original["image_manifest"])
        image = b.read_json(image_path)
        firmware = b.check_artifact(image["artifacts"]["tiny_baseline.hex"])
        b.retained_image(image_path.parent.parent.parent, firmware)
        first, end = image["descriptor_range"]
        flags = ["+tiny_r2_baseline", f"+baseline_tcd_base={first:x}", f"+baseline_tcd_end={end:x}"]
        samples, paths = simulate(args, directory, "compat-p1", model, firmware, flags, 10800, b.parse_log)
        record["cases"].append({"name": "compat-p1", "image": b.artifact(image_path),
                                 "samples": samples, "baseline_samples": original["runs"][0]["samples"]})
        artifacts += [reference, image_path, *paths]
    else:
        reference = args.root / (P5 if args.stage == "matched" else P3)
        report = b.read_json(reference)
        if args.stage == "matched":
            old = p5.validate_replay(b.check_artifact(report["executions"]["verilator"]), "verilator")
            cases = old["cases"]
        else:
            cases = p4.reference_cases(reference, [c["name"] for c in report["cases"]
                                                   if c["name"] not in MATCHED])
        for case in cases:
            image_path = b.check_artifact(case["image"])
            image = p3.validate_image(image_path)
            p5.compatible_hardware(image["configuration"], configuration)
            first, end = image["layout"]["descriptor_range"]
            flags = ["+tiny_r2_p3", "+tiny_r2_p5", f"+baseline_tcd_base={first:x}",
                     f"+baseline_tcd_end={end:x}"]
            samples, paths = simulate(args, directory, case["name"], model,
                b.check_artifact(image["artifacts"]["tiny_p3.hex"]), flags, 10800, p4.parse_log)
            fabric = rows((directory / f"{case['name']}.log").read_text(), "R2_P5_FABRIC", p5.FABRIC_FIELDS)
            if [r["window"] for r in fabric] != list(range(1, 9)):
                raise ValueError("missing replay fabric measurements")
            samples["fabric"] = fabric
            record["cases"].append({"name": case["name"], "image": b.artifact(image_path),
                                     "samples": samples, "baseline_samples": case["samples"]})
            artifacts += [image_path, *paths]
            b.dump(directory / "record.json", record)
        artifacts.append(reference)
    if runtime_before != b.runtime_inputs(args.root, variant, "verilator"):
        raise ValueError("replay model inputs changed")
    artifacts += [args.root / name for name in runtime_before]
    return artifacts


def application(args, variant: Path, directory: Path, record: dict) -> list[Path]:
    command = make_command(args, args.stage)
    outputs = [variant / "sw/firmware", variant / "sw/retrosoc_fw.hex", variant / "sim/verilator/emu"]
    if any(p.exists() for p in outputs):
        raise ValueError("fresh application outputs required")
    run_make(args, directory, "build", [*command, "firmware", "comp", "manifest"])
    run_make(args, directory, "size", ["riscv32-unknown-elf-size", str(outputs[0])])
    run_make(args, directory, "symbols", ["riscv32-unknown-elf-nm", "-n", str(outputs[0])])
    size = (directory / "size.log").read_text().splitlines()[-1].split()
    symbols = (directory / "symbols.log").read_text()
    ebss = re.search(r"^([0-9a-f]+) [A-Za-z] _ebss$", symbols, re.M)
    if ebss is None or not 0x30000000 < int(ebss[1], 16) <= 0x30020000 - 4096:
        raise ValueError("application lacks 4 KiB flat-SRAM stack headroom")
    record["firmware_size"] = dict(zip(("text", "data", "bss"), map(int, size[:3]), strict=True))
    record["stack_headroom"] = 0x30020000 - int(ebss[1], 16)
    record["configuration"] = b.read_json(variant / "meta/manifest.json")
    runtime = b.runtime_inputs(args.root, variant, "verilator")
    targets = b.read_json(args.root / "rtl/tiny/integration/soc_topology.json")["fabric"]["target_count"]
    record["target_count"] = targets
    flags = ["+tiny_p10_audio"]
    parse = audio_measurements
    if args.stage == "camera":
        flags = ["+tiny_psram", "+tiny_p9_camera", "+tiny_p9_half_ns=500", "+tiny_p10_camera"]
        parse = camera_measurements
    samples, paths = simulate(args, directory, args.stage, outputs[2], outputs[1], flags,
                              14400 if args.stage == "camera" else 10800,
                              lambda log, flow: parse(log, flow, targets))
    record["measurements"] = samples
    record["runtime_inputs"] = runtime
    if runtime != b.runtime_inputs(args.root, variant, "verilator"):
        raise ValueError("application runtime inputs changed")
    return [*outputs, *paths, variant / "sw/retrosoc_fw.map", variant / "sw/retrosoc_fw.bin",
            variant / "sw/retrosoc_fw.txt", *[args.root / name for name in runtime]]


def backend(args, variant: Path, directory: Path, record: dict) -> list[Path]:
    command = make_command(args, "backend")
    netlist = variant / "syn/yosys/out/retrosoc_tiny_asic_yosys.v"
    if netlist.exists():
        raise ValueError("fresh backend variant required")
    run_make(args, directory, "firmware-lint", [*command, "SIMU=VERILATOR", "firmware", "rtl-lint"])
    run_make(args, directory, "synthesis", [*command, "SYNTH=YOSYS", "YOSYS_TIMEOUT=10800", "synth"])
    runtime_identity = b.vvp_identity("vvp", record["tools"]["iverilog"])
    b.dump(directory / "vvp-pre-simulation.json", {
        "captured_at": datetime.now(timezone.utc).isoformat(), "runtime": runtime_identity})
    command += ["VVP=" + runtime_identity["executable"]["path"]]
    run_make(args, directory, "netlist-boot", [*command, "netsim-boot"])
    model = b.artifact(variant / "sim/iverilog/netl/simv")
    runtime = b.runtime_inputs(args.root, variant, "iverilog")
    run_make(args, directory, "netlist-dvp", [*command, "-o", "netcomp", "netsim-dvp"])
    b.check_artifact(model)
    if runtime != b.runtime_inputs(args.root, variant, "iverilog"):
        raise ValueError("netlist simulator inputs changed between workloads")
    record["runtime_inputs"] = runtime
    run_make(args, directory, "sta", [*command, "STA=OPENSTA", "sta"])
    record["observations"] = {}
    for name in ("check-warnings", "check-metrics"):
        record["observations"][name] = run_make(args, directory, name, [*command, name], observation=True)
    paths = [netlist, netlist.with_suffix(".config"), Path(model["path"])]
    for sub in ("sim/iverilog/netl", "sim/iverilog/netl/dvp"):
        base = variant / sub
        flow = b.read_json(base / "result-sim.json")
        require_terminal((base / "sim.log").read_text(), flow)
        paths += [base / name for name in ("sim.log", "result-sim.json", "result-sim-check.json")]
    paths += [variant / "syn/yosys/tiny-r2-p7-netlist.json", variant / "meta/metrics.json",
              variant / "meta/warnings.json", variant / "sta/opensta/retrosoc_core.sdc"]
    paths += list((variant / "sta/opensta").glob("*.rpt"))
    paths += list((variant / "syn/yosys").glob("*.rpt"))
    paths += [variant / "sw" / name for name in ("tiny_boot.elf", "tiny_boot.hex",
                                                "tiny_p9_netlist.elf", "tiny_p9_netlist.hex")]
    paths += [args.root / name for name in runtime]
    record["configuration"] = b.read_json(variant / "meta/manifest.json")
    record["metrics"] = b.read_json(variant / "meta/metrics.json")
    return paths


def report_stage(args, directory: Path, source: dict) -> int:
    stages = ("matched", "software", "audio", "camera", "backend") if args.pdk == "ICS55" else (
        "matched", "audio", "camera", "backend")
    records, gaps = {}, []
    for stage in stages:
        selected = argparse.Namespace(**vars(args))
        if args.retained_timestamp and stage != "camera":
            selected.timestamp = args.retained_timestamp
        _, parent = location(selected, stage)
        try:
            record = checked_record(parent / "record.json", source,
                                    allow_collector_update=args.allow_collector_update)
            records[stage] = {"record": b.artifact(parent / "record.json"),
                              "execution_source_digest": record["source"]["input_digest"],
                              "validation_input_delta": source_delta(record, source, args.allow_collector_update),
                              "cases": record.get("cases"), "measurements": record.get("measurements"),
                              "metrics": record.get("metrics"), "observations": record.get("observations"),
                              "firmware_size": record.get("firmware_size"),
                              "stack_headroom": record.get("stack_headroom")}
        except (OSError, ValueError) as error:
            gaps.append({"stage": stage, "reason": str(error)})
    directory.mkdir(parents=True, exist_ok=True)
    comparisons = []
    if "matched" in records:
        for case in records["matched"]["cases"]:
            comparisons.append({"name": case["name"], "image": case["image"],
                                "firmware": retained_footprint(case["image"]),
                                "workloads": compare_samples(case["baseline_samples"], case["samples"]),
                                "attribution": "whole platform revision; not an isolated CPU/fabric change"})
    software = []
    if "matched" in records and "software" in records:
        cases = {case["name"]: case for stage in ("matched", "software") for case in records[stage]["cases"]}
        pairs = [("isa", "compat-os-flat", "perf-os-plain-flat"),
                 ("optimizer", "perf-o2-plain-flat", "perf-o3-plain-flat"),
                 ("optimizer", "perf-o2-plain-flat", "perf-os-plain-flat"),
                 ("placement", "perf-o2-plain-flat", "perf-o2-plain-banked")]
        pairs += [("lto", f"perf-{opt}-plain-flat", f"perf-{opt}-lto-flat") for opt in ("o2", "o3", "os")]
        for kind, baseline, candidate in pairs:
            software.append({"kind": kind, "baseline": baseline, "candidate": candidate,
                             "baseline_firmware": retained_footprint(cases[baseline]["image"]),
                             "candidate_firmware": retained_footprint(cases[candidate]["image"]),
                             "workloads": compare_samples(cases[baseline]["samples"], cases[candidate]["samples"])})
    quality = {}
    for timestamp in dict.fromkeys((args.retained_timestamp or args.timestamp, args.timestamp)):
        selected = argparse.Namespace(**vars(args))
        selected.timestamp = timestamp
        _, backend_directory = location(selected, "backend")
        for path in (backend_directory.parent / "validation").glob("*.json"):
            value = b.read_json(path)
            quality[timestamp + "/" + path.stem] = {
                "record": b.artifact(path), "status": value.get("status"), "exit_code": value.get("exit_code")}
    b.dump(directory / "report.json", {"phase": PHASE, "phase_accepted": False, "pdk": args.pdk,
        "status": "selected_gates_complete" if not gaps else "incomplete", "stages": records,
        "gaps": gaps, "deferred": DEFERRED, "matched_comparisons": comparisons,
        "software_comparisons": software, "quality_attempts": quality,
        "collector": b.artifact(Path(__file__)), "validation_source_digest": b.digest_map(source),
        "retained_timestamp": args.retained_timestamp,
        "qualification": "SAFE24 observations only; full regression and human acceptance remain open"})
    return int(bool(gaps))


def retained_footprint(identity: dict) -> dict:
    image = b.read_json(b.check_artifact(identity))
    log = b.check_artifact(image["artifacts"]["size.log"]).read_text()
    sections = {name: int(size) for name, size in re.findall(r"^(\.[\w.]+)\s+(\d+)\s+\d+\s*$", log, re.M)}
    if ".text" not in sections or ".bss" not in sections:
        raise ValueError("retained image lacks section-size evidence")
    return {"sections": sections, "layout": image.get("layout"),
            "stack_headroom": image.get("stack_headroom", image.get("layout", {}).get("stack_headroom")),
            "size_log": image["artifacts"]["size.log"]}


def compare_samples(baseline: dict, candidate: dict) -> list[dict]:
    old = baseline.get("cases", baseline.get("case", []))
    new = candidate.get("cases", candidate.get("case", []))
    if not old or len(old) != len(new):
        raise ValueError("comparison workload mismatch")
    result = []
    for a, z in zip(old, new, strict=True):
        if any(a[key] != z[key] for key in ("name", "payload_bytes", "checksum", "kernel_calls")):
            raise ValueError("comparison is not identical work")
        result.append({"name": a["name"], "payload_bytes": a["payload_bytes"],
                       "baseline_cycles": a["cycles"], "candidate_cycles": z["cycles"],
                       "baseline_instructions": a["instructions"], "candidate_instructions": z["instructions"],
                       "baseline_cpi": a["cycles"] / a["instructions"],
                       "candidate_cpi": z["cycles"] / z["instructions"],
                       "cycle_ratio": a["cycles"] / z["cycles"]})
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=ROOT)
    parser.add_argument("--pdk", choices=("ICS55", "IHP130"), required=True)
    parser.add_argument("--timestamp", required=True)
    parser.add_argument("--jobs", type=int, default=4)
    parser.add_argument("--stage", choices=STAGES, required=True)
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--resume", action="store_true")
    parser.add_argument("--retained-timestamp", help="report-only: preserve completed stages from this campaign")
    parser.add_argument("--allow-collector-update", action="store_true",
                        help="report-only: admit explicitly listed collector/test changes, never DUT changes")
    args = parser.parse_args()
    args.root = args.root.resolve()
    if (not re.fullmatch(r"\d{4}-\d{2}-\d{2}-\d{2}-\d{2}", args.timestamp) or args.jobs < 1 or
            (args.pdk == "IHP130" and args.stage == "software")):
        parser.error("invalid timestamp/jobs or unsupported IHP130 software matrix")
    if (args.retained_timestamp or args.allow_collector_update) and args.stage != "report":
        parser.error("retained campaign and collector update are report-only")
    if args.retained_timestamp and not re.fullmatch(r"\d{4}-\d{2}-\d{2}-\d{2}-\d{2}", args.retained_timestamp):
        parser.error("invalid retained timestamp")
    variant, directory = location(args, args.stage)
    if args.dry_run:
        selections = list(MATCHED) if args.stage == "matched" and args.pdk == "ICS55" else (
            [case[0] for case in p3.MATRIX if case[0] not in MATCHED] if args.stage == "software" else
            ["compat-p1"] if args.stage == "matched" else [args.stage])
        print(json.dumps({"stage": args.stage, "pdk": args.pdk, "variant": str(variant),
                          "make": make_command(args, args.stage), "evidence": str(directory),
                          "case_names": selections, "maximum_attempts": 1,
                          "max_cycles": 100000000,
                          "wall_seconds": 14400 if args.stage == "camera" else 10800,
                          "references": {"IHP130": P1, "ICS55": P5, "software": P3},
                          "deferred": DEFERRED}, indent=2))
        return 0
    source = sources(args.root, args.pdk)
    if args.stage == "report":
        return report_stage(args, directory, source)
    if directory.exists():
        if args.resume:
            checked_record(directory / "record.json", source)
            print(f"Reused verified completed stage: {directory}")
            return 0
        raise ValueError("evidence exists; use --resume for an unchanged successful stage or a fresh timestamp")
    directory.mkdir(parents=True, exist_ok=False)
    record = {"phase": PHASE, "phase_accepted": False, "stage": args.stage, "pdk": args.pdk,
              "source_inputs": source, "status": "running", "pid": os.getpid(),
              "started_at": datetime.now(timezone.utc).isoformat(), "maximum_attempts": 1}
    b.dump(directory / "record.json", record)
    print(f"P10 {args.pdk}/{args.stage}: {directory}", flush=True)
    try:
        record["tools"] = b.tools_identity(args.root)
        record["host_tools"] = {name: b.artifact(Path(shutil.which(name)).resolve()) for name in
                                ("make", "cc", "c++", "timeout")}
        record["source"] = b.snapshot(args.root, directory / "source", source)
        b.dump(directory / "record.json", record)
        if args.stage in ("matched", "software"):
            paths = replay(args, variant, directory, record)
        elif args.stage in ("audio", "camera"):
            paths = application(args, variant, directory, record)
        else:
            paths = backend(args, variant, directory, record)
        after = sources(args.root, args.pdk)
        if source != after:
            raise ValueError("source inputs changed during P10 execution")
        record["source_after"] = after
        paths += [p for p in directory.iterdir() if p.is_file() and p.name != "record.json"]
        record["artifacts"] = capture_artifacts(paths)
        record["status"] = "passed"
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        record.update(status="failed_or_incomplete", reason=str(error))
    record["finished_at"] = datetime.now(timezone.utc).isoformat()
    b.dump(directory / "record.json", record)
    print(f"P10 {args.pdk}/{args.stage}: {record['status']}", flush=True)
    return 0 if record["status"] == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
