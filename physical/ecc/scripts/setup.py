#!/usr/bin/env python3
"""Install the latest official ECC release and toolchain using upstream defaults."""

from __future__ import annotations

import argparse
import json
import os
import subprocess
from pathlib import Path


INSTALL_COMMAND = (
    "curl -fsSL http://release.openecos.com/installers/ecc/latest/ecc-installer.sh"
    " | sh -s -- --with-toolchain"
)


def default_binary() -> Path:
    return Path(os.environ.get("XDG_BIN_HOME") or Path.home() / ".local/bin") / "ecc"


def install() -> Path:
    # Inherit upstream directory/environment defaults; do not save the installer.
    subprocess.run(["bash", "-o", "pipefail", "-c", INSTALL_COMMAND], check=True)
    binary = default_binary()
    if not binary.is_file() or not os.access(binary, os.X_OK):
        raise RuntimeError(f"ECC installer did not create an executable wrapper: {binary}")
    subprocess.run([str(binary), "--version"], check=True)
    result = subprocess.run(
        [str(binary), "version", "--json"], check=True, text=True, stdout=subprocess.PIPE
    )
    json.loads(result.stdout)
    print(result.stdout.strip())
    return binary


def main() -> int:
    argparse.ArgumentParser(description=__doc__).parse_args()
    binary = install()
    print(f"ECC is ready: {binary}")
    print(f"Add {binary.parent} to PATH to invoke ecc directly.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
