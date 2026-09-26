// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0
// Real DMA channels 4/5 -> AES ECB -> memory, with AXI stalls.
`timescale 1ns / 1ps

module crypto_dma_v2_tb;
  import dma_pkg::*;

  logic  [31:0] constants     [0:2047];
  string        constant_path;
  localparam int NumChannels = 8;
  localparam logic [31:0] SourceBase = 32'h4000_0000;
  localparam logic [31:0] DestinationBase = 32'h4000_1000;
  localparam logic [31:0] TransferBytes = 32'd64;

  logic clk_i = 1'b0;
  logic rst_n_i = 1'b0;
  logic inject_read_error = 0, inject_write_error = 0;
  logic                        stalled_output = 0;
  logic   [              36:0] held_output;
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
  logic crypto_irq, crypto_input_proc, crypto_output_proc;
  apb4_if crypto_apb (
      .pclk   (clk_i),
      .presetn(rst_n_i)
  );
  function automatic logic [31:0] plaintext(input logic [1:0] index);
    case (index)
      0:       return 32'h33221100;
      1:       return 32'h77665544;
      2:       return 32'hbbaa9988;
      default: return 32'hffeeddcc;
    endcase
  endfunction
  function automatic logic [31:0] ciphertext(input logic [1:0] index);
    case (index)
      0:       return 32'hd8e0c469;
      1:       return 32'h30047b6a;
      2:       return 32'h80b7cdd8;
      default: return 32'h5ac5b470;
    endcase
  endfunction
  task automatic apb_write(input logic [11:0] address, input logic [31:0] data);
    @(negedge clk_i);
    crypto_apb.paddr   = {20'd0, address};
    crypto_apb.pwdata  = data;
    crypto_apb.pstrb   = 4'hf;
    crypto_apb.pwrite  = 1'b1;
    crypto_apb.psel    = 1'b1;
    crypto_apb.penable = 1'b0;
    @(negedge clk_i);
    crypto_apb.penable = 1'b1;
    do begin
      @(posedge clk_i);
    end while (!crypto_apb.pready);
    if (crypto_apb.pslverr) $fatal(1, "crypto DMA APB write %h", address);
    @(negedge clk_i);
    crypto_apb.psel    = 1'b0;
    crypto_apb.penable = 1'b0;
  endtask
  task automatic apb_read(input logic [11:0] address, output logic [31:0] data);
    @(negedge clk_i);
    crypto_apb.paddr   = {20'd0, address};
    crypto_apb.pstrb   = 0;
    crypto_apb.pwrite  = 1'b0;
    crypto_apb.psel    = 1'b1;
    crypto_apb.penable = 1'b0;
    @(negedge clk_i);
    crypto_apb.penable = 1'b1;
    do begin
      @(posedge clk_i);
    end while (!crypto_apb.pready);
    if (crypto_apb.pslverr) $fatal(1, "crypto DMA APB read %h", address);
    data = crypto_apb.prdata;
    @(negedge clk_i);
    crypto_apb.psel    = 1'b0;
    crypto_apb.penable = 1'b0;
  endtask
  initial begin
    #1000000;
    $fatal(1, "crypto DMA test watchdog");
  end

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

  apb4_crypto u_crypto (
      .clk_i            (clk_i),
      .rst_n_i          (rst_n_i),
      .irq_o            (crypto_irq),
      .dma_input_proc_o (crypto_input_proc),
      .dma_output_proc_o(crypto_output_proc),
      .apb4             (crypto_apb),
      .crypto_in_axis   (crypto_in_axis),
      .crypto_out_axis  (crypto_out_axis)
  );

  always #5 clk_i = ~clk_i;

  assign req.i2s_tx_proc     = 1'b1;
  assign req.i2s_rx_proc     = 1'b1;
  assign req.qspi_tx_proc    = 1'b1;
  assign req.qspi_rx_proc    = 1'b1;
  assign req.uart_tx_proc    = 1'b1;
  assign req.uart_rx_proc    = 1'b1;
  assign req.i2c0_tx_proc    = 1'b1;
  assign req.i2c0_rx_proc    = 1'b1;
  assign req.i2c1_tx_proc    = 1'b1;
  assign req.i2c1_rx_proc    = 1'b1;
  assign req.crypto_in_proc  = crypto_input_proc;
  assign req.crypto_out_proc = crypto_output_proc;

  assign axi4.arready        = !read_active_q && cycle_q[0];
  assign axi4.rid            = '0;
  assign axi4.rdata          = plaintext(2'(((read_addr_q - SourceBase) >> 2) + read_index_q));
  assign axi4.rresp          = inject_read_error ? `AXI4_RESP_SLAVE_ERROR : `AXI4_RESP_OKAY;
  assign axi4.rlast          = (read_index_q + 1'b1) == read_beats_q;
  assign axi4.ruser          = '0;
  assign axi4.rvalid         = read_active_q;
  assign axi4.awready        = !write_active_q && !write_response_q && cycle_q[0];
  assign axi4.wready         = write_active_q && cycle_q[1];
  assign axi4.bid            = '0;
  assign axi4.bresp          = inject_write_error ? `AXI4_RESP_SLAVE_ERROR : `AXI4_RESP_OKAY;
  assign axi4.buser          = '0;
  assign axi4.bvalid         = write_response_q;

  assign i2s_tx_axis.tready  = 1'b0;
  assign i2s_rx_axis.tdata   = '0;
  assign i2s_rx_axis.tkeep   = '0;
  assign i2s_rx_axis.tstrb   = '0;
  assign i2s_rx_axis.tlast   = 1'b0;
  assign i2s_rx_axis.tid     = '0;
  assign i2s_rx_axis.tdest   = '0;
  assign i2s_rx_axis.tuser   = '0;
  assign i2s_rx_axis.tvalid  = 1'b0;
  assign dvp_rx_axis.tdata   = '0;
  assign dvp_rx_axis.tkeep   = '0;
  assign dvp_rx_axis.tstrb   = '0;
  assign dvp_rx_axis.tlast   = 1'b0;
  assign dvp_rx_axis.tid     = '0;
  assign dvp_rx_axis.tdest   = '0;
  assign dvp_rx_axis.tuser   = '0;
  assign dvp_rx_axis.tvalid  = 1'b0;


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
        if (axi4.wdata != ciphertext(2'(write_count))) begin
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
    integer        wait_cycles;
    logic   [31:0] status;
    inject_read_error = $test$plusargs("dma_read_error");
    inject_write_error = $test$plusargs("dma_write_error");
    crypto_apb.paddr = 0;
    crypto_apb.pprot = 0;
    crypto_apb.psel = 0;
    crypto_apb.penable = 0;
    crypto_apb.pwrite = 0;
    crypto_apb.pwdata = 0;
    crypto_apb.pstrb = 0;

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
    if (!$value$plusargs("constants=%s", constant_path)) $fatal(1, "missing CRYC1 image");
    $readmemh(constant_path, constants);
    status = 4;
    while (status & 4) apb_read(12'h028, status);
    apb_write(12'h02c, 1);
    for (int index = 0; index < 2048; index++) apb_write(12'h038, constants[index]);
    apb_write(12'h02c, 2);
    status = 0;
    while ((status & 35) != 35) apb_read(12'h028, status);
    apb_write(12'h104, 32'h100);
    apb_write(12'h140, 32'h03020100);
    apb_write(12'h144, 32'h07060504);
    apb_write(12'h148, 32'h0b0a0908);
    apb_write(12'h14c, 32'h0f0e0d0c);
    apb_write(12'h128, 32'h1);
    status = 0;
    while (!(status & 1)) apb_read(12'h12c, status);
    apb_write(12'h10c, TransferBytes);
    apb_write(12'h100, 32'h1);
    @(negedge clk_i);
    start_i[5:4] = 2'b11;
    @(negedge clk_i);
    start_i     = '0;
    wait_cycles = 0;
    while (!(done_o[4] && done_o[5]) && !(|error_o) && (wait_cycles < 5000)) begin
      @(posedge clk_i);
      wait_cycles = wait_cycles + 1;
    end
    if (inject_read_error || inject_write_error) begin
      if (!(inject_read_error ? error_o[4] : error_o[5]))
        $fatal(1, "DMA did not report injected AXI error");
      apb_write(12'h010, 2);
      repeat (2200) @(negedge clk_i);
      apb_read(12'h108, status);
      if (status[1]) $fatal(1, "DMA error/abort asserted AES DONE");
      // The failed consumer may own a held beat. Only coordinated reset can
      // reclaim it when the consumer cannot drain; never call this erasure.
      rst_n_i = 0;
      repeat (3) @(negedge clk_i);
      rst_n_i = 1;
      repeat (2100) @(negedge clk_i);
      if (crypto_out_axis.tvalid || error_o != 0 || busy_o != 0)
        $fatal(1, "coordinated DMA/Crypto reset failed");
      $display("CRYPTO_V2_DMA_ERROR_PASS read=%0d write=%0d", inject_read_error,
               inject_write_error);
    end else begin
      if (!(done_o[4] && done_o[5])) begin
        $fatal(1, "crypto DMA endpoint test timeout");
      end
      if ((error_o != '0) || (write_count != 16) || !stream_last_seen_q ||
        (bytes_done_o[(4*32)+:32] != TransferBytes) ||
        (bytes_done_o[(5*32)+:32] != TransferBytes)) begin
        $fatal(1, "crypto DMA result mismatch errors=%b writes=%0d last=%b", error_o, write_count,
               stream_last_seen_q);
      end
      apb_read(12'h108, status);
      if ((status & 32'h6) != 32'h2) $fatal(1, "AES DMA did not complete correctly");
      apb_read(12'h124, status);
      $display("CRYPTO_CYCLES operation=aes_dma_64bytes cycles=%0d", status);
      $display("CRYPTO_V2_DMA_PASS");
    end
    $finish;
  end
  always @(posedge clk_i) begin
    if (rst_n_i && stalled_output) begin
      if (!crypto_out_axis.tvalid ||
          {crypto_out_axis.tlast, crypto_out_axis.tkeep, crypto_out_axis.tdata} !== held_output)
        $fatal(1, "DMA error cleanup retracted a held Crypto beat");
    end
    stalled_output <= rst_n_i && crypto_out_axis.tvalid && !crypto_out_axis.tready;
    held_output    <= {crypto_out_axis.tlast, crypto_out_axis.tkeep, crypto_out_axis.tdata};
  end
endmodule
