#!/usr/bin/env python3
"""Build and run host tests for deterministic SDK utilities."""

from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
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
    "crt/src/hal/gpio_math.c",
    "crt/src/hal/i2c_math.c",
    "crt/src/hal/ws2812_math.c",
    "crt/src/hal/uart_math.c",
    "crt/src/hal/timer_math.c",
    "crt/src/hal/psram_math.c",
    "crt/src/hal/sdram_math.c",
    "crt/src/hal/sdio_math.c",
    "crt/src/hal/spisd_math.c",
    "crt/src/hal/i2s_math.c",
    "crt/src/hal/dma_math.c",
    "crt/src/hal/sysctrl.c",
    "rtl/managed/clusterip/ps2/sw/src/ps2.c",
    "rtl/managed/clusterip/ps2/sw/src/ps2_keyboard.c",
    "rtl/managed/clusterip/ps2/sw/src/ps2_mouse.c",
    "rtl/managed/clusterip/rtc/sw/src/rtc.c",
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
        temporary_root = Path(temporary_directory)
        memory_map_root = temporary_root / "memory_map"
        user_extensions_root = temporary_root / "user_extensions"
        subprocess.run(
            [
                sys.executable,
                str(root / "rtl/mini/address_map/generate_memory_map.py"),
                "--map",
                str(root / "rtl/mini/address_map/memory_map.json"),
                "--output-dir",
                str(memory_map_root),
            ],
            check=True,
        )
        subprocess.run(
            [
                sys.executable,
                str(root / "rtl/mini/integration/generate_user_extensions.py"),
                "--map",
                str(root / "rtl/mini/integration/user_extensions.json"),
                "--output-dir",
                str(user_extensions_root),
            ],
            check=True,
        )
        executable = temporary_root / "runtime_tests"
        command = [
            compiler,
            "-std=c11",
            "-Wall",
            "-Wextra",
            "-Werror",
            "-fno-builtin",
            "-I",
            str(memory_map_root / "include"),
            "-I",
            str(user_extensions_root / "include"),
            "-I",
            str(root / "rtl/managed/clusterip/ps2/sw/include"),
            "-I",
            str(root / "rtl/managed/clusterip/rtc/sw/include"),
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
