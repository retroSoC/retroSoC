// Copyright (c) 2026 Yuchi Miao
// SPDX-License-Identifier: MulanPSL-2.0

// One outstanding SYS control request. Either endpoint reset flushes both
// mailboxes. A destination reset aborts the accepted source transfer with an
// error; it never replays it when the destination returns. The SYS endpoint
// remains clocked so a stopped/disabled peripheral is still reachable.
module tiny_apb_async_bridge (
    input  logic                src_clk_i,
    input  logic                src_rst_n_i,
    input  logic                dst_clk_i,
    input  logic                dst_rst_n_i,
    input  logic                disabled_i,
    input  logic          [1:0] src_origin_i,
    input  logic          [2:0] src_channel_i,
    output logic                idle_o,
    output logic                ready_o,
    output logic          [1:0] dst_origin_o,
    output logic          [2:0] dst_channel_o,
           apb4_if.slave        src_apb4,
           apb4_if.master       dst_apb4
);
  typedef enum logic [1:0] {
    SrcIdle,
    SrcSend,
    SrcWait,
    SrcResponse
  } src_state_e;
  typedef enum logic [1:0] {
    DstIdle,
    DstSetup,
    DstAccess,
    DstResponse
  } dst_state_e;
  typedef struct packed {
    src_state_e  state;
    logic [76:0] req;
    logic [32:0] resp;
  } src_t;
  typedef struct packed {
    dst_state_e  state;
    logic [76:0] req;
    logic [32:0] resp;
  } dst_t;
  src_t s_src_d, s_src_q;
  dst_t s_dst_d, s_dst_q;
  logic s_link_src_rst_n, s_link_dst_rst_n;
  logic s_req_ready, s_req_valid, s_resp_ready, s_resp_valid;
  logic [76:0] s_req_data;
  logic [32:0] s_resp_data;

  cdc_reset_barrier #(
      .STAGES(5)
  ) u_barrier (
      .clk_a_i  (src_clk_i),
      .clk_b_i  (dst_clk_i),
      .rst_n_i  (src_rst_n_i && dst_rst_n_i),
      .release_i(1'b1),
      .rst_a_n_o(s_link_src_rst_n),
      .rst_b_n_o(s_link_dst_rst_n)
  );
  cdc_2phase #(
      .DATA_WIDTH(77)
  ) u_req_cdc (
      .src_clk_i  (src_clk_i),
      .src_rst_n_i(s_link_src_rst_n),
      .src_data_i (s_src_q.req),
      .src_valid_i(s_src_q.state == SrcSend),
      .src_ready_o(s_req_ready),
      .dst_clk_i  (dst_clk_i),
      .dst_rst_n_i(s_link_dst_rst_n),
      .dst_data_o (s_req_data),
      .dst_valid_o(s_req_valid),
      .dst_ready_i(s_dst_q.state == DstIdle)
  );
  cdc_2phase #(
      .DATA_WIDTH(33)
  ) u_resp_cdc (
      .src_clk_i  (dst_clk_i),
      .src_rst_n_i(s_link_dst_rst_n),
      .src_data_i (s_dst_q.resp),
      .src_valid_i(s_dst_q.state == DstResponse),
      .src_ready_o(s_resp_ready),
      .dst_clk_i  (src_clk_i),
      .dst_rst_n_i(s_link_src_rst_n),
      .dst_data_o (s_resp_data),
      .dst_valid_o(s_resp_valid),
      .dst_ready_i(s_src_q.state == SrcWait)
  );
  assign ready_o = s_link_src_rst_n && s_req_ready;
  assign idle_o = (s_src_q.state == SrcIdle) && s_req_ready && !s_resp_valid;
  assign src_apb4.pready = s_src_q.state == SrcResponse;
  assign src_apb4.pslverr = s_src_q.resp[32];
  assign src_apb4.prdata = s_src_q.resp[31:0];
  assign {dst_apb4.paddr, dst_apb4.pprot, dst_apb4.pwrite,
          dst_apb4.pwdata, dst_apb4.pstrb} = s_dst_q.req[71:0];
  assign dst_apb4.psel = s_link_dst_rst_n &&
      ((s_dst_q.state == DstSetup) || (s_dst_q.state == DstAccess));
  assign dst_apb4.penable = s_link_dst_rst_n && (s_dst_q.state == DstAccess);
  assign dst_origin_o = s_dst_q.req[76:75];
  assign dst_channel_o = s_dst_q.req[74:72];

  always_comb begin
    s_src_d = s_src_q;
    unique case (s_src_q.state)
      SrcIdle:
      if (src_apb4.psel && src_apb4.penable) begin
        s_src_d.req = {
          src_origin_i,
          src_channel_i,
          src_apb4.paddr,
          src_apb4.pprot,
          src_apb4.pwrite,
          src_apb4.pwdata,
          src_apb4.pstrb
        };
        s_src_d.resp = {1'b1, 32'd0};
        s_src_d.state = disabled_i ? SrcResponse : SrcSend;
      end
      SrcSend:     if (s_req_ready) s_src_d.state = SrcWait;
      SrcWait:
      if (s_resp_valid) begin
        s_src_d.resp  = s_resp_data;
        s_src_d.state = SrcResponse;
      end
      SrcResponse: s_src_d.state = SrcIdle;
      default:     s_src_d.state = SrcIdle;
    endcase
    if (((s_src_q.state == SrcSend) || (s_src_q.state == SrcWait)) && !s_link_src_rst_n) begin
      s_src_d.resp  = {1'b1, 32'd0};
      s_src_d.state = SrcResponse;
    end
  end
  always_comb begin
    s_dst_d = s_dst_q;
    unique case (s_dst_q.state)
      DstIdle:
      if (s_req_valid) begin
        s_dst_d.req   = s_req_data;
        s_dst_d.state = DstSetup;
      end
      DstSetup:    s_dst_d.state = DstAccess;
      DstAccess:
      if (dst_apb4.pready) begin
        s_dst_d.resp  = {dst_apb4.pslverr, dst_apb4.prdata};
        s_dst_d.state = DstResponse;
      end
      DstResponse: if (s_resp_ready) s_dst_d.state = DstIdle;
      default:     s_dst_d.state = DstIdle;
    endcase
  end
  dffr #(
      .DATA_WIDTH($bits(src_t))
  ) u_src (
      .clk_i  (src_clk_i),
      .rst_n_i(src_rst_n_i),
      .dat_i  (s_src_d),
      .dat_o  (s_src_q)
  );
  dffr #(
      .DATA_WIDTH($bits(dst_t))
  ) u_dst (
      .clk_i  (dst_clk_i),
      .rst_n_i(s_link_dst_rst_n),
      .dat_i  (s_dst_d),
      .dat_o  (s_dst_q)
  );
endmodule
