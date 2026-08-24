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
import subprocess
import sys
import time

from check_outputs import apply_check, write_verdict


def main():
    parser = argparse.ArgumentParser(description="Run a tool and apply a strict result check")
    parser.add_argument("--kind", required=True)
    parser.add_argument("--root", required=True)
    parser.add_argument("--verdict", required=True)
    parser.add_argument("--limit", type=int, default=0)
    parser.add_argument("--top")
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    if args.command and args.command[0] == "--":
        args.command = args.command[1:]
    if not args.command:
        parser.error("a command is required after --")

    if os.path.isfile(args.verdict):
        os.remove(args.verdict)
    started = time.time()
    exit_code = subprocess.call(args.command)
    if exit_code != 0:
        return exit_code
    error = apply_check(
        args.kind,
        args.root,
        args.limit,
        args.top,
        started - 2.0,
    )
    if error:
        print("ERROR: {0}".format(error), file=sys.stderr)
        return 2
    write_verdict(args.verdict)
    return 0


if __name__ == "__main__":
    sys.exit(main())
