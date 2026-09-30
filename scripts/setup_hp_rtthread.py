#!/usr/bin/env python3
"""Install the locked RT-Thread source, RV64 compiler and SCons environment."""

from __future__ import annotations

import argparse
import venv
from pathlib import Path

from dependency_lock import load_lock
from install_toolchain import install
from setup_helpers import ensure_git_repo, run


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--update", action="store_true")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    lock = load_lock()
    spec = lock["sources"]["rtthread_hp"]
    ensure_git_repo(spec["url"], root / spec["destination"], spec["revision"], update=args.update)
    install("riscv_gnu_hp", lock["toolchains"]["ubuntu-22.04"]["riscv_gnu_hp"],
            root / ".cache/retrosoc/development", args.update)
    environment = root / ".cache/retrosoc/rtthread-venv"
    if not (environment / "bin/python").is_file():
        venv.EnvBuilder(with_pip=True).create(environment)
    run((str(environment / "bin/python"), "-m", "pip", "install", "--require-hashes",
         "--cache-dir", str(root / ".cache/retrosoc/pip"),
         "-r", str(root / "requirements/rtthread.txt")))


if __name__ == "__main__":
    main()
