// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.
// See LICENSE for the complete license text.

`include "axi4_define.svh"
`include "mmap_define.svh"

module axi42apb4_periph (
    input logic         clk_i,
    input logic         rst_n_i,
          axi4_if.slave axi4,
    `include "apb4_periph_ports.svh"
);
  `include "axi42apb4_state.svh"
  `include "apb4_periph_declarations.svh"

  assign s_decode_addr = s_addr_q;
  assign s_xfer_valid  = (s_fsm_q == FSM_SETP) || (s_fsm_q == FSM_ENAB);
  `include "apb4_periph_request_routes.svh"
  `include "apb4_periph_select_routes.svh"
  `include "apb4_periph_response_mux.svh"
  assign s_psel_valid = |s_psel_comb;

  `include "axi42apb4.svh"
endmodule
