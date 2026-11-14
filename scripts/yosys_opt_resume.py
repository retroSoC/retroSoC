#!/usr/bin/env python3
"""Run plain Yosys opt with resumable, revision-bound checkpoints."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from scripts.agent_control import dump_json, read_json  # noqa: E402
from scripts.flow_control import (  # noqa: E402
    Lease,
    digest_json,
    execution_fingerprint,
    fingerprint_mismatches,
    write_json,
)
from scripts.rtl.filelist import parse_filelists  # noqa: E402
from scripts.setup_helpers import atomic_write  # noqa: E402

OPT_COMMAND = "yosys opt\n"
ITERATION_SCRIPT = """yosys read_rtlil $::env(OPT_INPUT)
yosys scratchpad -unset opt.did_something
yosys opt_muxtree
yosys opt_reduce
yosys opt_merge
yosys opt_dff
yosys opt_clean
yosys opt_expr
yosys tee -q -o "$::env(OPT_REPORT)/stat.rpt" stat
yosys tee -q -o "$::env(OPT_REPORT)/did-something.txt" scratchpad -get opt.did_something
yosys write_rtlil $::env(OPT_OUTPUT)
"""


def split_synth_script(text: str) -> tuple[str, str]:
    count = text.count(OPT_COMMAND)
    if count == 0:
        raise ValueError("expected at least one plain `yosys opt` command")
    prefix, suffix = text.split(OPT_COMMAND, 1)
    return prefix, suffix


def preserve_script_directory(text: str) -> str:
    return text.replace("set script_dir [file dirname [info script]]", "set script_dir $::env(YOSYS_SCRIPT_DIR)", 1)


def frontend_script(text: str) -> str:
    prefix, _ = split_synth_script(text)
    return preserve_script_directory(prefix + "yosys opt_expr\nyosys opt_merge -nomux\nyosys write_rtlil $::env(OPT_PRELOOP)\n")


def backend_script(text: str) -> str:
    prefix, suffix = split_synth_script(text)
    setup_commands = {
        "set script_dir [file dirname [info script]]",
        "source $script_dir/common.tcl",
        "source $script_dir/init_tech.tcl",
    }
    setup = "".join(line for line in prefix.splitlines(keepends=True) if line.strip() in setup_commands)
    return preserve_script_directory(setup + "yosys read_rtlil $::env(OPT_FINAL)\n" + suffix)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


SYNTH_ENVIRONMENT = (
    "VLOG_FILES",
    "SV_FLIST",
    "PDK",
    "SOC",
    "TOP_DESIGN",
    "HIER_DEPTH",
    "YOSYS_TARGET_PERIOD_PS",
    "SYNTH_RECIPE",
    "PROJ_NAME",
    "BUILD",
    "WORK",
    "REPORTS",
    "NETLIST",
    "CONFIG",
    "YOSYS_KEEP_HIER_INST",
    "YOSYS_FLATTEN_HIER",
    "YOSYS_REPORT_INSTS",
    "HAVE_SRAM_MACRO",
    "SRAM_SIZE_KIB",
    "HAVE_PLL",
    "CONFIG_DIGEST",
)


def optimizer_environment() -> dict[str, str]:
    return {name: value for name, value in os.environ.items() if name not in SYNTH_ENVIRONMENT}


def file_identity(path: Path) -> dict[str, str]:
    resolved = path.resolve()
    return {"path": str(resolved), "sha256": sha256(resolved)}


def source_identity(filelist: Path) -> dict[str, Any]:
    parsed = parse_filelists([filelist])
    dependencies = {filelist.resolve(), *(path.resolve() for path in parsed.files), *(path.resolve() for path in parsed.library_files)}
    for directory in parsed.incdirs:
        dependencies.update(
            path.resolve()
            for path in directory.rglob("*")
            if path.is_file() and path.suffix.lower() in {".h", ".vh", ".svh"}
        )
    return {
        "defines": parsed.defines,
        "options": parsed.options,
        "include_directories": [str(path) for path in parsed.incdirs],
        "files": [file_identity(path) for path in sorted(dependencies)],
    }


def synthesis_identity(script: Path, text: str) -> dict[str, Any]:
    script = script.resolve()
    support = [script.parent / name for name in ("common.tcl", "init_tech.tcl")]
    support.extend(sorted(script.parent.glob("abc_*.script")))
    filelist = os.environ.get("SV_FLIST")
    return {
        "script": file_identity(script),
        "frontend_sha256": hashlib.sha256(frontend_script(text).encode("utf-8")).hexdigest(),
        "backend_sha256": hashlib.sha256(backend_script(text).encode("utf-8")).hexdigest(),
        "support": [file_identity(path) for path in support if path.is_file()],
        "environment": {name: os.environ.get(name) for name in SYNTH_ENVIRONMENT},
        "sources": source_identity(Path(filelist)) if filelist else None,
    }


def stage_cache_valid(cache_path: Path, result_path: Path, identity: dict[str, Any], output: Path | None) -> bool:
    if not cache_path.is_file() or not result_path.is_file() or (output is not None and not output.is_file()):
        return False
    result = read_json(result_path)
    if result.get("status") != "passed" or result.get("exit_code") != 0:
        return False
    expected = {
        "schema_version": 1,
        "identity": identity,
        "result_sha256": sha256(result_path),
        "output_sha256": sha256(output) if output is not None else None,
    }
    return read_json(cache_path) == expected


def record_stage_cache(cache_path: Path, result_path: Path, identity: dict[str, Any], output: Path | None) -> None:
    record = {
        "schema_version": 1,
        "identity": identity,
        "result_sha256": sha256(result_path),
        "output_sha256": sha256(output) if output is not None else None,
    }
    atomic_write(cache_path, dump_json(record))


def identity_fields(value: Any) -> tuple[str, str] | None:
    if not isinstance(value, dict):
        return None
    path = value.get("path")
    digest = value.get("sha256")
    if not isinstance(path, str) or not isinstance(digest, str):
        return None
    return path, digest


def iteration_identity(iteration: int, input_identity: dict[str, str], report: Path, script_path: Path, changed: bool) -> dict[str, Any]:
    did_path = report / "did-something.txt"
    return {
        "schema_version": 1,
        "iteration": iteration,
        "input": input_identity,
        "script": file_identity(script_path),
        "output": file_identity(report / "next.il"),
        "did": {**file_identity(did_path), "changed": changed},
        "result": file_identity(report / "result.json"),
    }


def cached_iteration(
    iteration: int,
    input_identity: dict[str, str],
    report: Path,
    script_path: Path,
) -> tuple[dict[str, Any], dict[str, Any]] | None:
    identity_path = report / "identity.json"
    result_path = report / "result.json"
    if not all(path.is_file() for path in (identity_path, report / "next.il", report / "did-something.txt", result_path)):
        return None
    changed = parse_changed(report / "did-something.txt")
    candidate = iteration_identity(iteration, input_identity, report, script_path, changed)
    if read_json(identity_path) != candidate:
        raise ValueError(f"opt resume iteration identity mismatch for iteration {iteration}")
    result = read_json(result_path)
    if result.get("status") != "passed" or result.get("exit_code") != 0:
        return None
    return candidate, result


def run_yosys(
    root: Path,
    command: list[str],
    *,
    log: Path,
    result: Path,
    timeout: int,
    environment: dict[str, str] | None = None,
) -> dict[str, Any]:
    launcher = [
        sys.executable,
        str(ROOT / "scripts/run_flow.py"),
        "--tool",
        "yosys",
        "--log",
        str(log),
        "--result",
        str(result),
    ]
    if "-c" in command:
        launcher.extend(["--script", command[command.index("-c") + 1]])
    if environment and "OPT_INPUT" in environment:
        launcher.extend(["--input", environment["OPT_INPUT"]])
    for name, flag in (("PDK", "--pdk"), ("SOC", "--soc"), ("CONFIG", "--profile")):
        if os.environ.get(name):
            launcher.extend([flag, os.environ[name]])
    launcher.extend(["--timeout-seconds", str(timeout + 5), "--heartbeat-seconds", "5"])
    for name, value in (environment or {}).items():
        launcher.extend(["--env", f"{name}={value}"])
    launcher.extend(["--", "timeout", "--foreground", "--kill-after=5s", f"{timeout}s", *command])
    completed = subprocess.run(launcher, cwd=root, check=False)
    document = read_json(result)
    if completed.returncode:
        raise RuntimeError(f"Yosys stage failed with exit code {completed.returncode}: {log}")
    if document.get("status") != "passed" or document.get("exit_code") != 0:
        raise RuntimeError(f"invalid Yosys stage result: {result}")
    return document


def parse_changed(path: Path) -> bool:
    value = path.read_text(encoding="utf-8").strip()
    if value.endswith("true"):
        return True
    if "not set" in value:
        return False
    raise ValueError(f"cannot parse opt.did_something: {value}")


def summary_from_state(state: dict[str, Any], status: str, output: Path, error: str | None = None) -> dict[str, Any]:
    iterations = state["iterations"]
    summary = {
        "schema_version": 1,
        "status": status,
        "input": state["input"],
        "input_sha256": state["input_sha256"],
        "output": str(output),
        "output_sha256": sha256(output) if output.is_file() else None,
        "max_iterations": state["max_iterations"],
        "next_iteration": state["next_iteration"],
        "completed_iterations": len(iterations),
        "elapsed_seconds": round(sum(item["duration_seconds"] for item in iterations), 3),
        "peak_rss_kib": max((item["peak_rss_kib"] for item in iterations), default=0),
        "iterations": iterations,
    }
    if error:
        summary["error"] = error
    return summary


def validate_iteration(work_dir: Path, item: dict[str, Any]) -> dict[str, Any]:
    iteration = item["iteration"]
    report = work_dir / "iterations" / f"{iteration:02d}"
    checkpoint = report / "next.il"
    did_path = report / "did-something.txt"
    result_path = report / "result.json"
    stat_path = report / "stat.rpt"
    result = read_json(result_path)
    if result.get("status") != "passed" or result.get("exit_code") != 0:
        raise ValueError(f"retained iteration result is not passing: {result_path}")
    if not checkpoint.is_file() or sha256(checkpoint) != item.get("next_sha256"):
        raise ValueError(f"retained iteration checkpoint digest mismatch: {iteration}")
    if not did_path.is_file() or sha256(did_path) != item.get("did_sha256"):
        raise ValueError(f"retained iteration marker digest mismatch: {iteration}")
    if parse_changed(did_path) != item.get("did_something"):
        raise ValueError(f"retained iteration marker disagrees with state: {iteration}")
    if not stat_path.is_file() or sha256(stat_path) != item.get("stat_sha256"):
        raise ValueError(f"retained iteration stat digest mismatch: {iteration}")
    return result


def _optimize_unlocked(
    root: Path,
    input_path: Path,
    output_path: Path,
    work_dir: Path,
    *,
    max_iterations: int,
    iteration_timeout: int,
    fingerprint_environment: dict[str, str] | None = None,
) -> dict[str, Any]:
    if max_iterations <= 0 or iteration_timeout <= 0:
        raise ValueError("iteration count and timeout must be positive")
    input_path = input_path.resolve()
    output_path = output_path.resolve()
    work_dir = work_dir.resolve()
    if not input_path.is_file():
        raise ValueError(f"input checkpoint is missing: {input_path}")
    work_dir.mkdir(parents=True, exist_ok=True)
    atomic_write(work_dir / "iteration.tcl", ITERATION_SCRIPT)
    state_path = work_dir / "state.json"
    summary_path = work_dir / "summary.json"
    current = work_dir / "current.il"
    input_digest = sha256(input_path)
    fingerprint = execution_fingerprint(
        root,
        ["yosys", "opt"],
        os.environ.copy() if fingerprint_environment is None else fingerprint_environment,
        script=work_dir / "iteration.tcl",
        inputs=[input_path],
        configuration={"max_iterations": max_iterations, "iteration_timeout": iteration_timeout},
    )
    if state_path.exists():
        state = read_json(state_path)
        if state.get("schema_version") != 2:
            raise ValueError("legacy opt resume state has no execution fingerprint")
        for key in ("input", "input_sha256", "output", "max_iterations", "next_iteration", "iterations", "fingerprint"):
            if key not in state:
                raise ValueError(f"opt resume state is missing {key}")
        if state["input_sha256"] != input_digest:
            raise ValueError("opt resume input digest does not match the retained state")
        mismatches = fingerprint_mismatches(state["fingerprint"], fingerprint)
        if mismatches:
            raise ValueError(f"opt resume fingerprint mismatch: {', '.join(mismatches)}")
        if Path(state["output"]) != output_path:
            raise ValueError("opt resume output path does not match the retained state")
        if state["max_iterations"] != max_iterations:
            raise ValueError("opt resume iteration limit does not match the retained state")
        if not isinstance(state["iterations"], list):
            raise ValueError("opt resume iterations must be a list")
    else:
        if current.exists():
            raise ValueError("current checkpoint exists without a state file")
        state = {
            "schema_version": 2,
            "status": "running",
            "fingerprint": fingerprint,
            "input": str(input_path),
            "input_sha256": input_digest,
            "output": str(output_path),
            "output_sha256": None,
            "current_sha256": None,
            "max_iterations": max_iterations,
            "next_iteration": 1,
            "iterations": [],
        }
        write_json(state_path, state)

    if state.get("status") not in {"running", "converged"}:
        raise ValueError(f"cannot resume opt state {state.get('status')}")
    next_iteration = state["next_iteration"]
    if not isinstance(next_iteration, int) or next_iteration < 1:
        raise ValueError("invalid next iteration in opt resume state")
    if next_iteration > max_iterations:
        raise RuntimeError(f"plain opt did not converge within {max_iterations} iterations")
    if [entry.get("iteration") for entry in state["iterations"]] != list(range(1, next_iteration)):
        raise ValueError("opt resume iteration history is not contiguous")
    for entry in state["iterations"]:
        validate_iteration(work_dir, entry)
    if state.get("status") == "converged":
        if not output_path.is_file():
            raise ValueError("converged state has no final checkpoint")
        if state.get("output_sha256") != sha256(output_path):
            raise ValueError("opt resume output digest does not match the retained state")
        if not current.is_file() or state.get("current_sha256") != sha256(current):
            raise ValueError("opt resume current digest does not match the retained state")
        return summary_from_state(state, "converged", output_path)

    resume_input_identity = None
    if next_iteration > 1:
        if not current.is_file():
            raise ValueError("resumable current checkpoint is missing")
        if state.get("current_sha256") != sha256(current):
            report = work_dir / "iterations" / f"{next_iteration:02d}"
            identity_path = report / "identity.json"
            retained = read_json(identity_path) if identity_path.is_file() else None
            retained_input = identity_fields(retained.get("input") if isinstance(retained, dict) else None)
            retained_output = identity_fields(retained.get("output") if isinstance(retained, dict) else None)
            previous = [
                entry
                for entry in state["iterations"]
                if isinstance(entry, dict) and entry.get("iteration") == next_iteration - 1
            ]
            previous_identity = previous[0].get("identity") if len(previous) == 1 else None
            previous_output = identity_fields(previous_identity.get("output") if isinstance(previous_identity, dict) else None)
            if (
                retained_input != (str(current), state["current_sha256"])
                or retained_output is None
                or retained_output[1] != sha256(current)
                or previous_output is None
                or previous_output[1] != state["current_sha256"]
            ):
                raise ValueError("opt resume current digest does not match the retained state")
            resume_input_identity = {"path": retained_input[0], "sha256": retained_input[1]}
            if cached_iteration(next_iteration, resume_input_identity, report, work_dir / "iteration.tcl") is None:
                raise ValueError("opt resume current digest does not match the retained state")
        else:
            latest_digest = state["iterations"][-1]["next_sha256"]
            if sha256(current) != latest_digest:
                raise ValueError("current checkpoint digest does not match the retained state")

    for iteration in range(next_iteration, max_iterations + 1):
        report = work_dir / "iterations" / f"{iteration:02d}"
        report.mkdir(parents=True, exist_ok=True)
        next_checkpoint = report / "next.il"
        did_path = report / "did-something.txt"
        result_path = report / "result.json"
        identity_path = report / "identity.json"
        iteration_input = current if iteration > 1 else input_path
        input_identity = resume_input_identity if iteration == next_iteration and resume_input_identity is not None else file_identity(iteration_input)
        result: dict[str, Any]
        use_cached = False
        cached = cached_iteration(iteration, input_identity, report, work_dir / "iteration.tcl")
        if cached is not None:
            candidate, result = cached
            if any(
                entry.get("iteration") == iteration and entry.get("identity") != candidate
                for entry in state["iterations"]
            ):
                raise ValueError(f"opt resume iteration identity mismatch for iteration {iteration}")
            use_cached = True
        if not use_cached:
            result = run_yosys(
                root,
                ["yosys", "-t", "--perffile", str(report / "perf.json"), "-c", str(work_dir / "iteration.tcl")],
                log=report / "yosys.log",
                result=report / "result.json",
                timeout=iteration_timeout,
                environment={"OPT_INPUT": str(iteration_input), "OPT_OUTPUT": str(next_checkpoint), "OPT_REPORT": str(report)},
            )
        if not next_checkpoint.is_file():
            raise RuntimeError(f"iteration produced no checkpoint: {iteration}")
        changed = parse_changed(did_path)
        identity = iteration_identity(iteration, input_identity, report, work_dir / "iteration.tcl", changed)
        if not use_cached:
            atomic_write(identity_path, dump_json(identity))
        item = {
            "iteration": iteration,
            "did_something": changed,
            "duration_seconds": result["duration_seconds"],
            "peak_rss_kib": result["peak_rss_kib"],
            "log": str(report / "yosys.log"),
            "result": str(result_path),
            "stat": str(report / "stat.rpt"),
            "identity": identity,
            "next_sha256": sha256(next_checkpoint),
            "did_sha256": sha256(did_path),
            "stat_sha256": sha256(report / "stat.rpt"),
        }
        state["iterations"] = [entry for entry in state["iterations"] if entry.get("iteration") != iteration]
        state["iterations"].append(item)
        state["iterations"].sort(key=lambda entry: entry["iteration"])
        checkpoint_tmp = work_dir / "current.tmp.il"
        shutil.copyfile(next_checkpoint, checkpoint_tmp)
        os.replace(checkpoint_tmp, current)
        state["current_sha256"] = item["next_sha256"]
        state["next_iteration"] = iteration + 1
        atomic_write(state_path, dump_json(state))
        print(f"opt resume: iteration={iteration} did_something={str(changed).lower()}", flush=True)
        if not changed:
            output_path.parent.mkdir(parents=True, exist_ok=True)
            output_tmp = output_path.with_name(output_path.name + ".tmp")
            shutil.copyfile(current, output_tmp)
            os.replace(output_tmp, output_path)
            state["output_sha256"] = sha256(output_path)
            state["status"] = "converged"
            atomic_write(state_path, dump_json(state))
            summary = summary_from_state(state, "converged", output_path)
            atomic_write(summary_path, dump_json(summary))
            return summary

    state["status"] = "bound_reached"
    atomic_write(state_path, dump_json(state))
    error = f"plain opt did not converge within {max_iterations} iterations"
    atomic_write(summary_path, dump_json(summary_from_state(state, "bound_reached", output_path, error)))
    raise RuntimeError(error)


def optimize(
    root: Path,
    input_path: Path,
    output_path: Path,
    work_dir: Path,
    *,
    max_iterations: int,
    iteration_timeout: int,
    fingerprint_environment: dict[str, str] | None = None,
) -> dict[str, Any]:
    work_dir = work_dir.resolve()
    with Lease(work_dir / "optimize.lock", {"task_id": "yosys-opt", "input": str(input_path.resolve())}):
        return _optimize_unlocked(
            root,
            input_path,
            output_path,
            work_dir,
            max_iterations=max_iterations,
            iteration_timeout=iteration_timeout,
            fingerprint_environment=fingerprint_environment,
        )


def _run_synthesis_unlocked(
    root: Path,
    script: Path,
    work_dir: Path,
    *,
    max_iterations: int,
    iteration_timeout: int,
    frontend_timeout: int,
) -> dict[str, Any]:
    text = script.read_text(encoding="utf-8")
    split_synth_script(text)
    work_dir = work_dir.resolve()
    work_dir.mkdir(parents=True, exist_ok=True)
    summary_path = work_dir / "synthesis-summary.json"
    optimizer_env = optimizer_environment()
    optimizer_environment_digest = digest_json(optimizer_env)
    fingerprint = execution_fingerprint(
        root,
        ["yosys_opt_resume", "synth"],
        os.environ.copy(),
        script=script,
        inputs=[script],
        configuration={
            "max_iterations": max_iterations,
            "iteration_timeout": iteration_timeout,
            "frontend_timeout": frontend_timeout,
        },
    )
    if summary_path.is_file():
        manifest = read_json(summary_path)
        if manifest.get("schema_version") != 2:
            raise ValueError("legacy synthesis manifest has no execution fingerprint")
        if manifest.get("optimizer_environment_sha256") != optimizer_environment_digest:
            raise ValueError("synthesis optimizer environment mismatch")
        mismatches = fingerprint_mismatches(manifest["fingerprint"], fingerprint)
        rebuildable = {"script_sha256", "input_sha256", "environment_sha256"}
        if mismatches:
            if not os.environ.get("SV_FLIST") or any(key not in rebuildable for key in mismatches):
                raise ValueError(f"synthesis fingerprint mismatch: {', '.join(mismatches)}")
            manifest = {
                "schema_version": 2,
                "status": "running",
                "fingerprint": fingerprint,
                "optimizer_environment_sha256": optimizer_environment_digest,
                "stages": {},
            }
        else:
            manifest["status"] = "running"
    else:
        manifest = {
            "schema_version": 2,
            "status": "running",
            "fingerprint": fingerprint,
            "optimizer_environment_sha256": optimizer_environment_digest,
            "stages": {},
        }
    manifest.setdefault("stages", {})
    write_json(summary_path, manifest)

    preloop = work_dir / "preloop.il"
    final = work_dir / "final.il"
    frontend_result = work_dir / "result-frontend.json"
    frontend_cache = work_dir / "cache-frontend.json"
    configuration = synthesis_identity(script, text)
    frontend_identity = {"stage": "frontend", "configuration": configuration, "output": str(preloop)}
    frontend_passed = configuration["sources"] is not None and stage_cache_valid(
        frontend_cache, frontend_result, frontend_identity, preloop
    )
    if not frontend_passed:
        atomic_write(work_dir / "frontend.tcl", frontend_script(text))
        run_yosys(
            root,
            ["yosys", "-t", "--perffile", str(work_dir / "frontend-perf.json"), "-c", str(work_dir / "frontend.tcl")],
            log=work_dir / "frontend.log",
            result=frontend_result,
            timeout=frontend_timeout,
            environment={"OPT_PRELOOP": str(preloop), "YOSYS_SCRIPT_DIR": str(script.resolve().parent)},
        )
        record_stage_cache(frontend_cache, frontend_result, frontend_identity, preloop)
        manifest["stages"]["frontend"] = {
            "result": str(frontend_result),
            "preloop_sha256": sha256(preloop),
        }
        write_json(summary_path, manifest)

    summary = optimize(
        root,
        preloop,
        final,
        work_dir,
        max_iterations=max_iterations,
        iteration_timeout=iteration_timeout,
        fingerprint_environment=optimizer_env,
    )
    manifest["stages"]["opt"] = {"status": summary["status"], "final_sha256": sha256(final)}
    write_json(summary_path, manifest)

    backend_result = work_dir / "result-backend.json"
    backend_cache = work_dir / "cache-backend.json"
    netlist = Path(os.environ["NETLIST"]).resolve() if "NETLIST" in os.environ else None
    backend_identity = {
        "stage": "backend",
        "configuration": configuration,
        "input_sha256": sha256(final),
        "output": str(netlist) if netlist is not None else None,
    }
    backend_passed = False
    if configuration["sources"] is not None:
        backend_passed = stage_cache_valid(backend_cache, backend_result, backend_identity, netlist)
    else:
        backend_stage = manifest["stages"].get("backend", {})
        if backend_result.is_file() and backend_stage and (netlist is None or netlist.is_file()):
            previous = read_json(backend_result)
            if previous.get("status") == "passed" and previous.get("exit_code") == 0:
                if netlist is not None and backend_stage.get("netlist_sha256") != sha256(netlist):
                    raise ValueError("backend output digest does not match the synthesis manifest")
                backend_passed = True
    if not backend_passed:
        atomic_write(work_dir / "backend.tcl", backend_script(text))
        run_yosys(
            root,
            ["yosys", "-t", "--perffile", str(work_dir / "backend-perf.json"), "-c", str(work_dir / "backend.tcl")],
            log=work_dir / "backend.log",
            result=backend_result,
            timeout=frontend_timeout,
            environment={"OPT_FINAL": str(final), "YOSYS_SCRIPT_DIR": str(script.resolve().parent)},
        )
        record_stage_cache(backend_cache, backend_result, backend_identity, netlist)
        manifest["stages"]["backend"] = {
            "result": str(backend_result),
            "netlist_sha256": sha256(netlist) if netlist and netlist.is_file() else None,
        }
        write_json(summary_path, manifest)

    document = dict(manifest, status="passed", opt=summary, backend=read_json(backend_result))
    write_json(summary_path, document)
    return document


def run_synthesis(
    root: Path,
    script: Path,
    work_dir: Path,
    *,
    max_iterations: int,
    iteration_timeout: int,
    frontend_timeout: int,
) -> dict[str, Any]:
    work_dir = work_dir.resolve()
    with Lease(work_dir / "synthesis.lock", {"task_id": "yosys-synth", "script": str(script.resolve())}):
        return _run_synthesis_unlocked(
            root,
            script,
            work_dir,
            max_iterations=max_iterations,
            iteration_timeout=iteration_timeout,
            frontend_timeout=frontend_timeout,
        )


def positive(value: str) -> int:
    parsed = int(value)
    if parsed <= 0:
        raise argparse.ArgumentTypeError("value must be positive")
    return parsed


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=ROOT)
    subparsers = parser.add_subparsers(dest="command", required=True)
    opt = subparsers.add_parser("opt")
    opt.add_argument("--input", type=Path, required=True)
    opt.add_argument("--output", type=Path, required=True)
    opt.add_argument("--work-dir", type=Path, required=True)
    opt.add_argument("--max-iterations", type=positive, default=64)
    opt.add_argument("--iteration-timeout", type=positive, default=600)
    synth = subparsers.add_parser("synth")
    synth.add_argument("--script", type=Path, required=True)
    synth.add_argument("--work-dir", type=Path, required=True)
    synth.add_argument("--max-iterations", type=positive, default=64)
    synth.add_argument("--iteration-timeout", type=positive, default=600)
    synth.add_argument("--frontend-timeout", type=positive, default=10800)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        if args.command == "opt":
            summary = optimize(
                args.root.resolve(),
                args.input,
                args.output,
                args.work_dir,
                max_iterations=args.max_iterations,
                iteration_timeout=args.iteration_timeout,
            )
            print(f"opt resume: CONVERGED iterations={summary['completed_iterations']}: {summary['output']}")
        else:
            summary = run_synthesis(
                args.root.resolve(),
                args.script,
                args.work_dir,
                max_iterations=args.max_iterations,
                iteration_timeout=args.iteration_timeout,
                frontend_timeout=args.frontend_timeout,
            )
            print(f"opt resume: synthesis complete: {summary['backend']['log']}")
        return 0
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError, json.JSONDecodeError) as error:
        print(f"opt resume: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
