#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import os
import re
import resource
import selectors
import signal
import subprocess
import sys
import termios
import time
import uuid
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from scripts.flow_control import (  # noqa: E402
    Lease,
    cancel_result,
    execution_fingerprint,
    fingerprint_mismatches,
    preserve_attempt,
    process_group_exists,
    process_start_ticks,
    reconcile_result,
    terminate_process_group,
    utc_now,
    write_json,
)

FAILURE_MARKER = re.compile(r"(?:\bFAILED?\b|\bFATAL\b|assertion failed|%Error)", re.IGNORECASE)


def parse_env(values: list[str]) -> dict[str, str]:
    environment = os.environ.copy()
    for item in values:
        name, separator, value = item.partition("=")
        if not separator or not name:
            raise ValueError(f"invalid environment assignment: {item}")
        environment[name] = value
    return environment


def should_display(tool: str, line: str) -> bool:
    if tool != "yosys":
        return True
    keywords = ("Executing", "Warning", "Error", "Build succeeded", "End of script")
    return any(keyword in line for keyword in keywords)


def jobserver_fds() -> tuple[int, ...]:
    match = re.search(r"--jobserver-(?:auth|fds)=(\d+),(\d+)", os.environ.get("MAKEFLAGS", ""))
    if not match:
        return ()
    descriptors = tuple(int(value) for value in match.groups())
    try:
        for descriptor in descriptors:
            os.fstat(descriptor)
    except OSError:
        return ()
    return descriptors


def terminal_requires_crlf() -> bool:
    if not sys.stdout.isatty():
        return False
    try:
        output_flags = termios.tcgetattr(sys.stdout.fileno())[1]
    except OSError:
        return False
    return not (output_flags & termios.OPOST and output_flags & termios.ONLCR)


def write_console_output(line: str) -> None:
    if terminal_requires_crlf():
        line = line.replace("\n", "\r\n")
    sys.stdout.write(line)
    sys.stdout.flush()


def write_console_bytes(chunk: bytes) -> None:
    if terminal_requires_crlf():
        chunk = chunk.replace(b"\n", b"\r\n")
    sys.stdout.buffer.write(chunk)
    sys.stdout.buffer.flush()


def stop_process(process: subprocess.Popen[str] | subprocess.Popen[bytes]) -> bool:
    pending = terminate_process_group(process.pid)
    try:
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait(timeout=5)
    return pending or process_group_exists(process.pid)


def positive_float(value: str) -> float:
    parsed = float(value)
    if parsed <= 0:
        raise argparse.ArgumentTypeError("value must be positive")
    return parsed


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run a flow command with structured results")
    parser.add_argument("--tool", required=True)
    parser.add_argument("--log", type=Path, required=True)
    parser.add_argument("--result", type=Path, required=True)
    parser.add_argument("--cwd", type=Path)
    parser.add_argument("--env", action="append", default=[])
    parser.add_argument("--stream-bytes", action="store_true")
    parser.add_argument("--success-marker")
    parser.add_argument("--terminate-on-success-marker", action="store_true")
    parser.add_argument("--resume", action="store_true")
    parser.add_argument("--status", action="store_true")
    parser.add_argument("--cancel", action="store_true")
    parser.add_argument("--task-id")
    parser.add_argument("--timeout-seconds", type=positive_float)
    parser.add_argument("--heartbeat-seconds", type=positive_float, default=5.0)
    parser.add_argument("--script", type=Path)
    parser.add_argument("--input", dest="inputs", type=Path, action="append", default=[])
    parser.add_argument("--pdk")
    parser.add_argument("--soc")
    parser.add_argument("--profile")
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command[1:] if args.command[:1] == ["--"] else args.command
    if args.status and args.cancel:
        parser.error("--status and --cancel are mutually exclusive")
    if (args.status or args.cancel) and (command or args.resume):
        parser.error("--status/--cancel do not accept a command or --resume")
    if not command and not (args.status or args.cancel):
        parser.error("a command is required after --")
    if args.terminate_on_success_marker and not args.success_marker:
        parser.error("--terminate-on-success-marker requires --success-marker")
    if args.terminate_on_success_marker and args.stream_bytes:
        parser.error("success-marker termination is unsupported with --stream-bytes")
    args.command = command
    return args


def emit(document: dict[str, Any]) -> None:
    print(json.dumps(document, indent=2, sort_keys=True))


def run_command(
    args: argparse.Namespace,
    command: list[str],
    environment: dict[str, str],
    running_result: dict[str, Any],
    started_clock: float,
) -> int:
    returncode = 127
    error_message = None
    process: subprocess.Popen[str] | subprocess.Popen[bytes] | None = None
    marker_seen = False
    rejected_matches: list[str] = []
    deadline_clock = started_clock + args.timeout_seconds if args.timeout_seconds else None
    next_heartbeat = started_clock + args.heartbeat_seconds

    def interrupt_flow(_signum: int, _frame: object) -> None:
        signal.signal(signal.SIGINT, signal.SIG_IGN)
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
        raise KeyboardInterrupt

    signal.signal(signal.SIGINT, interrupt_flow)
    signal.signal(signal.SIGTERM, interrupt_flow)
    try:
        log_context = args.log.open("wb") if args.stream_bytes else args.log.open("w", encoding="utf-8", errors="replace")
        with log_context as log:
            process = subprocess.Popen(
                command,
                cwd=args.cwd,
                env=environment,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=not args.stream_bytes,
                errors=None if args.stream_bytes else "replace",
                bufsize=0 if args.stream_bytes else 1,
                pass_fds=jobserver_fds(),
                start_new_session=True,
            )
            running_result.update(
                child_pid=process.pid,
                child_start_ticks=process_start_ticks(process.pid),
                process_group_id=process.pid,
            )
            write_json(args.result, running_result)
            assert process.stdout is not None
            selector = selectors.DefaultSelector()
            selector.register(process.stdout, selectors.EVENT_READ)
            eof = False
            while not eof:
                now = time.monotonic()
                if deadline_clock is not None and now >= deadline_clock:
                    returncode = 124
                    error_message = f"flow exceeded its {args.timeout_seconds}-second deadline"
                    stop_process(process)
                    break
                if process.poll() is not None:
                    returncode = process.returncode
                    if process_group_exists(process.pid):
                        error_message = "direct child exited while its process group remained active"
                        if returncode == 0:
                            returncode = 1
                        stop_process(process)
                        break
                if now >= next_heartbeat:
                    running_result["heartbeat_at"] = utc_now()
                    running_result["child_cleanup_pending"] = process_group_exists(process.pid)
                    write_json(args.result, running_result)
                    next_heartbeat = now + args.heartbeat_seconds
                wait_seconds = args.heartbeat_seconds
                if deadline_clock is not None:
                    wait_seconds = min(wait_seconds, max(0.01, deadline_clock - now))
                if not selector.select(wait_seconds):
                    continue
                if args.stream_bytes:
                    chunk = os.read(process.stdout.fileno(), 4096)
                    if not chunk:
                        eof = True
                        continue
                    log.write(chunk)
                    log.flush()
                    write_console_bytes(chunk)
                    continue
                line = process.stdout.readline()
                if not line:
                    eof = True
                    continue
                log.write(line)
                log.flush()
                match = FAILURE_MARKER.search(line)
                if match:
                    rejected_matches.append(match.group(0))
                if should_display(args.tool, line):
                    write_console_output(line)
                if args.terminate_on_success_marker and args.success_marker in line:
                    marker_seen = True
                    stop_process(process)
                    returncode = 1 if rejected_matches else 0
                    break
            if not marker_seen and returncode == 127:
                returncode = process.wait()
    except KeyboardInterrupt:
        error_message = "interrupted"
        cancelled = dict(
            running_result,
            status="interrupted",
            exit_code=130,
            interrupted_at=utc_now(),
            child_cleanup_pending=process is not None,
        )
        write_json(args.result, cancelled)
        if process is not None:
            stop_process(process)
        returncode = 130
    except (OSError, subprocess.SubprocessError) as error:
        error_message = str(error)
        if process is not None:
            stop_process(process)
        if returncode == 0:
            returncode = 1
    except BaseException as error:
        error_message = f"unexpected {type(error).__name__}: {error}"
        if process is not None:
            stop_process(process)
        returncode = 1

    cleanup_pending = process_group_exists(process.pid) if process is not None else False
    if cleanup_pending:
        if returncode == 0:
            returncode = 1
        error_message = error_message or "process group remains active after cleanup"
    finished = datetime.now(timezone.utc)
    result = dict(
        running_result,
        finished_at=finished.isoformat(),
        duration_seconds=round(time.monotonic() - started_clock, 3),
        peak_rss_kib=resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss,
        exit_code=returncode,
        status="interrupted" if returncode == 130 else ("passed" if returncode == 0 else "failed"),
        child_cleanup_pending=cleanup_pending,
    )
    if process is not None:
        result["child_exit_code"] = process.returncode
    if error_message:
        result["error"] = error_message
    if args.success_marker:
        result["success_marker"] = args.success_marker
        result["success_marker_seen"] = marker_seen
    if marker_seen:
        result["completion_mode"] = "success_marker"
    if rejected_matches:
        result["rejected_matches"] = sorted(set(rejected_matches))
    write_json(args.result, result)
    return returncode


def execute(args: argparse.Namespace, environment: dict[str, str]) -> int:
    command = args.command
    cwd = (args.cwd or Path.cwd()).resolve()
    previous = reconcile_result(args.result) if args.result.is_file() else None
    configuration = {"pdk": args.pdk, "soc": args.soc, "profile": args.profile}
    fingerprint = execution_fingerprint(
        cwd,
        command,
        environment,
        script=args.script,
        inputs=args.inputs,
        configuration=configuration,
    )
    metadata = {"task_id": args.task_id or args.tool, "command_sha256": fingerprint["command_sha256"]}
    lock_path = args.result.with_name(args.result.name + ".lock")
    with Lease(lock_path, metadata):
        if previous and previous.get("status") == "running":
            raise RuntimeError(f"another flow still owns the running result: {args.result}")
        if args.resume and previous:
            mismatches = fingerprint_mismatches(previous, fingerprint)
            if mismatches:
                raise RuntimeError(f"resume fingerprint mismatch: {', '.join(mismatches)}")
            if previous.get("status") == "passed":
                emit(previous)
                return 0
        previous = preserve_attempt(args.result, args.log)
        attempt = int(previous.get("attempt", 1)) + 1 if previous else 1
        started = datetime.now(timezone.utc)
        started_clock = time.monotonic()
        running_result: dict[str, Any] = {
            "schema_version": 2,
            **fingerprint,
            "run_id": uuid.uuid4().hex,
            "task_id": args.task_id or args.tool,
            "attempt": attempt,
            "tool": args.tool,
            "command": command,
            "cwd": str(cwd),
            "started_at": started.isoformat(),
            "heartbeat_at": started.isoformat(),
            "deadline_at": (started + timedelta(seconds=args.timeout_seconds)).isoformat() if args.timeout_seconds else None,
            "status": "running",
            "parent_pid": os.getpid(),
            "parent_start_ticks": process_start_ticks(os.getpid()),
            "log": str(args.log.resolve()),
        }
        write_json(args.result, running_result)
        return run_command(args, command, environment, running_result, started_clock)


def main() -> int:
    args = parse_args()
    try:
        if args.status:
            emit(reconcile_result(args.result))
            return 0
        if args.cancel:
            emit(cancel_result(args.result))
            return 0
        environment = parse_env(args.env)
        return execute(args, environment)
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        print(f"run_flow: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
