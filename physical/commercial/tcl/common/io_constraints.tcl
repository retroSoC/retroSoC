# Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
# retroSoC is licensed under Mulan PSL v2.
# You can use this software according to the terms and conditions of the Mulan PSL v2.
# You may obtain a copy of Mulan PSL v2 at:
#             http://license.coscl.org.cn/MulanPSL2
# THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND.

namespace eval flow {
    variable io_qualified 0
    variable unqualified_interfaces {}
}

proc flow::interface_ports {label names} {
    return [flow::required_ports "$label interface" $names]
}

proc flow::apply_input_budget {prefix clock ports} {
    set_input_delay -clock $clock -max [flow::env ${prefix}_INPUT_DELAY_MAX_NS] $ports
    set_input_delay -clock $clock -min [flow::env ${prefix}_INPUT_DELAY_MIN_NS] $ports
    set_input_transition -max [flow::env ${prefix}_INPUT_TRANSITION_NS] $ports
    set_input_transition -min [flow::env ${prefix}_INPUT_TRANSITION_NS] $ports
}

proc flow::apply_output_budget {prefix clock ports} {
    set_output_delay -clock $clock -max [flow::env ${prefix}_OUTPUT_DELAY_MAX_NS] $ports
    set_output_delay -clock $clock -min [flow::env ${prefix}_OUTPUT_DELAY_MIN_NS] $ports
    set_load [flow::env ${prefix}_OUTPUT_LOAD_PF] $ports
}

proc flow::create_virtual_interface_clock {prefix} {
    set name vclk_[string tolower $prefix]
    create_clock -name $name -period [flow::env ${prefix}_CLOCK_PERIOD_NS]
    return $name
}

proc flow::numbered_ports {prefix first last suffix} {
    set names {}
    for {set index $first} {$index <= $last} {incr index} {
        lappend names ${prefix}${index}${suffix}
    }
    return $names
}

proc flow::apply_qualified_io_constraints {} {
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
        [flow::interface_ports asynchronous [concat {uart0_rx_i_pad} $gpio_names]]
    flow::apply_output_budget ASYNC $async_clock \
        [flow::interface_ports asynchronous [concat {uart0_tx_o_pad} $gpio_names]]

    set_false_path -to [flow::interface_ports asynchronous_control \
        {xo_o_pad usb2_ulpi_reset_n_o_pad}]
    flow::source_hook TIMING_IO_MODE_HOOK
}

proc flow::apply_io_constraints {} {
    variable io_qualified
    variable unqualified_interfaces
    set mode [string toupper [flow::env IO_TIMING_QUALIFIED NO]]
    if {$mode eq "YES"} {
        set io_qualified 1
        set unqualified_interfaces {}
        flow::apply_qualified_io_constraints
    } elseif {$mode eq "NO"} {
        set io_qualified 0
        set unqualified_interfaces {JTAG DVP ULPI SDRAM SDIO XPI ASYNC}
        # Internal-QoR mode closes all sequential domains while explicitly
        # excluding board and package paths that do not yet have a budget.
        set_false_path -from [all_inputs]
        set_false_path -to [all_outputs]
    } else {
        flow::fail "IO_TIMING_QUALIFIED must be YES or NO"
    }
}
