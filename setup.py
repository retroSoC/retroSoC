#!/usr/bin/env python3

import argparse
from pathlib import Path

from scripts.setup_helpers import ensure_git_repo


ROOT = Path(__file__).resolve().parent
MPW_REVISION = "30503eb8a7cf33a0c955913faba5014ebd00186f"


def main() -> int:
    parser = argparse.ArgumentParser(description="Install the pinned MPW generator")
    parser.add_argument("--update", action="store_true")
    args = parser.parse_args()
    ensure_git_repo(
        "https://github.com/retroSoC/mini-ver-mpw.git",
        ROOT / "rtl/mini/mpw",
        MPW_REVISION,
        update=args.update,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
