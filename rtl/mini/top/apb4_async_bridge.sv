// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

module apb4_async_bridge (
    input logic          src_clk_i,
    input logic          src_rst_n_i,
    input logic          dst_clk_i,
    input logic          dst_rst_n_i,
          apb4_if.slave  src_apb4,
          apb4_if.master dst_apb4
);
  localparam int unsigned RequestWidth = 72;
  localparam int unsigned ResponseWidth = 33;

  typedef enum logic [1:0] {
    Idle,
    Setup,
    Access,
    Respond
  } state_e;

  logic   [ RequestWidth-1:0] s_src_req_data_d;
  logic   [ RequestWidth-1:0] s_src_req_data_q;
  logic                       s_src_pending_d;
  logic                       s_src_pending_q;
  logic                       s_src_sent_d;
  logic                       s_src_sent_q;
  logic                       s_src_req_ready;
  logic   [ RequestWidth-1:0] s_dst_req_data;
  logic                       s_dst_req_valid;
  logic                       s_dst_req_ready;
  logic   [ResponseWidth-1:0] s_dst_rsp_data;
  logic                       s_dst_rsp_valid;
  logic                       s_dst_rsp_ready;
  logic   [ResponseWidth-1:0] s_src_rsp_data;
  logic                       s_src_rsp_valid;
  logic                       s_src_rsp_ready;
  logic   [ RequestWidth-1:0] s_req_d;
  logic   [ RequestWidth-1:0] s_req_q;
  logic   [ResponseWidth-1:0] s_rsp_d;
  logic   [ResponseWidth-1:0] s_rsp_q;
  logic                       s_rsp_pending_d;
  logic                       s_rsp_pending_q;
  state_e                     s_state_d;
  state_e                     s_state_q;
  logic   [              1:0] s_state_bits_q;
  logic                       s_src_accept;

  assign s_state_q        = state_e'(s_state_bits_q);
  assign s_src_accept     = src_apb4.psel && src_apb4.penable && !s_src_pending_q;
  assign src_apb4.pready  = s_src_rsp_valid;
  assign src_apb4.prdata  = s_src_rsp_data[31:0];
  assign src_apb4.pslverr = s_src_rsp_data[32];
  assign s_src_rsp_ready  = src_apb4.psel && src_apb4.penable;

  always_comb begin
    s_src_req_data_d = s_src_req_data_q;
    s_src_pending_d  = s_src_pending_q;
    s_src_sent_d     = s_src_sent_q;
    if (s_src_accept) begin
      s_src_req_data_d = {
        src_apb4.paddr, src_apb4.pprot, src_apb4.pwrite, src_apb4.pwdata, src_apb4.pstrb
      };
      s_src_pending_d = 1'b1;
      s_src_sent_d = 1'b0;
    end
    if (s_src_pending_q && !s_src_sent_q && s_src_req_ready) begin
      s_src_sent_d = 1'b1;
    end
    if (s_src_rsp_valid && s_src_rsp_ready) begin
      s_src_pending_d = 1'b0;
      s_src_sent_d    = 1'b0;
    end
  end

  cdc_2phase #(
      .DATA_WIDTH(RequestWidth)
  ) u_req_cdc (
      .src_clk_i  (src_clk_i),
      .src_rst_n_i(src_rst_n_i),
      .src_data_i (s_src_req_data_q),
      .src_valid_i(s_src_pending_q && !s_src_sent_q),
      .src_ready_o(s_src_req_ready),
      .dst_clk_i  (dst_clk_i),
      .dst_rst_n_i(dst_rst_n_i),
      .dst_data_o (s_dst_req_data),
      .dst_valid_o(s_dst_req_valid),
      .dst_ready_i(s_dst_req_ready)
  );

  cdc_2phase #(
      .DATA_WIDTH(ResponseWidth)
  ) u_rsp_cdc (
      .src_clk_i  (dst_clk_i),
      .src_rst_n_i(dst_rst_n_i),
      .src_data_i (s_dst_rsp_data),
      .src_valid_i(s_dst_rsp_valid),
      .src_ready_o(s_dst_rsp_ready),
      .dst_clk_i  (src_clk_i),
      .dst_rst_n_i(src_rst_n_i),
      .dst_data_o (s_src_rsp_data),
      .dst_valid_o(s_src_rsp_valid),
      .dst_ready_i(s_src_rsp_ready)
  );

  assign s_dst_req_ready = s_state_q == Idle;
  assign s_dst_rsp_data = s_rsp_q;
  assign s_dst_rsp_valid = s_rsp_pending_q;
  assign {
    dst_apb4.paddr,
    dst_apb4.pprot,
    dst_apb4.pwrite,
    dst_apb4.pwdata,
    dst_apb4.pstrb
  } = s_req_q;
  assign dst_apb4.psel = (s_state_q == Setup) || (s_state_q == Access);
  assign dst_apb4.penable = s_state_q == Access;

  always_comb begin
    s_state_d       = s_state_q;
    s_req_d         = s_req_q;
    s_rsp_d         = s_rsp_q;
    s_rsp_pending_d = s_rsp_pending_q;
    unique case (s_state_q)
      Idle: begin
        if (s_dst_req_valid) begin
          s_req_d   = s_dst_req_data;
          s_state_d = Setup;
        end
      end
      Setup:   s_state_d = Access;
      Access: begin
        if (dst_apb4.pready) begin
          s_rsp_d         = {dst_apb4.pslverr, dst_apb4.prdata};
          s_rsp_pending_d = 1'b1;
          s_state_d       = Respond;
        end
      end
      Respond: begin
        if (s_rsp_pending_q && s_dst_rsp_ready) begin
          s_rsp_pending_d = 1'b0;
          s_state_d       = Idle;
        end
      end
      default: s_state_d = Idle;
    endcase
  end

  dffr #(
      .DATA_WIDTH(RequestWidth)
  ) u_src_req_data_dffr (
      .clk_i  (src_clk_i),
      .rst_n_i(src_rst_n_i),
      .dat_i  (s_src_req_data_d),
      .dat_o  (s_src_req_data_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_src_pending_dffr (
      .clk_i  (src_clk_i),
      .rst_n_i(src_rst_n_i),
      .dat_i  (s_src_pending_d),
      .dat_o  (s_src_pending_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_src_sent_dffr (
      .clk_i  (src_clk_i),
      .rst_n_i(src_rst_n_i),
      .dat_i  (s_src_sent_d),
      .dat_o  (s_src_sent_q)
  );
  dffrc #(
      .DATA_WIDTH(2),
      .RESET_VAL (Idle)
  ) u_state_dffrc (
      .clk_i  (dst_clk_i),
      .rst_n_i(dst_rst_n_i),
      .dat_i  (s_state_d),
      .dat_o  (s_state_bits_q)
  );
  dffr #(
      .DATA_WIDTH(RequestWidth)
  ) u_req_dffr (
      .clk_i  (dst_clk_i),
      .rst_n_i(dst_rst_n_i),
      .dat_i  (s_req_d),
      .dat_o  (s_req_q)
  );
  dffr #(
      .DATA_WIDTH(ResponseWidth)
  ) u_rsp_dffr (
      .clk_i  (dst_clk_i),
      .rst_n_i(dst_rst_n_i),
      .dat_i  (s_rsp_d),
      .dat_o  (s_rsp_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_rsp_pending_dffr (
      .clk_i  (dst_clk_i),
      .rst_n_i(dst_rst_n_i),
      .dat_i  (s_rsp_pending_d),
      .dat_o  (s_rsp_pending_q)
  );
endmodule
