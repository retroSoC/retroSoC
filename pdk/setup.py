#!/usr/bin/env python3

import argparse
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from scripts.setup_helpers import ensure_git_repo  # noqa: E402


DEPENDENCIES = (
    (
        "https://github.com/IHP-GmbH/IHP-Open-PDK.git",
        "IHP-Open-PDK",
        "68eebafcd9b2f5e92c69d37a8d3d90eb266550f5",
    ),
    (
        "https://github.com/openecos-projects/icsprout55-pdk.git",
        "icsprout55-pdk",
        "e696e093129ca2212487aa169af74d06ebd86eb6",
    ),
)


def main() -> int:
    parser = argparse.ArgumentParser(description="Install pinned open PDKs")
    parser.add_argument("--update", action="store_true")
    args = parser.parse_args()
    pdk_dir = Path(__file__).resolve().parent
    for url, name, revision in DEPENDENCIES:
        ensure_git_repo(
            url,
            pdk_dir / name,
            revision,
            recursive=True,
            update=args.update,
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
