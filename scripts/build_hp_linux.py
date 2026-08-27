#!/usr/bin/env python3
"""Build the pinned RV32 HP Buildroot, Linux, DTB, and OpenSBI images."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import subprocess
from pathlib import Path


LAYOUT = {
    "fw_jump.bin": (0x38000000, 512 * 1024),
    "retrosoc_hp.dtb": (0x38080000, 64 * 1024),
    "Image": (0x38400000, 12 * 1024 * 1024),
    "rootfs.cpio.gz": (0x39000000, 8 * 1024 * 1024),
}


def command(arguments: list[str], cwd: Path) -> None:
    environment = dict(os.environ)
    environment.pop("CONFIG", None)
    environment.pop("MAKEFLAGS", None)
    environment.pop("MAKEOVERRIDES", None)
    environment.pop("MFLAGS", None)
    subprocess.run(arguments, cwd=cwd, check=True, env=environment)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def require_source(path: Path, name: str) -> Path:
    resolved = path.resolve()
    if not (resolved / ".git").exists():
        raise FileNotFoundError(f"missing locked {name} source: {resolved}; run setup-hp-linux")
    return resolved


def source_revision(path: Path) -> str:
    return subprocess.check_output(
        ["git", "-C", str(path), "rev-parse", "HEAD"], text=True
    ).strip()


def find_toolchain(buildroot_output: Path) -> str:
    matches = sorted((buildroot_output / "host/bin").glob("riscv32*-linux-*-gcc"))
    if len(matches) != 1:
        raise RuntimeError(f"expected one RV32 Linux GCC in {buildroot_output / 'host/bin'}")
    return str(matches[0])[: -len("gcc")]


def build(args: argparse.Namespace) -> None:
    root = args.root.resolve()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    buildroot = require_source(args.buildroot, "Buildroot")
    linux = require_source(args.linux, "Linux")
    opensbi = require_source(args.opensbi, "OpenSBI")
    external = root / "app/ports/linux"

    buildroot_output = output / "buildroot"
    command(
        ["make", f"O={buildroot_output}", f"BR2_EXTERNAL={external}", "retrosoc_hp_defconfig"],
        buildroot,
    )
    command(["make", f"O={buildroot_output}", f"BR2_EXTERNAL={external}", f"-j{args.jobs}"], buildroot)
    cross_compile = find_toolchain(buildroot_output)

    linux_output = output / "linux"
    command(
        ["make", f"O={linux_output}", "ARCH=riscv", f"CROSS_COMPILE={cross_compile}", "tinyconfig"],
        linux,
    )
    command(
        [
            str(linux / "scripts/kconfig/merge_config.sh"),
            "-m",
            "-O",
            str(linux_output),
            str(linux_output / ".config"),
            str(external / "linux/retrosoc_hp.config"),
        ],
        linux,
    )
    command(
        ["make", f"O={linux_output}", "ARCH=riscv", f"CROSS_COMPILE={cross_compile}", "olddefconfig"],
        linux,
    )
    command(
        ["make", f"O={linux_output}", "ARCH=riscv", f"CROSS_COMPILE={cross_compile}",
         f"-j{args.jobs}", "Image"],
        linux,
    )

    image_dir = output / "images"
    image_dir.mkdir(parents=True, exist_ok=True)
    rootfs_source = buildroot_output / "images/rootfs.cpio.gz"
    if not rootfs_source.is_file():
        raise FileNotFoundError(f"HP Linux build output is missing: {rootfs_source}")
    initrd_end = LAYOUT["rootfs.cpio.gz"][0] + rootfs_source.stat().st_size
    command(
        [
            "dtc",
            "-I",
            "dts",
            "-O",
            "dtb",
            "-o",
            str(image_dir / "retrosoc_hp.dtb"),
            str(external / "linux/retrosoc_hp.dts"),
        ],
        root,
    )
    command(
        [
            "fdtput",
            "-t",
            "x",
            str(image_dir / "retrosoc_hp.dtb"),
            "/chosen",
            "linux,initrd-end",
            f"0x{initrd_end:08x}",
        ],
        root,
    )

    opensbi_output = output / "opensbi"
    command(
        [
            "make",
            f"O={opensbi_output}",
            f"CROSS_COMPILE={cross_compile}",
            "PLATFORM=retrosoc_hp",
            f"PLATFORM_DIR={external / 'opensbi'}",
            "PLATFORM_RISCV_XLEN=32",
            "PLATFORM_RISCV_ABI=ilp32d",
            "PLATFORM_RISCV_ISA=rv32imafdc_zicsr_zifencei",
            "FW_TEXT_START=0x38000000",
            "FW_JUMP=y",
            "FW_JUMP_ADDR=0x38400000",
            "FW_JUMP_FDT_ADDR=0x38080000",
            f"-j{args.jobs}",
        ],
        opensbi,
    )

    copies = {
        opensbi_output / "platform/retrosoc_hp/firmware/fw_jump.bin": image_dir / "fw_jump.bin",
        linux_output / "arch/riscv/boot/Image": image_dir / "Image",
        rootfs_source: image_dir / "rootfs.cpio.gz",
    }
    for source, destination in copies.items():
        if not source.is_file():
            raise FileNotFoundError(f"HP Linux build output is missing: {source}")
        shutil.copy2(source, destination)

    manifest: dict[str, object] = {
        "schema_version": 1,
        "boot_flow": "opensbi-fw_jump",
        "hart_id": 1,
        "sources": {
            "buildroot": source_revision(buildroot),
            "linux": source_revision(linux),
            "opensbi": source_revision(opensbi),
        },
        "artifacts": {},
    }
    artifacts = manifest["artifacts"]
    assert isinstance(artifacts, dict)
    for name, (address, maximum) in LAYOUT.items():
        path = image_dir / name
        size = path.stat().st_size
        if size > maximum:
            raise ValueError(f"{name} is {size} bytes; maximum is {maximum}")
        artifacts[name] = {
            "address": f"0x{address:08X}",
            "maximum_bytes": maximum,
            "size_bytes": size,
            "sha256": sha256(path),
        }
    (image_dir / "manifest.json").write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--buildroot", type=Path, required=True)
    parser.add_argument("--linux", type=Path, required=True)
    parser.add_argument("--opensbi", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--jobs", type=int, default=1)
    build(parser.parse_args())


if __name__ == "__main__":
    main()
