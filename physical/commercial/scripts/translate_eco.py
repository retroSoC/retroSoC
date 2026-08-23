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
import re
import sys


CURRENT = re.compile(r"^current_instance(?:\s+\{([^}]*)\})?\s*$")
SIZE = re.compile(r"^size_cell\s+\{([^}]+)\}\s+\{([^}]+)\}\s*$")
INSERT = re.compile(
    r"^insert_buffer\s+\[get_pins\s+\{([^}]+)\}\]\s+(\S+)"
    r"\s+-new_net_names\s+\{([^}]+)\}\s+-new_cell_names\s+\{([^}]+)\}\s*$"
)


def full_name(parent, name):
    if not parent:
        return name
    return parent.rstrip("/") + "/" + name


def translate(paths):
    output = []
    for path in paths:
        current = ""
        with open(path, "r") as handle:
            for number, raw_line in enumerate(handle, 1):
                line = raw_line.strip()
                if not line or line.startswith("#"):
                    continue
                match = CURRENT.match(line)
                if match:
                    current = match.group(1) or ""
                    continue
                match = SIZE.match(line)
                if match:
                    output.append(
                        "ecoChangeCell -inst {{{0}}} -cell {{{1}}}".format(
                            full_name(current, match.group(1)), match.group(2)
                        )
                    )
                    continue
                match = INSERT.match(line)
                if match:
                    output.append(
                        "ecoAddRepeater -term {{{0}}} -cell {{{1}}} "
                        "-newNetName {{{2}}} -name {{{3}}}".format(
                            full_name(current, match.group(1)),
                            match.group(2),
                            match.group(3),
                            match.group(4),
                        )
                    )
                    continue
                raise ValueError(
                    "{0}:{1}: unsupported PrimeTime ECO command: {2}".format(
                        path, number, line
                    )
                )
    return output


def main():
    parser = argparse.ArgumentParser(description="Translate reviewed PrimeTime ECO operations")
    parser.add_argument("--input", action="append", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--allow-empty", action="store_true")
    args = parser.parse_args()
    try:
        commands = translate(args.input)
    except (IOError, ValueError) as error:
        print("ERROR: {0}".format(error), file=sys.stderr)
        return 2
    if not commands and not args.allow_empty:
        print("ERROR: PrimeTime produced no supported ECO operations", file=sys.stderr)
        return 2
    parent = os.path.dirname(os.path.abspath(args.output))
    if not os.path.isdir(parent):
        os.makedirs(parent)
    with open(args.output, "w") as handle:
        if commands:
            handle.write("\n".join(commands))
            handle.write("\n")
        else:
            handle.write("# No ECO operations were required.\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
