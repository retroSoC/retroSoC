"""Whole-book diagram coverage, binary structures, operand rules and footer behavior."""
from __future__ import annotations

import copy
import os
import shutil
import subprocess
from dataclasses import replace
from pathlib import Path

import pytest

from publications.build_datasheet import CONFIG, collect_data, read_json
from publications.circuit_reference import validate_instance_connections
from publications.diagram_coverage import inventory, validate_usage
from publications.format_reference import structure_fields
from publications.report_changes import REPOSITORY_URL, repository_footer_pages
from publications.storage_reference import fifo_geometry, linker_sections, validate_ranges
from scripts import apu_isa as isa

ROOT = Path(__file__).resolve().parents[1]


@pytest.fixture(scope="module")
def diagrams():
    return collect_data(read_json(CONFIG), check_snapshot=False)["system_reference"]["illustrations"]


def test_every_frozen_chapter_has_explicit_diagram_coverage(diagrams):
    contract = read_json(ROOT / "publications/datasheets/structure-contract.json")
    rows = diagrams["coverage"]
    assert len(rows) == len(contract["entries"]) == 107
    expected = inventory(diagrams)
    for row in rows:
        assert {key: row[key] for key in ("level", "title", "anchor")} == contract["entries"][row["index"]]
        for category in row["categories"].values():
            assert category["reason"]
            assert set(category["diagrams"]) <= expected.keys()
            assert category["sources"] or category["status"] == "not_applicable"
    assert len(diagrams["circuits"]) == 44
    assert len(diagrams["layouts"]) == 37
    assert len(diagrams["storage"]) == 40
    assert len(expected) == 131
    for identifier in contract["ip_ids"]:
        row = next(row for row in rows if row["anchor"] == identifier)
        assert row["categories"]["circuiteria"]["diagrams"] == ["circuiteria:" + identifier]


@pytest.mark.parametrize("mutation", ["missing", "duplicate", "unknown", "bad-page"])
def test_declared_but_unused_or_duplicate_diagrams_fail_build(diagrams, mutation):
    records = [{**item, "page": index + 1} for index, item in enumerate(inventory(diagrams).values())]
    assert len(validate_usage(diagrams, records)) == 131
    if mutation == "missing":
        records.pop()
    elif mutation == "duplicate":
        records.append(records[0])
    elif mutation == "unknown":
        records[0]["id"] = "not-in-the-book"
    else:
        records[0]["page"] = 0
    with pytest.raises(ValueError):
        validate_usage(diagrams, records)


def test_all_62_opcodes_have_legal_source_encoded_examples_and_zero_slots(diagrams):
    families = diagrams["apu"]["families"]
    assert [len(row["operations"]) for row in families] == [9, 14, 8, 7, 7, 10, 7]
    for family in families:
        for operation in family["operations"]:
            instruction = isa.Instruction(**operation["values"])
            assert f"0x{instruction.encode():016X}" == operation["word"]
            assert isa.Instruction.decode(instruction.encode()) == instruction
            isa.validate_instruction(instruction, "p5")
            for field, value in operation["fixed"].items():
                assert value == 0
                with pytest.raises(ValueError):
                    isa.validate_instruction(replace(instruction, **{field: 1}), "p5")
    control = families[0]
    wait = next(row for row in control["operations"] if row["name"] == "WAIT")
    assert wait["targets"] == "P4/P5"
    assert next(row for row in families[-1]["operations"] if row["name"] == "EVENT")["active"] == ["predicate", "immediate"]


def test_structures_expand_arrays_and_preserve_mixed_ownership(diagrams):
    apu = diagrams["layouts"]["apu-descriptor"]
    assert len(apu["fields"]) == 32 and apu["bits"] == 1024
    assert [row["offset"] for row in apu["fields"] if row["member"] == "reserved"] == list(range(96, 128, 4))
    assert [row["name"] for row in apu["fields"] if row["member"] == "cookie"] == ["cookie[0]", "cookie[1]"]
    sdio = diagrams["layouts"]["sdio-descriptor"]
    assert sdio["fields"][-1]["role"] == "mixed"
    assert diagrams["layouts"]["hp-bundle-header"]["bits"] == 256
    assert diagrams["layouts"]["hp-bundle-entry"]["bits"] == 192


@pytest.mark.parametrize("declaration", ["uint32_t reserved[3];", "uint32_t reserved[0];", "void *reserved;"])
def test_binary_structure_changes_require_review(tmp_path, declaration):
    (tmp_path / "layout.h").write_text("typedef struct { uint32_t first; " + declaration + " } sample_t;")
    with pytest.raises(ValueError):
        structure_fields(tmp_path, {"file": "layout.h", "name": "sample_t", "bytes": 12})


def test_fifo_geometry_reads_parameters_and_rejects_non_power_of_two(tmp_path):
    file = tmp_path / "fifo_top.sv"
    file.write_text("module fifo_top; parameter int N = 8; fifo #(.DATA_WIDTH(37), .BUFFER_DEPTH(N)) u_fifo (.dat_i(data)); endmodule")
    store = {"file": "fifo_top.sv", "instance": "u_fifo"}
    assert fifo_geometry(tmp_path, store) == (8, 37)
    assert fifo_geometry(tmp_path, {**store, "parameters": {"N": 32}}) == (32, 37)
    file.write_text(file.read_text().replace("N = 8", "N = 3"))
    with pytest.raises(ValueError, match="power-of-two"):
        fifo_geometry(tmp_path, store)


def test_storage_geometry_preserves_product_overrides_and_sidebands(diagrams):
    stores = diagrams["storage"]
    assert [(s["depth"], s["bits"]) for s in stores["dma-channel-fifos"]["stores"]] == [(32, 32)]
    assert [(s["depth"], s["bits"]) for s in stores["sdio-pio"]["stores"]] == [(4, 36), (1, 32)]
    assert [(s["depth"], s["bits"]) for s in stores["apu-fifos"]["stores"]] == [(64, 41), (64, 41)]
    assert [(s["depth"], s["bits"]) for s in stores["opi-lines"]["stores"]] == [(4, 256)]
    assert sum(row["bytes"] for row in stores["apu-local"]["ranges"]) == 114688
    assert stores["linker-ld2_psram"]["stack_region"] == "PSRAM"
    assert stores["linker-ld2_all_sram"]["stack_region"] == "SRAM"


def test_jtag_linker_keeps_init_inside_text_and_bss_without_load_payload():
    sections = linker_sections(ROOT, "crt/linker/jtag_sram.lds")
    assert len(sections) == 3
    assert sections[0]["name"] == ".text" and sections[0]["includes_init"]
    assert all(row["vma"] == "SRAM" for row in sections)
    assert sections[-1]["initialization"] == "zero"


@pytest.mark.parametrize("rows", [
    [{"base": 16, "bytes": 16}, {"base": 20, "bytes": 4}],
    [{"base": (1 << 32) - 2, "bytes": 4}],
    [{"base": -1, "bytes": 8}],
    [{"base": 0, "bytes": 0}],
])
def test_storage_ranges_reject_overlap_overflow_and_invalid_sizes(rows):
    with pytest.raises(ValueError):
        validate_ranges(copy.deepcopy(rows))


def test_circuit_direction_is_checked_against_module_declaration(tmp_path):
    (tmp_path / "wrapper.sv").write_text("module wrapper; src u_src(.data_o(shared)); sink u_sink(.data_i(shared)); endmodule")
    (tmp_path / "src.sv").write_text("module src(\noutput logic [31:0] data_o\n); endmodule")
    (tmp_path / "sink.sv").write_text("module sink(\ninput logic [31:0] data_i\n); endmodule")
    circuit = {"nodes": [{"id": name, "instance_source": {"file": "wrapper.sv", "name": "u_" + name,
                 "module": name, "declaration_file": name + ".sv"}} for name in ("src", "sink")],
               "edges": [{"from": "src.out", "to": "sink.in", "instance_ports": [
                   {"node": "src", "port": "data_o", "expression": "shared"},
                   {"node": "sink", "port": "data_i", "expression": "shared"}]}]}
    validate_instance_connections(tmp_path, circuit)
    (tmp_path / "src.sv").write_text("module src(\ninput logic [31:0] data_o\n); endmodule")
    with pytest.raises(ValueError, match="direction"):
        validate_instance_connections(tmp_path, circuit)


def test_only_repository_links_in_the_footer_are_global_footer_changes():
    class Ref(dict):
        def get_object(self):
            return self

    class Reader:
        pages = [
            {"/Annots": [Ref({"/A": {"/URI": REPOSITORY_URL}, "/Rect": [54, 15, 230, 28]})]},
            {"/Annots": [Ref({"/A": {"/URI": REPOSITORY_URL}, "/Rect": [54, 300, 230, 315]})]},
            {"/Annots": [Ref({"/A": {"/URI": REPOSITORY_URL + "/issues"}, "/Rect": [54, 15, 230, 28]})]},
        ]
    assert repository_footer_pages(Reader()) == [1]


def test_all_descriptor_diagrams_match_c_layout(tmp_path, diagrams):
    if os.name == "nt":
        pytest.skip("C layout comparison runs on the Linux host")
    cc = shutil.which("cc") or shutil.which("gcc")
    if cc is None:
        pytest.skip("host C compiler unavailable")
    generated = tmp_path / "retrosoc/generated"
    generated.mkdir(parents=True)
    for name in ("memory_map.h", "user_extensions.h"):
        (generated / name).write_text("/* No MMIO is executed. */\n")
    layouts = [record for record in diagrams["layouts"].values() if record.get("structure")]
    includes = sorted({record["structure"]["file"].removeprefix("crt/include/") for record in layouts})
    program = "#include <stddef.h>\n" + "".join(f"#include <{header}>\n" for header in includes)
    for record in layouts:
        name = record["structure"]["name"]
        program += f'_Static_assert(sizeof({name}) == {record["bits"] // 8}, "structure size");\n'
        for field in record["fields"]:
            index = field.get("array_index")
            actual = f"offsetof({name}, {field['member']})" + (f" + {index} * {field['bits'] // 8}" if index is not None else "")
            program += f'_Static_assert({actual} == {field["offset"]}, "member offset");\n'
    source = tmp_path / "descriptors.c"
    source.write_text(program + "int main(void) { return 0; }\n")
    subprocess.run([cc, "-std=c11", "-Wall", "-Wextra", "-Werror", "-I", str(ROOT / "crt/include"),
                    "-I", str(tmp_path), str(source), "-o", str(tmp_path / "descriptors")], check=True, capture_output=True, text=True)
