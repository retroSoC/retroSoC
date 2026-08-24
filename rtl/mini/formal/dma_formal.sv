// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

module dma_formal_design (
    // verilog_format: off -- protocol observations are grouped by channel.
    input  logic          clk_i,
    output logic          rst_n_i,
    output logic          f_past_valid,
    output logic [  3:0]  start_i,
    output logic [  3:0]  abort_i,
    output logic [  3:0]  start_seen,
    output logic          abort_seen,
    output logic [127:0]  programmed_bytes,
    output logic [  3:0]  busy,
    output logic [  3:0]  done,
    output logic [  3:0]  aborted,
    output logic [  3:0]  error,
    output logic [  3:0]  abort_pending,
    output logic [127:0]  bytes_done,
    output logic [127:0]  remaining,
    output logic [127:0]  channel_len,
    output logic [ 11:0]  fifo_count,
    output logic [  3:0]  fifo_push,
    output logic [  3:0]  fifo_pop,
    output logic [  3:0]  fifo_flush,
    output logic [  3:0]  fifo_full,
    output logic [  3:0]  fifo_empty,
    output logic          read_owner_valid,
    output logic [  1:0]  read_owner,
    output logic          write_owner_valid,
    output logic [  1:0]  write_owner,
    output logic [ 31:0]  write_bytes,
    output logic [ 31:0]  write_owner_bytes_done,
    output logic [ 31:0]  write_owner_len,
    output logic          read_start_valid,
    output logic          read_start_ready,
    output logic [  1:0]  read_start_channel,
    output logic          write_start_valid,
    output logic          write_start_ready,
    output logic [  1:0]  write_start_channel,
    output logic          tx_channel_valid,
    output logic [  1:0]  tx_channel,
    output logic [ 31:0]  tx_channel_bytes_done,
    output logic [ 31:0]  tx_channel_len,
    output logic          awvalid,
    output logic          awready,
    output logic          awid,
    output logic [ 31:0]  awaddr,
    output logic [  7:0]  awlen,
    output logic [  2:0]  awsize,
    output logic [  1:0]  awburst,
    output logic          awlock,
    output logic [  3:0]  awcache,
    output logic [  2:0]  awprot,
    output logic [  3:0]  awqos,
    output logic [  3:0]  awregion,
    output logic          awuser,
    output logic          wvalid,
    output logic          wready,
    output logic [ 31:0]  wdata,
    output logic [  3:0]  wstrb,
    output logic          wlast,
    output logic          wuser,
    output logic          bvalid,
    output logic          bready,
    output logic          bid,
    output logic [  1:0]  bresp,
    output logic          buser,
    output logic          arvalid,
    output logic          arready,
    output logic          arid,
    output logic [ 31:0]  araddr,
    output logic [  7:0]  arlen,
    output logic [  2:0]  arsize,
    output logic [  1:0]  arburst,
    output logic          arlock,
    output logic [  3:0]  arcache,
    output logic [  2:0]  arprot,
    output logic [  3:0]  arqos,
    output logic [  3:0]  arregion,
    output logic          aruser,
    output logic          rvalid,
    output logic          rready,
    output logic          rid,
    output logic [ 31:0]  rdata,
    output logic [  1:0]  rresp,
    output logic          rlast,
    output logic          ruser,
    output logic          tx_valid,
    output logic          tx_ready,
    output logic [ 31:0]  tx_data,
    output logic [  3:0]  tx_keep,
    output logic [  3:0]  tx_strb,
    output logic          tx_last,
    output logic          tx_id,
    output logic          tx_dest,
    output logic          tx_user,
    output logic          rx_valid,
    output logic          rx_ready,
    output logic [ 31:0]  rx_data,
    output logic [  3:0]  rx_keep,
    output logic [  3:0]  rx_strb,
    output logic          rx_last,
    output logic          rx_id,
    output logic          rx_dest,
    output logic          rx_user,
    output logic          dvp_rx_valid,
    output logic          dvp_rx_ready,
    output logic [ 31:0]  dvp_rx_data,
    output logic [  3:0]  dvp_rx_keep,
    output logic [  3:0]  dvp_rx_strb,
    output logic          dvp_rx_last,
    output logic          dvp_rx_id,
    output logic          dvp_rx_dest,
    output logic          dvp_rx_user
    // verilog_format: on
);
  import dma_pkg::*;

  localparam int NumChannels = 4;
  localparam int FifoDepth = 4;
  localparam int FifoCountWidth = $clog2(FifoDepth) + 1;

  logic [NumChannels*32-1:0] s_ch_cfg_i;
  logic [NumChannels*32-1:0] s_src_addr_i;
  logic [NumChannels*32-1:0] s_dst_addr_i;
  logic [NumChannels*32-1:0] s_byte_count_i;
  logic [NumChannels*32-1:0] s_request_sel_i;
  logic [NumChannels*32-1:0] s_burst_cfg_i;
  logic [   NumChannels-1:0] s_start_i;
  logic [   NumChannels-1:0] s_abort_i;
  logic [               5:0] s_cycle_q;
  logic [   NumChannels-1:0] s_start_seen_q;
  logic                      s_abort_seen_q;

  logic [   NumChannels-1:0] s_busy;
  logic [   NumChannels-1:0] s_done;
  logic [   NumChannels-1:0] s_aborted;
  logic [   NumChannels-1:0] s_error;
  logic [NumChannels*32-1:0] s_bytes_done;
  logic [NumChannels*32-1:0] s_remaining;

  logic                      s_read_active_q;
  logic                      s_read_stalled_once_q;
  logic [               4:0] s_read_beats_q;
  logic [               4:0] s_read_beat_q;
  logic                      s_read_error_q;
  logic [              31:0] s_read_data_q;

  logic                      s_write_active_q;
  logic                      s_write_response_q;
  logic                      s_aw_stalled_once_q;
  logic                      s_w_stalled_once_q;
  logic                      s_write_error_q;

  logic                      s_tx_stalled_once_q;

  (* anyconst *)logic [               1:0] f_scenario;
  (* anyconst *)logic [              31:0] f_read_data;
  (* anyconst *)logic [              31:0] f_rx_data;
  (* anyconst *)logic                      f_rx_last;

  dma_req_if req ();
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .USER_WIDTH(1)
  ) axi4 (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );
  axi4_stream_if #(
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .DEST_WIDTH(1),
      .USER_WIDTH(1)
  ) i2s_tx_axis (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );
  axi4_stream_if #(
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .DEST_WIDTH(1),
      .USER_WIDTH(1)
  ) i2s_rx_axis (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );
  axi4_stream_if #(
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .DEST_WIDTH(1),
      .USER_WIDTH(1)
  ) dvp_rx_axis (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );
  axi4_stream_if #(
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .DEST_WIDTH(1),
      .USER_WIDTH(1)
  ) crypto_in_axis (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );
  axi4_stream_if #(
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .DEST_WIDTH(1),
      .USER_WIDTH(1)
  ) crypto_out_axis (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );

  always_comb begin
    s_ch_cfg_i              = '0;
    s_src_addr_i            = '0;
    s_dst_addr_i            = '0;
    s_byte_count_i          = '0;
    s_request_sel_i         = '0;
    s_burst_cfg_i           = '0;

    s_ch_cfg_i[0+:32]       = {22'd0, 2'd0, 1'b1, 1'b1, DMA_WIDTH_32, 1'b0, DMA_KIND_MM_TO_MM};
    s_src_addr_i[0+:32]     = 32'h1000_0FF0;
    s_dst_addr_i[0+:32]     = 32'h1000_1FF0;
    s_byte_count_i[0+:32]   = 32'd16;
    s_request_sel_i[0+:32]  = {28'd0, DMA_REQUEST_SOFTWARE};
    s_burst_cfg_i[0+:32]    = 32'd4;

    s_ch_cfg_i[32+:32]      = {22'd0, 2'd1, 1'b0, 1'b1, DMA_WIDTH_32, 1'b0, DMA_KIND_MM_TO_STREAM};
    s_src_addr_i[32+:32]    = 32'h1000_3000;
    s_byte_count_i[32+:32]  = 32'd8;
    s_request_sel_i[32+:32] = {28'd0, DMA_REQUEST_I2S_TX};
    s_burst_cfg_i[32+:32]   = 32'd2;

    s_ch_cfg_i[64+:32]      = {22'd0, 2'd2, 1'b1, 1'b0, DMA_WIDTH_32, 1'b0, DMA_KIND_STREAM_TO_MM};
    s_dst_addr_i[64+:32]    = 32'h1000_4000;
    s_byte_count_i[64+:32]  = 32'd8;
    s_request_sel_i[64+:32] = {28'd0, DMA_REQUEST_I2S_RX};
    s_burst_cfg_i[64+:32]   = 32'd2;

    s_ch_cfg_i[96+:32]      = {22'd0, 2'd3, 1'b1, 1'b1, DMA_WIDTH_32, 1'b0, DMA_KIND_MM_TO_MM};
    s_src_addr_i[96+:32]    = 32'hDEAD_0000;
    s_dst_addr_i[96+:32]    = 32'h1000_5000;
    s_byte_count_i[96+:32]  = 32'd8;
    s_request_sel_i[96+:32] = {28'd0, DMA_REQUEST_SOFTWARE};
    s_burst_cfg_i[96+:32]   = 32'd2;
  end

  always_comb begin
    s_start_i = '0;
    s_abort_i = '0;
    if (rst_n_i) begin
      unique case (f_scenario)
        2'd0: begin
          if (s_cycle_q == 6'd0) begin
            s_start_i[0] = 1'b1;
          end
        end
        2'd1: begin
          if (s_cycle_q == 6'd0) begin
            s_start_i[1] = 1'b1;
          end
          if (s_cycle_q == 6'd1) begin
            s_start_i[0] = 1'b1;
          end
          if (!s_abort_seen_q && i2s_tx_axis.tvalid && !i2s_tx_axis.tready) begin
            s_abort_i[1] = 1'b1;
          end
        end
        2'd2: begin
          if (s_cycle_q == 6'd0) begin
            s_start_i[2] = 1'b1;
          end
        end
        default: begin
          if (s_cycle_q == 6'd0) begin
            s_start_i[0] = 1'b1;
          end
          if (s_cycle_q == 6'd1) begin
            s_start_i[3] = 1'b1;
          end
        end
      endcase
    end
  end

  assign start_i = s_start_i;
  assign abort_i = s_abort_i;
  assign start_seen = s_start_seen_q;
  assign abort_seen = s_abort_seen_q;
  assign programmed_bytes = s_byte_count_i;

  assign req.i2s_tx_proc = 1'b1;
  assign req.i2s_rx_proc = 1'b1;
  assign req.qspi_tx_proc = 1'b1;
  assign req.qspi_rx_proc = 1'b1;
  assign req.uart_tx_proc = 1'b1;
  assign req.uart_rx_proc = 1'b1;
  assign req.i2c0_tx_proc = 1'b1;
  assign req.i2c0_rx_proc = 1'b1;
  assign req.i2c1_tx_proc = 1'b1;
  assign req.i2c1_rx_proc = 1'b1;
  assign req.crypto_in_proc = 1'b1;
  assign req.crypto_out_proc = 1'b1;

  assign axi4.arready = !s_read_active_q && (!axi4.arvalid || s_read_stalled_once_q);
  assign axi4.rid = 1'b0;
  assign axi4.rdata = s_read_data_q;
  assign axi4.rresp = s_read_error_q ? 2'b11 : 2'b00;
  assign axi4.rlast = s_read_active_q && ((s_read_beat_q + 1'b1) == s_read_beats_q);
  assign axi4.ruser = 1'b0;
  assign axi4.rvalid = s_read_active_q;

  assign axi4.awready = !s_write_active_q && !s_write_response_q &&
                        (!axi4.awvalid || s_aw_stalled_once_q);
  assign axi4.wready = s_write_active_q && (!axi4.wvalid || s_w_stalled_once_q);
  assign axi4.bid = 1'b0;
  assign axi4.bresp = s_write_error_q ? 2'b10 : 2'b00;
  assign axi4.buser = 1'b0;
  assign axi4.bvalid = s_write_response_q;

  // The first stream beat observes one legal backpressure cycle.
  assign i2s_tx_axis.tready = !i2s_tx_axis.tvalid || s_tx_stalled_once_q;

  assign i2s_rx_axis.tdata = f_rx_data;
  assign i2s_rx_axis.tkeep = 4'hF;
  assign i2s_rx_axis.tstrb = 4'hF;
  assign i2s_rx_axis.tlast = f_rx_last;
  assign i2s_rx_axis.tid = 1'b0;
  assign i2s_rx_axis.tdest = 1'b0;
  assign i2s_rx_axis.tuser = 1'b0;
  assign i2s_rx_axis.tvalid = rst_n_i && (f_scenario == 2'd2);

  assign dvp_rx_axis.tdata = 32'd0;
  assign dvp_rx_axis.tkeep = 4'hF;
  assign dvp_rx_axis.tstrb = 4'hF;
  assign dvp_rx_axis.tlast = 1'b0;
  assign dvp_rx_axis.tid = 1'b0;
  assign dvp_rx_axis.tdest = 1'b0;
  assign dvp_rx_axis.tuser = 1'b0;
  assign dvp_rx_axis.tvalid = 1'b0;
  assign crypto_in_axis.tready = 1'b0;
  assign crypto_out_axis.tdata = 32'd0;
  assign crypto_out_axis.tkeep = 4'hF;
  assign crypto_out_axis.tstrb = 4'hF;
  assign crypto_out_axis.tlast = 1'b0;
  assign crypto_out_axis.tid = 1'b0;
  assign crypto_out_axis.tdest = 1'b0;
  assign crypto_out_axis.tuser = 1'b0;
  assign crypto_out_axis.tvalid = 1'b0;

  dma_core #(
      .AddrWidth    (32),
      .DataWidth    (32),
      .NumChannels  (NumChannels),
      .MaxBurstBeats(4),
      .FifoDepth    (FifoDepth)
  ) u_dut (
      .clk_i                (clk_i),
      .rst_n_i              (rst_n_i),
      .global_reset_i       (1'b0),
      .global_error_clear_i (1'b0),
      .ch_cfg_i             (s_ch_cfg_i),
      .src_addr_i           (s_src_addr_i),
      .dst_addr_i           (s_dst_addr_i),
      .byte_count_i         (s_byte_count_i),
      .request_sel_i        (s_request_sel_i),
      .burst_cfg_i          (s_burst_cfg_i),
      .start_i              (s_start_i),
      .suspend_i            ('0),
      .resume_i             ('0),
      .abort_i              (s_abort_i),
      .channel_reset_i      ('0),
      .event_clear_i        ('0),
      .busy_o               (s_busy),
      .suspended_o          (),
      .done_o               (s_done),
      .aborted_o            (s_aborted),
      .error_o              (s_error),
      .stream_last_o        (),
      .event_status_o       (),
      .error_status_o       (),
      .error_addr_o         (),
      .current_src_o        (),
      .current_dst_o        (),
      .remaining_o          (s_remaining),
      .bytes_done_o         (s_bytes_done),
      .stall_cycles_lo_o    (),
      .stall_cycles_hi_o    (),
      .first_error_valid_o  (),
      .first_error_channel_o(),
      .first_error_status_o (),
      .first_error_addr_hi_o(),
      .request_status_o     (),
      .xpi_xfer_done_o      (),
      .req                  (req),
      .axi4                 (axi4),
      .i2s_tx_axis          (i2s_tx_axis),
      .i2s_rx_axis          (i2s_rx_axis),
      .dvp_rx_axis          (dvp_rx_axis),
      .crypto_in_axis       (crypto_in_axis),
      .crypto_out_axis      (crypto_out_axis)
  );

  assign busy                = s_busy;
  assign done                = s_done;
  assign aborted             = s_aborted;
  assign error               = s_error;
  assign bytes_done          = s_bytes_done;
  assign remaining           = s_remaining;
  assign channel_len         = u_dut.s_len_q;
  assign fifo_count          = u_dut.s_fifo_count;
  assign fifo_push           = u_dut.s_fifo_push;
  assign fifo_pop            = u_dut.s_fifo_pop;
  assign fifo_flush          = u_dut.s_fifo_flush;
  assign fifo_full           = u_dut.s_fifo_full;
  assign fifo_empty          = u_dut.s_fifo_empty;
  assign abort_pending       = u_dut.s_abort_q;
  assign read_owner_valid    = u_dut.s_read_owner_valid_q;
  assign read_owner          = u_dut.s_read_owner_q;
  assign write_owner_valid   = u_dut.s_write_owner_valid_q;
  assign write_owner         = u_dut.s_write_owner_q;
  assign write_bytes         = u_dut.s_write_bytes_q;
  assign read_start_valid    = u_dut.s_axi_read_start_valid;
  assign read_start_ready    = u_dut.s_axi_read_start_ready;
  assign read_start_channel  = u_dut.s_read_rr_selected;
  assign write_start_valid   = u_dut.s_axi_write_start_valid;
  assign write_start_ready   = u_dut.s_axi_write_start_ready;
  assign write_start_channel = u_dut.s_write_rr_selected;
  assign tx_channel_valid    = u_dut.s_i2s_tx_channel_valid;
  assign tx_channel          = u_dut.s_i2s_tx_channel;

  always_comb begin
    write_owner_bytes_done = 32'd0;
    write_owner_len        = 32'd0;
    tx_channel_bytes_done  = 32'd0;
    tx_channel_len         = 32'd0;
    if (u_dut.s_write_owner_valid_q) begin
      write_owner_bytes_done = u_dut.s_bytes_done_q[u_dut.s_write_owner_q];
      write_owner_len        = u_dut.s_len_q[u_dut.s_write_owner_q];
    end
    if (u_dut.s_i2s_tx_channel_valid) begin
      tx_channel_bytes_done = u_dut.s_bytes_done_q[u_dut.s_i2s_tx_channel];
      tx_channel_len        = u_dut.s_len_q[u_dut.s_i2s_tx_channel];
    end
  end

  assign awvalid      = axi4.awvalid;
  assign awready      = axi4.awready;
  assign awid         = axi4.awid;
  assign awaddr       = axi4.awaddr;
  assign awlen        = axi4.awlen;
  assign awsize       = axi4.awsize;
  assign awburst      = axi4.awburst;
  assign awlock       = axi4.awlock;
  assign awcache      = axi4.awcache;
  assign awprot       = axi4.awprot;
  assign awqos        = axi4.awqos;
  assign awregion     = axi4.awregion;
  assign awuser       = axi4.awuser;
  assign wvalid       = axi4.wvalid;
  assign wready       = axi4.wready;
  assign wdata        = axi4.wdata;
  assign wstrb        = axi4.wstrb;
  assign wlast        = axi4.wlast;
  assign wuser        = axi4.wuser;
  assign bvalid       = axi4.bvalid;
  assign bready       = axi4.bready;
  assign bid          = axi4.bid;
  assign bresp        = axi4.bresp;
  assign buser        = axi4.buser;
  assign arvalid      = axi4.arvalid;
  assign arready      = axi4.arready;
  assign arid         = axi4.arid;
  assign araddr       = axi4.araddr;
  assign arlen        = axi4.arlen;
  assign arsize       = axi4.arsize;
  assign arburst      = axi4.arburst;
  assign arlock       = axi4.arlock;
  assign arcache      = axi4.arcache;
  assign arprot       = axi4.arprot;
  assign arqos        = axi4.arqos;
  assign arregion     = axi4.arregion;
  assign aruser       = axi4.aruser;
  assign rvalid       = axi4.rvalid;
  assign rready       = axi4.rready;
  assign rid          = axi4.rid;
  assign rdata        = axi4.rdata;
  assign rresp        = axi4.rresp;
  assign rlast        = axi4.rlast;
  assign ruser        = axi4.ruser;
  assign tx_valid     = i2s_tx_axis.tvalid;
  assign tx_ready     = i2s_tx_axis.tready;
  assign tx_data      = i2s_tx_axis.tdata;
  assign tx_keep      = i2s_tx_axis.tkeep;
  assign tx_strb      = i2s_tx_axis.tstrb;
  assign tx_last      = i2s_tx_axis.tlast;
  assign tx_id        = i2s_tx_axis.tid;
  assign tx_dest      = i2s_tx_axis.tdest;
  assign tx_user      = i2s_tx_axis.tuser;
  assign rx_valid     = i2s_rx_axis.tvalid;
  assign rx_ready     = i2s_rx_axis.tready;
  assign rx_data      = i2s_rx_axis.tdata;
  assign rx_keep      = i2s_rx_axis.tkeep;
  assign rx_strb      = i2s_rx_axis.tstrb;
  assign rx_last      = i2s_rx_axis.tlast;
  assign rx_id        = i2s_rx_axis.tid;
  assign rx_dest      = i2s_rx_axis.tdest;
  assign rx_user      = i2s_rx_axis.tuser;
  assign dvp_rx_valid = dvp_rx_axis.tvalid;
  assign dvp_rx_ready = dvp_rx_axis.tready;
  assign dvp_rx_data  = dvp_rx_axis.tdata;
  assign dvp_rx_keep  = dvp_rx_axis.tkeep;
  assign dvp_rx_strb  = dvp_rx_axis.tstrb;
  assign dvp_rx_last  = dvp_rx_axis.tlast;
  assign dvp_rx_id    = dvp_rx_axis.tid;
  assign dvp_rx_dest  = dvp_rx_axis.tdest;
  assign dvp_rx_user  = dvp_rx_axis.tuser;

  initial begin
    rst_n_i      = 1'b0;
    f_past_valid = 1'b0;
  end

  always_ff @(posedge clk_i) begin
    rst_n_i      <= 1'b1;
    f_past_valid <= 1'b1;
    if (!rst_n_i) begin
      s_cycle_q      <= 6'd0;
      s_start_seen_q <= '0;
      s_abort_seen_q <= 1'b0;
    end else begin
      if (s_cycle_q != 6'h3F) begin
        s_cycle_q <= s_cycle_q + 1'b1;
      end
      s_start_seen_q <= s_start_seen_q | s_start_i;
      s_abort_seen_q <= s_abort_seen_q | s_abort_i[1];
    end
  end

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      s_read_active_q       <= 1'b0;
      s_read_stalled_once_q <= 1'b0;
      s_read_beats_q        <= 5'd0;
      s_read_beat_q         <= 5'd0;
      s_read_error_q        <= 1'b0;
      s_read_data_q         <= 32'd0;
    end else begin
      if (axi4.arvalid && !axi4.arready) begin
        s_read_stalled_once_q <= 1'b1;
      end
      if (axi4.arvalid && axi4.arready) begin
        s_read_active_q <= 1'b1;
        s_read_beats_q  <= {1'b0, axi4.arlen[3:0]} + 1'b1;
        s_read_beat_q   <= 5'd0;
        s_read_error_q  <= axi4.araddr[31:28] == 4'hD;
        s_read_data_q   <= f_read_data;
      end
      if (axi4.rvalid && axi4.rready) begin
        if (axi4.rlast) begin
          s_read_active_q <= 1'b0;
        end else begin
          s_read_beat_q <= s_read_beat_q + 1'b1;
          s_read_data_q <= f_read_data;
        end
      end
    end
  end

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      s_write_active_q    <= 1'b0;
      s_write_response_q  <= 1'b0;
      s_aw_stalled_once_q <= 1'b0;
      s_w_stalled_once_q  <= 1'b0;
      s_write_error_q     <= 1'b0;
    end else begin
      if (axi4.awvalid && !axi4.awready) begin
        s_aw_stalled_once_q <= 1'b1;
      end
      if (axi4.awvalid && axi4.awready) begin
        s_write_active_q <= 1'b1;
        s_write_error_q  <= axi4.awaddr[31:28] == 4'hE;
      end
      if (axi4.wvalid && !axi4.wready) begin
        s_w_stalled_once_q <= 1'b1;
      end
      if (axi4.wvalid && axi4.wready) begin
        if (axi4.wlast) begin
          s_write_active_q   <= 1'b0;
          s_write_response_q <= 1'b1;
        end
      end
      if (axi4.bvalid && axi4.bready) begin
        s_write_response_q <= 1'b0;
      end
    end
  end

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      s_tx_stalled_once_q <= 1'b0;
    end else if (i2s_tx_axis.tvalid && !i2s_tx_axis.tready) begin
      s_tx_stalled_once_q <= 1'b1;
    end
  end

endmodule
