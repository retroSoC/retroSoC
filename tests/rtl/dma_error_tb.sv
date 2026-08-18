`timescale 1ns / 1ps

module dma_error_tb;
  localparam int NumChannels = 4;
  localparam logic [31:0] SourceBase = 32'h4000_0000;
  localparam logic [31:0] CopySource = 32'h4000_0FF0;
  localparam logic [31:0] CopyDestination = 32'h4000_2000;
  localparam logic [31:0] ErrorSource = 32'hDEAD_0000;
  localparam logic [31:0] StreamSource = 32'h4000_3000;
  localparam logic [31:0] StreamDestination = 32'h4000_4000;

  logic                        clk_i = 1'b0;
  logic                        rst_n_i = 1'b0;
  logic   [NumChannels*32-1:0] ch_cfg_i = '0;
  logic   [NumChannels*32-1:0] src_addr_i = '0;
  logic   [NumChannels*32-1:0] dst_addr_i = '0;
  logic   [NumChannels*32-1:0] byte_count_i = '0;
  logic   [NumChannels*32-1:0] request_sel_i = '0;
  logic   [NumChannels*32-1:0] burst_cfg_i = '0;
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
  logic                        first_error_valid_o;
  logic   [               1:0] first_error_channel_o;
  logic   [              31:0] first_error_status_o;
  logic   [              31:0] first_error_addr_o;
  logic   [              15:0] request_status_o;
  logic                        xpi_xfer_done_o;
  logic                        error_mode = 1'b0;
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
  integer                      write_count = 0;
  integer                      read_burst_count = 0;
  integer                      write_burst_count = 0;
  integer                      max_read_beats = 0;
  integer                      max_write_beats = 0;
  integer                      stream_tx_count = 0;
  integer                      stream_rx_count = 0;
  logic   [              31:0] written_addr                     [0:127];
  logic   [              31:0] written_data                     [0:127];
  logic   [              31:0] stream_tx_data                   [  0:7];
  logic                        stream_tx_last                   [  0:7];
  logic                        rx_driver_valid_q = 1'b0;
  logic   [              31:0] rx_driver_data_q = 32'h5100_0000;
  logic   [               3:0] rx_driver_keep_q = 4'hF;
  logic                        rx_driver_last_q = 1'b0;
  logic                        stream_tx_ready_enable = 1'b1;
  logic                        write_accept_enable = 1'b1;

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

  always #5 clk_i = ~clk_i;

  function automatic logic [31:0] model_read_data(input logic [31:0] address);
    model_read_data = 32'hA500_0000 + ((address - SourceBase) >> 2);
  endfunction

  assign axi4.arready = !read_active_q && cycle_q[0];
  assign axi4.rvalid = read_active_q && cycle_q[1];
  assign axi4.rid = '0;
  assign axi4.rdata = model_read_data(read_addr_q + (read_index_q << 2));
  assign axi4.rresp =
      error_mode && (read_addr_q == ErrorSource) ? `AXI4_RESP_DECODE_ERROR : `AXI4_RESP_OKAY;
  assign axi4.rlast = (read_index_q + 1'b1) == read_beats_q;
  assign axi4.ruser = '0;

  assign axi4.awready = write_accept_enable && !write_active_q && !write_response_q && cycle_q[0];
  assign axi4.wready = write_active_q && cycle_q[1];
  assign axi4.bid = '0;
  assign axi4.bresp = `AXI4_RESP_OKAY;
  assign axi4.buser = '0;
  assign axi4.bvalid = write_response_q && cycle_q[0];

  assign i2s_tx_axis.tready = stream_tx_ready_enable && cycle_q[0];
  assign i2s_rx_axis.tdata = rx_driver_data_q;
  assign i2s_rx_axis.tkeep = rx_driver_keep_q;
  assign i2s_rx_axis.tstrb = 4'hF;
  assign i2s_rx_axis.tlast = rx_driver_last_q;
  assign i2s_rx_axis.tid = '0;
  assign i2s_rx_axis.tdest = '0;
  assign i2s_rx_axis.tuser = '0;
  assign i2s_rx_axis.tvalid = rx_driver_valid_q;
  assign dvp_rx_axis.tdata = '0;
  assign dvp_rx_axis.tkeep = '0;
  assign dvp_rx_axis.tstrb = '0;
  assign dvp_rx_axis.tlast = 1'b0;
  assign dvp_rx_axis.tid = '0;
  assign dvp_rx_axis.tdest = '0;
  assign dvp_rx_axis.tuser = '0;
  assign dvp_rx_axis.tvalid = 1'b0;

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      cycle_q           <= '0;
      read_active_q     <= 1'b0;
      read_addr_q       <= '0;
      read_beats_q      <= '0;
      read_index_q      <= '0;
      write_active_q    <= 1'b0;
      write_addr_q      <= '0;
      write_beats_q     <= '0;
      write_index_q     <= '0;
      write_response_q  <= 1'b0;
      write_count       <= 0;
      read_burst_count  <= 0;
      write_burst_count <= 0;
      max_read_beats    <= 0;
      max_write_beats   <= 0;
    end else begin
      cycle_q <= cycle_q + 1'b1;
      if (axi4.arvalid && axi4.arready) begin
        read_active_q    <= 1'b1;
        read_addr_q      <= axi4.araddr;
        read_beats_q     <= axi4.arlen + 1'b1;
        read_index_q     <= '0;
        read_burst_count <= read_burst_count + 1;
        if ((axi4.arlen + 1) > max_read_beats) begin
          max_read_beats <= axi4.arlen + 1;
        end
      end
      if (axi4.rvalid && axi4.rready) begin
        if (axi4.rlast) begin
          read_active_q <= 1'b0;
        end else begin
          read_index_q <= read_index_q + 1'b1;
        end
      end
      if (axi4.awvalid && axi4.awready) begin
        write_active_q    <= 1'b1;
        write_addr_q      <= axi4.awaddr;
        write_beats_q     <= axi4.awlen + 1'b1;
        write_index_q     <= '0;
        write_burst_count <= write_burst_count + 1;
        if ((axi4.awlen + 1) > max_write_beats) begin
          max_write_beats <= axi4.awlen + 1;
        end
      end
      if (axi4.wvalid && axi4.wready) begin
        written_addr[write_count] <= write_addr_q + (write_index_q << 2);
        written_data[write_count] <= axi4.wdata;
        write_count               <= write_count + 1;
        if (axi4.wlast) begin
          if ((write_index_q + 1'b1) != write_beats_q) begin
            $fatal(1, "AXI WLAST did not match the declared burst length");
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
    end
  end

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      stream_tx_count   <= 0;
      stream_rx_count   <= 0;
      rx_driver_valid_q <= 1'b0;
      rx_driver_data_q  <= 32'h5100_0000;
    end else begin
      if (i2s_tx_axis.tvalid && i2s_tx_axis.tready) begin
        stream_tx_data[stream_tx_count] <= i2s_tx_axis.tdata;
        stream_tx_last[stream_tx_count] <= i2s_tx_axis.tlast;
        stream_tx_count                 <= stream_tx_count + 1;
      end
      if (i2s_rx_axis.tvalid && i2s_rx_axis.tready) begin
        stream_rx_count <= stream_rx_count + 1;
      end
    end
  end

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
      .first_error_valid_o  (first_error_valid_o),
      .first_error_channel_o(first_error_channel_o),
      .first_error_status_o (first_error_status_o),
      .first_error_addr_o   (first_error_addr_o),
      .request_status_o     (request_status_o),
      .xpi_xfer_done_o      (xpi_xfer_done_o),
      .req                  (req),
      .axi4                 (axi4),
      .i2s_tx_axis          (i2s_tx_axis),
      .i2s_rx_axis          (i2s_rx_axis),
      .dvp_rx_axis          (dvp_rx_axis)
  );

  task automatic configure_channel(input integer channel, input logic [2:0] kind,
                                   input logic [3:0] request, input logic [31:0] source,
                                   input logic source_increment, input logic [31:0] destination,
                                   input logic destination_increment, input logic [31:0] byte_count,
                                   input logic [1:0] priority_i, input logic [4:0] burst_beats);
    begin
      ch_cfg_i[(channel*32)+:32] = {
        22'd0, priority_i, destination_increment, source_increment, 2'd2, 1'b0, kind
      };
      src_addr_i[(channel*32)+:32] = source;
      dst_addr_i[(channel*32)+:32] = destination;
      byte_count_i[(channel*32)+:32] = byte_count;
      request_sel_i[(channel*32)+:32] = {28'd0, request};
      burst_cfg_i[(channel*32)+:32] = {27'd0, burst_beats};
    end
  endtask

  task automatic start_channel(input integer channel);
    begin
      @(negedge clk_i);
      start_i[channel] = 1'b1;
      @(negedge clk_i);
      start_i[channel] = 1'b0;
    end
  endtask

  task automatic wait_terminal(input integer channel);
    integer timeout;

    begin
      timeout = 0;
      while (!done_o[channel] && !error_o[channel] && !aborted_o[channel]) begin
        @(posedge clk_i);
        timeout = timeout + 1;
        if (timeout > 1000) begin
          $fatal(1, "DMA channel %0d timed out", channel);
        end
      end
      @(negedge clk_i);
    end
  endtask

  task automatic drive_rx_beat(input logic [31:0] data, input logic [3:0] keep, input logic last);
    begin
      @(negedge clk_i);
      rx_driver_data_q  = data;
      rx_driver_keep_q  = keep;
      rx_driver_last_q  = last;
      rx_driver_valid_q = 1'b1;
      do begin
        @(posedge clk_i);
      end while (!i2s_rx_axis.tready);
      @(negedge clk_i);
      rx_driver_valid_q = 1'b0;
    end
  endtask

  initial begin
    integer        write_before;
    logic   [31:0] stalled_stream_data;
    logic          stalled_stream_last;

    req.i2s_tx_proc  = 1'b1;
    req.i2s_rx_proc  = 1'b1;
    req.qspi_tx_proc = 1'b1;
    req.qspi_rx_proc = 1'b1;
    req.uart_tx_proc = 1'b1;
    req.uart_rx_proc = 1'b1;
    req.i2c0_tx_proc = 1'b1;
    req.i2c0_rx_proc = 1'b1;
    req.i2c1_tx_proc = 1'b1;
    req.i2c1_rx_proc = 1'b1;
    repeat (3) @(posedge clk_i);
    rst_n_i = 1'b1;

    configure_channel(0, 3'd0, 4'd0, CopySource, 1'b1, CopyDestination, 1'b1, 32'd80, 2'd1, 5'd16);
    start_channel(0);
    wait_terminal(0);
    if (error_o[0] || (write_count != 20) || (max_read_beats != 16) ||
        (max_write_beats != 16) || (read_burst_count < 2) || (write_burst_count < 2) ||
        (bytes_done_o[0 +: 32] != 32'd80)) begin
      $fatal(1, "DMA copy count=%0d max-r=%0d max-w=%0d reads=%0d writes=%0d done=%0d error=%b",
             write_count, max_read_beats, max_write_beats, read_burst_count, write_burst_count,
             bytes_done_o[0+:32], error_o[0]);
    end
    for (integer index = 0; index < 20; index++) begin
      if ((written_addr[index] != (CopyDestination + (index * 4))) ||
          (written_data[index] != model_read_data(
              CopySource + (index * 4)
          ))) begin
        $fatal(1, "DMA copy data mismatch at beat %0d", index);
      end
    end

    error_mode = 1'b1;
    configure_channel(1, 3'd0, 4'd0, ErrorSource, 1'b1, 32'h4000_5000, 1'b1, 32'd4, 2'd3, 5'd1);
    start_channel(1);
    wait_terminal(1);
    if (!error_o[1] || !first_error_valid_o || (first_error_channel_o != 2'd1) ||
        (write_count != 20)) begin
      $fatal(1, "DMA read error was not isolated to its channel");
    end
    error_mode = 1'b0;

    configure_channel(2, 3'd1, 4'd1, StreamSource, 1'b1, 32'd0, 1'b0, 32'd8, 2'd2, 5'd16);
    start_channel(2);
    wait_terminal(2);
    if (error_o[2] || (stream_tx_count != 2) || !stream_tx_last[1] ||
        (stream_tx_data[0] != model_read_data(
            StreamSource
        )) || (stream_tx_data[1] != model_read_data(
            StreamSource + 32'd4
        ))) begin
      $fatal(1, "DMA AXI4-Stream TX did not obey backpressure or TLAST");
    end

    configure_channel(3, 3'd2, 4'd2, 32'd0, 1'b0, StreamDestination, 1'b1, 32'd8, 2'd2, 5'd16);
    stream_rx_count = 0;
    start_channel(3);
    drive_rx_beat(32'h5100_0000, 4'hF, 1'b0);
    drive_rx_beat(32'h5100_0001, 4'hF, 1'b1);
    wait_terminal(3);
    if (error_o[3] || (stream_rx_count != 2) || !stream_last_o[3] ||
        (written_data[20] != 32'h5100_0000) || (written_data[21] != 32'h5100_0001)) begin
      $fatal(1, "DMA AXI4-Stream RX did not write the programmed byte count");
    end

    stream_tx_ready_enable = 1'b0;
    configure_channel(2, 3'd1, 4'd1, StreamSource + 32'h100, 1'b1, 32'd0, 1'b0, 32'd8, 2'd2, 5'd16);
    start_channel(2);
    wait (i2s_tx_axis.tvalid);
    @(negedge clk_i);
    stalled_stream_data = i2s_tx_axis.tdata;
    stalled_stream_last = i2s_tx_axis.tlast;
    abort_i[2]          = 1'b1;
    @(negedge clk_i);
    abort_i[2] = 1'b0;
    repeat (3) begin
      @(posedge clk_i);
      if (!i2s_tx_axis.tvalid || (i2s_tx_axis.tdata != stalled_stream_data) ||
          (i2s_tx_axis.tlast != stalled_stream_last)) begin
        $fatal(1, "DMA abort unstable: valid=%b data=%h/%h last=%b/%b busy=%b abort=%b stop=%b",
               i2s_tx_axis.tvalid, i2s_tx_axis.tdata, stalled_stream_data, i2s_tx_axis.tlast,
               stalled_stream_last, busy_o[2], u_dma_core.s_abort_q[2],
               u_dma_core.s_stream_tx_stop_q[2]);
      end
    end
    stream_tx_ready_enable = 1'b1;
    wait_terminal(2);
    if (!aborted_o[2] || done_o[2]) begin
      $fatal(1, "DMA stream abort did not terminate as aborted");
    end

    write_accept_enable = 1'b0;
    configure_channel(3, 3'd2, 4'd2, 32'd0, 1'b0, StreamDestination + 32'h100, 1'b1, 32'd8, 2'd2,
                      5'd16);
    start_channel(3);
    drive_rx_beat(32'h6100_0000, 4'hF, 1'b0);
    drive_rx_beat(32'h6100_0001, 4'h3, 1'b1);
    wait (error_o[3]);
    wait (!busy_o[3]);
    write_accept_enable = 1'b1;
    write_before        = write_count;
    configure_channel(3, 3'd2, 4'd2, 32'd0, 1'b0, StreamDestination + 32'h200, 1'b1, 32'd4, 2'd2,
                      5'd1);
    start_channel(3);
    drive_rx_beat(32'h6200_0000, 4'hF, 1'b1);
    wait_terminal(3);
    if (error_o[3] || (write_count != (write_before + 1)) ||
        (written_data[write_before] != 32'h6200_0000)) begin
      $fatal(1, "DMA retained stale stream data after a TKEEP error");
    end

    $display("DMA native AXI4 burst, backpressure, stream, and error test passed");
    $finish;
  end
endmodule
