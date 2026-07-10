#!/usr/bin/env python3

import argparse
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from scripts.setup_helpers import ensure_git_repo  # noqa: E402


REVISIONS = {
    "archinfo": "d65dd13c83a1176668bf5178004814a1551bf6ba",
    "clint": "ce49f1a5501c0a9f18c0e3f358417648f3f2fb18",
    "common": "d9921eb05160be873aebc46bb2f820bee2c7eebc",
    "crc": "4654a63d06d487b5b9fe22af228c36c736b90bad",
    "i2c": "73b024547c5cd70fb8bf801cc7757db2536c604f",
    "i2s": "bd0978e8b45e4cf4c1335a1fa7311385d2a4e805",
    "plic": "c851d93829d2e75b224003a058e718925855c0cc",
    "ps2": "60921e0f72d6113f8615d03ce54567388fc2410f",
    "pwm": "0777ef085c661d2b103f2fa0f8519f97eea3c950",
    "rng": "7374e1e7f25bfd1ff9954ea99f19b77a583def29",
    "rtc": "69963b8424cb00e04c8be70157b8ca738464e342",
    "spi": "515cb408806584525605b4747db5e890dbdf1928",
    "timer": "0c44b0d8b742c6a477fda15a812cf22962b54dd8",
    "uart": "eca12213ba06f42e0a6dd0f27907fd4c447e2774",
    "wdg": "b2603c1faeba96603392f0fe9e692e645d7e061f",
}


def main() -> int:
    parser = argparse.ArgumentParser(description="Install pinned cluster IP repositories")
    parser.add_argument("--update", action="store_true")
    args = parser.parse_args()
    destination = Path(__file__).resolve().parent
    for name, revision in REVISIONS.items():
        ensure_git_repo(
            f"https://github.com/retroSoC/{name}.git",
            destination / name,
            revision,
            update=args.update,
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
