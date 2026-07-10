#!/usr/bin/env python3

import argparse
import shutil
import sys
from pathlib import Path
from zipfile import ZipFile


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from scripts.setup_helpers import atomic_write, download_file, ensure_git_repo  # noqa: E402


APP_DIR = Path(__file__).resolve().parent
FATFS_DIR = APP_DIR / "fatfs"
FATFS_ARCHIVE = FATFS_DIR / "ff16/ff16.zip"
FATFS_URL = "https://elm-chan.org/fsw/ff/arc/ff16.zip"
FATFS_SHA256 = "41d98115f72b090c2d0c269a001c5c0216efd78fbd84bb6427be808a76315a5a"
COREMARK_DIR = APP_DIR / "coremark/coremark-main"
COREMARK_REVISION = "1f483d5b8316753a742cbf5590caf5bd0a4e4777"


def patch_coremark() -> None:
    header = COREMARK_DIR / "coremark.h"
    content = header.read_text(encoding="utf-8")
    include = "#include <tinyprintf.h>"
    if include not in content:
        marker = '#include "core_portme.h"'
        if marker not in content:
            raise RuntimeError(f"CoreMark patch marker missing in {header}")
        content = content.replace(marker, f"{marker}\n{include}", 1)
        atomic_write(header, content)

    source = COREMARK_DIR / "core_main.c"
    content = source.read_text(encoding="utf-8")
    if "core_main(" not in content:
        if "main(" not in content:
            raise RuntimeError(f"CoreMark entry point not found in {source}")
        content = content.replace("/* Function: main", "/* Function: core_main", 1)
        content = content.replace("\nmain(", "\ncore_main(")
        atomic_write(source, content)


def main() -> int:
    parser = argparse.ArgumentParser(description="Install pinned application dependencies")
    parser.add_argument("--update", action="store_true")
    args = parser.parse_args()

    download_file(
        FATFS_URL,
        FATFS_ARCHIVE,
        FATFS_SHA256,
        update=args.update,
    )
    fatfs_source = FATFS_ARCHIVE.parent / "source"
    if not fatfs_source.is_dir():
        with ZipFile(FATFS_ARCHIVE) as archive:
            archive.extractall(FATFS_ARCHIVE.parent)
    for name in ("ffconf.h", "diskio.c"):
        source = FATFS_DIR / name
        if not source.is_file():
            raise FileNotFoundError(f"FatFs configuration file missing: {source}")
        shutil.copy2(source, fatfs_source / name)

    ensure_git_repo(
        "https://github.com/eembc/coremark.git",
        COREMARK_DIR,
        COREMARK_REVISION,
        update=args.update,
        allow_dirty=True,
    )
    patch_coremark()
    print("application dependencies are ready")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
