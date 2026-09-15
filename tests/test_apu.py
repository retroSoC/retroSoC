"""Directed verification for the APU-P1 APB4 register shell."""

from __future__ import annotations

import shutil
import struct
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))

from apu_interpreter import Machine, PredicateInputs
from apu_isa import ControlOpcode, Instruction, crc32_iso_hdlc
from apu_kws import infer_apum
from apu_kws_convert import import_tflite
from apu_mcasm import assemble


ROOT = Path(__file__).resolve().parents[1]
TOPOLOGY = ROOT / "rtl/mini/integration/soc_topology.json"
TOPOLOGY_GENERATOR = ROOT / "rtl/mini/integration/generate_soc_topology.py"
MEMORY_MAP = ROOT / "rtl/mini/address_map/memory_map.json"
KWS_MODEL = (
    ROOT
    / ".cache/retrosoc/sources/apu-mlperf-tiny/benchmark/training/keyword_spotting"
    / "trained_models/kws_ref_model.tflite"
)


def _patch_crc32(payload: bytearray, offset: int, target: int) -> None:
    payload[offset : offset + 4] = b"\0\0\0\0"
    base = crc32_iso_hdlc(payload)
    effects: list[int] = []
    for bit in range(32):
        candidate = bytearray(payload)
        candidate[offset + bit // 8] ^= 1 << (bit % 8)
        effects.append(crc32_iso_hdlc(candidate) ^ base)

    basis: dict[int, tuple[int, int]] = {}
    for bit, effect in enumerate(effects):
        value = effect
        combination = 1 << bit
        while value:
            pivot = value.bit_length() - 1
            if pivot not in basis:
                basis[pivot] = (value, combination)
                break
            value ^= basis[pivot][0]
            combination ^= basis[pivot][1]

    value = target ^ base
    combination = 0
    while value:
        pivot = value.bit_length() - 1
        if pivot not in basis:
            raise AssertionError("CRC32 patch matrix is singular")
        value ^= basis[pivot][0]
        combination ^= basis[pivot][1]
    payload[offset : offset + 4] = combination.to_bytes(4, "little")
    assert crc32_iso_hdlc(payload) == target


def test_apu_p1_apb_register_shell(tmp_path: Path) -> None:
    iverilog = shutil.which("iverilog")
    vvp = shutil.which("vvp")
    sv2v = shutil.which("sv2v")
    if iverilog is None or vvp is None or sv2v is None:
        return

    common = ROOT / "rtl/managed/clusterip/common/rtl"
    multimedia = ROOT / "rtl/ip/multimedia"
    source_list = tmp_path / "apu_reg.fl"
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
                str(multimedia / "apu_microcode_pkg.sv"),
                str(multimedia / "apu_dma.sv"),
                str(multimedia / "apu_ring_scheduler.sv"),
                str(multimedia / "apu_stream_router.sv"),
                str(multimedia / "apu_control_store.sv"),
                str(multimedia / "apu_microcode_loader.sv"),
                str(multimedia / "apu_local_sram.sv"),
                str(multimedia / "apu_kws_engine.sv"),
                str(multimedia / "apu_kws_sram_client.sv"),
                str(multimedia / "apu_kws_model_loader.sv"),
                str(multimedia / "apu_bitstream_engine.sv"),
                str(multimedia / "apu_entropy_engine.sv"),
                str(multimedia / "apu_reconstruction_engine.sv"),
                str(multimedia / "apu_transform_engine.sv"),
                str(multimedia / "apu_resampler.sv"),
                str(multimedia / "apu_kernel_engine.sv"),
                str(multimedia / "apu_primitive_dispatcher.sv"),
                str(multimedia / "apu_codec_sequencer.sv"),
                str(multimedia / "apu_codec_transport.sv"),
                str(multimedia / "apu_codec_controller.sv"),
                str(multimedia / "apu_reg.sv"),
                str(multimedia / "apb4_apu.sv"),
                str(ROOT / "tests/rtl/apu_reg_tb.sv"),
                "",
            ]
        ),
        encoding="utf-8",
    )
    converted = tmp_path / "apu_reg_tb.v"
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
    simulation = tmp_path / "apu_reg_tb"
    subprocess.run(
        [iverilog, "-g2012", "-s", "apu_reg_tb", "-o", str(simulation), str(converted)],
        check=True,
    )
    result = subprocess.run([vvp, str(simulation)], text=True, capture_output=True, check=True)
    assert "APU-P1 complete APB register matrix passed" in result.stdout


def test_apu_p1_integrated_irq_ownership_topology(tmp_path: Path) -> None:
    iverilog = shutil.which("iverilog")
    vvp = shutil.which("vvp")
    sv2v = shutil.which("sv2v")
    if iverilog is None or vvp is None or sv2v is None:
        return

    common = ROOT / "rtl/managed/clusterip/common/rtl"
    multimedia = ROOT / "rtl/ip/multimedia"
    peripheral = ROOT / "rtl/ip/peripheral"
    topology_output = tmp_path / "topology"
    subprocess.run(
        [
            sys.executable,
            str(TOPOLOGY_GENERATOR),
            "--map",
            str(TOPOLOGY),
            "--memory-map",
            str(MEMORY_MAP),
            "--output-dir",
            str(topology_output),
        ],
        check=True,
    )

    source_list = tmp_path / "apu_irq_topology.fl"
    source_list.write_text(
        "\n".join(
            [
                "+define+SV_ASSRT_DISABLE",
                f"+incdir+{topology_output / 'rtl'}",
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
                str(multimedia / "apu_microcode_pkg.sv"),
                str(multimedia / "apu_dma.sv"),
                str(multimedia / "apu_ring_scheduler.sv"),
                str(multimedia / "apu_stream_router.sv"),
                str(multimedia / "apu_control_store.sv"),
                str(multimedia / "apu_microcode_loader.sv"),
                str(multimedia / "apu_local_sram.sv"),
                str(multimedia / "apu_kws_engine.sv"),
                str(multimedia / "apu_kws_sram_client.sv"),
                str(multimedia / "apu_kws_model_loader.sv"),
                str(multimedia / "apu_bitstream_engine.sv"),
                str(multimedia / "apu_entropy_engine.sv"),
                str(multimedia / "apu_reconstruction_engine.sv"),
                str(multimedia / "apu_transform_engine.sv"),
                str(multimedia / "apu_resampler.sv"),
                str(multimedia / "apu_kernel_engine.sv"),
                str(multimedia / "apu_primitive_dispatcher.sv"),
                str(multimedia / "apu_codec_sequencer.sv"),
                str(multimedia / "apu_codec_transport.sv"),
                str(multimedia / "apu_codec_controller.sv"),
                str(multimedia / "apu_reg.sv"),
                str(multimedia / "apb4_apu.sv"),
                str(ROOT / "rtl/mini/top/resource_controller.sv"),
                str(peripheral / "apb4_plic.sv"),
                str(ROOT / "tests/rtl/apu_irq_topology_tb.sv"),
                "",
            ]
        ),
        encoding="utf-8",
    )
    converted = tmp_path / "apu_irq_topology_tb.v"
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
    simulation = tmp_path / "apu_irq_topology_tb"
    subprocess.run(
        [
            iverilog,
            "-g2012",
            "-s",
            "apu_irq_topology_tb",
            "-o",
            str(simulation),
            str(converted),
        ],
        check=True,
    )
    result = subprocess.run([vvp, str(simulation)], text=True, capture_output=True, check=True)
    assert "APU-P1 integrated IRQ ownership topology passed" in result.stdout


def test_apu_p3_loader_control_store_and_sequencer(tmp_path: Path) -> None:
    iverilog = shutil.which("iverilog")
    vvp = shutil.which("vvp")
    sv2v = shutil.which("sv2v")
    if iverilog is None or vvp is None or sv2v is None:
        return

    source = """
.build_id 0x1122334455667788
    .entry 0 start start last 16 64
    .entry 1 start start last 16 64
    .entry 2 start start last 16 64
start:
  movi r0, 5
  movi r1, 3
  add r2, r0, r1
  sub r9, r0, r1
  and r10, r0, r1
  or r11, r0, r1
  xor r12, r0, r1
  movi r13, 1
  shl r14, r0, r13
  shr r15, r14, r13
  movi r4, 0xfffffff0
  sar r4, r4, r13
  cmp r1, r0
  movi r3, 0xa5 if=ne
  mov r2, r0 if=slt
  movi r2, 8 if=sge
  movi r2, 9 if=ult
  movi r2, 10 if=uge
  min r10, r4, r0, 1
  max r11, r4, r0, 1
  sat r5, r4, 40
  movi r12, 7 if=input_exhausted
  movi r12, 8 if=input_ready
  movi r13, 9 if=output_ready
  movi r13, 10 if=kernel_done
  movi r14, 11 if=transport_done
  movi r7, 2
  loop_setup 0, r7
loop_body:
  add r8, r8, r0
  loop_back 0, loop_body
  call_fwd sub if=ne
done:
  end
sub:
  movi r6, 0x66
last:
  ret
"""
    assembly = assemble(source)
    reference = Machine(
        assembly.instructions,
        assembly.entries[0],
        predicate_inputs=PredicateInputs(
            input_exhausted=True,
            input_ready=False,
            output_ready=True,
            kernel_done=False,
            transport_done=True,
        ),
        timeout=16,
    ).run()
    assert reference["retired"] == 36
    assert reference["registers"] == [
        5,
        3,
        9,
        0xA5,
        0xFFFFFFF8,
        0xFFFFFFF8,
        0x66,
        2,
        10,
        2,
        0xFFFFFFF8,
        5,
        7,
        9,
        11,
        5,
    ]
    bundle = assembly.bundle
    image = tmp_path / "apu_p3_image.hex"
    image.write_text(
        "".join(
            f"{int.from_bytes(bundle[offset : offset + 4], 'little'):08x}\n"
            for offset in range(0, len(bundle), 4)
        ),
        encoding="utf-8",
    )

    invalid_source = """
.entry 0 start start done 1 16
.entry 1 start start done 1 16
.entry 2 start start done 1 16
start:
  nop
  nop
  nop
done:
  end
"""
    invalid_bundle = bytearray(assemble(invalid_source).bundle)
    invalid_instructions = (
        Instruction(0, ControlOpcode.CALL_FWD, predicate=1, immediate=1),
        Instruction(0, ControlOpcode.NOP),
        Instruction(0, ControlOpcode.RET),
        Instruction(0, ControlOpcode.END),
    )
    for pc, instruction in enumerate(invalid_instructions):
        struct.pack_into("<Q", invalid_bundle, 192 + pc * 8, instruction.encode())
    struct.pack_into("<I", invalid_bundle, 44, crc32_iso_hdlc(invalid_bundle[64:]))
    invalid_image = tmp_path / "apu_p3_invalid_control.hex"
    invalid_image.write_text(
        "".join(
            f"{int.from_bytes(invalid_bundle[offset : offset + 4], 'little'):08x}\n"
            for offset in range(0, len(invalid_bundle), 4)
        ),
        encoding="utf-8",
    )

    invalid_loop_source = """
.entry 0 start start done 1 16
.entry 1 start start done 1 16
.entry 2 start start done 1 16
start:
  nop
  nop
  nop
  nop
done:
  end
"""
    invalid_loop_bundle = bytearray(assemble(invalid_loop_source).bundle)
    invalid_loop_instructions = (
        Instruction(0, ControlOpcode.JUMP_FWD, predicate=1, immediate=1),
        Instruction(0, ControlOpcode.LOOP_SETUP, src0=0, aux=0),
        Instruction(0, ControlOpcode.NOP),
        Instruction(0, ControlOpcode.LOOP_BACK, aux=0, immediate=2),
        Instruction(0, ControlOpcode.END),
    )
    for pc, instruction in enumerate(invalid_loop_instructions):
        struct.pack_into("<Q", invalid_loop_bundle, 192 + pc * 8, instruction.encode())
    struct.pack_into("<I", invalid_loop_bundle, 44, crc32_iso_hdlc(invalid_loop_bundle[64:]))
    invalid_loop_image = tmp_path / "apu_p3_invalid_loop.hex"
    invalid_loop_image.write_text(
        "".join(
            f"{int.from_bytes(invalid_loop_bundle[offset : offset + 4], 'little'):08x}\n"
            for offset in range(0, len(invalid_loop_bundle), 4)
        ),
        encoding="utf-8",
    )
    diagnostic_source = """
.entry 0 start start last 1 16
.entry 1 start start last 1 16
.entry 2 start start last 1 16
start:
  nop
  nop
  end
  nop
last:
  end
"""
    diagnostic_bundle = bytearray(assemble(diagnostic_source).bundle)
    diagnostic_instructions = (
        Instruction(0, ControlOpcode.JUMP_FWD, predicate=1, immediate=3),
        Instruction(0, ControlOpcode.RET),
        Instruction(0, ControlOpcode.END),
        Instruction(0, ControlOpcode.NOP),
        Instruction(0, ControlOpcode.RET),
    )
    for pc, instruction in enumerate(diagnostic_instructions):
        struct.pack_into("<Q", diagnostic_bundle, 192 + pc * 8, instruction.encode())
    struct.pack_into("<I", diagnostic_bundle, 44, crc32_iso_hdlc(diagnostic_bundle[64:]))
    diagnostic_image = tmp_path / "apu_p3_diagnostic_order.hex"
    diagnostic_image.write_text(
        "".join(
            f"{int.from_bytes(diagnostic_bundle[offset : offset + 4], 'little'):08x}\n"
            for offset in range(0, len(diagnostic_bundle), 4)
        ),
        encoding="utf-8",
    )

    lexical_source = """
.entry 0 start start last 1 16
.entry 1 start start last 1 16
.entry 2 start start last 1 16
start:
  nop
  nop
  nop
  nop
last:
  end
"""
    lexical_bundle = bytearray(assemble(lexical_source).bundle)
    lexical_instructions = (
        Instruction(0, ControlOpcode.JUMP_FWD, predicate=1, immediate=1),
        Instruction(0, ControlOpcode.NOP),
        Instruction(0, ControlOpcode.RET),
        Instruction(0, 9),
        Instruction(0, ControlOpcode.END),
    )
    for pc, instruction in enumerate(lexical_instructions):
        struct.pack_into("<Q", lexical_bundle, 192 + pc * 8, instruction.encode())
    struct.pack_into("<I", lexical_bundle, 44, crc32_iso_hdlc(lexical_bundle[64:]))
    lexical_image = tmp_path / "apu_p3_lexical_path_image.hex"
    lexical_image.write_text(
        "".join(
            f"{int.from_bytes(lexical_bundle[offset : offset + 4], 'little'):08x}\n"
            for offset in range(0, len(lexical_bundle), 4)
        ),
        encoding="utf-8",
    )

    deep_lines = [
        ".entry 0 start start last 1 4096",
        ".entry 1 start start last 1 4096",
        ".entry 2 start start last 1 4096",
        "start:",
    ]
    for index in range(65):
        if index != 0:
            deep_lines.append(f"branch_{index}:")
        deep_lines.append(f"  jump_fwd branch_{index + 1} if=eq")
        deep_lines.append(f"fallback_{index}:")
        deep_lines.append("  end")
    deep_lines.extend(("branch_65:", "last:", "  end"))
    deep_bundle = assemble("\n".join(deep_lines)).bundle
    deep_image = tmp_path / "apu_p3_deep_path_image.hex"
    deep_image.write_text(
        "".join(
            f"{int.from_bytes(deep_bundle[offset : offset + 4], 'little'):08x}\n"
            for offset in range(0, len(deep_bundle), 4)
        ),
        encoding="utf-8",
    )

    common = ROOT / "rtl/managed/clusterip/common/rtl"
    multimedia = ROOT / "rtl/ip/multimedia"
    source_list = tmp_path / "apu_p3_microcode.fl"
    source_list.write_text(
        "\n".join(
            [
                "+define+SV_ASSRT_DISABLE",
                f"+incdir+{multimedia}",
                f"+incdir+{common}",
                str(ROOT / "rtl/tech/tc_sram.sv"),
                str(multimedia / "apu_microcode_pkg.sv"),
                str(multimedia / "apu_control_store.sv"),
                str(multimedia / "apu_microcode_loader.sv"),
                str(multimedia / "apu_codec_sequencer.sv"),
                str(ROOT / "tests/rtl/apu_p3_microcode_tb.sv"),
                "",
            ]
        ),
        encoding="utf-8",
    )
    converted = tmp_path / "apu_p3_microcode_tb.v"
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
    simulation = tmp_path / "apu_p3_microcode_tb"
    subprocess.run(
        [
            iverilog,
            "-g2012",
            "-s",
            "apu_p3_microcode_tb",
            "-o",
            str(simulation),
            str(converted),
        ],
        check=True,
    )
    result = subprocess.run(
        [
            vvp,
            str(simulation),
            f"+IMAGE={image}",
            f"+INVALID_CF_IMAGE={invalid_image}",
            f"+INVALID_LOOP_IMAGE={invalid_loop_image}",
            f"+DIAGNOSTIC_IMAGE={diagnostic_image}",
            f"+LEXICAL_PATH_IMAGE={lexical_image}",
            f"+DEEP_PATH_IMAGE={deep_image}",
        ],
        check=True,
        capture_output=True,
        text=True,
    )
    assert "APU-P3 loader, control store, and sequencer tests passed" in result.stdout


def test_apu_p3_control_store_profile_mapping() -> None:
    source = (ROOT / "rtl/ip/multimedia/apu_control_store.sv").read_text(encoding="utf-8")
    assert source.count("tc_sram_1024x32 u_control_") == 8
    assert "if (Depth == 4096) begin : gen_expanded_banks" in source
    assert "`ifdef HAVE_SRAM_MACRO" in source
    assert "logic [63:0] mem" in source
    assert "[0:Depth-1];" in source
    assert source.index("logic [63:0] mem") > source.index("`else")


def test_apu_p3_apb_dma_loader_integration(tmp_path: Path) -> None:
    iverilog = shutil.which("iverilog")
    vvp = shutil.which("vvp")
    sv2v = shutil.which("sv2v")
    if iverilog is None or vvp is None or sv2v is None:
        return

    source = """
.build_id 0x1122334455667788
.entry 0 start start done 16 64
.entry 1 start start done 16 64
.entry 2 start start done 16 64
start:
  movi r0, 1
done:
  end
"""
    bundle = assemble(source).bundle
    image = tmp_path / "apu_p3_integration_image.hex"
    image.write_text(
        "".join(
            f"{int.from_bytes(bundle[offset : offset + 4], 'little'):08x}\n"
            for offset in range(0, len(bundle), 4)
        ),
        encoding="utf-8",
    )

    common = ROOT / "rtl/managed/clusterip/common/rtl"
    multimedia = ROOT / "rtl/ip/multimedia"
    source_list = tmp_path / "apu_p3_integration.fl"
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
                str(multimedia / "apu_microcode_pkg.sv"),
                str(multimedia / "apu_dma.sv"),
                str(multimedia / "apu_ring_scheduler.sv"),
                str(multimedia / "apu_stream_router.sv"),
                str(multimedia / "apu_control_store.sv"),
                str(multimedia / "apu_microcode_loader.sv"),
                str(multimedia / "apu_local_sram.sv"),
                str(multimedia / "apu_kws_engine.sv"),
                str(multimedia / "apu_kws_sram_client.sv"),
                str(multimedia / "apu_kws_model_loader.sv"),
                str(multimedia / "apu_bitstream_engine.sv"),
                str(multimedia / "apu_entropy_engine.sv"),
                str(multimedia / "apu_reconstruction_engine.sv"),
                str(multimedia / "apu_transform_engine.sv"),
                str(multimedia / "apu_resampler.sv"),
                str(multimedia / "apu_kernel_engine.sv"),
                str(multimedia / "apu_primitive_dispatcher.sv"),
                str(multimedia / "apu_codec_sequencer.sv"),
                str(multimedia / "apu_codec_transport.sv"),
                str(multimedia / "apu_codec_controller.sv"),
                str(multimedia / "apu_reg.sv"),
                str(multimedia / "apb4_apu.sv"),
                str(ROOT / "tests/rtl/apu_p3_integration_tb.sv"),
                "",
            ]
        ),
        encoding="utf-8",
    )
    converted = tmp_path / "apu_p3_integration_tb.v"
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
    simulation = tmp_path / "apu_p3_integration_tb"
    subprocess.run(
        [
            iverilog,
            "-g2012",
            "-s",
            "apu_p3_integration_tb",
            "-o",
            str(simulation),
            str(converted),
        ],
        check=True,
    )
    result = subprocess.run(
        [vvp, str(simulation), f"+IMAGE={image}"],
        check=True,
        capture_output=True,
        text=True,
    )
    assert "APU-P3 APB, DMA, loader integration passed" in result.stdout


def test_apu_p5_product_scope_remains_coreless_and_later_features_fail_closed() -> None:
    top = (ROOT / "rtl/ip/multimedia/apb4_apu.sv").read_text(encoding="utf-8")
    register_block = (ROOT / "rtl/ip/multimedia/apu_reg.sv").read_text(encoding="utf-8")
    product_filelist = (ROOT / "rtl/mini/filelist/ip.fl").read_text(encoding="utf-8")
    normalized_top = " ".join(top.split())
    assert ".launch_i(s_codec_seq_launch)" in normalized_top
    assert ".start_i (s_ring_kick)" in normalized_top
    assert "COMMAND_MODEL_LOAD" in register_block
    assert "s_merged_write[3:2] != 2'd0" in register_block
    assert "apu_interpreter" not in product_filelist
    assert "apu_primitives.py" not in product_filelist
    assert "apu_p4_primitives_tb" not in product_filelist
    assert "apu_p4_loader_tb" not in product_filelist
    assert "apu_p4_sequencer_tb" not in product_filelist
    assert "apu_p3_microcode_tb" not in product_filelist
    assert "VerificationCrcBypass" not in product_filelist
    assert ".VerificationCrcBypass" not in top
    assert "VerificationControlFlowBypass" not in product_filelist
    assert ".VerificationControlFlowBypass" not in top
    for production_module in (
        "apu_local_sram.sv",
        "apu_bitstream_engine.sv",
        "apu_entropy_engine.sv",
        "apu_kernel_engine.sv",
        "apu_primitive_dispatcher.sv",
        "apu_codec_transport.sv",
        "apu_codec_controller.sv",
    ):
        assert production_module in product_filelist
    for forbidden in ("hazard3", "vexiiriscv", "rv32", "dsp_core"):
        assert forbidden not in top.lower()


def test_apu_p2_stream_router(tmp_path: Path) -> None:
    iverilog = shutil.which("iverilog")
    vvp = shutil.which("vvp")
    if iverilog is None or vvp is None:
        return

    common = ROOT / "rtl/managed/clusterip/common/rtl"
    source_list = tmp_path / "apu_stream_router.fl"
    source_list.write_text(
        "\n".join(
            [
                f"+incdir+{common}",
                f"+incdir+{common / 'interface'}",
                str(common / "interface/axi4_stream_if.sv"),
                str(common / "utils/fifo.sv"),
                str(ROOT / "rtl/ip/multimedia/apu_stream_router.sv"),
                str(ROOT / "tests/rtl/apu_stream_router_tb.sv"),
                "",
            ]
        ),
        encoding="utf-8",
    )
    converted = tmp_path / "apu_stream_router_tb.v"
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
    simulation = tmp_path / "apu_stream_router_tb"
    subprocess.run(
        [
            iverilog,
            "-g2012",
            "-s",
            "apu_stream_router_tb",
            "-o",
            str(simulation),
            str(converted),
        ],
        check=True,
    )
    result = subprocess.run([vvp, str(simulation)], check=True, capture_output=True, text=True)
    assert "APU-P2 stream router tests passed" in result.stdout


def test_apu_p2_private_dma(tmp_path: Path) -> None:
    iverilog = shutil.which("iverilog")
    vvp = shutil.which("vvp")
    if iverilog is None or vvp is None:
        return

    common = ROOT / "rtl/managed/clusterip/common/rtl"
    source_list = tmp_path / "apu_dma.fl"
    source_list.write_text(
        "\n".join(
            [
                f"+incdir+{common}",
                f"+incdir+{common / 'interface'}",
                f"+incdir+{ROOT / 'rtl/ip/multimedia'}",
                str(common / "interface/axi4_if.sv"),
                str(common / "interface/axi4_stream_if.sv"),
                str(common / "utils/register.sv"),
                str(ROOT / "rtl/ip/peripheral/dma_axi4_master.sv"),
                str(ROOT / "rtl/ip/multimedia/apu_dma.sv"),
                str(ROOT / "tests/rtl/apu_dma_tb.sv"),
                "",
            ]
        ),
        encoding="utf-8",
    )
    converted = tmp_path / "apu_dma_tb.v"
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
    simulation = tmp_path / "apu_dma_tb"
    subprocess.run(
        [iverilog, "-g2012", "-s", "apu_dma_tb", "-o", str(simulation), str(converted)],
        check=True,
    )
    result = subprocess.run([vvp, str(simulation)], check=True, capture_output=True, text=True)
    assert "APU-P2 DMA tests passed" in result.stdout


def test_apu_p2_ring_scheduler_backend(tmp_path: Path) -> None:
    iverilog = shutil.which("iverilog")
    vvp = shutil.which("vvp")
    sv2v = shutil.which("sv2v")
    if iverilog is None or vvp is None or sv2v is None:
        return

    common = ROOT / "rtl/managed/clusterip/common/rtl"
    source_list = tmp_path / "apu_ring_scheduler.fl"
    source_list.write_text(
        "\n".join(
            [
                f"+incdir+{common}",
                f"+incdir+{common / 'interface'}",
                f"+incdir+{ROOT / 'rtl/ip/multimedia'}",
                str(common / "interface/axi4_stream_if.sv"),
                str(ROOT / "rtl/ip/multimedia/apu_ring_scheduler.sv"),
                str(ROOT / "tests/rtl/apu_p2_backend.sv"),
                str(ROOT / "tests/rtl/apu_ring_scheduler_tb.sv"),
                "",
            ]
        ),
        encoding="utf-8",
    )
    converted = tmp_path / "apu_ring_scheduler_tb.v"
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
    simulation = tmp_path / "apu_ring_scheduler_tb"
    subprocess.run(
        [
            iverilog,
            "-g2012",
            "-s",
            "apu_ring_scheduler_tb",
            "-o",
            str(simulation),
            str(converted),
        ],
        check=True,
    )
    result = subprocess.run([vvp, str(simulation)], check=True, capture_output=True, text=True)
    assert "APU-P2 ring scheduler/backend tests passed" in result.stdout


def test_apu_p2_integrated_dma_ring_backend(tmp_path: Path) -> None:
    iverilog = shutil.which("iverilog")
    vvp = shutil.which("vvp")
    sv2v = shutil.which("sv2v")
    if iverilog is None or vvp is None or sv2v is None:
        return

    common = ROOT / "rtl/managed/clusterip/common/rtl"
    multimedia = ROOT / "rtl/ip/multimedia"
    source_list = tmp_path / "apu_p2_integration.fl"
    source_list.write_text(
        "\n".join(
            [
                f"+incdir+{common}",
                f"+incdir+{common / 'interface'}",
                f"+incdir+{common / 'cdc'}",
                f"+incdir+{multimedia}",
                str(common / "interface/axi4_if.sv"),
                str(common / "interface/axi4_stream_if.sv"),
                str(common / "utils/register.sv"),
                str(common / "utils/fifo.sv"),
                str(common / "utils/xchecker.sv"),
                str(common / "utils/spill_register.sv"),
                str(common / "utils/bin2gray.sv"),
                str(common / "utils/gray2bin.sv"),
                str(common / "stream/round_robin_arbiter.sv"),
                str(common / "cdc/cdc_sync.sv"),
                str(common / "cdc/cdc_rst_ctrlr.sv"),
                str(common / "cdc/cdc_2phase.sv"),
                str(common / "clkrst/rst_sync.sv"),
                str(ROOT / "rtl/ip/peripheral/dma_axi4_master.sv"),
                str(multimedia / "apu_dma.sv"),
                str(multimedia / "apu_ring_scheduler.sv"),
                str(ROOT / "rtl/mini/top/soc_common_cdc.sv"),
                str(ROOT / "rtl/mini/top/axi4_async_bridge.sv"),
                str(ROOT / "rtl/mini/top/axi4_target_guard.sv"),
                str(ROOT / "rtl/mini/top/hp_axi4_mux3.sv"),
                str(ROOT / "tests/rtl/apu_p2_transport_backend.sv"),
                str(ROOT / "tests/rtl/apu_p2_integration_tb.sv"),
                "",
            ]
        ),
        encoding="utf-8",
    )
    converted = tmp_path / "apu_p2_integration_tb.v"
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
    simulation = tmp_path / "apu_p2_integration_tb"
    subprocess.run(
        [
            iverilog,
            "-g2012",
            "-s",
            "apu_p2_integration_tb",
            "-o",
            str(simulation),
            str(converted),
        ],
        check=True,
    )
    result = subprocess.run([vvp, str(simulation)], check=True, capture_output=True, text=True)
    assert "APU-P2 integrated DMA/ring/backend tests passed" in result.stdout


def test_apu_p2_gateway_a_round_robin_fairness(tmp_path: Path) -> None:
    iverilog = shutil.which("iverilog")
    vvp = shutil.which("vvp")
    sv2v = shutil.which("sv2v")
    if iverilog is None or vvp is None or sv2v is None:
        return

    common = ROOT / "rtl/managed/clusterip/common/rtl"
    source_list = tmp_path / "gateway_a_rr.fl"
    source_list.write_text(
        "\n".join(
            [
                f"+incdir+{common}",
                f"+incdir+{common / 'interface'}",
                str(common / "interface/axi4_if.sv"),
                str(common / "utils/register.sv"),
                str(common / "stream/round_robin_arbiter.sv"),
                str(ROOT / "rtl/mini/top/hp_axi4_mux3.sv"),
                str(ROOT / "tests/rtl/hp_axi4_mux3_rr_tb.sv"),
                "",
            ]
        ),
        encoding="utf-8",
    )
    converted = tmp_path / "hp_axi4_mux3_rr_tb.v"
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
    simulation = tmp_path / "hp_axi4_mux3_rr_tb"
    subprocess.run(
        [
            iverilog,
            "-g2012",
            "-s",
            "hp_axi4_mux3_rr_tb",
            "-o",
            str(simulation),
            str(converted),
        ],
        check=True,
    )
    result = subprocess.run([vvp, str(simulation)], check=True, capture_output=True, text=True)
    assert (
        "APU-P2 Gateway A round-robin fairness passed with read/write/mixed retention"
        in result.stdout
    )


def test_apu_p7_kws_engine_directed(tmp_path: Path) -> None:
    iverilog = shutil.which("iverilog")
    vvp = shutil.which("vvp")
    sv2v = shutil.which("sv2v")
    if iverilog is None or vvp is None or sv2v is None:
        return
    common = ROOT / "rtl/managed/clusterip/common/rtl"
    multimedia = ROOT / "rtl/ip/multimedia"
    source_list = tmp_path / "apu_kws_engine.fl"
    source_list.write_text(
        "\n".join(
            [
                "+define+SV_ASSRT_DISABLE",
                f"+incdir+{common}",
                f"+incdir+{common / 'interface'}",
                f"+incdir+{multimedia}",
                str(common / "interface/axi4_stream_if.sv"),
                str(multimedia / "apu_kws_sram_client.sv"),
                str(multimedia / "apu_kws_engine.sv"),
                str(ROOT / "tests/rtl/apu_kws_engine_tb.sv"),
                "",
            ]
        ),
        encoding="utf-8",
    )
    converted = tmp_path / "apu_kws_engine.v"
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
    simulation = tmp_path / "apu_kws_engine"
    subprocess.run(
        [iverilog, "-g2012", "-s", "apu_kws_engine_tb", "-o", str(simulation), str(converted)],
        check=True,
    )
    command = [vvp, str(simulation)]
    feature = (
        ROOT
        / ".cache/retrosoc/sources/apu-kws-mfcc/datasets/kws01"
        / "tst_000000_Stop_7.bin"
    )
    if KWS_MODEL.is_file() and feature.is_file():
        image = import_tflite(KWS_MODEL)
        apum_hex = tmp_path / "kws_apum.hex"
        mfcc_hex = tmp_path / "kws_mfcc.hex"
        layers_hex = tmp_path / "kws_layers.hex"
        apum_hex.write_text(
            "".join(
                f"{int.from_bytes(image[offset : offset + 4], 'little'):08x}\n"
                for offset in range(0, len(image), 4)
            ),
            encoding="ascii",
        )
        mfcc_hex.write_text(
            "".join(f"{value:02x}\n" for value in feature.read_bytes()),
            encoding="ascii",
        )
        layers = infer_apum(image, feature.read_bytes())
        layers_hex.write_text(
            "".join(f"{value & 0xff:02x}\n" for layer in layers for value in layer),
            encoding="ascii",
        )
        command.extend(
            (
                f"+APUM_HEX={apum_hex}",
                f"+MFCC_HEX={mfcc_hex}",
                f"+LAYERS_HEX={layers_hex}",
            )
        )
    result = subprocess.run(command, check=True, capture_output=True, text=True)
    assert "APU-P7 KWS engine directed test passed" in result.stdout


def test_apu_p7_kws_sram_layout_and_isolation(tmp_path: Path) -> None:
    iverilog = shutil.which("iverilog")
    vvp = shutil.which("vvp")
    sv2v = shutil.which("sv2v")
    if iverilog is None or vvp is None or sv2v is None:
        return
    multimedia = ROOT / "rtl/ip/multimedia"
    source_list = tmp_path / "apu_kws_sram_client.fl"
    source_list.write_text(
        "\n".join(
            [
                f"+incdir+{multimedia}",
                str(ROOT / "rtl/tech/tc_sram.sv"),
                str(multimedia / "apu_local_sram.sv"),
                str(multimedia / "apu_kws_sram_client.sv"),
                str(ROOT / "tests/rtl/apu_kws_sram_client_tb.sv"),
                "",
            ]
        ),
        encoding="utf-8",
    )
    converted = tmp_path / "apu_kws_sram_client.v"
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
    simulation = tmp_path / "apu_kws_sram_client"
    subprocess.run(
        [
            iverilog,
            "-g2012",
            "-s",
            "apu_kws_sram_client_tb",
            "-o",
            str(simulation),
            str(converted),
        ],
        check=True,
    )
    result = subprocess.run([vvp, str(simulation)], check=True, capture_output=True, text=True)
    assert "PASS: APU P7 banks10..25 model/scratch SRAM isolation" in result.stdout


def test_apu_p7_kws_job_lifecycle(tmp_path: Path) -> None:
    iverilog = shutil.which("iverilog")
    vvp = shutil.which("vvp")
    sv2v = shutil.which("sv2v")
    if iverilog is None or vvp is None or sv2v is None:
        return
    common = ROOT / "rtl/managed/clusterip/common/rtl"
    multimedia = ROOT / "rtl/ip/multimedia"
    source_list = tmp_path / "apu_kws_job.fl"
    source_list.write_text(
        "\n".join(
            [
                "+define+SV_ASSRT_DISABLE",
                f"+incdir+{common}",
                f"+incdir+{multimedia}",
                str(multimedia / "apu_codec_controller.sv"),
                str(ROOT / "tests/rtl/apu_kws_job_tb.sv"),
                "",
            ]
        ),
        encoding="utf-8",
    )
    converted = tmp_path / "apu_kws_job.v"
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
    simulation = tmp_path / "apu_kws_job"
    subprocess.run(
        [iverilog, "-g2012", "-s", "apu_kws_job_tb", "-o", str(simulation), str(converted)],
        check=True,
    )
    result = subprocess.run([vvp, str(simulation)], check=True, capture_output=True, text=True)
    assert "PASS: APU P7 direct/ring KWS job lifecycle" in result.stdout


def test_apu_p7_kws_loader_admission_and_abort(tmp_path: Path) -> None:
    iverilog = shutil.which("iverilog")
    vvp = shutil.which("vvp")
    sv2v = shutil.which("sv2v")
    if iverilog is None or vvp is None or sv2v is None:
        return
    multimedia = ROOT / "rtl/ip/multimedia"
    source_list = tmp_path / "apu_kws_loader.fl"
    source_list.write_text(
        "\n".join(
            [
                f"+incdir+{multimedia}",
                str(multimedia / "apu_kws_model_loader.sv"),
                str(ROOT / "tests/rtl/apu_kws_loader_tb.sv"),
                "",
            ]
        ),
        encoding="utf-8",
    )
    converted = tmp_path / "apu_kws_loader.v"
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
    simulation = tmp_path / "apu_kws_loader"
    subprocess.run(
        [iverilog, "-g2012", "-s", "apu_kws_loader_tb", "-o", str(simulation), str(converted)],
        check=True,
    )
    command = [vvp, str(simulation)]
    if KWS_MODEL.is_file():
        apum_hex = tmp_path / "kws_apum.hex"
        bad_crc_hex = tmp_path / "kws_bad_crc.hex"
        bad_profile_hex = tmp_path / "kws_bad_profile.hex"
        image = import_tflite(KWS_MODEL)
        apum_hex.write_text(
            "".join(
                f"{int.from_bytes(image[offset : offset + 4], 'little'):08x}\n"
                for offset in range(0, len(image), 4)
            ),
            encoding="ascii",
        )
        bad_crc = bytearray(image)
        bad_crc[0x1200] ^= 1
        bad_crc_hex.write_text(
            "".join(
                f"{int.from_bytes(bad_crc[offset : offset + 4], 'little'):08x}\n"
                for offset in range(0, len(bad_crc), 4)
            ),
            encoding="ascii",
        )
        bad_profile = bytearray(image)
        bad_profile[0x1000] ^= 1
        bad_profile_payload = bad_profile[64:]
        _patch_crc32(bad_profile_payload, 0x1200 - 64, 0xB9034B22)
        bad_profile[64:] = bad_profile_payload
        bad_profile_hex.write_text(
            "".join(
                f"{int.from_bytes(bad_profile[offset : offset + 4], 'little'):08x}\n"
                for offset in range(0, len(bad_profile), 4)
            ),
            encoding="ascii",
        )
        command.append(f"+APUM_HEX={apum_hex}")
        command.append(f"+APUM_BAD_CRC_HEX={bad_crc_hex}")
        command.append(f"+APUM_BAD_PROFILE_HEX={bad_profile_hex}")
    result = subprocess.run(command, check=True, capture_output=True, text=True)
    assert "APU-P7 KWS loader admission and abort test passed" in result.stdout
