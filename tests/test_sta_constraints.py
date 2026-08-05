"""Tests for generated core-STA constraints."""

from __future__ import annotations

import hashlib
import io
import json
import subprocess
import sys
import tarfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DOMAINS = ROOT / "rtl/mini/integration/clock_reset_domains.json"
PIN_MAP = ROOT / "rtl/mini/pin_map/pin_map.json"
GENERATOR = ROOT / "sta/opensta/generate_sdc.py"
OPENSTA_MAKEFILE = ROOT / "sta/opensta/opensta.mk"
GF180_GENERATOR = ROOT / "pdk/generate_gf180_liberty.py"
ICS55_PREPARER = ROOT / "pdk/prepare_ics55_liberty.py"
ICS55_SIM_MODEL_PREPARER = ROOT / "pdk/prepare_ics55_sim_model.py"


def generate(domains: Path, output: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [
            sys.executable,
            str(GENERATOR),
            "--domains",
            str(domains),
            "--pin-map",
            str(PIN_MAP),
            "--output",
            str(output),
        ],
        text=True,
        capture_output=True,
    )


def test_core_sdc_covers_current_clock_domains(tmp_path: Path) -> None:
    output = tmp_path / "retrosoc_core.sdc"
    result = generate(DOMAINS, output)

    assert result.returncode == 0, result.stderr
    sdc = output.read_text(encoding="utf-8")
    assert "create_clock -name clk_external -period 13.888888889" in sdc
    assert "create_generated_clock -name clk_system" in sdc
    assert "create_clock -name clk_audio -period 54.253472222" in sdc
    assert "create_clock -name clk_jtag -period 100" in sdc
    assert "create_clock -name clk_dvp -period 41.666666667" in sdc
    assert "get_pins -quiet" in sdc
    assert "get_ports -quiet" in sdc
    assert "set clk_jtag_port [require_ports \"clock jtag\" {jtag_tck_i_pad}]" in sdc
    assert "u_retrosoc.u_ip_ribp_wrapper.u_rib_dvp.u_dvp_pclk_clk_buf/clk_o" in sdc
    assert "-group [get_clocks {clk_external clk_system}]" in sdc
    assert "set_clock_transition 0.1 [get_clocks {clk_dvp}]" in sdc
    assert "set_input_transition" not in sdc
    assert "set_false_path -from $reset_ext_rst_n_i_pad" in sdc


def test_opensta_invocation_exits_after_a_tcl_error() -> None:
    makefile = OPENSTA_MAKEFILE.read_text(encoding="utf-8")

    assert "$(OPENSTA) -no_init -exit -threads $(OPENSTA_THREADS)" in makefile


def test_core_sdc_rejects_pads_missing_from_the_pin_map(tmp_path: Path) -> None:
    document = json.loads(DOMAINS.read_text(encoding="utf-8"))
    document["domains"][3]["sta"]["source_port"] = "missing_pad"
    invalid = tmp_path / "clock_reset_domains.json"
    invalid.write_text(json.dumps(document), encoding="utf-8")

    result = generate(invalid, tmp_path / "retrosoc_core.sdc")

    assert result.returncode != 0
    assert "source port is not declared in pin map" in result.stderr


def test_gf180_liberty_generator_assembles_requested_io_cells(tmp_path: Path) -> None:
    library = "gf180mcu_fd_io"
    corner = "ss_125C_4v50"
    source = tmp_path / "source"
    library_dir = source / "libraries" / library / "latest"
    liberty_dir = library_dir / "liberty"
    cells_dir = library_dir / "cells"
    liberty_dir.mkdir(parents=True)
    (liberty_dir / f"{library}__{corner}.lib").write_text(
        "library (gf180_io) {\n}\n", encoding="utf-8"
    )
    for cell in ("bi_t", "in_c"):
        cell_dir = cells_dir / cell
        cell_dir.mkdir(parents=True)
        (cell_dir / f"{library}__{cell}__{corner}.lib").write_text(
            f"cell ({cell}) {{}}\n", encoding="utf-8"
        )

    output_dir = tmp_path / "output"
    result = subprocess.run(
        [
            sys.executable,
            str(GF180_GENERATOR),
            "--source",
            str(source),
            "--output-dir",
            str(output_dir),
            "--revision",
            "locked-revision",
            "--library",
            library,
            "--cell",
            "bi_t",
            "--cell",
            "in_c",
            "--corner",
            corner,
            "--output-name",
            "retrosoc_io.lib",
        ],
        text=True,
        capture_output=True,
    )

    assert result.returncode == 0, result.stderr
    output = output_dir / "retrosoc_io.lib"
    assert "library (gf180_io)" in output.read_text(encoding="utf-8")
    assert "cell (bi_t) {}" in output.read_text(encoding="utf-8")
    assert "cell (in_c) {}" in output.read_text(encoding="utf-8")
    assert (output.with_suffix(".lib.revision")).read_text(encoding="utf-8") == (
        "locked-revision\ngf180mcu_fd_io\nbi_t,in_c\n"
    )


def test_ics55_liberty_preparer_selects_stable_tt_and_ss_views(tmp_path: Path) -> None:
    archive = tmp_path / "ics55_LLSC_H7CR_liberty.tar.bz2"
    members = {
        "liberty/ics55_LLSC_H7CR_tt_1p2_25c.lib": "library (ics55_tt) {}\n",
        "liberty/ics55_LLSC_H7CR_ss_1p08_125c.lib": "library (ics55_ss) {}\n",
    }
    with tarfile.open(archive, "w:bz2") as bundle:
        for name, content in members.items():
            payload = content.encode("utf-8")
            member = tarfile.TarInfo(name)
            member.size = len(payload)
            bundle.addfile(member, io.BytesIO(payload))

    output = tmp_path / "output"
    command = [
        sys.executable,
        str(ICS55_PREPARER),
        "--archive",
        str(archive),
        "--output-dir",
        str(output),
        "--revision",
        "locked-revision",
    ]
    first = subprocess.run(command, text=True, capture_output=True)

    assert first.returncode == 0, first.stderr
    assert (output / "ics55_h7cr_tt.lib").read_text(encoding="utf-8") == members[
        "liberty/ics55_LLSC_H7CR_tt_1p2_25c.lib"
    ]
    assert (output / "ics55_h7cr_ss.lib").read_text(encoding="utf-8") == members[
        "liberty/ics55_LLSC_H7CR_ss_1p08_125c.lib"
    ]
    assert (output / ".complete").read_text(encoding="utf-8") == (
        "locked-revision\n" + hashlib.sha256(archive.read_bytes()).hexdigest() + "\n"
    )

    first_mtime = (output / "ics55_h7cr_tt.lib").stat().st_mtime_ns
    second = subprocess.run(command, text=True, capture_output=True)
    assert second.returncode == 0, second.stderr
    assert (output / "ics55_h7cr_tt.lib").stat().st_mtime_ns == first_mtime


def test_ics55_sim_model_preparer_patches_every_h7cr_muxi2_variant(tmp_path: Path) -> None:
    cells = (
        "MUXI2X0P5H7R",
        "MUXI2X0P7H7R",
        "MUXI2X1H7R",
        "MUXI2X1P4H7R",
        "MUXI2X2H7R",
        "MUXI2X3H7R",
        "MUXI2X4H7R",
    )
    source = tmp_path / "ics55_LLSC_H7CR.v"
    source.write_text(
        "".join(
            f"module {cell} (Y, A, B, S0);\n"
            "output Y;\n"
            "input A, B, S0;\n\n"
            "  udp_mux2 u0(Y, A, B, S0);\n"
            "  not      u1(Y, Y);\n"
            f"endmodule //{cell}\n"
            for cell in cells
        ),
        encoding="utf-8",
    )
    output = tmp_path / "ics55_h7cr_functional.v"
    command = [
        sys.executable,
        str(ICS55_SIM_MODEL_PREPARER),
        "--source",
        str(source),
        "--output",
        str(output),
        "--revision",
        "locked-revision",
    ]

    first = subprocess.run(command, text=True, capture_output=True)

    assert first.returncode == 0, first.stderr
    prepared = output.read_text(encoding="utf-8")
    assert prepared.startswith(
        "/* verilator lint_off DECLFILENAME */\n/* verilator lint_off SPECIFYIGN */\n"
    )
    assert prepared.endswith(
        "/* verilator lint_on SPECIFYIGN */\n/* verilator lint_on DECLFILENAME */\n"
    )
    assert prepared.count("wire muxi2_y;") == len(cells)
    assert prepared.count("udp_mux2 u0(muxi2_y, A, B, S0);") == len(cells)
    assert "not      u1(Y, Y);" not in prepared
    assert (output.with_suffix(".v.revision")).read_text(encoding="utf-8") == (
        "locked-revision\n"
        + hashlib.sha256(source.read_bytes()).hexdigest()
        + "\n"
        + ",".join(cells)
        + "\n"
    )

    first_mtime = output.stat().st_mtime_ns
    second = subprocess.run(command, text=True, capture_output=True)
    assert second.returncode == 0, second.stderr
    assert output.stat().st_mtime_ns == first_mtime
