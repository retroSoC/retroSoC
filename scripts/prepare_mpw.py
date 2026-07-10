#!/usr/bin/env python3

from __future__ import annotations

import argparse
import hashlib
import shutil
import sys
import tarfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from scripts.setup_helpers import download_file, ensure_git_repo  # noqa: E402


MPW_DIR = ROOT / "rtl/mini/mpw"
HAZARD3_REVISION = "5b3a34f6955e50e03bdcb964201c91462f7078c3"
IBEX_REVISION = "0c233f54361d769f370889223acc456f2ac19d46"
SERV_ARCHIVE = MPW_DIR / "serv-1.4.0.tar.gz"
SERV_URL = "https://github.com/olofk/serv/archive/refs/tags/1.4.0.tar.gz"
SERV_SHA256 = "f81c37b9f9d548c658e23bb7eb90fbed8b54e2e9e51fa42b8cd2f34cecc472ab"


def tree_digest(root: Path) -> str:
    digest = hashlib.sha256()
    for path in sorted(item for item in root.rglob("*") if item.is_file()):
        digest.update(path.relative_to(root).as_posix().encode("utf-8"))
        with path.open("rb") as stream:
            for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                digest.update(chunk)
    return digest.hexdigest()


def sync_tree(source: Path, destination: Path) -> None:
    if destination.is_dir() and tree_digest(source) == tree_digest(destination):
        print(f"[dependency] source tree unchanged: {destination}")
        return
    if destination.exists():
        shutil.rmtree(destination)
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copytree(source, destination)


def extract_serv() -> Path:
    extracted = MPW_DIR / "serv-1.4.0"
    if extracted.is_dir():
        return extracted
    with tarfile.open(SERV_ARCHIVE, "r:gz") as archive:
        for member in archive.getmembers():
            (MPW_DIR / member.name).resolve().relative_to(MPW_DIR.resolve())
        archive.extractall(MPW_DIR)
    if not extracted.is_dir():
        raise RuntimeError(f"SERV archive did not create {extracted}")
    return extracted


def main() -> int:
    parser = argparse.ArgumentParser(description="Prepare pinned MPW core sources")
    parser.add_argument("--update", action="store_true")
    args = parser.parse_args()
    if not (MPW_DIR / ".git").is_dir():
        raise SystemExit("MPW generator is missing; run 'python3 setup.py' first")

    ensure_git_repo(
        "https://github.com/Wren6991/Hazard3.git",
        MPW_DIR / "Hazard3",
        HAZARD3_REVISION,
        update=args.update,
    )
    ensure_git_repo(
        "https://github.com/lowRISC/ibex.git",
        MPW_DIR / "ibex",
        IBEX_REVISION,
        update=args.update,
    )
    download_file(
        SERV_URL,
        SERV_ARCHIVE,
        SERV_SHA256,
        update=args.update,
    )
    serv = extract_serv()

    sync_tree(MPW_DIR / "Hazard3/hdl", MPW_DIR / "core/username3/Hazard3")
    sync_tree(serv / "rtl", MPW_DIR / "core/username4/serv")
    sync_tree(MPW_DIR / "ibex/rtl", MPW_DIR / "core/username7/ibex")
    (MPW_DIR / ".build").mkdir(exist_ok=True)
    print("pinned MPW core sources are ready")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
