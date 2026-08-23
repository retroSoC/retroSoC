# Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
# retroSoC is licensed under Mulan PSL v2.
# You can use this software according to the terms and conditions of the Mulan PSL v2.
# You may obtain a copy of Mulan PSL v2 at:
#             http://license.coscl.org.cn/MulanPSL2
# THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
# EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
# MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
# See the Mulan PSL v2 for more details.

set constraints_dir [file dirname [info script]]
source [file join $constraints_dir clocks.tcl]
source [file join $constraints_dir io_constraints.tcl]

proc flow::apply_constraints {} {
    flow::load_canonical_timing_contract
    flow::apply_clock_constraints
    flow::apply_io_constraints

    set_max_transition [flow::env MAX_TRANSITION_NS] [current_design]
    set_max_fanout [flow::env MAX_FANOUT] [current_design]
    flow::source_hook TIMING_EXCEPTION_HOOK
}
