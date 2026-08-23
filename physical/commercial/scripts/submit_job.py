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
import os
import shlex
import subprocess
import sys


def build_submission(mode, bsub_command, bsub_args, tool_log, tool_command):
    command = shlex.split(bsub_command)
    resources = shlex.split(bsub_args)
    if not command:
        raise ValueError("LSF command is empty")
    if mode == "batch":
        return (
            command
            + ["-K"]
            + resources
            + ["-oo", tool_log, "-eo", tool_log]
            + tool_command
        )
    logger = os.path.join(os.path.dirname(os.path.abspath(__file__)), "run_logged.py")
    return (
        command
        + ["-I"]
        + resources
        + [sys.executable, logger, "--log", tool_log, "--"]
        + tool_command
    )


def main():
    parser = argparse.ArgumentParser(description="Submit one blocking LSF EDA job")
    parser.add_argument("--mode", choices=("batch", "interactive"), required=True)
    parser.add_argument("--bsub-command", required=True)
    parser.add_argument("--bsub-args", default="")
    parser.add_argument("--tool-log", required=True)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    if args.command and args.command[0] == "--":
        args.command = args.command[1:]
    if not args.command:
        parser.error("a tool command is required after --")
    try:
        command = build_submission(
            args.mode,
            args.bsub_command,
            args.bsub_args,
            os.path.abspath(args.tool_log),
            args.command,
        )
        return subprocess.call(command)
    except (OSError, ValueError) as error:
        print("ERROR: {0}".format(error), file=sys.stderr)
        return 127


if __name__ == "__main__":
    sys.exit(main())
