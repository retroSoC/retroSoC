#!/usr/bin/env python3

import argparse
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from scripts.setup_helpers import atomic_write  # noqa: E402


def git_value(root: Path, *args: str, fallback: str = "unknown") -> str:
    try:
        return subprocess.check_output(
            ["git", "-C", str(root), *args],
            text=True,
            stderr=subprocess.DEVNULL,
        ).strip()
    except (subprocess.CalledProcessError, FileNotFoundError):
        return fallback


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate the firmware version header")
    parser.add_argument("--root", type=Path, default=ROOT)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    root = args.root.resolve()
    output = args.output or root / "crt/inc/socver.h"

    branch = git_value(root, "rev-parse", "--abbrev-ref", "HEAD")
    commit = git_value(root, "rev-parse", "--short=6", "HEAD")
    template = (root / "crt/ver.tmpl").read_text(encoding="utf-8")
    content = template.replace("SOC_DEFAULT_BRANCH", branch).replace(
        "SOC_DEFAULT_COMMIT", commit
    )
    changed = atomic_write(output, content)
    print(f"version {branch}@{commit}: {'updated' if changed else 'unchanged'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
