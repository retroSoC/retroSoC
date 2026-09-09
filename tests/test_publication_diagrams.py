"""Representative diagram geometry, source bindings and multi-version package integrity."""
from __future__ import annotations

import copy
import json
import os
import shutil
import subprocess
from pathlib import Path

import pytest

from publications import diagram_reference as dr
from publications import package_reference as pr
from publications.build_datasheet import CONFIG, collect_data, read_json
from scripts.dependency_lock import load_lock

ROOT = Path(__file__).resolve().parents[1]
SPEC = read_json(ROOT / "publications/datasheets/system-reference.json")["illustrations"]


@pytest.fixture(scope="module")
def data():
    return collect_data(read_json(CONFIG), check_snapshot=False)


@pytest.fixture
def source_tree(tmp_path):
    for relative in dr.dependencies(SPEC):
        target = tmp_path / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(ROOT / relative, target)
    return tmp_path


def replace(root: Path, relative: str, old: str, new: str) -> None:
    path = root / relative
    source = path.read_text(encoding="utf-8")
    assert old in source
    path.write_text(source.replace(old, new), encoding="utf-8")


def test_representative_inventory_uses_actual_widths_and_addresses(data):
    value = data["system_reference"]["illustrations"]
    assert sum(f["bits"] for f in value["dma_tcd"]) == 512
    assert [f["offset"] for f in value["dma_tcd"] if f["name"] == "y_count"] == [24]
    assert [f["bits"] for f in value["sdio_command"]] == [1, 1, 6, 32, 7, 1]
    assert value["apu"]["examples"][0]["word"] == "0x1101000012345678"
    assert value["apu"]["examples"][1]["word"] == "0x0800000000000000"
    assert value["uart_fifo"] == {"tx": {"depth": 64, "bits": 8}, "rx": {"depth": 64, "bits": 12}}
    assert next(row for row in value["windows"] if row["symbol"] == "SRAM")["size"] == 32768
    assert value["cache"] == {"granule": 64, "offset": 16, "length": 64, "end": 80, "covered_bytes": 128}
    assert set(value["circuits"]) == {"uart0", "dma", "apu"}


@pytest.mark.parametrize("mutation", ["gap", "overlap", "oversize", "duplicate"])
def test_field_coverage_rejects_invalid_diagrams(mutation):
    fields = copy.deepcopy(SPEC["sdio_command"])
    if mutation == "gap":
        fields.pop()
    elif mutation == "overlap":
        fields[-1]["lsb"] = 1
    elif mutation == "oversize":
        fields[0]["bits"] = 2
    else:
        fields[-1]["name"] = fields[0]["name"]
    with pytest.raises(ValueError):
        dr.validate_fields(fields, 48)


def test_protocol_field_order_is_checked_even_with_complete_coverage(data):
    spec = copy.deepcopy(SPEC)
    spec["sdio_command"][0], spec["sdio_command"][-1] = spec["sdio_command"][-1], spec["sdio_command"][0]
    with pytest.raises(ValueError, match="field order"):
        dr.collect_diagrams(ROOT, spec, data["regions"])


@pytest.mark.parametrize("relative,old,new", [
    ("rtl/ip/storage/sdio_command.sv", "cmd_index_i,", "other_index_i,"),
    ("rtl/ip/serial/uart_reg.sv", ".DATA_WIDTH      (12)", ".DATA_WIDTH      (16)"),
    ("rtl/ip/serial/uart_reg.sv", "TxFifoDepth    = 64", "TxFifoDepth    = 32"),
    ("scripts/apu_isa.py", "(self.dst, 4, 48)", "(self.dst, 4, 47)"),
    ("scripts/apu_isa.py", "APUMC_MAX_INSTRUCTIONS = 2048", "APUMC_MAX_INSTRUCTIONS = 4096"),
    ("app/ports/linux/linux/retrosoc_hp.dts", "riscv,cbom-block-size = <64>", "riscv,cbom-block-size = <128>"),
])
def test_source_drift_requires_diagram_review(source_tree, data, relative, old, new):
    replace(source_tree, relative, old, new)
    with pytest.raises(ValueError):
        dr.collect_diagrams(source_tree, SPEC, data["regions"])


@pytest.mark.parametrize("mutation", ["node", "port", "endpoint", "direction", "width", "binding", "duplicate-edge"])
def test_circuit_records_reject_invented_or_inconsistent_connections(mutation):
    circuit = copy.deepcopy(SPEC["circuits"]["uart0"])
    if mutation == "node":
        circuit["nodes"].append(circuit["nodes"][0])
    elif mutation == "port":
        circuit["nodes"][0]["ports"].append(circuit["nodes"][0]["ports"][0])
    elif mutation == "endpoint":
        circuit["edges"][0]["to"] = "missing.input"
    elif mutation == "direction":
        circuit["nodes"][0]["ports"][0]["direction"] = "in"
    elif mutation == "width":
        circuit["nodes"][0]["ports"][0]["width"] = 64
    elif mutation == "binding":
        circuit["edges"][0]["bindings"][0]["text"] = ".nonexistent(nonexistent)"
    else:
        circuit["edges"].append(circuit["edges"][0])
    with pytest.raises(ValueError):
        dr.validate_circuit(ROOT, circuit)


def test_memory_window_labels_cannot_disagree_with_numeric_bounds(data):
    regions = copy.deepcopy(data["regions"])
    next(row for row in regions if row["symbol"] == "SRAM")["end_hex"] = "0xFFFFFFFF"
    with pytest.raises(ValueError, match="range labels"):
        dr.collect_diagrams(ROOT, SPEC, regions)


def test_both_package_versions_are_locked_and_permitted():
    records = pr.package_records(load_lock())
    ids = {row["identity"] for row in records}
    assert {"cetz:0.3.4", "cetz:0.5.2", "oxifmt:0.2.1", "oxifmt:1.0.0"} <= ids
    assert len(ids) == len(records) == 11
    pr.validate_imports('#import "@preview/cetz:0.5.2"\n#import "@preview/cetz:0.3.4"', records)
    with pytest.raises(ValueError, match="unlocked"):
        pr.validate_imports('#import "@preview/cetz:0.3.3"', records)


def test_duplicate_package_identity_is_rejected():
    lock = copy.deepcopy(load_lock())
    lock["archives"]["typst_cetz_0_3_4"] = copy.deepcopy(lock["archives"]["typst_cetz"])
    lock["archives"]["typst_cetz_0_3_4"]["package_name"] = "cetz"
    with pytest.raises(ValueError, match="duplicate"):
        pr.package_records(lock)


@pytest.fixture
def cached_package(tmp_path):
    directory = tmp_path / "package"
    directory.mkdir()
    (directory / "typst.toml").write_text('[package]\nname="example"\nversion="1.0.0"\nentrypoint="lib.typ"\n')
    (directory / "lib.typ").write_text('#import "src/runtime.typ"\n// #import "missing.typ"\n')
    (directory / "src").mkdir()
    (directory / "src/runtime.typ").write_text('#import "/helper.typ"\n')
    (directory / "helper.typ").write_text('#import "@preview/cetz:0.3.4"\n')
    (directory / "manual.typ").write_text('#import "@preview/unneeded-manual-package:9.9.9"\n')
    record = {"name": "example", "version": "1.0.0", "identity": "example:1.0.0", "destination": "package", "sha256": "0" * 64}
    marker = directory / ".manifest.json"
    marker.write_text(json.dumps({"archive": record["sha256"], "files": pr.directory_hashes(directory)}))
    return tmp_path, directory, record


def test_runtime_graph_excludes_manuals_and_resolves_package_root(cached_package):
    root, directory, record = cached_package
    assert pr.checked_package(root, record) == directory
    assert pr.runtime_imports(directory) == {"cetz:0.3.4"}


@pytest.mark.parametrize("mutation", ["missing-marker", "changed-file", "missing-file", "archive"])
def test_missing_or_tampered_package_caches_are_rejected(cached_package, mutation):
    root, directory, record = cached_package
    if mutation == "missing-marker":
        (directory / ".manifest.json").unlink()
    elif mutation == "changed-file":
        (directory / "helper.typ").write_text("changed")
    elif mutation == "missing-file":
        (directory / "helper.typ").unlink()
    else:
        record["sha256"] = "1" * 64
    with pytest.raises(ValueError, match="missing or modified"):
        pr.checked_package(root, record)


def test_offline_closure_rejects_an_unlocked_runtime_dependency(cached_package):
    root, _, record = cached_package
    with pytest.raises(ValueError, match="unlocked runtime"):
        pr.validate_package_closure(root, [record])


def test_missing_local_runtime_import_is_rejected(cached_package):
    _, directory, _ = cached_package
    (directory / "helper.typ").unlink()
    with pytest.raises(ValueError, match="missing or escapes"):
        pr.runtime_imports(directory)


def test_tcd_diagram_matches_actual_c_offsets(tmp_path):
    if os.name == "nt":
        pytest.skip("C layout comparison runs in the Linux host environment")
    cc = shutil.which("cc") or shutil.which("gcc")
    if cc is None:
        pytest.skip("host C compiler unavailable")
    generated = tmp_path / "retrosoc/generated"
    generated.mkdir(parents=True)
    (generated / "memory_map.h").write_text("/* No MMIO is executed. */\n")
    (generated / "user_extensions.h").write_text("/* No selectors are executed. */\n")
    fields = dr.dma_fields(ROOT)
    program = '#include <stdio.h>\n#include <stddef.h>\n#include <retrosoc/hal/dma.h>\nint main(void) {\n'
    for row in fields:
        name = row["name"]
        program += f'printf("%zu %zu\\n", offsetof(rs_dma_tcd_t,{name}), sizeof(((rs_dma_tcd_t*)0)->{name}));\n'
    program += 'return 0; }\n'
    source, exe = tmp_path / "offsets.c", tmp_path / "offsets"
    source.write_text(program)
    subprocess.run([cc, "-std=c11", "-Wall", "-Wextra", "-Werror", "-I", str(ROOT / "crt/include"),
                    "-I", str(tmp_path), str(source), "-o", str(exe)], check=True, capture_output=True, text=True)
    values = subprocess.check_output([str(exe)], text=True).splitlines()
    assert [tuple(map(int, line.split())) for line in values] == [(f["offset"], f["bits"] // 8) for f in fields]
