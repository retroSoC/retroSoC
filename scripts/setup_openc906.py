#!/usr/bin/env python3
"""Install the locked OpenC906 source used by Mini product profiles."""

from __future__ import annotations

import argparse
from pathlib import Path

from dependency_lock import source
from setup_helpers import ensure_git_repo


ROOT = Path(__file__).resolve().parents[1]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--update", action="store_true")
    args = parser.parse_args()
    dependency = source("openc906")
    destination = ROOT / dependency["destination"]
    ensure_git_repo(
        dependency["url"],
        destination,
        dependency["revision"],
        recursive=dependency.get("recursive", False),
        update=args.update,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
