#!/usr/bin/env python3

import argparse
from pathlib import Path

from scripts.dependency_lock import source
from scripts.setup_helpers import ensure_git_repo


ROOT = Path(__file__).resolve().parent


def main() -> int:
    parser = argparse.ArgumentParser(description="Install pinned MPW and management-core sources")
    parser.add_argument("--update", action="store_true")
    args = parser.parse_args()
    for name in ("mpw", "hazard3"):
        dependency = source(name)
        ensure_git_repo(
            dependency["url"], ROOT / dependency["destination"], dependency["revision"],
            recursive=dependency.get("recursive", False), update=args.update,
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
