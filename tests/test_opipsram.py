"""Keep the handwritten OPI PSRAM register ABI synchronized with RTL."""

from __future__ import annotations

import re
import shutil
import subprocess
from pathlib import Path

import pytest


ROOT = Path(__file__).resolve().parents[1]
RTL_DEFINE = ROOT / "rtl/ip/memory/opipsram_define.svh"
RTL_PACKAGE = ROOT / "rtl/ip/memory/opipsram_pkg.sv"
RTL_PROTOCOL = ROOT / "rtl/ip/memory/opipsram_protocol.sv"
C_DEFINE = ROOT / "crt/include/retrosoc/hal/opipsram_regs.h"
HAL_HEADER = ROOT / "crt/include/retrosoc/hal/opipsram.h"
HAL_REGS = ROOT / "crt/include/retrosoc/hal/opipsram_regs.h"
HAL_SOURCE = ROOT / "crt/src/hal/opipsram.c"
OPIPSRAM_MODEL = ROOT / "rtl/mini/dv/model/opipsram_model.sv"
OPIPSRAM_TB = ROOT / "tests/rtl/opipsram_tb.sv"


def _values(path: Path, pattern: str) -> dict[str, int]:
    values: dict[str, int] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        match = re.match(pattern, line)
        if match is None:
            continue
        name, literal = match.groups()
        if "'" in literal:
            _, value = literal.split("'", maxsplit=1)
            base = 16 if value[0].lower() == "h" else 10
            values[name] = int(value[1:], base)
        else:
            values[name] = int(literal, 0)
    return values


def test_opipsram_protocol_model_compiles_and_runs() -> None:
    verilator = shutil.which("verilator")
    if verilator is None:
        pytest.skip("verilator is not installed")

    work = ROOT / ".cache" / "test-opipsram"
    shutil.rmtree(work, ignore_errors=True)
    work.mkdir(parents=True, exist_ok=True)
    output = work / "opipsram_tb"
    sources = [
        ROOT / "rtl/managed/clusterip/common/rtl/interface/axi4_if.sv",
        ROOT / "rtl/managed/clusterip/common/rtl/interface/apb4_if.sv",
        ROOT / "rtl/managed/clusterip/common/rtl/cdc/cdc_2phase.sv",
        ROOT / "rtl/managed/clusterip/common/rtl/cdc/cdc_sync.sv",
        ROOT / "rtl/managed/clusterip/common/rtl/cdc/cdc_rst_ctrlr.sv",
        ROOT / "rtl/managed/clusterip/common/rtl/clkrst/rst_sync.sv",
        ROOT / "rtl/managed/clusterip/common/rtl/utils/register.sv",
        ROOT / "rtl/managed/clusterip/common/rtl/utils/xchecker.sv",
        ROOT / "rtl/managed/clusterip/common/rtl/utils/gray2bin.sv",
        ROOT / "rtl/ip/util/async_fifo.sv",
        ROOT / "rtl/tech/tc_clk.sv",
        ROOT / "rtl/ip/memory/opipsram_pkg.sv",
        ROOT / "rtl/ip/memory/opipsram_protocol.sv",
        ROOT / "rtl/ip/memory/opipsram_trx.sv",
        ROOT / "rtl/ip/memory/opipsram_axi4.sv",
        ROOT / "rtl/ip/memory/opipsram_core.sv",
        ROOT / "rtl/ip/memory/opipsram_phy.sv",
        ROOT / "rtl/ip/memory/opipsram_reg.sv",
        ROOT / "rtl/ip/memory/opipsram_if.sv",
        ROOT / "rtl/ip/memory/apb4_opipsram.sv",
        ROOT / "rtl/tech/tc_opipsram_delay.sv",
        OPIPSRAM_MODEL,
        OPIPSRAM_TB,
    ]
    command = [
        verilator,
        "--binary",
        "--timing",
        "-Wno-fatal",
        "+define+PDK_BEHAV",
        "--top-module",
        "opipsram_tb",
        "-I" + str(ROOT / "rtl/ip/memory"),
        "-I" + str(ROOT / "rtl/ip/util"),
        "-I" + str(ROOT / "rtl/managed/clusterip/common/rtl"),
        "-I" + str(ROOT / "rtl/managed/clusterip/common/rtl/interface"),
        "-I" + str(ROOT / "rtl/managed/clusterip/common/rtl/cdc"),
        "-I" + str(ROOT / "rtl/managed/clusterip/common/rtl/clkrst"),
        *(str(source) for source in sources),
        "-Mdir",
        str(work / "obj"),
        "-o",
        str(output),
    ]
    try:
        compile_result = subprocess.run(command, check=False, text=True, capture_output=True)
        if compile_result.returncode != 0:
            pytest.fail(
                "production OPI PSRAM RTL does not compile with the locked model list:\n"
                + (compile_result.stderr or compile_result.stdout)[-4000:]
            )
        try:
            result = subprocess.run(
                [output], check=False, text=True, capture_output=True, timeout=60
            )
        except subprocess.TimeoutExpired as error:
            pytest.fail(
                "OPI PSRAM integration test did not terminate:\n"
                + str(error.stdout or "")
                + str(error.stderr or "")
            )
        assert result.returncode == 0, result.stdout + result.stderr
        assert "OPIPSRAM controller integration test passed" in result.stdout
    finally:
        shutil.rmtree(work, ignore_errors=True)


def test_opipsram_model_has_no_vendor_device_dependency() -> None:
    model = OPIPSRAM_MODEL.read_text(encoding="utf-8")
    protocol = RTL_PROTOCOL.read_text(encoding="utf-8")
    assert "module opipsram_model" in model
    assert "INJECT_MISSING_DEVICE" in model
    assert "INJECT_TIMEOUT" in model
    assert "ModelHyperCa" in model
    assert "OPI_READ_COMMAND[7:0]" in model
    assert "OPI_ADDRESS_BYTES == 3" in model
    assert "current_address = address_shift" in model
    assert "rwds_io" in model
    assert "last_tx_change_time" in model
    assert "EXPECTED_DIVIDER" in model
    assert "source_clk_i" in model
    assert "ESP_PSRAM64H" not in model
    assert re.search(
        r"s_hyper_word_addr\s*=\s*\{1'b0,\s*addr_i\[31:1\]\}", protocol
    )
    assert "current_address = hyper_word_address << 1" in model


def test_opipsram_hal_uses_generated_map_and_starts_dma() -> None:
    regs = HAL_REGS.read_text(encoding="utf-8")
    header = HAL_HEADER.read_text(encoding="utf-8")
    source = HAL_SOURCE.read_text(encoding="utf-8")

    assert "#include <retrosoc/core/soc.h>" in regs
    assert "RS_SOC_APB4_OPIPSRAM_BASE" in regs
    assert "RS_SOC_OPIPSRAM_BASE" in source
    assert "RS_SOC_OPIPSRAM_END" in source
    assert "0x10010000" not in regs
    assert "0x48000000" not in regs
    assert "RS_OPIPSRAM_APERTURE_BASE" not in source
    assert "RS_OPIPSRAM_APERTURE_SIZE" not in source

    for duplicate in (
        "rs_opipsram_validate_config",
        "rs_opipsram_init",
        "rs_opipsram_interrupt_enable",
        "rs_opipsram_interrupt_pending",
        "rs_opipsram_interrupt_clear",
        "rs_opipsram_delay_tap_read",
        "rs_opipsram_delay_tap_write",
    ):
        assert re.search(rf"\b{duplicate}\s*\(", header) is None
        assert re.search(rf"\b{duplicate}\s*\(", source) is None

    dma_body = re.search(
        r"rs_status_t rs_opipsram_dma_copy\(.*?\n\}", source, flags=re.DOTALL
    )
    assert dma_body is not None
    assert "rs_dma_configure" in dma_body.group(0)
    assert "rs_dma_start(channel)" in dma_body.group(0)
    assert dma_body.group(0).index("rs_dma_configure") < dma_body.group(0).index("rs_dma_start")


def test_opipsram_handwritten_abi_matches_rtl() -> None:
    if not RTL_DEFINE.exists():
        pytest.skip("the OPI PSRAM RTL register define is not integrated yet")

    rtl = _values(
        RTL_DEFINE,
        r"^`define\s+(APB4_OPIPSRAM__[A-Z0-9_]+|OPIPSRAM_[A-Z0-9_]+)\s+"
        r"((?:\d+)'[hHdD][0-9a-fA-F_]+|\d+)\s*$",
    )
    c = _values(
        C_DEFINE,
        r"^#define\s+(RS_OPIPSRAM_[A-Z0-9_]+)\s+UINT32_C\((0x[0-9a-fA-F]+|\d+)\)\s*$",
    )
    assert rtl
    assert c

    offset_names = (
        "IP_ID",
        "IP_VERSION",
        "CAPABILITY",
        "CTRL",
        "COMMAND",
        "STATUS",
        "PROTOCOL_CFG",
        "DEVICE_SIZE",
        "OPI_READ_CMD",
        "OPI_WRITE_CMD",
        "OPI_REG_READ_CMD",
        "OPI_REG_WRITE_CMD",
        "OPI_TIMING",
        "HYPER_TIMING",
        "CLK_CONFIG",
        "CS_TIMING",
        "POWERUP_CYCLES",
        "TIMEOUT_CYCLES",
        "RX_DELAY",
        "PROFILE_STATUS",
        "INDIRECT_CTRL",
        "INDIRECT_ADDR",
        "INDIRECT_WDATA_LO",
        "INDIRECT_WDATA_HI",
        "INDIRECT_RDATA_LO",
        "INDIRECT_RDATA_HI",
        "LAST_ERROR",
        "LAST_ERROR_ADDR",
        "TRAIN_STATUS",
        "TRAIN_WINDOW",
        "INTR_STATE",
        "INTR_ENABLE",
        "INTR_STATUS",
        "INTR_TEST",
        "PERF_CTRL",
        "PERF_READ_BYTES",
        "PERF_WRITE_BYTES",
        "PERF_COMMANDS",
        "PERF_CACHE_HITS",
        "PERF_STALL_CYCLES",
        "PERF_ERROR_COUNT",
    )
    for name in offset_names:
        rtl_name = f"APB4_OPIPSRAM__{name}"
        c_name = f"RS_OPIPSRAM_REG_{name}"
        assert rtl_name in rtl
        assert c_name in c
        assert rtl[rtl_name] == c[c_name]

    bit_masks = {
        "CTRL_ENABLE": "CTRL_ENABLE",
        "CTRL_MEMORY_ENABLE": "CTRL_MEMORY_ENABLE",
        "CTRL_AUTO_INIT": "CTRL_AUTO_INIT",
        "CTRL_LINE_BUFFER": "CTRL_LINE_BUFFER",
        "COMMAND_INIT": "COMMAND_INIT",
        "COMMAND_ABORT": "COMMAND_ABORT",
        "COMMAND_SOFT_RESET": "COMMAND_SOFT_RESET",
        "COMMAND_TRAIN": "COMMAND_TRAIN",
        "STATUS_BUSY": "STATUS_BUSY",
        "STATUS_INITIALIZED": "STATUS_INITIALIZED",
        "STATUS_READY": "STATUS_READY",
        "STATUS_QUIESCED": "STATUS_QUIESCED",
        "STATUS_TRAINED": "STATUS_TRAINED",
        "STATUS_ERROR": "STATUS_ERROR",
        "STATUS_PROFILE_LOCK": "STATUS_PROFILE_LOCK",
        "STATUS_HYPER": "STATUS_HYPER",
        "PROTOCOL_HYPER": "PROTOCOL_HYPER",
        "PROTOCOL_LOCK": "PROTOCOL_LOCK",
        "INDIRECT_WRITE": "INDIRECT_WRITE",
        "INDIRECT_REGISTER": "INDIRECT_REGISTER_SPACE",
        "INDIRECT_START": "INDIRECT_START",
        "INTR_INIT_DONE": "INTERRUPT_INIT_DONE",
        "INTR_INDIRECT_DONE": "INTERRUPT_INDIRECT_DONE",
        "INTR_TRAIN_DONE": "INTERRUPT_TRAIN_DONE",
        "INTR_ERROR": "INTERRUPT_ERROR",
        "INTR_TIMEOUT": "INTERRUPT_TIMEOUT",
        "PERF_ENABLE": "PERF_ENABLE",
        "PERF_FREEZE": "PERF_FREEZE",
        "PERF_CLEAR": "PERF_CLEAR",
    }
    for rtl_suffix, c_suffix in bit_masks.items():
        rtl_name = f"APB4_OPIPSRAM__{rtl_suffix}"
        c_name = f"RS_OPIPSRAM_{c_suffix}"
        assert rtl_name in rtl
        assert c_name in c
        assert c[c_name] == (1 << rtl[rtl_name])

    shifts = {
        "INDIRECT_LENGTH_LSB": "INDIRECT_LENGTH_SHIFT",
        "INDIRECT_LENGTH_MSB": "INDIRECT_LENGTH_MSB",
    }
    for rtl_suffix, c_suffix in shifts.items():
        assert rtl[f"APB4_OPIPSRAM__{rtl_suffix}"] == c[f"RS_OPIPSRAM_{c_suffix}"]

    values = {
        "IP_ID_VALUE": "IP_ID_VALUE",
        "IP_VERSION_VALUE": "IP_VERSION_VALUE",
        "DEVICE_SIZE_RESET": "DEVICE_SIZE_RESET",
        "OPI_READ_CMD_RESET": "OPI_READ_CMD_RESET",
        "OPI_WRITE_CMD_RESET": "OPI_WRITE_CMD_RESET",
        "OPI_TIMING_RESET": "OPI_TIMING_RESET",
        "HYPER_TIMING_RESET": "HYPER_TIMING_RESET",
        "CLK_CONFIG_RESET": "CLK_CONFIG_RESET",
        "CS_TIMING_RESET": "CS_TIMING_RESET",
        "POWERUP_RESET": "POWERUP_RESET",
        "TIMEOUT_RESET": "TIMEOUT_RESET",
        "CAPABILITY_VALUE": "CAPABILITY_VALUE",
    }
    for rtl_suffix, c_suffix in values.items():
        assert rtl[f"APB4_OPIPSRAM__{rtl_suffix}"] == c[f"RS_OPIPSRAM_{c_suffix}"]

    if RTL_PACKAGE.exists():
        errors = {
            name: int(value)
            for name, value in re.findall(
                r"\b(OpipsramError[A-Za-z]+)\s*=\s*4'd(\d+)",
                RTL_PACKAGE.read_text(encoding="utf-8"),
            )
        }
        error_map = {
            "OpipsramErrorNone": "ERROR_NONE",
            "OpipsramErrorIllegal": "ERROR_ILLEGAL_TRANSACTION",
            "OpipsramErrorUnavailable": "ERROR_UNAVAILABLE",
            "OpipsramErrorTimeout": "ERROR_TIMEOUT",
            "OpipsramErrorProfile": "ERROR_PROFILE",
            "OpipsramErrorAborted": "ERROR_ABORTED",
            "OpipsramErrorPhy": "ERROR_PHY",
            "OpipsramErrorProtocol": "ERROR_PROTOCOL",
            "OpipsramErrorBounds": "ERROR_BOUNDS",
            "OpipsramErrorTraining": "ERROR_TRAINING",
        }
        for rtl_name, c_suffix in error_map.items():
            assert rtl_name in errors
            assert c[f"RS_OPIPSRAM_{c_suffix}"] == errors[rtl_name]
