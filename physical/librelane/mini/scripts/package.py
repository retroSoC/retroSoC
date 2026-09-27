#!/usr/bin/env python3
"""Create a checksummed LibreLane implementation delivery archive."""

from __future__ import annotations

import argparse
import hashlib
import shutil
import tarfile
import tempfile
from pathlib import Path


def hash_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        while block := source.read(1024 * 1024):
            digest.update(block)
    return digest.hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--variant-root", type=Path, required=True)
    parser.add_argument("--run-root", type=Path, required=True)
    parser.add_argument("--target", choices=("chip", "core"), required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    root = args.root.resolve()
    variant_root = args.variant_root.resolve()
    run_root = args.run_root.resolve()
    required = (
        run_root / "config.json",
        run_root / "result.json",
        run_root / "final",
        run_root / "runs/current",
        variant_root / "meta/manifest.json",
        variant_root / f"meta/librelane-{args.target}-doctor.json",
        variant_root / f"meta/librelane-{args.target}.json",
        root / "dependencies/dependencies.lock.json",
    )
    missing = [str(path) for path in required if not path.exists()]
    if missing:
        parser.error("missing LibreLane delivery input(s): " + ", ".join(missing))

    args.output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="retrosoc-librelane-package-") as temporary:
        staging = Path(temporary) / f"retrosoc-ihp130-{args.target}"
        shutil.copytree(run_root / "final", staging / "final")
        shutil.copytree(run_root / "runs/current", staging / "evidence/run")
        shutil.copy2(run_root / "config.json", staging / "evidence/config.json")
        shutil.copy2(run_root / "result.json", staging / "evidence/result.json")
        shutil.copy2(variant_root / "meta/manifest.json", staging / "evidence/manifest.json")
        shutil.copy2(
            variant_root / f"meta/librelane-{args.target}-doctor.json",
            staging / "evidence/librelane-doctor.json",
        )
        shutil.copy2(
            variant_root / f"meta/librelane-{args.target}.json",
            staging / f"evidence/librelane-{args.target}.json",
        )
        shutil.copy2(
            root / "dependencies/dependencies.lock.json",
            staging / "evidence/dependencies.lock.json",
        )
        files = sorted(path for path in staging.rglob("*") if path.is_file())
        sums = "\n".join(f"{hash_file(path)}  {path.relative_to(staging)}" for path in files)
        (staging / "SHA256SUMS").write_text(sums + "\n", encoding="utf-8")
        with tarfile.open(args.output, "w:gz") as archive:
            archive.add(staging, arcname=staging.name)
    print(f"created LibreLane delivery: {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
