// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

module apu_stream_router #(
    parameter int unsigned FifoDepth = 64
) (
    // verilog_format: off -- preserve stream direction columns
    input  logic                   clk_i,
    input  logic                   rst_n_i,
    input  logic                   flush_i,
    input  logic                   counter_clear_i,
    input  logic                   xrun_clear_i,
    input  logic                   tx_route_apu_i,
    input  logic                   rx_route_apu_i,
    input  logic                   tx_session_active_i,
    input  logic                   rx_session_active_i,
    input  logic [7:0]             rx_high_watermark_i,
    input  logic [7:0]             tx_low_watermark_i,
    input  logic                   tx_underrun_i,
    input  logic                   rx_overrun_i,
    axi4_stream_if.sink            dma_tx_axis,
    axi4_stream_if.source          dma_rx_axis,
    axi4_stream_if.source          i2s_tx_axis,
    axi4_stream_if.sink            i2s_rx_axis,
    axi4_stream_if.sink            apu_tx_axis,
    axi4_stream_if.source          apu_rx_axis,
    output logic [31:0]            status_o,
    output logic                   input_watermark_evt_o,
    output logic                   output_watermark_evt_o,
    output logic                   stream_xrun_evt_o,
    output logic                   idle_o
    // verilog_format: on
);
  localparam int unsigned PayloadWidth = 44;
  localparam int unsigned CountWidth = $clog2(FifoDepth) + 1;

  logic [PayloadWidth-1:0] s_tx_push_data;
  logic [PayloadWidth-1:0] s_tx_pop_data;
  logic [PayloadWidth-1:0] s_rx_push_data;
  logic [PayloadWidth-1:0] s_rx_pop_data;
  logic [  CountWidth-1:0] s_tx_count;
  logic [  CountWidth-1:0] s_rx_count;
  logic s_tx_full, s_tx_empty, s_rx_full, s_rx_empty;
  logic s_tx_push, s_tx_pop, s_rx_push, s_rx_pop;
  logic s_tx_active, s_rx_active;
  logic s_tx_low_armed_q, s_rx_high_armed_q;
  logic s_tx_underrun_q, s_rx_overrun_q;
  logic [7:0] s_tx_words_q, s_rx_words_q;
  logic [CountWidth-1:0] s_tx_count_after;
  logic [CountWidth-1:0] s_rx_count_after;

  function automatic logic [7:0] saturating_increment(input logic [7:0] value_i);
    return (&value_i) ? value_i : value_i + 1'b1;
  endfunction

  assign s_tx_push_data = {
    apu_tx_axis.tuser,
    apu_tx_axis.tdest,
    apu_tx_axis.tid,
    apu_tx_axis.tlast,
    apu_tx_axis.tstrb,
    apu_tx_axis.tkeep,
    apu_tx_axis.tdata
  };
  assign s_rx_push_data = {
    i2s_rx_axis.tuser,
    i2s_rx_axis.tdest,
    i2s_rx_axis.tid,
    i2s_rx_axis.tlast,
    i2s_rx_axis.tstrb,
    i2s_rx_axis.tkeep,
    i2s_rx_axis.tdata
  };
  assign s_tx_push = apu_tx_axis.tvalid && apu_tx_axis.tready;
  assign s_tx_pop = tx_route_apu_i && i2s_tx_axis.tvalid && i2s_tx_axis.tready;
  assign s_rx_push = rx_route_apu_i && i2s_rx_axis.tvalid && i2s_rx_axis.tready;
  assign s_rx_pop = apu_rx_axis.tvalid && apu_rx_axis.tready;
  assign apu_tx_axis.tready = !s_tx_full;

  assign i2s_tx_axis.tdata = tx_route_apu_i ? s_tx_pop_data[31:0] : dma_tx_axis.tdata;
  assign i2s_tx_axis.tkeep = tx_route_apu_i ? s_tx_pop_data[35:32] : dma_tx_axis.tkeep;
  assign i2s_tx_axis.tstrb = tx_route_apu_i ? s_tx_pop_data[39:36] : dma_tx_axis.tstrb;
  assign i2s_tx_axis.tlast = tx_route_apu_i ? s_tx_pop_data[40] : dma_tx_axis.tlast;
  assign i2s_tx_axis.tid = tx_route_apu_i ? s_tx_pop_data[41] : dma_tx_axis.tid;
  assign i2s_tx_axis.tdest = tx_route_apu_i ? s_tx_pop_data[42] : dma_tx_axis.tdest;
  assign i2s_tx_axis.tuser = tx_route_apu_i ? s_tx_pop_data[43] : dma_tx_axis.tuser;
  assign i2s_tx_axis.tvalid = tx_route_apu_i ? !s_tx_empty : dma_tx_axis.tvalid;
  assign dma_tx_axis.tready = !tx_route_apu_i && i2s_tx_axis.tready;

  assign i2s_rx_axis.tready = rx_route_apu_i ? !s_rx_full : dma_rx_axis.tready;
  assign dma_rx_axis.tdata = i2s_rx_axis.tdata;
  assign dma_rx_axis.tkeep = i2s_rx_axis.tkeep;
  assign dma_rx_axis.tstrb = i2s_rx_axis.tstrb;
  assign dma_rx_axis.tlast = i2s_rx_axis.tlast;
  assign dma_rx_axis.tid = i2s_rx_axis.tid;
  assign dma_rx_axis.tdest = i2s_rx_axis.tdest;
  assign dma_rx_axis.tuser = i2s_rx_axis.tuser;
  assign dma_rx_axis.tvalid = !rx_route_apu_i && i2s_rx_axis.tvalid;

  assign apu_rx_axis.tdata = s_rx_pop_data[31:0];
  assign apu_rx_axis.tkeep = s_rx_pop_data[35:32];
  assign apu_rx_axis.tstrb = s_rx_pop_data[39:36];
  assign apu_rx_axis.tlast = s_rx_pop_data[40];
  assign apu_rx_axis.tid = s_rx_pop_data[41];
  assign apu_rx_axis.tdest = s_rx_pop_data[42];
  assign apu_rx_axis.tuser = s_rx_pop_data[43];
  assign apu_rx_axis.tvalid = !s_rx_empty;

  assign s_tx_active = tx_route_apu_i &&
      (tx_session_active_i || !s_tx_empty || (i2s_tx_axis.tvalid && !i2s_tx_axis.tready));
  assign s_rx_active = rx_route_apu_i && (rx_session_active_i || !s_rx_empty || s_rx_push);
  assign idle_o = !s_tx_active && !s_rx_active;
  assign s_tx_count_after = s_tx_count + CountWidth'(s_tx_push) - CountWidth'(s_tx_pop);
  assign s_rx_count_after = s_rx_count + CountWidth'(s_rx_push) - CountWidth'(s_rx_pop);
  assign input_watermark_evt_o = (rx_high_watermark_i != 8'd0) && s_rx_high_armed_q &&
      (s_rx_count < CountWidth'(rx_high_watermark_i)) &&
      (s_rx_count_after >= CountWidth'(rx_high_watermark_i));
  assign output_watermark_evt_o = (tx_low_watermark_i != 8'd0) && s_tx_low_armed_q &&
      s_tx_active && (s_tx_count > CountWidth'(tx_low_watermark_i)) &&
      (s_tx_count_after <= CountWidth'(tx_low_watermark_i));
  assign stream_xrun_evt_o = (tx_route_apu_i && tx_underrun_i) || (rx_route_apu_i && rx_overrun_i);
  assign status_o = {
    8'd0,
    s_rx_words_q,
    s_tx_words_q,
    s_rx_overrun_q,
    s_tx_underrun_q,
    s_rx_full,
    s_rx_empty,
    s_tx_full,
    s_tx_empty,
    s_rx_active,
    s_tx_active
  };

  stream_fifo #(
      .DATA_WIDTH  (PayloadWidth),
      .BUFFER_DEPTH(FifoDepth)
  ) u_tx_fifo (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .flush_i(flush_i),
      .full_o (s_tx_full),
      .empty_o(s_tx_empty),
      .cnt_o  (s_tx_count),
      .dat_i  (s_tx_push_data),
      .push_i (s_tx_push),
      .dat_o  (s_tx_pop_data),
      .pop_i  (s_tx_pop)
  );
  stream_fifo #(
      .DATA_WIDTH  (PayloadWidth),
      .BUFFER_DEPTH(FifoDepth)
  ) u_rx_fifo (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .flush_i(flush_i),
      .full_o (s_rx_full),
      .empty_o(s_rx_empty),
      .cnt_o  (s_rx_count),
      .dat_i  (s_rx_push_data),
      .push_i (s_rx_push),
      .dat_o  (s_rx_pop_data),
      .pop_i  (s_rx_pop)
  );

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i || flush_i) begin
      s_tx_low_armed_q  <= 1'b0;
      s_rx_high_armed_q <= 1'b1;
      s_tx_underrun_q   <= 1'b0;
      s_rx_overrun_q    <= 1'b0;
      s_tx_words_q      <= 8'd0;
      s_rx_words_q      <= 8'd0;
    end else begin
      if ((tx_low_watermark_i == 8'd0) ||
          (s_tx_count_after > CountWidth'(tx_low_watermark_i))) begin
        s_tx_low_armed_q <= tx_low_watermark_i != 8'd0;
      end else if (output_watermark_evt_o) begin
        s_tx_low_armed_q <= 1'b0;
      end
      if ((rx_high_watermark_i == 8'd0) ||
          (s_rx_count_after < CountWidth'(rx_high_watermark_i))) begin
        s_rx_high_armed_q <= 1'b1;
      end else if (input_watermark_evt_o) begin
        s_rx_high_armed_q <= 1'b0;
      end
      s_tx_underrun_q <= (s_tx_underrun_q && !xrun_clear_i) || (tx_route_apu_i && tx_underrun_i);
      s_rx_overrun_q  <= (s_rx_overrun_q && !xrun_clear_i) || (rx_route_apu_i && rx_overrun_i);
      if (counter_clear_i) begin
        s_tx_words_q <= 8'd0;
        s_rx_words_q <= 8'd0;
      end else begin
        if (s_tx_pop) s_tx_words_q <= saturating_increment(s_tx_words_q);
        if (s_rx_push) s_rx_words_q <= saturating_increment(s_rx_words_q);
      end
    end
  end

`ifndef SYNTHESIS
  initial begin
    if (FifoDepth != 64) $fatal(1, "apu_stream_router: P2 requires 64-word FIFOs");
  end
`endif
endmodule
