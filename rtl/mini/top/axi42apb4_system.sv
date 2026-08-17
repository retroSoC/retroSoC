// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// See LICENSE for the complete license text.

`include "axi4_define.svh"
`include "mmap_define.svh"

module axi42apb4_system (
    input logic         clk_i,
    input logic         rst_n_i,
          axi4_if.slave axi4,
    `include "apb4_system_ports.svh"
);
  `include "axi42apb4_state.svh"
  `include "apb4_system_declarations.svh"

  assign s_decode_addr = s_addr_q;
  assign s_xfer_valid  = (s_fsm_q == FSM_SETP) || (s_fsm_q == FSM_ENAB);
  `include "apb4_system_request_routes.svh"
  `include "apb4_system_select_routes.svh"
  `include "apb4_system_response_mux.svh"
  assign s_psel_valid = |s_psel_comb;

  `include "axi42apb4.svh"
endmodule
