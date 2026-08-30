"""Tests for the generated scalar user-extension bindings."""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
EXTENSIONS = ROOT / "rtl/mini/integration/user_extensions.json"
LEGACY_EXTENSIONS = ROOT / "rtl/mini/integration/user_extensions_legacy.json"
GENERATOR = ROOT / "rtl/mini/integration/generate_user_extensions.py"


def generate(output_dir: Path, manifest: Path = EXTENSIONS) -> None:
    subprocess.run(
        [
            sys.executable,
            str(GENERATOR),
            "--map",
            str(manifest),
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


def test_product_extensions_generate_fixed_slot_contract(tmp_path: Path) -> None:
    generate(tmp_path)

    core = (tmp_path / "rtl/user_core_bindings.svh").read_text(encoding="utf-8")
    ip = (tmp_path / "rtl/user_ip_bindings.svh").read_text(encoding="utf-8")
    filelist = (tmp_path / "user_extensions.fl").read_text(encoding="utf-8")
    config = (tmp_path / "rtl/user_extensions_config.svh").read_text(encoding="utf-8")
    product = (tmp_path / "rtl/product_extensions_config.svh").read_text(encoding="utf-8")
    c_config = (tmp_path / "include/retrosoc/generated/user_extensions.h").read_text(
        encoding="utf-8"
    )

    assert "rib_if u_user_" not in core
    assert "mpw_i" not in ip
    assert "`define USER_CORE_COUNT 0" in config
    assert "`define USER_IP_COUNT 0" in config
    assert "`define RETROSOC_EXTENSION__COUNT 2" in config
    assert "`define RETROSOC_EXTENSION__EXT_L_COUNT 1" in config
    assert "`define RETROSOC_EXTENSION__EXT_H_COUNT 1" in config
    assert "RETROSOC_EXTENSION__SLOT0_KIND_EXT_H" in product
    assert "RETROSOC_EXTENSION__SLOT1_KIND_EXT_H" in product
    assert "RS_SOC_USER_CORE_COUNT UINT32_C(0)" in c_config
    assert "RS_SOC_EXTENSION_COUNT UINT32_C(2)" in c_config
    assert filelist.startswith("+incdir+")


def test_legacy_extensions_generate_isolated_scalar_bindings(tmp_path: Path) -> None:
    generate(tmp_path, LEGACY_EXTENSIONS)

    core = (tmp_path / "rtl/user_core_bindings.svh").read_text(encoding="utf-8")
    ip = (tmp_path / "rtl/user_ip_bindings.svh").read_text(encoding="utf-8")
    config = (tmp_path / "rtl/user_extensions_config.svh").read_text(encoding="utf-8")

    assert core.count("rib_if u_user_") == 4
    assert core.count("ribp_if u_user_") == 4
    assert core.count("ribp2rib #(") == 4
    assert core.count(".SyncReset(1'b1)") == 1
    assert core.count(".SyncReset(1'b0)") == 3
    assert "u_user_rib_if.cmd_valid = '0;" in core
    assert "5'd0: begin" in core
    assert "5'd3: begin" in core
    assert "5'd4: begin" not in core
    assert "core_reset_i[0]" in core
    assert "mpw_c0 #(0)" in core
    assert "mpw_c1 #(1)" in core
    assert "mpw_c3 #(3)" in core
    assert "u_mpw_core_serv" in core
    assert "u_mpw_core_kianv_rv32ima" not in core
    assert "u_mpw_core_picorv32" not in core
    assert "mpw_i1 #(1)" in ip
    assert "User core 0 uses the RIBP contract" in core
    assert ip.count("user_gpio_if #(`USER_GPIO_NUM)") == 2
    assert "gpio.do_o = '0;" in ip
    assert "8'd2: begin" in ip
    assert "u_user_2_apb4_if.psel = apb.psel;" in ip
    assert "`define USER_CORE_COUNT 4" in config


def test_extensions_reject_noncontiguous_slots_and_invalid_modules(tmp_path: Path) -> None:
    document = json.loads(EXTENSIONS.read_text(encoding="utf-8"))
    document["extensions"][1]["slot"] = 7
    result = validate(write_invalid_extensions(tmp_path, document))
    assert result.returncode != 0
    assert "product extension slots must be contiguous from 0" in result.stderr

    document = json.loads(EXTENSIONS.read_text(encoding="utf-8"))
    document["extensions"][0]["control_region"] = "user-ip"
    result = validate(write_invalid_extensions(tmp_path, document))
    assert result.returncode != 0
    assert "must be a SystemVerilog identifier" in result.stderr


def test_extensions_reject_invalid_kind_and_ext_l_data_path(tmp_path: Path) -> None:
    document = json.loads(EXTENSIONS.read_text(encoding="utf-8"))
    document["extensions"][0]["kind"] = "mixed"
    result = validate(write_invalid_extensions(tmp_path, document))
    assert result.returncode != 0
    assert ".kind must be ext_l or ext_h" in result.stderr

    document = json.loads(EXTENSIONS.read_text(encoding="utf-8"))
    document["extensions"][0]["data_master"] = True
    result = validate(write_invalid_extensions(tmp_path, document))
    assert result.returncode != 0
    assert "EXT-L cannot expose a data master or stream" in result.stderr


def test_extensions_reject_duplicate_regions_and_irqs(tmp_path: Path) -> None:
    document = json.loads(EXTENSIONS.read_text(encoding="utf-8"))
    document["extensions"][1]["control_region"] = document["extensions"][0][
        "control_region"
    ]
    result = validate(write_invalid_extensions(tmp_path, document))
    assert result.returncode != 0
    assert "duplicates a slot or control region" in result.stderr

    document = json.loads(EXTENSIONS.read_text(encoding="utf-8"))
    document["extensions"][1]["irq_base"] = document["extensions"][0]["irq_base"]
    result = validate(write_invalid_extensions(tmp_path, document))
    assert result.returncode != 0
    assert "overlapping or out-of-range IRQs" in result.stderr
