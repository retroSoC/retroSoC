#!/usr/bin/env python3
"""Create a checksummed development delivery from an ECC core harden run."""

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
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--variant-root", type=Path, required=True)
    parser.add_argument("--run-root", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    root = args.root.resolve()
    variant_root = args.variant_root.resolve()
    run_root = args.run_root.resolve()
    project = run_root / "project"
    workspace = project / "runs/default"
    required = (
        project / "ecc.toml",
        workspace,
        run_root / "result.json",
        run_root / "verification.json",
        variant_root / "meta/manifest.json",
        variant_root / "meta/ecc-core-doctor.json",
        variant_root / "meta/ecc-core.json",
        root / "dependencies/dependencies.lock.json",
    )
    missing = [str(path) for path in required if not path.exists()]
    if missing:
        parser.error("missing ECC delivery input(s): " + ", ".join(missing))

    args.output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="retrosoc-ecc-package-") as temporary:
        staging = Path(temporary) / "retrosoc-ics55-core"
        shutil.copytree(run_root / "input", staging / "input")
        shutil.copy2(project / "ecc.toml", staging / "evidence/ecc.toml")
        shutil.copytree(workspace, staging / "evidence/workspace")
        for source, destination in (
            (run_root / "result.json", "ecc-result.json"),
            (run_root / "verification.json", "verification.json"),
            (variant_root / "meta/manifest.json", "manifest.json"),
            (variant_root / "meta/ecc-core-doctor.json", "ecc-doctor.json"),
            (variant_root / "meta/ecc-core.json", "ecc-core.json"),
            (root / "dependencies/dependencies.lock.json", "dependencies.lock.json"),
        ):
            target = staging / "evidence" / destination
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)
        files = sorted(path for path in staging.rglob("*") if path.is_file())
        checksums = "\n".join(
            f"{hash_file(path)}  {path.relative_to(staging)}" for path in files
        )
        (staging / "SHA256SUMS").write_text(checksums + "\n", encoding="utf-8")
        with tarfile.open(args.output, "w:gz") as archive:
            archive.add(staging, arcname=staging.name)
    print(f"created ECC delivery: {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
