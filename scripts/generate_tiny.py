#!/usr/bin/env python3
"""Generate Tiny integration bindings and absolute source lists from owned maps."""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from scripts.rtl.generate_memory_map import generate as generate_memory_map  # noqa: E402
from scripts.rtl.generate_pin_map import generate as generate_pin_map  # noqa: E402
from scripts.setup_helpers import atomic_write  # noqa: E402

TINY = ROOT / "rtl/tiny"
RCU_TARGETS = {"gpio": 1, "uart0": 2, "i2c0": 3, "timer0": 4, "timer1": 5,
               "pwm": 6, "i2s": 7, "sdio": 8, "dma": 9, "ws2812": 10,
               "rng": 11, "crc": 12, "crypto": 13, "dvp": 14, "spi": 16}


def read_topology(path: Path, memory_map: Path) -> dict:
    document = json.loads(path.read_text())
    regions = {r["symbol"] for r in json.loads(memory_map.read_text())["regions"]}
    if (document.get("schema_version") != 1 or document.get("dma_channels") != 8
            or document.get("dma_request_mask") != "0x339ff"):
        raise ValueError("Tiny SPI-P3 requires eight DMA channels and request mask 0x339ff")
    if document.get("cpu") != {"module": "hazard3_cpu_2port", "local_ports": 2,
                               "data_outstanding": 1}:
        raise ValueError("Tiny P4 requires independent I/D and one ordered data operation")
    memory = document.get("main_sram", {})
    if any(memory.get(key) != value for key, value in {
        "groups": 4, "group_bytes": 32768, "macros_per_group": 8,
        "macro_bytes": 4096, "base": "0x30000000",
        "macro_instance": "u_soc.u_sram.gen_group[{group}].u_group.gen_bank[{bank}].u_ram.u_mem",
        "external_attachment": "per-target-P5",
    }.items()):
        raise ValueError("Tiny SRAM geometry/P5 attachment differs from its frozen contract")
    if document.get("fabric") != {
        "owners": ["cpu_slow", "central_dma", "sdio"], "active_owners": [0, 1, 2],
        "cpu_combined_outstanding": 1, "dma_direction_outstanding": 1,
        "sdio_direction_outstanding": 1, "target_combined_outstanding": 1,
        "sram_targets": [0, 1, 2, 3], "xpi_target": 4, "apb_target_base": 5,
        "decode_error_target": 27, "protocol_error_target": 28, "target_count": 29,
    }:
        raise ValueError("Tiny SPI-P3 requires three active owners and 29 targets")
    if document.get("irq_vector_width") != 32 or document.get("external_irq_count") != 30:
        raise ValueError("Tiny requires a 32-bit IRQ vector and 30 external inputs")
    names: set[str] = set()
    bits: set[int] = set()
    for irq in document["interrupts"]:
        if irq["name"] in names or irq["core_bit"] in bits:
            raise ValueError("duplicate Tiny interrupt")
        if not 0 <= irq["core_bit"] < 32:
            raise ValueError("Tiny IRQ outside vector")
        names.add(irq["name"])
        bits.add(irq["core_bit"])
    assigned: set[str] = set()
    for target in document["apb_targets"]:
        for region in target["regions"]:
            if region not in regions or region in assigned:
                raise ValueError(f"invalid or duplicate APB region {region}")
            assigned.add(region)
    if assigned != {r for r in regions if r.startswith("APB4_")}:
        raise ValueError("Tiny topology must route every APB region")
    if len(document["apb_targets"]) != 22:
        raise ValueError("Tiny SPI-P3 requires twenty-two independent APB targets")
    target_names = [target["name"] for target in document["apb_targets"]]
    if len(set(target_names)) != 22 or any(re.fullmatch(r"[a-z][a-z0-9_]*", name) is None
                                         for name in target_names):
        raise ValueError("Tiny APB target names must be unique identifiers")
    if sorted(item["pin"] for item in document["gpio_alt_functions"]) != list(range(32)):
        raise ValueError("Tiny GPIO map must contain all 32 pins exactly once")
    inputs = [signal for pin in document["gpio_alt_functions"] for mode in ("alt0", "alt1")
              for signal in pin[mode]["inputs"]]
    if len(inputs) != len(set(inputs)):
        raise ValueError("Tiny peripheral inputs require one exclusive route")
    if document.get("private_crypto") != {
        "banks": 6, "bank_bytes": 4096,
        "macro_instance": "u_soc.u_crypto.u_storage.gen_bank[{bank}].gen_macro.u_sram.u_mem",
        "clock_domain": "peripheral", "logical_domain": "PCLK",
    }:
        raise ValueError("Tiny requires six private Crypto banks on PCLK")
    return document


def platform_values(pdk: str, have_pll: bool = False) -> dict[str, int]:
    if (pdk, have_pll) not in (("IHP130", False), ("ICS55", True)):
        raise ValueError("unsupported Tiny PDK/PLL combination")
    return {"technology": 0x02040037 if pdk == "ICS55" else 0x02010082,
            "features0": 0x7FFE | int(have_pll), "pll_present": int(have_pll),
            "gpio_pulls": int(pdk == "ICS55")}


def generate_bindings(document: dict, output: Path, pdk: str = "IHP130",
                      have_pll: bool = False) -> None:
    platform = platform_values(pdk, have_pll)
    comment = "// Generated by scripts/generate_tiny.py; do not edit.\n"
    constants = [comment, "`ifndef RETROSOC_TINY__TOPOLOGY_SVH",
                 "`define RETROSOC_TINY__TOPOLOGY_SVH",
                 f"`define RETROSOC_TINY__TARGET_COUNT {document['fabric']['target_count']}",
                 f"`define RETROSOC_TINY__LEAF_COUNT {len(document['apb_targets']) + 1}",
                 f"`define RETROSOC_TINY__DECODE_ERROR {document['fabric']['decode_error_target']}",
                 f"`define RETROSOC_TINY__PROTOCOL_ERROR {document['fabric']['protocol_error_target']}"]
    constants += [f"`define RETROSOC_TINY__TARGET_{target['name'].upper()} {index + 5}"
                  for index, target in enumerate(document["apb_targets"])]
    constants.append("`endif\n")
    atomic_write(output / "rtl/tiny_topology.svh", "\n".join(constants))
    # Keep board pulls independently resolved. A packed tri1 with partial
    # external drivers loses its weak pulls in the locked Verilator 5.046.
    board = [comment, *[f"tri1 s_gpio_{pin};" for pin in range(document["gpio_pins"])]]
    board.append("wire [31:0] s_gpio = {" +
                 ", ".join(f"s_gpio_{pin}" for pin in reversed(range(32))) + "};\n")
    atomic_write(output / "rtl/tiny_tb_gpio.svh", "\n".join(board))
    irq = [comment, "always_comb begin", "  s_irq_async = '0;"]
    header = ["#ifndef RETROSOC_GENERATED_IRQ_METADATA_H",
              "#define RETROSOC_GENERATED_IRQ_METADATA_H", "#include <stdint.h>",
              "#define RS_SOC_IRQ_VECTOR_WIDTH UINT32_C(32)",
              "#define RS_SOC_EXTERNAL_IRQ_COUNT UINT32_C(30)",
              f"#define RS_SOC_ALLOCATED_IRQ_COUNT UINT32_C({len(document['interrupts']) - 2})"]
    for item in document["interrupts"]:
        bit, name = item["core_bit"], item["name"].upper()
        irq.append(f"  s_irq_async[{bit}] = {item['signal']};")
        header.append(f"#define RS_SOC_IRQ_{name} UINT32_C({bit})")
        if bit >= 2:
            header.append(f"#define RS_SOC_EXT_IRQ_{name} UINT32_C({bit - 2})")
    irq.append("end\n")
    header.append("#endif\n")
    atomic_write(output / "rtl/tiny_irq.svh", "\n".join(irq))
    atomic_write(output / "include/retrosoc/generated/irq_metadata.h", "\n".join(header))
    atomic_write(output / "include/retrosoc/generated/user_extensions.h",
                 "#ifndef RETROSOC_GENERATED_USER_EXTENSIONS_H\n"
                 "#define RETROSOC_GENERATED_USER_EXTENSIONS_H\n"
                 "#define RS_SOC_USER_CORE_COUNT 0U\n#define RS_SOC_USER_IP_COUNT 0U\n"
                 "#define RS_SOC_HAS_USER_CORES 0U\n#define RS_SOC_HAS_USER_IP_MUX 0U\n#endif\n")
    atomic_write(output / "include/retrosoc/generated/soc_features.h",
                 "#ifndef RETROSOC_GENERATED_SOC_FEATURES_H\n"
                 "#define RETROSOC_GENERATED_SOC_FEATURES_H\n"
                 "#define RS_SOC_TINY 1\n#define RS_SOC_HAS_PSRAM 0U\n"
                 "#define RS_SOC_DMA_CHANNELS 8U\n#define RS_SOC_ID 0x54494E59U\n"
                 f"#define RS_SOC_DMA_REQUEST_MASK {document['dma_request_mask']}U\n"
                 "#define RS_SOC_HAS_I2C1 0U\n#define RS_SOC_HAS_SDIO1 0U\n"
                 "#define RS_SOC_HAS_UART0 1U\n#define RS_SOC_HAS_UART1 0U\n"
                 "#define RS_SOC_HAS_I2C0 1U\n"
                 "#define RS_SOC_HAS_RNG 1U\n#define RS_SOC_HAS_CRC 1U\n"
                 "#define RS_SOC_HAS_WS2812 1U\n#define RS_SOC_HAS_CRYPTO 1U\n"
                 "#define RS_SOC_HAS_I2S 1U\n#define RS_SOC_HAS_SDIO0 1U\n"
                 "#define RS_SOC_HAS_DVP 1U\n#define RS_SOC_DVP_DMA_CHANNEL 2U\n"
                 "#define RS_SOC_DVP_DMA_BURST_BEATS 4U\n#define RS_SOC_RNG_QUALIFIED 0U\n"
                 "#define RS_SOC_HAS_SPI 1U\n#define RS_SOC_SPI_DMA_TX 16U\n"
                 "#define RS_SOC_SPI_DMA_RX 17U\n"
                 f"#define RS_SOC_TECHNOLOGY_ID 0x{platform['technology']:08X}U\n"
                 f"#define RS_SOC_PLL_PRESENT {platform['pll_present']}U\n"
                 f"#define RS_SOC_GPIO_HAS_PULLS {platform['gpio_pulls']}U\n#endif\n")
    atomic_write(output / "rtl/tiny_platform.svh", comment +
                 f"`define RETROSOC_TINY__TECHNOLOGY 32'h{platform['technology']:08x}\n"
                 f"`define RETROSOC_TINY__FEATURES0 32'h{platform['features0']:08x}\n")
    gpio = [comment]
    for function in document["gpio_alt_functions"]:
        pin = function["pin"]
        for mode in ("alt0", "alt1"):
            value = function[mode]
            gpio.extend(f"assign {signal} = u_gpio_if.di_i[{pin}];" for signal in value["inputs"])
            gpio.extend((f"assign u_gpio_if.{mode}_do_i[{pin}] = {value['do']};",
                         f"assign u_gpio_if.{mode}_oe_i[{pin}] = {value['oe']};"))
    atomic_write(output / "rtl/tiny_gpio.svh", "\n".join(gpio) + "\n")
    declarations, bridges, decode = [comment], [comment], [comment]
    reset_assignments = []
    for index, target in enumerate(document["apb_targets"]):
        name = target["name"]
        clock = ("s_ref_clk" if name in ("clint", "archinfo") else
                 "s_backend_mem_clk" if name == "xpi" else
                 "s_exec_clk" if name in ("sysctrl", "sram", "sdio") else "s_backend_pclk")
        target_bit = RCU_TARGETS.get(name)
        ip_clock = f"s_{name}_clk" if target_bit is not None else clock
        if target_bit is not None:
            declarations.append(f"logic {ip_clock};")
        declarations.append(f"logic s_{name}_rst_n;")
        if name == "spi":
            # Only SPI consumes the origin/channel qualifier; other crossings tie off below.
            declarations.append(f"logic [1:0] s_{name}_origin_sys;")
            declarations.append(f"logic [2:0] s_{name}_channel_sys;")
        declarations.append(f"apb4_if u_{name}_apb4_if (.pclk({ip_clock}), .presetn(s_{name}_rst_n));")
        if target_bit is None:
            reset_assignments.append(f"assign s_{name}_rst_n = s_leaf_rst_n[{index + 1}];")
        else:
            reset_assignments.append(f"(* keep_hierarchy = 1 *) tiny_peripheral_leaf u_{name}_lifecycle ("
                                    f".clk_i({clock}), .rst_n_i(s_leaf_rst_n[{index + 1}]), "
                                    f".gate_i(s_gate_request[{target_bit}]), "
                                    f".reset_i(s_local_reset[{target_bit}]), "
                                    f".clk_o({ip_clock}), .rst_n_o(s_{name}_rst_n), "
                                    f".gated_o(s_actual_gate[{target_bit}]), "
                                    f".held_o(s_reset_held[{target_bit}]));")
            extra_ready = " && s_i2s_reset_ready" if name == "i2s" else ""
            if name == "dvp":
                # Local camera reset waits for its pixel domain. Global CPU
                # boot uses APB/AXI barriers, not this local-reset vector.
                extra_ready = " && s_dvp_reset_ready"
            if name == "dma":
                # CDC-ready outputs are observed in SYS, matching APB readiness.
                extra_ready = " && s_dma_ready_sys && s_dma_idle_sys"
            reset_assignments.append(f"assign s_reset_ready[{target_bit}] = s_{name}_rst_n && "
                                    f"s_apb_cdc_ready[{index}]{extra_ready};")
        reset_assignments.append(f"assign s_leaf_clk[{index + 1}] = {clock};")
        bridges.append(f"assign s_target_rst_n[{index + 5}] = s_fabric_rst_n;")
        crossed = clock != "s_exec_clk" or target_bit is not None
        endpoint = f"u_{name}_sys_apb4_if" if crossed else f"u_{name}_apb4_if"
        qualifier = (f".origin_o(s_{name}_origin_sys), .channel_o(s_{name}_channel_sys)"
                     if name == "spi" else ".origin_o(), .channel_o()")
        bridges.append(f"tiny_axi42apb4 u_{name}_bridge ("
                       f".clk_i(s_exec_clk), .rst_n_i(s_fabric_rst_n), "
                       f".axi4(u_targets_axi4_if[{index + 5}]), .apb4({endpoint}), {qualifier});")
        if crossed:
            disabled = f"s_disabled_sys[{target_bit}]" if target_bit is not None else "1'b0"
            source = (f".src_origin_i(s_{name}_origin_sys), .src_channel_i(s_{name}_channel_sys)"
                      if name == "spi" else ".src_origin_i(2'd0), .src_channel_i(3'd0)")
            declarations.append(f"apb4_if {endpoint} (.pclk(s_exec_clk), .presetn(s_fabric_rst_n));")
            bridges.append(f"tiny_apb_async_bridge u_{name}_cfg_cdc ("
                           f".src_clk_i(s_exec_clk), .src_rst_n_i(s_fabric_rst_n), "
                           f".dst_clk_i({ip_clock}), .dst_rst_n_i(s_{name}_rst_n), "
                           f".disabled_i({disabled}), "
                           f"{source}, "
                           f".dst_origin_o({ 's_spi_origin' if name == 'spi' else ''}), "
                           f".dst_channel_o({ 's_spi_channel' if name == 'spi' else ''}), "
                           f".idle_o(s_apb_cdc_idle[{index}]), "
                           f".ready_o(s_apb_cdc_ready[{index}]), "
                           f".src_apb4({endpoint}), .dst_apb4(u_{name}_apb4_if));")
        else:
            bridges.append(f"assign s_apb_cdc_idle[{index}] = 1'b1;")
            bridges.append(f"assign s_apb_cdc_ready[{index}] = 1'b1;")
        decode.append(f"if ({' || '.join(f'`SOC_ADDR_IS_{r}(addr_i)' for r in target['regions'])}) "
                      f"return 5'd{index + 5};")
    atomic_write(output / "rtl/tiny_apb_interfaces.svh", "\n".join(declarations + reset_assignments) + "\n")
    atomic_write(output / "rtl/tiny_apb_bridges.svh", "\n".join(bridges) + "\n")
    atomic_write(output / "rtl/tiny_fabric_decode.svh", "\n".join(decode) + "\n")


def generate_filelists(output: Path, generated: Path, defines: list[str],
                       pdk: str = "IHP130", simulator: str = "VERILATOR",
                       synthesis: str = "NONE") -> None:
    prefixes = {"top": TINY / "top", "dv": TINY / "dv", "ip": ROOT / "rtl/ip",
                "tech": ROOT / "rtl/tech", "clusterip": ROOT / "rtl/managed/clusterip",
                "hazard3": ROOT / "rtl/managed/hazard3/hdl", "physical": ROOT / "physical",
                "cache": ROOT / ".cache", "tests": ROOT / "tests",
                "device_model": ROOT / "rtl/model"}
    suffix = "_yosys" if synthesis == "YOSYS" else "_verilator" if simulator == "VERILATOR" else ""
    pdk_name = "pdk_ihp130.fl" if pdk == "IHP130" else f"pdk_ics55{suffix}.fl"
    templates = [*sorted((TINY / "filelist").glob("*.fl")),
                 ROOT / "rtl/filelist" / pdk_name]
    for template in templates:
        content = template.read_text()
        for prefix, directory in prefixes.items():
            content = re.sub(rf"(?<![^\s+])/{prefix}(?=/|\s|$)", str(directory), content)
        if template.name == pdk_name and pdk == "ICS55":
            # The shared tc_sram file also declares an unused 16 KiB wrapper.
            # Keep its official interface visible to parsers; Tiny must never
            # instantiate it (the mapped-netlist audit rejects that case).
            content = content.replace("ics55_ecos_sram_4096x32_m8_core.v",
                                      "ics55_ecos_sram_4096x32_m8_stub.v")
        atomic_write(output / template.name, content)
        if template.name == pdk_name:
            if pdk == "ICS55" and synthesis != "YOSYS":
                content += str(ROOT / ".cache/retrosoc/sources/ics55_ecos_pll/verilog/PLL_TOP.behavioral.v") + "\n"
            atomic_write(output / "pdk_selected.fl", content)
    include = [TINY / "dv", generated / "rtl", generated / "memory_map/rtl", generated / "pin_map/rtl",
               generated / "archinfo"]
    atomic_write(output / "def.fl", " ".join([*defines, *(f"+incdir+{p}" for p in include)]) + "\n")
    atomic_write(output / "pdk_local.fl", "")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--filelists", type=Path)
    parser.add_argument("--define", action="append", default=[])
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--pdk", choices=("IHP130", "ICS55"), default="IHP130")
    parser.add_argument("--simulator", choices=("IVERILOG", "VERILATOR"), default="VERILATOR")
    parser.add_argument("--synthesis", choices=("NONE", "YOSYS"), default="NONE")
    args = parser.parse_args()
    document = read_topology(TINY / "integration/soc_topology.json",
                             TINY / "address_map/memory_map.json")
    if args.check:
        return 0
    if args.output is None or args.filelists is None:
        parser.error("--output and --filelists are required unless --check is used")
    if any(not value.startswith("+define+") for value in args.define):
        parser.error("--define requires a +define+ token")
    output = args.output.resolve()
    generate_memory_map(TINY / "address_map/memory_map.json", output / "memory_map", "YES", 128)
    generate_pin_map(TINY / "pin_map/pin_map.json", output / "pin_map", read_while_driving=True)
    generate_bindings(document, output, args.pdk, "+define+HAVE_PLL" in args.define)
    generate_filelists(args.filelists.resolve(), output, args.define,
                       args.pdk, args.simulator, args.synthesis)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
