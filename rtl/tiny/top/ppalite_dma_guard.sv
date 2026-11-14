// Copyright (c) 2026 Yuchi Miao
// SPDX-License-Identifier: MulanPSL-2.0
`include "dma_define.svh"
`include "ppalite_define.svh"

module ppalite_dma_guard #(
    parameter int NumChannels   = 8,
    parameter int MaxBurstBeats = 4
) (
    input  logic                 clk_i,
    input  logic                 rst_n_i,
           apb4_if.slave         host_apb4,
           apb4_if.master        dma_apb4,
    input  logic                 route_i,
    input  logic          [ 2:0] capture_state_i,
    input  logic                 capture_arm_request_i,
    input  logic                 capture_release_i,
    input  logic                 capture_close_i,
    input  logic          [31:0] job_destination_i,
    input  logic          [31:0] job_transport_bytes_i,
    input  logic                 dma_rst_n_i,
    input  logic                 dma_ready_i,
    input  logic                 dma_start_pending_i,
    input  logic                 dma_busy_i,
    input  logic                 dma_done_i,
    input  logic          [31:0] dma_bytes_done_i,
    input  logic          [31:0] dma_error_status_i,
    output logic                 dma_start_o,
    output logic                 transport_ready_o,
    output logic                 transport_idle_o,
    output logic                 transport_admitted_o,
    output logic                 transport_done_o,
    output logic          [ 7:0] transport_err_o,
    output logic                 stream_isolated_o
);
  logic [31:0] s_cfg_shadow_d, s_cfg_shadow_q;
  logic [31:0] s_src_shadow_d, s_src_shadow_q;
  logic [31:0] s_dst_shadow_d, s_dst_shadow_q;
  logic [31:0] s_len_shadow_d, s_len_shadow_q;
  logic [31:0] s_burst_shadow_d, s_burst_shadow_q;
  logic [31:0] s_tcd_head_shadow_d, s_tcd_head_shadow_q;
  logic [31:0] s_tcd_count_shadow_d, s_tcd_count_shadow_q;
  logic [NumChannels*32-1:0] s_req_shadow_d, s_req_shadow_q;
  logic s_token_d, s_token_q;
  logic s_reject_d, s_reject_q;
  logic s_legal_d, s_legal_q;
  logic        s_access;
  logic        s_write_access;
  logic [11:0] s_offset;
  logic [ 6:0] s_channel_offset;
  logic [ 2:0] s_channel_index;
  logic        s_channel_access;
  logic        s_channel2_access;
  logic        s_ctrl_access;
  logic        s_config_access;
  logic        s_tcd_access;
  logic        s_global_reset_access;
  logic        s_channel2_reset_accept;
  logic        s_forward_write;
  logic        s_start_accept;
  logic        s_job_req;
  logic        s_matching_start;
  logic        s_exact_shadow;
  logic        s_capture_owned;
  logic        s_closing;
  logic        s_access_forbidden;
  logic        s_access_reject;

  function automatic logic [31:0] merge_wstrb(
      input logic [31:0] current_i, input logic [31:0] value_i, input logic [3:0] strobe_i);
    logic [31:0] merged;
    begin
      merged = current_i;
      for (int index = 0; index < 4; index++) begin
        if (strobe_i[index]) merged[index*8+:8] = value_i[index*8+:8];
      end
      return merged;
    end
  endfunction

  assign s_access = host_apb4.psel && host_apb4.penable;
  assign s_write_access = s_access && (host_apb4.pwrite || (|host_apb4.pstrb));
  assign s_offset = host_apb4.paddr[11:0];
  assign s_channel_offset = s_offset[6:0];
  assign s_channel_access = ({20'd0, s_offset} >= {20'd0, `APB4_DMA__CH_BASE}) &&
      ({20'd0, s_offset} < ({20'd0, `APB4_DMA__CH_BASE} + (NumChannels * `APB4_DMA__CH_STRIDE)));
  assign s_channel_index = 3'(({20'd0, s_offset} - {20'd0, `APB4_DMA__CH_BASE}) >> 7);
  assign s_channel2_access = s_channel_access && (s_channel_index == 3'd2);
  assign s_ctrl_access = s_channel2_access && (s_channel_offset == `APB4_DMA__CH_CTRL);
  assign s_config_access = s_channel2_access &&
      ((s_channel_offset == `APB4_DMA__CH_CFG) ||
       (s_channel_offset == `APB4_DMA__CH_SRC_ADDR) ||
       (s_channel_offset == `APB4_DMA__CH_DST_ADDR) ||
       (s_channel_offset == `APB4_DMA__CH_BYTE_COUNT) ||
       (s_channel_offset == `APB4_DMA__CH_REQUEST_SEL) ||
       (s_channel_offset == `APB4_DMA__CH_BURST_CFG) ||
       (s_channel_offset == `APB4_DMA__CH_TCD_HEAD) ||
       (s_channel_offset == `APB4_DMA__CH_TCD_COUNT) ||
       (s_channel_offset == `APB4_DMA__CH_CRC_EXPECTED));
  assign s_tcd_access = s_channel2_access &&
      ((s_channel_offset == `APB4_DMA__CH_TCD_HEAD) ||
       (s_channel_offset == `APB4_DMA__CH_TCD_COUNT));
  assign s_global_reset_access = s_write_access &&
      (s_offset == `APB4_DMA__GLOBAL_CTRL) && host_apb4.pwdata[`APB4_DMA__GLOBAL_CTRL_RESET];
  assign s_job_req = s_channel_access && (s_req_shadow_q[s_channel_index*32+:32] == 32'd11);
  assign s_capture_owned = capture_state_i != `PPALITE_STATE_IDLE;
  assign s_closing = capture_state_i == `PPALITE_STATE_CLOSING;

  assign s_exact_shadow = (s_cfg_shadow_q[31:12] == 20'd0) &&
      (s_cfg_shadow_q[2:0] == 3'd2) && (s_cfg_shadow_q[5:4] == 2'd2) &&
      !s_cfg_shadow_q[6] && s_cfg_shadow_q[7] && (s_cfg_shadow_q[11:10] == 2'd0) &&
      (s_src_shadow_q == 32'd0) && (s_dst_shadow_q == job_destination_i) &&
      (s_len_shadow_q == job_transport_bytes_i) && (s_len_shadow_q != 32'd0) &&
      (s_len_shadow_q[1:0] == 2'd0) && (s_req_shadow_q[2*32+:32] == 32'd11) &&
      (s_burst_shadow_q[31:5] == 27'd0) && (s_burst_shadow_q[4:0] != 5'd0) &&
      (s_burst_shadow_q <= 32'(MaxBurstBeats)) &&
      (s_tcd_head_shadow_q == 32'd0) && (s_tcd_count_shadow_q == 32'd0);
  assign s_matching_start = s_write_access && s_ctrl_access &&
      (host_apb4.pwdata == 32'd1) && s_exact_shadow &&
      ((capture_state_i == `PPALITE_STATE_ARMED) || capture_arm_request_i) &&
      !capture_close_i && !s_token_q && !dma_busy_i && dma_ready_i;

  assign transport_ready_o = route_i && !s_capture_owned && s_exact_shadow && !s_token_q &&
      !dma_busy_i && !dma_start_pending_i && dma_rst_n_i && dma_ready_i &&
      (dma_error_status_i[7:0] == 8'd0);
  assign transport_idle_o = !dma_busy_i && dma_rst_n_i && dma_ready_i &&
      (!s_token_q || dma_done_i || (dma_error_status_i[7:0] != 8'd0));
  assign transport_admitted_o = s_token_q;
  assign transport_done_o = s_token_q && dma_done_i && !dma_busy_i && dma_ready_i &&
      (dma_bytes_done_i == job_transport_bytes_i) && (dma_error_status_i[7:0] == 8'd0);
  assign transport_err_o = (!dma_rst_n_i || !dma_ready_i) ? 8'h40 :
      (s_capture_owned ? dma_error_status_i[7:0] : 8'd0);
  assign stream_isolated_o = transport_idle_o;

  always_comb begin
    s_access_forbidden = 1'b0;
    if (route_i && s_write_access) begin
      if (s_global_reset_access && s_capture_owned) s_access_forbidden = 1'b1;
      if (s_config_access && (s_capture_owned || capture_arm_request_i)) begin
        s_access_forbidden = 1'b1;
      end
      if (s_tcd_access && (host_apb4.pwdata != 32'd0)) s_access_forbidden = 1'b1;
      if ((s_config_access || s_ctrl_access || s_global_reset_access) &&
          (!host_apb4.pwrite || !(|host_apb4.pstrb))) begin
        s_access_forbidden = 1'b1;
      end
      if (s_channel_access && (s_channel_offset == `APB4_DMA__CH_CTRL) &&
          host_apb4.pwdata[`APB4_DMA__CH_CTRL_START]) begin
        if (!s_channel2_access) begin
          if (s_job_req) s_access_forbidden = 1'b1;
        end else if (!s_matching_start && (s_capture_owned || s_job_req ||
                                          capture_arm_request_i || s_token_q)) begin
          s_access_forbidden = 1'b1;
        end
      end
      if (s_ctrl_access && (s_capture_owned || s_job_req || s_token_q)) begin
        if (host_apb4.pwdata[`APB4_DMA__CH_CTRL_ABORT] &&
            !(s_closing || (s_token_q && !s_capture_owned))) begin
          s_access_forbidden = 1'b1;
        end
        if (host_apb4.pwdata[`APB4_DMA__CH_CTRL_RESET] &&
            !((s_closing || !s_capture_owned) && !dma_busy_i && dma_rst_n_i && dma_ready_i)) begin
          s_access_forbidden = 1'b1;
        end
        if ((host_apb4.pwdata[31:5] != 27'd0) || (host_apb4.pwdata[2:1] != 2'd0)) begin
          s_access_forbidden = 1'b1;
        end
      end
    end
  end

  assign s_access_reject = s_access_forbidden && !s_legal_q;
  always_comb begin
    dma_apb4.paddr    = host_apb4.paddr;
    dma_apb4.pprot    = host_apb4.pprot;
    dma_apb4.psel     = host_apb4.psel && !s_access_reject && !s_reject_q;
    dma_apb4.penable  = host_apb4.penable;
    dma_apb4.pwrite   = host_apb4.pwrite;
    dma_apb4.pwdata   = host_apb4.pwdata;
    dma_apb4.pstrb    = host_apb4.pstrb;
    host_apb4.pready  = s_reject_q ? 1'b1 : (s_access_reject ? 1'b0 : dma_apb4.pready);
    host_apb4.prdata  = s_reject_q ? 32'd0 : dma_apb4.prdata;
    host_apb4.pslverr = s_reject_q ? 1'b1 : dma_apb4.pslverr;
  end

  assign s_forward_write = dma_apb4.psel && dma_apb4.penable && dma_apb4.pwrite &&
      dma_apb4.pready && !dma_apb4.pslverr;
  assign s_start_accept = s_forward_write && s_matching_start;
  assign s_channel2_reset_accept = s_forward_write && s_ctrl_access &&
      host_apb4.pwdata[`APB4_DMA__CH_CTRL_RESET];
  assign dma_start_o = s_forward_write && s_channel_access &&
      (s_channel_offset == `APB4_DMA__CH_CTRL) && host_apb4.pwdata[`APB4_DMA__CH_CTRL_START];

  always_comb begin
    s_reject_d = s_reject_q;
    if (s_reject_q && host_apb4.pready) begin
      s_reject_d = 1'b0;
    end else if (s_access && s_access_reject) begin
      s_reject_d = 1'b1;
    end else if (!host_apb4.psel) begin
      s_reject_d = 1'b0;
    end
  end
  dffr #(1) u_reject_reg (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_reject_d),
      .dat_o  (s_reject_q)
  );

  always_comb begin
    s_legal_d = s_legal_q;
    if (s_write_access && !s_access_forbidden && !s_reject_q && !s_legal_q) begin
      s_legal_d = 1'b1;
    end else if (!host_apb4.psel || dma_apb4.pready) begin
      s_legal_d = 1'b0;
    end
  end
  dffr #(1) u_legal_reg (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_legal_d),
      .dat_o  (s_legal_q)
  );

  always_comb begin
    s_token_d = s_token_q;
    if (!route_i || capture_release_i || s_channel2_reset_accept ||
        (s_forward_write && (s_offset == `APB4_DMA__GLOBAL_CTRL) &&
         host_apb4.pwdata[`APB4_DMA__GLOBAL_CTRL_RESET])) begin
      s_token_d = 1'b0;
    end else if (s_start_accept) begin
      s_token_d = 1'b1;
    end
  end
  dffr #(1) u_token_reg (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_token_d),
      .dat_o  (s_token_q)
  );

  always_comb begin
    s_cfg_shadow_d       = s_cfg_shadow_q;
    s_src_shadow_d       = s_src_shadow_q;
    s_dst_shadow_d       = s_dst_shadow_q;
    s_len_shadow_d       = s_len_shadow_q;
    s_burst_shadow_d     = s_burst_shadow_q;
    s_tcd_head_shadow_d  = s_tcd_head_shadow_q;
    s_tcd_count_shadow_d = s_tcd_count_shadow_q;
    s_req_shadow_d       = s_req_shadow_q;
    if (!dma_rst_n_i) begin
      s_cfg_shadow_d       = 32'd0;
      s_src_shadow_d       = 32'd0;
      s_dst_shadow_d       = 32'd0;
      s_len_shadow_d       = 32'd0;
      s_burst_shadow_d     = 32'd0;
      s_tcd_head_shadow_d  = 32'd0;
      s_tcd_count_shadow_d = 32'd0;
      s_req_shadow_d       = '0;
    end else if (s_forward_write && (s_offset == `APB4_DMA__GLOBAL_CTRL) &&
        host_apb4.pwdata[`APB4_DMA__GLOBAL_CTRL_RESET]) begin
      s_cfg_shadow_d       = 32'd0;
      s_src_shadow_d       = 32'd0;
      s_dst_shadow_d       = 32'd0;
      s_len_shadow_d       = 32'd0;
      s_burst_shadow_d     = 32'd0;
      s_tcd_head_shadow_d  = 32'd0;
      s_tcd_count_shadow_d = 32'd0;
      s_req_shadow_d       = '0;
    end else if (s_forward_write && s_channel_access) begin
      unique case (s_channel_offset)
        `APB4_DMA__CH_REQUEST_SEL:
        s_req_shadow_d[s_channel_index*32+:32] =
            merge_wstrb(s_req_shadow_q[s_channel_index*32+:32], host_apb4.pwdata, host_apb4.pstrb);
        default: begin
        end
      endcase
      if (s_channel2_access) begin
        unique case (s_channel_offset)
          `APB4_DMA__CH_CFG:
          s_cfg_shadow_d = merge_wstrb(s_cfg_shadow_q, host_apb4.pwdata, host_apb4.pstrb);
          `APB4_DMA__CH_SRC_ADDR:
          s_src_shadow_d = merge_wstrb(s_src_shadow_q, host_apb4.pwdata, host_apb4.pstrb);
          `APB4_DMA__CH_DST_ADDR:
          s_dst_shadow_d = merge_wstrb(s_dst_shadow_q, host_apb4.pwdata, host_apb4.pstrb);
          `APB4_DMA__CH_BYTE_COUNT:
          s_len_shadow_d = merge_wstrb(s_len_shadow_q, host_apb4.pwdata, host_apb4.pstrb);
          `APB4_DMA__CH_BURST_CFG:
          s_burst_shadow_d = merge_wstrb(s_burst_shadow_q, host_apb4.pwdata, host_apb4.pstrb);
          `APB4_DMA__CH_TCD_HEAD:
          s_tcd_head_shadow_d = merge_wstrb(s_tcd_head_shadow_q, host_apb4.pwdata, host_apb4.pstrb);
          `APB4_DMA__CH_TCD_COUNT:
          s_tcd_count_shadow_d =
              merge_wstrb(s_tcd_count_shadow_q, host_apb4.pwdata, host_apb4.pstrb);
          default: begin
          end
        endcase
      end
    end
  end
  dffr #($bits(
      {
        s_cfg_shadow_q,
        s_src_shadow_q,
        s_dst_shadow_q,
        s_len_shadow_q,
        s_burst_shadow_q,
        s_tcd_head_shadow_q,
        s_tcd_count_shadow_q,
        s_req_shadow_q
      }
  )) u_shadow_reg (
      .clk_i(clk_i),
      .rst_n_i(rst_n_i),
      .dat_i({
        s_cfg_shadow_d,
        s_src_shadow_d,
        s_dst_shadow_d,
        s_len_shadow_d,
        s_burst_shadow_d,
        s_tcd_head_shadow_d,
        s_tcd_count_shadow_d,
        s_req_shadow_d
      }),
      .dat_o({
        s_cfg_shadow_q,
        s_src_shadow_q,
        s_dst_shadow_q,
        s_len_shadow_q,
        s_burst_shadow_q,
        s_tcd_head_shadow_q,
        s_tcd_count_shadow_q,
        s_req_shadow_q
      })
  );

`ifdef FORMAL
  logic s_formal_past_q;
  always_ff @(posedge clk_i) begin
    if (!rst_n_i) begin
      s_formal_past_q <= 1'b0;
    end else begin
      s_formal_past_q <= 1'b1;
      if (transport_done_o) begin
        assert (s_token_q && dma_done_i && !dma_busy_i);
        assert (dma_bytes_done_i == job_transport_bytes_i);
      end
      if (s_start_accept) begin
        assert (s_channel2_access && s_exact_shadow && !s_token_q);
        assert ((capture_state_i == `PPALITE_STATE_ARMED) || capture_arm_request_i);
      end
      if (s_forward_write && s_config_access) begin
        assert ((!s_capture_owned && !capture_arm_request_i) || !route_i);
      end
      if (s_formal_past_q && $past(s_start_accept)) assert (s_token_q);
      if (s_reject_q) assert (host_apb4.pready && host_apb4.pslverr && !dma_apb4.psel);
      if (!route_i) begin
        assert (dma_apb4.paddr == host_apb4.paddr);
        assert (dma_apb4.psel == host_apb4.psel);
      end
      if (s_formal_past_q && $past(!route_i)) assert (!s_token_q);
    end
  end
`endif
endmodule
