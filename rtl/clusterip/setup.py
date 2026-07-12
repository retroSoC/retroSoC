#!/usr/bin/env python3

import argparse
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from scripts.dependency_lock import load_lock  # noqa: E402
from scripts.setup_helpers import ensure_git_repo  # noqa: E402


def main() -> int:
    parser = argparse.ArgumentParser(description="Install pinned cluster IP repositories")
    parser.add_argument("--update", action="store_true")
    args = parser.parse_args()
    dependencies = load_lock()["sources"]
    for name in sorted(item for item in dependencies if item.startswith("cluster_")):
        dependency = dependencies[name]
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
