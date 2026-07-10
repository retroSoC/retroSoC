#!/usr/bin/env python3

from __future__ import annotations

import argparse
import os
import posixpath
import shutil
import sys
import tarfile
import tempfile
from pathlib import Path, PurePosixPath

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from scripts.dependency_lock import DEFAULT_LOCK, load_lock  # noqa: E402
from scripts.setup_helpers import atomic_write, download_file  # noqa: E402


def safe_extract(archive: Path, destination: Path) -> None:
    with tarfile.open(archive, "r:*") as bundle:
        for member in bundle.getmembers():
            member_path = PurePosixPath(member.name)
            if member_path.is_absolute() or ".." in member_path.parts:
                raise ValueError(f"unsafe archive member path: {member.name}")
            if member.ischr() or member.isblk() or member.isfifo():
                raise ValueError(f"unsupported archive member type: {member.name}")
            if member.issym() or member.islnk():
                link = PurePosixPath(member.linkname)
                combined = member_path.parent / link if member.issym() else link
                normalized = PurePosixPath(posixpath.normpath(str(combined)))
                escapes_root = normalized.parts[:1] == ("..",)
                if link.is_absolute() or normalized.is_absolute() or escapes_root:
                    raise ValueError(
                        f"unsafe archive link: {member.name} -> {member.linkname}"
                    )
        bundle.extractall(destination)


def install(name: str, spec: dict[str, str], cache: Path, update: bool) -> Path:
    downloads = cache / "downloads"
    archive = downloads / spec["archive"]
    download_file(spec["url"], archive, spec["sha256"], update=update, timeout=120)

    destination = cache / "toolchains" / f"{name}-{spec['version']}"
    marker = destination / ".complete"
    if marker.is_file() and marker.read_text(encoding="utf-8").strip() == spec["sha256"]:
        return destination / spec["path"]

    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=f".{destination.name}.", dir=destination.parent) as temp:
        extracted = Path(temp) / "content"
        extracted.mkdir()
        safe_extract(archive, extracted)
        atomic_write(extracted / ".complete", spec["sha256"] + "\n")
        if destination.exists():
            shutil.rmtree(destination)
        os.replace(extracted, destination)
    return destination / spec["path"]


def main() -> int:
    parser = argparse.ArgumentParser(description="Install pinned retroSoC toolchains")
    parser.add_argument("--lock", type=Path, default=DEFAULT_LOCK)
    parser.add_argument("--platform", default="ubuntu-22.04")
    parser.add_argument("--cache", type=Path, required=True)
    parser.add_argument("--tool", action="append", required=True)
    parser.add_argument("--github-path", type=Path)
    parser.add_argument("--update", action="store_true")
    args = parser.parse_args()

    lock = load_lock(args.lock)
    try:
        available = lock["toolchains"][args.platform]
    except KeyError as error:
        raise SystemExit(f"unsupported toolchain platform: {args.platform}") from error
    paths: list[Path] = []
    for name in args.tool:
        if name not in available:
            raise SystemExit(f"toolchain is not locked for {args.platform}: {name}")
        path = install(name, available[name], args.cache.resolve(), args.update)
        paths.append(path)
        print(f"{name}: {path}")
    if args.github_path:
        args.github_path.parent.mkdir(parents=True, exist_ok=True)
        with args.github_path.open("a", encoding="utf-8") as stream:
            for path in paths:
                stream.write(str(path.resolve()) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
