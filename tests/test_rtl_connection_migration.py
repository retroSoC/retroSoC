from __future__ import annotations

import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts/migrate_rtl_connections.py"
NAME_SCRIPT = ROOT / "scripts/migrate_rtl_names.py"


def test_migrates_exact_positional_instance(tmp_path: Path) -> None:
    (tmp_path / "rtl/ip/example.sv").parent.mkdir(parents=True)
    (tmp_path / "rtl/ip/example.sv").write_text(
        "module dffr #(parameter WIDTH = 1) (input logic clk_i, input logic rst_n_i, "
        "input logic dat_i, output logic dat_o); endmodule\n"
        "module top(input logic clk_i, output logic data_o);\n"
        "  dffr #(1) u_reg (clk_i, 1'b1, 1'b0, data_o);\n"
        "endmodule\n",
        encoding="utf-8",
    )
    result = subprocess.run(
        [sys.executable, str(SCRIPT), "--root", str(tmp_path), "--apply"],
        text=True,
        capture_output=True,
        check=False,
    )
    assert result.returncode == 0, result.stderr
    source = (tmp_path / "rtl/ip/example.sv").read_text(encoding="utf-8")
    assert ".WIDTH(1)" in source
    assert ".clk_i(clk_i)" in source
    assert ".dat_o(data_o)" in source


def test_leaves_ambiguous_instance_unchanged(tmp_path: Path) -> None:
    (tmp_path / "rtl/ip/example.sv").parent.mkdir(parents=True)
    (tmp_path / "rtl/ip/example.sv").write_text(
        "module dffr (input logic clk_i, input logic rst_n_i); endmodule\n"
        "module top(input logic clk_i);\n"
        "  dffr u_reg (clk_i, 1'b1, 1'b0);\n"
        "endmodule\n",
        encoding="utf-8",
    )
    before = (tmp_path / "rtl/ip/example.sv").read_text(encoding="utf-8")
    result = subprocess.run(
        [sys.executable, str(SCRIPT), "--root", str(tmp_path), "--apply"],
        text=True,
        capture_output=True,
        check=False,
    )
    assert result.returncode == 0, result.stderr
    assert "ambiguous=1" in result.stdout
    assert (tmp_path / "rtl/ip/example.sv").read_text(encoding="utf-8") == before


def test_shortens_local_names_but_not_ports(tmp_path: Path) -> None:
    (tmp_path / "rtl/ip/example.sv").parent.mkdir(parents=True)
    path = tmp_path / "rtl/ip/example.sv"
    path.write_text(
        "module example(input logic request_i, output logic response_o);\n"
        "  logic s_command_enable;\n"
        "  assign response_o = request_i & s_command_enable;\n"
        "endmodule\n",
        encoding="utf-8",
    )
    result = subprocess.run(
        [sys.executable, str(NAME_SCRIPT), "--root", str(tmp_path), "--apply"],
        text=True,
        capture_output=True,
        check=False,
    )
    assert result.returncode == 0, result.stderr
    source = path.read_text(encoding="utf-8")
    assert "s_cmd_en" in source
    assert "request_i" in source
    assert "response_o" in source
