#!/usr/bin/env python3
"""Generate the narrow formal source list for one Mini SoC protocol proof."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path


SCRIPT_DIR = Path(__file__).resolve().parent
ROOT = SCRIPT_DIR.parents[2]
FILELIST_DIR = ROOT / "rtl/mini/script"
sys.path.insert(0, str(FILELIST_DIR))

from filelist import FileList, write_filelist  # noqa: E402


COMMON_RTL = ROOT / "rtl/managed/clusterip/common/rtl"
INTERCONNECT = ROOT / "rtl/ip/interconnect"
PERIPHERAL = ROOT / "rtl/ip/peripheral"
SERIAL = ROOT / "rtl/ip/serial"
MEMORY = ROOT / "rtl/ip/memory"
STORAGE = ROOT / "rtl/ip/storage"
MULTIMEDIA = ROOT / "rtl/ip/multimedia"
TOP = ROOT / "rtl/mini/top"
APU_LOADER_SCENARIOS = {
    "apu_loader_success": 0,
    "apu_loader_header_range": 1,
    "apu_loader_descriptor_range": 2,
    "apu_loader_crc": 3,
    "apu_loader_control_flow": 4,
    "apu_loader_abort": 5,
    "apu_loader_resource_reset": 6,
}
APU_PRIMITIVE_SCENARIOS = {
    "apu_primitives_invalid_read": 0,
    "apu_primitives_local": 1,
    "apu_primitives_kernel": 2,
    "apu_primitives_input_fifo": 3,
    "apu_primitives_alignment": 4,
    "apu_primitives_output_fifo": 5,
    "apu_primitives_local_overflow": 6,
}


def target_defines(target: str) -> list[str]:
    if target == "onchip_ram":
        return ["+define+PDK_BEHAV", "+define+SYNTHESIS"]
    if target == "apu_loader" or target in APU_LOADER_SCENARIOS:
        scenario = APU_LOADER_SCENARIOS.get(target, 0)
        return [
            "+define+SV_ASSRT_DISABLE",
            "+define+SYNTHESIS",
            f"+define+APU_LOADER_FORMAL_SCENARIO={scenario}",
        ]
    if target in APU_PRIMITIVE_SCENARIOS:
        return [
            "+define+SV_ASSRT_DISABLE",
            f"+define+APU_PRIMITIVES_FORMAL_SCENARIO={APU_PRIMITIVE_SCENARIOS[target]}",
        ]
    if target == "opipsram":
        return ["+define+PDK_BEHAV"]
    if target == "sysctrl":
        return ["+define+SV_ASSRT_DISABLE", "+define+MINI_PRODUCT"]
    return ["+define+SV_ASSRT_DISABLE"]


def source_files(target: str) -> list[Path]:
    common = [
        COMMON_RTL / "interface/axi4_if.sv",
        COMMON_RTL / "interface/apb4_if.sv",
        COMMON_RTL / "interface/ribp_if.sv",
        COMMON_RTL / "interface/ram_if.sv",
        COMMON_RTL / "utils/register.sv",
        TOP / "rib_if.sv",
    ]
    if target == "bus":
        return [
            *common,
            COMMON_RTL / "utils/spill_register.sv",
            TOP / "ribp2rib.sv",
            TOP / "rib2ribp.sv",
            TOP / "rib_error_slave.sv",
            TOP / "rib2ram.sv",
            TOP / "rib_bus.sv",
            SCRIPT_DIR / "bus_formal.sv",
        ]
    if target == "rib_adapter":
        return [
            *common,
            TOP / "ribp2rib.sv",
            TOP / "rib2ribp.sv",
            SCRIPT_DIR / "rib_adapter_formal.sv",
        ]
    if target == "rib2apb":
        return [
            COMMON_RTL / "interface/apb4_pure_if.sv",
            COMMON_RTL / "utils/register.sv",
            COMMON_RTL / "utils/spill_register.sv",
            TOP / "rib_if.sv",
            TOP / "rib2apb.sv",
            SCRIPT_DIR / "rib2apb_formal.sv",
        ]
    if target == "sysctrl":
        return [
            *common,
            COMMON_RTL / "cdc/cdc_sync.sv",
            PERIPHERAL / "pll_ctrl_if.sv",
            PERIPHERAL / "clock_ctrl_if.sv",
            PERIPHERAL / "sysctrl_if.sv",
            PERIPHERAL / "sysctrl_define.svh",
            PERIPHERAL / "sysctrl_reg.sv",
            PERIPHERAL / "sysctrl_core.sv",
            PERIPHERAL / "apb4_sysctrl.sv",
            SCRIPT_DIR / "sysctrl_formal.sv",
        ]
    if target == "pll_rcu":
        return [
            *common,
            COMMON_RTL / "cdc/cdc_sync.sv",
            COMMON_RTL / "cdc/cdc_rst_ctrlr.sv",
            COMMON_RTL / "cdc/cdc_2phase.sv",
            COMMON_RTL / "clkrst/rst_sync.sv",
            COMMON_RTL / "clkrst/counter.sv",
            COMMON_RTL / "utils/edge_det.sv",
            PERIPHERAL / "pll_ctrl_if.sv",
            PERIPHERAL / "clock_ctrl_if.sv",
            PERIPHERAL / "clint_timebase.sv",
            TOP / "rcu.sv",
            TOP / "pll_rcu_controller.sv",
            SCRIPT_DIR / "pll_rcu_formal.sv",
        ]
    if target == "gpio":
        return [
            *common,
            COMMON_RTL / "cdc/cdc_sync.sv",
            COMMON_RTL / "cdc/cdc_rst_ctrlr.sv",
            COMMON_RTL / "clkrst/counter.sv",
            COMMON_RTL / "utils/edge_det.sv",
            PERIPHERAL / "gpio_if.sv",
            PERIPHERAL / "user_gpio_if.sv",
            PERIPHERAL / "gpio_core.sv",
            PERIPHERAL / "gpio_reg.sv",
            PERIPHERAL / "apb4_gpio.sv",
            SCRIPT_DIR / "gpio_formal.sv",
        ]
    if target == "ws2812":
        return [
            COMMON_RTL / "interface/apb4_if.sv",
            COMMON_RTL / "utils/register.sv",
            COMMON_RTL / "utils/fifo.sv",
            SERIAL / "ws2812_if.sv",
            SERIAL / "ws2812_reg.sv",
            SERIAL / "ws2812_core.sv",
            SERIAL / "apb4_ws2812.sv",
            SCRIPT_DIR / "ws2812_formal.sv",
        ]
    if target == "uart":
        return [
            COMMON_RTL / "interface/apb4_if.sv",
            COMMON_RTL / "cdc/cdc_sync.sv",
            COMMON_RTL / "utils/register.sv",
            COMMON_RTL / "utils/edge_det.sv",
            COMMON_RTL / "utils/fifo.sv",
            SERIAL / "uart_if.sv",
            SERIAL / "uart_baudgen.sv",
            SERIAL / "apb4_uart_tx.sv",
            SERIAL / "apb4_uart_rx.sv",
            SERIAL / "uart_flow_ctrl.sv",
            SERIAL / "uart_core.sv",
            SERIAL / "uart_reg.sv",
            SERIAL / "apb4_uart.sv",
            SCRIPT_DIR / "uart_formal.sv",
        ]
    if target == "i2c":
        return [
            COMMON_RTL / "interface/apb4_if.sv",
            COMMON_RTL / "utils/register.sv",
            COMMON_RTL / "utils/fifo.sv",
            COMMON_RTL / "cdc/cdc_sync.sv",
            SERIAL / "i2c_if.sv",
            SERIAL / "i2c_filter.sv",
            SERIAL / "i2c_core.sv",
            SERIAL / "i2c_reg.sv",
            SERIAL / "apb4_i2c.sv",
            SCRIPT_DIR / "i2c_formal.sv",
        ]
    if target == "timer":
        return [
            COMMON_RTL / "interface/apb4_if.sv",
            COMMON_RTL / "utils/register.sv",
            COMMON_RTL / "clkrst/counter.sv",
            PERIPHERAL / "timer_core.sv",
            PERIPHERAL / "timer_reg.sv",
            PERIPHERAL / "apb4_timer.sv",
            SCRIPT_DIR / "timer_formal.sv",
        ]
    if target == "clint":
        return [
            COMMON_RTL / "interface/apb4_if.sv",
            COMMON_RTL / "utils/register.sv",
            COMMON_RTL / "clkrst/counter.sv",
            PERIPHERAL / "clint_if.sv",
            PERIPHERAL / "clint_reg.sv",
            PERIPHERAL / "clint_core.sv",
            PERIPHERAL / "apb4_clint.sv",
            SCRIPT_DIR / "clint_formal.sv",
        ]
    if target == "dvp":
        return [
            COMMON_RTL / "interface/apb4_if.sv",
            COMMON_RTL / "utils/register.sv",
            ROOT / "rtl/ip/multimedia/dvp_define.svh",
            ROOT / "rtl/ip/multimedia/dvp_reg.sv",
            SCRIPT_DIR / "dvp_formal.sv",
        ]
    if target == "i2s":
        return [
            COMMON_RTL / "interface/apb4_if.sv",
            COMMON_RTL / "utils/register.sv",
            SERIAL / "i2s_define.svh",
            SERIAL / "i2s_pkg.sv",
            SERIAL / "i2s_reg.sv",
            SCRIPT_DIR / "i2s_formal.sv",
        ]
    if target == "psram":
        return [
            COMMON_RTL / "interface/axi4_if.sv",
            COMMON_RTL / "interface/axi4_addr_gen.sv",
            COMMON_RTL / "utils/register.sv",
            MEMORY / "psram_pkg.sv",
            MEMORY / "psram_axi4.sv",
            MEMORY / "psram_phy.sv",
            SCRIPT_DIR / "psram_formal.sv",
        ]
    if target == "onchip_ram":
        return [
            COMMON_RTL / "interface/axi4_if.sv",
            COMMON_RTL / "interface/apb4_if.sv",
            COMMON_RTL / "interface/axi4_addr_gen.sv",
            COMMON_RTL / "utils/register.sv",
            COMMON_RTL / "utils/xchecker.sv",
            ROOT / "rtl/tech/tc_sram.sv",
            TOP / "onchip_ram_reg.sv",
            TOP / "onchip_ram.sv",
            SCRIPT_DIR / "onchip_ram_formal.sv",
        ]
    if target == "opipsram":
        return [
            COMMON_RTL / "interface/axi4_if.sv",
            COMMON_RTL / "interface/apb4_if.sv",
            COMMON_RTL / "utils/register.sv",
            COMMON_RTL / "utils/xchecker.sv",
            COMMON_RTL / "utils/gray2bin.sv",
            ROOT / "rtl/ip/util/async_fifo.sv",
            ROOT / "rtl/tech/tc_clk.sv",
            ROOT / "rtl/tech/tc_opipsram_delay.sv",
            MEMORY / "opipsram_define.svh",
            MEMORY / "opipsram_pkg.sv",
            MEMORY / "opipsram_protocol.sv",
            MEMORY / "opipsram_trx.sv",
            MEMORY / "opipsram_axi4.sv",
            MEMORY / "opipsram_core.sv",
            MEMORY / "opipsram_phy.sv",
            MEMORY / "opipsram_reg.sv",
            SCRIPT_DIR / "opipsram_formal.sv",
        ]
    if target == "dma":
        return [
            COMMON_RTL / "interface/axi4_if.sv",
            COMMON_RTL / "interface/axi4_stream_if.sv",
            COMMON_RTL / "stream/round_robin_arbiter.sv",
            COMMON_RTL / "utils/fifo.sv",
            PERIPHERAL / "dma_pkg.sv",
            PERIPHERAL / "dma_req_if.sv",
            PERIPHERAL / "dma_axi4_master.sv",
            PERIPHERAL / "dma_core.sv",
            SCRIPT_DIR / "dma_formal.sv",
        ]
    if target == "apu":
        return [
            COMMON_RTL / "interface/axi4_if.sv",
            COMMON_RTL / "interface/axi4_stream_if.sv",
            COMMON_RTL / "utils/register.sv",
            PERIPHERAL / "dma_axi4_master.sv",
            MULTIMEDIA / "apu_dma.sv",
            SCRIPT_DIR / "apu_formal.sv",
        ]
    if target == "apu_codec":
        return [
            COMMON_RTL / "interface/axi4_stream_if.sv",
            MULTIMEDIA / "apu_codec_transport.sv",
            SCRIPT_DIR / "apu_codec_formal.sv",
        ]
    if target == "apu_primitives" or target in APU_PRIMITIVE_SCENARIOS:
        return [
            COMMON_RTL / "utils/fifo.sv",
            MULTIMEDIA / "apu_microcode_pkg.sv",
            MULTIMEDIA / "apu_local_sram.sv",
            MULTIMEDIA / "apu_bitstream_engine.sv",
            MULTIMEDIA / "apu_entropy_engine.sv",
            MULTIMEDIA / "apu_reconstruction_engine.sv",
            MULTIMEDIA / "apu_transform_engine.sv",
            MULTIMEDIA / "apu_resampler.sv",
            MULTIMEDIA / "apu_kernel_engine.sv",
            MULTIMEDIA / "apu_primitive_dispatcher.sv",
            SCRIPT_DIR / "apu_primitives_formal.sv",
        ]
    if target == "apu_loader" or target in APU_LOADER_SCENARIOS:
        return [
            ROOT / "rtl/tech/tc_sram.sv",
            MULTIMEDIA / "apu_microcode_pkg.sv",
            MULTIMEDIA / "apu_microcode_loader.sv",
            SCRIPT_DIR / "apu_loader_formal.sv",
        ]
    if target == "apu_sequencer":
        return [
            MULTIMEDIA / "apu_microcode_pkg.sv",
            MULTIMEDIA / "apu_codec_sequencer.sv",
            SCRIPT_DIR / "apu_sequencer_formal.sv",
        ]
    if target == "gateway_a":
        return [
            COMMON_RTL / "interface/axi4_if.sv",
            COMMON_RTL / "utils/register.sv",
            COMMON_RTL / "stream/round_robin_arbiter.sv",
            TOP / "hp_axi4_mux3.sv",
            SCRIPT_DIR / "gateway_a_formal.sv",
        ]
    if target == "sdio":
        return [
            COMMON_RTL / "interface/apb4_if.sv",
            COMMON_RTL / "interface/axi4_if.sv",
            PERIPHERAL / "dma_axi4_master.sv",
            STORAGE / "sdio_pkg.sv",
            STORAGE / "sdio_define.svh",
            STORAGE / "sdio_clock.sv",
            STORAGE / "sdio_dma_descriptor.sv",
            STORAGE / "sdio_dma.sv",
            STORAGE / "sdio_reg.sv",
            SCRIPT_DIR / "sdio_formal.sv",
        ]
    raise ValueError(f"unsupported formal target: {target}")


def generate(
    target: str,
    output: Path,
    memory_map_dir: Path,
    soc_topology_dir: Path,
    user_extensions_dir: Path,
) -> bool:
    filelist = FileList(
        defines=target_defines(target),
        incdirs=[
            memory_map_dir.resolve() / "rtl",
            soc_topology_dir.resolve() / "rtl",
            user_extensions_dir.resolve() / "rtl",
            TOP,
            COMMON_RTL,
            COMMON_RTL / "interface",
            COMMON_RTL / "stream",
            COMMON_RTL / "utils",
            INTERCONNECT,
            PERIPHERAL,
            SERIAL,
            MEMORY,
            MULTIMEDIA,
        ],
        files=source_files(target),
    ).deduplicate()
    return write_filelist(output.resolve(), filelist)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--target",
        choices=(
            "bus",
            "rib_adapter",
            "rib2apb",
            "sysctrl",
            "pll_rcu",
            "gpio",
            "ws2812",
            "uart",
            "i2c",
            "timer",
            "clint",
            "dvp",
            "i2s",
            "psram",
            "onchip_ram",
            "opipsram",
            "dma",
            "apu",
            "apu_codec",
            "apu_primitives",
            *APU_PRIMITIVE_SCENARIOS,
            *APU_LOADER_SCENARIOS,
            "apu_sequencer",
            "gateway_a",
            "sdio",
        ),
        required=True,
    )
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--memory-map-dir", type=Path, required=True)
    parser.add_argument("--soc-topology-dir", type=Path, required=True)
    parser.add_argument("--user-extensions-dir", type=Path, required=True)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    changed = generate(
        args.target,
        args.output,
        args.memory_map_dir,
        args.soc_topology_dir,
        args.user_extensions_dir,
    )
    print(f"formal filelist {'updated' if changed else 'unchanged'}: {args.output.resolve()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
