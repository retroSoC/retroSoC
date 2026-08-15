// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

module ribp_regslice (
    // verilog_format: off -- preserve reviewed column alignment
    input logic    clk_i,
    input logic    rst_n_i,
    ribp_if.slave  ribp_slv,
    ribp_if.master ribp_mst
    // verilog_format: on
);

  // One RIBP request is buffered until its response returns; backpressure is
  // applied while it is outstanding, and response error/data are replayed.
  typedef enum logic [1:0] {
    Idle     = 2'd0,
    Request  = 2'd1,
    Response = 2'd2
  } regslice_state_e;

  regslice_state_e s_fsm_d, s_fsm_q;
  logic s_ribp_mst_valid_d, s_ribp_mst_valid_q;
  logic [31:0] s_ribp_mst_addr_d, s_ribp_mst_addr_q;
  logic [31:0] s_ribp_mst_wdata_d, s_ribp_mst_wdata_q;
  logic [3:0] s_ribp_mst_wstrb_d, s_ribp_mst_wstrb_q;
  logic [31:0] s_ribp_mst_rdata_d, s_ribp_mst_rdata_q;
  logic s_ribp_mst_ready_d, s_ribp_mst_ready_q;
  logic s_ribp_mst_resp_err_d, s_ribp_mst_resp_err_q;
  // ribp mst if
  assign ribp_mst.valid = s_ribp_mst_valid_q;
  assign ribp_mst.addr  = s_ribp_mst_addr_q;
  assign ribp_mst.wdata = s_ribp_mst_wdata_q;
  assign ribp_mst.wstrb = s_ribp_mst_wstrb_q;


  always_comb begin
    s_fsm_d               = s_fsm_q;
    s_ribp_mst_valid_d    = s_ribp_mst_valid_q;
    s_ribp_mst_addr_d     = s_ribp_mst_addr_q;
    s_ribp_mst_wdata_d    = s_ribp_mst_wdata_q;
    s_ribp_mst_wstrb_d    = s_ribp_mst_wstrb_q;
    s_ribp_mst_ready_d    = s_ribp_mst_ready_q;
    s_ribp_mst_rdata_d    = s_ribp_mst_rdata_q;
    s_ribp_mst_resp_err_d = s_ribp_mst_resp_err_q;
    ribp_slv.ready        = '0;
    ribp_slv.rdata        = '0;
    ribp_slv.resp_err     = 1'b0;
    unique case (s_fsm_q)
      Idle: begin
        if (ribp_slv.valid) begin
          s_fsm_d            = Request;
          s_ribp_mst_valid_d = ribp_slv.valid;
          s_ribp_mst_addr_d  = ribp_slv.addr;
          s_ribp_mst_wdata_d = ribp_slv.wdata;
          s_ribp_mst_wstrb_d = ribp_slv.wstrb;
        end
      end
      Request: begin
        if (ribp_mst.ready) begin
          s_fsm_d               = Response;
          s_ribp_mst_valid_d    = 1'b0;
          s_ribp_mst_ready_d    = ribp_mst.ready;
          s_ribp_mst_rdata_d    = ribp_mst.rdata;
          s_ribp_mst_resp_err_d = ribp_mst.resp_err;
        end
      end
      Response: begin
        s_fsm_d           = Idle;
        ribp_slv.ready    = s_ribp_mst_ready_q;
        ribp_slv.rdata    = s_ribp_mst_rdata_q;
        ribp_slv.resp_err = s_ribp_mst_resp_err_q;
      end
      default: begin
        s_fsm_d               = s_fsm_q;
        s_ribp_mst_valid_d    = s_ribp_mst_valid_q;
        s_ribp_mst_addr_d     = s_ribp_mst_addr_q;
        s_ribp_mst_wdata_d    = s_ribp_mst_wdata_q;
        s_ribp_mst_wstrb_d    = s_ribp_mst_wstrb_q;
        s_ribp_mst_ready_d    = s_ribp_mst_ready_q;
        s_ribp_mst_rdata_d    = s_ribp_mst_rdata_q;
        s_ribp_mst_resp_err_d = s_ribp_mst_resp_err_q;
        ribp_slv.ready        = '0;
        ribp_slv.rdata        = '0;
        ribp_slv.resp_err     = 1'b0;
      end
    endcase
  end
  dffr #(
      .DATA_WIDTH(2)
  ) u_fsm_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_fsm_d),
      .dat_o  (s_fsm_q)
  );

  dffr #(
      .DATA_WIDTH(1)
  ) u_ribp_mstr_valid_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_ribp_mst_valid_d),
      .dat_o  (s_ribp_mst_valid_q)
  );


  dffr #(
      .DATA_WIDTH(32)
  ) u_ribp_mst_addr_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_ribp_mst_addr_d),
      .dat_o  (s_ribp_mst_addr_q)
  );


  dffr #(
      .DATA_WIDTH(32)
  ) u_ribp_mst_wdata_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_ribp_mst_wdata_d),
      .dat_o  (s_ribp_mst_wdata_q)
  );


  dffr #(
      .DATA_WIDTH(4)
  ) u_ribp_mst_wstrb_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_ribp_mst_wstrb_d),
      .dat_o  (s_ribp_mst_wstrb_q)
  );

  dffr #(
      .DATA_WIDTH(32)
  ) u_ribp_mst_rdata_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_ribp_mst_rdata_d),
      .dat_o  (s_ribp_mst_rdata_q)
  );

  dffr #(
      .DATA_WIDTH(1)
  ) u_ribp_mst_ready_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_ribp_mst_ready_d),
      .dat_o  (s_ribp_mst_ready_q)
  );

  dffr #(
      .DATA_WIDTH(1)
  ) u_ribp_mst_resp_err_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_ribp_mst_resp_err_d),
      .dat_o  (s_ribp_mst_resp_err_q)
  );

endmodule
