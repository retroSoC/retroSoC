#!/usr/bin/env python3
"""Focused SPI-P2 DMA V2.2 evidence driver; product integration stays disabled."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from scripts.setup_helpers import atomic_write  # noqa: E402

SOURCES = [ROOT / "rtl/ip/serial/spi_dma_pacing.sv",
           ROOT / "rtl/ip/peripheral/dma_define.svh", ROOT / "rtl/ip/peripheral/dma_pkg.sv",
           ROOT / "rtl/ip/peripheral/dma_core.sv", ROOT / "rtl/ip/peripheral/dma_reg.sv",
           ROOT / "rtl/ip/peripheral/apb4_dma.sv", ROOT / "tests/rtl/spi_dma_pacing_tb.sv",
           ROOT / "tests/test_spi_p2.py", ROOT / "scripts/spi_p2.py",
           ROOT / "crt/include/retrosoc/hal/dma.h",
           ROOT / "crt/include/retrosoc/hal/dma_regs.h",
           ROOT / "crt/src/hal/dma.c", ROOT / "crt/src/hal/dma_math.c",
           ROOT / "rtl/mini/formal/dma_formal.sv",
           ROOT / "rtl/mini/formal/dma_formal_props.sv",
           ROOT / "rtl/mini/formal/dma_tcd_cancel_props.sv"]
PACING_TB = ROOT / "tests/rtl/spi_dma_pacing_tb.sv"

def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()

def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("stage", choices=("lint", "rtl", "report"))
    parser.add_argument("--variant-root", type=Path, required=True)
    parser.add_argument("--pdk", choices=("ICS55", "IHP130"), required=True)
    args = parser.parse_args()
    variant = args.variant_root.resolve()
    variant.relative_to(ROOT / "build")
    manifest = json.loads((variant / "meta/manifest.json").read_text())
    if manifest["configuration"]["SOC"] != "TINY" or manifest["configuration"]["PDK"] != args.pdk:
        raise ValueError("profile/PDK mismatch")
    directory = variant / "meta/spi-p2" / args.stage
    if directory.exists():
        raise ValueError(f"existing SPI-P2 attempt: {directory}")
    directory.mkdir(parents=True)
    source = {str(path.relative_to(ROOT)): digest(path) for path in SOURCES}
    record = {"phase": "SPI-P2", "stage": args.stage, "status": "running",
              "source": source, "manifest": manifest, "phase_accepted": False}
    try:
        common = ROOT / "rtl/managed/clusterip/common/rtl"
        if args.stage == "rtl":
            command = ["iverilog", "-g2012", "-s", "spi_dma_pacing_tb", "-o",
                       str(directory / "spi_dma_pacing_tb"), f"-I{common}", f"-I{common / 'utils'}",
                       str(common / "utils/register.sv"), str(SOURCES[0]), str(PACING_TB)]
            result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, check=False)
            (directory / "compile.log").write_text(result.stdout + result.stderr)
            if result.returncode != 0:
                raise RuntimeError("SPI-P2 pacing compile failed")
            run = subprocess.run(["vvp", str(directory / "spi_dma_pacing_tb")], cwd=ROOT,
                                 capture_output=True, text=True, check=False)
            (directory / "sim.log").write_text(run.stdout + run.stderr)
            if run.returncode != 0 or "SPI_P2_PASS spi_dma_pacing_tb" not in run.stdout:
                raise RuntimeError("SPI-P2 pacing fixture failed")
        elif args.stage == "lint":
            result = subprocess.run(["verilator", "--lint-only", "--Wall", "-Wno-fatal",
                                     "-Wno-DECLFILENAME", "--top-module",
                                     "spi_dma_pacing", f"-I{common}", str(common / "utils/register.sv"),
                                     str(SOURCES[0])], cwd=ROOT,
                                    capture_output=True, text=True, check=False)
            (directory / "lint.log").write_text(result.stdout + result.stderr)
            if result.returncode != 0:
                raise RuntimeError("SPI-P2 pacing lint failed")
        record["status"] = "passed"
    except (OSError, RuntimeError) as error:
        record.update(status="failed", error=str(error))
        print(error, file=sys.stderr)
        return 1
    record["artifacts"] = {str(path): digest(path) for path in directory.rglob("*") if path.is_file()}
    atomic_write(directory / "record.json", json.dumps(record, indent=2, sort_keys=True) + "\n")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
