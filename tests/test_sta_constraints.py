"""Tests for generated core-STA constraints."""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DOMAINS = ROOT / "rtl/mini/integration/clock_reset_domains.json"
PIN_MAP = ROOT / "rtl/mini/pin_map/pin_map.json"
GENERATOR = ROOT / "sta/opensta/generate_sdc.py"
GF180_GENERATOR = ROOT / "pdk/generate_gf180_liberty.py"


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
    assert "create_clock -name clk_dvp -period 41.666666667" in sdc
    assert "u_dvp_pclk_clk_buf/clk_o" in sdc
    assert "-group [get_clocks {clk_external clk_system}]" in sdc
    assert "set_clock_transition 0.1 [get_clocks {clk_dvp}]" in sdc
    assert "set_input_transition" not in sdc
    assert "set_false_path -from $reset_ext_rst_n_i_pad" in sdc


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
