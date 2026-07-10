#!/usr/bin/env python3

import argparse
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from scripts.setup_helpers import ensure_git_repo  # noqa: E402


REVISION = "d991ec9f7bf696e7e5d840758487068b11bd4121"


def main() -> int:
    parser = argparse.ArgumentParser(description="Install pinned third-party IP")
    parser.add_argument("--update", action="store_true")
    args = parser.parse_args()
    ensure_git_repo(
        "https://github.com/retroSoC/3rd-party.git",
        Path(__file__).resolve().parent / "3rd-party",
        REVISION,
        update=args.update,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
