#!/usr/bin/env python3
# Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
# retroSoC is licensed under Mulan PSL v2.
# You can use this software according to the terms and conditions of the Mulan PSL v2.
# You may obtain a copy of Mulan PSL v2 at:
#             http://license.coscl.org.cn/MulanPSL2
# THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
# EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
# MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
# See the Mulan PSL v2 for more details.

from __future__ import annotations

import argparse
import re
import subprocess
from pathlib import Path


FORBIDDEN_SUFFIXES = {
    ".db",
    ".ddc",
    ".def",
    ".gds",
    ".gdsii",
    ".lib",
    ".lef",
    ".nxtgrd",
    ".spef",
    ".sdf",
    ".spf",
    ".svdb",
}
ABSOLUTE_SITE_PATH = re.compile(
    r"(?<![A-Za-z0-9_])/(?:data|eda|home|mnt|nfs|opt|proj|project|site|tools)(?:/|$)",
    re.IGNORECASE,
)


def candidate_files(root: Path) -> list[Path]:
    output = subprocess.check_output(
        [
            "git",
            "ls-files",
            "--cached",
            "--others",
            "--exclude-standard",
            "physical/commercial",
        ],
        cwd=root,
        text=True,
    )
    return [root / line for line in output.splitlines() if line]


def violations(root: Path, files: list[Path]) -> list[str]:
    errors: list[str] = []
    for path in files:
        relative = path.relative_to(root)
        if relative.parts[:3] == ("physical", "commercial", "local") and path.name != ".gitignore":
            errors.append(f"{relative}: local configuration must not be tracked")
        if path.suffix.lower() in FORBIDDEN_SUFFIXES:
            errors.append(f"{relative}: commercial/generated suffix is forbidden")
        if not path.is_file() or path.name == ".gitignore":
            continue
        text = path.read_text(encoding="utf-8", errors="replace")
        if ABSOLUTE_SITE_PATH.search(text):
            errors.append(f"{relative}: contains a site-specific absolute path")
    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, required=True)
    args = parser.parse_args()
    root = args.root.resolve()
    errors = violations(root, candidate_files(root))
    if errors:
        for error in errors:
            print(f"ERROR: {error}")
        return 1
    print("commercial boundary audit passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
