#!/usr/bin/env python3
"""Build pinned RV64 Linux images with a small, static acceptance initramfs."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import subprocess
from pathlib import Path

try:
    from scripts.hp_tools import require_revision, require_rv64_elf
except ModuleNotFoundError:
    from hp_tools import require_revision, require_rv64_elf

LAYOUT = {
    "fw_jump.bin": (0x38000000, 512 * 1024),
    "retrosoc_hp.dtb": (0x38080000, 64 * 1024),
    "Image": (0x38400000, 12 * 1024 * 1024),
    "rootfs.cpio": (0x39000000, 8 * 1024 * 1024),
}

REQUIRED_LINUX_CONFIG = (
    "CONFIG_ARCH_RV64I",
    "CONFIG_64BIT",
    "CONFIG_MMU",
    "CONFIG_OF_RESERVED_MEM",
    "CONFIG_BINFMT_ELF",
    "CONFIG_BINFMT_SCRIPT",
    "CONFIG_PRINTK",
    "CONFIG_TTY",
    "CONFIG_HVC_RISCV_SBI",
    "CONFIG_SERIAL_EARLYCON_RISCV_SBI",
    "CONFIG_PROC_FS",
    "CONFIG_SYSFS",
    "CONFIG_SHMEM",
    "CONFIG_TMPFS",
    "CONFIG_DEVTMPFS",
    "CONFIG_DEVMEM",
)


def command(arguments: list[str], cwd: Path, extra_env: dict[str, str] | None = None) -> None:
    environment = dict(os.environ)
    environment.pop("CONFIG", None)
    environment.pop("MAKEFLAGS", None)
    environment.pop("MAKEOVERRIDES", None)
    environment.pop("MFLAGS", None)
    environment.update(extra_env or {})
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
    matches = sorted((buildroot_output / "host/bin").glob("riscv64*-linux-*-gcc"))
    if len(matches) != 1:
        raise RuntimeError(f"expected one RV64 Linux GCC in {buildroot_output / 'host/bin'}")
    return str(matches[0])[: -len("gcc")]


def minimal_busybox(buildroot: Path, output: Path, external: Path, jobs: int) -> str:
    """Expand an allowlist using BusyBox's own allnoconfig, not default-y oldconfig."""
    make = ["make", f"O={output}", f"BR2_EXTERNAL={external}", f"-j{jobs}"]
    command([*make, "busybox-configure"], buildroot)
    sources = [path for path in (output / "build").glob("busybox-*")
               if (path / "scripts/kconfig/conf").is_file()]
    if len(sources) != 1:
        raise RuntimeError("expected one configured locked BusyBox source")
    source = sources[0]
    config_dir = output.parent / "busybox-config"
    (config_dir / "include").mkdir(parents=True, exist_ok=True)
    command([str(source / "scripts/kconfig/conf"), "-n", str(source / "Config.in")], config_dir,
            {"srctree": str(source), "KCONFIG_NOTIMESTAMP": "1",
             "KCONFIG_ALLCONFIG": str(external / "busybox/retrosoc_hp.config")})
    # This BusyBox conf implementation resets booleans even when ALLCONFIG
    # specified y. Overlay our explicit choices after its all-no expansion;
    # Buildroot's ordinary oldconfig then resolves the real dependencies.
    selected = dict(line.split("=", 1) for line in
                    (external / "busybox/retrosoc_hp.config").read_text().splitlines()
                    if line.startswith("CONFIG_") and "=" in line)
    config = config_dir / ".config"
    lines = []
    for line in config.read_text().splitlines():
        key = line[2:].split(" ", 1)[0] if line.startswith("# CONFIG_") else line.split("=", 1)[0]
        lines.append(f"{key}={selected.pop(key)}" if key in selected else line)
    lines.extend(f"{key}={value}" for key, value in selected.items())
    config.write_text("\n".join(lines) + "\n", encoding="utf-8")
    config_arg = f"BUSYBOX_CONFIG_FILE={config_dir / '.config'}"
    command([*make, config_arg, "busybox-reconfigure"], buildroot)
    return config_arg


def validate_linux_config(config: Path) -> None:
    values: dict[str, str] = {}
    for line in config.read_text(encoding="utf-8").splitlines():
        if line.startswith("CONFIG_") and "=" in line:
            symbol, value = line.split("=", 1)
            values[symbol] = value
        elif line.startswith("# CONFIG_") and line.endswith(" is not set"):
            symbol = line[len("# ") : -len(" is not set")]
            values[symbol] = "n"

    invalid = [
        f"{symbol}={values.get(symbol, 'missing')}"
        for symbol in REQUIRED_LINUX_CONFIG
        if values.get(symbol) != "y"
    ]
    if invalid:
        raise RuntimeError(
            "invalid HP Linux effective configuration: " + ", ".join(invalid)
        )


def build(args: argparse.Namespace) -> None:
    root = args.root.resolve()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    buildroot = require_source(args.buildroot, "Buildroot")
    linux = require_source(args.linux, "Linux")
    opensbi = require_source(args.opensbi, "OpenSBI")
    for name, path in (("buildroot_hp", buildroot), ("linux_hp", linux), ("opensbi_hp", opensbi)):
        if path != require_revision(root, name).resolve():
            raise ValueError(f"{name} must use its locked source directory")
    external = root / "app/ports/linux"

    buildroot_output = output / "buildroot"
    command(
        ["make", f"O={buildroot_output}", f"BR2_EXTERNAL={external}", "retrosoc_hp_defconfig"],
        buildroot,
    )
    busybox_config = minimal_busybox(buildroot, buildroot_output, external, args.jobs)
    command(["make", f"O={buildroot_output}", f"BR2_EXTERNAL={external}",
             busybox_config, f"-j{args.jobs}"], buildroot)
    busybox_sources = sorted((buildroot_output / "build").glob("busybox-*/.config"))
    if len(busybox_sources) != 1:
        raise RuntimeError("missing effective BusyBox configuration")
    busybox_effective = busybox_sources[0].read_text().splitlines()
    for symbol in ("STATIC", "BUSYBOX", "ASH", "MOUNT", "TEST", "ECHO", "CAT", "TRUE"):
        if f"CONFIG_{symbol}=y" not in busybox_effective:
            raise RuntimeError(f"HP BusyBox requires CONFIG_{symbol}=y")
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
    validate_linux_config(linux_output / ".config")
    command(
        ["make", f"O={linux_output}", "ARCH=riscv", f"CROSS_COMPILE={cross_compile}",
         f"-j{args.jobs}", "Image"],
        linux,
    )

    image_dir = output / "images"
    image_dir.mkdir(parents=True, exist_ok=True)
    require_rv64_elf(linux_output / "vmlinux")
    busybox = buildroot_output / "target/bin/busybox"
    require_rv64_elf(busybox)
    if "INTERP" in subprocess.check_output([cross_compile + "readelf", "-l", str(busybox)], text=True):
        raise ValueError("HP acceptance BusyBox must be statically linked")
    helper = output / "hp-ready"
    command([cross_compile + "gcc", "-Os", "-static", "-Wall", "-Wextra", "-Werror",
             "-o", str(helper), str(external / "hp_ready.c")], root)
    require_rv64_elf(helper)
    archive_spec = output / "initramfs.list"
    entries = [f"dir /{name} 755 0 0" for name in ("bin", "dev", "proc", "sys", "tmp")]
    entries += [f"file /bin/busybox {busybox} 755 0 0",
                f"file /bin/hp-ready {helper} 755 0 0", f"file /init {external / 'init'} 755 0 0",
                "nod /dev/console 600 0 0 c 5 1", "nod /dev/mem 600 0 0 c 1 1"]
    entries += [f"slink /bin/{name} busybox 777 0 0" for name in
                ("sh", "mount", "mkdir", "echo", "test", "cat", "sleep")]
    archive_spec.write_text("\n".join(entries) + "\n", encoding="utf-8")
    rootfs_source = image_dir / "rootfs.cpio"
    with rootfs_source.open("wb") as archive:
        subprocess.run([str(linux_output / "usr/gen_init_cpio"), "-t", "0", str(archive_spec)],
                       stdout=archive, check=True)
    initrd_end = LAYOUT["rootfs.cpio"][0] + rootfs_source.stat().st_size
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
            "PLATFORM_RISCV_XLEN=64",
            "PLATFORM_RISCV_ABI=lp64d",
            "PLATFORM_RISCV_ISA=rv64imafdc_zicbom_zicsr_zifencei",
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
    }
    for source, destination in copies.items():
        if not source.is_file():
            raise FileNotFoundError(f"HP Linux build output is missing: {source}")
        shutil.copy2(source, destination)

    require_rv64_elf(opensbi_output / "platform/retrosoc_hp/firmware/fw_jump.elf")
    manifest: dict[str, object] = {
        "schema_version": 1,
        "xlen": 64,
        "abi": "lp64d",
        "initramfs": "minimal-static-uncompressed",
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
