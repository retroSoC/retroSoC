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


def read_text(path):
    with open(path, "r") as handle:
        return handle.read()


SPEF_CORNERS = (
    "Cworst_m40",
    "Cworst_125",
    "RCworst_m40",
    "RCworst_125",
    "Cbest_m40",
    "Cbest_125",
    "RCbest_m40",
    "RCbest_125",
    "TYP_25",
)


def find_files(root, suffixes):
    found = []
    for directory, unused_dirs, files in os.walk(root):
        for name in files:
            if any(name.lower().endswith(suffix) for suffix in suffixes):
                found.append(os.path.join(directory, name))
    return found


def calibre_count(text):
    matches = re.findall(
        r"(?:TOTAL\s+(?:DRC\s+)?RESULTS\s+GENERATED|DRC\s+RESULTS)"
        r"\s*[:=]\s*(\d+)",
        text,
        re.IGNORECASE,
    )
    return max([int(value) for value in matches] or [-1])


def apply_check(kind, root, limit, top=None, minimum_mtime=None):
    error = None
    if kind == "spef":
        if not top:
            error = "the SPEF check requires the design top"
            files = []
        else:
            files = [
                os.path.join(root, "{0}.{1}.spef.gz".format(top, corner))
                for corner in SPEF_CORNERS
            ]
            missing = [path for path in files if not os.path.isfile(path)]
            if missing:
                error = "missing ICS55 SPEF corners: {0}".format(
                    ", ".join(os.path.basename(path) for path in missing)
                )
            elif any(os.path.getsize(path) == 0 for path in files):
                error = "an ICS55 SPEF corner is empty"
    elif kind in ("calibre-drc", "calibre-antenna"):
        reports = find_files(root, (".summary", ".sum", ".rpt"))
        files = reports
        counts = [calibre_count(read_text(path)) for path in reports]
        counts = [count for count in counts if count >= 0]
        if not counts:
            error = "Calibre summary does not contain a result count"
        elif max(counts) > limit:
            error = "Calibre result count {0} exceeds {1}".format(max(counts), limit)
    elif kind == "calibre-lvs":
        reports = find_files(root, (".rpt", ".report"))
        files = reports
        text = "\n".join(read_text(path) for path in reports)
        clean = re.search(
            r"(?:LVS\s+COMPLETED\s+CORRECT|"
            r"OVERALL\s+COMPARISON\s+RESULTS.{0,2000}?\bCORRECT\b)",
            text,
            re.IGNORECASE | re.DOTALL,
        )
        if not clean:
            error = "Calibre LVS report is not clean"
        if re.search(r"(INCORRECT|NOT\s+COMPARED|ERROR:)", text, re.IGNORECASE):
            error = "Calibre LVS report contains a failure marker"
    else:
        error = "unknown check kind: {0}".format(kind)
        files = []
    if error is None and minimum_mtime is not None:
        stale = [path for path in files if os.path.getmtime(path) < minimum_mtime]
        if stale:
            error = "result files were not refreshed: {0}".format(
                ", ".join(os.path.basename(path) for path in stale)
            )
    return error


def write_verdict(path):
    parent = os.path.dirname(os.path.abspath(path))
    if not os.path.isdir(parent):
        os.makedirs(parent)
    with open(path, "w") as handle:
        handle.write("PASS\n")


def main():
    parser = argparse.ArgumentParser(description="Apply strict output verdicts")
    parser.add_argument("--kind", required=True)
    parser.add_argument("--root", required=True)
    parser.add_argument("--verdict", required=True)
    parser.add_argument("--limit", type=int, default=0)
    parser.add_argument("--top")
    args = parser.parse_args()
    error = apply_check(args.kind, args.root, args.limit, args.top)
    if error:
        print("ERROR: {0}".format(error), file=sys.stderr)
        return 2
    write_verdict(args.verdict)
    return 0


if __name__ == "__main__":
    sys.exit(main())
