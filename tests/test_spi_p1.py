"""SPI-P1 evidence must fail closed on command, marker and input drift."""
import json
from pathlib import Path
import shutil

import pytest

from scripts import spi_p1 as spi


@pytest.mark.parametrize('suffix', ['FAILED', 'FATAL', 'assertion failed', '%Error',
                                   'SIM_TEST_FAIL', 'SIM_TEST_TIMEOUT'])
def test_spi_rejects_error_after_success(suffix):
    with pytest.raises(ValueError):
        spi.require_pass(f'SPI_P1_PASS case\n{suffix}',
                         {'status': 'passed', 'exit_code': 0}, 'SPI_P1_PASS case')


@pytest.mark.parametrize('result', [{'status': 'failed', 'exit_code': 0},
                                   {'status': 'passed', 'exit_code': 1}])
def test_spi_rejects_failed_command(result):
    with pytest.raises(ValueError):
        spi.require_pass('SPI_P1_PASS case', result, 'SPI_P1_PASS case')


def test_spi_requires_exactly_one_terminal():
    result = {'status': 'passed', 'exit_code': 0}
    spi.require_pass('SPI_P1_PASS case', result, 'SPI_P1_PASS case')
    for text in ('', 'SPI_P1_PASS case\nSPI_P1_PASS case'):
        with pytest.raises(ValueError):
            spi.require_pass(text, result, 'SPI_P1_PASS case')


def test_spi_retained_evidence_requires_same_source_and_artifact(tmp_path, monkeypatch):
    tool = tmp_path / 'tool'
    tool.write_text('original executable')
    external = {str(tool): spi.digest(tool)}
    monkeypatch.setattr(spi, 'external_inputs', lambda pdk: external)
    log = tmp_path / 'log'
    log.write_text('original')
    record = tmp_path / 'record.json'
    record.write_text(json.dumps({'status': 'passed', 'source': {'rtl': 'one'},
                                 'tool_input_schema': spi.TOOL_INPUT_SCHEMA,
                                 'manifest': {'configuration': {'PDK': 'ICS55'}},
                                 'external_inputs': external,
                                 'artifacts': {str(log): spi.digest(log)}}))
    assert spi.checked_record(record, {'rtl': 'one'})['status'] == 'passed'
    with pytest.raises(ValueError):
        spi.checked_record(record, {'rtl': 'two'})
    log.write_text('changed')
    with pytest.raises(ValueError):
        spi.checked_record(record, {'rtl': 'one'})


def test_spi_input_inventory_includes_headers_and_oracle():
    sources = spi.inputs()
    for name in ('rtl/ip/serial/spi_define.svh', 'tests/rtl/spi_pin_bfm.sv',
                 'tests/rtl/spi_test_body.svh', 'dependencies/dependencies.lock.json',
                 'crt/include/retrosoc/hal/spi_regs.h'):
        assert name in sources and (spi.ROOT / Path(name)).is_file()


def test_yosys_timestamp_prefix_is_not_json_corruption(tmp_path):
    report = tmp_path / 'stat.json'
    report.write_text('[00001.123456] {\n[00001.123457] "modules": {}\n[00001.123458] }\n')
    assert spi.yosys_json(report) == {'modules': {}}
    report.write_text('[00001.123456] {"modules": broken}')
    with pytest.raises(ValueError):
        spi.yosys_json(report)


@pytest.mark.parametrize('mode', ['prove', 'bmc', 'cover'])
def test_empty_formal_model_cannot_pass(mode):
    with pytest.raises(ValueError):
        spi.formal_model_counts('; no properties\n', mode)
    keyword = 'cover' if mode == 'cover' else 'assert'
    assert spi.formal_model_counts(f'; yosys-smt2-{keyword} 0 property\n', mode)[keyword] == 1


def test_short_cover_witness_cannot_qualify_the_full_window(tmp_path):
    witness=tmp_path/'trace0.yw'
    witness.write_text(json.dumps({'steps': [{}]*10}))
    with pytest.raises(ValueError):
        spi.cover_witness_steps(tmp_path)
    witness.write_text(json.dumps({'steps': [{}]*193}))
    assert spi.cover_witness_steps(tmp_path)==193


@pytest.mark.parametrize('drift', ['none', 'model', 'consumed', 'config', 'tool',
                                  'artifact', 'command', 'status', 'vacuous', 'source', 'inventory',
                                  'old_schema', 'missing_tool'])
def test_formal_reuse_requires_exact_successful_producer(tmp_path, monkeypatch, drift):
    previous, current = tmp_path / 'old', tmp_path / 'new'
    previous.mkdir()
    current.mkdir()
    (previous / 'bmc/src').mkdir(parents=True)
    (previous / 'bmc/model').mkdir()
    for root in (previous, current):
        (root / 'bmc.v').write_text('module spi_formal; endmodule\n')
        (root / 'bmc.sby').write_text(f'[options]\nmode bmc\ndepth 192\n[files]\ndesign.v {root}/bmc.v\n')
    shutil.copyfile(previous / 'bmc.v', previous / 'bmc/src/design.v')
    shutil.copyfile(previous / 'bmc.sby', previous / 'bmc/config.sby')
    (previous / 'bmc/status').write_text('PASS 0 192\n')
    (previous / 'bmc/model/design_smt2.smt2').write_text('; yosys-smt2-assert 0 property\n')
    (previous / 'bmc.json').write_text(json.dumps({'status': 'passed', 'exit_code': 0}))
    (previous / 'bmc.log').write_text('original producer log')
    tool = tmp_path / 'tool'
    tool.write_text('tool')
    external = {str(tool): spi.digest(tool)}
    source = {'rtl.sv': 'rtl', 'scripts/spi_p1.py': 'old-driver'}
    monkeypatch.setattr(spi, 'inputs', lambda: {**source, 'scripts/spi_p1.py': 'new-driver'})
    if drift == 'command':
        (previous / 'bmc.json').write_text(json.dumps({'status': 'failed', 'exit_code': 1}))
    if drift == 'status':
        (previous / 'bmc/status').write_text('FAIL\n')
    if drift == 'vacuous':
        (previous / 'bmc/model/design_smt2.smt2').write_text('; no properties\n')
    if drift == 'consumed':
        (previous / 'bmc/src/design.v').write_text('different consumed model')
    record = {'phase': 'SPI-P1', 'stage': 'formal', 'status': 'failed',
              'tool_input_schema': spi.TOOL_INPUT_SCHEMA,
              'source': dict(source), 'manifest': {'producer': 'original'},
              'external_inputs': external,
              'artifacts': {str(p): spi.digest(p) for p in previous.rglob('*') if p.is_file()}}
    if drift == 'old_schema':
        record.pop('tool_input_schema')
    if drift == 'missing_tool':
        record['external_inputs'] = {}
    if drift == 'source':
        record['source']['rtl.sv'] = 'different'
    if drift == 'inventory':
        record['artifacts'].pop(str(previous / 'bmc/src/design.v'))
    (previous / 'record.json').write_text(json.dumps(record))
    if drift == 'tool':
        tool.write_text('changed tool')
    if drift == 'model':
        (current / 'bmc.v').write_text('changed model')
    if drift == 'config':
        config = current / 'bmc.sby'
        config.write_text(config.read_text().replace('depth 192', 'depth 1'))
    if drift == 'artifact':
        (previous / 'bmc.log').write_text('changed log')
    if drift == 'none':
        retained = spi.reuse_formal_task(previous, current, 'bmc', 'bmc', external)
        assert str(previous / 'record.json') in retained
        reuse = json.loads((current / 'bmc-reuse.json').read_text())
        assert reuse['producer_source']['scripts/spi_p1.py'] == 'old-driver'
        assert reuse['phase_accepted'] is False
    else:
        with pytest.raises(ValueError):
            spi.reuse_formal_task(previous, current, 'bmc', 'bmc', external)


@pytest.fixture
def proof_installation(tmp_path):
    paths = {}
    for tool in ('yosys', 'yosys-smtbmc', 'yosys-abc', 'sby'):
        root = tmp_path / ('sby' if tool == 'sby' else 'yosys')
        executable = root / 'bin' / tool
        executable.parent.mkdir(parents=True, exist_ok=True)
        executable.write_text(f'original {tool}')
        paths[tool] = executable
    for owner, modules in [('sby', ('sby_core', 'sby_engine_smtbmc', 'sby_cmdline', 'sby_mode_bmc',
                                   'sby_mode_cover', 'sby_mode_prove', 'sby_design', 'sby_jobserver',
                                   'sby_status')), ('yosys', ('smtio', 'ywio'))]:
        directory = tmp_path / owner / 'share/yosys/python3'
        directory.mkdir(parents=True)
        for name in modules:
            (directory / f'{name}.py').write_text(f'# original {name}')
    return paths


@pytest.mark.parametrize('component', ['yosys-smtbmc', 'yosys-abc', 'sby_engine_smtbmc.py',
                                      'sby_core.py', 'smtio.py', 'ywio.py'])
def test_helper_drift_changes_fingerprint(proof_installation, component):
    before = spi.proof_tool_components(proof_installation)
    path = next(Path(name) for name in before if Path(name).name == component)
    path.write_text('changed component without changing launcher')
    after = spi.proof_tool_components(proof_installation)
    assert before != after and before[str(path)] != after[str(path)]


@pytest.mark.parametrize('component', ['sby_engine_smtbmc.py', 'smtio.py', 'ywio.py'])
def test_missing_helper_fails_closed(proof_installation, component):
    before = spi.proof_tool_components(proof_installation)
    next(Path(name) for name in before if Path(name).name == component).unlink()
    with pytest.raises(ValueError, match='incomplete Python tool installation'):
        spi.proof_tool_components(proof_installation)


def test_module_search_shadow_is_rejected(proof_installation):
    (proof_installation['sby'].parent / 'sby_core.py').write_text('# shadow')
    with pytest.raises(ValueError, match='shadowed'):
        spi.proof_tool_components(proof_installation)


def test_mixed_yosys_helper_is_rejected(proof_installation, tmp_path):
    alternate = tmp_path / 'other-abc'
    alternate.write_text('other')
    proof_installation['yosys-abc'] = alternate
    with pytest.raises(ValueError, match='mixed Yosys'):
        spi.proof_tool_components(proof_installation)


def test_new_component_changes_inventory_but_python_cache_does_not(proof_installation):
    before = spi.proof_tool_components(proof_installation)
    root = proof_installation['sby'].parent.parent / 'share/yosys/python3'
    cache = root / '__pycache__'
    cache.mkdir()
    (cache / 'sby_core.pyc').write_bytes(b'cache')
    assert spi.proof_tool_components(proof_installation) == before
    (root / 'sby_new_helper.py').write_text('# new consumed module')
    assert spi.proof_tool_components(proof_installation) != before


def test_incomplete_record_inventory_cannot_pass(tmp_path, monkeypatch):
    monkeypatch.setattr(spi, 'external_inputs', lambda pdk: {'required-component': 'hash'})
    path = tmp_path / 'record.json'
    path.write_text(json.dumps({'status': 'passed', 'source': {}, 'artifacts': {},
                               'tool_input_schema': spi.TOOL_INPUT_SCHEMA,
                               'manifest': {'configuration': {'PDK': 'ICS55'}},
                               'external_inputs': {}}))
    with pytest.raises(ValueError, match='incomplete SPI tool/input inventory'):
        spi.checked_record(path, {})


@pytest.mark.parametrize('simulator', ['VERILATOR', 'IVERILOG'])
@pytest.mark.parametrize('top', spi.CASES)
def test_spi_standalone_protocol(tmp_path, simulator, top):
    required = ['verilator'] if simulator == 'VERILATOR' else ['iverilog','vvp','sv2v']
    for tool in required:
        assert shutil.which(tool), f'required SPI verification tool missing: {tool}'
    spi.simulate(tmp_path, simulator, top, 4)
