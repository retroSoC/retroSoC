#!/usr/bin/env python3

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
PDK_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT))
from scripts.dependency_lock import archive, source  # noqa: E402
from scripts.setup_helpers import download_file, ensure_git_repo, sha256  # noqa: E402


PLL_VIEWS = (
    "README.md", "verilog/PLL_TOP.behavioral.v", "verilog/PLL_TOP.blackbox.v",
    "lef/PLL_TOP.lef", "lib/PLL_TOP_min.lib", "lib/PLL_TOP_typ.lib", "lib/PLL_TOP_max.lib",
)


def setup_ics55_pll(*, update: bool = False) -> dict:
    """Restore the locked integration views without selecting them in any RTL flow."""
    dependency = source("pdk_ics55_pll")
    destination = ROOT / dependency["destination"]
    ensure_git_repo(dependency["url"], destination, dependency["revision"], update=update)
    hashes = {}
    for name in PLL_VIEWS:
        path = destination / name
        if not path.is_file() or path.stat().st_size == 0:
            raise ValueError(f"ICS55 PLL view is missing or empty: {path}")
        content = path.read_text(encoding="utf-8")
        pattern = None
        if path.suffix == ".v":
            pattern = r"\bmodule\s+PLL_TOP\s*\("
        elif path.suffix == ".lib":
            pattern = r'\bcell\s*\(\s*"?PLL_TOP"?\s*\)'
        elif path.suffix == ".lef":
            pattern = r"\bMACRO\s+PLL_TOP\b"
        if pattern is not None and re.search(pattern, content) is None:
            raise ValueError(f"ICS55 PLL view does not define PLL_TOP: {path}")
        hashes[name] = sha256(path)
    record = {"source": "pdk_ics55_pll", "revision": dependency["revision"],
              "destination": str(destination), "sha256": hashes,
              "qualification": "integration views only; no characterized PLL timing arcs"}
    print(json.dumps(record, sort_keys=True))
    return record


def main() -> int:
    parser = argparse.ArgumentParser(description="Install pinned open PDKs")
    parser.add_argument("--update", action="store_true")
    parser.add_argument("--pdk", choices=("IHP130", "ICS55", "GF180", "SKY130"), action="append")
    parser.add_argument("--component", choices=("all", "pll"), default="all",
                        help="pll restores only the ICS55 PLL integration views")
    args = parser.parse_args()
    if args.component == "pll":
        if args.pdk != ["ICS55"]:
            parser.error("--component pll requires exactly --pdk ICS55")
        setup_ics55_pll(update=args.update)
        return 0
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
                    str(PDK_DIR / "generate_gf180_liberty.py"),
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
                    str(PDK_DIR / "generate_gf180_liberty.py"),
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
                    str(PDK_DIR / "generate_gf180_liberty.py"),
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
                    str(PDK_DIR / "generate_sky130_liberty.py"),
                    "--source",
                    str(destination),
                    "--output-dir",
                    str(ROOT / ".cache/retrosoc/pdk/sky130"),
                    "--revision",
                    dependency["revision"],
                ),
                check=True,
            )
            sram = archive("sky130_openram_sram_4kbyte_1rw_32x1024_8")
            sram_archive = ROOT / sram["destination"]
            download_file(
                sram["url"],
                sram_archive,
                sram["sha256"],
                update=args.update,
                timeout=120,
            )
            subprocess.run(
                (
                    sys.executable,
                    str(PDK_DIR / "prepare_sky130_sram.py"),
                    "--archive",
                    str(sram_archive),
                    "--output-dir",
                    str(ROOT / ".cache/retrosoc/pdk/sky130/openram"),
                    "--archive-sha256",
                    sram["sha256"],
                ),
                check=True,
            )
            subprocess.run(
                (
                    sys.executable,
                    str(PDK_DIR / "generate_sky130_liberty.py"),
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
                    str(PDK_DIR / "prepare_ics55_liberty.py"),
                    "--archive",
                    str(archive_path),
                    "--output-dir",
                    str(ROOT / ".cache/retrosoc/pdk/ics55"),
                    "--revision",
                    dependency["revision"],
                ),
                check=True,
            )
            for sram_name, directory_name in (
                ("pdk_ics55_sram_1024x32_m8", "ics55_ecos_sram_1024x32_m8"),
                ("pdk_ics55_sram_4096x32_m8", "ics55_ecos_sram_4096x32_m8"),
            ):
                sram = archive(sram_name)
                sram_archive = ROOT / sram["destination"]
                download_file(
                    sram["url"],
                    sram_archive,
                    sram["sha256"],
                    update=args.update,
                    timeout=120,
                )
                subprocess.run(
                    (
                        sys.executable,
                        str(PDK_DIR / "prepare_ics55_sram.py"),
                        "--archive",
                        str(sram_archive),
                        "--output-dir",
                        str(ROOT / ".cache/retrosoc/pdk/ics55/sram" / directory_name),
                        "--archive-sha256",
                        sram["sha256"],
                    ),
                    check=True,
                )
            subprocess.run(
                (
                    sys.executable,
                    str(PDK_DIR / "prepare_ics55_sim_model.py"),
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
            setup_ics55_pll(update=args.update)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
