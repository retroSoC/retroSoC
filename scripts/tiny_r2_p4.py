#!/usr/bin/env python3
"""Replay immutable P3 images on P4 RTL without relabeling image provenance."""
from __future__ import annotations

import argparse
from pathlib import Path
import sys
import subprocess

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from scripts import tiny_r2_baseline as b  # noqa: E402
from scripts import tiny_r2_p3 as p3  # noqa: E402

PHASE = "TINY-R2-P4"
HARDWARE_KEYS = ("SOC", "PDK", "HAVE_PLL", "HAVE_SRAM_IF", "HAVE_SRAM_MACRO",
                 "SRAM_SIZE_KIB", "PDK_BEHAV", "HAVE_HP", "EXT_CLK_HZ", "AUD_CLK_HZ",
                 "CLINT_TIMEBASE_HZ", "MGMT_CPU_CLK_HZ", "JTAG_IDCODE")
LOCAL_FIELDS = {"window", "port", "accepted", "completed", "latency_max", "admission_wait"}
BANK_FIELDS = {"window", "group", "issues_i", "issues_d", "issues_external", "conflicts",
               "wait_i", "wait_d", "wait_external"}


def inputs(root: Path, variant: Path) -> dict:
    result = p3.inputs(root, variant)
    # Publication bindings are tested source consumers, not generated PDFs.
    names = subprocess.check_output(
        ["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z", "--", "publications"],
        cwd=root, text=True).split("\0")
    for name in names:
        path = root / name
        if name and path.is_file() and path.suffix in (".py", ".json", ".typ"):
            result[name] = p3.sha256(path)
    return result


def compatible_hardware(image: dict, model: dict) -> None:
    a, z = (c["configuration"] for c in (image, model))
    if any(key not in a or key not in z or a[key] != z[key] for key in HARDWARE_KEYS):
        raise ValueError("retained image and candidate hardware configuration differ")


def parse_log(log: str, flow: dict) -> dict:
    samples = p3.parse_log(log, flow)
    rows = [b.parse_fields(line, LOCAL_FIELDS) for line in log.splitlines()
            if line.startswith("R2_P4_LOCAL ")]
    rows.sort(key=lambda row: (row["window"], row["port"]))
    if [(r["window"], r["port"]) for r in rows] != [(w, p) for w in range(1, 9) for p in range(2)]:
        raise ValueError("missing or duplicate P4 local observations")
    for row in rows:
        if row["completed"] > row["accepted"] or row["accepted"] - row["completed"] > 1:
            raise ValueError("P4 local request/response accounting mismatch")
    samples["local"] = rows
    banks = [b.parse_fields(line, BANK_FIELDS) for line in log.splitlines()
             if line.startswith("R2_P4_BANK ")]
    banks.sort(key=lambda row: (row["window"], row["group"]))
    if [(r["window"], r["group"]) for r in banks] != [(w, g) for w in range(1, 9) for g in range(4)]:
        raise ValueError("missing or duplicate P4 bank observations")
    samples["banks"] = banks
    return samples


def reference_cases(path: Path, names: list[str]) -> list[dict]:
    report = b.read_json(path)
    if report.get("phase") != p3.PHASE or report.get("status") != "measurement_complete":
        raise ValueError("reference is not a completed P3 measurement report")
    matrix = b.read_json(b.check_artifact(report["matrix"]))
    if matrix.get("status") != "passed":
        raise ValueError("reference matrix did not pass")
    if not names or len(set(names)) != len(names):
        raise ValueError("select distinct retained cases")
    result = []
    for name in names:
        matching = [c for c in report["cases"] if c["name"] == name]
        original = [c for c in matrix["cases"] if c["name"] == name]
        if len(matching) != 1 or len(original) != 1 or matching[0]["image"] != original[0]["image"]:
            raise ValueError("unknown or mismatched retained case")
        case = matching[0]
        p3.validate_image(b.check_artifact(case["image"]))
        # Recheck the original logs, not just a report's claimed numeric values.
        samples = p3.validate_simulation(original[0]["simulations"]["verilator"],
                                         case["image"], "verilator")
        if samples != case["samples"]:
            raise ValueError("reference report differs from its retained execution")
        result.append(case)
    return result


def replay(args) -> None:
    root, variant = args.root, args.variant_root
    parent = variant / "meta/tiny-r2-p4/replay" / args.simulator
    directory = b.new_attempt(parent, "attempt-")
    record = {"phase": PHASE, "status": "running", "repetitions": 1, "cases": []}
    b.dump(parent / "latest.json", {"path": str(directory / "record.json")})
    try:
        reference = b.artifact(args.reference)
        cases = reference_cases(args.reference, args.cases.split(","))
        configuration = p3.configuration(variant)
        for case in cases:
            compatible_hardware(b.read_json(b.check_artifact(case["image"]))["configuration"],
                                configuration)
        before = inputs(root, variant)
        tools = b.tools_identity(root)
        command = args.command[1:] if args.command[:1] == ["--"] else args.command
        if not command:
            raise ValueError("fresh model compilation command required")
        p3.execute_make(root, directory, "compile-model", command)
        if before != inputs(root, variant):
            raise ValueError("source changed while compiling candidate model")
        runtime = b.runtime_inputs(root, variant, args.simulator)
        model = variant / "sim" / args.simulator / ("emu" if args.simulator == "verilator" else "simv")
        record.update(reference=reference, configuration=configuration, tools=tools,
                      model=b.artifact(model), source_digest=b.digest_map(before),
                      source=b.snapshot(root, directory / "inputs", before | runtime),
                      compilation={s: b.artifact(directory / f"compile-model.{s}") for s in ("json", "log")})
        launch = [str(model)]
        if args.simulator == "iverilog":
            record["runtime_tool"] = b.vvp_identity(args.vvp, tools["iverilog"])
            launch.insert(0, record["runtime_tool"]["executable"]["path"])
        for case in cases:
            image = p3.validate_image(b.check_artifact(case["image"]))
            begin, end = image["layout"]["descriptor_range"]
            cmd = [*launch, "+firmware=" + image["artifacts"]["tiny_p3.hex"]["path"],
                   "+tiny_r2_p3", f"+baseline_tcd_base={begin:x}", f"+baseline_tcd_end={end:x}",
                   "+max_cycles=100000000"]
            label = case["name"]
            flow = b.execute(root, directory, label,
                             ["timeout", "--foreground", f"{args.timeout}s", *cmd], quiet=True)
            samples = parse_log((directory / f"{label}.log").read_text(), flow)
            p3.validate_image(b.check_artifact(case["image"]))
            record["cases"].append({"name": label, "image": case["image"], "samples": samples,
                                     "baseline_samples": case["samples"],
                                     "command": cmd, "timeout_seconds": args.timeout,
                                     "flow": b.artifact(directory / f"{label}.json"),
                                     "log": b.artifact(directory / f"{label}.log")})
            b.dump(directory / "record.json", record)
        if before != inputs(root, variant) or runtime != b.runtime_inputs(root, variant, args.simulator):
            raise ValueError("candidate inputs changed during execution")
        b.check_artifact(record["model"])
        b.check_artifact(reference)
        for case in cases:
            p3.validate_image(b.check_artifact(case["image"]))
        for tool in tools.values():
            b.check_artifact(tool["executable"])
        record["status"] = "passed"
    except (OSError, ValueError) as error:
        record.update(status="failed", error=str(error))
        raise
    finally:
        b.dump(directory / "record.json", record)
    print(f"P4 {args.simulator}: one execution per image; {directory}")


def validate_replay(path: Path, simulator: str) -> dict:
    record = b.read_json(path)
    if record.get("phase") != PHASE or record.get("status") != "passed" or record.get("repetitions") != 1:
        raise ValueError("not a completed single-execution P4 replay")
    for field in ("model", "reference"):
        b.check_artifact(record[field])
    for value in record["compilation"].values():
        b.check_artifact(value)
    for field in ("inputs", "snapshot", "patch"):
        b.check_artifact(record["source"][field])
    captured = b.read_json(Path(record["source"]["inputs"]["path"]))
    if b.digest_map(captured) != record["source"]["input_digest"]:
        raise ValueError("candidate source digest mismatch")
    for tool in record["tools"].values():
        b.check_artifact(tool["executable"])
        b.check_artifact(tool["archive"])
    prefix = [record["model"]["path"]]
    if simulator == "iverilog":
        runtime = b.check_artifact(record["runtime_tool"]["executable"])
        compiler = Path(record["tools"]["iverilog"]["executable"]["path"])
        if runtime.resolve().parent != compiler.resolve().parent:
            raise ValueError("unmatched Icarus runtime")
        prefix.insert(0, str(runtime))
    reference = reference_cases(Path(record["reference"]["path"]), [c["name"] for c in record["cases"]])
    for case, original in zip(record["cases"], reference, strict=True):
        if case["image"] != original["image"] or case["baseline_samples"] != original["samples"]:
            raise ValueError("comparison changed the retained image or reference measurements")
        image = p3.validate_image(b.check_artifact(case["image"]))
        compatible_hardware(image["configuration"], record["configuration"])
        first, end = image["layout"]["descriptor_range"]
        expected = [*prefix, "+firmware=" + image["artifacts"]["tiny_p3.hex"]["path"],
                    "+tiny_r2_p3", f"+baseline_tcd_base={first:x}", f"+baseline_tcd_end={end:x}",
                    "+max_cycles=100000000"]
        flow = b.read_json(b.check_artifact(case["flow"]))
        if case["command"] != expected or case["timeout_seconds"] <= 0 or flow["command"] != [
                "timeout", "--foreground", f"{case['timeout_seconds']}s", *expected]:
            raise ValueError("model/image execution provenance mismatch")
        if parse_log(b.check_artifact(case["log"]).read_text(), flow) != case["samples"]:
            raise ValueError("reported candidate samples differ from the log")
    return record


def report(args) -> None:
    base = args.variant_root / "meta/tiny-r2-p4"
    runs = {}
    for simulator in ("verilator", "iverilog"):
        pointer = b.read_json(base / "replay" / simulator / "latest.json")
        path = Path(pointer["path"])
        runs[simulator] = (validate_replay(path, simulator), b.artifact(path))
    before = b.digest_map(inputs(args.root, args.variant_root))
    if any(run[0]["source_digest"] != before for run in runs.values()):
        raise ValueError("candidate source changed after measurement")
    cases = {c["name"]: c for c in runs["verilator"][0]["cases"]}
    if set(cases) != {"perf-o2-plain-flat", "perf-o2-plain-banked"}:
        raise ValueError("P4 comparison requires both approved placement images")
    cross = runs["iverilog"][0]["cases"]
    if len(cross) != 1 or cross[0]["name"] != "perf-o2-plain-banked":
        raise ValueError("P4 requires one banked Icarus execution")
    if any(cross[0][key] != cases["perf-o2-plain-banked"][key] for key in ("image", "samples")):
        raise ValueError("cross-simulator image/results differ")
    comparisons = []
    for name, case in cases.items():
        rows = []
        for old, new in zip(case["baseline_samples"]["cases"], case["samples"]["cases"], strict=True):
            rows.append({"name": new["name"], "baseline_cycles": old["cycles"],
                         "candidate_cycles": new["cycles"], "baseline_instructions": old["instructions"],
                         "candidate_instructions": new["instructions"],
                         "cycle_ratio": old["cycles"] / new["cycles"]})
        comparisons.append({"name": name, "image": case["image"], "workloads": rows,
                            "local": case["samples"]["local"], "banks": case["samples"]["banks"]})
    b.dump(base / "report.json", {"phase": PHASE, "status": "measurement_complete",
                                  "source_digest": before, "comparisons": comparisons,
                                  "executions": {key: value[1] for key, value in runs.items()},
                                  "qualification": "matched-binary SAFE24 simulation; not phase/physical acceptance"})
    print(f"P4 matched-image report: {base / 'report.json'}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--variant-root", type=Path, required=True)
    parser.add_argument("--report", action="store_true")
    parser.add_argument("--reference", type=Path)
    parser.add_argument("--cases")
    parser.add_argument("--simulator", choices=("verilator", "iverilog"))
    parser.add_argument("--vvp", default="vvp")
    parser.add_argument("--timeout", type=int, default=21600)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    if args.timeout <= 0:
        parser.error("timeout must be positive")
    if args.report:
        report(args)
    else:
        if args.reference is None or not args.cases or not args.simulator:
            parser.error("replay requires reference, cases and simulator")
        replay(args)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
