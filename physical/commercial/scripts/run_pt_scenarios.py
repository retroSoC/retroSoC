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
import shutil
import subprocess
import sys


def command_parts(value):
    parts = shlex.split(value)
    if not parts:
        raise ValueError("tool command is empty")
    return parts


def read_scenarios(tcl_command, script):
    command = command_parts(tcl_command) + [script]
    output = subprocess.check_output(command).decode("utf-8", "replace")
    scenarios = [line.strip() for line in output.splitlines() if line.strip()]
    if not scenarios:
        raise ValueError("the scenario list is empty")
    if len(scenarios) != len(set(scenarios)):
        raise ValueError("the scenario list contains duplicates")
    return scenarios


def write_text(path, text):
    parent = os.path.dirname(os.path.abspath(path))
    if not os.path.isdir(parent):
        os.makedirs(parent)
    with open(path, "w") as handle:
        handle.write(text)


def main():
    parser = argparse.ArgumentParser(
        description="Run every PrimeTime signoff scenario inside one LSF job"
    )
    parser.add_argument("--pt-command", required=True)
    parser.add_argument("--tcl-command", required=True)
    parser.add_argument("--scenario-script", required=True)
    parser.add_argument("--main", required=True)
    parser.add_argument("--tag", choices=("route", "eco"), required=True)
    args = parser.parse_args()

    run_root = os.environ.get("RUN_ROOT", "").strip()
    if not run_root:
        parser.error("RUN_ROOT is not set")
    base = os.path.join(run_root, "sta", args.tag)
    log_dir = os.path.join(base, "log")
    work_dir = os.path.join(base, "work")
    output_dir = os.path.join(base, "output")
    verdict = os.path.join(output_dir, "verdict.pass")
    if os.path.isfile(verdict):
        os.remove(verdict)

    try:
        scenarios = read_scenarios(args.tcl_command, args.scenario_script)
        pt_command = command_parts(args.pt_command)
    except (OSError, subprocess.CalledProcessError, ValueError) as error:
        print("ERROR: {0}".format(error), file=sys.stderr)
        return 2

    summary = "scenario\tsetup\thold\tdrv\n"
    for scenario in scenarios:
        marker = os.path.join(output_dir, scenario + ".pass")
        scenario_summary = os.path.join(output_dir, scenario + ".summary.tsv")
        session = os.path.join(work_dir, "sessions", scenario)
        for path in (marker, scenario_summary):
            if os.path.isfile(path):
                os.remove(path)
        if args.tag == "route" and os.path.isdir(session):
            shutil.rmtree(session)

        environment = os.environ.copy()
        environment["STA_TAG"] = args.tag
        environment["STA_SCENARIO"] = scenario
        log_path = os.path.join(log_dir, scenario + ".log")
        print("PrimeTime scenario: {0}".format(scenario))
        with open(log_path, "wb") as log_handle:
            try:
                exit_code = subprocess.call(
                    pt_command + ["-f", args.main],
                    cwd=work_dir,
                    env=environment,
                    stdout=log_handle,
                    stderr=subprocess.STDOUT,
                )
            except OSError as error:
                print("ERROR: {0}".format(error), file=sys.stderr)
                return 127
        if exit_code != 0:
            print(
                "ERROR: PrimeTime scenario {0} exited with {1}; see {2}".format(
                    scenario, exit_code, log_path
                ),
                file=sys.stderr,
            )
            return exit_code
        if not os.path.isfile(marker) or not os.path.isfile(scenario_summary):
            print(
                "ERROR: PrimeTime scenario {0} did not write its verdict".format(
                    scenario
                ),
                file=sys.stderr,
            )
            return 2
        if args.tag == "route" and not os.path.isdir(session):
            print(
                "ERROR: PrimeTime scenario {0} did not save a session".format(
                    scenario
                ),
                file=sys.stderr,
            )
            return 2
        with open(scenario_summary, "r") as handle:
            summary += handle.read()

    write_text(os.path.join(output_dir, "summary.tsv"), summary)
    write_text(verdict, "PASS\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
