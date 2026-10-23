#!/usr/bin/env python3
"""Source-bound focused SPI-P3 Tiny integration checks."""
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


def configuration_digest(manifest: dict) -> str:
    payload = json.dumps(manifest["configuration"], sort_keys=True).encode("utf-8")
    return hashlib.sha256(payload).hexdigest()


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
    output = variant / "meta/spi-p3" / args.stage
    output.mkdir(parents=True, exist_ok=False)
    command = [sys.executable, "-m", "pytest", "-q", "tests/test_spi_p3.py",
               "tests/test_spi_p2.py", "tests/test_spi_register_parity.py"]
    result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, check=False)
    atomic_write(output / "pytest.log", result.stdout + result.stderr)
    record = {"phase": "SPI-P3", "stage": args.stage,
              "status": "passed" if result.returncode == 0 else "failed",
              "command": command, "configuration_digest": configuration_digest(manifest),
              "phase_accepted": False}
    atomic_write(output / "record.json", json.dumps(record, indent=2, sort_keys=True) + "\n")
    if result.returncode != 0:
        print(result.stdout + result.stderr, file=sys.stderr)
    return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())
