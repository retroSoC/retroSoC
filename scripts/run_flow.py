#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import termios
import time
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from scripts.setup_helpers import atomic_write  # noqa: E402


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


def main() -> int:
    parser = argparse.ArgumentParser(description="Run a flow command with structured results")
    parser.add_argument("--tool", required=True)
    parser.add_argument("--log", type=Path, required=True)
    parser.add_argument("--result", type=Path, required=True)
    parser.add_argument("--cwd", type=Path)
    parser.add_argument("--env", action="append", default=[])
    parser.add_argument(
        "--stream-bytes",
        action="store_true",
        help="stream child output byte-by-byte and preserve raw log bytes",
    )
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command[1:] if args.command[:1] == ["--"] else args.command
    if not command:
        parser.error("a command is required after --")
    try:
        environment = parse_env(args.env)
    except ValueError as error:
        parser.error(str(error))

    args.log.parent.mkdir(parents=True, exist_ok=True)
    args.result.parent.mkdir(parents=True, exist_ok=True)
    started = datetime.now(timezone.utc)
    start_clock = time.monotonic()
    returncode = 127
    error_message = None
    process: subprocess.Popen[str] | subprocess.Popen[bytes] | None = None
    try:
        if args.stream_bytes:
            log_context = args.log.open("wb")
        else:
            log_context = args.log.open("w", encoding="utf-8", errors="replace")
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
            )
            assert process.stdout is not None
            if args.stream_bytes:
                while chunk := os.read(process.stdout.fileno(), 4096):
                    log.write(chunk)
                    log.flush()
                    write_console_bytes(chunk)
            else:
                for line in process.stdout:
                    log.write(line)
                    log.flush()
                    if should_display(args.tool, line):
                        write_console_output(line)
            returncode = process.wait()
    except KeyboardInterrupt:
        error_message = "interrupted"
        if process is not None and process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
        returncode = 130
    except (OSError, subprocess.SubprocessError) as error:
        error_message = str(error)

    finished = datetime.now(timezone.utc)
    result = {
        "schema_version": 1,
        "tool": args.tool,
        "command": command,
        "cwd": str(args.cwd.resolve()) if args.cwd else os.getcwd(),
        "started_at": started.isoformat(),
        "finished_at": finished.isoformat(),
        "duration_seconds": round(time.monotonic() - start_clock, 3),
        "exit_code": returncode,
        "status": "passed" if returncode == 0 else "failed",
        "log": str(args.log.resolve()),
    }
    if error_message:
        result["error"] = error_message
    atomic_write(args.result, json.dumps(result, indent=2, sort_keys=True) + "\n")
    return returncode


if __name__ == "__main__":
    raise SystemExit(main())
