#!/usr/bin/env python3

from __future__ import annotations

import argparse
import shutil
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Remove retroSoC generated output")
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--path", type=Path, action="append", required=True)
    return parser.parse_args()


def remove(root: Path, requested: Path) -> None:
    requested = requested.absolute()
    requested.parent.resolve().relative_to(root)
    if requested.is_symlink():
        requested.unlink()
        print(f"cleaned {requested}")
        return
    target = requested.resolve()
    target.relative_to(root)
    if target == root:
        raise ValueError("refusing to remove the repository root")
    if target.is_dir() and not target.is_symlink():
        shutil.rmtree(target)
    elif target.exists() or target.is_symlink():
        target.unlink()
    print(f"cleaned {target}")


def main() -> int:
    args = parse_args()
    root = args.root.resolve()
    if not (root / "Makefile").is_file() or not (root / ".git").exists():
        raise SystemExit(f"not a retroSoC repository root: {root}")
    try:
        for requested in args.path:
            remove(root, requested)
    except ValueError as error:
        raise SystemExit(f"refusing unsafe clean path: {error}") from error
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
