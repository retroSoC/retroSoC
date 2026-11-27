`timescale 1ns / 1ps
`include "axi4_define.svh"

module piolite_p3_dma_tb;
  localparam int NumChannels = 8;
  localparam logic [2:0] KindMm = 3'd0;
  localparam logic [2:0] KindTx = 3'd1;
  localparam logic [2:0] KindRx = 3'd2;
  localparam logic [4:0] RequestSoftware = 5'd0;
  localparam logic [4:0] RequestPioliteTx = 5'd14;
  localparam logic [4:0] RequestPioliteRx = 5'd15;

  logic clk_i = 1'b0;
  logic rst_n_i = 1'b0;
  always #5 clk_i = ~clk_i;

  logic [NumChannels*32-1:0] ch_cfg_i = '0;
  logic [NumChannels*32-1:0] src_addr_i = '0;
  logic [NumChannels*32-1:0] dst_addr_i = '0;
  logic [NumChannels*32-1:0] byte_count_i = '0;
  logic [NumChannels*32-1:0] request_sel_i = '0;
  logic [NumChannels*32-1:0] burst_cfg_i = '0;
  logic [NumChannels*32-1:0] tcd_head_i = '0;
  logic [NumChannels*32-1:0] tcd_count_i = '0;
  logic [NumChannels*32-1:0] crc_expected_i = '0;
  logic [   NumChannels-1:0] start_i = '0;
  logic [   NumChannels-1:0] suspend_i = '0;
  logic [   NumChannels-1:0] resume_i = '0;
  logic [   NumChannels-1:0] abort_i = '0;
  logic [   NumChannels-1:0] channel_reset_i = '0;
  logic [ NumChannels*3-1:0] event_clear_i = '0;
  logic                      global_reset_i = 1'b0;
  logic                      global_error_clear_i = 1'b0;
  logic                      ppalite_route_i = 1'b0;
  logic [   NumChannels-1:0] busy_o;
  logic [   NumChannels-1:0] suspended_o;
  logic [   NumChannels-1:0] done_o;
  logic [   NumChannels-1:0] aborted_o;
  logic [   NumChannels-1:0] error_o;
  logic [   NumChannels-1:0] stream_last_o;
  logic [ NumChannels*3-1:0] event_status_o;
  logic [NumChannels*32-1:0] error_status_o;
  logic [NumChannels*32-1:0] error_addr_o;
  logic [NumChannels*32-1:0] current_src_o;
  logic [NumChannels*32-1:0] current_dst_o;
  logic [NumChannels*32-1:0] remaining_o;
  logic [NumChannels*32-1:0] bytes_done_o;
  logic [NumChannels*32-1:0] stall_cycles_lo_o;
  logic [NumChannels*32-1:0] stall_cycles_hi_o;
  logic [NumChannels*32-1:0] crc_result_o;
  logic                      first_error_valid_o;
  logic [               2:0] first_error_channel_o;
  logic [               8:0] first_error_status_o;
  logic [              15:0] first_error_addr_hi_o;
  logic [              31:0] request_status_o;
  logic                      xpi_xfer_done_o;
  logic [               1:0] spi_admit_ready_i = 2'b00;
  logic [               1:0] spi_credit_valid_o;
  logic [               1:0] spi_credit_retire_o;
  logic [               1:0] spi_start_pending_o;
  logic [               3:0] spi_status_o;
  logic                      spi_error_o;
  logic [   NumChannels-1:0] piolite_tx_admit_i = '0;
  logic [   NumChannels-1:0] piolite_rx_admit_i = '0;
  logic [   NumChannels-1:0] piolite_tx_job_o;
  logic [   NumChannels-1:0] piolite_rx_job_o;
  logic [   NumChannels-1:0] channel_busy_o;
  logic [   NumChannels-1:0] channel_start_o;

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
  axi4_stream_if piolite_tx_axis (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );
  axi4_stream_if piolite_rx_axis (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );

  logic   [31:0] memory                                [0:255];
  logic          read_active_q = 1'b0;
  logic   [31:0] read_addr_q = '0;
  logic   [ 4:0] read_beats_q = '0;
  logic   [ 4:0] read_index_q = '0;
  logic          write_active_q = 1'b0;
  logic   [31:0] write_addr_q = '0;
  logic   [ 4:0] write_beats_q = '0;
  logic   [ 4:0] write_index_q = '0;
  logic          write_response_q = 1'b0;
  logic          read_hold = 1'b0;
  logic          address_hold = 1'b0;
  logic          write_hold = 1'b0;
  integer        ar_count = 0;
  integer        unbound_ar_count = 0;
  integer        aw_count = 0;
  integer        pio_tx_count = 0;
  logic   [31:0] pio_tx_words                          [0:255];
  logic          rx_driver_valid_q = 1'b0;
  logic   [31:0] rx_driver_data_q = rx_driver_words[0];
  logic   [31:0] rx_driver_words                       [  0:7];
  integer        rx_driver_index = 0;
  integer        rx_driver_count = 0;
  logic          tx_ready_enable = 1'b1;

  assign axi4.arready           = !read_active_q && !address_hold;
  assign axi4.rvalid            = read_active_q && !read_hold;
  assign axi4.rid               = '0;
  assign axi4.rdata             = memory[read_addr_q[9:2]+read_index_q];
  assign axi4.rresp             = `AXI4_RESP_OKAY;
  assign axi4.rlast             = (read_index_q + 1'b1) == read_beats_q;
  assign axi4.ruser             = '0;
  assign axi4.awready           = !write_active_q && !write_response_q;
  assign axi4.wready            = write_active_q;
  assign axi4.bid               = '0;
  assign axi4.bresp             = `AXI4_RESP_OKAY;
  assign axi4.buser             = '0;
  assign axi4.bvalid            = write_response_q && !write_hold;

  assign piolite_tx_axis.tready = tx_ready_enable;
  assign piolite_rx_axis.tdata  = rx_driver_data_q;
  assign piolite_rx_axis.tkeep  = 4'hf;
  assign piolite_rx_axis.tstrb  = 4'hf;
  assign piolite_rx_axis.tlast  = 1'b0;
  assign piolite_rx_axis.tid    = 1'b0;
  assign piolite_rx_axis.tdest  = 1'b0;
  assign piolite_rx_axis.tuser  = 1'b0;
  assign piolite_rx_axis.tvalid = rx_driver_valid_q;

  assign req.i2s_tx_proc        = 1'b1;
  assign req.i2s_rx_proc        = 1'b1;
  assign req.qspi_tx_proc       = 1'b1;
  assign req.qspi_rx_proc       = 1'b1;
  assign req.uart_tx_proc       = 1'b1;
  assign req.uart_rx_proc       = 1'b1;
  assign req.i2c0_tx_proc       = 1'b1;
  assign req.i2c0_rx_proc       = 1'b1;
  assign req.i2c1_tx_proc       = 1'b0;
  assign req.i2c1_rx_proc       = 1'b0;
  assign req.crypto_in_proc     = 1'b1;
  assign req.crypto_out_proc    = 1'b1;
  assign req.piolite_tx_proc    = piolite_tx_axis.tready;
  assign req.piolite_rx_proc    = piolite_rx_axis.tvalid;
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
      write_addr_q     <= '0;
      write_beats_q    <= '0;
      write_index_q    <= '0;
      write_response_q <= 1'b0;
      ar_count         <= 0;
      aw_count         <= 0;
      pio_tx_count     <= 0;
    end else begin
      if (axi4.arvalid && axi4.arready) begin
        read_active_q <= 1'b1;
        read_addr_q   <= axi4.araddr;
        read_beats_q  <= axi4.arlen + 1'b1;
        read_index_q  <= '0;
        ar_count      <= ar_count + 1;
      end
      if (axi4.rvalid && axi4.rready) begin
        if (axi4.rlast) read_active_q <= 1'b0;
        else read_index_q <= read_index_q + 1'b1;
      end
      if (axi4.awvalid && axi4.awready) begin
        write_active_q <= 1'b1;
        write_addr_q   <= axi4.awaddr;
        write_beats_q  <= axi4.awlen + 1'b1;
        write_index_q  <= '0;
        aw_count       <= aw_count + 1;
      end
      if (axi4.wvalid && axi4.wready) begin
        memory[write_addr_q[9:2]+write_index_q] <= axi4.wdata;
        if (axi4.wlast) begin
          write_active_q   <= 1'b0;
          write_response_q <= 1'b1;
        end else begin
          write_index_q <= write_index_q + 1'b1;
        end
      end
      if (axi4.bvalid && axi4.bready) write_response_q <= 1'b0;
      if (piolite_tx_axis.tvalid && piolite_tx_axis.tready) begin
        $display(
            "P3_TX_TRACE time=%0t count=%0d abort=%b stop=%b busy=%b cv=%b parse=%b start=%b resume=%b",
            $time, pio_tx_count, u_dma_core.s_abort_q, u_dma_core.s_stream_tx_stop_q, busy_o,
            u_dma_core.s_piolite_tx_channel_valid, u_dma_core.s_tcd_parse_q, start_i, resume_i);
        pio_tx_words[pio_tx_count] <= piolite_tx_axis.tdata;
        pio_tx_count               <= pio_tx_count + 1;
      end
    end
  end

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      rx_driver_index   <= 0;
      rx_driver_data_q  <= '0;
      rx_driver_valid_q <= 1'b0;
    end else if (rx_driver_valid_q && piolite_rx_axis.tready) begin
      if ((rx_driver_index + 1) < rx_driver_count) begin
        rx_driver_index   <= rx_driver_index + 1;
        rx_driver_data_q  <= rx_driver_words[rx_driver_index+1];
        rx_driver_valid_q <= 1'b1;
      end else begin
        rx_driver_valid_q <= 1'b0;
      end
    end
  end

  dma_core #(
      .AddrWidth            (32),
      .DataWidth            (32),
      .NumChannels          (NumChannels),
      .MaxBurstBeats        (16),
      .FifoDepth            (32),
      .RequestMask          (32'h0003_f9ff),
      .EnableStreams        (1'b1),
`ifdef PIOLITE_MINI_DEFAULT
      .EnablePiolite        (1'b0),
`else
      .EnablePiolite        (1'b1),
`endif
      .EnableSpi            (1'b1),
      .EnableOriginQualifier(1'b1),
      .EnablePpaliteGuard   (1'b1),
      .SpiTxAddress         (32'h1001_d054),
      .SpiRxAddress         (32'h1001_d058)
  ) u_dma_core (
      .clk_i                (clk_i),
      .rst_n_i              (rst_n_i),
      .global_reset_i       (global_reset_i),
      .global_error_clear_i (global_error_clear_i),
      .ch_cfg_i             (ch_cfg_i),
      .src_addr_i           (src_addr_i),
      .dst_addr_i           (dst_addr_i),
      .byte_count_i         (byte_count_i),
      .request_sel_i        (request_sel_i),
      .burst_cfg_i          (burst_cfg_i),
      .tcd_head_i           (tcd_head_i),
      .tcd_count_i          (tcd_count_i),
      .crc_expected_i       (crc_expected_i),
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
      .ppalite_route_i      (ppalite_route_i),
      .spi_admit_ready_i    (spi_admit_ready_i),
      .spi_credit_valid_o   (spi_credit_valid_o),
      .spi_credit_retire_o  (spi_credit_retire_o),
      .spi_start_pending_o  (spi_start_pending_o),
      .spi_status_o         (spi_status_o),
      .spi_error_o          (spi_error_o),
      .xpi_xfer_done_o      (xpi_xfer_done_o),
      .req                  (req),
      .axi4                 (axi4),
      .i2s_tx_axis          (i2s_tx_axis),
      .i2s_rx_axis          (i2s_rx_axis),
      .dvp_rx_axis          (dvp_rx_axis),
      .crypto_in_axis       (crypto_in_axis),
      .crypto_out_axis      (crypto_out_axis),
      .piolite_tx_axis      (piolite_tx_axis),
      .piolite_rx_axis      (piolite_rx_axis),
      .piolite_tx_admit_i   (piolite_tx_admit_i),
      .piolite_rx_admit_i   (piolite_rx_admit_i),
      .piolite_tx_job_o     (piolite_tx_job_o),
      .piolite_rx_job_o     (piolite_rx_job_o),
      .channel_busy_o       (channel_busy_o),
      .channel_start_o      (channel_start_o)
  );

  task automatic configure(input integer channel, input logic [2:0] kind, input logic [4:0] request,
                           input logic [31:0] source, input logic source_increment,
                           input logic [31:0] destination, input logic destination_increment,
                           input logic [31:0] bytes);
    begin
      ch_cfg_i[channel*32+:32] = {24'd0, destination_increment, source_increment, 2'd2, 1'b0, kind};
      src_addr_i[channel*32+:32] = source;
      dst_addr_i[channel*32+:32] = destination;
      byte_count_i[channel*32+:32] = bytes;
      request_sel_i[channel*32+:32] = {27'd0, request};
      burst_cfg_i[channel*32+:32] = 32'd2;
      tcd_head_i[channel*32+:32] = 32'd0;
      tcd_count_i[channel*32+:32] = 32'd0;
    end
  endtask

  task automatic configure_tcd(input integer channel, input logic [31:0] head,
                               input logic [31:0] count);
    begin
      tcd_head_i[channel*32+:32]  = head;
      tcd_count_i[channel*32+:32] = count;
    end
  endtask

  task automatic start(input integer channel);
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
        if (timeout > 2000) begin
          $fatal(
              1,
              "channel %0d timeout busy=%b suspended=%b abort=%b stop=%b valid=%b bytes=%0d len=%0d read=%b/%0d write=%b/%0d tcd=%b/%b/%b txjob=%b rxjob=%b",
              channel, busy_o[channel], suspended_o[channel], u_dma_core.s_abort_q[channel],
              u_dma_core.s_stream_tx_stop_q[channel], u_dma_core.s_stream_tx_valid[channel],
              u_dma_core.s_bytes_done_q[channel], u_dma_core.s_len_q[channel],
              u_dma_core.s_read_owner_valid_q, u_dma_core.s_read_owner_q,
              u_dma_core.s_write_owner_valid_q, u_dma_core.s_write_owner_q,
              u_dma_core.s_tcd_mode_q[channel], u_dma_core.s_tcd_loaded_q[channel],
              u_dma_core.s_tcd_fetch_pending_q[channel], piolite_tx_job_o[channel],
              piolite_rx_job_o[channel]);
        end
      end
      @(negedge clk_i);
    end
  endtask

  task automatic reset_channel(input integer channel);
    begin
      @(negedge clk_i);
      channel_reset_i[channel] = 1'b1;
      @(negedge clk_i);
      channel_reset_i[channel] = 1'b0;
    end
  endtask

  task automatic make_tcd(input integer index, input logic [31:0] next_ptr, input logic [2:0] kind,
                          input logic [4:0] request, input logic [31:0] source,
                          input logic [31:0] destination, input logic [31:0] bytes);
    begin
      memory[index] = next_ptr;
      memory[index+1] = source;
      memory[index+2] = destination;
      memory[index+3] = bytes;
      memory[index+4] = 32'd0;
      memory[index+5] = 32'd0;
      memory[index+6] = 32'd1;
      memory[index+7] = 32'd1 | (kind << 8) | (request << 12) |
                        ((source != 0) << 1) | ((destination != 0) << 2) | (2 << 20);
      memory[index+8] = 32'd0;
      memory[index+9] = 32'd0;
      for (integer reserved = 10; reserved < 16; reserved++) memory[index+reserved] = 32'd0;
    end
  endtask

  initial begin
    for (integer index = 0; index < 256; index++) memory[index] = 32'hA500_0000 + index;
    for (integer index = 0; index < 8; index++) begin
      pio_tx_words[index]    = 32'd0;
      rx_driver_words[index] = 32'hC001_0000 + index;
    end
    rx_driver_count = 0;
    repeat (5) @(posedge clk_i);
    rst_n_i = 1'b1;

`ifdef PIOLITE_MINI_DEFAULT
    configure(3, KindTx, RequestPioliteTx, 32'h0000_0040, 1'b1, 32'd0, 1'b0, 32'd4);
    piolite_tx_admit_i[3] = 1'b1;
    start(3);
    wait_terminal(3);
    if (!error_o[3] || (ar_count != 0) || piolite_tx_job_o[3]) $fatal(1, "Mini TX enabled");
    configure(2, KindRx, RequestPioliteRx, 32'd0, 1'b0, 32'h0000_0080, 1'b1, 32'd4);
    piolite_rx_admit_i[2] = 1'b1;
    start(2);
    wait_terminal(2);
    if (!error_o[2] || (aw_count != 0) || piolite_rx_job_o[2]) $fatal(1, "Mini RX enabled");
    $display("SIM_TEST_PASS PIOLITE_MINI_DEFAULT_OFF");
    $finish;
`else
    configure(3, KindTx, RequestPioliteTx, 32'h0000_0040, 1'b1, 32'd0, 1'b0, 32'd8);
    piolite_tx_admit_i[3] = 1'b1;
    start(3);
    if (!piolite_tx_job_o[3]) $fatal(1, "direct TX ownership missing");
    wait_terminal(3);
    if (error_o[3] || (pio_tx_count != 2) || (pio_tx_words[0] != 32'hA500_0010) ||
        (pio_tx_words[1] != 32'hA500_0011) || piolite_tx_job_o[3]) begin
      $fatal(1, "direct TX failed");
    end

    rx_driver_count   = 2;
    rx_driver_index   = 0;
    rx_driver_data_q  = rx_driver_words[0];
    rx_driver_valid_q = 1'b1;
    configure(2, KindRx, RequestPioliteRx, 32'd0, 1'b0, 32'h0000_0080, 1'b1, 32'd8);
    piolite_rx_admit_i[2] = 1'b1;
    start(2);
    wait_terminal(2);
    if (error_o[2] || (memory[32] != 32'hC001_0000) || (memory[33] != 32'hC001_0001) ||
        piolite_rx_job_o[2]) begin
      $fatal(
          1,
          "direct RX failed: error=%0d status=%08x word0=%08x word1=%08x job=%0d remaining=%0d accepted=%0d",
          error_o[2], error_status_o[2*32+:32], memory[32], memory[33], piolite_rx_job_o[2],
          remaining_o[2*32+:32], u_dma_core.s_stream_accepted_q[2]);
    end

    make_tcd(96, 32'h0000_01c0, KindMm, RequestSoftware, 32'h0000_0100, 32'h0000_0140, 32'd4);
    make_tcd(112, 32'd0, KindTx, RequestPioliteTx, 32'h0000_0040, 32'd0, 32'd4);
    configure(3, KindMm, RequestSoftware, 32'h0000_0100, 1'b1, 32'h0000_0140, 1'b1, 32'd4);
    configure_tcd(3, 32'h0000_0180, 32'd2);
    start(3);
    if (!piolite_tx_job_o[3]) $fatal(1, "mixed TCD ownership missing");
    wait_terminal(3);
    if (error_o[3] || (pio_tx_count != 3) || (pio_tx_words[2] != 32'hA500_0010)) begin
      $fatal(1, "mixed TCD TX failed");
    end

    configure(4, KindTx, RequestPioliteTx, 32'h0000_0040, 1'b1, 32'd0, 1'b0, 32'd4);
    piolite_tx_admit_i[4] = 1'b0;
    unbound_ar_count      = ar_count;
    start(4);
    wait_terminal(4);
    if (!error_o[4] || (ar_count != unbound_ar_count)) begin
      $fatal(1, "unbound TX was admitted: error=%0d ar_count=%0d status=%08x job=%0d", error_o[4],
             ar_count, error_status_o[4*32+:32], piolite_tx_job_o[4]);
    end

    make_tcd(128, 32'h0000_0200, KindTx, RequestPioliteTx, 32'h0000_0040, 32'd0, 32'd4);
    configure(3, KindMm, RequestSoftware, 32'h0000_0100, 1'b1, 32'h0000_0140, 1'b1, 32'd4);
    configure_tcd(3, 32'h0000_0200, 32'd1);
    read_hold = 1'b1;
    start(3);
    do @(posedge clk_i); while (!(axi4.arvalid && axi4.arready));
    @(negedge clk_i);
    abort_i[3] = 1'b1;
    @(negedge clk_i);
    abort_i[3] = 1'b0;
    read_hold  = 1'b0;
    wait_terminal(3);
    if (!aborted_o[3] || (pio_tx_count != 3) || piolite_tx_job_o[3]) begin
      $fatal(
          1,
          "abort during accepted TCD read failed to drain: aborted=%0d tx_count=%0d job=%0d busy=%0d error=%0d status=%08x",
          aborted_o[3], pio_tx_count, piolite_tx_job_o[3], busy_o[3], error_o[3],
          error_status_o[3*32+:32]);
    end

    make_tcd(144, 32'h0000_0240, KindTx, RequestPioliteTx, 32'h0000_0040, 32'd0, 32'd4);
    configure(3, KindMm, RequestSoftware, 32'h0000_0100, 1'b1, 32'h0000_0140, 1'b1, 32'd4);
    configure_tcd(3, 32'h0000_0240, 32'd1);
    start(3);
    while (!u_dma_core.s_tcd_parse_q) @(negedge clk_i);
    abort_i[3] = 1'b1;
    @(negedge clk_i);
    abort_i[3] = 1'b0;
    wait_terminal(3);
    if (!aborted_o[3] || u_dma_core.s_tcd_loaded_q[3] || (pio_tx_count != 3)) begin
      $fatal(1, "abort during TCD parse activated stale work");
    end

    configure(1, KindMm, RequestSoftware, 32'h0000_0100, 1'b1, 32'h0000_0140, 1'b1, 32'd4);
    start(1);
    wait_terminal(1);
    if (error_o[1] || (memory[80] != memory[64])) $fatal(1, "unrelated channel did not progress");

    rx_driver_count   = 2;
    rx_driver_index   = 0;
    rx_driver_data_q  = rx_driver_words[0];
    rx_driver_valid_q = 1'b1;
    configure(2, KindRx, RequestPioliteRx, 32'd0, 1'b0, 32'h0000_0080, 1'b1, 32'd4);
    piolite_rx_admit_i[2] = 1'b1;
    start(2);
    wait_terminal(2);
    if (!piolite_rx_axis.tvalid || (memory[32] != 32'hC001_0000) ||
        (memory[33] != 32'hC001_0001)) begin
      $fatal(1, "residual RX VALID/count semantics failed");
    end
    if (piolite_rx_axis.tdata != 32'hC001_0001) $fatal(1, "residual RX payload changed");

    configure(1, KindRx, RequestPioliteTx, 32'h0000_0040, 1'b1, 32'h0000_0080, 1'b1, 32'd4);
    piolite_tx_admit_i[1] = 1'b1;
    start(1);
    wait_terminal(1);
    if (!error_o[1]) $fatal(1, "TX request accepted on RX kind");

    configure(1, KindTx, RequestPioliteRx, 32'h0000_0040, 1'b1, 32'd0, 1'b0, 32'd4);
    piolite_rx_admit_i[1] = 1'b1;
    start(1);
    wait_terminal(1);
    if (!error_o[1]) $fatal(1, "RX request accepted on TX kind");

    configure(1, KindRx, RequestPioliteRx, 32'd0, 1'b0, 32'h0000_0080, 1'b1, 32'd4);
    piolite_rx_admit_i[1] = 1'b0;
    start(1);
    wait_terminal(1);
    if (!error_o[1]) $fatal(1, "unbound RX was admitted");

    rx_driver_count   = 2;
    rx_driver_index   = 0;
    rx_driver_data_q  = rx_driver_words[0];
    rx_driver_valid_q = 1'b1;
    make_tcd(160, 32'h0000_02c0, KindMm, RequestSoftware, 32'h0000_0100, 32'h0000_0140, 32'd4);
    make_tcd(176, 32'd0, KindRx, RequestPioliteRx, 32'd0, 32'h0000_0180, 32'd4);
    configure(2, KindMm, RequestSoftware, 32'h0000_0100, 1'b1, 32'h0000_0140, 1'b1, 32'd4);
    configure_tcd(2, 32'h0000_0280, 32'd2);
    configure(3, KindTx, RequestPioliteTx, 32'h0000_0040, 1'b1, 32'd0, 1'b0, 32'd4);
    start(3);
    start(2);
    if (!piolite_tx_job_o[3] || !piolite_rx_job_o[2]) $fatal(1, "full-duplex ownership missing");
    wait_terminal(3);
    wait_terminal(2);
    if (error_o[3] || error_o[2] || (pio_tx_count != 4) ||
        (pio_tx_words[3] != 32'hA500_0010) || (memory[96] != 32'hC001_0000) ||
        (memory[80] != memory[64])) begin
      $fatal(1, "full-duplex mixed TCD failed");
    end

    $display("P3_CASE suspend_resume");
    configure(3, KindTx, RequestPioliteTx, 32'h0000_0040, 1'b1, 32'd0, 1'b0, 32'd8);
    tx_ready_enable = 1'b0;
    start(3);
    wait (u_dma_core.s_stream_tx_valid[3]);
    @(negedge clk_i);
    tx_ready_enable = 1'b1;
    suspend_i[3]    = 1'b1;
    @(negedge clk_i);
    suspend_i[3] = 1'b0;
    wait (suspended_o[3]);
    unbound_ar_count = ar_count;
    repeat (20) @(posedge clk_i);
    if ((ar_count != unbound_ar_count) || (pio_tx_count != 5)) begin
      $fatal(1, "suspended TX progressed: ar_count=%0d pio_tx_count=%0d suspended=%b", ar_count,
             pio_tx_count, suspended_o[3]);
    end
    @(negedge clk_i);
    resume_i[3]     = 1'b1;
    tx_ready_enable = 1'b1;
    @(negedge clk_i);
    resume_i[3] = 1'b0;
    wait_terminal(3);
    if (error_o[3] || (pio_tx_count != 6)) $fatal(1, "resume did not preserve TX");

    $display("P3_CASE mixed_tcd_suspend");
    make_tcd(224, 32'h0000_03c0, KindTx, RequestPioliteTx, 32'h0000_0040, 32'd0, 32'd4);
    make_tcd(240, 32'd0, KindTx, RequestPioliteTx, 32'h0000_0040, 32'd0, 32'd4);
    configure(3, KindMm, RequestSoftware, 32'h0000_0040, 1'b1, 32'd0, 1'b0, 32'd4);
    configure_tcd(3, 32'h0000_0380, 32'd2);
    tx_ready_enable = 1'b0;
    start(3);
    wait (u_dma_core.s_tcd_loaded_q[3] && u_dma_core.s_stream_tx_valid[3]);
    @(negedge clk_i);
    tx_ready_enable = 1'b1;
    suspend_i[3]    = 1'b1;
    @(negedge clk_i);
    suspend_i[3] = 1'b0;
    wait (suspended_o[3]);
    unbound_ar_count = ar_count;
    repeat (20) @(posedge clk_i);
    if ((ar_count != unbound_ar_count) || (pio_tx_count != 7) ||
        !u_dma_core.s_tcd_fetch_pending_q[3] || u_dma_core.s_tcd_loaded_q[3]) begin
      $fatal(1, "mixed TCD suspend fetched or lost work: ar=%0d tx=%0d pending=%b loaded=%b",
             ar_count, pio_tx_count, u_dma_core.s_tcd_fetch_pending_q[3],
             u_dma_core.s_tcd_loaded_q[3]);
    end
    @(negedge clk_i);
    resume_i[3] = 1'b1;
    @(negedge clk_i);
    resume_i[3] = 1'b0;
    wait_terminal(3);
    if (error_o[3] || (pio_tx_count != 8)) $fatal(1, "mixed TCD resume failed");

    $display("P3_CASE full_tx_abort");
    configure(3, KindTx, RequestPioliteTx, 32'h0000_0040, 1'b1, 32'd0, 1'b0, 32'd4);
    tx_ready_enable = 1'b0;
    start(3);
    wait (u_dma_core.s_stream_tx_valid[3]);
    @(negedge clk_i);
    abort_i[3] = 1'b1;
    @(negedge clk_i);
    abort_i[3] = 1'b0;
    repeat (20) @(posedge clk_i);
    if (!busy_o[3] || aborted_o[3] || !piolite_tx_job_o[3]) begin
      $fatal(1, "full-TX abort released ownership before drain");
    end
    @(negedge clk_i);
    tx_ready_enable = 1'b1;
    wait_terminal(3);
    if (!aborted_o[3] || (pio_tx_count > 9) || piolite_tx_job_o[3]) begin
      $fatal(
          1,
          "full-TX abort failed aborted=%b done=%b error=%b count=%0d job=%b busy=%b stop=%b valid=%b",
          aborted_o[3], done_o[3], error_o[3], pio_tx_count, piolite_tx_job_o[3], busy_o[3],
          u_dma_core.s_stream_tx_stop_q[3], u_dma_core.s_stream_tx_valid[3]);
    end

    rx_driver_valid_q = 1'b0;
    configure(2, KindRx, RequestPioliteRx, 32'd0, 1'b0, 32'h0000_0080, 1'b1, 32'd4);
    start(2);
    wait (busy_o[2]);
    @(negedge clk_i);
    abort_i[2] = 1'b1;
    @(negedge clk_i);
    abort_i[2] = 1'b0;
    wait_terminal(2);
    if (!aborted_o[2] || piolite_rx_job_o[2]) $fatal(1, "empty-RX abort failed");

    $display("P3_CASE activation_abort");
    make_tcd(192, 32'd0, KindTx, RequestPioliteTx, 32'h0000_0040, 32'd0, 32'd4);
    configure(3, KindMm, RequestSoftware, 32'h0000_0040, 1'b1, 32'd0, 1'b0, 32'd4);
    configure_tcd(3, 32'h0000_0300, 32'd1);
    tx_ready_enable = 1'b0;
    start(3);
    while (!u_dma_core.s_tcd_loaded_q[3]) @(negedge clk_i);
    abort_i[3] = 1'b1;
    @(negedge clk_i);
    abort_i[3]      = 1'b0;
    tx_ready_enable = 1'b1;
    wait_terminal(3);
    if (!aborted_o[3] || (pio_tx_count > 9) || piolite_tx_job_o[3]) begin
      $fatal(1, "activation abort failed");
    end

    $display("P3_CASE fetch_backpressure_abort");
    make_tcd(208, 32'd0, KindTx, RequestPioliteTx, 32'h0000_0040, 32'd0, 32'd4);
    configure(3, KindMm, RequestSoftware, 32'h0000_0040, 1'b1, 32'd0, 1'b0, 32'd4);
    configure_tcd(3, 32'h0000_0340, 32'd1);
    address_hold = 1'b1;
    start(3);
    do @(posedge clk_i); while (!axi4.arvalid);
    @(negedge clk_i);
    abort_i[3] = 1'b1;
    @(negedge clk_i);
    abort_i[3]   = 1'b0;
    address_hold = 1'b0;
    wait_terminal(3);
    if (!aborted_o[3] || u_dma_core.s_tcd_read_owner_valid_q || (pio_tx_count > 9)) begin
      $fatal(1, "descriptor backpressure abort failed");
    end

    rx_driver_count   = 1;
    rx_driver_index   = 0;
    rx_driver_data_q  = rx_driver_words[0];
    rx_driver_valid_q = 1'b1;
    configure(2, KindRx, RequestPioliteRx, 32'd0, 1'b0, 32'h0000_0080, 1'b1, 32'd4);
    start(2);
    write_hold = 1'b1;
    wait (write_response_q && axi4.bready);
    if (done_o[2] || !busy_o[2]) $fatal(1, "B response released ownership early");
    @(negedge clk_i);
    abort_i[2] = 1'b1;
    @(negedge clk_i);
    abort_i[2] = 1'b0;
    write_hold = 1'b0;
    wait_terminal(2);
    if (!aborted_o[2] || (memory[32] != 32'hC001_0000) || piolite_rx_job_o[2]) begin
      $fatal(1, "B response drain failed");
    end

    reset_channel(2);
    if (aborted_o[2] || busy_o[2] || piolite_rx_job_o[2]) $fatal(1, "isolated reset incomplete");
    configure(1, KindMm, RequestSoftware, 32'h0000_0100, 1'b1, 32'h0000_0140, 1'b1, 32'd4);
    start(1);
    wait_terminal(1);
    if (error_o[1] || (memory[80] != memory[64])) $fatal(1, "post-reset unrelated channel stalled");

    $display("P3_CASE guard_loss_held_tx");
    configure(3, KindTx, RequestPioliteTx, 32'h0000_0040, 1'b1, 32'd0, 1'b0, 32'd4);
    piolite_tx_admit_i[3] = 1'b1;
    tx_ready_enable       = 1'b0;
    start(3);
    wait (piolite_tx_axis.tvalid);
    @(negedge clk_i);
    piolite_tx_admit_i[3] = 1'b0;
    repeat (4) begin
      @(negedge clk_i);
      if (!piolite_tx_axis.tvalid || (piolite_tx_axis.tdata != 32'hA500_0010)) begin
        $fatal(1, "guard loss revoked or changed held TX payload");
      end
    end
    abort_i[3] = 1'b1;
    @(negedge clk_i);
    abort_i[3] = 1'b0;
    repeat (4) begin
      if (!piolite_tx_axis.tvalid || (piolite_tx_axis.tdata != 32'hA500_0010)) begin
        $fatal(1, "guard-loss abort did not preserve closing TX discard beat");
      end
      @(negedge clk_i);
    end
    tx_ready_enable = 1'b1;
    wait_terminal(3);
    if (!aborted_o[3] || piolite_tx_job_o[3]) $fatal(1, "guard-loss TX abort did not drain");
    piolite_tx_admit_i[3] = 1'b1;

    $display("P3_CASE abort_before_ar");
    configure(3, KindTx, RequestPioliteTx, 32'h0000_0040, 1'b1, 32'd0, 1'b0, 32'd136);
    tx_ready_enable = 1'b0;
    start(3);
    wait (u_dma_core.s_fifo_full[3] && u_dma_core.s_stream_tx_valid[3]);
    unbound_ar_count = ar_count;
    @(negedge clk_i);
    tx_ready_enable = 1'b1;
    abort_i[3]      = 1'b1;
    @(posedge clk_i);
    if (axi4.arvalid && axi4.arready) $fatal(1, "abort edge accepted a new AR burst");
    @(negedge clk_i);
    abort_i[3] = 1'b0;
    wait_terminal(3);
    if (!aborted_o[3] || (ar_count != unbound_ar_count)) $fatal(1, "AR abort was not bounded");

    $display("P3_CASE pending_suspend_before_ar");
    configure(3, KindTx, RequestPioliteTx, 32'h0000_0040, 1'b1, 32'd0, 1'b0, 32'd136);
    tx_ready_enable = 1'b0;
    start(3);
    wait (u_dma_core.s_fifo_full[3] && u_dma_core.s_stream_tx_valid[3]);
    unbound_ar_count = ar_count;
    @(negedge clk_i);
    tx_ready_enable = 1'b1;
    suspend_i[3]    = 1'b1;
    @(posedge clk_i);
    if (axi4.arvalid && axi4.arready) $fatal(1, "suspend edge accepted a new AR burst");
    @(negedge clk_i);
    suspend_i[3]    = 1'b0;
    tx_ready_enable = 1'b0;
    wait (suspended_o[3]);
    repeat (3) @(posedge clk_i);
    if (ar_count != unbound_ar_count) $fatal(1, "pending suspend issued AR");
    @(negedge clk_i);
    resume_i[3]     = 1'b1;
    tx_ready_enable = 1'b1;
    @(negedge clk_i);
    resume_i[3] = 1'b0;
    wait_terminal(3);
    if (error_o[3] || done_o[3] != 1'b1) $fatal(1, "AR suspend resume failed");

    $display("P3_CASE abort_before_aw");
    rx_driver_count   = 2;
    rx_driver_index   = 0;
    rx_driver_data_q  = rx_driver_words[0];
    rx_driver_valid_q = 1'b0;
    configure(2, KindRx, RequestPioliteRx, 32'd0, 1'b0, 32'h0000_0080, 1'b1, 32'd8);
    start(2);
    wait (busy_o[2]);
    unbound_ar_count = aw_count;
    @(negedge clk_i);
    rx_driver_valid_q = 1'b1;
    abort_i[2]        = 1'b1;
    @(posedge clk_i);
    @(negedge clk_i);
    rx_driver_valid_q = 1'b0;
    abort_i[2]        = 1'b0;
    @(posedge clk_i);
    if (axi4.awvalid && axi4.awready) $fatal(1, "abort edge accepted a new AW burst");
    wait_terminal(2);
    if (!aborted_o[2] || (aw_count != unbound_ar_count)) $fatal(1, "AW abort was not bounded");

    $display("P3_CASE pending_suspend_before_aw");
    rx_driver_count   = 2;
    rx_driver_index   = 0;
    rx_driver_data_q  = rx_driver_words[0];
    rx_driver_valid_q = 1'b0;
    configure(2, KindRx, RequestPioliteRx, 32'd0, 1'b0, 32'h0000_0080, 1'b1, 32'd8);
    start(2);
    wait (busy_o[2]);
    unbound_ar_count = aw_count;
    @(negedge clk_i);
    rx_driver_valid_q = 1'b1;
    suspend_i[2]      = 1'b1;
    @(posedge clk_i);
    @(negedge clk_i);
    suspend_i[2] = 1'b0;
    @(posedge clk_i);
    if (axi4.awvalid && axi4.awready) $fatal(1, "pending suspend accepted a new AW burst");
    rx_driver_valid_q = 1'b0;
    wait (suspended_o[2]);
    repeat (3) @(posedge clk_i);
    if (aw_count != unbound_ar_count) $fatal(1, "pending suspend issued AW");
    @(negedge clk_i);
    abort_i[2] = 1'b1;
    @(negedge clk_i);
    abort_i[2] = 1'b0;
    wait_terminal(2);
    if (!aborted_o[2]) $fatal(1, "suspended AW channel did not recover");

    $display("P3_CASE descriptor_stall_attribution");
    make_tcd(128, 32'd0, KindTx, RequestPioliteTx, 32'h0000_0040, 32'd0, 32'd4);
    make_tcd(144, 32'd0, KindTx, RequestPioliteTx, 32'h0000_0040, 32'd0, 32'd4);
    configure(0, KindMm, RequestSoftware, 32'h0000_0040, 1'b1, 32'd0, 1'b0, 32'd4);
    configure_tcd(0, 32'h0000_0200, 32'd1);
    configure(3, KindMm, RequestSoftware, 32'h0000_0040, 1'b1, 32'd0, 1'b0, 32'd4);
    configure_tcd(3, 32'h0000_0240, 32'd1);
    piolite_tx_admit_i[0] = 1'b1;
    piolite_tx_admit_i[3] = 1'b1;
    ch_cfg_i[3*32+8+:2]   = 2'd3;
    @(negedge clk_i);
    start_i[0] = 1'b1;
    start_i[3] = 1'b1;
    @(negedge clk_i);
    start_i[0] = 1'b0;
    start_i[3] = 1'b0;
    while (!u_dma_core.s_axi_read_start_valid || !u_dma_core.s_axi_read_start_ready)
    @(negedge clk_i);
    if (!u_dma_core.s_tcd_fetch_valid || (u_dma_core.s_tcd_fetch_selected != 3))
      $fatal(1, "wrong descriptor selected for stall test");
    begin : descriptor_stall_check
      integer channel0_stall;
      integer channel3_stall;
      channel0_stall = u_dma_core.s_stall_cycles_q[0];
      channel3_stall = u_dma_core.s_stall_cycles_q[3];
      @(posedge clk_i);
      @(negedge clk_i);
      if ((u_dma_core.s_stall_cycles_q[3] != channel3_stall) ||
          (u_dma_core.s_stall_cycles_q[0] != (channel0_stall + 1))) begin
        $fatal(1, "descriptor AR progress charged to wrong channel: before=%0d/%0d after=%0d/%0d",
               channel0_stall, channel3_stall, u_dma_core.s_stall_cycles_q[0],
               u_dma_core.s_stall_cycles_q[3]);
      end
    end
    abort_i[0] = 1'b1;
    abort_i[3] = 1'b1;
    @(negedge clk_i);
    abort_i[0] = 1'b0;
    abort_i[3] = 1'b0;
    wait_terminal(0);
    wait_terminal(3);
    if (!aborted_o[0] || !aborted_o[3]) $fatal(1, "descriptor stall test cleanup failed");

    $display(
        "SIM_TEST_PASS PIOLITE_P3_DMA direct=1 tcd=1 abort=1 residual=1 full_duplex=1 suspend=1 mixed_suspend=1 backpressure=1 b_drain=1 guard_loss=1 command_edges=1 stall_accounting=1");
    $finish;
`endif
  end

  initial begin
    #5000000;
    $fatal(
        1,
        "SIM_TEST_TIMEOUT piolite_p3_dma_tb busy=%02x done=%02x aborted=%02x error=%02x abort=%02x tcd_owner=%0d tcd_parse=%0d tcd_loaded=%02x tcd_fetch=%02x ar=%0d/%0d r=%0d/%0d read_owner=%0d/%0d read_seen=%0d tx_count=%0d streamv=%b empty=%b stop=%b owned=%b chvalid=%b len=%0d issued=%0d",
        busy_o, done_o, aborted_o, error_o, u_dma_core.s_abort_q,
        u_dma_core.s_tcd_read_owner_valid_q, u_dma_core.s_tcd_parse_q, u_dma_core.s_tcd_loaded_q,
        u_dma_core.s_tcd_fetch_pending_q, axi4.arvalid, axi4.arready, axi4.rvalid, axi4.rready,
        u_dma_core.s_read_owner_valid_q, u_dma_core.s_read_owner_q, u_dma_core.s_read_seen_q,
        pio_tx_count, u_dma_core.s_stream_tx_valid[3], u_dma_core.s_fifo_empty[3],
        u_dma_core.s_stream_tx_stop_q[3], u_dma_core.s_piolite_tx_owned_q[3],
        u_dma_core.s_piolite_tx_channel_valid, u_dma_core.s_len_q[3],
        u_dma_core.s_read_issued_q[3]);
  end
endmodule
