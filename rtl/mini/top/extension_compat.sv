// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

module extension_compat (
    input logic         clk_i,
    input logic         rst_n_i,
          apb4_if.slave apb4
);
  logic        s_ready_d;
  logic        s_ready_q;
  logic        s_resp_err_d;
  logic        s_resp_err_q;
  logic [31:0] s_rdata_d;
  logic [31:0] s_rdata_q;
  logic        s_req_accept;

  assign s_req_accept = apb4.psel && apb4.penable && !s_ready_q;
  assign s_ready_d = s_req_accept;
  assign s_resp_err_d = s_req_accept && (|apb4.pstrb);
  assign s_rdata_d = (apb4.paddr[11:0] == 12'h000) ? 32'h4558_5443 :
                   (apb4.paddr[11:0] == 12'h004) ? 32'h0001_0000 :
                   (apb4.paddr[11:0] == 12'h008) ? 32'h0000_0201 : 32'd0;
  assign apb4.pready = s_ready_q;
  assign apb4.pslverr = s_resp_err_q;
  assign apb4.prdata = s_rdata_q;

  dffr #(
      .DATA_WIDTH(1)
  ) u_ready_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_ready_d),
      .dat_o  (s_ready_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_resp_err_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_resp_err_d),
      .dat_o  (s_resp_err_q)
  );
  dffer #(
      .DATA_WIDTH(32)
  ) u_rdata_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_req_accept && !(|apb4.pstrb)),
      .dat_i  (s_rdata_d),
      .dat_o  (s_rdata_q)
  );
endmodule
