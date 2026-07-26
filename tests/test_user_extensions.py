"""Tests for the generated scalar user-extension bindings."""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
EXTENSIONS = ROOT / "rtl/mini/integration/user_extensions.json"
GENERATOR = ROOT / "rtl/mini/integration/generate_user_extensions.py"


def generate(output_dir: Path) -> None:
    subprocess.run(
        [
            sys.executable,
            str(GENERATOR),
            "--map",
            str(EXTENSIONS),
            "--output-dir",
            str(output_dir),
        ],
        check=True,
    )


def validate(extensions: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(GENERATOR), "--map", str(extensions), "--check"],
        text=True,
        capture_output=True,
    )


def write_invalid_extensions(tmp_path: Path, document: dict[str, object]) -> Path:
    path = tmp_path / "invalid_extensions.json"
    path.write_text(json.dumps(document), encoding="utf-8")
    return path


def test_extensions_generate_isolated_scalar_bindings(tmp_path: Path) -> None:
    generate(tmp_path)

    core = (tmp_path / "rtl/user_core_bindings.svh").read_text(encoding="utf-8")
    ip = (tmp_path / "rtl/user_ip_bindings.svh").read_text(encoding="utf-8")
    filelist = (tmp_path / "user_extensions.fl").read_text(encoding="utf-8")

    assert core.count("nmi_if u_user_") == 6
    assert "nmi.valid = '0;" in core
    assert "5'd0: begin" in core
    assert "5'd5: begin" in core
    assert "core_reset_i[0]" in core
    assert "user_core_design_username1 #(" in core
    assert ip.count("user_gpio_if #(`USER_GPIO_NUM)") == 2
    assert "gpio.do_o = '0;" in ip
    assert "8'd2: begin" in ip
    assert "u_user_2_apb_if.psel = apb.psel;" in ip
    assert filelist.startswith("+incdir+")


def test_extensions_reject_noncontiguous_slots_and_invalid_modules(tmp_path: Path) -> None:
    document = json.loads(EXTENSIONS.read_text(encoding="utf-8"))
    document["core_targets"][2]["slot"] = 7
    result = validate(write_invalid_extensions(tmp_path, document))
    assert result.returncode != 0
    assert "slots must be contiguous from 0" in result.stderr

    document = json.loads(EXTENSIONS.read_text(encoding="utf-8"))
    document["ip_targets"][0]["module"] = "user-ip"
    result = validate(write_invalid_extensions(tmp_path, document))
    assert result.returncode != 0
    assert "must be a SystemVerilog identifier" in result.stderr
