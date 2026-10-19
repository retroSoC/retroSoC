#!/usr/bin/env python3
"""Standalone SPI-P1 flows; no product integration or qualification promotion."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
from pathlib import Path
import shutil
import subprocess
import sys
import tarfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from scripts.check_simulation import DEFAULT_FAILURE  # noqa: E402
from scripts.setup_helpers import atomic_write  # noqa: E402
from scripts.yosys_period import period_ps  # noqa: E402

COMMON = ROOT / "rtl/managed/clusterip/common/rtl"
IP = ROOT / "rtl/ip/serial"
TOP = "apb4_spi_block_top"
WRAPPER = ROOT / f"physical/smoke/syn/yosys/{TOP}.sv"
SOURCES = [COMMON / "interface/apb4_if.sv", COMMON / "utils/register.sv",
           ROOT / "rtl/ip/util/soc_common_fifo.sv",
           *[IP / f"{name}.sv" for name in (
               "spi_pkg", "spi_ctrl_if", "spi_gpio_guard", "spi_phase_ctrl",
               "spi_word_packer", "spi_master_core", "spi_reg", "apb4_spi")], WRAPPER]
INCLUDES = [COMMON, COMMON / "utils", IP, ROOT / "tests/rtl"]
CASES = ("spi_pin_checker_tb", "spi_core_tb", "spi_apb_tb", "spi_lifecycle_tb", "spi_packer_tb")
TOOL_INPUT_SCHEMA = 2


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def dump(path: Path, data: dict) -> None:
    atomic_write(path, json.dumps(data, indent=2, sort_keys=True) + "\n")


def inputs() -> dict[str, str]:
    files = set(SOURCES) | {COMMON / "utils/fifo.sv", COMMON / "config.svh", IP / "spi_define.svh",
        ROOT / "Makefile", ROOT / "scripts/spi_p1.py", ROOT / "scripts/run_flow.py",
        ROOT / "scripts/check_simulation.py", ROOT / "dependencies/dependencies.lock.json",
        ROOT / "docs/ip/spi.md", ROOT / "configs/ci/ics55-tiny.mk",
        ROOT / "rtl/tiny/integration/clock_reset_domains.json",
        ROOT / "scripts/bitwuzla_smt2.py", ROOT / "scripts/yosys_period.py",
        ROOT / "configs/ci/ihp130-tiny.mk", ROOT / "crt/include/retrosoc/hal/spi_regs.h"}
    for pattern in ("tests/rtl/spi_*", "tests/test_spi*", "physical/smoke/sta/opensta/spi_block.*",
                    "physical/smoke/syn/yosys/script/*"):
        files.update(ROOT.glob(pattern))
    return {str(p.relative_to(ROOT)): digest(p) for p in sorted(files) if p.is_file()}


def yosys_json(path: Path) -> dict:
    """Remove only Yosys tee timestamp prefixes, preserving the raw artifact."""
    return json.loads(re.sub(r'^\[\d+\.\d+\]\s?', '', path.read_text(), flags=re.M))


def formal_model_counts(content: str, mode: str) -> dict:
    counts = {kind: len(re.findall(rf'^; yosys-smt2-{kind}\b', content, re.M))
              for kind in ('assert', 'assume', 'cover')}
    required = 'cover' if mode == 'cover' else 'assert'
    if counts[required] == 0:
        raise ValueError(f'formal model has no active {required} properties')
    return counts


def cover_witness_steps(directory: Path, minimum: int = 193) -> int:
    lengths = [len(json.loads(p.read_text())['steps']) for p in directory.glob('trace*.yw')]
    if not lengths or max(lengths) < minimum:
        raise ValueError('formal cover lacks a witness for the complete 192-cycle window')
    return max(lengths)


def require_pass(content: str, result: dict, marker: str) -> None:
    if result.get("status") != "passed" or result.get("exit_code") != 0:
        raise ValueError("command did not pass")
    if content.count(marker) != 1 or DEFAULT_FAILURE.search(content):
        raise ValueError("missing/duplicate success or forbidden error marker")


def checked_record(path: Path, source: dict) -> dict:
    data = json.loads(path.read_text())
    if data.get('tool_input_schema') != TOOL_INPUT_SCHEMA:
        raise ValueError(f'incomplete historical tool inventory: {path}')
    if data.get("status") != "passed" or data.get("source") != source:
        raise ValueError(f"incomplete or stale SPI evidence: {path}")
    pdk = data['manifest']['configuration']['PDK']
    if data.get('external_inputs') != external_inputs(pdk):
        raise ValueError(f'changed or incomplete SPI tool/input inventory: {path}')
    for name, value in data["artifacts"].items():
        if digest(Path(name)) != value:
            raise ValueError(f"changed SPI artifact: {name}")
    for name, value in data.get('external_inputs', {}).items():
        if digest(Path(name)) != value:
            raise ValueError(f'changed SPI external input: {name}')
    return data


def execute(directory: Path, name: str, command: list[str], timeout: int = 300,
            environment: dict | None = None) -> tuple[dict, str]:
    log, result = directory / f"{name}.log", directory / f"{name}.json"
    args = [sys.executable, str(ROOT / "scripts/run_flow.py"), "--tool", name,
            "--log", str(log), "--result", str(result), "--cwd", str(ROOT)]
    for key, value in (environment or {}).items():
        args += ["--env", f"{key}={value}"]
    args += ["--", "timeout", "--foreground", "--kill-after=5s", f"{timeout}s", *command]
    completed = subprocess.run(args, cwd=ROOT, check=False)
    data = json.loads(result.read_text())
    if completed.returncode != 0 or data.get("exit_code") != 0 or data.get('status') != 'passed':
        raise RuntimeError(f"{name} failed; see {log}")
    if re.search(r'(?im)^Error:', log.read_text(errors='replace')):
        raise RuntimeError(f'{name} reported a tool error; see {log}')
    return data, log.read_text(errors="replace")


def verilator_config(directory: Path) -> str:
    path = directory / "common.vlt"
    atomic_write(path, "`verilator_config\n"
                 f'lint_off -rule DECLFILENAME -file "{COMMON}/utils/register.sv"\n'
                 f'lint_off -rule UNUSEDSIGNAL -file "{COMMON}/interface/apb4_if.sv"\n')
    return str(path)


def simulate(directory: Path, simulator: str, top: str, jobs: int,
             netlist: Path | None = None, models: list[Path] | None = None) -> None:
    extra = [ROOT / "tests/rtl/spi_pin_bfm.sv", ROOT / f"tests/rtl/{top}.sv"]
    defines = [f"-I{p}" for p in INCLUDES]
    model = directory / top
    if netlist is not None:
        adapter = netlist_adapter(netlist, directory)
        command = ["iverilog", "-g2012", "-gno-specify", "-s", top, "-o", str(model),
                   '-DSPI_DUT=spi_netlist_adapter', *defines,
                   *map(str, (models or []) + [netlist, adapter] + extra)]
    elif simulator == "VERILATOR":
        command = ["verilator", "--binary", "--timing", "--timescale", "1ns/1ps",
                   verilator_config(directory), "--assert", "-j", str(jobs),
                   "--top-module", top, "--Mdir", str(directory / f"obj-{top}"),
                   "-o", str(model), *defines, *map(str, SOURCES + extra)]
    else:
        converted = directory / f"{top}.v"
        conversion = subprocess.run(["sv2v", *defines, *map(str, SOURCES + extra)],
                                    capture_output=True, text=True, timeout=180, check=False)
        atomic_write(directory / f"{top}-sv2v.log", conversion.stderr)
        if conversion.returncode:
            raise RuntimeError(conversion.stderr)
        atomic_write(converted, '`timescale 1ns/1ps\n' + conversion.stdout)
        command = ["iverilog", "-g2012", "-s", top, "-o", str(model), str(converted)]
    execute(directory, f"{top}-compile", command, environment={"CCACHE_DISABLE": "1"})
    launch = [str(model)] if simulator == "VERILATOR" and netlist is None else ["vvp", str(model)]
    result, log = execute(directory, top, launch, timeout=600)
    require_pass(log, result, f"SPI_P1_PASS {top}")


def synth(directory: Path, pdk: str) -> None:
    period = period_ps(json.loads((ROOT / 'rtl/tiny/integration/clock_reset_domains.json').read_text()),
                       'peripheral')
    for name in ("out", "tmp", "rpt"):
        (directory / name).mkdir()
    filelist = directory / "source.fl"
    atomic_write(filelist, "\n".join([*[f"+incdir+{p}" for p in INCLUDES],
                                     *map(str, SOURCES)]) + "\n")
    execute(directory, "yosys", ["yosys", "-t", "--perffile", str(directory / "yosys-perf.json"),
        "-c", str(ROOT / "physical/smoke/syn/yosys/script/synth.tcl")], 10800, {
        "PDK": pdk, "SOC": "TINY", "SYNTH_RECIPE": "balanced", "HAVE_SRAM_MACRO": "NO",
        "YOSYS_TARGET_PERIOD_PS": str(period), "SRAM_SIZE_KIB": '128',
        "SV_FLIST": str(filelist), "TOP_DESIGN": TOP,
        "PROJ_NAME": TOP, "WORK": str(directory / "tmp"), "BUILD": str(directory / "out"),
        "REPORTS": str(directory / "rpt"), "NETLIST": str(directory / "out/netlist.v"),
        "CONFIG": str(directory / "out/config"), "YOSYS_KEEP_HIER_INST": "",
        "YOSYS_REPORT_INSTS": "", "YOSYS_FLATTEN_HIER": "1"})
    mapped = json.loads((directory / 'out/netlist.v.json').read_text())['modules'][TOP]
    cells = [cell['type'] for cell in mapped['cells'].values()]
    if any(not (c.startswith('sg13g2_') if pdk == 'IHP130' else c.endswith('H7R')) for c in cells):
        raise ValueError('foreign, unresolved or macro cell in SPI block netlist')
    generic = (directory / f'rpt/{TOP}_generic.rpt').read_text()
    if '$dlatch' in generic.lower() or '$_dlatch' in generic.lower():
        raise ValueError('SPI inferred latch')
    check = (directory / f'rpt/{TOP}_synth.rpt').read_text()
    if 'Found and reported 0 problems.' not in check:
        raise ValueError('SPI netlist structural check did not pass')
    memory = yosys_json(directory / f'rpt/{TOP}_pre_memory.json')['modules']
    fifo_bits = {name: item.get('num_memory_bits', 0) for name, item in memory.items()
                 if 'u_tx_fifo' in name or 'u_rx_fifo' in name}
    if sorted(fifo_bits.values()) != [256, 256]:
        raise ValueError(f'SPI FIFO storage mapping differs: {fifo_bits}')
    area = yosys_json(directory / f'rpt/{TOP}_area.json')['design']['area']
    dump(directory / 'mapping.json', {'top': TOP, 'pdk': pdk, 'period_ps': period,
         'cells': len(cells), 'area': area, 'fifo_bits': fifo_bits, 'sram_macros': 0})


def netlist_adapter(netlist: Path, directory: Path) -> Path:
    ports = json.loads(Path(str(netlist) + '.json').read_text())['modules'][TOP]['ports']
    groups = {}
    connections = []
    for name, value in ports.items():
        match = re.fullmatch(r'(.*?)(?:__v(\d+)|_(\d+)_|\[(\d+)\])', name)
        if match:
            base = match[1]
            index = int(next(v for v in match.groups()[1:] if v is not None))
            group = groups.setdefault(base, {'direction': value['direction'], 'indices': []})
            if group['direction'] != value['direction'] or len(value['bits']) != 1:
                raise ValueError('invalid split-port direction/width')
            group['indices'].append(index)
            target = f'{base}[{index}]'
        else:
            base = name
            groups[base] = {'direction': value['direction'], 'indices': list(range(len(value['bits'])))}
            target = name
        escaped = f'\\{name} ' if not re.fullmatch(r'[A-Za-z_]\w*', name) else name
        connections.append(f'.{escaped}({target})')
    declarations = []
    for name, value in groups.items():
        indices = sorted(value['indices'])
        if indices != list(range(len(indices))):
            raise ValueError('noncontiguous split port')
        width = '' if len(indices) == 1 else f'[{len(indices)-1}:0] '
        declarations.append(f'{value["direction"]} wire {width}{name}')
    path = directory / 'adapter.v'
    atomic_write(path, 'module spi_netlist_adapter(\n' + ',\n'.join(declarations) + ');\n' +
                 f'{TOP} u_mapped(\n' + ',\n'.join(connections) + ');\nendmodule\n')
    return path


def technology(pdk: str) -> tuple[Path, list[Path]]:
    if pdk == "ICS55":
        return (ROOT / ".cache/retrosoc/pdk/ics55/ics55_h7cr_ss.lib",
                [ROOT / ".cache/retrosoc/pdk/ics55/ics55_h7cr_functional.v"])
    base = ROOT / "physical/pdk/IHP-Open-PDK/ihp-sg13g2/libs.ref/sg13g2_stdcell"
    return base / "lib/sg13g2_stdcell_slow_1p08V_125C.lib", [
        base / "verilog/sg13g2_udp.v", base / "verilog/sg13g2_stdcell.v"]


def tool_path(name: str) -> Path:
    executable = shutil.which(name)
    if executable is None:
        raise ValueError(f'missing SPI tool: {name}')
    return Path(executable).resolve()


def python_tool_directory(executable: Path, required: tuple[str, ...]) -> Path:
    """Resolve the installed search order used by SBY/yosys-smtbmc."""
    candidates = [executable.parent / 'share/python3',
                  executable.parent.parent / 'share/yosys/python3']
    # A script-directory module would take precedence over the installed tree.
    if any((executable.parent / name).exists() for name in required):
        raise ValueError(f'shadowed Python tool module beside {executable}')
    selected = next((p for p in candidates if (p / required[0]).is_file()), None)
    if selected is None or any(not (selected / name).is_file() for name in required):
        raise ValueError(f'incomplete Python tool installation: {executable}')
    return selected


def proof_tool_components(executables: dict[str, Path]) -> dict[str, str]:
    """Hash the actual helper programs and installed tool data, excluding caches."""
    yosys = executables['yosys']
    for name in ('yosys-smtbmc', 'yosys-abc'):
        if executables[name] != (yosys.parent / name).resolve():
            raise ValueError(f'mixed Yosys installation: {name}')
    sby_modules = python_tool_directory(executables['sby'], (
        'sby_core.py', 'sby_engine_smtbmc.py', 'sby_cmdline.py', 'sby_mode_bmc.py',
        'sby_mode_cover.py', 'sby_mode_prove.py', 'sby_design.py', 'sby_jobserver.py', 'sby_status.py'))
    yosys_modules = python_tool_directory(executables['yosys-smtbmc'], ('smtio.py', 'ywio.py'))
    paths = set(executables.values())
    for directory in (yosys.parent, yosys.parent.parent / 'share/yosys', sby_modules, yosys_modules):
        paths.update(p for p in directory.rglob('*') if p.is_file()
                     and '__pycache__' not in p.parts and p.suffix not in ('.pyc', '.pyo'))
    return {str(p): digest(p) for p in sorted(paths)}


def proof_environment() -> dict[str, str]:
    # Eliminate user PYTHONPATH/site-module overrides; the scripts append their
    # fingerprinted installation paths. Keep the active pinned venv interpreter.
    return {'PYTHONPATH': '', 'PYTHONNOUSERSITE': '1', 'PYTHONDONTWRITEBYTECODE': '1'}


def external_inputs(pdk: str) -> dict[str, str]:
    slow, models = technology(pdk)
    typical = Path(str(slow).replace('_ss.lib', '_tt.lib').replace(
        '_slow_1p08V_125C.lib', '_typ_1p20V_25C.lib'))
    paths = [slow, typical, *models]
    if pdk == 'ICS55':
        paths += [ROOT / '.cache/retrosoc/sources/ics55_ecos_pll/lib/PLL_TOP_typ.lib',
                  ROOT / 'physical/pdk/icsprout55-pdk/IP/IO/ICsprout_55LLULP1233_IO_251013/liberty/ICSIOA_N55_3P3_tt_1p2_3p3_25c.lib']
    else:
        paths += [ROOT / 'physical/pdk/IHP-Open-PDK/ihp-sg13g2/libs.ref/sg13g2_io/lib/sg13g2_io_typ_1p2V_3p3V_25C.lib']
    executables = {name: tool_path(name) for name in (
        'verilator', 'iverilog', 'vvp', 'sv2v', 'yosys', 'yosys-smtbmc',
        'yosys-abc', 'sta', 'sby', 'bitwuzla', 'python3')}
    paths.append(Path(sys.executable).resolve())
    venv_config = Path(sys.prefix) / 'pyvenv.cfg'
    if venv_config.is_file():
        paths.append(venv_config)
    return {**{str(p): digest(p) for p in paths}, **proof_tool_components(executables)}


def reuse_formal_task(previous: Path, directory: Path, label: str, mode: str,
                      external: dict) -> dict[str, str]:
    """Reuse an intact successful subtask, never the failed enclosing campaign."""
    original = previous / 'record.json'
    record = json.loads(original.read_text())
    if record.get('tool_input_schema') != TOOL_INPUT_SCHEMA:
        raise ValueError('historical proof lacks complete tool-component fingerprints')
    if record.get('phase') != 'SPI-P1' or record.get('stage') != 'formal':
        raise ValueError('not SPI-P1 formal evidence')
    if record.get('external_inputs') != external:
        raise ValueError('formal tools or external inputs changed')
    # Driver/Make/test changes may affect orchestration, but never the model,
    # solver adapter, dependency lock or any other proof-producing source.
    orchestration = {'Makefile', 'scripts/spi_p1.py', 'tests/test_spi_p1.py'}
    old_source = {k: v for k, v in record['source'].items() if k not in orchestration}
    new_source = {k: v for k, v in inputs().items() if k not in orchestration}
    if old_source != new_source:
        raise ValueError('formal source inputs changed')
    artifacts = record['artifacts']
    required = [previous / f'{label}{suffix}' for suffix in ('.v', '.sby', '.json', '.log')]
    required += [previous / label / name for name in
                 ('status', 'config.sby', 'src/design.v', 'model/design_smt2.smt2')]
    if any(str(p) not in artifacts for p in required):
        raise ValueError('formal producer artifact missing from original inventory')
    for name, value in {**artifacts, **external}.items():
        if digest(Path(name)) != value:
            raise ValueError(f'changed formal producer input/artifact: {name}')
    result = json.loads((previous / f'{label}.json').read_text())
    if result.get('status') != 'passed' or result.get('exit_code') != 0:
        raise ValueError('formal subtask command failed')
    if (previous / label / 'status').read_text().split()[0] != 'PASS':
        raise ValueError('formal subtask did not pass')
    model = directory / f'{label}.v'
    if any(digest(p) != digest(model) for p in
           (previous / f'{label}.v', previous / label / 'src/design.v')):
        raise ValueError('formal model differs from actual consumed model')

    def normalized_config(path: Path, design: Path) -> str:
        content = path.read_text()
        line = f'design.v {design}\n'
        if content.count(line) != 1:
            raise ValueError('unexpected formal model mapping')
        return content.replace(line, f'design.v SHA256:{digest(design)}\n')

    candidate = normalized_config(directory / f'{label}.sby', model)
    for config in (previous / f'{label}.sby', previous / label / 'config.sby'):
        if normalized_config(config, previous / f'{label}.v') != candidate:
            raise ValueError('formal configuration changed')
    counts = formal_model_counts((previous / label / 'model/design_smt2.smt2').read_text(), mode)
    dump(directory / f'{label}-properties.json', counts)
    dump(directory / f'{label}-reuse.json', {
        'status': 'passed', 'original_record': str(original), 'original_record_sha256': digest(original),
        'producer_source': record['source'], 'producer_manifest': record['manifest'],
        'producer_result': result, 'model_sha256': digest(model),
        'validation': 'identical consumed model, configuration, inputs and intact artifacts',
        'phase_accepted': False})
    return {**artifacts, str(original): digest(original)}


def formal(directory: Path, external: dict, retained: dict,
           previous: Path | None = None) -> None:
    sources = SOURCES + [ROOT / "tests/rtl/spi_formal.sv", ROOT / "tests/rtl/spi_formal_props.sv"]
    solver = shutil.which('bitwuzla')
    if solver is None:
        raise ValueError('missing locked Bitwuzla solver')
    bindir = directory / 'bin'
    bindir.mkdir()
    wrapper = bindir / 'bitwuzla'
    wrapper.symlink_to(ROOT / 'scripts/bitwuzla_smt2.py')
    for label, mode, depth in [('prove', 'prove', 32), ('register', 'prove', 32),
                               ('bmc', 'bmc', 192), ('cover', 'cover', 320)]:
        defines = [] if mode == 'prove' else ['-DSPI_FORMAL_BOUNDED']
        if label == 'register':
            defines = ['-DSPI_FORMAL_REGISTER']
        converted = subprocess.run(['sv2v', '-E', 'Assert', '-DFORMAL', '-DSV_ASSRT_DISABLE', *defines,
            *[f'-I{p}' for p in INCLUDES], *map(str, sources)],
            capture_output=True, text=True, timeout=180, check=True)
        design = directory / f'{label}.v'
        for keyword in (('assert', 'cover') if mode == 'cover' else ('assert',)):
            if not re.search(rf'\b{keyword}\s*\(', converted.stdout):
                raise ValueError(f'formal conversion removed {keyword} properties')
        atomic_write(design, converted.stdout)
        atomic_write(directory / f'{label}-sv2v.log', converted.stderr)
        config = directory / f'{label}.sby'
        task_timeout = 1200 if mode == 'bmc' else 600
        # The mandatory depth-192 cover witnesses satisfiable assumptions for
        # the whole BMC window; avoid a redundant presat query at every step.
        engine = 'smtbmc --nopresat bitwuzla' if mode == 'bmc' else 'smtbmc --presat --nounroll bitwuzla'
        waveform = 'vcd off\n' if mode == 'cover' else ''
        atomic_write(config, f'[options]\nmode {mode}\ndepth {depth}\ntimeout {task_timeout}\n{waveform}'
            f'\n[engines]\n{engine}\n\n[script]\n'
            'read_verilog -formal -sv design.v\nprep -top spi_formal\nasync2sync\ndffunmap\n'
            f'\n[files]\ndesign.v {design}\n')
        if previous is not None and mode != 'cover':
            retained.update(reuse_formal_task(previous, directory, label, mode, external))
            continue
        execute(directory, label, [str(tool_path('sby')), '--yosys', str(tool_path('yosys')),
                '--smtbmc', str(tool_path('yosys-smtbmc')), '--abc', str(tool_path('yosys-abc')),
                '-d', str(directory / label), str(config)], task_timeout + 60,
                {**proof_environment(), 'PATH': f'{bindir}:{os.environ["PATH"]}',
                 'RETROSOC_BITWUZLA': solver})
        if (directory / label / 'status').read_text().split()[0] != 'PASS':
            raise ValueError(f'formal {mode} did not pass')
        counts = formal_model_counts((directory / label / 'model/design_smt2.smt2').read_text(), mode)
        dump(directory / f'{label}-properties.json', counts)
        if mode == 'cover':
            steps = cover_witness_steps(directory / mode / 'engine_0')
            dump(directory / 'nonvacuity.json', {'bmc_depth': 192, 'witness_steps': steps})


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("stage", choices=("lint", "rtl", "formal", "synth", "netsim", "sta", "report"))
    parser.add_argument("--variant-root", type=Path, required=True)
    parser.add_argument("--pdk", choices=("ICS55", "IHP130"), required=True)
    parser.add_argument("--simulator", choices=("VERILATOR", "IVERILOG"), default="VERILATOR")
    parser.add_argument("--jobs", type=int, default=4)
    parser.add_argument('--common-variant-root', type=Path)
    parser.add_argument('--formal-reuse-root', type=Path,
                        help='original formal stage; reuse only identical successful subtasks')
    args = parser.parse_args()
    variant = args.variant_root.resolve()
    variant.relative_to(ROOT / "build")
    manifest = json.loads((variant / "meta/manifest.json").read_text())
    if manifest["configuration"]["SOC"] != "TINY" or manifest["configuration"]["PDK"] != args.pdk:
        raise ValueError("profile/PDK mismatch")
    phase = variant / "meta/spi-p1"
    suffix = args.stage + (f"-{args.simulator.lower()}" if args.stage == "rtl" else "")
    directory = phase / suffix
    source = inputs()
    retained = {}
    previous = args.formal_reuse_root.resolve() if args.formal_reuse_root else None
    if previous is not None:
        previous.relative_to(ROOT / 'build')
        if args.stage != 'formal':
            raise ValueError('formal reuse is valid only for the formal stage')
    if directory.exists():
        raise ValueError(f"existing attempt: {directory}; use a fresh timestamp")
    directory.mkdir(parents=True)
    record = {"phase": "SPI-P1", "stage": args.stage, "status": "running",
              'tool_input_schema': TOOL_INPUT_SCHEMA,
              "source": source, "manifest": manifest, "phase_accepted": False,
              'external_inputs': external_inputs(args.pdk)}
    dump(directory / "record.json", record)
    with tarfile.open(directory / "sources.tar.gz", "w:gz") as archive:
        for name in source:
            archive.add(ROOT / name, arcname=name)
    try:
        if args.stage == "lint":
            execute(directory, "lint", ["verilator", "--lint-only", "--Wall",
                    verilator_config(directory), "--top-module", TOP,
                    *[f"-I{p}" for p in INCLUDES], *map(str, SOURCES)])
        elif args.stage == "rtl":
            record['cases'] = list(CASES)
            for top in CASES:
                simulate(directory, args.simulator, top, args.jobs)
        elif args.stage == "synth":
            synth(directory, args.pdk)
        elif args.stage in ("netsim", "sta"):
            checked_record(phase / "synth/record.json", source)
            netlist = phase / "synth/out/netlist.v"
            liberty, models = technology(args.pdk)
            if args.stage == "netsim":
                simulate(directory, "IVERILOG", "spi_netlist_tb", args.jobs, netlist, models)
            else:
                execute(directory, "sta", ["sta", "-exit", str(ROOT /
                    "physical/smoke/sta/opensta/spi_block.tcl")], environment={
                    "SPI_NETLIST": str(netlist), "SPI_LIBERTY": str(liberty),
                    "SPI_REPORT_DIR": str(directory)})
        elif args.stage == "formal":
            formal(directory, record['external_inputs'], retained, previous)
        else:
            common = (args.common_variant_root.resolve() / 'meta/spi-p1'
                      if args.common_variant_root else phase)
            record["stages"] = {name: checked_record(
                (common if name in ('lint', 'rtl-verilator', 'rtl-iverilog', 'formal') else phase) /
                name / 'record.json', source) for name in
                ('lint', 'rtl-verilator', 'rtl-iverilog', 'formal', 'synth', 'netsim', 'sta')}
        if source != inputs():
            raise ValueError("source changed during execution")
        if record['external_inputs'] != external_inputs(args.pdk):
            raise ValueError('external SPI inputs changed during execution')
        record["status"] = "passed"
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        record.update(status="failed", error=str(error))
        print(error, file=sys.stderr)
        return 1
    finally:
        record["artifacts"] = {**retained, **{str(p): digest(p) for p in directory.rglob("*")
                               if p.is_file() and p.name != "record.json"}}
        dump(directory / "record.json", record)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
