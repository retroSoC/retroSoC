`timescale 1ns / 1ps

module dma_origin_tb;
  localparam int NumChannels = 4;
  localparam logic [31:0] SourceBase = 32'h4000_0000;
  localparam logic [31:0] DestinationBase = 32'h5000_0000;

  logic                        clk_i = 1'b0;
  logic                        rst_n_i = 1'b0;
  logic   [NumChannels*32-1:0] ch_cfg_i = '0;
  logic   [NumChannels*32-1:0] src_addr_i = '0;
  logic   [NumChannels*32-1:0] dst_addr_i = '0;
  logic   [NumChannels*32-1:0] byte_count_i = '0;
  logic   [NumChannels*32-1:0] request_sel_i = '0;
  logic   [NumChannels*32-1:0] burst_cfg_i = '0;
  logic   [NumChannels*32-1:0] tcd_head_i = '0;
  logic   [NumChannels*32-1:0] tcd_count_i = '0;
  logic   [NumChannels*32-1:0] crc_expected_i = '0;
  logic   [   NumChannels-1:0] start_i = '0;
  logic   [   NumChannels-1:0] suspend_i = '0;
  logic   [   NumChannels-1:0] resume_i = '0;
  logic   [   NumChannels-1:0] abort_i = '0;
  logic   [   NumChannels-1:0] channel_reset_i = '0;
  logic   [ NumChannels*3-1:0] event_clear_i = '0;
  logic   [   NumChannels-1:0] busy_o;
  logic   [   NumChannels-1:0] suspended_o;
  logic   [   NumChannels-1:0] done_o;
  logic   [   NumChannels-1:0] aborted_o;
  logic   [   NumChannels-1:0] error_o;
  logic   [   NumChannels-1:0] stream_last_o;
  logic   [ NumChannels*3-1:0] event_status_o;
  logic   [NumChannels*32-1:0] error_status_o;
  logic   [NumChannels*32-1:0] error_addr_o;
  logic   [NumChannels*32-1:0] current_src_o;
  logic   [NumChannels*32-1:0] current_dst_o;
  logic   [NumChannels*32-1:0] remaining_o;
  logic   [NumChannels*32-1:0] bytes_done_o;
  logic   [NumChannels*32-1:0] stall_cycles_lo_o;
  logic   [NumChannels*32-1:0] stall_cycles_hi_o;
  logic   [NumChannels*32-1:0] crc_result_o;
  logic                        first_error_valid_o;
  logic   [               1:0] first_error_channel_o;
  logic   [               8:0] first_error_status_o;
  logic   [              15:0] first_error_addr_hi_o;
  logic   [              15:0] request_status_o;
  logic                        xpi_xfer_done_o;

  integer                      ar_mismatch = 0;
  integer                      aw_mismatch = 0;
  integer                      w_mismatch = 0;
  integer                      ar_checked = 0;
  integer                      aw_checked = 0;
  integer                      w_checked = 0;
  logic   [               2:0] write_channel_q = '0;
  logic                        write_active_q = 1'b0;
  logic                        read_active_q = 1'b0;
  logic   [               4:0] read_beats_q = '0;
  logic   [               4:0] read_index_q = '0;
  logic   [              31:0] read_addr_q = '0;
  logic   [               4:0] write_beats_q = '0;
  logic   [               4:0] write_index_q = '0;
  logic                        write_response_q = 1'b0;

  dma_req_if req ();
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .USER_WIDTH(4)
  ) axi4 (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );
  axi4_stream_if i2s_tx_axis (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );
  axi4_stream_if i2s_rx_axis (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );
  axi4_stream_if dvp_rx_axis (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );
  axi4_stream_if crypto_in_axis (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );
  axi4_stream_if crypto_out_axis (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );

  always #5 clk_i = ~clk_i;

  assign axi4.arready           = !read_active_q;
  assign axi4.rvalid            = read_active_q;
  assign axi4.rid               = '0;
  assign axi4.rdata             = 32'hA500_0000 + ((read_addr_q - SourceBase) >> 2) + read_index_q;
  assign axi4.rresp             = `AXI4_RESP_OKAY;
  assign axi4.rlast             = (read_index_q + 1'b1) == read_beats_q;
  assign axi4.ruser             = '0;

  assign axi4.awready           = !write_active_q && !write_response_q;
  assign axi4.wready            = write_active_q;
  assign axi4.bid               = '0;
  assign axi4.bresp             = `AXI4_RESP_OKAY;
  assign axi4.buser             = '0;
  assign axi4.bvalid            = write_response_q;

  assign i2s_tx_axis.tready     = 1'b0;
  assign i2s_rx_axis.tdata      = '0;
  assign i2s_rx_axis.tkeep      = '0;
  assign i2s_rx_axis.tstrb      = '0;
  assign i2s_rx_axis.tlast      = 1'b0;
  assign i2s_rx_axis.tid        = '0;
  assign i2s_rx_axis.tdest      = '0;
  assign i2s_rx_axis.tuser      = '0;
  assign i2s_rx_axis.tvalid     = 1'b0;
  assign dvp_rx_axis.tdata      = '0;
  assign dvp_rx_axis.tkeep      = '0;
  assign dvp_rx_axis.tstrb      = '0;
  assign dvp_rx_axis.tlast      = 1'b0;
  assign dvp_rx_axis.tid        = '0;
  assign dvp_rx_axis.tdest      = '0;
  assign dvp_rx_axis.tuser      = '0;
  assign dvp_rx_axis.tvalid     = 1'b0;
  assign crypto_in_axis.tready  = 1'b0;
  assign crypto_out_axis.tdata  = '0;
  assign crypto_out_axis.tkeep  = '0;
  assign crypto_out_axis.tstrb  = '0;
  assign crypto_out_axis.tlast  = 1'b0;
  assign crypto_out_axis.tid    = '0;
  assign crypto_out_axis.tdest  = '0;
  assign crypto_out_axis.tuser  = '0;
  assign crypto_out_axis.tvalid = 1'b0;

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      read_active_q    <= 1'b0;
      read_addr_q      <= '0;
      read_beats_q     <= '0;
      read_index_q     <= '0;
      write_active_q   <= 1'b0;
      write_channel_q  <= '0;
      write_beats_q    <= '0;
      write_index_q    <= '0;
      write_response_q <= 1'b0;
    end else begin
      if (axi4.arvalid && axi4.arready) begin
        read_active_q <= 1'b1;
        read_addr_q   <= axi4.araddr;
        read_beats_q  <= {1'b0, axi4.arlen} + 5'd1;
        read_index_q  <= '0;
      end else if (axi4.rvalid && axi4.rready && axi4.rlast) begin
        read_active_q <= 1'b0;
      end else if (axi4.rvalid && axi4.rready) begin
        read_index_q <= read_index_q + 5'd1;
      end
      if (axi4.awvalid && axi4.awready) begin
        write_active_q   <= 1'b1;
        write_channel_q  <= axi4.awuser[2:0];
        write_beats_q    <= {1'b0, axi4.awlen} + 5'd1;
        write_index_q    <= '0;
        write_response_q <= 1'b0;
      end else if (axi4.wvalid && axi4.wready && axi4.wlast) begin
        write_active_q   <= 1'b0;
        write_response_q <= 1'b1;
      end else if (axi4.wvalid && axi4.wready) begin
        write_index_q <= write_index_q + 5'd1;
      end else if (axi4.bvalid && axi4.bready) begin
        write_response_q <= 1'b0;
      end
    end
  end

  always_ff @(posedge clk_i) begin
    if (rst_n_i) begin
      if (axi4.arvalid && axi4.arready) begin
        ar_checked <= ar_checked + 1;
        if (axi4.aruser !== {1'b1, 3'((axi4.araddr - SourceBase) >> 12)}) begin
          ar_mismatch <= ar_mismatch + 1;
        end
      end
      if (axi4.awvalid && axi4.awready) begin
        aw_checked <= aw_checked + 1;
        if (axi4.awuser !== {1'b1, 3'((axi4.awaddr - DestinationBase) >> 12)}) begin
          aw_mismatch <= aw_mismatch + 1;
        end
      end
      if (axi4.wvalid && axi4.wready) begin
        w_checked <= w_checked + 1;
        if (axi4.wuser !== {1'b1, write_channel_q}) begin
          w_mismatch <= w_mismatch + 1;
        end
      end
    end
  end

  dma_core #(
      .NumChannels          (NumChannels),
      .MaxBurstBeats        (16),
      .FifoDepth            (16),
      .EnableOriginQualifier(1'b1)
  ) u_dma_core (
      .clk_i                (clk_i),
      .rst_n_i              (rst_n_i),
      .global_reset_i       (1'b0),
      .global_error_clear_i (1'b0),
      .ch_cfg_i             (ch_cfg_i),
      .tcd_head_i           (tcd_head_i),
      .tcd_count_i          (tcd_count_i),
      .crc_expected_i       (crc_expected_i),
      .src_addr_i           (src_addr_i),
      .dst_addr_i           (dst_addr_i),
      .byte_count_i         (byte_count_i),
      .request_sel_i        (request_sel_i),
      .burst_cfg_i          (burst_cfg_i),
      .start_i              (start_i),
      .suspend_i            (suspend_i),
      .resume_i             (resume_i),
      .abort_i              (abort_i),
      .channel_reset_i      (channel_reset_i),
      .event_clear_i        (event_clear_i),
      .busy_o               (busy_o),
      .suspended_o          (suspended_o),
      .done_o               (done_o),
      .aborted_o            (aborted_o),
      .error_o              (error_o),
      .stream_last_o        (stream_last_o),
      .event_status_o       (event_status_o),
      .error_status_o       (error_status_o),
      .error_addr_o         (error_addr_o),
      .current_src_o        (current_src_o),
      .current_dst_o        (current_dst_o),
      .remaining_o          (remaining_o),
      .bytes_done_o         (bytes_done_o),
      .stall_cycles_lo_o    (stall_cycles_lo_o),
      .stall_cycles_hi_o    (stall_cycles_hi_o),
      .crc_result_o         (crc_result_o),
      .first_error_valid_o  (first_error_valid_o),
      .first_error_channel_o(first_error_channel_o),
      .first_error_status_o (first_error_status_o),
      .first_error_addr_hi_o(first_error_addr_hi_o),
      .request_status_o     (request_status_o),
      .xpi_xfer_done_o      (xpi_xfer_done_o),
      .req                  (req),
      .axi4                 (axi4),
      .i2s_tx_axis          (i2s_tx_axis),
      .i2s_rx_axis          (i2s_rx_axis),
      .dvp_rx_axis          (dvp_rx_axis),
      .crypto_in_axis       (crypto_in_axis),
      .crypto_out_axis      (crypto_out_axis),
      .spi_admit_ready_i    (2'b00)
  );

  task automatic configure_channel(input integer channel, input logic [31:0] byte_count);
    begin
      ch_cfg_i[(channel*32)+:32]      = {22'd0, 2'd1, 1'b1, 1'b1, 2'd2, 1'b0, 3'd0};
      src_addr_i[(channel*32)+:32]    = SourceBase + (32'(channel) << 12);
      dst_addr_i[(channel*32)+:32]    = DestinationBase + (32'(channel) << 12);
      byte_count_i[(channel*32)+:32]  = byte_count;
      request_sel_i[(channel*32)+:32] = 32'd0;
      burst_cfg_i[(channel*32)+:32]   = {27'd0, 5'd1};
    end
  endtask

  task automatic wait_done(input integer channel);
    integer timeout;
    begin
      timeout = 0;
      while (!done_o[channel] && !error_o[channel] && (timeout < 100000)) begin
        @(posedge clk_i);
        timeout = timeout + 1;
      end
      if (timeout >= 100000) $fatal(1, "channel %0d never completed", channel);
    end
  endtask

  initial begin
    req.i2s_tx_proc     = 1'b1;
    req.i2s_rx_proc     = 1'b1;
    req.qspi_tx_proc    = 1'b1;
    req.qspi_rx_proc    = 1'b1;
    req.uart_tx_proc    = 1'b1;
    req.uart_rx_proc    = 1'b1;
    req.i2c0_tx_proc    = 1'b1;
    req.i2c0_rx_proc    = 1'b1;
    req.i2c1_tx_proc    = 1'b1;
    req.i2c1_rx_proc    = 1'b1;
    req.crypto_in_proc  = 1'b1;
    req.crypto_out_proc = 1'b1;
    repeat (3) @(posedge clk_i);
    rst_n_i = 1'b1;
    repeat (4) @(posedge clk_i);

    // Idle arbiter: one single-beat job on nonzero channel 2.
    configure_channel(2, 32'd4);
    @(negedge clk_i);
    start_i[2] = 1'b1;
    @(negedge clk_i);
    start_i[2] = 1'b0;
    wait_done(2);

    // Contended arbiter: three channels rotate single-beat bursts.
    configure_channel(1, 32'd64);
    configure_channel(2, 32'd64);
    configure_channel(3, 32'd64);
    @(negedge clk_i);
    start_i[1] = 1'b1;
    start_i[2] = 1'b1;
    start_i[3] = 1'b1;
    @(negedge clk_i);
    start_i = '0;
    wait_done(1);
    wait_done(2);
    wait_done(3);

    if ((ar_checked == 0) || (aw_checked == 0) || (w_checked == 0)) begin
      $fatal(1, "origin checks never ran");
    end
    if ((ar_mismatch != 0) || (aw_mismatch != 0) || (w_mismatch != 0) || (error_o != '0)) begin
      $fatal(1, "origin mismatch ar=%0d aw=%0d w=%0d", ar_mismatch, aw_mismatch, w_mismatch);
    end
    $display("DMA origin qualifier staging test passed ar=%0d aw=%0d w=%0d", ar_checked,
             aw_checked, w_checked);
    $finish;
  end

  initial begin
    repeat (1000000) @(posedge clk_i);
    $fatal(1, "SIM_TEST_TIMEOUT DMA origin");
  end
endmodule
