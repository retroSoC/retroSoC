# Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
# retroSoC is licensed under Mulan PSL v2.
# You can use this software according to the terms and conditions of the Mulan PSL v2.
# You may obtain a copy of Mulan PSL v2 at:
#             http://license.coscl.org.cn/MulanPSL2
# THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
# EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
# MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
# See the Mulan PSL v2 for more details.

# retroSoC Mini (retrosoc_asic) product overlay.
#
# Clock intent: the canonical contract (rtl/mini/integration/
# clock_reset_domains.json) owns nine domains. This overlay takes over the
# lp/pclk domains because the LP root mux selects between the 24 MHz reference
# (bypass) and the PLL (performance) source; both modes are modeled as
# physically exclusive generated clocks, preserving the legacy commercial
# system-clock mux semantics on the current hierarchy.

namespace eval product {}

proc product::expected_clock_domains {} {
    return {aon lp hp pclk memory audio jtag dvp usb2_ulpi}
}

proc product::custom_clock_domains {} {
    return {lp pclk}
}

proc product::clock_names {} {
    return {
        clk_aon clk_hp clk_memory clk_audio clk_jtag clk_dvp clk_usb2_ulpi
        clk_pll clk_lp_ext clk_lp_pll clk_pclk_ext clk_pclk_pll
    }
}

proc product::io_interface_groups {} {
    return {JTAG DVP ULPI SDRAM SDIO XPI ASYNC}
}

proc product::apply_clock_overlays {} {
    set pll_pin [flow::required_pins pll_clock \
        u_rcu/u_clock_reset_subsystem/u_tc_pll/u_PLL_TOP/CKOUT1]
    create_clock -name clk_pll -period [flow::env PLL_OUTPUT_PERIOD_NS] $pll_pin
    flow::register_clock clk_pll lp

    set aon_object [flow::domain_object aon]
    set lp_object [flow::domain_object lp]
    create_generated_clock -name clk_lp_ext -master_clock clk_aon \
        -source $aon_object -divide_by 1 $lp_object
    flow::register_clock clk_lp_ext lp
    create_generated_clock -name clk_lp_pll -master_clock clk_pll \
        -source $pll_pin -divide_by 1 -add $lp_object
    flow::register_clock clk_lp_pll lp

    set pclk_object [flow::domain_object pclk]
    create_generated_clock -name clk_pclk_ext -master_clock clk_lp_ext \
        -source $lp_object -divide_by 1 $pclk_object
    flow::register_clock clk_pclk_ext lp
    create_generated_clock -name clk_pclk_pll -master_clock clk_lp_pll \
        -source $lp_object -divide_by 1 -add $pclk_object
    flow::register_clock clk_pclk_pll lp

    set_clock_groups -name retrosoc_system_sources -physically_exclusive \
        -group [get_clocks {clk_aon clk_lp_ext clk_pclk_ext}] \
        -group [get_clocks {clk_pll clk_lp_pll clk_pclk_pll}]
}

proc product::apply_io_constraints {} {
    set jtag_in [flow::interface_ports jtag {jtag_tms_i_pad jtag_tdi_i_pad}]
    set jtag_out [flow::interface_ports jtag {jtag_tdo_o_pad}]
    flow::apply_input_budget JTAG clk_jtag $jtag_in
    flow::apply_output_budget JTAG clk_jtag $jtag_out

    set dvp_names [flow::numbered_ports gpio_ 11 20 _io_pad]
    set dvp_in [flow::interface_ports dvp $dvp_names]
    flow::apply_input_budget DVP clk_dvp $dvp_in

    set ulpi_data [flow::numbered_ports usb2_ulpi_data 0 7 _io_pad]
    set ulpi_in [flow::interface_ports ulpi \
        [concat {usb2_ulpi_dir_i_pad usb2_ulpi_nxt_i_pad} $ulpi_data]]
    set ulpi_out [flow::interface_ports ulpi \
        [concat $ulpi_data {usb2_ulpi_stp_o_pad}]]
    flow::apply_input_budget ULPI clk_usb2_ulpi $ulpi_in
    flow::apply_output_budget ULPI clk_usb2_ulpi $ulpi_out

    set sdram_data [flow::numbered_ports sdram_dq 0 15 _io_pad]
    set sdram_out_names {
        sdram_clk_o_pad sdram_cke_o_pad sdram_cs_n_o_pad
        sdram_ras_n_o_pad sdram_cas_n_o_pad sdram_we_n_o_pad
        sdram_ba0_o_pad sdram_ba1_o_pad sdram_dqm0_o_pad sdram_dqm1_o_pad
    }
    set sdram_out_names [concat $sdram_out_names \
        [flow::numbered_ports sdram_addr 0 12 _o_pad] $sdram_data]
    set sdram_clock [flow::create_virtual_interface_clock SDRAM]
    flow::apply_input_budget SDRAM $sdram_clock \
        [flow::interface_ports sdram $sdram_data]
    flow::apply_output_budget SDRAM $sdram_clock \
        [flow::interface_ports sdram $sdram_out_names]

    set sdio_data {
        sdio1_cmd_io_pad sdio1_dat0_io_pad sdio1_dat1_io_pad
        sdio1_dat2_io_pad sdio1_dat3_io_pad
    }
    set sdio_clock [flow::create_virtual_interface_clock SDIO]
    flow::apply_input_budget SDIO $sdio_clock [flow::interface_ports sdio $sdio_data]
    flow::apply_output_budget SDIO $sdio_clock \
        [flow::interface_ports sdio [concat {sdio1_clk_o_pad} $sdio_data]]

    set xpi_data [flow::numbered_ports xpi_dat 0 3 _io_pad]
    set xpi_clock [flow::create_virtual_interface_clock XPI]
    flow::apply_input_budget XPI $xpi_clock [flow::interface_ports xpi $xpi_data]
    flow::apply_output_budget XPI $xpi_clock [flow::interface_ports xpi \
        [concat {xpi_sck_o_pad xpi_nss0_o_pad xpi_nss1_o_pad
            xpi_nss2_o_pad xpi_nss3_o_pad} $xpi_data]]

    set gpio_names [concat \
        [flow::numbered_ports gpio_ 0 9 _io_pad] \
        [flow::numbered_ports gpio_ 21 31 _io_pad]]
    set async_clock [flow::create_virtual_interface_clock ASYNC]
    flow::apply_input_budget ASYNC $async_clock \
        [flow::interface_ports asynchronous \
            [concat {uart0_rx_i_pad uart1_rx_i_pad} $gpio_names]]
    flow::apply_output_budget ASYNC $async_clock \
        [flow::interface_ports asynchronous \
            [concat {uart0_tx_o_pad uart1_tx_o_pad} $gpio_names]]

    set_false_path -to [flow::interface_ports asynchronous_control \
        {usb2_ulpi_reset_n_o_pad}]
    flow::source_hook TIMING_IO_MODE_HOOK
}
