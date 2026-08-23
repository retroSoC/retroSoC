#!/usr/bin/env python3
"""Export the configured retroSoC RTL as a tarball or a single SV file."""

from __future__ import annotations

import argparse
import io
import re
import sys
import tarfile
import tempfile
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[4]
SCRIPT_DIR = REPO_ROOT / "rtl/mini/script"
INTEGRATION_DIR = REPO_ROOT / "rtl/mini/integration"
sys.path.insert(0, str(SCRIPT_DIR))
sys.path.insert(0, str(INTEGRATION_DIR))
from filelist import FileList, atomic_write, parse_filelists  # noqa: E402
from generate_filelist import generate_all  # noqa: E402
from generate_user_extensions import generate as generate_user_extensions  # noqa: E402


INCLUDE_RE = re.compile(r'^\s*`include\s+"([^"]+)"')


def build_defines(args: argparse.Namespace) -> list[str]:
    defines = [
        f"+define+PDK_{args.pdk}",
        f"+define+SIMU_{args.simu}",
        "+define+SYNTHESIS",
    ]
    if args.have_pll:
        defines.append("+define+HAVE_PLL")
    if args.have_sram_if:
        defines.append("+define+HAVE_SRAM_IF")
    if args.have_sram_macro:
        defines.append("+define+HAVE_SRAM_MACRO")
    if not args.have_sva:
        defines.append("+define+SV_ASSRT_DISABLE")
    idcode = int(args.jtag_idcode, 16)
    if idcode >= (1 << 31):
        idcode -= 1 << 32
    defines.append(f"+define+SOC_JTAG_IDCODE={idcode}")
    return defines


def configured_filelist(
    args: argparse.Namespace,
    generated_dir: Path,
    user_extensions_dir: Path,
    *,
    require_files: bool = True,
) -> FileList:
    names: list[str | Path] = []
    for name in (
        "memory_map_filelist",
        "soc_topology_filelist",
        "user_extensions_filelist",
    ):
        path = getattr(args, name, None)
        if path is not None:
            names.append(path)
    names.extend(
        [
            "def.fl",
            "sys_def.fl",
            "commonip.fl",
            "inc.fl",
        ]
    )
    pin_map = getattr(args, "pin_map_filelist", None)
    if pin_map is not None:
        names.append(pin_map)
    names.extend(["clusterip.fl", "ip.fl", "tech.fl"])
    names.append("core_hazard3.fl")
    dynamic_core = args.dynamic_core_filelist
    if not dynamic_core.is_file():
        raise FileNotFoundError(f"user core filelist is not generated: {dynamic_core}")
    names.append(str(dynamic_core))
    dynamic_ip = args.dynamic_ip_filelist
    if not dynamic_ip.is_file():
        raise FileNotFoundError(f"user IP filelist is not generated: {dynamic_ip}")
    names.append(str(dynamic_ip))
    if getattr(args, "user_extensions_filelist", None) is None:
        names.append(str(user_extensions_dir / "user_extensions.fl"))
    names.append("top.fl")
    paths = [Path(name) if Path(name).is_absolute() else generated_dir / name for name in names]
    filelist = parse_filelists(paths, require_files=require_files)
    archinfo_incdir = getattr(args, "archinfo_incdir", None)
    if archinfo_incdir is not None:
        archinfo_incdir = archinfo_incdir.resolve()
        if require_files and not archinfo_incdir.is_dir():
            raise FileNotFoundError(f"archinfo include directory not found: {archinfo_incdir}")
        filelist.incdirs.append(archinfo_incdir)
        filelist.deduplicate()
    return filelist


def resolve_include(name: str, incdirs: list[Path], current_file: Path) -> Path | None:
    candidates = [current_file.parent / name, *(directory / name for directory in incdirs)]
    for candidate in candidates:
        if candidate.is_file():
            return candidate.resolve()
    return None


def collect_includes(files: list[Path], incdirs: list[Path]) -> list[Path]:
    headers: set[Path] = set()

    def visit(path: Path) -> None:
        for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
            match = INCLUDE_RE.search(line)
            if not match:
                continue
            header = resolve_include(match.group(1), incdirs, path)
            if header is None:
                continue
            if header not in headers:
                headers.add(header)
                visit(header)

    for source in files:
        visit(source)
    return sorted(headers)


def inline_file(path: Path, incdirs: list[Path], stack: tuple[Path, ...] = ()) -> list[str]:
    resolved = path.resolve()
    if resolved in stack:
        cycle = " -> ".join(str(item) for item in (*stack, resolved))
        raise RuntimeError(f"cyclic `include detected: {cycle}")

    output: list[str] = []
    for line in resolved.read_text(encoding="utf-8", errors="replace").splitlines():
        match = INCLUDE_RE.search(line)
        if not match:
            output.append(line)
            continue
        header = resolve_include(match.group(1), incdirs, resolved)
        if header is None:
            output.append(line)
            continue
        output.append(f'// begin `include "{match.group(1)}"')
        output.extend(inline_file(header, incdirs, (*stack, resolved)))
        output.append(f'// end `include "{match.group(1)}"')
    return output


def defines_to_sv(defines: list[str]) -> list[str]:
    output = []
    for define in defines:
        body = define[len("+define+") :]
        name, separator, value = body.partition("=")
        output.append(f"`define {name}{' ' + value if separator else ''}")
    return output


def write_single_sv(filelist: FileList, output: Path) -> None:
    lines = [
        "// Generated by physical/smoke/syn/tools/export_soc_sources.py",
        *defines_to_sv(filelist.defines),
        "",
    ]
    for source in [*filelist.library_files, *filelist.files]:
        lines.append(f"// ===== file: {source.relative_to(REPO_ROOT)} =====")
        lines.extend(inline_file(source, filelist.incdirs))
        lines.append("")
    atomic_write(output, "\n".join(lines) + "\n")


def bundle_relative(path: Path) -> Path:
    try:
        relative = path.resolve().relative_to(REPO_ROOT)
    except ValueError:
        return Path("_abs") / path.as_posix().lstrip("/")
    if relative.parts and relative.parts[0] == "rtl":
        return Path(*relative.parts[1:])
    return Path("repo") / relative


def write_tar(filelist: FileList, export_dir: Path, soc: str) -> Path:
    export_dir.mkdir(parents=True, exist_ok=True)
    sources = [*filelist.library_files, *filelist.files]
    bundled_files: dict[Path, Path] = {}
    for source in [*sources, *collect_includes(sources, filelist.incdirs)]:
        bundled_files[bundle_relative(source)] = source.resolve()

    manifest = [*filelist.defines]
    manifest.extend(f"+incdir+{bundle_relative(path)}" for path in filelist.incdirs)
    manifest.extend(str(bundle_relative(path)) for path in sources)
    manifest_data = ("\n".join(manifest) + "\n").encode()

    tar_path = export_dir / f"retrosoc_{soc.lower()}_sources.tar.gz"
    with tarfile.open(tar_path, "w:gz") as archive:
        for relative, source in sorted(bundled_files.items()):
            archive.add(source, arcname=str(Path("rtl") / relative), recursive=False)
        filelist_info = tarfile.TarInfo("rtl/filelist.fl")
        filelist_info.size = len(manifest_data)
        filelist_info.mode = 0o644
        archive.addfile(filelist_info, io.BytesIO(manifest_data))
    return tar_path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Export configured retroSoC RTL sources")
    parser.add_argument("mode", choices=("tar", "sv"))
    parser.add_argument("--soc", default="MINI", choices=("MINI",))
    parser.add_argument("--pdk", default="IHP130", choices=("IHP130", "ICS55", "SKY130", "GF180"))
    parser.add_argument("--simu", default="VCS", choices=("VCS", "VERILATOR", "IVERILOG"))
    parser.add_argument("--have-pll", action="store_true")
    parser.add_argument("--have-sram-if", action="store_true")
    parser.add_argument("--have-sram-macro", action="store_true")
    parser.add_argument("--have-sva", action="store_true")
    parser.add_argument("--jtag-idcode", default="DEADBEEF")
    parser.add_argument(
        "--dynamic-core-filelist",
        type=Path,
        required=True,
    )
    parser.add_argument(
        "--dynamic-ip-filelist",
        type=Path,
        required=True,
    )
    parser.add_argument("--memory-map-filelist", type=Path)
    parser.add_argument("--soc-topology-filelist", type=Path)
    parser.add_argument("--user-extensions-filelist", type=Path)
    parser.add_argument("--pin-map-filelist", type=Path)
    parser.add_argument("--archinfo-incdir", type=Path)
    parser.add_argument("--output-dir", type=Path, default=REPO_ROOT / "export")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if not re.fullmatch(r"[0-9a-fA-F]{8}", args.jtag_idcode):
        raise SystemExit("--jtag-idcode must be exactly eight hexadecimal digits")
    export_dir = args.output_dir.resolve()
    export_dir.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="retrosoc-filelists-") as temporary:
        generated_dir = Path(temporary)
        user_extensions_dir = generated_dir / "user_extensions"
        generate_all(generated_dir, build_defines(args))
        if args.user_extensions_filelist is None:
            generate_user_extensions(
                REPO_ROOT / "rtl/mini/integration/user_extensions.json",
                user_extensions_dir,
            )
        filelist = configured_filelist(args, generated_dir, user_extensions_dir)
        if args.mode == "sv":
            output = export_dir / "retrosoc_asic_sources.sv"
            write_single_sv(filelist, output)
        else:
            output = write_tar(filelist, export_dir, args.soc)
    print(f"generated: {output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
