"""Crypto accelerator directed RTL tests."""

from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def test_crypto_aes_and_sha_primitives(tmp_path: Path) -> None:
    iverilog = shutil.which("iverilog")
    vvp = shutil.which("vvp")
    if iverilog is None or vvp is None:
        return

    simulation = tmp_path / "crypto_primitive_tb"
    subprocess.run(
        [
            iverilog,
            "-g2012",
            "-s",
            "crypto_primitive_tb",
            "-o",
            str(simulation),
            str(ROOT / "rtl/ip/security/crypto_pkg.sv"),
            str(ROOT / "rtl/ip/security/crypto_aes_core.sv"),
            str(ROOT / "rtl/ip/security/crypto_sha2_core.sv"),
            str(ROOT / "tests/rtl/crypto_primitive_tb.sv"),
        ],
        check=True,
    )
    result = subprocess.run([vvp, str(simulation)], text=True, capture_output=True, check=True)
    assert "Crypto AES and SHA primitive tests passed" in result.stdout


def test_crypto_rsa_montgomery_engine(tmp_path: Path) -> None:
    iverilog = shutil.which("iverilog")
    vvp = shutil.which("vvp")
    if iverilog is None or vvp is None:
        return

    simulation = tmp_path / "crypto_rsa_tb"
    subprocess.run(
        [
            iverilog,
            "-g2012",
            "-s",
            "crypto_rsa_tb",
            "-o",
            str(simulation),
            str(ROOT / "rtl/ip/security/crypto_montgomery.sv"),
            str(ROOT / "rtl/ip/security/crypto_rsa_core.sv"),
            str(ROOT / "tests/rtl/crypto_rsa_tb.sv"),
        ],
        check=True,
    )
    result = subprocess.run([vvp, str(simulation)], text=True, capture_output=True, check=True)
    assert "Crypto RSA Montgomery tests passed" in result.stdout


def test_crypto_streaming_engines(tmp_path: Path) -> None:
    iverilog = shutil.which("iverilog")
    vvp = shutil.which("vvp")
    if iverilog is None or vvp is None:
        return

    simulation = tmp_path / "crypto_engine_tb"
    subprocess.run(
        [
            iverilog,
            "-g2012",
            "-s",
            "crypto_engine_tb",
            "-o",
            str(simulation),
            str(ROOT / "rtl/managed/clusterip/common/rtl/utils/fifo.sv"),
            str(ROOT / "rtl/ip/security/crypto_pkg.sv"),
            str(ROOT / "rtl/ip/security/crypto_aes_core.sv"),
            str(ROOT / "rtl/ip/security/crypto_aes_engine.sv"),
            str(ROOT / "rtl/ip/security/crypto_sha2_core.sv"),
            str(ROOT / "rtl/ip/security/crypto_sha2_engine.sv"),
            str(ROOT / "tests/rtl/crypto_engine_tb.sv"),
        ],
        check=True,
    )
    result = subprocess.run([vvp, str(simulation)], text=True, capture_output=True, check=True)
    assert "Crypto streaming engine tests passed" in result.stdout


def test_crypto_apb_register_path(tmp_path: Path) -> None:
    iverilog = shutil.which("iverilog")
    vvp = shutil.which("vvp")
    sv2v = shutil.which("sv2v")
    if iverilog is None or vvp is None or sv2v is None:
        return

    source_list = tmp_path / "crypto_apb.fl"
    source_list.write_text(
        "\n".join(
            [
                f"+incdir+{ROOT / 'rtl/ip/security'}",
                str(ROOT / "rtl/managed/clusterip/common/rtl/interface/apb4_if.sv"),
                str(ROOT / "rtl/managed/clusterip/common/rtl/interface/axi4_stream_if.sv"),
                str(ROOT / "rtl/managed/clusterip/common/rtl/utils/fifo.sv"),
                str(ROOT / "rtl/ip/security/crypto_pkg.sv"),
                str(ROOT / "rtl/ip/security/crypto_aes_core.sv"),
                str(ROOT / "rtl/ip/security/crypto_aes_engine.sv"),
                str(ROOT / "rtl/ip/security/crypto_sha2_core.sv"),
                str(ROOT / "rtl/ip/security/crypto_sha2_engine.sv"),
                str(ROOT / "rtl/ip/security/crypto_montgomery.sv"),
                str(ROOT / "rtl/ip/security/crypto_rsa_core.sv"),
                str(ROOT / "rtl/ip/security/apb4_crypto.sv"),
                str(ROOT / "tests/rtl/crypto_apb_tb.sv"),
                "",
            ]
        ),
        encoding="utf-8",
    )
    converted = tmp_path / "crypto_apb_tb.v"
    subprocess.run(
        [
            sys.executable,
            str(ROOT / "rtl/mini/script/convt_sv2v.py"),
            "-f",
            str(source_list),
            "--output",
            str(converted),
        ],
        check=True,
    )
    simulation = tmp_path / "crypto_apb_tb"
    subprocess.run(
        [iverilog, "-g2012", "-s", "crypto_apb_tb", "-o", str(simulation), str(converted)],
        check=True,
    )
    result = subprocess.run([vvp, str(simulation)], text=True, capture_output=True, check=True)
    assert "Crypto APB register tests passed" in result.stdout
