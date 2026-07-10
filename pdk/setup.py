#!/usr/bin/env python3

import argparse
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from scripts.dependency_lock import source  # noqa: E402
from scripts.setup_helpers import ensure_git_repo  # noqa: E402


def main() -> int:
    parser = argparse.ArgumentParser(description="Install pinned open PDKs")
    parser.add_argument("--update", action="store_true")
    parser.add_argument("--pdk", choices=("IHP130", "ICS55"), action="append")
    args = parser.parse_args()
    selected = args.pdk or ("IHP130", "ICS55")
    names = {"IHP130": "pdk_ihp130", "ICS55": "pdk_ics55"}
    for name in (names[pdk] for pdk in selected):
        dependency = source(name)
        ensure_git_repo(
            dependency["url"],
            ROOT / dependency["destination"],
            dependency["revision"],
            recursive=dependency.get("recursive", False),
            update=args.update,
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
