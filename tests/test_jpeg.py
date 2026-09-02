"""Directed RTL tests for the JPEG accelerator."""

from __future__ import annotations

import re
import shutil
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def _write_hex_bytes(path: Path, data: bytes) -> None:
    path.write_text("".join(f"{value:02x}\n" for value in data), encoding="ascii")


def _write_hex_words(path: Path, data: list[int]) -> None:
    path.write_text("".join(f"{value:08x}\n" for value in data), encoding="ascii")


def test_jpeg_forward_inverse_transform(tmp_path: Path) -> None:
    iverilog = shutil.which("iverilog")
    vvp = shutil.which("vvp")
    if iverilog is None or vvp is None:
        return
    simulation = tmp_path / "jpeg_transform_tb"
    subprocess.run(
        [
            iverilog,
            "-g2012",
            "-DSV_ASSRT_DISABLE",
            "-I",
            str(ROOT / "rtl/managed/clusterip/common/rtl"),
            "-s",
            "jpeg_transform_tb",
            "-o",
            str(simulation),
            str(ROOT / "rtl/managed/clusterip/common/rtl/utils/register.sv"),
            str(ROOT / "rtl/ip/multimedia/jpeg_transform.sv"),
            str(ROOT / "tests/rtl/jpeg_transform_tb.sv"),
        ],
        check=True,
    )
    result = subprocess.run([vvp, str(simulation)], text=True, capture_output=True, check=True)
    assert "JPEG transform tests passed" in result.stdout


def test_jpeg_quantize_dequantize(tmp_path: Path) -> None:
    iverilog = shutil.which("iverilog")
    vvp = shutil.which("vvp")
    if iverilog is None or vvp is None:
        return
    simulation = tmp_path / "jpeg_quantizer_tb"
    subprocess.run(
        [
            iverilog,
            "-g2012",
            "-DSV_ASSRT_DISABLE",
            "-I",
            str(ROOT / "rtl/managed/clusterip/common/rtl"),
            "-s",
            "jpeg_quantizer_tb",
            "-o",
            str(simulation),
            str(ROOT / "rtl/managed/clusterip/common/rtl/utils/register.sv"),
            str(ROOT / "rtl/ip/multimedia/jpeg_quantizer.sv"),
            str(ROOT / "tests/rtl/jpeg_quantizer_tb.sv"),
        ],
        check=True,
    )
    result = subprocess.run([vvp, str(simulation)], text=True, capture_output=True, check=True)
    assert "JPEG quantizer tests passed" in result.stdout


def test_jpeg_coefficient_engine(tmp_path: Path) -> None:
    iverilog = shutil.which("iverilog")
    vvp = shutil.which("vvp")
    if iverilog is None or vvp is None:
        return
    simulation = tmp_path / "jpeg_coefficient_engine_tb"
    subprocess.run(
        [
            iverilog,
            "-g2012",
            "-DSV_ASSRT_DISABLE",
            "-I",
            str(ROOT / "rtl/managed/clusterip/common/rtl"),
            "-s",
            "jpeg_coefficient_engine_tb",
            "-o",
            str(simulation),
            str(ROOT / "rtl/managed/clusterip/common/rtl/utils/register.sv"),
            str(ROOT / "rtl/ip/multimedia/jpeg_transform.sv"),
            str(ROOT / "rtl/ip/multimedia/jpeg_quantizer.sv"),
            str(ROOT / "rtl/ip/multimedia/jpeg_coefficient_engine.sv"),
            str(ROOT / "tests/rtl/jpeg_coefficient_engine_tb.sv"),
        ],
        check=True,
    )
    result = subprocess.run([vvp, str(simulation)], text=True, capture_output=True, check=True)
    assert "JPEG coefficient engine test passed" in result.stdout


def test_jpeg_entropy_encoder(tmp_path: Path) -> None:
    iverilog = shutil.which("iverilog")
    vvp = shutil.which("vvp")
    if iverilog is None or vvp is None:
        return
    simulation = tmp_path / "jpeg_entropy_encoder_tb"
    subprocess.run(
        [
            iverilog,
            "-g2012",
            "-DSV_ASSRT_DISABLE",
            "-I",
            str(ROOT / "rtl/managed/clusterip/common/rtl"),
            "-s",
            "jpeg_entropy_encoder_tb",
            "-o",
            str(simulation),
            str(ROOT / "rtl/managed/clusterip/common/rtl/utils/register.sv"),
            str(ROOT / "rtl/ip/multimedia/jpeg_entropy_encoder.sv"),
            str(ROOT / "tests/rtl/jpeg_entropy_encoder_tb.sv"),
        ],
        check=True,
    )
    result = subprocess.run([vvp, str(simulation)], text=True, capture_output=True, check=True)
    assert "JPEG entropy encoder tests passed" in result.stdout


def test_jpeg_bit_packer_and_stuffing(tmp_path: Path) -> None:
    iverilog = shutil.which("iverilog")
    vvp = shutil.which("vvp")
    if iverilog is None or vvp is None:
        return
    simulation = tmp_path / "jpeg_bit_packer_tb"
    subprocess.run(
        [
            iverilog,
            "-g2012",
            "-DSV_ASSRT_DISABLE",
            "-I",
            str(ROOT / "rtl/managed/clusterip/common/rtl"),
            "-s",
            "jpeg_bit_packer_tb",
            "-o",
            str(simulation),
            str(ROOT / "rtl/managed/clusterip/common/rtl/utils/register.sv"),
            str(ROOT / "rtl/ip/multimedia/jpeg_bit_packer.sv"),
            str(ROOT / "tests/rtl/jpeg_bit_packer_tb.sv"),
        ],
        check=True,
    )
    result = subprocess.run([vvp, str(simulation)], text=True, capture_output=True, check=True)
    assert "JPEG bit packer tests passed" in result.stdout


def test_jpeg_apb_register_path(tmp_path: Path) -> None:
    iverilog = shutil.which("iverilog")
    vvp = shutil.which("vvp")
    sv2v = shutil.which("sv2v")
    if iverilog is None or vvp is None or sv2v is None:
        return
    source_list = tmp_path / "jpeg_reg.fl"
    source_list.write_text(
        "\n".join(
            [
                f"+incdir+{ROOT / 'rtl/managed/clusterip/common/rtl'}",
                f"+incdir+{ROOT / 'rtl/ip/multimedia'}",
                str(ROOT / "rtl/managed/clusterip/common/rtl/interface/apb4_if.sv"),
                str(ROOT / "rtl/managed/clusterip/common/rtl/utils/register.sv"),
                str(ROOT / "rtl/ip/multimedia/jpeg_reg.sv"),
                str(ROOT / "tests/rtl/jpeg_reg_tb.sv"),
                "",
            ]
        ),
        encoding="utf-8",
    )
    converted = tmp_path / "jpeg_reg_tb.v"
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
    simulation = tmp_path / "jpeg_reg_tb"
    subprocess.run(
        [iverilog, "-g2012", "-s", "jpeg_reg_tb", "-o", str(simulation), str(converted)],
        check=True,
    )
    result = subprocess.run([vvp, str(simulation)], text=True, capture_output=True, check=True)
    assert "JPEG APB register tests passed" in result.stdout


def test_jpeg_2d_axi_dma(tmp_path: Path) -> None:
    iverilog = shutil.which("iverilog")
    vvp = shutil.which("vvp")
    sv2v = shutil.which("sv2v")
    if iverilog is None or vvp is None or sv2v is None:
        return
    source_list = tmp_path / "jpeg_dma.fl"
    source_list.write_text(
        "\n".join(
            [
                f"+incdir+{ROOT / 'rtl/managed/clusterip/common/rtl'}",
                f"+incdir+{ROOT / 'rtl/managed/clusterip/common/rtl/interface'}",
                str(ROOT / "rtl/managed/clusterip/common/rtl/interface/axi4_if.sv"),
                str(ROOT / "rtl/managed/clusterip/common/rtl/interface/axi4_stream_if.sv"),
                str(ROOT / "rtl/managed/clusterip/common/rtl/utils/register.sv"),
                str(ROOT / "rtl/ip/peripheral/dma_axi4_master.sv"),
                str(ROOT / "rtl/ip/multimedia/jpeg_dma.sv"),
                str(ROOT / "tests/rtl/jpeg_dma_tb.sv"),
                "",
            ]
        ),
        encoding="utf-8",
    )
    converted = tmp_path / "jpeg_dma_tb.v"
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
    simulation = tmp_path / "jpeg_dma_tb"
    subprocess.run(
        [iverilog, "-g2012", "-s", "jpeg_dma_tb", "-o", str(simulation), str(converted)],
        check=True,
    )
    result = subprocess.run([vvp, str(simulation)], text=True, capture_output=True, check=True)
    assert "JPEG DMA tests passed" in result.stdout


def test_jpeg_apb_ring_descriptor_path(tmp_path: Path) -> None:
    iverilog = shutil.which("iverilog")
    vvp = shutil.which("vvp")
    sv2v = shutil.which("sv2v")
    if iverilog is None or vvp is None or sv2v is None:
        return
    multimedia = ROOT / "rtl/ip/multimedia"
    source_list = tmp_path / "apb4_jpeg_ring.fl"
    modules = [
        "jpeg_pkg.sv",
        "jpeg_transform.sv",
        "jpeg_quantizer.sv",
        "jpeg_coefficient_engine.sv",
        "jpeg_entropy_encoder.sv",
        "jpeg_entropy_decoder.sv",
        "jpeg_bit_packer.sv",
        "jpeg_bit_reader.sv",
        "jpeg_byte_unpacker.sv",
        "jpeg_byte_joiner.sv",
        "jpeg_header_writer.sv",
        "jpeg_marker_parser.sv",
        "jpeg_table_store.sv",
        "jpeg_table_cache.sv",
        "jpeg_table_register_bank.sv",
        "jpeg_block_encoder.sv",
        "jpeg_block_decoder.sv",
        "jpeg_mcu_builder.sv",
        "jpeg_mcu_reconstructor.sv",
        "jpeg_encode_core.sv",
        "jpeg_decode_core.sv",
        "jpeg_dma.sv",
        "jpeg_reg.sv",
        "apb4_jpeg.sv",
    ]
    source_list.write_text(
        "\n".join(
            [
                f"+incdir+{ROOT / 'rtl/managed/clusterip/common/rtl'}",
                f"+incdir+{ROOT / 'rtl/managed/clusterip/common/rtl/interface'}",
                f"+incdir+{multimedia}",
                "+define+SV_ASSRT_DISABLE",
                str(ROOT / "rtl/managed/clusterip/common/rtl/interface/apb4_if.sv"),
                str(ROOT / "rtl/managed/clusterip/common/rtl/interface/axi4_if.sv"),
                str(ROOT / "rtl/managed/clusterip/common/rtl/interface/axi4_stream_if.sv"),
                str(ROOT / "rtl/managed/clusterip/common/rtl/utils/register.sv"),
                str(ROOT / "rtl/managed/clusterip/common/rtl/utils/spill_register.sv"),
                str(ROOT / "rtl/tech/tc_sram.sv"),
                str(ROOT / "rtl/ip/peripheral/dma_axi4_master.sv"),
                *(str(multimedia / module) for module in modules),
                str(ROOT / "tests/rtl/apb4_jpeg_ring_tb.sv"),
                "",
            ]
        ),
        encoding="utf-8",
    )
    converted = tmp_path / "apb4_jpeg_ring_tb.v"
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
    simulation = tmp_path / "apb4_jpeg_ring_tb"
    subprocess.run(
        [
            iverilog,
            "-g2012",
            "-DSV_ASSRT_DISABLE",
            "-DPDK_BEHAV",
            "-s",
            "apb4_jpeg_ring_tb",
            "-o",
            str(simulation),
            str(converted),
        ],
        check=True,
    )
    result = subprocess.run([vvp, str(simulation)], text=True, capture_output=True, check=True)
    assert "JPEG APB ring tests passed" in result.stdout


def test_jpeg_table_store(tmp_path: Path) -> None:
    iverilog = shutil.which("iverilog")
    vvp = shutil.which("vvp")
    if iverilog is None or vvp is None:
        return
    simulation = tmp_path / "jpeg_table_store_tb"
    subprocess.run(
        [
            iverilog,
            "-g2012",
            "-DSV_ASSRT_DISABLE",
            "-DPDK_BEHAV",
            "-I",
            str(ROOT / "rtl/managed/clusterip/common/rtl"),
            "-s",
            "jpeg_table_store_tb",
            "-o",
            str(simulation),
            str(ROOT / "rtl/managed/clusterip/common/rtl/utils/register.sv"),
            str(ROOT / "rtl/tech/tc_sram.sv"),
            str(ROOT / "rtl/ip/multimedia/jpeg_table_store.sv"),
            str(ROOT / "tests/rtl/jpeg_table_store_tb.sv"),
        ],
        check=True,
    )
    result = subprocess.run([vvp, str(simulation)], text=True, capture_output=True, check=True)
    assert "JPEG table store tests passed" in result.stdout


def test_jpeg_entropy_decoder(tmp_path: Path) -> None:
    iverilog = shutil.which("iverilog")
    vvp = shutil.which("vvp")
    if iverilog is None or vvp is None:
        return
    simulation = tmp_path / "jpeg_entropy_decoder_tb"
    subprocess.run(
        [
            iverilog,
            "-g2012",
            "-DSV_ASSRT_DISABLE",
            "-I",
            str(ROOT / "rtl/managed/clusterip/common/rtl"),
            "-s",
            "jpeg_entropy_decoder_tb",
            "-o",
            str(simulation),
            str(ROOT / "rtl/managed/clusterip/common/rtl/utils/register.sv"),
            str(ROOT / "rtl/ip/multimedia/jpeg_entropy_decoder.sv"),
            str(ROOT / "tests/rtl/jpeg_entropy_decoder_tb.sv"),
        ],
        check=True,
    )
    result = subprocess.run([vvp, str(simulation)], text=True, capture_output=True, check=True)
    assert "JPEG entropy decoder tests passed" in result.stdout


def test_jpeg_byte_unpacker_and_bit_reader(tmp_path: Path) -> None:
    iverilog = shutil.which("iverilog")
    vvp = shutil.which("vvp")
    sv2v = shutil.which("sv2v")
    if iverilog is None or vvp is None or sv2v is None:
        return
    source_list = tmp_path / "jpeg_bit_reader.fl"
    source_list.write_text(
        "\n".join(
            [
                f"+incdir+{ROOT / 'rtl/managed/clusterip/common/rtl'}",
                str(ROOT / "rtl/managed/clusterip/common/rtl/interface/axi4_stream_if.sv"),
                str(ROOT / "rtl/managed/clusterip/common/rtl/utils/register.sv"),
                str(ROOT / "rtl/ip/multimedia/jpeg_byte_unpacker.sv"),
                str(ROOT / "rtl/ip/multimedia/jpeg_bit_reader.sv"),
                str(ROOT / "tests/rtl/jpeg_bit_reader_tb.sv"),
                "",
            ]
        ),
        encoding="utf-8",
    )
    converted = tmp_path / "jpeg_bit_reader_tb.v"
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
    simulation = tmp_path / "jpeg_bit_reader_tb"
    subprocess.run(
        [iverilog, "-g2012", "-s", "jpeg_bit_reader_tb", "-o", str(simulation),
         str(converted)],
        check=True,
    )
    result = subprocess.run([vvp, str(simulation)], text=True, capture_output=True, check=True)
    assert "JPEG byte unpacker and bit reader tests passed" in result.stdout


def test_jpeg_marker_parser(tmp_path: Path) -> None:
    from jpeg_reference import (
        AC_CHROMA_BITS,
        AC_CHROMA_VALUES,
        AC_LUMA_BITS,
        AC_LUMA_VALUES,
        DC_CHROMA_BITS,
        DC_LUMA_BITS,
        DC_VALUES,
        Sampling,
        _huffman_codes,
        encode_rgb,
        scaled_quant_table,
        LUMA_QUANT,
        CHROMA_QUANT,
    )

    iverilog = shutil.which("iverilog")
    vvp = shutil.which("vvp")
    if iverilog is None or vvp is None:
        return
    encoded = encode_rgb(
        bytes((index * 13) & 0xFF for index in range(17 * 15 * 3)),
        17,
        15,
        quality=75,
        sampling=Sampling.YUV420,
        restart_interval=1,
    )
    hex_path = tmp_path / "jpeg_input.hex"
    tables_path = tmp_path / "jpeg_tables.hex"
    _write_hex_bytes(hex_path, encoded)
    expected_tables = [0] * 3072
    luma_quant = scaled_quant_table(LUMA_QUANT, 75)
    chroma_quant = scaled_quant_table(CHROMA_QUANT, 75)
    for index, value in enumerate(luma_quant):
        expected_tables[index] = value
    for index, value in enumerate(chroma_quant):
        expected_tables[256 + index] = value
    table_specs = (
        (4, DC_LUMA_BITS, DC_VALUES),
        (5, DC_CHROMA_BITS, DC_VALUES),
        (8, AC_LUMA_BITS, AC_LUMA_VALUES),
        (9, AC_CHROMA_BITS, AC_CHROMA_VALUES),
    )
    for kind, bits, values in table_specs:
        for symbol, (code, length) in _huffman_codes(bits, values).items():
            expected_tables[(kind * 256) + symbol] = (length << 16) | code
    _write_hex_words(tables_path, expected_tables)
    simulation = tmp_path / "jpeg_marker_parser_tb"
    subprocess.run(
        [
            iverilog,
            "-g2012",
            "-DSV_ASSRT_DISABLE",
            "-I",
            str(ROOT / "rtl/managed/clusterip/common/rtl"),
            "-s",
            "jpeg_marker_parser_tb",
            "-o",
            str(simulation),
            str(ROOT / "rtl/managed/clusterip/common/rtl/utils/register.sv"),
            str(ROOT / "rtl/ip/multimedia/jpeg_marker_parser.sv"),
            str(ROOT / "tests/rtl/jpeg_marker_parser_tb.sv"),
        ],
        check=True,
    )
    result = subprocess.run(
        [vvp, str(simulation), f"+jpeg_hex={hex_path}", f"+tables_hex={tables_path}",
         f"+jpeg_size={len(encoded)}"],
        text=True,
        capture_output=True,
        check=True,
    )
    assert "JPEG marker parser tests passed" in result.stdout


def test_jpeg_block_decoder_pipeline(tmp_path: Path) -> None:
    iverilog = shutil.which("iverilog")
    vvp = shutil.which("vvp")
    if iverilog is None or vvp is None:
        return
    simulation = tmp_path / "jpeg_block_decoder_tb"
    subprocess.run(
        [
            iverilog,
            "-g2012",
            "-DSV_ASSRT_DISABLE",
            "-I",
            str(ROOT / "rtl/managed/clusterip/common/rtl"),
            "-s",
            "jpeg_block_decoder_tb",
            "-o",
            str(simulation),
            str(ROOT / "rtl/managed/clusterip/common/rtl/utils/register.sv"),
            str(ROOT / "rtl/ip/multimedia/jpeg_entropy_decoder.sv"),
            str(ROOT / "rtl/ip/multimedia/jpeg_quantizer.sv"),
            str(ROOT / "rtl/ip/multimedia/jpeg_transform.sv"),
            str(ROOT / "rtl/ip/multimedia/jpeg_block_decoder.sv"),
            str(ROOT / "tests/rtl/jpeg_block_decoder_tb.sv"),
        ],
        check=True,
    )
    result = subprocess.run([vvp, str(simulation)], text=True, capture_output=True, check=True)
    assert "JPEG block decoder tests passed" in result.stdout


def test_jpeg_block_encoder_pipeline(tmp_path: Path) -> None:
    iverilog = shutil.which("iverilog")
    vvp = shutil.which("vvp")
    if iverilog is None or vvp is None:
        return
    simulation = tmp_path / "jpeg_block_encoder_tb"
    subprocess.run(
        [
            iverilog,
            "-g2012",
            "-DSV_ASSRT_DISABLE",
            "-I",
            str(ROOT / "rtl/managed/clusterip/common/rtl"),
            "-s",
            "jpeg_block_encoder_tb",
            "-o",
            str(simulation),
            str(ROOT / "rtl/managed/clusterip/common/rtl/utils/register.sv"),
            str(ROOT / "rtl/ip/multimedia/jpeg_transform.sv"),
            str(ROOT / "rtl/ip/multimedia/jpeg_quantizer.sv"),
            str(ROOT / "rtl/ip/multimedia/jpeg_entropy_encoder.sv"),
            str(ROOT / "rtl/ip/multimedia/jpeg_block_encoder.sv"),
            str(ROOT / "tests/rtl/jpeg_block_encoder_tb.sv"),
        ],
        check=True,
    )
    result = subprocess.run([vvp, str(simulation)], text=True, capture_output=True, check=True)
    assert "JPEG block encoder tests passed" in result.stdout


def test_jpeg_mcu_reconstructor(tmp_path: Path) -> None:
    iverilog = shutil.which("iverilog")
    vvp = shutil.which("vvp")
    sv2v = shutil.which("sv2v")
    if iverilog is None or vvp is None or sv2v is None:
        return
    source_list = tmp_path / "jpeg_mcu_reconstructor.fl"
    source_list.write_text(
        "\n".join(
            [
                f"+incdir+{ROOT / 'rtl/managed/clusterip/common/rtl'}",
                "+define+SV_ASSRT_DISABLE",
                str(ROOT / "rtl/managed/clusterip/common/rtl/interface/axi4_stream_if.sv"),
                str(ROOT / "rtl/managed/clusterip/common/rtl/utils/register.sv"),
                str(ROOT / "rtl/ip/multimedia/jpeg_mcu_reconstructor.sv"),
                str(ROOT / "tests/rtl/jpeg_mcu_reconstructor_tb.sv"),
                "",
            ]
        ),
        encoding="utf-8",
    )
    converted = tmp_path / "jpeg_mcu_reconstructor_tb.v"
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
    simulation = tmp_path / "jpeg_mcu_reconstructor_tb"
    subprocess.run(
        [
            iverilog,
            "-g2012",
            "-s",
            "jpeg_mcu_reconstructor_tb",
            "-o",
            str(simulation),
            str(converted),
        ],
        check=True,
    )
    result = subprocess.run([vvp, str(simulation)], text=True, capture_output=True, check=True)
    assert "JPEG MCU reconstructor tests passed" in result.stdout


def test_jpeg_mcu_builder(tmp_path: Path) -> None:
    iverilog = shutil.which("iverilog")
    vvp = shutil.which("vvp")
    sv2v = shutil.which("sv2v")
    if iverilog is None or vvp is None or sv2v is None:
        return
    source_list = tmp_path / "jpeg_mcu_builder.fl"
    source_list.write_text(
        "\n".join(
            [
                f"+incdir+{ROOT / 'rtl/managed/clusterip/common/rtl'}",
                str(ROOT / "rtl/managed/clusterip/common/rtl/interface/axi4_stream_if.sv"),
                str(ROOT / "rtl/managed/clusterip/common/rtl/utils/register.sv"),
                str(ROOT / "rtl/tech/tc_sram.sv"),
                str(ROOT / "rtl/ip/multimedia/jpeg_mcu_builder.sv"),
                str(ROOT / "tests/rtl/jpeg_mcu_builder_tb.sv"),
                "",
            ]
        ),
        encoding="utf-8",
    )
    converted = tmp_path / "jpeg_mcu_builder_tb.v"
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
    simulation = tmp_path / "jpeg_mcu_builder_tb"
    subprocess.run(
        [
            iverilog,
            "-g2012",
            "-s",
            "jpeg_mcu_builder_tb",
            "-o",
            str(simulation),
            str(converted),
        ],
        check=True,
    )
    result = subprocess.run([vvp, str(simulation)], text=True, capture_output=True, check=True)
    assert "JPEG MCU builder tests passed" in result.stdout


def test_jpeg_header_writer(tmp_path: Path) -> None:
    from jpeg_reference import (
        CHROMA_QUANT,
        LUMA_QUANT,
        Sampling,
        _parse_header,
        encode_rgb,
        scaled_quant_table,
    )

    iverilog = shutil.which("iverilog")
    vvp = shutil.which("vvp")
    if iverilog is None or vvp is None:
        return
    encoded = encode_rgb(
        bytes((index * 13) & 0xFF for index in range(17 * 15 * 3)),
        17,
        15,
        quality=75,
        sampling=Sampling.YUV420,
        restart_interval=1,
    )
    header = encoded[: _parse_header(encoded).entropy_offset]
    luma = scaled_quant_table(LUMA_QUANT, 75)
    chroma = scaled_quant_table(CHROMA_QUANT, 75)
    header_path = tmp_path / "header.hex"
    luma_path = tmp_path / "luma.hex"
    chroma_path = tmp_path / "chroma.hex"
    _write_hex_bytes(header_path, header)
    _write_hex_bytes(luma_path, bytes(luma))
    _write_hex_bytes(chroma_path, bytes(chroma))
    simulation = tmp_path / "jpeg_header_writer_tb"
    subprocess.run(
        [
            iverilog,
            "-g2012",
            "-DSV_ASSRT_DISABLE",
            "-I",
            str(ROOT / "rtl/managed/clusterip/common/rtl"),
            "-s",
            "jpeg_header_writer_tb",
            "-o",
            str(simulation),
            str(ROOT / "rtl/managed/clusterip/common/rtl/utils/register.sv"),
            str(ROOT / "rtl/ip/multimedia/jpeg_header_writer.sv"),
            str(ROOT / "tests/rtl/jpeg_header_writer_tb.sv"),
        ],
        check=True,
    )
    result = subprocess.run(
        [
            vvp,
            str(simulation),
            f"+header_hex={header_path}",
            f"+luma_hex={luma_path}",
            f"+chroma_hex={chroma_path}",
            f"+header_size={len(header)}",
        ],
        text=True,
        capture_output=True,
        check=True,
    )
    assert "JPEG header writer tests passed" in result.stdout


def test_jpeg_byte_joiner(tmp_path: Path) -> None:
    iverilog = shutil.which("iverilog")
    vvp = shutil.which("vvp")
    sv2v = shutil.which("sv2v")
    if iverilog is None or vvp is None or sv2v is None:
        return
    source_list = tmp_path / "jpeg_byte_joiner.fl"
    source_list.write_text(
        "\n".join(
            [
                f"+incdir+{ROOT / 'rtl/managed/clusterip/common/rtl'}",
                str(ROOT / "rtl/managed/clusterip/common/rtl/interface/axi4_stream_if.sv"),
                str(ROOT / "rtl/managed/clusterip/common/rtl/utils/register.sv"),
                str(ROOT / "rtl/ip/multimedia/jpeg_byte_joiner.sv"),
                str(ROOT / "tests/rtl/jpeg_byte_joiner_tb.sv"),
                "",
            ]
        ),
        encoding="utf-8",
    )
    converted = tmp_path / "jpeg_byte_joiner_tb.v"
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
    simulation = tmp_path / "jpeg_byte_joiner_tb"
    subprocess.run(
        [iverilog, "-g2012", "-s", "jpeg_byte_joiner_tb", "-o", str(simulation),
         str(converted)],
        check=True,
    )
    result = subprocess.run([vvp, str(simulation)], text=True, capture_output=True, check=True)
    assert "JPEG byte joiner tests passed" in result.stdout


def test_jpeg_encode_core_complete_file(tmp_path: Path) -> None:
    from jpeg_reference import (
        AC_CHROMA_BITS,
        AC_CHROMA_VALUES,
        AC_LUMA_BITS,
        AC_LUMA_VALUES,
        CHROMA_QUANT,
        DC_CHROMA_BITS,
        DC_LUMA_BITS,
        DC_VALUES,
        LUMA_QUANT,
        Sampling,
        _huffman_codes,
        encode_rgb,
        scaled_quant_table,
    )

    iverilog = shutil.which("iverilog")
    vvp = shutil.which("vvp")
    sv2v = shutil.which("sv2v")
    if iverilog is None or vvp is None or sv2v is None:
        return

    def entries(bits: tuple[int, ...], values: tuple[int, ...], size: int) -> list[int]:
        codes = _huffman_codes(bits, values)
        return [((codes[symbol][1] << 16) | codes[symbol][0]) if symbol in codes else 0
                for symbol in range(size)]

    rgb = bytes([128] * (16 * 16 * 3))
    expected = encode_rgb(rgb, 16, 16, quality=75, sampling=Sampling.YUV420)
    files = {
        "expected": tmp_path / "expected.hex",
        "luma_quant": tmp_path / "luma_quant.hex",
        "chroma_quant": tmp_path / "chroma_quant.hex",
        "luma_dc": tmp_path / "luma_dc.hex",
        "chroma_dc": tmp_path / "chroma_dc.hex",
        "luma_ac": tmp_path / "luma_ac.hex",
        "chroma_ac": tmp_path / "chroma_ac.hex",
    }
    _write_hex_bytes(files["expected"], expected)
    _write_hex_bytes(files["luma_quant"], bytes(scaled_quant_table(LUMA_QUANT, 75)))
    _write_hex_bytes(files["chroma_quant"], bytes(scaled_quant_table(CHROMA_QUANT, 75)))
    _write_hex_words(files["luma_dc"], entries(DC_LUMA_BITS, DC_VALUES, 12))
    _write_hex_words(files["chroma_dc"], entries(DC_CHROMA_BITS, DC_VALUES, 12))
    _write_hex_words(files["luma_ac"], entries(AC_LUMA_BITS, AC_LUMA_VALUES, 256))
    _write_hex_words(files["chroma_ac"], entries(AC_CHROMA_BITS, AC_CHROMA_VALUES, 256))

    source_list = tmp_path / "jpeg_encode_core.fl"
    source_list.write_text(
        "\n".join(
            [
                f"+incdir+{ROOT / 'rtl/managed/clusterip/common/rtl'}",
                "+define+SV_ASSRT_DISABLE",
                str(ROOT / "rtl/managed/clusterip/common/rtl/interface/axi4_stream_if.sv"),
                str(ROOT / "rtl/managed/clusterip/common/rtl/utils/register.sv"),
                str(ROOT / "rtl/managed/clusterip/common/rtl/utils/spill_register.sv"),
                str(ROOT / "rtl/tech/tc_sram.sv"),
                str(ROOT / "rtl/ip/multimedia/jpeg_transform.sv"),
                str(ROOT / "rtl/ip/multimedia/jpeg_quantizer.sv"),
                str(ROOT / "rtl/ip/multimedia/jpeg_coefficient_engine.sv"),
                str(ROOT / "rtl/ip/multimedia/jpeg_entropy_encoder.sv"),
                str(ROOT / "rtl/ip/multimedia/jpeg_block_encoder.sv"),
                str(ROOT / "rtl/ip/multimedia/jpeg_bit_packer.sv"),
                str(ROOT / "rtl/ip/multimedia/jpeg_header_writer.sv"),
                str(ROOT / "rtl/ip/multimedia/jpeg_mcu_builder.sv"),
                str(ROOT / "rtl/ip/multimedia/jpeg_byte_joiner.sv"),
                str(ROOT / "rtl/ip/multimedia/jpeg_encode_core.sv"),
                str(ROOT / "tests/rtl/jpeg_encode_core_tb.sv"),
                "",
            ]
        ),
        encoding="utf-8",
    )
    converted = tmp_path / "jpeg_encode_core_tb.v"
    subprocess.run(
        [sys.executable, str(ROOT / "rtl/mini/script/convt_sv2v.py"), "-f", str(source_list),
         "--output", str(converted)],
        check=True,
    )
    simulation = tmp_path / "jpeg_encode_core_tb"
    subprocess.run(
        [iverilog, "-g2012", "-s", "jpeg_encode_core_tb", "-o", str(simulation),
         str(converted)],
        check=True,
    )
    plusargs = [f"+{name}_hex={path}" for name, path in files.items()]
    result = subprocess.run(
        [vvp, str(simulation), *plusargs, f"+expected_size={len(expected)}"],
        text=True,
        capture_output=True,
        check=True,
    )
    assert "JPEG encode core tests passed" in result.stdout
    baseline_match = re.search(r"cycles=(\d+)", result.stdout)
    assert baseline_match is not None
    baseline_cycles = int(baseline_match.group(1))

    benchmark_rgb = bytes([128] * (16 * 32 * 3))
    benchmark = encode_rgb(benchmark_rgb, 16, 32, quality=75, sampling=Sampling.YUV420)
    _write_hex_bytes(files["expected"], benchmark)
    result = subprocess.run(
        [
            vvp,
            str(simulation),
            *plusargs,
            f"+expected_size={len(benchmark)}",
            "+test_width=16",
            "+test_height=32",
            "+input_beats=192",
        ],
        text=True,
        capture_output=True,
        check=True,
    )
    match = re.search(r"cycles=(\d+)", result.stdout)
    assert match is not None
    benchmark_cycles = int(match.group(1))
    assert baseline_cycles < benchmark_cycles
    assert benchmark_cycles - baseline_cycles <= 550


def test_jpeg_decode_core_complete_file(tmp_path: Path) -> None:
    from jpeg_reference import Sampling, decode_rgb, encode_rgb

    iverilog = shutil.which("iverilog")
    vvp = shutil.which("vvp")
    sv2v = shutil.which("sv2v")
    if iverilog is None or vvp is None or sv2v is None:
        return
    rgb = bytes([128] * (16 * 16 * 3))
    encoded = encode_rgb(rgb, 16, 16, quality=75, sampling=Sampling.YUV420)
    expected = decode_rgb(encoded).rgb
    input_path = tmp_path / "input.hex"
    expected_path = tmp_path / "expected_rgb.hex"
    _write_hex_bytes(input_path, encoded)
    _write_hex_bytes(expected_path, expected)

    source_list = tmp_path / "jpeg_decode_core.fl"
    sources = [
        ROOT / "rtl/managed/clusterip/common/rtl/interface/axi4_stream_if.sv",
        ROOT / "rtl/managed/clusterip/common/rtl/utils/register.sv",
        ROOT / "rtl/tech/tc_sram.sv",
        ROOT / "rtl/ip/multimedia/jpeg_byte_unpacker.sv",
        ROOT / "rtl/ip/multimedia/jpeg_marker_parser.sv",
        ROOT / "rtl/ip/multimedia/jpeg_table_store.sv",
        ROOT / "rtl/ip/multimedia/jpeg_table_cache.sv",
        ROOT / "rtl/ip/multimedia/jpeg_table_register_bank.sv",
        ROOT / "rtl/ip/multimedia/jpeg_bit_reader.sv",
        ROOT / "rtl/ip/multimedia/jpeg_entropy_decoder.sv",
        ROOT / "rtl/ip/multimedia/jpeg_quantizer.sv",
        ROOT / "rtl/ip/multimedia/jpeg_transform.sv",
        ROOT / "rtl/ip/multimedia/jpeg_coefficient_engine.sv",
        ROOT / "rtl/ip/multimedia/jpeg_block_decoder.sv",
        ROOT / "rtl/ip/multimedia/jpeg_mcu_reconstructor.sv",
        ROOT / "rtl/ip/multimedia/jpeg_decode_core.sv",
        ROOT / "tests/rtl/jpeg_decode_core_tb.sv",
    ]
    source_list.write_text(
        "\n".join(
            [
                f"+incdir+{ROOT / 'rtl/managed/clusterip/common/rtl'}",
                "+define+PDK_BEHAV",
                "+define+SV_ASSRT_DISABLE",
                *(str(source) for source in sources),
                "",
            ]
        ),
        encoding="utf-8",
    )
    converted = tmp_path / "jpeg_decode_core_tb.v"
    subprocess.run(
        [sys.executable, str(ROOT / "rtl/mini/script/convt_sv2v.py"), "-f", str(source_list),
         "--output", str(converted)],
        check=True,
    )
    simulation = tmp_path / "jpeg_decode_core_tb"
    subprocess.run(
        [iverilog, "-g2012", "-s", "jpeg_decode_core_tb", "-o", str(simulation),
         str(converted)],
        check=True,
    )
    result = subprocess.run(
        [
            vvp,
            str(simulation),
            f"+input_hex={input_path}",
            f"+input_size={len(encoded)}",
            f"+expected_rgb_hex={expected_path}",
            f"+expected_rgb_size={len(expected)}",
        ],
        text=True,
        capture_output=True,
        check=True,
    )
    assert "JPEG decode core tests passed" in result.stdout
