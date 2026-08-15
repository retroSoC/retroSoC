// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of the Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

`include "mmap_define.svh"
`include "rib_defs.svh"

module rib2apb (
    // verilog_format: off -- preserve reviewed column alignment
    input  logic       clk_i,
    input  logic       rst_n_i,
    rib_if.slave       rib,
`include "soc_apb_ports.svh"
    // verilog_format: on
);

  localparam logic [2:0] FSM_CMD = 3'd0;
  localparam logic [2:0] FSM_WDATA = 3'd1;
  localparam logic [2:0] FSM_SETP = 3'd2;
  localparam logic [2:0] FSM_ENAB = 3'd3;
  localparam logic [2:0] FSM_DROP_WDATA = 3'd4;
  localparam logic [2:0] FSM_ERR = 3'd5;
  localparam int RSP_WIDTH = 39;

  logic [31:0] s_rd_data;
  logic s_xfer_valid, s_xfer_ready, s_xfer_err;
  logic [2:0] s_fsm_d, s_fsm_q;
  logic [31:0] s_addr_q, s_wdata_q;
  logic [31:0] s_decode_addr;
  logic [ 3:0] s_wstrb_q;
  logic        s_write_q;
  logic [2:0] s_err_code_d, s_err_code_q;
  logic s_cmd_hdshk, s_w_hdshk, s_rsp_hdshk;
  logic s_psel_valid;
  logic s_rsp_input_valid, s_rsp_input_ready;
  logic [RSP_WIDTH-1:0] s_rsp_input_data, s_rsp_output_data;

  // Registered slave-select one-hot and APB response mux.
  `include "soc_apb_declarations.svh"

  assign s_cmd_hdshk   = rib.cmd_valid && rib.cmd_ready;
  assign s_decode_addr = rib.cmd_addr;
  assign s_w_hdshk     = rib.w_valid && rib.w_ready;

  assign rib.cmd_ready = (s_fsm_q == FSM_CMD) && !rib.rsp_valid;
  assign rib.w_ready   = (s_fsm_q == FSM_WDATA) || (s_fsm_q == FSM_DROP_WDATA);

  assign s_xfer_valid  = (s_fsm_q == FSM_SETP) || (s_fsm_q == FSM_ENAB);

  // Generated APB routing uses the latched RIB request and selected target.
  `include "soc_apb_request_routes.svh"
  `include "soc_apb_select_routes.svh"
  `include "soc_apb_response_mux.svh"

  assign s_psel_valid = |s_psel_comb;

  assign s_rsp_input_valid = ((s_fsm_q == FSM_ENAB) && s_xfer_ready) || (s_fsm_q == FSM_ERR);
  assign s_rsp_input_data = (s_fsm_q == FSM_ENAB) ?
      {1'b1, 2'd0, s_xfer_err ? `RIB_RESP_SLVERR : `RIB_RESP_OK, s_xfer_err,
       s_write_q ? 32'd0 : s_rd_data} :
      {1'b1, 2'd0, s_err_code_q, 1'b1, 32'd0};
  assign s_rsp_hdshk = s_rsp_input_valid && s_rsp_input_ready;

  spill_register #(
      .DATA_WIDTH(RSP_WIDTH),
      .BYPASS    (1'b0)
  ) u_rsp_spill_register (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .flush_i(1'b0),
      .valid_i(s_rsp_input_valid),
      .ready_o(s_rsp_input_ready),
      .data_i (s_rsp_input_data),
      .valid_o(rib.rsp_valid),
      .ready_i(rib.rsp_ready),
      .data_o (s_rsp_output_data)
  );

  assign rib.rdata     = s_rsp_output_data[31:0];
  assign rib.resp_err  = s_rsp_output_data[32];
  assign rib.resp_code = s_rsp_output_data[35:33];
  assign rib.rsp_beat  = s_rsp_output_data[37:36];
  assign rib.rsp_last  = s_rsp_output_data[38];

  always_comb begin
    s_fsm_d      = s_fsm_q;
    s_err_code_d = s_err_code_q;
    unique case (s_fsm_q)
      FSM_CMD: begin
        if (s_cmd_hdshk) begin
          if (rib.cmd_len != `RIB_LEN_INCR1) begin
            s_err_code_d = `RIB_RESP_BURSTERR;
            s_fsm_d      = rib.cmd_write ? FSM_DROP_WDATA : FSM_ERR;
          end else if (!s_psel_valid) begin
            s_err_code_d = `RIB_RESP_DECERR;
            s_fsm_d      = rib.cmd_write ? FSM_DROP_WDATA : FSM_ERR;
          end else begin
            s_fsm_d = rib.cmd_write ? FSM_WDATA : FSM_SETP;
          end
        end
      end
      FSM_WDATA: begin
        if (s_w_hdshk) begin
          if (rib.wlast) begin
            s_fsm_d = FSM_SETP;
          end else begin
            s_err_code_d = `RIB_RESP_BURSTERR;
            s_fsm_d      = FSM_ERR;
          end
        end
      end
      FSM_SETP: s_fsm_d = FSM_ENAB;
      FSM_ENAB: begin
        if (s_xfer_ready && s_rsp_input_ready) s_fsm_d = FSM_CMD;
      end
      FSM_DROP_WDATA: begin
        if (s_w_hdshk && rib.wlast) s_fsm_d = FSM_ERR;
      end
      FSM_ERR: begin
        if (s_rsp_hdshk) s_fsm_d = FSM_CMD;
      end
      default:  s_fsm_d = FSM_CMD;
    endcase
  end

  dffr #(
      .DATA_WIDTH(3)
  ) u_fsm_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_fsm_d),
      .dat_o  (s_fsm_q)
  );
  dffer #(
      .DATA_WIDTH(32)
  ) u_addr_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_cmd_hdshk),
      .dat_i  (rib.cmd_addr),
      .dat_o  (s_addr_q)
  );
  dffer #(
      .DATA_WIDTH(1)
  ) u_write_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_cmd_hdshk),
      .dat_i  (rib.cmd_write),
      .dat_o  (s_write_q)
  );
  dffer #(
      .DATA_WIDTH(32)
  ) u_wdata_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_w_hdshk && (s_fsm_q == FSM_WDATA)),
      .dat_i  (rib.wdata),
      .dat_o  (s_wdata_q)
  );
  dffer #(
      .DATA_WIDTH(4)
  ) u_wstrb_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_w_hdshk && (s_fsm_q == FSM_WDATA)),
      .dat_i  (rib.wstrb),
      .dat_o  (s_wstrb_q)
  );
  dffr #(
      .DATA_WIDTH(3)
  ) u_error_code_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_err_code_d),
      .dat_o  (s_err_code_q)
  );
  dffr #(
      .DATA_WIDTH(NSLV)
  ) u_psel_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_cmd_hdshk ? s_psel_comb : s_psel_q),
      .dat_o  (s_psel_q)
  );

endmodule
