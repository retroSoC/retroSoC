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


def main():
    parser = argparse.ArgumentParser(description="Run and tee one EDA tool command")
    parser.add_argument("--log", required=True)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    if args.command and args.command[0] == "--":
        args.command = args.command[1:]
    if not args.command:
        parser.error("a command is required after --")

    parent = os.path.dirname(os.path.abspath(args.log))
    if not os.path.isdir(parent):
        os.makedirs(parent)
    try:
        process = subprocess.Popen(
            args.command,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
        )
    except OSError as error:
        print("ERROR: {0}".format(error), file=sys.stderr)
        return 127

    with open(args.log, "wb") as log_handle:
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


if __name__ == "__main__":
    sys.exit(main())
