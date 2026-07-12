#!/usr/bin/env python3

import argparse
import shutil
import sys
from pathlib import Path
from zipfile import ZipFile


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from scripts.dependency_lock import archive, source  # noqa: E402
from scripts.setup_helpers import atomic_write, download_file, ensure_git_repo  # noqa: E402


APP_DIR = Path(__file__).resolve().parent
FATFS_DIR = APP_DIR / "middleware/fatfs"
COREMARK_DIR = APP_DIR / "coremark/coremark-main"


def extract_fatfs(archive: Path, destination: Path, *, update: bool) -> None:
    if update and destination.is_dir():
        shutil.rmtree(destination)
    if not destination.is_dir():
        with ZipFile(archive) as zip_archive:
            zip_archive.extractall(archive.parent)


def patch_fatfs(source: Path) -> None:
    fatfs_source = source / "ff.c"
    content = fatfs_source.read_text(encoding="utf-8")
    original_content = content
    include = "#include <retrosoc/lib/string.h>"
    if include not in content:
        for legacy_include in ("#include <string.h>", "#include <tinystring.h>", "#include <rs_string.h>"):
            if legacy_include in content:
                content = content.replace(legacy_include, include)
                break
        else:
            raise RuntimeError(f"FatFs string include missing in {fatfs_source}")
    if content != original_content:
        atomic_write(fatfs_source, content)


def patch_coremark() -> None:
    header = COREMARK_DIR / "coremark.h"
    content = header.read_text(encoding="utf-8")
    original_content = content
    include = "#include <retrosoc/lib/printf.h>"
    for legacy_include in ("#include <tinyprintf.h>", "#include <rs_printf.h>"):
        if legacy_include in content:
            content = content.replace(legacy_include, include)
    if include not in content:
        marker = '#include "core_portme.h"'
        if marker not in content:
            raise RuntimeError(f"CoreMark patch marker missing in {header}")
        content = content.replace(marker, f"{marker}\n{include}", 1)
    if content != original_content:
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

    fatfs = archive("fatfs")
    fatfs_archive = ROOT / fatfs["destination"]
    download_file(fatfs["url"], fatfs_archive, fatfs["sha256"], update=args.update)
    fatfs_source = fatfs_archive.parent / "source"
    extract_fatfs(fatfs_archive, fatfs_source, update=args.update)
    patch_fatfs(fatfs_source)
    for name in ("ffconf.h", "diskio.c"):
        config_source = FATFS_DIR / name
        if not config_source.is_file():
            raise FileNotFoundError(f"FatFs configuration file missing: {config_source}")
        shutil.copy2(config_source, fatfs_source / name)

    coremark = source("coremark")
    ensure_git_repo(
        coremark["url"], ROOT / coremark["destination"], coremark["revision"],
        update=args.update,
        allow_dirty=True,
    )
    patch_coremark()
    print("application dependencies are ready")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
