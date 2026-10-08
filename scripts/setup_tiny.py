#!/usr/bin/env python3
"""Prepare only the locked inputs used by the Tiny MCU."""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from scripts.dependency_lock import source  # noqa: E402
from scripts.setup_helpers import ensure_git_repo  # noqa: E402

TINY_SOURCES = (
    "hazard3", "cluster_common", "cluster_archinfo", "cluster_pwm",
    "cluster_rtc", "cluster_wdg", "pdk_ihp130",
)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--update", action="store_true")
    parser.add_argument("--pdk", choices=("IHP130", "ICS55"), default="ICS55")
    args = parser.parse_args()
    for name in (name for name in TINY_SOURCES if not name.startswith("pdk_")):
        dependency = source(name)
        ensure_git_repo(
            dependency["url"], ROOT / dependency["destination"], dependency["revision"],
            recursive=dependency.get("recursive", False), update=args.update,
        )
    subprocess.run([sys.executable, str(ROOT / "physical/pdk/setup.py"), "--pdk", args.pdk,
                    *(["--update"] if args.update else [])], check=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
