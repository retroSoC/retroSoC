from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts/check_rtl_style.py"


def run_style(tmp_path: Path, source: str) -> subprocess.CompletedProcess[str]:
    (tmp_path / "rtl/ip/test.sv").parent.mkdir(parents=True)
    (tmp_path / "rtl/ip/test.sv").write_text(source, encoding="utf-8")
    (tmp_path / "rtl/rtl_style_manifest.json").write_text(
        json.dumps(
            {
                "schema_version": 1,
                "profiles": {
                    "owned": {
                        "roots": ["rtl/ip"],
                        "suffixes": [".sv"],
                        "format": "verible",
                        "lint": "strict",
                    }
                },
            }
        ),
        encoding="utf-8",
    )
    subprocess.run(["git", "init", "-q", str(tmp_path)], check=True)
    subprocess.run(["git", "-C", str(tmp_path), "add", "."], check=True)
    return subprocess.run(
        [sys.executable, str(SCRIPT), "--root", str(tmp_path), "--profile", "owned"],
        text=True,
        capture_output=True,
        check=False,
    )


def test_owned_style_rejects_positional_connections(tmp_path: Path) -> None:
    result = run_style(
        tmp_path,
        "module test(input logic clk_i, output logic data_o);\n"
        "  dffr #(1) u_reg (clk_i, 1'b1, 1'b0, data_o);\n"
        "endmodule\n",
    )
    assert result.returncode == 1
    assert "module-port" in result.stderr


def test_owned_style_allows_named_connections(tmp_path: Path) -> None:
    result = run_style(
        tmp_path,
        "module test(input logic clk_i, output logic data_o);\n"
        "  dffr #(1) u_reg (.clk_i(clk_i), .rst_n_i(1'b1), .dat_i(1'b0), .dat_o(data_o));\n"
        "endmodule\n",
    )
    assert result.returncode == 0, result.stderr


def test_owned_style_rejects_forbidden_constructs(tmp_path: Path) -> None:
    result = run_style(
        tmp_path,
        "module test(input logic clk_i, output logic data_o);\n"
        "  always_comb begin\n"
        "    data_o = 1'b0;\n"
        "    casex (data_o)\n"
        "      1'bx: data_o = 1'b1;\n"
        "    endcase\n"
        "  end\n"
        "endmodule\n",
    )
    assert result.returncode == 1
    assert "casex" in result.stderr


def test_owned_style_rejects_non_ascii_and_long_lines(tmp_path: Path) -> None:
    result = run_style(
        tmp_path,
        "module test(input logic clk_i, output logic data_o);\n"
        "  logic data_q;\n"
        "  // 非 ASCII comment\n"
        "  assign data_o = data_q; // " + ("x" * 101) + "\n"
        "endmodule\n",
    )
    assert result.returncode == 1
    assert "non-ASCII" in result.stderr
    assert "100 characters" in result.stderr
