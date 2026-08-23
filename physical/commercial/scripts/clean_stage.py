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
import shutil
import sys


STAGES = (
    ("input", "input"),
    ("syn", "syn"),
    ("fm-rtl2syn", "formality/rtl2syn"),
    ("apr-initialize", "apr/initialize"),
    ("apr-floorplan", "apr/floorplan"),
    ("apr-preplace", "apr/preplace"),
    ("apr-place", "apr/place"),
    ("apr-cts", "apr/cts"),
    ("apr-route", "apr/route"),
    ("fm-syn2pr", "formality/syn2pr"),
    ("extract", "extract/route"),
    ("sta", "sta/route"),
    ("eco", "eco"),
    ("apr-eco", "apr/eco"),
    ("reextract", "extract/eco"),
    ("resta", "sta/eco"),
    ("pv-merge", "pv/merge"),
    ("pv-drc", "pv/drc"),
    ("pv-antenna", "pv/antenna"),
    ("pv-lvs", "pv/lvs"),
)


def contained(root, path):
    root = os.path.realpath(root)
    path = os.path.realpath(path)
    return path != root and path.startswith(root + os.sep)


def main():
    parser = argparse.ArgumentParser(description="Clean one stage and its dependants")
    parser.add_argument("--build-root", required=True)
    parser.add_argument("--run-root", required=True)
    parser.add_argument("--from-stage", required=True)
    args = parser.parse_args()

    names = [name for name, unused in STAGES]
    if args.from_stage not in names:
        parser.error("unknown stage: {0}".format(args.from_stage))
    if not contained(args.build_root, args.run_root):
        parser.error("run root must be below build root")

    start = names.index(args.from_stage)
    stamp_dir = os.path.join(args.run_root, "meta", "stamps")
    for name, relative in STAGES[start:]:
        path = os.path.join(args.run_root, relative)
        if os.path.isdir(path):
            shutil.rmtree(path)
        stamp = os.path.join(stamp_dir, name + ".stamp")
        if os.path.isfile(stamp):
            os.remove(stamp)
        print("cleaned: {0}".format(name))
    return 0


if __name__ == "__main__":
    sys.exit(main())
