// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

`include "mmap_define.svh"

module ribp2apb (
    // verilog_format: off
    input  logic       clk_i,
    input  logic       rst_n_i,
    ribp_if.slave       ribp,
    output logic       resp_err_o,
`include "soc_apb_ports.svh"
    // verilog_format: on
);

  localparam FSM_IDLE = 2'd0;
  localparam FSM_SETP = 2'd1;
  localparam FSM_ENAB = 2'd2;

  logic [31:0] s_rd_data;
  logic s_xfer_valid, s_xfer_ready, s_xfer_error;
  logic s_mem_valid_re;
  logic [1:0] s_fsm_d, s_fsm_q;

  // Registered slave-select one-hot for response mux
  `include "soc_apb_declarations.svh"


  // Generated APB request routing retains the scalar interface protocol.
  `include "soc_apb_request_routes.svh"

  // verilog_format: off
  edge_det_sync_re #(1) u_mem_valid_edge_det_sync_re (
      clk_i,
      rst_n_i,
      ribp.valid,
      s_mem_valid_re
  );
  // verilog_format: on

  assign s_xfer_valid = ((s_fsm_q == FSM_IDLE) && s_mem_valid_re) ||
                         (s_fsm_q == FSM_SETP) || (s_fsm_q == FSM_ENAB);

  always_comb begin
    s_fsm_d = s_fsm_q;
    unique case (s_fsm_q)
      FSM_IDLE: if (s_mem_valid_re) s_fsm_d = FSM_SETP;
      FSM_SETP: s_fsm_d = FSM_ENAB;
      FSM_ENAB: if (s_xfer_ready) s_fsm_d = FSM_IDLE;
      default:  s_fsm_d = s_fsm_q;
    endcase
  end
  dffr #(2) u_fsm_dffr (
      clk_i,
      rst_n_i,
      s_fsm_d,
      s_fsm_q
  );

  assign ribp.ready = ribp.valid && (s_fsm_q == FSM_ENAB) && s_xfer_ready;
  assign ribp.rdata = {32{ribp.ready}} & s_rd_data;
  assign resp_err_o = ribp.ready && s_xfer_error;

  // Capture slave-select one-hot at FSM_SETP for cleaner response mux.
  `include "soc_apb_select_routes.svh"

  assign s_psel_d = (s_fsm_q == FSM_IDLE && s_mem_valid_re) ? s_psel_comb : s_psel_q;
  dffr #(NSLV) u_psel_dffr (
      clk_i,
      rst_n_i,
      s_psel_d,
      s_psel_q
  );

  // Generated response mux uses the registered one-hot target selection.
  `include "soc_apb_response_mux.svh"

endmodule
