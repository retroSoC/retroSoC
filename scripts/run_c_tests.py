#!/usr/bin/env python3
"""Build and run host tests for deterministic SDK utilities."""

from __future__ import annotations

import argparse
import shutil
import subprocess
import tempfile
from pathlib import Path


TEST_SOURCES = (
    "crt/arch/riscv/libgcc/clzsi2.c",
    "crt/arch/riscv/libgcc/divdi3.c",
    "crt/arch/riscv/libgcc/ffssi2.c",
    "crt/arch/riscv/libgcc/udivdi3.c",
    "crt/arch/riscv/libgcc/umoddi3.c",
    "crt/src/lib/printf.c",
    "crt/src/lib/stdlib.c",
    "crt/src/lib/string.c",
    "app/media/src/video_player.c",
    "app/media/src/wav_audio.c",
    "tests/c/test_runtime.c",
)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--cc", default="clang")
    args = parser.parse_args()

    compiler = shutil.which(args.cc)
    if compiler is None:
        raise SystemExit(f"host C compiler not found: {args.cc}")

    root = args.root.resolve()
    with tempfile.TemporaryDirectory(prefix="retrosoc-c-tests-") as temporary_directory:
        executable = Path(temporary_directory) / "runtime_tests"
        command = [
            compiler,
            "-std=c11",
            "-Wall",
            "-Wextra",
            "-Werror",
            "-fno-builtin",
            "-I",
            str(root / "crt/include"),
            "-I",
            str(root / "app/media/include"),
            "-o",
            str(executable),
            *(str(root / source) for source in TEST_SOURCES),
        ]
        subprocess.run(command, check=True)
        subprocess.run([str(executable)], check=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
