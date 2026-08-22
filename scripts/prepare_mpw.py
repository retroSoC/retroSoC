#!/usr/bin/env python3

from __future__ import annotations

import argparse
import fcntl
import hashlib
import shutil
import sys
import tarfile
from pathlib import Path

try:
    import tomllib
except ModuleNotFoundError:  # Python 3.10
    import tomli as tomllib

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from scripts.dependency_lock import archive  # noqa: E402
from scripts.setup_helpers import atomic_write, download_file  # noqa: E402


MPW_DIR = ROOT / "rtl/managed/mpw"
SERV_ARCHIVE = MPW_DIR / "serv-1.4.0.tar.gz"


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


def patch_serv(source: Path) -> None:
    state = source / "serv_state.v"
    content = state.read_text(encoding="utf-8")
    declaration_marker = "   wire misalign_trap_sync;\n"
    declaration = "   wire trap_pending;\n"
    legacy_definition = "wire trap_pending = WITH_CSR"
    patched_definition = "assign trap_pending = WITH_CSR"

    if declaration in content and patched_definition in content:
        return
    if declaration in content or patched_definition in content:
        raise RuntimeError(f"SERV trap_pending patch is incomplete in {state}")
    if content.count(declaration_marker) != 1 or content.count(legacy_definition) != 1:
        raise RuntimeError(f"SERV trap_pending patch markers missing in {state}")

    content = content.replace(
        declaration_marker,
        declaration_marker + declaration,
        1,
    )
    content = content.replace(legacy_definition, patched_definition, 1)
    atomic_write(state, content)


def manifest_design_dir(identifier: str) -> Path:
    manifest = MPW_DIR / "mpw.toml"
    document = tomllib.loads(manifest.read_text(encoding="utf-8"))
    for design in document.get("design", []):
        if design.get("id") == identifier:
            source_dir = Path(design["source_dir"])
            if source_dir.is_absolute() or ".." in source_dir.parts:
                raise RuntimeError(f"unsafe source directory for MPW design {identifier}")
            return MPW_DIR / source_dir
    raise RuntimeError(f"MPW manifest does not define {identifier}")


def prepare(update: bool) -> None:
    if not (MPW_DIR / ".git").is_dir():
        raise SystemExit("MPW generator is missing; run 'python3 setup.py' first")

    serv_archive = archive("serv")
    download_file(
        serv_archive["url"], ROOT / serv_archive["destination"],
        serv_archive["sha256"], update=update,
    )
    serv = extract_serv()
    patch_serv(serv / "rtl")

    sync_tree(serv / "rtl", manifest_design_dir("serv") / "serv")
    print("pinned MPW core sources are ready")


def main() -> int:
    parser = argparse.ArgumentParser(description="Prepare pinned MPW core sources")
    parser.add_argument("--update", action="store_true")
    parser.add_argument("--lock-file", type=Path)
    args = parser.parse_args()
    if args.lock_file is None:
        prepare(args.update)
        return 0
    args.lock_file.parent.mkdir(parents=True, exist_ok=True)
    with args.lock_file.open("a+", encoding="utf-8") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        prepare(args.update)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
