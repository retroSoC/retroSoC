`timescale 1ns / 1ps

module dma_crypto_tb;
  import dma_pkg::*;

  localparam int NumChannels = 6;
  localparam logic [31:0] SourceBase = 32'h4000_0000;
  localparam logic [31:0] DestinationBase = 32'h4000_1000;
  localparam logic [31:0] TransferBytes = 32'd64;

  logic                        clk_i = 1'b0;
  logic                        rst_n_i = 1'b0;
  logic   [NumChannels*32-1:0] ch_cfg_i = '0;
  logic   [NumChannels*32-1:0] src_addr_i = '0;
  logic   [NumChannels*32-1:0] dst_addr_i = '0;
  logic   [NumChannels*32-1:0] byte_count_i = '0;
  logic   [NumChannels*32-1:0] request_sel_i = '0;
  logic   [NumChannels*32-1:0] burst_cfg_i = '0;
  logic   [   NumChannels-1:0] start_i = '0;
  logic   [   NumChannels-1:0] busy_o;
  logic   [   NumChannels-1:0] done_o;
  logic   [   NumChannels-1:0] error_o;
  logic   [NumChannels*32-1:0] bytes_done_o;
  logic   [              31:0] cycle_q = '0;
  logic                        read_active_q = 1'b0;
  logic   [              31:0] read_addr_q = '0;
  logic   [               4:0] read_beats_q = '0;
  logic   [               4:0] read_index_q = '0;
  logic                        write_active_q = 1'b0;
  logic   [              31:0] write_addr_q = '0;
  logic   [               4:0] write_beats_q = '0;
  logic   [               4:0] write_index_q = '0;
  logic                        write_response_q = 1'b0;
  logic                        stream_last_seen_q = 1'b0;
  integer                      write_count = 0;

  dma_req_if req ();
  axi4_if axi4 (
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

  assign req.i2s_tx_proc        = 1'b1;
  assign req.i2s_rx_proc        = 1'b1;
  assign req.qspi_tx_proc       = 1'b1;
  assign req.qspi_rx_proc       = 1'b1;
  assign req.uart_tx_proc       = 1'b1;
  assign req.uart_rx_proc       = 1'b1;
  assign req.i2c0_tx_proc       = 1'b1;
  assign req.i2c0_rx_proc       = 1'b1;
  assign req.i2c1_tx_proc       = 1'b1;
  assign req.i2c1_rx_proc       = 1'b1;
  assign req.crypto_in_proc     = 1'b1;
  assign req.crypto_out_proc    = 1'b1;

  assign axi4.arready           = !read_active_q && cycle_q[0];
  assign axi4.rid               = '0;
  assign axi4.rdata             = 32'hcafe_0000 | ((read_addr_q - SourceBase) >> 2) | read_index_q;
  assign axi4.rresp             = `AXI4_RESP_OKAY;
  assign axi4.rlast             = (read_index_q + 1'b1) == read_beats_q;
  assign axi4.ruser             = '0;
  assign axi4.rvalid            = read_active_q;
  assign axi4.awready           = !write_active_q && !write_response_q && cycle_q[0];
  assign axi4.wready            = write_active_q && cycle_q[1];
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

  assign crypto_in_axis.tready  = crypto_out_axis.tready && cycle_q[0];
  assign crypto_out_axis.tdata  = crypto_in_axis.tdata;
  assign crypto_out_axis.tkeep  = crypto_in_axis.tkeep;
  assign crypto_out_axis.tstrb  = crypto_in_axis.tstrb;
  assign crypto_out_axis.tlast  = crypto_in_axis.tlast;
  assign crypto_out_axis.tid    = crypto_in_axis.tid;
  assign crypto_out_axis.tdest  = crypto_in_axis.tdest;
  assign crypto_out_axis.tuser  = crypto_in_axis.tuser;
  assign crypto_out_axis.tvalid = crypto_in_axis.tvalid && cycle_q[0];

  dma_core #(
      .NumChannels  (NumChannels),
      .MaxBurstBeats(16),
      .FifoDepth    (16)
  ) u_dma_core (
      .clk_i                (clk_i),
      .rst_n_i              (rst_n_i),
      .global_reset_i       (1'b0),
      .global_error_clear_i (1'b0),
      .ch_cfg_i             (ch_cfg_i),
      .src_addr_i           (src_addr_i),
      .dst_addr_i           (dst_addr_i),
      .byte_count_i         (byte_count_i),
      .request_sel_i        (request_sel_i),
      .burst_cfg_i          (burst_cfg_i),
      .start_i              (start_i),
      .suspend_i            ('0),
      .resume_i             ('0),
      .abort_i              ('0),
      .channel_reset_i      ('0),
      .event_clear_i        ('0),
      .busy_o               (busy_o),
      .suspended_o          (),
      .done_o               (done_o),
      .aborted_o            (),
      .error_o              (error_o),
      .stream_last_o        (),
      .event_status_o       (),
      .error_status_o       (),
      .error_addr_o         (),
      .current_src_o        (),
      .current_dst_o        (),
      .remaining_o          (),
      .bytes_done_o         (bytes_done_o),
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

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      cycle_q            <= '0;
      read_active_q      <= 1'b0;
      write_active_q     <= 1'b0;
      write_response_q   <= 1'b0;
      stream_last_seen_q <= 1'b0;
      write_count        <= 0;
    end else begin
      cycle_q <= cycle_q + 1'b1;
      if (axi4.arvalid && axi4.arready) begin
        read_active_q <= 1'b1;
        read_addr_q   <= axi4.araddr;
        read_beats_q  <= axi4.arlen + 1'b1;
        read_index_q  <= '0;
      end
      if (axi4.rvalid && axi4.rready) begin
        if (axi4.rlast) begin
          read_active_q <= 1'b0;
        end else begin
          read_index_q <= read_index_q + 1'b1;
        end
      end
      if (axi4.awvalid && axi4.awready) begin
        write_active_q <= 1'b1;
        write_addr_q   <= axi4.awaddr;
        write_beats_q  <= axi4.awlen + 1'b1;
        write_index_q  <= '0;
      end
      if (axi4.wvalid && axi4.wready) begin
        if ((write_addr_q + (write_index_q << 2)) != (DestinationBase + (write_count * 4))) begin
          $fatal(1, "crypto DMA write address mismatch");
        end
        if (axi4.wdata != (32'hcafe_0000 | write_count)) begin
          $fatal(1, "crypto DMA write data mismatch: %h at %0d", axi4.wdata, write_count);
        end
        write_count <= write_count + 1;
        if (axi4.wlast) begin
          if ((write_index_q + 1'b1) != write_beats_q) begin
            $fatal(1, "crypto DMA WLAST mismatch");
          end
          write_active_q   <= 1'b0;
          write_response_q <= 1'b1;
        end else begin
          write_index_q <= write_index_q + 1'b1;
        end
      end
      if (axi4.bvalid && axi4.bready) begin
        write_response_q <= 1'b0;
      end
      if (crypto_in_axis.tvalid && crypto_in_axis.tready && crypto_in_axis.tlast) begin
        stream_last_seen_q <= 1'b1;
      end
    end
  end

  initial begin
    integer wait_cycles;

    ch_cfg_i[(4*32)+:32] = {22'd0, 2'd3, 1'b0, 1'b1, DMA_WIDTH_32, 1'b0, DMA_KIND_MM_TO_STREAM};
    src_addr_i[(4*32)+:32] = SourceBase;
    byte_count_i[(4*32)+:32] = TransferBytes;
    request_sel_i[(4*32)+:32] = {28'd0, DMA_REQUEST_CRYPTO_IN};
    burst_cfg_i[(4*32)+:32] = 32'd8;
    ch_cfg_i[(5*32)+:32] = {22'd0, 2'd3, 1'b1, 1'b0, DMA_WIDTH_32, 1'b0, DMA_KIND_STREAM_TO_MM};
    dst_addr_i[(5*32)+:32] = DestinationBase;
    byte_count_i[(5*32)+:32] = TransferBytes;
    request_sel_i[(5*32)+:32] = {28'd0, DMA_REQUEST_CRYPTO_OUT};
    burst_cfg_i[(5*32)+:32] = 32'd8;

    repeat (3) @(posedge clk_i);
    rst_n_i = 1'b1;
    @(negedge clk_i);
    start_i[5:4] = 2'b11;
    @(negedge clk_i);
    start_i     = '0;
    wait_cycles = 0;
    while (!(done_o[4] && done_o[5]) && (wait_cycles < 5000)) begin
      @(posedge clk_i);
      wait_cycles = wait_cycles + 1;
    end
    if (!(done_o[4] && done_o[5])) begin
      $fatal(1, "crypto DMA endpoint test timeout");
    end
    if ((error_o != '0) || (write_count != 16) || !stream_last_seen_q ||
        (bytes_done_o[(4*32)+:32] != TransferBytes) ||
        (bytes_done_o[(5*32)+:32] != TransferBytes)) begin
      $fatal(1, "crypto DMA result mismatch errors=%b writes=%0d last=%b", error_o, write_count,
             stream_last_seen_q);
    end
    $display("DMA crypto channel 4/5 streaming test passed");
    $finish;
  end
endmodule
