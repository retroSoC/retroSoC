#!/usr/bin/env python3
"""Install the locked VexiiRiscv source used by Mini product profiles."""

from __future__ import annotations

import argparse
import subprocess
from pathlib import Path

from dependency_lock import source
from setup_helpers import ensure_git_repo, run


ROOT = Path(__file__).resolve().parents[1]


def repair_incomplete_checkout(destination: Path, url: str, revision: str) -> None:
    if not (destination / ".git").is_dir():
        return
    result = subprocess.run(
        ["git", "-C", str(destination), "rev-parse", "--verify", "HEAD"],
        check=False,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    if result.returncode == 0:
        return
    run(("git", "remote", "set-url", "origin", url), cwd=destination)
    run(("git", "fetch", "--depth", "1", "origin", revision), cwd=destination)
    run(("git", "checkout", "--detach", "FETCH_HEAD"), cwd=destination)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--update", action="store_true")
    args = parser.parse_args()
    dependency = source("vexiiriscv")
    destination = ROOT / dependency["destination"]
    repair_incomplete_checkout(destination, dependency["url"], dependency["revision"])
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
