"""APU-P5 class-6 assembler, BAM, and product-filelist tests."""

from __future__ import annotations

import os
import sys
from pathlib import Path

import shutil
import subprocess


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

from apu_codecs import crc8, crc16  # noqa: E402
from apu_interpreter import Machine, TransportModel  # noqa: E402
from apu_isa import parse_apumc  # noqa: E402
from apu_mcasm import assemble  # noqa: E402
from apu_p5_coefficients import coefficient_bytes  # noqa: E402
from apu_primitives import PrimitiveBam  # noqa: E402


TRANSPORT_PROGRAM = """
.entry 0 wav wav done 16 128 0 256 0x001b0030 0 0
.entry 1 mp3 mp3 mp3 1 1 0 0 0 0 0
.entry 2 wav wav done 16 128 0 256 0x001b0030 0 0
mp3:
  trap 0x01000001
wav:
  movi r0, 0
  movi r1, 8
  input_refill r2, r0, r1
  movi r3, 0x55
  dma_wait r4
  ld32 r5, r0, 0
  movi r6, 8
  output_commit r8, r0, r6
  dma_wait r4
  movi r6, 4
  frame_commit r6, r6
  frame_commit r6, r6
  movi r7, 0
  job_result r7, r7, 0
done:
  end
"""


def test_p5_transport_assembler_and_parser_keep_legacy_targets_closed() -> None:
    assembly = assemble(TRANSPORT_PROGRAM, "p5")
    instructions, entries, _ = parse_apumc(assembly.bundle, "p5")
    assert entries[0].scratch_bytes == 256
    assert any(instruction.instruction_class == 6 for instruction in instructions)


def test_p5_transport_runs_asynchronously_and_preserves_independent_scalar_progress() -> None:
    assembly = assemble(TRANSPORT_PROGRAM, "p5")
    primitives = PrimitiveBam()
    transport = TransportModel(input_data=b"ABCDEFGH", latency=3)
    result = Machine(
        assembly.instructions,
        assembly.entries[0],
        target="p5",
        primitives=primitives,
        transport=transport,
        fetch_no_retirement_cycles=0,
    ).run()
    assert result["registers"][2] == 8
    assert result["registers"][3] == 0x55
    assert result["registers"][5] == int.from_bytes(b"ABCD", "little")
    assert result["transport"]["input_used"] == 8
    assert result["transport"]["frames"] == 2
    assert result["transport"]["output"] == b"ABCDEFGH".hex()


def test_p5_production_and_verification_filelist_boundaries() -> None:
    product = (ROOT / "rtl/mini/filelist/ip.fl").read_text(encoding="utf-8")
    assert "/ip/multimedia/apu_codec_transport.sv" in product
    assert "/ip/multimedia/apu_codec_controller.sv" in product
    assert "tests/rtl" not in product
    assert "apu_p2_backend" not in product


def test_p5_production_transport_matches_icarus_and_verilator(tmp_path: Path) -> None:
    iverilog = shutil.which("iverilog")
    vvp = shutil.which("vvp")
    sv2v = shutil.which("sv2v")
    verilator = shutil.which("verilator")
    if None in (iverilog, vvp, sv2v, verilator):
        raise RuntimeError("P5 requires Icarus, vvp, sv2v, and Verilator")
    common = ROOT / "rtl/managed/clusterip/common/rtl"
    multimedia = ROOT / "rtl/ip/multimedia"
    filelist = tmp_path / "apu_p5_transport.fl"
    filelist.write_text(
        "\n".join(
            [
                "+define+SV_ASSRT_DISABLE",
                f"+incdir+{multimedia}",
                str(common / "interface/axi4_stream_if.sv"),
                str(common / "utils/fifo.sv"),
                str(multimedia / "apu_codec_transport.sv"),
                str(ROOT / "tests/rtl/apu_p5_transport_tb.sv"),
                "",
            ]
        ),
        encoding="utf-8",
    )
    converted = tmp_path / "apu_p5_transport_tb.v"
    subprocess.run(
        [
            sys.executable,
            str(ROOT / "rtl/mini/script/convt_sv2v.py"),
            "-f",
            str(filelist),
            "--output",
            str(converted),
        ],
        check=True,
    )
    executable = tmp_path / "apu_p5_transport_tb"
    subprocess.run(
        [iverilog, "-g2012", "-s", "apu_p5_transport_tb", "-o", str(executable), str(converted)],
        check=True,
    )
    icarus = subprocess.run([vvp, str(executable)], check=True, capture_output=True, text=True)
    assert "APU-P5 production transport passed" in icarus.stdout

    verilator_dir = tmp_path / "verilator"
    ccache_dir = tmp_path / "ccache"
    ccache_dir.mkdir()
    environment = {
        **os.environ,
        "CCACHE_DIR": str(ccache_dir),
        "CCACHE_TEMPDIR": str(ccache_dir),
    }
    subprocess.run(
        [
            verilator,
            "--binary",
            "--timing",
            "-Wno-fatal",
            "--top-module",
            "apu_p5_transport_tb",
            "--Mdir",
            str(verilator_dir),
            str(converted),
        ],
        check=True,
        env=environment,
    )
    verilator_run = subprocess.run(
        [str(verilator_dir / "Vapu_p5_transport_tb")], check=True, capture_output=True, text=True
    )
    assert "APU-P5 production transport passed" in verilator_run.stdout


def test_p5_direct_wav_uses_product_loader_dma_sequencer_and_tx(tmp_path: Path) -> None:
    iverilog = shutil.which("iverilog")
    vvp = shutil.which("vvp")
    sv2v = shutil.which("sv2v")
    verilator = shutil.which("verilator")
    if None in (iverilog, vvp, sv2v, verilator):
        raise RuntimeError("P5 integration requires Icarus, vvp, sv2v, and Verilator")
    multimedia = ROOT / "rtl/ip/multimedia"
    common = ROOT / "rtl/managed/clusterip/common/rtl"
    assembly = assemble(
        (multimedia / "apu_p5_codecs.apus").read_text(encoding="utf-8"),
        "p5",
        coefficient_bytes(),
    )
    image = tmp_path / "apu_p5.hex"
    image.write_text(
        "".join(
            f"{int.from_bytes(assembly.bundle[offset : offset + 4], 'little'):08x}\n"
            for offset in range(0, len(assembly.bundle), 4)
        ),
        encoding="utf-8",
    )
    streaminfo = bytearray(34)
    streaminfo[0:2] = (16).to_bytes(2, "big")
    streaminfo[2:4] = (16).to_bytes(2, "big")
    streaminfo[10:18] = ((48000 << 44) | (15 << 36) | 16).to_bytes(8, "big")
    frame_header = ((0x3FFE << 18) | (6 << 12) | (4 << 1)).to_bytes(4, "big")
    frame_header += b"\x00\x0f"
    frame_header += bytes([crc8(frame_header)])
    frame = frame_header + b"\x00\xff\xfe"
    frame += crc16(frame).to_bytes(2, "big")
    flac = b"fLaC" + bytes([0x80, 0, 0, 34]) + streaminfo + frame
    flac_image = tmp_path / "apu_p5_constant_flac.hex"
    flac_image.write_text(
        "".join(
            f"{int.from_bytes(flac[offset : offset + 4].ljust(4, bytes(1)), 'little'):08x}\n"
            for offset in range(0, len(flac), 4)
        ),
        encoding="utf-8",
    )
    sources = [
        common / "interface/apb4_if.sv",
        common / "interface/axi4_if.sv",
        common / "interface/axi4_stream_if.sv",
        common / "utils/register.sv",
        common / "utils/fifo.sv",
        ROOT / "rtl/tech/tc_sram.sv",
        ROOT / "rtl/ip/peripheral/dma_axi4_master.sv",
        *(
            multimedia / name
            for name in (
                "apu_microcode_pkg.sv",
                "apu_dma.sv",
                "apu_ring_scheduler.sv",
                "apu_stream_router.sv",
                "apu_control_store.sv",
                "apu_microcode_loader.sv",
                "apu_local_sram.sv",
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
        ),
        ROOT / "tests/rtl/apu_p5_integration_tb.sv",
    ]
    filelist = tmp_path / "apu_p5_integration.fl"
    filelist.write_text(
        "\n".join(
            [
                "+define+SV_ASSRT_DISABLE",
                f"+incdir+{common}",
                f"+incdir+{common / 'interface'}",
                f"+incdir+{multimedia}",
                *(str(source) for source in sources),
                "",
            ]
        ),
        encoding="utf-8",
    )
    converted = tmp_path / "apu_p5_integration.v"
    subprocess.run(
        [
            sys.executable,
            str(ROOT / "rtl/mini/script/convt_sv2v.py"),
            "-f",
            str(filelist),
            "--output",
            str(converted),
        ],
        check=True,
    )
    executable = tmp_path / "apu_p5_integration"
    subprocess.run(
        [iverilog, "-g2012", "-s", "apu_p5_integration_tb", "-o", str(executable), str(converted)],
        check=True,
    )
    result = subprocess.run(
        [vvp, str(executable), f"+IMAGE={image}", f"+FLAC={flac_image}"],
        check=True,
        capture_output=True,
        text=True,
    )
    assert "APU-P5 direct WAV product integration passed" in result.stdout

    verilator_dir = tmp_path / "integration_verilator"
    ccache_dir = tmp_path / "integration_ccache"
    ccache_dir.mkdir()
    environment = {
        **os.environ,
        "CCACHE_DIR": str(ccache_dir),
        "CCACHE_TEMPDIR": str(ccache_dir),
    }
    subprocess.run(
        [
            verilator,
            "--binary",
            "--timing",
            "-Wno-fatal",
            "--top-module",
            "apu_p5_integration_tb",
            "--Mdir",
            str(verilator_dir),
            str(converted),
        ],
        check=True,
        env=environment,
    )
    verilator_result = subprocess.run(
        [str(verilator_dir / "Vapu_p5_integration_tb"), f"+IMAGE={image}", f"+FLAC={flac_image}"],
        check=True,
        capture_output=True,
        text=True,
    )
    assert "APU-P5 direct WAV product integration passed" in verilator_result.stdout
