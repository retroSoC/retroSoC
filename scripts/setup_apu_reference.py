#!/usr/bin/env python3
"""Install and build the pinned host-only APU FLAC references."""

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from scripts.dependency_lock import archive, source  # noqa: E402
from scripts.install_toolchain import safe_extract  # noqa: E402
from scripts.setup_helpers import atomic_write, download_file  # noqa: E402


def _install_archive(name: str, *, update: bool, timeout: int) -> Path:
    source_spec = source(name)
    archive_spec = archive(name)
    archive_path = ROOT / archive_spec["destination"]
    destination = ROOT / source_spec["destination"]
    marker = destination / ".retrosoc-archive-sha256"

    download_file(
        archive_spec["url"],
        archive_path,
        archive_spec["sha256"],
        update=update,
        timeout=timeout,
        resume=name == "apu_flac_corpus",
    )
    if marker.is_file() and marker.read_text(encoding="utf-8").strip() == archive_spec["sha256"]:
        return destination
    if destination.exists() and not update:
        raise RuntimeError(f"stale APU reference source: {destination}; rerun with --update")

    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(
        prefix=f".{destination.name}.", dir=destination.parent
    ) as temp:
        extracted = Path(temp) / "extracted"
        extracted.mkdir()
        safe_extract(archive_path, extracted)
        roots = [path for path in extracted.iterdir() if path.is_dir()]
        if len(roots) != 1:
            raise RuntimeError(f"{name} archive must contain one source root")
        atomic_write(roots[0] / ".retrosoc-archive-sha256", archive_spec["sha256"] + "\n")
        if destination.exists():
            shutil.rmtree(destination)
        os.replace(roots[0], destination)
    return destination


def _validate_notices(libflac: Path, corpus: Path) -> None:
    for name in ("COPYING.Xiph", "COPYING.GPL", "COPYING.LGPL", "COPYING.FDL"):
        if not (libflac / name).is_file():
            raise RuntimeError(f"libFLAC notice is missing: {name}")
    if not (corpus / "LICENSE.txt").is_file() or not (corpus / "README.txt").is_file():
        raise RuntimeError("FLAC corpus license or attribution is missing")


def _build_libflac(source_dir: Path, build_dir: Path) -> None:
    build_dir.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        [
            "cmake",
            "-S",
            str(source_dir),
            "-B",
            str(build_dir),
            "-G",
            "Ninja",
            "-DWITH_OGG=OFF",
            "-DBUILD_CXXLIBS=OFF",
            "-DBUILD_PROGRAMS=ON",
            "-DBUILD_EXAMPLES=OFF",
            "-DBUILD_TESTING=OFF",
            "-DBUILD_DOCS=OFF",
            "-DINSTALL_MANPAGES=OFF",
            "-DBUILD_SHARED_LIBS=OFF",
        ],
        check=True,
    )
    subprocess.run(["cmake", "--build", str(build_dir), "--target", "flac"], check=True)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build-dir", type=Path, required=True)
    parser.add_argument("--update", action="store_true")
    args = parser.parse_args()

    libflac = _install_archive("apu_libflac", update=args.update, timeout=120)
    corpus = _install_archive("apu_flac_corpus", update=args.update, timeout=1800)
    _validate_notices(libflac, corpus)
    _build_libflac(libflac, args.build_dir.resolve())
    print(f"APU libFLAC reference: {args.build_dir.resolve() / 'src/flac/flac'}")
    print(f"APU FLAC corpus: {corpus}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
