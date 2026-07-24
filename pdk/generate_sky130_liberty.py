#!/usr/bin/env python3

from __future__ import annotations

import argparse
import os
import subprocess
import sys
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from scripts.setup_helpers import atomic_write  # noqa: E402


CORNER = "tt_025C_1v80"
LIBRARY = "sky130_fd_sc_hd"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Generate the SKY130 HD Liberty model from locked PDK JSON sources"
    )
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--revision", required=True)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    source = args.source.resolve()
    library_dir = source / "libraries" / LIBRARY / "latest"
    generator_dir = source / "scripts" / "python-skywater-pdk"
    required = (
        library_dir / "timing" / f"{LIBRARY}__common.lib.json",
        library_dir / "timing" / f"{LIBRARY}__{CORNER}.lib.json",
        generator_dir / "skywater_pdk" / "liberty.py",
    )
    missing = [str(path) for path in required if not path.is_file()]
    if missing:
        raise FileNotFoundError("missing SKY130 Liberty input(s): " + ", ".join(missing))

    output_dir = args.output_dir.resolve()
    output = output_dir / f"{LIBRARY}__{CORNER}.lib"
    revision = output.with_suffix(output.suffix + ".revision")
    if (
        output.is_file()
        and revision.is_file()
        and revision.read_text(encoding="utf-8") == f"{args.revision}\n"
    ):
        print(f"SKY130 Liberty is ready: {output}")
        return 0

    output_dir.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="sky130-liberty-", dir=output_dir) as temporary:
        temporary_dir = Path(temporary)
        command = (
            sys.executable,
            "-m",
            "skywater_pdk.liberty",
            str(library_dir),
            CORNER,
            "--output_directory",
            str(temporary_dir),
        )
        print("+ " + " ".join(command))
        environment = os.environ.copy()
        environment["PYTHONPATH"] = str(generator_dir)
        subprocess.run(command, check=True, env=environment)
        generated = temporary_dir / output.name
        if not generated.is_file():
            raise RuntimeError(f"SKY130 Liberty generator did not create {generated}")
        atomic_write(output, generated.read_text(encoding="utf-8"))
    atomic_write(revision, f"{args.revision}\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
