"""Validate strict Tiny R2-P9 camera workload records."""

from __future__ import annotations

import re
import hashlib
from pathlib import Path
from copy import deepcopy
import argparse
import subprocess
import sys
import shutil

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from scripts.check_simulation import DEFAULT_FAILURE  # noqa: E402

PHASE = "TINY-R2-P9"


def recovery_measurements(content: str, config: dict) -> dict:
    if config.get("SOC") != "TINY" or config.get("PDK") not in ("ICS55", "IHP130") or config.get("TINY_P9_QUICK", "NO") != "NO":
        raise ValueError("invalid recovery configuration")
    cases = re.findall(r"^P9_RECOVERY_CASE id=(\d+) pass=(\d+)$", content, re.M)
    if cases != [(str(index), "1") for index in range(1, 8)]:
        raise ValueError("missing, failed or duplicated recovery case")
    terminal = re.findall(r"^P9_RECOVERY_RESULT code=(\d+) cases=(\d+) frames=(\d+) irqs=(\d+)$", content, re.M)
    if terminal != [("0", "7", "6", "6")]:
        raise ValueError("incomplete recovery frame/IRQ result")
    diagnostics = re.findall(r"^P9_RECOVERY_DIAG high=(\d+) reset_status=(\d+) fault=(\d+) dvp_error=(\d+) words=(\d+)$", content, re.M)
    if (len(diagnostics) != 2 or [row[0] for row in diagnostics] != ["0", "1"] or
            any(row[1] != str((1 << 32) - 4) or int(row[2]) == 0 for row in diagnostics)):
        raise ValueError("missing stopped-clock reset rejection diagnostics")
    board = re.findall(r"^P9_RECOVERY_BOARD controls=(\d+) audio_cases=(\d+)$", content, re.M)
    if board != [("8", "2")]:
        raise ValueError("missing recovery board-control evidence")
    return {"cases": cases, "terminal": terminal[0], "diagnostics": diagnostics, "board": board}


def measurements(content: str, config: dict) -> dict:
    if DEFAULT_FAILURE.search(content) or len(re.findall(
            r"^SIM_TEST_PASS Tiny cycles=[1-9][0-9]*$", content, re.M)) != 1:
        raise ValueError("missing strict Tiny terminal success or forbidden marker")
    if config.get("TINY_P9_WORKLOAD") == "RECOVERY":
        return recovery_measurements(content, config)
    terminal = re.findall(r"^P9_RESULT code=(\d+) frames=(\d+) bytes=(\d+)$", content, re.M)
    if len(terminal) != 1 or terminal[0][0] != "0":
        raise ValueError("missing or failed P9 result")
    def records(prefix: str) -> list[dict]:
        result = []
        for line in content.splitlines():
            if not line.startswith(prefix + " "):
                continue
            fields = line.split()[1:]
            if any(re.fullmatch(r"[a-z_]+=[0-9]+", field) is None for field in fields):
                raise ValueError("malformed measurement field")
            row = dict((key, int(value)) for key, value in (field.split("=") for field in fields))
            if len(row) != len(fields):
                raise ValueError("duplicate measurement field")
            result.append(row)
        return result

    rows = records("P9_FRAME")
    workload = config.get("TINY_P9_WORKLOAD", "QVGA_RGB565")
    quick = config.get("TINY_P9_QUICK", "NO") == "YES"
    if workload not in ("QVGA_RGB565", "VGA_YUV422") or (quick and workload != "QVGA_RGB565"):
        raise ValueError("invalid P9 workload selection")
    expected = (1, 640, 480) if workload == "VGA_YUV422" else (
        (0, 16, 8) if quick else (0, 320, 240))
    if len(rows) != 1 or tuple(rows[0].get(key) for key in ("format", "width", "height")) != expected:
        raise ValueError("frame does not match selected workload")
    if (not rows or len(rows) != int(terminal[0][1]) or
            sum(row.get("bytes", 0) for row in rows) != int(terminal[0][2])):
        raise ValueError("frame records do not match terminal byte count")
    for row in rows:
        if row.get("bytes", 0) <= 0 or row.get("dma_channel") != 2 or row.get("request") != 11:
            raise ValueError("invalid DVP DMA binding or frame length")
        if row.get("dma_bytes") != row.get("bytes") or row.get("guards") != 1:
            raise ValueError("incomplete DMA/readback/guard evidence")
        if (row.get("format") not in (0, 1) or row.get("width", 0) <= 0 or
                row["width"] % 2 or row.get("height", 0) <= 0 or
                row["bytes"] != row["width"] * row["height"] * 2 or row.get("readback") != 1):
            raise ValueError("invalid dimensions or missing payload verification")
    pio = records("P9_PIO")
    counts = records("P9_COUNTS")
    expected_counts = {"words": expected[1] * expected[2] // 2,
                       "pixels": expected[1] * expected[2], "xpi_error": 0}
    if (counts and counts != [expected_counts]) or (workload == "VGA_YUV422" and not counts):
        raise ValueError("missing or inconsistent full-width frame counts")
    if len(pio) != 1 or pio[0] != {"width": 7, "height": 3, "valid_bytes": 42,
                                  "storage_bytes": 48, "readback": 1, "guards": 1}:
        raise ValueError("missing odd-width PIO readback")
    observations = records("P9_OBSERVATION")
    words = sum(row["bytes"] // 4 for row in rows) + 12
    if len(observations) != 1:
        raise ValueError("missing session observation")
    observed = observations[0]
    if (observed.get("version") != 1 or observed.get("accepted_words") != words or
            observed.get("delivered_words") != words or
            not 0 < observed.get("fifo_high_water", 0) <= 128 or
            observed.get("backpressure", -1) < 0 or observed.get("pixel_half_ns", 0) <= 0):
        raise ValueError("incomplete or inconsistent FIFO observations")
    if config.get("SOC") != "TINY" or config.get("PDK") not in ("ICS55", "IHP130"):
        raise ValueError("P9 evidence is not bound to a Tiny supported profile")
    return {"frames": rows, "pio": pio, "counts": counts,
            "observations": observations, "terminal": terminal[0]}


def validate_run(content: str, config: dict, flow: dict, source: dict, current: dict,
                 *, build: dict | None = None) -> dict:
    """Acceptance requires the captured run identity as well as parsed UART.

    The caller retains the build record captured from fresh outputs and the
    source snapshot taken before compilation, separately from the run record.
    A parsed log alone is never a qualified report.
    """
    digest = hashlib.sha256(content.encode()).hexdigest()
    if (flow.get("status") != "passed" or flow.get("exit_code") != 0 or
            flow.get("log_sha256") != digest or not flow.get("command")):
        raise ValueError("unsuccessful or unbound simulation command")
    if not source or source != current or any(
            not isinstance(value, str) or re.fullmatch(r"[0-9a-f]{64}", value) is None
            for value in source.values()):
        raise ValueError("missing or stale source snapshot")
    if config.get("APP") != "ci_smoke" or config.get("TINY_P9_ACCEPTANCE") != "YES":
        raise ValueError("not the P9 acceptance image")
    if flow.get("configuration") != config or flow.get("source_inputs") != source:
        raise ValueError("run does not match source/configuration")
    if (not build or build.get("phase") != PHASE or build.get("status") != "passed" or
            build.get("source_before") != source or build.get("source_after") != source or
            build.get("configuration") != config):
        raise ValueError("missing or stale build identity")
    if (not build.get("fresh_outputs") or not build.get("build_results") or
            any(result.get("exit_code") != 0 or result.get("status") != "passed"
                for result in build["build_results"])):
        raise ValueError("missing successful fresh-build commands")
    artifacts = build.get("artifacts", {})
    if set(artifacts) != {"elf", "hex", "simulator"} or flow.get("artifacts") != artifacts:
        raise ValueError("missing or mismatched run artifacts")
    for name, artifact in artifacts.items():
        try:
            path = Path(artifact["path"])
            data = path.read_bytes()
            if (not path.is_absolute() or len(data) != artifact["bytes"] or
                    hashlib.sha256(data).hexdigest() != artifact["sha256"]):
                raise ValueError(f"changed {name} artifact")
        except (OSError, KeyError, TypeError) as error:
            raise ValueError(f"missing {name} artifact") from error
    # Bind the launch arguments to the retained executable and firmware, not
    # merely to an arbitrary nonempty command string supplied with the log.
    cwd = Path(flow.get("cwd", ".")).resolve()
    command = flow["command"]
    def resolved(value: str) -> Path:
        return (cwd / value).resolve()
    simulator = Path(artifacts["simulator"]["path"]).resolve()
    firmware = Path(artifacts["hex"]["path"]).resolve()
    if (not isinstance(command, list) or not all(isinstance(value, str) for value in command) or
            simulator not in [resolved(value) for value in command if not value.startswith(("+", "-"))] or
            [resolved(value.split("=", 1)[1]) for value in command if value.startswith("+firmware=")] != [firmware]):
        raise ValueError("launch does not use the captured executable/firmware")
    measured = measurements(content, config)
    if config.get("TINY_P9_WORKLOAD") == "RECOVERY":
        required = ("+tiny_psram", "+tiny_p9_camera", "+tiny_p9_small", "+tiny_p9_recovery")
        forbidden = ("+tiny_p9_vga", "+tiny_p9_diag", "+tiny_p9_progress", "+tiny_p9_no_pixclk", "+p8_absent")
        if any(command.count(flag) != 1 for flag in required) or any(flag.startswith(forbidden) for flag in command):
            raise ValueError("recovery launch mismatch")
    if config.get("TINY_P9_WORKLOAD") == "VGA_YUV422":
        expected_camera = ("+tiny_psram", "+tiny_p9_camera", "+tiny_p9_vga")
        periods = [value for value in command if value.startswith("+tiny_p9_half_ns=")]
        rejected = ("+tiny_p9_small", "+tiny_p9_diag", "+tiny_p9_progress",
                    "+tiny_p9_no_pixclk", "+tiny_p9_pixclk_high", "+tiny_p8_psram", "+p8_absent")
        if (any(command.count(value) != 1 for value in expected_camera) or
                any(value.startswith(rejected) for value in command) or len(periods) != 1 or
                periods[0] != f"+tiny_p9_half_ns={measured['observations'][0]['pixel_half_ns']}"):
            raise ValueError("camera launch does not match VGA workload observations")
    return measured


def require_absent_outputs(outputs: dict[str, Path]) -> None:
    if any(path.exists() or path.is_symlink() for path in outputs.values()):
        raise ValueError("select a fresh build variant; outputs already exist")


def prepare_build(config: dict, source: dict, outputs: dict[str, Path]) -> dict:
    """Capture input identity before building into previously absent outputs."""
    if not source or set(outputs) != {"elf", "hex", "simulator"}:
        raise ValueError("incomplete fresh-build inputs")
    require_absent_outputs(outputs)
    return deepcopy({"configuration": config, "source_before": source,
                     "outputs": {name: str(path.resolve()) for name, path in outputs.items()}})


def capture_build(config: dict, source_before: dict, source_after: dict,
                  results: list[dict], outputs: dict[str, Path], *, prepared: dict) -> dict:
    """Record fresh build outputs after all source-bound build commands succeed.

    Use a new variant directory; capture source_before before compilation.
    Keep this record immutable when recording subsequent simulation runs.
    """
    if (not source_before or source_before != source_after or not results or
            any(result.get("exit_code") != 0 or result.get("status") != "passed" for result in results)):
        raise ValueError("build failed or sources changed during compilation")
    if set(outputs) != {"elf", "hex", "simulator"}:
        raise ValueError("incomplete build outputs")
    if (prepared.get("configuration") != config or prepared.get("source_before") != source_before or
            prepared.get("outputs") != {name: str(path.resolve()) for name, path in outputs.items()}):
        raise ValueError("outputs do not match the pre-build capture")
    artifacts = {}
    for name, path in outputs.items():
        data = path.read_bytes()
        artifacts[name] = {"path": str(path.resolve()), "bytes": len(data),
                           "sha256": hashlib.sha256(data).hexdigest()}
    return deepcopy({"phase": PHASE, "status": "passed", "configuration": config,
            "source_before": source_before, "source_after": source_after,
            "artifacts": artifacts, "build_results": results, "fresh_outputs": True})


def run_campaign(args: argparse.Namespace) -> int:
    """One fresh build and one bounded execution; never retry or overwrite."""
    from scripts import tiny_r2_baseline as baseline

    profile = f"configs/ci/{args.pdk.lower()}-tiny.mk"
    make = ["make", "--no-print-directory", f"CONFIG={profile}", "SOC=TINY",
            f"PDK={args.pdk}", "APP=ci_smoke", "TINY_P9_ACCEPTANCE=YES", "TINY_P9_QUICK=NO",
            f"TINY_P9_WORKLOAD={args.workload}", "SIMU=VERILATOR",
            f"BUILD_TIMESTAMP={args.timestamp}", f"JOBS={args.jobs}"]
    expanded = subprocess.run([*make, "config"], cwd=ROOT, text=True,
                              capture_output=True, check=True)
    values = dict(line.split(None, 1) for line in expanded.stdout.splitlines() if line.strip())
    variant = Path(values["VARIANT_ROOT"]).resolve()
    evidence = variant / "meta/tiny-r2-p9/full-frame"
    outputs = {"elf": variant / "sw/firmware", "hex": variant / "sw/retrosoc_fw.hex",
               "simulator": variant / "sim/verilator/emu"}
    # Reject collisions before even writing evidence: generation can overwrite
    # an older build's manifest/filelists although its final outputs are intact.
    try:
        require_absent_outputs(outputs)
        if evidence.exists() or evidence.is_symlink():
            raise ValueError("select a fresh build variant; evidence already exists")
        evidence.mkdir(parents=True, exist_ok=False)
    except (ValueError, OSError) as error:
        print(f"{args.pdk}: campaign rejected: {error}", file=sys.stderr)
        return 1
    assessment = {"phase": PHASE, "phase_accepted": False, "profile": profile, "pdk": args.pdk,
                  "workload": args.workload, "operating_point": "SAFE24", "status": "running",
                  "maximum_attempts": 1, "unrun": ["full Icarus", "broad regression",
                  "synthesis/netlist", "STA", "physical qualification", "remaining P9 matrix"]}
    baseline.dump(evidence / "assessment.json", assessment)
    try:
        identities = {}
        for program in ("riscv32-unknown-elf-gcc", "verilator", "verilator_bin", "make",
                        "cc", "c++", "timeout", "stdbuf"):
            executable = shutil.which(program)
            if executable is None:
                raise ValueError(f"required tool unavailable: {program}")
            identities[program] = baseline.artifact(Path(executable).resolve())
        baseline.dump(evidence / "tool-identity.json", {
            "executables": identities, "python": baseline.artifact(Path(sys.executable).resolve()),
            "lock": baseline.artifact(ROOT / "dependencies/dependencies.lock.json"),
            "archive_verification": "not performed by this campaign"})
        baseline.execute(ROOT, evidence, "generate", [*make, "generate_filelist", "manifest"],
                         cwd=ROOT, quiet=True)
        config = baseline.configuration(variant)["configuration"]

        def inputs() -> dict:
            result = baseline.source_inputs(ROOT, args.pdk) | baseline.runtime_inputs(
                ROOT, variant, "verilator")
            for name in ("docs/ip/tiny-soc.md", "docs/ip/tiny-soc-r2-dvp.md",
                         "tests/test_tiny_r2_p9.py", "tests/test_tiny_r2_p9_evidence.py",
                         "tests/c/test_runtime.c"):
                result[name] = baseline.sha256(ROOT / name)
            return result

        before = inputs()
        prepared = prepare_build(config, before, outputs)
        baseline.dump(evidence / "prepared-build.json", prepared)
        baseline.dump(evidence / "source-snapshot.json", baseline.snapshot(ROOT, evidence / "source", before))
        print(f"{args.pdk}: building fresh {args.workload}; evidence={evidence}", flush=True)
        built = baseline.execute(ROOT, evidence, "build", [*make, "firmware", "comp", "manifest"],
                                 cwd=ROOT, quiet=True)
        build = capture_build(config, before, inputs(), [built], outputs, prepared=prepared)
        baseline.dump(evidence / "build-identity.json", build)
        for artifact in identities.values():
            baseline.check_artifact(artifact)
        command = ["timeout", "--foreground", "--kill-after=30s", f"{args.wall_timeout}s",
                   "stdbuf", "-oL", "-eL", str(outputs["simulator"]),
                   f"+firmware={outputs['hex']}", f"+max_cycles={args.max_cycles}",
                   "+tiny_psram", "+tiny_p9_camera", f"+tiny_p9_half_ns={args.pixel_half_ns}",
                   "+tiny_p9_monitor", f"+tiny_p9_monitor_log={evidence / 'progress.log'}"]
        if args.workload == "VGA_YUV422":
            command.append("+tiny_p9_vga")
        elif args.workload == "RECOVERY":
            command += ["+tiny_p9_small", "+tiny_p9_recovery"]
        baseline.dump(evidence / "launch.json", {
            "command": command, "cwd": str(ROOT), "configuration": config,
            "source_inputs": before, "artifacts": build["artifacts"], "maximum_attempts": 1,
            "build_identity": baseline.artifact(evidence / "build-identity.json")})
        print(f"{args.pdk}: starting single {args.workload} replay", flush=True)
        run = subprocess.run([sys.executable, str(ROOT / "scripts/run_flow.py"),
              "--tool", "tiny-p9-full-frame", "--cwd", str(ROOT),
              "--log", str(evidence / "console.log"), "--result", str(evidence / "result-sim.json"),
              "--", *command], cwd=ROOT, check=False, stdout=subprocess.DEVNULL)
        flow = baseline.read_json(evidence / "result-sim.json")
        content = (evidence / "console.log").read_text()
        bound = {**flow, "source_inputs": before, "configuration": config,
                 "artifacts": build["artifacts"], "log_sha256": hashlib.sha256(content.encode()).hexdigest()}
        baseline.dump(evidence / "bound-result.json", bound)
        check = subprocess.run([sys.executable, str(ROOT / "scripts/check_simulation.py"),
                "--log", str(evidence / "console.log"),
                "--result", str(evidence / "result-sim-check.json"),
                "--require", "SIM_TEST_PASS Tiny"], cwd=ROOT, check=False)
        measured = validate_run(content, config, bound, before, inputs(), build=build)
        if run.returncode != 0 or check.returncode != 0:
            raise ValueError("simulation command/check failed")
        for artifact in identities.values():
            baseline.check_artifact(artifact)
        assessment.update(status="workload_passed", measurements=measured,
                          duration_seconds=flow.get("duration_seconds"),
                          build=baseline.artifact(evidence / "build-identity.json"),
                          log=baseline.artifact(evidence / "console.log"))
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        assessment.update(status="failed_or_incomplete", reason=str(error))
    baseline.dump(evidence / "assessment.json", assessment)
    print(f"{args.pdk}: {assessment['status']}; {evidence / 'assessment.json'}", flush=True)
    return 0 if assessment["status"] == "workload_passed" else 1


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    actions = parser.add_subparsers(dest="action", required=True)
    run = actions.add_parser("run", help="fresh build plus one source-bound Verilator execution")
    run.add_argument("--pdk", required=True, choices=("ICS55", "IHP130"))
    run.add_argument("--workload", required=True, choices=("QVGA_RGB565", "VGA_YUV422", "RECOVERY"))
    run.add_argument("--timestamp", required=True)
    run.add_argument("--jobs", type=int, default=4)
    run.add_argument("--pixel-half-ns", type=int, default=500)
    run.add_argument("--max-cycles", type=int, default=160000000)
    run.add_argument("--wall-timeout", type=int, default=43200)
    args = parser.parse_args()
    if not re.fullmatch(r"\d{4}-\d{2}-\d{2}-\d{2}-\d{2}", args.timestamp):
        parser.error("timestamp must be YYYY-MM-DD-HH-MM")
    if min(args.jobs, args.pixel_half_ns, args.max_cycles, args.wall_timeout) <= 0:
        parser.error("jobs, pixel period and execution limits must be positive")
    return run_campaign(args)


if __name__ == "__main__":
    sys.exit(main())
