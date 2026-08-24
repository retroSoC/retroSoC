#!/usr/bin/env python
# Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
# retroSoC is licensed under Mulan PSL v2.
# You can use this software according to the terms and conditions of the Mulan PSL v2.
# You may obtain a copy of Mulan PSL v2 at:
#             http://license.coscl.org.cn/MulanPSL2
# THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
# EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
# MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
# See the Mulan PSL v2 for more details.

from __future__ import print_function

import argparse
import datetime
import json
import os
import re
import subprocess
import sys
import time


def utc_timestamp():
    return datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")


def ensure_parent(path):
    parent = os.path.dirname(os.path.abspath(path))
    if not os.path.isdir(parent):
        os.makedirs(parent)


def write_json(path, value):
    ensure_parent(path)
    temporary = path + ".tmp"
    with open(temporary, "w") as handle:
        json.dump(value, handle, indent=2, sort_keys=True)
        handle.write("\n")
    os.rename(temporary, path)


def split_command_env(command):
    command_env = os.environ.copy()
    executable = list(command)
    assignment = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")
    while executable and assignment.match(executable[0]):
        name, value = executable.pop(0).split("=", 1)
        command_env[name] = value
    if not executable:
        raise ValueError("the command contains only environment assignments")
    return executable, command_env


def stream_command(command, cwd, log_path):
    ensure_parent(log_path)
    executable, command_env = split_command_env(command)
    with open(log_path, "wb") as log_handle:
        process = subprocess.Popen(
            executable,
            cwd=cwd,
            env=command_env,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
        )
        while True:
            chunk = process.stdout.readline()
            if not chunk:
                break
            log_handle.write(chunk)
            log_handle.flush()
            if hasattr(sys.stdout, "buffer"):
                sys.stdout.buffer.write(chunk)
                sys.stdout.buffer.flush()
            else:
                sys.stdout.write(chunk)
                sys.stdout.flush()
        return process.wait()


def parse_args():
    parser = argparse.ArgumentParser(description="Run one blocking commercial-flow stage")
    parser.add_argument("--stage", required=True)
    parser.add_argument("--cwd", required=True)
    parser.add_argument("--log", required=True)
    parser.add_argument("--result", required=True)
    parser.add_argument("--stamp", required=True)
    parser.add_argument("--expect", action="append", default=[])
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    if args.command and args.command[0] == "--":
        args.command = args.command[1:]
    if not args.command:
        parser.error("a command is required after --")
    return args


def main():
    args = parse_args()
    cwd = os.path.abspath(args.cwd)
    if not os.path.isdir(cwd):
        os.makedirs(cwd)
    if os.path.exists(args.stamp):
        os.remove(args.stamp)

    started_at = utc_timestamp()
    start = time.time()
    launch_error = ""
    try:
        exit_code = stream_command(args.command, cwd, args.log)
    except OSError as error:
        exit_code = 127
        launch_error = str(error)
    missing = [path for path in args.expect if not os.path.exists(path)]
    stale = [
        path
        for path in args.expect
        if path not in missing and os.path.getmtime(path) < start - 2.0
    ]
    status = "passed" if exit_code == 0 and not missing and not stale else "failed"
    result = {
        "schema_version": 1,
        "stage": args.stage,
        "status": status,
        "started_at": started_at,
        "finished_at": utc_timestamp(),
        "duration_seconds": round(time.time() - start, 3),
        "exit_code": exit_code,
        "launch_error": launch_error,
        "command": args.command,
        "cwd": cwd,
        "log": os.path.abspath(args.log),
        "expected_outputs": [os.path.abspath(path) for path in args.expect],
        "missing_outputs": [os.path.abspath(path) for path in missing],
        "stale_outputs": [os.path.abspath(path) for path in stale],
    }
    write_json(args.result, result)
    if status != "passed":
        if exit_code == 0:
            if missing:
                print(
                    "missing required outputs: {0}".format(", ".join(missing)),
                    file=sys.stderr,
                )
            if stale:
                print(
                    "required outputs were not refreshed: {0}".format(", ".join(stale)),
                    file=sys.stderr,
                )
            return 2
        return exit_code

    ensure_parent(args.stamp)
    with open(args.stamp, "w") as handle:
        handle.write("stage={0}\n".format(args.stage))
        handle.write("finished_at={0}\n".format(result["finished_at"]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
