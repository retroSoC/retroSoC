#!/usr/bin/env python3

import argparse
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from scripts.dependency_lock import archive, source  # noqa: E402
from scripts.setup_helpers import download_file, ensure_git_repo  # noqa: E402


def main() -> int:
    parser = argparse.ArgumentParser(description="Install pinned open PDKs")
    parser.add_argument("--update", action="store_true")
    parser.add_argument("--pdk", choices=("IHP130", "ICS55", "GF180", "SKY130"), action="append")
    args = parser.parse_args()
    selected = args.pdk or ("IHP130", "ICS55", "GF180", "SKY130")
    names = {
        "IHP130": "pdk_ihp130",
        "ICS55": "pdk_ics55",
        "GF180": "pdk_gf180",
        "SKY130": "pdk_sky130",
    }
    for name in (names[pdk] for pdk in selected):
        dependency = source(name)
        destination = ROOT / dependency["destination"]
        ensure_git_repo(
            dependency["url"],
            destination,
            dependency["revision"],
            recursive=dependency.get("recursive", False),
            submodules=tuple(dependency.get("submodules", ())),
            update=args.update,
        )
        if name == "pdk_gf180":
            subprocess.run(
                (
                    sys.executable,
                    str(ROOT / "pdk/generate_gf180_liberty.py"),
                    "--source",
                    str(destination),
                    "--output-dir",
                    str(ROOT / ".cache/retrosoc/pdk/gf180"),
                    "--revision",
                    dependency["revision"],
                ),
                check=True,
            )
            subprocess.run(
                (
                    sys.executable,
                    str(ROOT / "pdk/generate_gf180_liberty.py"),
                    "--source",
                    str(destination),
                    "--output-dir",
                    str(ROOT / ".cache/retrosoc/pdk/gf180"),
                    "--revision",
                    dependency["revision"],
                    "--corner",
                    "ss_125C_4v50",
                ),
                check=True,
            )
            subprocess.run(
                (
                    sys.executable,
                    str(ROOT / "pdk/generate_gf180_liberty.py"),
                    "--source",
                    str(destination),
                    "--output-dir",
                    str(ROOT / ".cache/retrosoc/pdk/gf180"),
                    "--revision",
                    dependency["revision"],
                    "--library",
                    "gf180mcu_fd_io",
                    "--cell",
                    "bi_t",
                    "--cell",
                    "in_c",
                    "--corner",
                    "ss_125C_4v50",
                    "--output-name",
                    "gf180mcu_fd_io_retrosoc__ss_125C_4v50.lib",
                ),
                check=True,
            )
        elif name == "pdk_sky130":
            subprocess.run(
                (
                    sys.executable,
                    str(ROOT / "pdk/generate_sky130_liberty.py"),
                    "--source",
                    str(destination),
                    "--output-dir",
                    str(ROOT / ".cache/retrosoc/pdk/sky130"),
                    "--revision",
                    dependency["revision"],
                ),
                check=True,
            )
            subprocess.run(
                (
                    sys.executable,
                    str(ROOT / "pdk/generate_sky130_liberty.py"),
                    "--source",
                    str(destination),
                    "--output-dir",
                    str(ROOT / ".cache/retrosoc/pdk/sky130"),
                    "--revision",
                    dependency["revision"],
                    "--corner",
                    "ss_100C_1v40",
                ),
                check=True,
            )
        elif name == "pdk_ics55":
            liberty = archive("pdk_ics55_h7cr_liberty")
            archive_path = ROOT / liberty["destination"]
            download_file(
                liberty["url"],
                archive_path,
                liberty["sha256"],
                update=args.update,
                timeout=120,
            )
            subprocess.run(
                (
                    sys.executable,
                    str(ROOT / "pdk/prepare_ics55_liberty.py"),
                    "--archive",
                    str(archive_path),
                    "--output-dir",
                    str(ROOT / ".cache/retrosoc/pdk/ics55"),
                    "--revision",
                    dependency["revision"],
                ),
                check=True,
            )
            subprocess.run(
                (
                    sys.executable,
                    str(ROOT / "pdk/prepare_ics55_sim_model.py"),
                    "--source",
                    str(
                        destination
                        / "IP/STD_cell/ics55_LLSC_H7C_V1p10C100"
                        / "ics55_LLSC_H7CR/verilog/ics55_LLSC_H7CR.v"
                    ),
                    "--output",
                    str(ROOT / ".cache/retrosoc/pdk/ics55/ics55_h7cr_functional.v"),
                    "--revision",
                    dependency["revision"],
                ),
                check=True,
            )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
