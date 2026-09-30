"""APU-P8 regression: quiesced MICROCODE_LOAD/MODEL_LOAD DMA admission."""

from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))

ROOT = Path(__file__).resolve().parents[1]
KWS_MODEL = (
    ROOT
    / ".cache/retrosoc/sources/apu-mlperf-tiny/benchmark/training/keyword_spotting"
    / "trained_models/kws_ref_model.tflite"
)

PRODUCTION_SOURCES = (
    "apu_microcode_pkg.sv",
    "apu_dma.sv",
    "apu_ring_scheduler.sv",
    "apu_stream_router.sv",
    "apu_control_store.sv",
    "apu_proof_memo.sv",
    "apu_microcode_loader.sv",
    "apu_local_sram.sv",
    "apu_kws_coeff_store.sv",
    "apu_kws_coeff_loader.sv",
    "apu_kws_engine.sv",
    "apu_kws_sram_client.sv",
    "apu_kws_model_loader.sv",
    "apu_bitstream_engine.sv",
    "apu_entropy_engine.sv",
    "apu_reconstruction_engine.sv",
    "apu_transform_engine.sv",
    "apu_resampler.sv",
    "apu_kernel_engine.sv",
    "apu_primitive_dispatcher.sv",
    "apu_codec_sequencer.sv",
    "apu_codec_transport.sv",
    "apu_codec_controller.sv",
    "apu_reg.sv",
    "apb4_apu.sv",
)


def _apumc_bundle() -> Path | None:
    candidates = sorted(
        ROOT.glob("build/*/apu/p5/apu-p5.apumc"), key=lambda path: path.stat().st_mtime
    )
    return candidates[-1] if candidates else None


def _hex_words(path: Path, payload: bytes, words: int) -> None:
    lines = []
    for index in range(words):
        chunk = payload[index * 4 : index * 4 + 4]
        lines.append(f"{int.from_bytes(chunk.ljust(4, bytes(1)), 'little'):08x}\n")
    path.write_text("".join(lines), encoding="ascii")


def test_apu_p8_quiesced_loader_admission(tmp_path: Path) -> None:
    iverilog = shutil.which("iverilog")
    vvp = shutil.which("vvp")
    sv2v = shutil.which("sv2v")
    if iverilog is None or vvp is None or sv2v is None:
        pytest.skip("APU-P8 quiesced loader admission requires iverilog, vvp, and sv2v")
    bundle = _apumc_bundle()
    if bundle is None:
        pytest.skip("APU-P5 bundle was not built (make CONFIG=configs/ci/ihp130.mk apu-p5-bundle)")
    if not KWS_MODEL.is_file():
        pytest.skip("locked P7 model was not installed")

    from apu_kws_convert import import_tflite
    from generate_apu_kws_rtl_constants import build_apuc

    apumc_hex = tmp_path / "apu-p5.hex"
    _hex_words(apumc_hex, bundle.read_bytes(), 16384)
    apum_hex = tmp_path / "kws-apum.hex"
    apum = import_tflite(KWS_MODEL)
    _hex_words(apum_hex, apum, 8192)
    apuc_hex = tmp_path / "kws-apuc.hex"
    apuc, _layout = build_apuc(apum)
    _hex_words(apuc_hex, apuc, 15376)

    common = ROOT / "rtl/managed/clusterip/common/rtl"
    multimedia = ROOT / "rtl/ip/multimedia"
    source_list = tmp_path / "apu_p8_quiesce_load.fl"
    source_list.write_text(
        "\n".join(
            [
                "+define+SV_ASSRT_DISABLE",
                f"+incdir+{common}",
                f"+incdir+{common / 'interface'}",
                f"+incdir+{multimedia}",
                str(common / "interface/apb4_if.sv"),
                str(common / "interface/axi4_if.sv"),
                str(common / "interface/axi4_stream_if.sv"),
                str(common / "utils/register.sv"),
                str(common / "utils/fifo.sv"),
                str(ROOT / "rtl/tech/tc_sram.sv"),
                str(ROOT / "rtl/ip/peripheral/dma_axi4_master.sv"),
                *(str(multimedia / name) for name in PRODUCTION_SOURCES),
                str(ROOT / "tests/rtl/apu_p8_quiesce_load_tb.sv"),
                "",
            ]
        ),
        encoding="utf-8",
    )
    converted = tmp_path / "apu_p8_quiesce_load.v"
    subprocess.run(
        [
            sys.executable,
            str(ROOT / "scripts/rtl/convt_sv2v.py"),
            "-f",
            str(source_list),
            "--output",
            str(converted),
        ],
        check=True,
    )
    simulation = tmp_path / "apu_p8_quiesce_load"
    subprocess.run(
        [iverilog, "-g2012", "-s", "apu_p8_quiesce_load_tb", "-o", str(simulation), str(converted)],
        check=True,
    )
    result = subprocess.run(
        [
            vvp,
            str(simulation),
            f"+APUMC_HEX={apumc_hex}",
            f"+APUM_HEX={apum_hex}",
            f"+APUC_HEX={apuc_hex}",
        ],
        check=True,
        capture_output=True,
        text=True,
    )
    assert "P8_QUIESCE_MC" in result.stdout
    assert "P8_QUIESCE_COEFF" in result.stdout
    assert "P8_QUIESCE_MODEL" in result.stdout
    assert "APU-P8 quiesced loader admission test passed" in result.stdout
