# Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
# retroSoC is licensed under Mulan PSL v2.
# You can use this software according to the terms and conditions of the Mulan PSL v2.
# You may obtain a copy of Mulan PSL v2 at:
#             http://license.coscl.org.cn/MulanPSL2
# THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
# EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
# MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
# See the Mulan PSL v2 for more details.

proc flow::existing_ports {pattern} {
    return [get_ports -quiet $pattern]
}

proc flow::apply_constraints {} {
    set ext_port [flow::existing_ports extclk_i_pad]
    set aud_port [flow::existing_ports audclk_i_pad]
    set xtal_port [flow::existing_ports xi_i_pad]
    if {[sizeof_collection $ext_port] == 0 || [sizeof_collection $aud_port] == 0} {
        flow::fail "required external/audio clock ports are missing"
    }

    create_clock -name ext_clk -period [flow::env EXT_CLK_PERIOD_NS] $ext_port
    create_clock -name aud_clk -period [flow::env AUD_CLK_PERIOD_NS] $aud_port
    if {[sizeof_collection $xtal_port] > 0} {
        create_clock -name xtal_clk -period [flow::env XTAL_CLK_PERIOD_NS] $xtal_port
    }

    set pll_pin [get_pins -quiet u_rcu/u_tc_pll/u_PLL_TOP/CKOUT1]
    if {[sizeof_collection $pll_pin] > 0} {
        create_clock -name pll_clk -period [flow::env PLL_OUTPUT_PERIOD_NS] $pll_pin
        set_clock_groups -physically_exclusive \
            -group [get_clocks ext_clk] -group [get_clocks pll_clk]
    }

    set async_groups [list [get_clocks ext_clk] [get_clocks aud_clk]]
    if {[sizeof_collection [get_clocks -quiet xtal_clk]] > 0} {
        lappend async_groups [get_clocks xtal_clk]
    }
    set command [list set_clock_groups -asynchronous]
    foreach group $async_groups {
        lappend command -group $group
    }
    eval $command

    set clock_ports [add_to_collection $ext_port $aud_port]
    if {[sizeof_collection $xtal_port] > 0} {
        set clock_ports [add_to_collection $clock_ports $xtal_port]
    }
    set input_ports [remove_from_collection [all_inputs] $clock_ports]
    set reset_ports [get_ports -quiet *rst*n*]
    set input_ports [remove_from_collection $input_ports $reset_ports]
    if {[sizeof_collection $input_ports] > 0} {
        set_input_delay [flow::env INPUT_DELAY_NS] -clock ext_clk $input_ports
    }
    if {[sizeof_collection [all_outputs]] > 0} {
        set_output_delay [flow::env OUTPUT_DELAY_NS] -clock ext_clk [all_outputs]
    }
    set_clock_uncertainty [flow::env CLOCK_UNCERTAINTY_NS] [all_clocks]
    set_max_transition [flow::env MAX_TRANSITION_NS] [current_design]
    set_max_fanout [flow::env MAX_FANOUT] [current_design]
    if {[sizeof_collection $reset_ports] > 0} {
        set_false_path -from $reset_ports
    }
}
