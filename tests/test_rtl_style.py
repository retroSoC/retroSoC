from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts/check_rtl_style.py"
AUDIT = ROOT / "rtl/rtl_style_audit.json"


def run_style(
    tmp_path: Path, source: str, *, enforce_naming: bool = False
) -> subprocess.CompletedProcess[str]:
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
    command = [sys.executable, str(SCRIPT), "--root", str(tmp_path), "--profile", "owned"]
    if enforce_naming:
        command.append("--enforce-naming")
    return subprocess.run(
        command,
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


def test_owned_style_enforces_staged_naming_contract(tmp_path: Path) -> None:
    result = run_style(
        tmp_path,
        "`define BAD_MACRO 1\n"
        "module badModule(\n"
        "  input logic clk,\n"
        "  output logic data_o\n"
        ");\n"
        "  logic s_state_q;\n"
        "  bad_if if0 ();\n"
        "endmodule\n",
        enforce_naming=True,
    )
    assert result.returncode == 1
    assert "module name" in result.stderr
    assert "port 'clk'" in result.stderr
    assert "interface instance" in result.stderr
    assert "macro 'BAD_MACRO'" in result.stderr


def test_owned_style_accepts_project_naming_contract(tmp_path: Path) -> None:
    result = run_style(
        tmp_path,
        "`define RETROSOC_TEST__VALUE 1\n"
        "module test(\n"
        "  input logic clk_i,\n"
        "  output logic data_o\n"
        ");\n"
        "  logic s_state_d;\n"
        "  logic s_state_q;\n"
        "  test_if u_test_if ();\n"
        "endmodule\n",
        enforce_naming=True,
    )
    assert result.returncode == 0, result.stderr


def test_owned_style_allows_protocol_localparams(tmp_path: Path) -> None:
    result = run_style(
        tmp_path,
        "module test #(parameter int DataWidth = 32) ("
        "input logic clk_i, output logic data_o);\n"
        "  localparam logic [1:0] FSM_IDLE = 2'd0;\n"
        "  localparam logic [1:0] FSM_RESP = 2'd1;\n"
        "  assign data_o = clk_i;\n"
        "endmodule\n",
        enforce_naming=True,
    )
    assert result.returncode == 0, result.stderr


def test_owned_style_allows_interface_members_and_include_guards(tmp_path: Path) -> None:
    result = run_style(
        tmp_path,
        "`ifndef GPIO_DEFINE_SVH\n"
        "`define GPIO_DEFINE_SVH\n"
        "interface test ();\n"
        "  logic cmd_valid;\n"
        "  modport dut(input cmd_valid);\n"
        "endinterface\n"
        "`endif\n",
        enforce_naming=True,
    )
    assert result.returncode == 0, result.stderr


def test_owned_style_rejects_mismatched_primary_design_unit(tmp_path: Path) -> None:
    result = run_style(
        tmp_path,
        "module wrong_name(input logic clk_i, output logic data_o);\n"
        "  assign data_o = clk_i;\n"
        "endmodule\n",
    )
    assert result.returncode == 1
    assert "RTL-FILE-002" in result.stderr


def test_owned_style_rejects_synthesizable_initial_block(tmp_path: Path) -> None:
    result = run_style(
        tmp_path,
        "module test(input logic clk_i, output logic data_o);\n"
        "  initial begin\n"
        "    data_o = clk_i;\n"
        "  end\n"
        "endmodule\n",
    )
    assert result.returncode == 1
    assert "RTL-SV-007" in result.stderr


def test_owned_style_allows_verification_only_initial_block(tmp_path: Path) -> None:
    result = run_style(
        tmp_path,
        "module test(input logic clk_i, output logic data_o);\n"
        "  assign data_o = clk_i;\n"
        "`ifndef SYNTHESIS\n"
        "  initial begin\n"
        "    if (clk_i) $error(\"unexpected clock\");\n"
        "  end\n"
        "`endif\n"
        "endmodule\n",
    )
    assert result.returncode == 0, result.stderr


def test_owned_style_rejects_unpaired_format_directive(tmp_path: Path) -> None:
    result = run_style(
        tmp_path,
        "module test(input logic clk_i, output logic data_o);\n"
        "  // verilog_format: on\n"
        "  assign data_o = clk_i;\n"
        "endmodule\n",
    )
    assert result.returncode == 1
    assert "RTL-FMT-005" in result.stderr


def test_owned_style_requires_formatter_exception_rationale(tmp_path: Path) -> None:
    result = run_style(
        tmp_path,
        "module test(input logic clk_i, output logic data_o);\n"
        "  // verilog_format: off\n"
        "  assign data_o = clk_i;\n"
        "  // verilog_format: on\n"
        "endmodule\n",
    )
    assert result.returncode == 1
    assert "RTL-FMT-007" in result.stderr


def test_owned_style_requires_automatic_typed_functions(tmp_path: Path) -> None:
    result = run_style(
        tmp_path,
        "module test(input logic clk_i, output logic data_o);\n"
        "  function logic invert(input logic value_i);\n"
        "    return !value_i;\n"
        "  endfunction\n"
        "  assign data_o = invert(clk_i);\n"
        "endmodule\n",
    )
    assert result.returncode == 1
    assert "RTL-SV-008" in result.stderr


def test_owned_style_audit_matches_current_inventory() -> None:
    audit = json.loads(AUDIT.read_text(encoding="utf-8"))
    assert audit["schema_version"] == 1
    assert audit["policy"] == "docs/rtl-coding-style.md"
    assert audit["profile"] == "owned"
    assert {
        "owner",
        "related_commit",
        "expiry",
        "removal_plan",
    }.issubset(audit["reviewed_boundary_record"])

    audited_paths = {
        str(Path(directory) / name)
        for directory, names in audit["inventory"].items()
        for name in names
    }
    actual_paths = {
        str(path.relative_to(ROOT))
        for root in (ROOT / "rtl/ip", ROOT / "rtl/mini/top")
        for path in root.rglob("*")
        if path.is_file() and path.suffix in {".sv", ".svh"}
    }
    assert audited_paths == actual_paths
    assert {
        "RTL-FILE",
        "RTL-SV",
        "RTL-NAME",
        "RTL-STRUCT",
        "RTL-COMB",
        "RTL-SEQ",
        "RTL-WIDTH",
        "RTL-CDC",
        "RTL-VERIFY",
        "RTL-FMT",
    }.issubset({rule["id"] for rule in audit["rules"]})
