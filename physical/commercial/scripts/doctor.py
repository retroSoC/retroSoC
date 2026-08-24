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

SYNTHESIS_TOOL_VARIABLES = (
    "LSF_COMMAND",
    "DC_SHELL",
    "FM_SHELL",
)

FILE_LIST_VARIABLES = (
    "STD_DB_MAX", "STD_DB_WCL", "STD_DB_TYP", "STD_DB_MIN", "STD_DB_ML",
    "SYN_STD_DB_TYP",
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

SYNTHESIS_FILE_VARIABLES = (
    "STD_DB_TYP",
    "SYN_STD_DB_TYP",
    "IO_DB_TYP",
    "SRAM_DB_TYP",
    "PLL_DB",
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
    "SYN_OPERATING_CONDITION_LIBRARY", "SYN_OPERATING_CONDITION",
)

SYNTHESIS_VALUE_VARIABLES = (
    "TOP",
    "TECHNOLOGY",
    "RTL_ARCHIVE",
    "LSF_MODE",
    "LSF_SYN_ARGS",
    "LSF_FM_ARGS",
    "SYN_DONT_USE",
    "SYN_OPERATING_CONDITION_LIBRARY",
    "SYN_OPERATING_CONDITION",
)

IO_BUDGET_VARIABLES = (
    "JTAG_INPUT_DELAY_MAX_NS", "JTAG_INPUT_DELAY_MIN_NS",
    "JTAG_INPUT_TRANSITION_NS", "JTAG_OUTPUT_DELAY_MAX_NS",
    "JTAG_OUTPUT_DELAY_MIN_NS", "JTAG_OUTPUT_LOAD_PF",
    "DVP_INPUT_DELAY_MAX_NS", "DVP_INPUT_DELAY_MIN_NS",
    "DVP_INPUT_TRANSITION_NS",
    "ULPI_INPUT_DELAY_MAX_NS", "ULPI_INPUT_DELAY_MIN_NS",
    "ULPI_INPUT_TRANSITION_NS", "ULPI_OUTPUT_DELAY_MAX_NS",
    "ULPI_OUTPUT_DELAY_MIN_NS", "ULPI_OUTPUT_LOAD_PF",
    "SDRAM_CLOCK_PERIOD_NS", "SDRAM_INPUT_DELAY_MAX_NS",
    "SDRAM_INPUT_DELAY_MIN_NS", "SDRAM_INPUT_TRANSITION_NS",
    "SDRAM_OUTPUT_DELAY_MAX_NS", "SDRAM_OUTPUT_DELAY_MIN_NS",
    "SDRAM_OUTPUT_LOAD_PF",
    "SDIO_CLOCK_PERIOD_NS", "SDIO_INPUT_DELAY_MAX_NS",
    "SDIO_INPUT_DELAY_MIN_NS", "SDIO_INPUT_TRANSITION_NS",
    "SDIO_OUTPUT_DELAY_MAX_NS", "SDIO_OUTPUT_DELAY_MIN_NS",
    "SDIO_OUTPUT_LOAD_PF",
    "XPI_CLOCK_PERIOD_NS", "XPI_INPUT_DELAY_MAX_NS",
    "XPI_INPUT_DELAY_MIN_NS", "XPI_INPUT_TRANSITION_NS",
    "XPI_OUTPUT_DELAY_MAX_NS", "XPI_OUTPUT_DELAY_MIN_NS",
    "XPI_OUTPUT_LOAD_PF",
    "ASYNC_CLOCK_PERIOD_NS", "ASYNC_INPUT_DELAY_MAX_NS",
    "ASYNC_INPUT_DELAY_MIN_NS", "ASYNC_INPUT_TRANSITION_NS",
    "ASYNC_OUTPUT_DELAY_MAX_NS", "ASYNC_OUTPUT_DELAY_MIN_NS",
    "ASYNC_OUTPUT_LOAD_PF",
)

H7C_PVT_TOKENS = {
    "MAX": "_ss_rcworst_1p08_125",
    "WCL": "_ss_cworst_1p08_m40",
    "TYP": "_typ_tt_1p2_25",
    "MIN": "_ff_rcbest_1p32_m40",
    "ML": "_ff_cbest_1p32_125",
}


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


def normalized_library_stem(path):
    stem = os.path.splitext(os.path.basename(path))[0]
    for suffix in ("_nldm", "_ccs"):
        if stem.endswith(suffix):
            return stem[:-len(suffix)]
    return stem


def h7c_variants(paths):
    variants = set()
    for path in paths:
        name = os.path.basename(path)
        for variant in ("H7CH", "H7CL", "H7CR"):
            if variant in name:
                variants.add(variant)
    return variants


def main():
    parser = argparse.ArgumentParser(description="Validate the EDA-zone commercial setup")
    parser.add_argument("--output", required=True)
    parser.add_argument("--dev", action="store_true")
    parser.add_argument("--allow-internal-qor", action="store_true")
    args = parser.parse_args()

    errors = []
    values = {}
    required_values = (
        SYNTHESIS_VALUE_VARIABLES if args.allow_internal_qor else VALUE_VARIABLES
    )
    for name in VALUE_VARIABLES:
        value = os.environ.get(name, "").strip()
        values[name] = value
        if name in required_values and (not value or value == "REQUIRED"):
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
    if not args.allow_internal_qor:
        for name in (
            "MAX_SETUP_VIOLATIONS",
            "MAX_HOLD_VIOLATIONS",
            "MAX_DRV_VIOLATIONS",
            "MAX_DRC_RESULTS",
            "MAX_ANTENNA_RESULTS",
        ):
            if os.environ.get(name, "").strip() != "0":
                errors.append("{0} must be zero for strict signoff".format(name))
    if not args.allow_internal_qor:
        try:
            if int(values.get("ECO_MAX_PROCESSES", "")) < 1:
                raise ValueError
        except ValueError:
            errors.append("ECO_MAX_PROCESSES must be a positive integer")
        if values.get("ECO_PHYSICAL_MODE") not in ("open_site", "occupied_site"):
            errors.append("ECO_PHYSICAL_MODE must be open_site or occupied_site")
    if values.get("LSF_MODE") not in ("batch", "interactive"):
        errors.append("LSF_MODE must be batch or interactive")

    io_mode = os.environ.get("IO_TIMING_QUALIFIED", "").strip().upper()
    if io_mode == "YES":
        for name in IO_BUDGET_VARIABLES:
            value = os.environ.get(name, "").strip()
            if not value or value == "REQUIRED":
                errors.append("{0} is not configured".format(name))
                continue
            try:
                float(value)
            except ValueError:
                errors.append("{0} must be numeric".format(name))
        io_hook = os.environ.get("TIMING_IO_MODE_HOOK", "").strip()
        if not io_hook or io_hook == "REQUIRED":
            errors.append("TIMING_IO_MODE_HOOK is required for qualified I/O")
        elif not os.path.isfile(io_hook) or not os.access(io_hook, os.R_OK):
            errors.append("TIMING_IO_MODE_HOOK is not readable: {0}".format(io_hook))
    elif io_mode == "NO" and args.allow_internal_qor:
        pass
    elif io_mode == "NO":
        errors.append("I/O timing is not qualified for production implementation")
    else:
        errors.append("IO_TIMING_QUALIFIED must be YES or NO")

    tools = {}
    for name in TOOL_VARIABLES:
        value = os.environ.get(name, "").strip()
        tools[name] = value
        tool_required = (
            name in SYNTHESIS_TOOL_VARIABLES
            if args.allow_internal_qor
            else True
        )
        if tool_required and not args.dev and (
            not value or command_path(value) is None
        ):
            errors.append("{0} is not executable".format(name))

    checked_files = {}
    required_files = (
        SYNTHESIS_FILE_VARIABLES if args.allow_internal_qor else FILE_LIST_VARIABLES
    )
    for name in FILE_LIST_VARIABLES:
        value = os.environ.get(name, "").strip()
        paths = split_value(value) if value and value != "REQUIRED" else []
        checked_files[name] = paths
        if not paths:
            if name in required_files:
                errors.append("{0} is not configured".format(name))
            continue
        if name not in required_files:
            continue
        for path in paths:
            if any(token in path for token in ("*", "?", "[")):
                errors.append("{0} contains a wildcard: {1}".format(name, path))
            elif not os.path.isfile(path) or not os.access(path, os.R_OK):
                errors.append("{0} is not readable: {1}".format(name, path))

    for prefix in ("STD", "IO", "SRAM"):
        for pvt in ("MAX", "WCL", "TYP", "MIN", "ML"):
            if args.allow_internal_qor and pvt != "TYP":
                continue
            db_name = "{0}_DB_{1}".format(prefix, pvt)
            lib_name = "{0}_LIB_{1}".format(prefix, pvt)
            db_paths = checked_files.get(db_name, ())
            lib_paths = checked_files.get(lib_name, ())
            if not args.allow_internal_qor:
                db_stems = sorted(
                    normalized_library_stem(path) for path in db_paths
                )
                lib_stems = sorted(
                    normalized_library_stem(path) for path in lib_paths
                )
                if db_stems != lib_stems:
                    errors.append(
                        "{0} and {1} do not describe the same libraries".format(
                            db_name, lib_name
                        )
                    )
            if prefix == "STD":
                expected = H7C_PVT_TOKENS[pvt]
                views = [(db_name, db_paths)]
                if not args.allow_internal_qor:
                    views.append((lib_name, lib_paths))
                for name, paths in views:
                    if h7c_variants(paths) != {"H7CH", "H7CL", "H7CR"}:
                        errors.append(
                            "{0} must contain H7CH, H7CL, and H7CR".format(name)
                        )
                    for path in paths:
                        stem = normalized_library_stem(path)
                        if not stem.startswith("ics55_LLSC_H7C"):
                            errors.append(
                                "{0} is not an LLSC H7C library: {1}".format(
                                    name, os.path.basename(path)
                                )
                            )
                        if expected not in stem:
                            errors.append(
                                "{0} has the wrong PVT mapping: {1}".format(
                                    name, os.path.basename(path)
                                )
                            )
    pll_db = checked_files.get("PLL_DB", ())
    pll_lib = checked_files.get("PLL_LIB", ())
    if not args.allow_internal_qor and pll_db and pll_lib:
        db_stem = normalized_library_stem(pll_db[0])
        lib_stem = normalized_library_stem(pll_lib[0])
        if db_stem != lib_stem:
            errors.append("PLL_DB and PLL_LIB do not describe the same library")

    synthesis_targets = checked_files.get("SYN_STD_DB_TYP", ())
    typical_std = checked_files.get("STD_DB_TYP", ())
    if h7c_variants(synthesis_targets) != {"H7CL", "H7CR"}:
        errors.append("SYN_STD_DB_TYP must contain only H7CL and H7CR")
    if len(synthesis_targets) != 2:
        errors.append("SYN_STD_DB_TYP must contain exactly two libraries")
    if not set(synthesis_targets).issubset(set(typical_std)):
        errors.append("SYN_STD_DB_TYP must be a subset of STD_DB_TYP")

    if not args.allow_internal_qor:
        for name in ("STD_LEFS", "STD_GDS", "STD_CDL"):
            paths = checked_files.get(name, ())
            if h7c_variants(paths) != {"H7CH", "H7CL", "H7CR"}:
                errors.append(
                    "{0} must contain H7CH, H7CL, and H7CR".format(name)
                )
            for path in paths:
                if "ics55_LLSC_H7C" not in os.path.basename(path):
                    errors.append(
                        "{0} is not from the LLSC H7C family: {1}".format(
                            name, os.path.basename(path)
                        )
                    )

    condition_library = values.get("SYN_OPERATING_CONDITION_LIBRARY", "")
    target_stems = [normalized_library_stem(path) for path in synthesis_targets]
    if condition_library not in target_stems or "H7CR" not in condition_library:
        errors.append(
            "SYN_OPERATING_CONDITION_LIBRARY must name the H7CR TYP target library"
        )

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
        "io_timing_qualified": io_mode == "YES",
        "implementation_qualified": not errors and io_mode == "YES",
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
