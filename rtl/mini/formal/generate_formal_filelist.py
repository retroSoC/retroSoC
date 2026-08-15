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
TOP = ROOT / "rtl/mini/top"


def target_defines(target: str) -> list[str]:
    return ["+define+SV_ASSRT_DISABLE"]


def source_files(target: str) -> list[Path]:
    common = [
        COMMON_RTL / "interface/axi4_if.sv",
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
            PERIPHERAL / "ribp_sysctrl.sv",
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
            PERIPHERAL / "ribp_gpio.sv",
            SCRIPT_DIR / "gpio_formal.sv",
        ]
    if target == "ws2812":
        return [
            COMMON_RTL / "interface/ribp_if.sv",
            COMMON_RTL / "utils/register.sv",
            COMMON_RTL / "utils/fifo.sv",
            SERIAL / "ws2812_if.sv",
            SERIAL / "ws2812_reg.sv",
            SERIAL / "ws2812_core.sv",
            SERIAL / "ribp_ws2812.sv",
            SCRIPT_DIR / "ws2812_formal.sv",
        ]
    if target == "uart":
        return [
            COMMON_RTL / "interface/ribp_if.sv",
            COMMON_RTL / "cdc/cdc_sync.sv",
            COMMON_RTL / "utils/register.sv",
            COMMON_RTL / "utils/edge_det.sv",
            COMMON_RTL / "utils/fifo.sv",
            SERIAL / "uart_if.sv",
            SERIAL / "uart_baudgen.sv",
            SERIAL / "ribp_uart_tx.sv",
            SERIAL / "ribp_uart_rx.sv",
            SERIAL / "uart_flow_ctrl.sv",
            SERIAL / "uart_core.sv",
            SERIAL / "uart_reg.sv",
            SERIAL / "ribp_uart.sv",
            SCRIPT_DIR / "uart_formal.sv",
        ]
    if target == "i2c":
        return [
            COMMON_RTL / "interface/ribp_if.sv",
            COMMON_RTL / "utils/register.sv",
            COMMON_RTL / "utils/fifo.sv",
            COMMON_RTL / "cdc/cdc_sync.sv",
            ROOT / "rtl/managed/clusterip/i2c/rtl/i2c_if.sv",
            SERIAL / "i2c_filter.sv",
            SERIAL / "i2c_core.sv",
            SERIAL / "i2c_reg.sv",
            SERIAL / "ribp_i2c.sv",
            SCRIPT_DIR / "i2c_formal.sv",
        ]
    if target == "timer":
        return [
            COMMON_RTL / "interface/ribp_if.sv",
            COMMON_RTL / "utils/register.sv",
            COMMON_RTL / "clkrst/counter.sv",
            PERIPHERAL / "timer_core.sv",
            PERIPHERAL / "timer_reg.sv",
            PERIPHERAL / "ribp_timer.sv",
            SCRIPT_DIR / "timer_formal.sv",
        ]
    if target == "clint":
        return [
            COMMON_RTL / "interface/ribp_if.sv",
            COMMON_RTL / "utils/register.sv",
            COMMON_RTL / "clkrst/counter.sv",
            PERIPHERAL / "clint_if.sv",
            PERIPHERAL / "clint_reg.sv",
            PERIPHERAL / "clint_core.sv",
            PERIPHERAL / "ribp_clint.sv",
            SCRIPT_DIR / "clint_formal.sv",
        ]
    if target == "dvp":
        return [
            COMMON_RTL / "interface/ribp_if.sv", COMMON_RTL / "utils/register.sv",
            ROOT / "rtl/ip/multimedia/dvp_define.svh",
            ROOT / "rtl/ip/multimedia/dvp_reg.sv",
            SCRIPT_DIR / "dvp_formal.sv",
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
            COMMON_RTL / "utils",
            INTERCONNECT,
            PERIPHERAL,
            SERIAL,
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
