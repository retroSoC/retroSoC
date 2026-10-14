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
# clock_reset_domains.json) owns REF24, derived SYS/MEM/PCLK, JTAG and GPIO17
# AUDIO. This adapter covers SAFE24 boot only. RCU can enable the physical PLL
# in functional operation, but its active timing remains unqualified.

namespace eval product {}

proc product::expected_clock_domains {} {
    return {aon system memory peripheral jtag audio}
}

proc product::custom_clock_domains {} {
    return {}
}

proc product::clock_names {} {
    return {clk_aon clk_system clk_memory clk_peripheral clk_jtag clk_audio clk_sys_div2 clk_sys_div4 clk_clkout_source}
}

proc product::io_interface_groups {} {
    return {JTAG XPI ASYNC}
}

proc product::apply_clock_overlays {} {
    foreach divisor {2 4} {
        create_generated_clock -name clk_sys_div$divisor \
            -source [flow::domain_object system] -divide_by $divisor \
            [flow::required_net_driver_pin "Tiny SYS /$divisor" \
                "u_soc/u_clock_backend/s_div${divisor}_clk"]
        flow::register_clock clk_sys_div$divisor core
    }
    foreach mux {u_sys_mux u_mem_mux u_pclk_div2_mux u_pclk_mux} {
        set_case_analysis 0 [flow::required_pins "Tiny SAFE24 mux $mux" \
            "u_soc/u_clock_backend/$mux/select_i"]
        foreach {side enabled} {0 1 1 0} {
            set_case_analysis $enabled [flow::required_net_driver_pin "Tiny settled clock gate" \
                "u_soc/u_clock_backend/$mux/r_enable$side"]
        }
    }
    set_case_analysis 0 [flow::required_pins "Tiny SAFE24 PLL enable" \
        "u_soc/u_clock_backend/u_pll/gen_ecos/u_backend/u_PLL_TOP/EN"]
    foreach bit {1 2} {
        set_case_analysis 0 [flow::required_net_driver_pin "Tiny boot CLKOUT source" \
            "u_soc/u_clock_output/s_cfg_q\[$bit\]"]
    }
    create_generated_clock -name clk_clkout_source -source [flow::domain_object aon] \
        -divide_by 1 [flow::required_net_driver_pin "Tiny boot CLKOUT source clock" \
            "u_soc/u_clock_output/s_src_clk"]
    flow::register_clock clk_clkout_source core
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
