"""Focused SPI-P2 DMA V2.2 and credit-pacing checks."""
from __future__ import annotations

import re
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def test_dma_v22_abi_and_product_defaults():
    define = (ROOT / "rtl/ip/peripheral/dma_define.svh").read_text()
    pkg = (ROOT / "rtl/ip/peripheral/dma_pkg.sv").read_text()
    regs = (ROOT / "crt/include/retrosoc/hal/dma_regs.h").read_text()
    core = (ROOT / "rtl/ip/peripheral/dma_core.sv").read_text()
    tiny = (ROOT / "rtl/tiny/top/retrosoc_tiny.sv").read_text()
    assert "APB4_DMA__SUPPORTED_REQUESTS" in define
    assert "RS_DMA_REG_SUPPORTED_REQUESTS" in regs
    assert "DMA_REQUEST_SPI_TX = 5'd16" in pkg
    assert "DMA_REQUEST_SPI_RX = 5'd17" in pkg
    assert "s_tcd_word7_q[s_tcd_read_owner_q][25]" in core
    assert "logic [      NumChannels-1:0][               4:0] s_req_q" in core
    assert "!EnableSpi && ((s_cfg_req[channel] == DMA_REQUEST_SPI_TX)" in core
    assert "s_tcd_parse_q &&" in core
    assert ".RequestMask" in tiny and "0003_39ff" in tiny
    assert ".EnableSpi(1'b1)" in re.sub(r"\s+", "", tiny)


def test_dma_v22_tcd_request_split_is_handwritten_and_stable():
    c_header = (ROOT / "crt/include/retrosoc/hal/dma.h").read_text()
    c_math = (ROOT / "crt/src/hal/dma_math.c").read_text()
    c_dma = (ROOT / "crt/src/hal/dma.c").read_text()
    assert "RS_DMA_TCD_REQUEST_HIGH" in c_header
    assert "request |= UINT32_C(0x10)" in c_math
    assert "RS_DMA_TCD_REQUEST_HIGH" in c_dma


def test_dma_v22_hal_mask_and_discovery_order():
    c_math = (ROOT / "crt/src/hal/dma_math.c").read_text()
    c_dma = (ROOT / "crt/src/hal/dma.c").read_text()
    core = (ROOT / "rtl/ip/peripheral/dma_core.sv").read_text()
    apb = (ROOT / "rtl/ip/peripheral/apb4_dma.sv").read_text()
    assert "UINT32_C(0x000339FF)" in c_math
    assert "RS_DMA_V22" not in c_math
    assert c_dma.index("rs_dma_supports_request(config->request)") < c_dma.index(
        "rs_dma_config_validate(channel, config)"
    )
    assert "s_cfg_req[channel] > DMA_REQUEST_SPI_RX" in core
    assert "s_cfg_req_raw[channel][31:5] != 27'd0" in core
    assert "32'h0003_ffff" in apb
    assert "EnableStreams ?" in apb


def test_dma_stream_status_is_disabled_with_streams_off():
    core = (ROOT / "rtl/ip/peripheral/dma_core.sv").read_text()
    for request in (
        "DMA_REQUEST_I2S_TX",
        "DMA_REQUEST_I2S_RX",
        "DMA_REQUEST_DVP_RX",
        "DMA_REQUEST_CRYPTO_IN",
        "DMA_REQUEST_CRYPTO_OUT",
    ):
        match = re.search(rf"s_req_ready\[{request}\]\s*=\s*([^;]+);", core)
        assert match is not None
        assert "EnableStreams" in match.group(1)


def test_dma_v21_descriptor_cancel_guards_are_structural():
    core = (ROOT / "rtl/ip/peripheral/dma_core.sv").read_text()
    formal = (ROOT / "rtl/mini/formal/dma_formal_props.sv").read_text()
    harness = (ROOT / "rtl/mini/formal/dma_formal.sv").read_text()
    tcd_props = (ROOT / "rtl/mini/formal/dma_tcd_cancel_props.sv").read_text()
    fetch = core[core.index("s_tcd_fetch_pending_q[channel]"):core.index("always_comb begin", core.index("s_tcd_fetch_pending_q[channel]"))]
    parse_start = core.index("if (s_tcd_parse_q)")
    parse = core[parse_start:core.index("if (s_axi_read_beat_valid && s_read_owner_valid_q)", parse_start)]
    ownership = core[core.index("s_read_owns_channel  = '0"):core.index("always_ff @(posedge clk_i", core.index("s_read_owns_channel  = '0"))]
    assert "!s_abort_q[channel]" in fetch
    assert "!abort_i[channel]" in fetch
    assert "!s_tcd_parse_q" in fetch
    assert "if (s_abort_q[s_tcd_read_owner_q])" in parse
    assert "s_tcd_parse_q &&" in ownership
    assert "s_tcd_fetch_pending_q[channel] <= 1'b0" in core
    assert "tcd_read_owner_valid" in formal
    assert "tcd_word" in harness
    assert "cover (tcd_fetch_pending && abort_i[0])" in tcd_props
    assert "assume (tcd_mode)" in tcd_props


def test_dma_v22_old_version_rejection_precedes_support_read():
    c_dma = (ROOT / "crt/src/hal/dma.c").read_text()
    start = c_dma.index("rs_status_t rs_dma_supports_request")
    body = c_dma[start:c_dma.index("static rs_status_t rs_dma_configure_owned", start)]
    assert body.index("version = RS_DMA_REG(RS_DMA_REG_IP_VERSION)") < body.index(
        "supported = RS_DMA_REG(RS_DMA_REG_SUPPORTED_REQUESTS)"
    )
    assert "version < RS_DMA_IP_VERSION_V22" in body


def test_spi_dma_pacing_fixture(tmp_path):
    iverilog = shutil.which("iverilog")
    vvp = shutil.which("vvp")
    assert iverilog and vvp
    common = ROOT / "rtl/managed/clusterip/common/rtl"
    sim = tmp_path / "spi_dma_pacing_tb"
    subprocess.run([
        iverilog, "-g2012", "-s", "spi_dma_pacing_tb", "-o", str(sim),
        f"-I{common}", f"-I{common / 'utils'}", str(common / "utils/register.sv"),
        str(ROOT / "rtl/ip/serial/spi_dma_pacing.sv"),
        str(ROOT / "tests/rtl/spi_dma_pacing_tb.sv")],
        check=True, capture_output=True, text=True)
    run = subprocess.run([vvp, str(sim)], check=True, capture_output=True, text=True)
    assert "SPI_P2_PASS spi_dma_pacing_tb" in run.stdout
    assert not re.search(r"FAILED|FATAL|SIM_TEST_TIMEOUT", run.stdout + run.stderr)
