// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

module tiny_axi4_async_bridge #(
    parameter int unsigned AddrWidth = 32,
    parameter int unsigned DataWidth = 32,
    parameter int unsigned IdWidth   = 1,
    parameter int unsigned UserWidth = 1,
    parameter int unsigned FifoDepth = 4
) (
    // verilog_format: off -- preserve the source/destination clock boundary columns
    input  logic       src_clk_i,
    input  logic       src_rst_n_i,
    input  logic       dst_clk_i,
    input  logic       dst_rst_n_i,
    input  logic       clear_i,
    output logic       clear_busy_o,
    output logic       ready_o,
    output logic [7:0] epoch_o,
    axi4_if.slave      src_axi4,
    axi4_if.master     dst_axi4
    // verilog_format: on
);
  localparam int unsigned StrbWidth = DataWidth / 8;
  localparam int unsigned AwWidth = IdWidth + AddrWidth + 8 + 3 + 2 + 1 + 4 + 3 + 4 + 4 + UserWidth;
  localparam int unsigned WWidth = DataWidth + StrbWidth + 1 + UserWidth;
  localparam int unsigned BWidth = IdWidth + 2 + UserWidth;
  localparam int unsigned ArWidth = AwWidth;
  localparam int unsigned RWidth = IdWidth + DataWidth + 2 + 1 + UserWidth;

  logic [AwWidth-1:0] s_aw_src_data;
  logic [AwWidth-1:0] s_aw_dst_data;
  logic [ WWidth-1:0] s_w_src_data;
  logic [ WWidth-1:0] s_w_dst_data;
  logic [ BWidth-1:0] s_b_dst_data;
  logic [ BWidth-1:0] s_b_src_data;
  logic [ArWidth-1:0] s_ar_src_data;
  logic [ArWidth-1:0] s_ar_dst_data;
  logic [ RWidth-1:0] s_r_dst_data;
  logic [ RWidth-1:0] s_r_src_data;
  logic               s_clear_src;
  logic               s_clear_dst;
  logic               s_clear_q;
  logic               s_clear_dst_q;
  logic               s_clear_src_pulse;
  logic               s_clear_dst_pulse;
  logic               s_dst_rst_n_src_q;
  logic               s_dst_reset_evt;
  logic [7:0] s_epoch_d, s_epoch_q;
  logic s_aw_src_clear_busy, s_aw_dst_clear_busy;
  logic s_w_src_clear_busy, s_w_dst_clear_busy;
  logic s_b_src_clear_busy, s_b_dst_clear_busy;
  logic s_ar_src_clear_busy, s_ar_dst_clear_busy;
  logic s_r_src_clear_busy, s_r_dst_clear_busy;
  logic s_dst_busy_src;
  logic s_link_src_rst_n, s_link_dst_rst_n;
  logic s_src_link_rst_n;
  logic s_src_accept;
  logic s_aw_src_ready_i, s_w_src_ready_i, s_ar_src_ready_i;
  logic s_b_src_valid, s_r_src_valid;
  logic s_write_pending_d, s_write_pending_q;
  logic s_read_pending_d, s_read_pending_q;
  logic s_abort_write_d, s_abort_write_q;
  logic s_abort_read_d, s_abort_read_q;
  logic [IdWidth-1:0] s_write_id_d, s_write_id_q;
  logic [IdWidth-1:0] s_read_id_d, s_read_id_q;
  logic [8:0] s_write_left_d, s_write_left_q, s_read_left_d, s_read_left_q;
  logic [BWidth-1:0] s_b_hold_d, s_b_hold_q;
  logic [RWidth-1:0] s_r_hold_d, s_r_hold_q;
  logic s_b_hold_valid_d, s_b_hold_valid_q, s_r_hold_valid_d, s_r_hold_valid_q;
  logic s_b_take, s_r_take, s_abort_evt;
  logic s_clear_wait_reset_d, s_clear_wait_reset_q;

  cdc_reset_barrier #(
      .STAGES(5)
  ) u_link_barrier (
      .clk_a_i  (src_clk_i),
      .clk_b_i  (dst_clk_i),
      .rst_n_i  (src_rst_n_i && dst_rst_n_i),
      .release_i(1'b1),
      .rst_a_n_o(s_link_src_rst_n),
      .rst_b_n_o(s_link_dst_rst_n)
  );
  assign s_src_link_rst_n = s_link_src_rst_n;
  assign s_src_accept = s_src_link_rst_n &&
      !clear_busy_o && !s_abort_write_q && !s_abort_read_q && !s_abort_evt && !s_clear_wait_reset_q;
  assign ready_o = s_src_accept;
  cdc_sync #(
      .STAGE     (2),
      .DATA_WIDTH(1)
  ) u_busy_sync (
      .clk_i(src_clk_i),
      .rst_n_i(src_rst_n_i),
      .dat_i(s_aw_dst_clear_busy || s_w_dst_clear_busy || s_b_dst_clear_busy ||
             s_ar_dst_clear_busy || s_r_dst_clear_busy || !s_link_dst_rst_n),
      .dat_o(s_dst_busy_src)
  );

  cdc_sync #(
      .STAGE     (2),
      .DATA_WIDTH(1)
  ) u_clear_src_sync (
      .clk_i  (src_clk_i),
      .rst_n_i(src_rst_n_i),
      .dat_i  (clear_i),
      .dat_o  (s_clear_src)
  );
  cdc_sync #(
      .STAGE     (2),
      .DATA_WIDTH(1)
  ) u_clear_sync (
      .clk_i  (dst_clk_i),
      .rst_n_i(dst_rst_n_i),
      .dat_i  (clear_i),
      .dat_o  (s_clear_dst)
  );
  assign s_clear_src_pulse = s_clear_src && !s_clear_q;
  assign s_clear_dst_pulse = s_clear_dst && !s_clear_dst_q;
  assign s_dst_reset_evt = s_dst_rst_n_src_q && !s_link_src_rst_n;
  assign s_abort_evt = s_dst_reset_evt || s_clear_src_pulse;

  assign src_axi4.awready = s_src_accept && !s_write_pending_q && s_aw_src_ready_i;
  // Accepted write data must drain even when its destination session is lost.
  // Never report B until all AWLEN+1 source beats have been consumed.
  assign src_axi4.wready = s_write_pending_q && s_write_left_q != 0 &&
      (s_abort_write_q || (s_src_accept && s_w_src_ready_i));
  assign src_axi4.arready = s_src_accept && !s_read_pending_q && s_ar_src_ready_i;

  // These registers belong to the surviving source session. Remote reset may
  // discard FIFO payload, but cannot revoke VALID or rewrite a held response.
  assign {src_axi4.bid, src_axi4.bresp, src_axi4.buser} = s_b_hold_q;
  assign {src_axi4.rid, src_axi4.rdata, src_axi4.rresp,
          src_axi4.rlast, src_axi4.ruser} = s_r_hold_q;
  assign src_axi4.bvalid = s_b_hold_valid_q;
  assign src_axi4.rvalid = s_r_hold_valid_q;
  assign s_b_take = (!s_b_hold_valid_q || src_axi4.bready) && s_write_pending_q &&
      !(src_axi4.bvalid && src_axi4.bready) &&
      s_write_left_q == 0 && !s_abort_write_q && !s_abort_evt && s_src_accept;
  assign s_r_take = (!s_r_hold_valid_q || src_axi4.rready) && s_read_pending_q &&
      !(src_axi4.rvalid && src_axi4.rready && src_axi4.rlast) &&
      !s_abort_read_q && !s_abort_evt && s_src_accept;

  always_comb begin
    s_write_pending_d    = s_write_pending_q;
    s_read_pending_d     = s_read_pending_q;
    s_abort_write_d      = s_abort_write_q;
    s_abort_read_d       = s_abort_read_q;
    s_write_id_d         = s_write_id_q;
    s_read_id_d          = s_read_id_q;
    s_write_left_d       = s_write_left_q;
    s_read_left_d        = s_read_left_q;
    s_b_hold_d           = s_b_hold_q;
    s_r_hold_d           = s_r_hold_q;
    s_b_hold_valid_d     = s_b_hold_valid_q;
    s_r_hold_valid_d     = s_r_hold_valid_q;
    s_clear_wait_reset_d = s_clear_wait_reset_q;
    if (src_axi4.awvalid && src_axi4.awready) begin
      s_write_pending_d = 1'b1;
      s_write_id_d      = src_axi4.awid;
      s_write_left_d    = {1'b0, src_axi4.awlen} + 9'd1;
    end
    if (src_axi4.arvalid && src_axi4.arready) begin
      s_read_pending_d = 1'b1;
      s_read_id_d      = src_axi4.arid;
      s_read_left_d    = {1'b0, src_axi4.arlen} + 9'd1;
    end
    if (src_axi4.wvalid && src_axi4.wready) s_write_left_d = s_write_left_q - 9'd1;
    if (src_axi4.bvalid && src_axi4.bready) begin
      s_write_pending_d = 1'b0;
      s_abort_write_d   = 1'b0;
      s_b_hold_valid_d  = 1'b0;
    end
    if (src_axi4.rvalid && src_axi4.rready) begin
      s_r_hold_valid_d = 1'b0;
      s_read_left_d    = s_read_left_q - 9'd1;
      if (src_axi4.rlast) begin
        s_read_pending_d = 1'b0;
        s_abort_read_d   = 1'b0;
      end
    end
    // A source handshake is irrevocable. Abort only the work still pending
    // after that handshake; do not create a second terminal response.
    if (s_abort_evt) begin
      s_abort_write_d = s_write_pending_d;
      s_abort_read_d  = s_read_pending_d;
    end
    // A FIFO clear alone cannot cancel a transaction already accepted by a
    // remote AXI slave. Return local errors, but quarantine late responses
    // until an actual destination reset establishes a new session. Normal
    // drained clears and already exposed terminal responses need no reset.
    if (s_clear_src_pulse &&
        ((s_write_pending_d && !s_b_hold_valid_q) ||
         (s_read_pending_d && !(s_r_hold_valid_q && src_axi4.rlast))))
      s_clear_wait_reset_d = 1'b1;
    if (s_dst_reset_evt) s_clear_wait_reset_d = 1'b0;
    if (s_b_take && s_b_src_valid) begin
      s_b_hold_d       = s_b_src_data;
      s_b_hold_valid_d = 1'b1;
    end else if (!s_b_hold_valid_d && s_abort_write_d && s_write_left_d == 0) begin
      s_b_hold_d       = {s_write_id_q, 2'b11, {UserWidth{1'b0}}};
      s_b_hold_valid_d = 1'b1;
    end
    if (s_r_take && s_r_src_valid) begin
      s_r_hold_d       = s_r_src_data;
      s_r_hold_valid_d = 1'b1;
    end else if (!s_r_hold_valid_d && s_abort_read_d && s_read_left_d != 0) begin
      s_r_hold_d = {
        s_read_id_q, {DataWidth{1'b0}}, 2'b11, (s_read_left_d == 9'd1), {UserWidth{1'b0}}
      };
      s_r_hold_valid_d = 1'b1;
    end
  end

  assign s_aw_src_data = {
    src_axi4.awid,
    src_axi4.awaddr,
    src_axi4.awlen,
    src_axi4.awsize,
    src_axi4.awburst,
    src_axi4.awlock,
    src_axi4.awcache,
    src_axi4.awprot,
    src_axi4.awqos,
    src_axi4.awregion,
    src_axi4.awuser
  };
  assign {
    dst_axi4.awid,
    dst_axi4.awaddr,
    dst_axi4.awlen,
    dst_axi4.awsize,
    dst_axi4.awburst,
    dst_axi4.awlock,
    dst_axi4.awcache,
    dst_axi4.awprot,
    dst_axi4.awqos,
    dst_axi4.awregion,
    dst_axi4.awuser
  } = s_aw_dst_data;

  cdc_fifo_warm_flush #(
      .DATA_WIDTH  (AwWidth),
      .BUFFER_DEPTH(FifoDepth)
  ) u_aw_fifo (
      .src_clk_i       (src_clk_i),
      .src_rst_n_i     (s_src_link_rst_n),
      .src_clear_i     (s_clear_src_pulse),
      .src_clear_busy_o(s_aw_src_clear_busy),
      .src_data_i      (s_aw_src_data),
      .src_valid_i     (src_axi4.awvalid && s_src_accept && !s_write_pending_q),
      .src_ready_o     (s_aw_src_ready_i),
      .dst_clk_i       (dst_clk_i),
      .dst_rst_n_i     (dst_rst_n_i),
      .dst_clear_busy_o(s_aw_dst_clear_busy),
      .dst_data_o      (s_aw_dst_data),
      .dst_valid_o     (dst_axi4.awvalid),
      .dst_ready_i     (dst_axi4.awready)
  );

  assign s_w_src_data = {src_axi4.wdata, src_axi4.wstrb, src_axi4.wlast, src_axi4.wuser};
  assign {dst_axi4.wdata, dst_axi4.wstrb, dst_axi4.wlast, dst_axi4.wuser} = s_w_dst_data;

  cdc_fifo_warm_flush #(
      .DATA_WIDTH  (WWidth),
      .BUFFER_DEPTH(FifoDepth)
  ) u_w_fifo (
      .src_clk_i(src_clk_i),
      .src_rst_n_i(s_src_link_rst_n),
      .src_clear_i(s_clear_src_pulse),
      .src_clear_busy_o(s_w_src_clear_busy),
      .src_data_i(s_w_src_data),
      .src_valid_i(src_axi4.wvalid && s_src_accept && s_write_pending_q && s_write_left_q != 0),
      .src_ready_o(s_w_src_ready_i),
      .dst_clk_i(dst_clk_i),
      .dst_rst_n_i(dst_rst_n_i),
      .dst_clear_busy_o(s_w_dst_clear_busy),
      .dst_data_o(s_w_dst_data),
      .dst_valid_o(dst_axi4.wvalid),
      .dst_ready_i(dst_axi4.wready)
  );

  assign s_b_dst_data = {dst_axi4.bid, dst_axi4.bresp, dst_axi4.buser};
  cdc_fifo_warm_flush #(
      .DATA_WIDTH  (BWidth),
      .BUFFER_DEPTH(FifoDepth)
  ) u_b_fifo (
      .src_clk_i       (dst_clk_i),
      .src_rst_n_i     (dst_rst_n_i),
      .src_clear_i     (s_clear_dst_pulse),
      .src_clear_busy_o(s_b_dst_clear_busy),
      .src_data_i      (s_b_dst_data),
      .src_valid_i     (dst_axi4.bvalid),
      .src_ready_o     (dst_axi4.bready),
      .dst_clk_i       (src_clk_i),
      .dst_rst_n_i     (s_src_link_rst_n),
      .dst_clear_busy_o(s_b_src_clear_busy),
      .dst_data_o      (s_b_src_data),
      .dst_valid_o     (s_b_src_valid),
      .dst_ready_i     (s_b_take)
  );

  assign s_ar_src_data = {
    src_axi4.arid,
    src_axi4.araddr,
    src_axi4.arlen,
    src_axi4.arsize,
    src_axi4.arburst,
    src_axi4.arlock,
    src_axi4.arcache,
    src_axi4.arprot,
    src_axi4.arqos,
    src_axi4.arregion,
    src_axi4.aruser
  };
  assign {
    dst_axi4.arid,
    dst_axi4.araddr,
    dst_axi4.arlen,
    dst_axi4.arsize,
    dst_axi4.arburst,
    dst_axi4.arlock,
    dst_axi4.arcache,
    dst_axi4.arprot,
    dst_axi4.arqos,
    dst_axi4.arregion,
    dst_axi4.aruser
  } = s_ar_dst_data;

  cdc_fifo_warm_flush #(
      .DATA_WIDTH  (ArWidth),
      .BUFFER_DEPTH(FifoDepth)
  ) u_ar_fifo (
      .src_clk_i       (src_clk_i),
      .src_rst_n_i     (s_src_link_rst_n),
      .src_clear_i     (s_clear_src_pulse),
      .src_clear_busy_o(s_ar_src_clear_busy),
      .src_data_i      (s_ar_src_data),
      .src_valid_i     (src_axi4.arvalid && s_src_accept && !s_read_pending_q),
      .src_ready_o     (s_ar_src_ready_i),
      .dst_clk_i       (dst_clk_i),
      .dst_rst_n_i     (dst_rst_n_i),
      .dst_clear_busy_o(s_ar_dst_clear_busy),
      .dst_data_o      (s_ar_dst_data),
      .dst_valid_o     (dst_axi4.arvalid),
      .dst_ready_i     (dst_axi4.arready)
  );

  assign s_r_dst_data = {
    dst_axi4.rid, dst_axi4.rdata, dst_axi4.rresp, dst_axi4.rlast, dst_axi4.ruser
  };
  cdc_fifo_warm_flush #(
      .DATA_WIDTH  (RWidth),
      .BUFFER_DEPTH(FifoDepth)
  ) u_r_fifo (
      .src_clk_i       (dst_clk_i),
      .src_rst_n_i     (dst_rst_n_i),
      .src_clear_i     (s_clear_dst_pulse),
      .src_clear_busy_o(s_r_dst_clear_busy),
      .src_data_i      (s_r_dst_data),
      .src_valid_i     (dst_axi4.rvalid),
      .src_ready_o     (dst_axi4.rready),
      .dst_clk_i       (src_clk_i),
      .dst_rst_n_i     (s_src_link_rst_n),
      .dst_clear_busy_o(s_r_src_clear_busy),
      .dst_data_o      (s_r_src_data),
      .dst_valid_o     (s_r_src_valid),
      .dst_ready_i     (s_r_take)
  );

  assign clear_busy_o = s_aw_src_clear_busy || s_w_src_clear_busy ||
                        s_b_src_clear_busy || s_ar_src_clear_busy ||
                        s_r_src_clear_busy || s_dst_busy_src;
  assign s_epoch_d = ((s_clear_src_pulse && !clear_busy_o) || s_dst_reset_evt) ?
      s_epoch_q + 1'b1 : s_epoch_q;
  assign epoch_o = s_epoch_q;

  always_ff @(posedge src_clk_i or negedge src_rst_n_i) begin
    if (!src_rst_n_i) begin
      s_clear_q            <= 1'b0;
      s_dst_rst_n_src_q    <= 1'b0;
      s_epoch_q            <= '0;
      s_write_pending_q    <= 1'b0;
      s_read_pending_q     <= 1'b0;
      s_abort_write_q      <= 1'b0;
      s_abort_read_q       <= 1'b0;
      s_write_id_q         <= '0;
      s_read_id_q          <= '0;
      s_write_left_q       <= '0;
      s_read_left_q        <= '0;
      s_b_hold_q           <= '0;
      s_r_hold_q           <= '0;
      s_b_hold_valid_q     <= 1'b0;
      s_r_hold_valid_q     <= 1'b0;
      s_clear_wait_reset_q <= 1'b0;
    end else begin
      s_clear_q            <= s_clear_src;
      s_dst_rst_n_src_q    <= s_link_src_rst_n;
      s_epoch_q            <= s_epoch_d;
      s_write_pending_q    <= s_write_pending_d;
      s_read_pending_q     <= s_read_pending_d;
      s_abort_write_q      <= s_abort_write_d;
      s_abort_read_q       <= s_abort_read_d;
      s_write_id_q         <= s_write_id_d;
      s_read_id_q          <= s_read_id_d;
      s_write_left_q       <= s_write_left_d;
      s_read_left_q        <= s_read_left_d;
      s_b_hold_q           <= s_b_hold_d;
      s_r_hold_q           <= s_r_hold_d;
      s_b_hold_valid_q     <= s_b_hold_valid_d;
      s_r_hold_valid_q     <= s_r_hold_valid_d;
      s_clear_wait_reset_q <= s_clear_wait_reset_d;
    end
  end

  always_ff @(posedge dst_clk_i or negedge dst_rst_n_i) begin
    if (!dst_rst_n_i) begin
      s_clear_dst_q <= 1'b0;
    end else begin
      s_clear_dst_q <= s_clear_dst;
    end
  end

`ifndef SYNTHESIS
  initial begin
    if ((AddrWidth < 1) || (DataWidth < 8) || ((DataWidth % 8) != 0) ||
        (IdWidth < 1) || (UserWidth < 1) || (FifoDepth < 2) ||
        ((FifoDepth & (FifoDepth - 1)) != 0)) begin
      $fatal(1, "axi4_async_bridge: invalid interface or FIFO parameters");
    end
  end
`endif
endmodule
