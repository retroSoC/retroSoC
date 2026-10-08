# Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
# retroSoC is licensed under Mulan PSL v2.
# You can use this software according to the terms and conditions of the Mulan PSL v2.
# You may obtain a copy of Mulan PSL v2 at:
#             http://license.coscl.org.cn/MulanPSL2
# THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
# EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
# MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
# See the Mulan PSL v2 for more details.

# retroSoC Tiny (retrosoc_tiny_asic) product overlay.
#
# Clock intent: the canonical contract (rtl/tiny/integration/
# clock_reset_domains.json) owns two domains, system (SAFE24 external clock)
# and jtag. The ICS55 PLL_TOP macro is present but parked off (EN=0) and is
# not a clock source; it carries no characterized timing arcs yet, so no PLL
# overlay clock is created here. See docs/ip/tiny-soc.md (TINY-055).

namespace eval product {}

proc product::expected_clock_domains {} {
    return {system jtag}
}

proc product::custom_clock_domains {} {
    return {}
}

proc product::clock_names {} {
    return {clk_system clk_jtag}
}

proc product::io_interface_groups {} {
    return {JTAG XPI ASYNC}
}

proc product::apply_clock_overlays {} {
}

proc product::apply_io_constraints {} {
    set jtag_in [flow::interface_ports jtag {jtag_tms_i_pad jtag_tdi_i_pad}]
    set jtag_out [flow::interface_ports jtag {jtag_tdo_o_pad}]
    flow::apply_input_budget JTAG clk_jtag $jtag_in
    flow::apply_output_budget JTAG clk_jtag $jtag_out

    set xpi_data [flow::numbered_ports xpi_dat 0 3 _io_pad]
    set xpi_clock [flow::create_virtual_interface_clock XPI]
    flow::apply_input_budget XPI $xpi_clock [flow::interface_ports xpi $xpi_data]
    flow::apply_output_budget XPI $xpi_clock [flow::interface_ports xpi \
        [concat {xpi_sck_o_pad xpi_nss0_o_pad xpi_nss1_o_pad
            xpi_nss2_o_pad xpi_nss3_o_pad} $xpi_data]]

    set gpio_names [flow::numbered_ports gpio_ 0 31 _io_pad]
    set async_clock [flow::create_virtual_interface_clock ASYNC]
    flow::apply_input_budget ASYNC $async_clock \
        [flow::interface_ports asynchronous \
            [concat {uart0_rx_i_pad uart1_rx_i_pad} $gpio_names]]
    flow::apply_output_budget ASYNC $async_clock \
        [flow::interface_ports asynchronous \
            [concat {uart0_tx_o_pad uart1_tx_o_pad} $gpio_names]]
}
