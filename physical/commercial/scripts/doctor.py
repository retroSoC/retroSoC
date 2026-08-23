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
import json
import os
import shlex
import subprocess
import sys

try:
    from shutil import which
except ImportError:
    from distutils.spawn import find_executable as which


TOOL_VARIABLES = (
    "LSF_COMMAND",
    "DC_SHELL",
    "FM_SHELL",
    "INNOVUS",
    "STARRC",
    "PT_SHELL",
    "CALIBRE",
    "CALIBREDRV",
    "V2LVS",
)

FILE_LIST_VARIABLES = (
    "STD_DB_MAX", "STD_DB_WCL", "STD_DB_TYP", "STD_DB_MIN", "STD_DB_ML",
    "IO_DB_MAX", "IO_DB_WCL", "IO_DB_TYP", "IO_DB_MIN", "IO_DB_ML",
    "SRAM_DB_MAX", "SRAM_DB_WCL", "SRAM_DB_TYP", "SRAM_DB_MIN", "SRAM_DB_ML",
    "PLL_DB", "TECH_LEF", "STD_LEFS", "IO_LEFS", "MACRO_LEFS",
    "STD_LIB_MAX", "STD_LIB_WCL", "STD_LIB_TYP", "STD_LIB_MIN", "STD_LIB_ML",
    "IO_LIB_MAX", "IO_LIB_WCL", "IO_LIB_TYP", "IO_LIB_MIN", "IO_LIB_ML",
    "SRAM_LIB_MAX", "SRAM_LIB_WCL", "SRAM_LIB_TYP", "SRAM_LIB_MIN",
    "SRAM_LIB_ML", "PLL_LIB",
    "CAP_TABLE_CWORST", "CAP_TABLE_RCWORST", "CAP_TABLE_CBEST",
    "CAP_TABLE_RCBEST", "CAP_TABLE_TYP", "STREAM_MAP",
    "NXTGRD_CWORST", "NXTGRD_RCWORST", "NXTGRD_CBEST", "NXTGRD_RCBEST",
    "NXTGRD_TYP", "STARRC_MAP", "STD_GDS", "IO_GDS", "MACRO_GDS",
    "STD_CDL", "IO_CDL", "MACRO_CDL", "CALIBRE_DRC_DECK",
    "CALIBRE_ANT_DECK", "CALIBRE_LVS_DECK",
)

VALUE_VARIABLES = (
    "TOP", "TECHNOLOGY", "RTL_ARCHIVE", "LSF_MODE", "APR_SITE", "APR_CORE_FILLERS",
    "APR_IO_FILLERS", "APR_SIGNAL_PAD_CELLS", "APR_IO_CORNER_CELL",
    "APR_IO_POWER_CELLS", "APR_IO_OFFSET", "APR_IO_PITCH",
    "APR_ENDCAP_CELLS", "APR_TIE_HIGH_CELL", "APR_TIE_LOW_CELL",
    "APR_CTS_BUFFER_CELLS", "APR_CTS_INVERTER_CELLS",
    "APR_CLOCK_ROUTING_LAYERS", "APR_SIGNAL_MIN_LAYER",
    "APR_SIGNAL_MAX_LAYER", "APR_POWER_NET", "APR_GROUND_NET",
    "APR_POWER_PINS", "APR_GROUND_PINS", "APR_RING_LAYERS",
    "APR_STRIPE_LAYER", "APR_RING_WIDTH", "APR_RING_SPACING",
    "APR_RING_OFFSET", "APR_STRIPE_WIDTH", "APR_STRIPE_SPACING",
    "APR_STRIPE_PITCH", "LSF_SYN_ARGS", "LSF_FM_ARGS", "LSF_APR_ARGS",
    "LSF_EXTRACT_ARGS", "LSF_STA_ARGS", "LSF_ECO_ARGS", "LSF_PV_ARGS",
    "SYN_DONT_USE", "ECO_SETUP_BUFFERS", "ECO_HOLD_BUFFERS",
    "ECO_MAX_PROCESSES", "ECO_PHYSICAL_MODE",
)


def split_value(value):
    return shlex.split(value)


def command_path(value):
    parts = split_value(value)
    if not parts:
        return None
    if os.path.dirname(parts[0]):
        return parts[0] if os.access(parts[0], os.X_OK) else None
    return which(parts[0])


def version_output(command):
    try:
        return subprocess.check_output(command, stderr=subprocess.STDOUT).decode(
            "utf-8", "replace"
        ).strip()
    except (OSError, subprocess.CalledProcessError):
        return ""


def stdin_output(command, text):
    try:
        process = subprocess.Popen(
            command,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
        )
        output = process.communicate(text.encode("ascii"))[0]
        if process.returncode != 0:
            return ""
        return output.decode("utf-8", "replace").strip()
    except OSError:
        return ""


def main():
    parser = argparse.ArgumentParser(description="Validate the EDA-zone commercial setup")
    parser.add_argument("--output", required=True)
    parser.add_argument("--dev", action="store_true")
    args = parser.parse_args()

    errors = []
    values = {}
    for name in VALUE_VARIABLES:
        value = os.environ.get(name, "").strip()
        values[name] = value
        if not value or value == "REQUIRED":
            errors.append("{0} is not configured".format(name))

    qualified_pll = {
        "ICS55_PLL_SUPPORTED_SEL": "0",
        "ICS55_PLL_N": "2",
        "ICS55_PLL_OD": "2",
    }
    for name, expected in qualified_pll.items():
        value = os.environ.get(name, "").strip()
        values[name] = value
        if value != expected:
            errors.append(
                "{0} must match the qualified value {1}".format(name, expected)
            )
    for name in (
        "MAX_SETUP_VIOLATIONS",
        "MAX_HOLD_VIOLATIONS",
        "MAX_DRV_VIOLATIONS",
        "MAX_DRC_RESULTS",
        "MAX_ANTENNA_RESULTS",
    ):
        if os.environ.get(name, "").strip() != "0":
            errors.append("{0} must be zero for strict signoff".format(name))
    try:
        if int(values.get("ECO_MAX_PROCESSES", "")) < 1:
            raise ValueError
    except ValueError:
        errors.append("ECO_MAX_PROCESSES must be a positive integer")
    if values.get("ECO_PHYSICAL_MODE") not in ("open_site", "occupied_site"):
        errors.append("ECO_PHYSICAL_MODE must be open_site or occupied_site")
    if values.get("LSF_MODE") not in ("batch", "interactive"):
        errors.append("LSF_MODE must be batch or interactive")

    tools = {}
    for name in TOOL_VARIABLES:
        value = os.environ.get(name, "").strip()
        tools[name] = value
        if not args.dev and (not value or command_path(value) is None):
            errors.append("{0} is not executable".format(name))

    checked_files = {}
    for name in FILE_LIST_VARIABLES:
        value = os.environ.get(name, "").strip()
        paths = split_value(value) if value and value != "REQUIRED" else []
        checked_files[name] = paths
        if not paths:
            errors.append("{0} is not configured".format(name))
            continue
        for path in paths:
            if any(token in path for token in ("*", "?", "[")):
                errors.append("{0} contains a wildcard: {1}".format(name, path))
            elif not os.path.isfile(path) or not os.access(path, os.R_OK):
                errors.append("{0} is not readable: {1}".format(name, path))

    for prefix in ("STD", "IO", "SRAM"):
        for pvt in ("MAX", "WCL", "TYP", "MIN", "ML"):
            db_name = "{0}_DB_{1}".format(prefix, pvt)
            lib_name = "{0}_LIB_{1}".format(prefix, pvt)
            db_stems = sorted(
                os.path.splitext(os.path.basename(path))[0]
                for path in checked_files.get(db_name, ())
            )
            lib_stems = sorted(
                os.path.splitext(os.path.basename(path))[0]
                for path in checked_files.get(lib_name, ())
            )
            if db_stems != lib_stems:
                errors.append(
                    "{0} and {1} do not describe the same libraries".format(
                        db_name, lib_name
                    )
                )
    pll_db = checked_files.get("PLL_DB", ())
    pll_lib = checked_files.get("PLL_LIB", ())
    if pll_db and pll_lib:
        db_stem = os.path.splitext(os.path.basename(pll_db[0]))[0]
        lib_stem = os.path.splitext(os.path.basename(pll_lib[0]))[0]
        if db_stem != lib_stem:
            errors.append("PLL_DB and PLL_LIB do not describe the same library")

    archive = values.get("RTL_ARCHIVE", "")
    if archive and archive != "REQUIRED" and not os.path.isfile(archive):
        errors.append("RTL_ARCHIVE is not a file: {0}".format(archive))

    runtime = {
        "python": sys.version.split()[0],
        "make": version_output(["make", "--version"]).splitlines()[0],
        "tcl": stdin_output([os.environ.get("TCLSH", "tclsh")], "puts [info patchlevel]\n"),
    }
    result = {
        "schema_version": 1,
        "status": "failed" if errors else "passed",
        "runtime": runtime,
        "tools": tools,
        "checked_file_variables": checked_files,
        "errors": errors,
    }
    parent = os.path.dirname(os.path.abspath(args.output))
    if not os.path.isdir(parent):
        os.makedirs(parent)
    with open(args.output, "w") as handle:
        json.dump(result, handle, indent=2, sort_keys=True)
        handle.write("\n")
    if errors:
        for error in errors:
            print("ERROR: {0}".format(error), file=sys.stderr)
        return 2
    print("commercial flow doctor passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
