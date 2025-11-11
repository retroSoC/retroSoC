#!/usr/bin/env python3
# Export retroSoC sources (tar.gz or single .sv).
# Rebuild filelists to absolute paths; inline `include` in .sv.
# Usage: python3 syn/tools/export_soc_sources.py [sv|tar] --soc MINI|TINY
# Outputs: sv -> export/retrosoc_asic_sources.sv; tar -> export/retrosoc_<soc>_sources.tar.gz
import argparse
import os
import tarfile
import shutil
import sys
from pathlib import Path
import re


REPO_ROOT = Path(__file__).resolve().parents[2]


def read_flist(flist: Path):
    """Parse a filelist where entries may be space-separated on a single line.

    Robustly handles lines like: "+define+FOO +define+BAR +incdir+dir path/to/file.sv ..."
    by splitting into tokens and classifying each token.
    """
    defines = []
    incdirs = []
    files = []
    if not flist.exists():
        return defines, incdirs, files
    for raw in flist.read_text().splitlines():
        # strip comments (# or //) and split by whitespace
        line = raw.split('//', 1)[0].split('#', 1)[0].strip()
        if not line:
            continue
        tokens = line.split()
        for tok in tokens:
            if not tok:
                continue
            if tok.startswith('+define+'):
                defines.append(tok)
            elif tok.startswith('+incdir+'):
                # Everything after +incdir+ is the directory path
                incdirs.append(tok[len('+incdir+'):].strip())
            else:
                # Treat as a file path entry
                files.append(tok)
    return defines, incdirs, files


def build_flist_if_missing(soc_dir: Path):
    """(Re)build yosys.fl and yosys-abspath.fl from canonical filelists.

    Always reconstruct them to avoid stale or inconsistent content.
    """
    fl_dir = soc_dir / 'filelist'
    yosys_fl = fl_dir / 'yosys.fl'
    yosys_abs = fl_dir / 'yosys-abspath.fl'
    # Compose in-order lists (always rebuild to avoid historical issues)
    def_fl = fl_dir / 'def.fl'
    inc_fl = fl_dir / 'inc.fl'
    ip_fl = fl_dir / 'ip.fl'
    tech_fl = fl_dir / 'tech.fl'
    top_fl = fl_dir / 'top.fl'
    # Guess core from def.fl
    core_name = None
    if def_fl.exists():
        text = def_fl.read_text()
        m = re.search(r"\+define\+CORE_([A-Z0-9_]+)", text)
        if m:
            core_name = m.group(1).lower()
    if core_name is None:
        core_name = 'picorv32'
    core_fl = fl_dir / f'core_{core_name}.fl'

    rel_lines = []
    if def_fl.exists():
        rel_lines.extend(def_fl.read_text().splitlines())
    if inc_fl.exists():
        rel_lines.extend(inc_fl.read_text().splitlines())
    if ip_fl.exists():
        rel_lines.extend(ip_fl.read_text().splitlines())
    if tech_fl.exists():
        rel_lines.extend(tech_fl.read_text().splitlines())
    if core_fl.exists():
        rel_lines.extend(core_fl.read_text().splitlines())
    if top_fl.exists():
        rel_lines.extend(top_fl.read_text().splitlines())

    # Write yosys.fl
    yosys_fl.write_text('\n'.join(rel_lines) + '\n')

    # Convert to abspath list
    defines, incdirs, files = read_flist(yosys_fl)
    abs_lines = []
    abs_lines.extend(defines)
    for d in incdirs:
        p = Path(d)
        if not p.is_absolute():
            p = (fl_dir / p).resolve()
        abs_lines.append(f'+incdir+{p}')
    for f in files:
        p = Path(f)
        if not p.is_absolute():
            p = (fl_dir / p).resolve()
        abs_lines.append(str(p))
    yosys_abs.write_text('\n'.join(abs_lines) + '\n')
    return yosys_fl, yosys_abs


def copy_sources_to_export(files, export_root: Path):
    for f in files:
        src = Path(f)
        # compute path relative to repo root if possible
        try:
            rel = src.relative_to(REPO_ROOT)
        except ValueError:
            # fall back to absolute path mirroring under export
            rel = Path('_abs') / src.as_posix().lstrip('/')
        dst = export_root / rel
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, dst)


def collect_includes(files, incdirs):
    """Collect all directly and transitively included headers for a set of files."""
    headers = set()  # store resolved absolute paths as strings

    def add_and_recurse(hpath: Path):
        sp = str(hpath.resolve())
        if sp in headers:
            return
        headers.add(sp)
        # recurse into header to discover nested includes
        try:
            text = hpath.read_text()
        except Exception:
            return
        for line in text.splitlines():
            m = INCLUDE_RE.search(line)
            if m:
                nested = resolve_include(m.group(1), incdirs, hpath)
                if nested:
                    add_and_recurse(nested)

    for f in files:
        fp = Path(f)
        if not fp.exists():
            continue
        try:
            text = fp.read_text()
        except Exception:
            continue
        for line in text.splitlines():
            m = INCLUDE_RE.search(line)
            if m:
                name = m.group(1)
                cand = resolve_include(name, incdirs, fp)
                if cand:
                    add_and_recurse(cand)
    return sorted(headers)


def defines_to_sv(defines):
    sv_lines = []
    for d in defines:
        # +define+FOO or +define+FOO=BAR
        if '=' in d:
            name = d[len('+define+'):].split('=')[0]
            val = d[len('+define+'):].split('=')[1]
            sv_lines.append(f'`define {name} {val}')
        else:
            name = d[len('+define+'):]
            sv_lines.append(f'`define {name}')
    return sv_lines


INCLUDE_RE = re.compile(r"`include\s+\"([^\"]+)\"")


def resolve_include(name: str, incdirs, current_file: Path):
    # search order: incdirs then alongside current working file dir
    for d in incdirs:
        cand = Path(d) / name
        if cand.exists():
            return cand
    # fallback: relative to current file directory
    cand = current_file.parent / name
    if cand.exists():
        return cand
    return None


def inline_file(path: Path, incdirs, visited_headers):
    out = []
    if not path.exists():
        return out
    text = path.read_text()
    for line in text.splitlines():
        m = INCLUDE_RE.search(line)
        if m:
            hdr = m.group(1)
            hdr_path = resolve_include(hdr, incdirs, path)
            if hdr_path:
                rp = str(hdr_path.resolve())
                if rp in visited_headers:
                    continue
                visited_headers.add(rp)
                out.append(f'// `include "{hdr}" inlined from {hdr_path}')
                out.extend(inline_file(hdr_path, incdirs, visited_headers))
                out.append('// end inline')
            else:
                # keep original include if not found
                out.append(line)
        else:
            out.append(line)
    return out


def build_single_sv(defines, incdirs, files, out_path: Path):
    lines = []
    # header
    lines.append('// retroSoC single-file export')
    lines.append(f'// Generated from {REPO_ROOT}')
    # translate defines
    lines.extend(defines_to_sv(defines))
    lines.append('')
    visited_headers = set()
    for f in files:
        fp = Path(f)
        lines.append(f'// ====== file: {fp} ======')
        lines.extend(inline_file(fp, incdirs, visited_headers))
        lines.append('')
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text('\n'.join(lines) + '\n')


def main():
    ap = argparse.ArgumentParser(description='Export retroSoC sources')
    ap.add_argument('mode', choices=['tar', 'sv'], help='export as tar.gz or single .sv')
    ap.add_argument('--soc', default='MINI', help='SOC: MINI or TINY')
    args = ap.parse_args()

    soc = args.soc.lower()
    soc_dir = REPO_ROOT / 'rtl' / soc
    if not soc_dir.exists():
        print(f'Error: SOC directory not found: {soc_dir}', file=sys.stderr)
        sys.exit(1)

    # ensure flists are present or build them
    _, yosys_abs = build_flist_if_missing(soc_dir)
    defines, incdirs, files = read_flist(yosys_abs)

    export_dir = REPO_ROOT / 'export'
    export_dir.mkdir(exist_ok=True)

    if args.mode == 'tar':
        bundle_root = export_dir / 'rtl'
        if bundle_root.exists():
            shutil.rmtree(bundle_root)
        bundle_root.mkdir(parents=True)
        # copy sources
        copy_sources_to_export(files, bundle_root)
        # copy headers referenced by sources
        hdrs = collect_includes(files, incdirs)
        copy_sources_to_export(hdrs, bundle_root)
        # write manifests (absolute and relative-to-bundle)
        abs_manifest = '\n'.join([*defines, *[f'+incdir+{d}' for d in incdirs], *files]) + '\n'
        (bundle_root / 'filelist_abspath.fl').write_text(abs_manifest)
        # relative manifest for portability
        def to_bundle_rel(p: Path):
            try:
                rel = p.resolve().relative_to(REPO_ROOT)
            except Exception:
                rel = Path('_abs') / p.as_posix().lstrip('/')
            return rel
        rel_incdirs = [f'+incdir+{to_bundle_rel(Path(d))}' for d in incdirs]
        rel_files = [str(to_bundle_rel(Path(f))) for f in files]
        (bundle_root / 'filelist_rel.fl').write_text('\n'.join([*defines, *rel_incdirs, *rel_files]) + '\n')
        # create tar.gz
        tar_path = export_dir / f'retrosoc_{soc}_sources.tar.gz'
        with tarfile.open(tar_path, 'w:gz') as tf:
            tf.add(bundle_root, arcname='rtl')
        print(f'Generated: {tar_path}')
    else:
        sv_path = export_dir / f'retrosoc_asic_sources.sv'
        build_single_sv(defines, incdirs, files, sv_path)
        print(f'Generated: {sv_path}')


if __name__ == '__main__':
    main()