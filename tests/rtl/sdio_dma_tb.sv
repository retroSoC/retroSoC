`timescale 1ns / 1ps
`include "axi4_define.svh"

module sdio_dma_tb;
  logic          clk_i = 1'b0;
  logic          rst_n_i = 1'b0;
  logic          start_i = 1'b0;
  logic          abort_i = 1'b0;
  logic          direction_i = 1'b0;
  logic   [31:0] desc_base_i = 32'd0;
  logic   [15:0] desc_count_i = 16'd1;
  logic   [31:0] total_bytes_i = 32'd5;
  logic          data_in_valid_i = 1'b0;
  logic          data_in_ready_o;
  logic   [31:0] data_in_i = '0;
  logic   [ 3:0] data_in_strb_i = '0;
  logic          data_in_last_i = 1'b0;
  logic          data_out_valid_o;
  logic          data_out_ready_i = 1'b1;
  logic   [31:0] data_out_o;
  logic   [ 3:0] data_out_strb_o;
  logic          data_out_last_o;
  logic          busy_o;
  logic          done_o;
  logic          error_o;
  logic   [ 7:0] error_code_o;
  logic   [31:0] current_desc_o;
  logic   [31:0] bytes_done_o;
  logic   [31:0] error_addr_o;
  logic   [31:0] memory                  [0:2047];
  logic          read_active_q = 1'b0;
  logic   [31:0] read_addr_q = '0;
  logic   [ 4:0] read_beats_q = '0;
  logic   [ 4:0] read_index_q = '0;
  logic          write_active_q = 1'b0;
  logic   [31:0] write_addr_q = '0;
  logic          write_response_q = 1'b0;
  integer        read_bursts;
  integer        max_read_beats;
  integer        output_count;
  logic          descriptor_irq_seen;
  logic   [31:0] output_data             [   0:3];
  logic   [ 3:0] output_strb             [   0:3];
  logic          output_last             [   0:3];
  logic          error_mode = 1'b0;

  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .USER_WIDTH(1)
  ) dma_axi4 (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );

  always #5 clk_i = ~clk_i;

  assign dma_axi4.arready = !read_active_q;
  assign dma_axi4.rid = 1'b0;
  assign dma_axi4.rdata = memory[(read_addr_q>>2)+read_index_q];
  assign dma_axi4.rresp =
      error_mode && (read_addr_q == 32'h0000_0200) ? `AXI4_RESP_SLAVE_ERROR :
      `AXI4_RESP_OKAY;
  assign dma_axi4.rlast = (read_index_q + 1'b1) >= read_beats_q;
  assign dma_axi4.ruser = '0;
  assign dma_axi4.rvalid = read_active_q;
  assign dma_axi4.awready = !write_active_q && !write_response_q;
  assign dma_axi4.wready = write_active_q;
  assign dma_axi4.bid = 1'b0;
  assign dma_axi4.bresp = `AXI4_RESP_OKAY;
  assign dma_axi4.buser = '0;
  assign dma_axi4.bvalid = write_response_q;

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      read_active_q    <= 1'b0;
      read_addr_q      <= '0;
      read_beats_q     <= '0;
      read_index_q     <= '0;
      write_active_q   <= 1'b0;
      write_addr_q     <= '0;
      write_response_q <= 1'b0;
      read_bursts      <= 0;
      max_read_beats   <= 0;
    end else begin
      if (dma_axi4.arvalid && dma_axi4.arready) begin
        read_active_q <= 1'b1;
        read_addr_q   <= dma_axi4.araddr;
        read_beats_q  <= dma_axi4.arlen + 1'b1;
        read_index_q  <= '0;
        read_bursts   <= read_bursts + 1;
        if ((dma_axi4.arlen + 1'b1) > max_read_beats) begin
          max_read_beats <= dma_axi4.arlen + 1'b1;
        end
      end
      if (dma_axi4.rvalid && dma_axi4.rready) begin
        if (dma_axi4.rlast) begin
          read_active_q <= 1'b0;
        end else begin
          read_index_q <= read_index_q + 1'b1;
        end
      end
      if (dma_axi4.awvalid && dma_axi4.awready) begin
        write_active_q <= 1'b1;
        write_addr_q   <= dma_axi4.awaddr;
      end
      if (dma_axi4.wvalid && dma_axi4.wready) begin
        for (integer byte_index = 0; byte_index < 4; byte_index++) begin
          if (dma_axi4.wstrb[byte_index]) begin
            memory[(write_addr_q>>2)][byte_index*8+:8] <= dma_axi4.wdata[byte_index*8+:8];
          end
        end
        if (dma_axi4.wlast) begin
          write_active_q   <= 1'b0;
          write_response_q <= 1'b1;
        end else begin
          write_addr_q <= write_addr_q + 4;
        end
      end
      if (dma_axi4.bvalid && dma_axi4.bready) begin
        write_response_q <= 1'b0;
      end
    end
  end

  always_ff @(posedge clk_i) begin
    if (data_out_valid_o && data_out_ready_i) begin
      output_data[output_count] <= data_out_o;
      output_strb[output_count] <= data_out_strb_o;
      output_last[output_count] <= data_out_last_o;
      output_count              <= output_count + 1;
    end
    if (u_sdio_dma.descriptor_irq_o) begin
      descriptor_irq_seen <= 1'b1;
    end
  end

  sdio_dma #(
      .AddrWidth(32),
      .DataWidth(32),
      .DescCount(16)
  ) u_sdio_dma (
      .clk_i           (clk_i),
      .rst_n_i         (rst_n_i),
      .start_i         (start_i),
      .abort_i         (abort_i),
      .direction_i     (direction_i),
      .desc_base_i     (desc_base_i),
      .desc_count_i    (desc_count_i),
      .total_bytes_i   (total_bytes_i),
      .data_in_valid_i (data_in_valid_i),
      .data_in_ready_o (data_in_ready_o),
      .data_in_i       (data_in_i),
      .data_in_strb_i  (data_in_strb_i),
      .data_in_last_i  (data_in_last_i),
      .data_out_valid_o(data_out_valid_o),
      .data_out_ready_i(data_out_ready_i),
      .data_out_o      (data_out_o),
      .data_out_strb_o (data_out_strb_o),
      .data_out_last_o (data_out_last_o),
      .busy_o          (busy_o),
      .done_o          (done_o),
      .error_o         (error_o),
      .error_code_o    (error_code_o),
      .current_desc_o  (current_desc_o),
      .bytes_done_o    (bytes_done_o),
      .error_addr_o    (error_addr_o),
      .dma_axi4        (dma_axi4)
  );

  initial begin
    for (integer index = 0; index < 2048; index++) memory[index] = '0;
    output_count        = 0;
    descriptor_irq_seen = 1'b0;
    direction_i         = 1'b1;
    memory[0]           = 32'h0000_0FFC;
    memory[1]           = 32'd5;
    memory[2]           = 32'd0;
    memory[3]           = 32'h0000_000D;
    memory[32'h0FFC>>2] = 32'h4433_2211;
    memory[32'h1000>>2] = 32'h0000_0055;
    repeat (3) @(posedge clk_i);
    rst_n_i = 1'b1;
    @(negedge clk_i);
    start_i = 1'b1;
    @(negedge clk_i);
    start_i = 1'b0;
    wait (done_o);
    if (error_o || (output_count != 2) || (bytes_done_o != 32'd5) ||
        (read_bursts < 3) || (max_read_beats > 16) ||
        (output_strb[0] != 4'hF) || (output_strb[1] != 4'h1) ||
        (output_data[0] != 32'h4433_2211) || (output_data[1] != 32'h0000_0055) ||
        !output_last[1] || (memory[3] != 32'h0001_000C)) begin
      $fatal(1, "DMA test failed err=%b code=%h outputs=%0d bytes=%0d bursts=%0d max=%0d wb=%h",
             error_o, error_code_o, output_count, bytes_done_o, read_bursts, max_read_beats,
             memory[3]);
    end
    @(posedge clk_i);
    #1;
    if (!descriptor_irq_seen) $fatal(1, "descriptor IRQ event was not visible");

    // Card-to-host is the opposite stream direction: input stream bytes are
    // AXI-written with low lane zero as the first byte.
    rst_n_i = 1'b0;
    repeat (3) @(posedge clk_i);
    rst_n_i             = 1'b1;
    output_count        = 0;
    direction_i         = 1'b0;
    desc_base_i         = 32'd0;
    total_bytes_i       = 32'd5;
    error_mode          = 1'b0;
    memory[0]           = 32'h0000_0200;
    memory[1]           = 32'd5;
    memory[2]           = 32'd0;
    memory[3]           = 32'h0000_000D;
    memory[32'h0200>>2] = '0;
    @(negedge clk_i);
    start_i = 1'b1;
    @(negedge clk_i);
    start_i = 1'b0;
    @(negedge clk_i);
    data_in_i       = 32'h8877_6655;
    data_in_strb_i  = 4'hF;
    data_in_last_i  = 1'b0;
    data_in_valid_i = 1'b1;
    while (u_sdio_dma.s_state_q != 4'd7) @(posedge clk_i);
    @(posedge clk_i);
    @(negedge clk_i);
    data_in_i      = 32'h0000_0099;
    data_in_strb_i = 4'h1;
    data_in_last_i = 1'b1;
    while (u_sdio_dma.s_state_q != 4'd7) @(posedge clk_i);
    @(posedge clk_i);
    @(negedge clk_i);
    data_in_valid_i = 1'b0;
    wait (done_o);
    if (error_o || (bytes_done_o != 32'd5) ||
        (memory[32'h0200>>2] != 32'h8877_6655) ||
        (memory[32'h0204>>2][7:0] != 8'h99) ||
        (memory[3] != 32'h0001_000C) || !descriptor_irq_seen) begin
      $fatal(1, "card-to-host DMA failed err=%b code=%h bytes=%0d data=%h tail=%h wb=%h", error_o,
             error_code_o, bytes_done_o, memory[32'h0200>>2], memory[32'h0204>>2], memory[3]);
    end

    for (integer tail_bytes = 1; tail_bytes <= 3; tail_bytes++) begin
      rst_n_i = 1'b0;
      repeat (3) @(posedge clk_i);
      rst_n_i         = 1'b1;
      data_in_valid_i = 1'b0;
      direction_i     = 1'b0;
      desc_base_i     = 32'd0;
      total_bytes_i   = tail_bytes;
      memory[0]       = 32'h0000_0300 + (tail_bytes * 32);
      memory[1]       = tail_bytes;
      memory[2]       = 32'd0;
      memory[3]       = 32'h0000_0005;
      @(negedge clk_i);
      start_i = 1'b1;
      @(negedge clk_i);
      start_i = 1'b0;
      while (u_sdio_dma.s_state_q != 4'd7) @(posedge clk_i);
      data_in_i       = 32'h0403_0201;
      data_in_strb_i  = (4'b0001 << tail_bytes) - 1'b1;
      data_in_last_i  = 1'b1;
      data_in_valid_i = 1'b1;
      @(posedge clk_i);
      @(negedge clk_i);
      data_in_valid_i = 1'b0;
      wait (done_o);
      for (integer byte_index = 0; byte_index < tail_bytes; byte_index++) begin
        if (memory[(32'h0000_0300 + (tail_bytes * 32) >> 2) + (byte_index >> 2)]
              [(byte_index % 4)*8+:8] != byte_index + 1) begin
          $fatal(1, "DMA tail readback failed bytes=%0d byte=%0d", tail_bytes, byte_index);
        end
      end
      if (error_o || (bytes_done_o != tail_bytes) || (memory[3] != 32'h0001_0004)) begin
        $fatal(1, "DMA tail transfer failed bytes=%0d err=%b wb=%h", tail_bytes, error_o,
               memory[3]);
      end
    end

    // A descriptor at ...FF0 is rejected before an AXI fetch.
    rst_n_i = 1'b0;
    repeat (3) @(posedge clk_i);
    rst_n_i       = 1'b1;
    desc_base_i   = 32'h0000_0FF0;
    direction_i   = 1'b1;
    total_bytes_i = 32'd4;
    @(negedge clk_i);
    start_i = 1'b1;
    @(negedge clk_i);
    start_i = 1'b0;
    wait (done_o);
    if (!error_o || (read_bursts != 0)) begin
      $fatal(1, "descriptor boundary rejection failed err=%b bursts=%0d", error_o, read_bursts);
    end

    // Restore a clean responder state for the directed AXI error check.
    rst_n_i = 1'b0;
    repeat (3) @(posedge clk_i);
    rst_n_i             = 1'b1;
    memory[0]           = 32'h0000_0200;
    memory[1]           = 32'd4;
    memory[2]           = 32'd0;
    memory[3]           = 32'h0000_0005;
    memory[32'h0200>>2] = 32'hAABB_CCDD;
    desc_base_i         = 32'd0;
    total_bytes_i       = 32'd4;
    direction_i         = 1'b1;
    error_mode          = 1'b1;
    @(negedge clk_i);
    start_i = 1'b1;
    @(negedge clk_i);
    start_i = 1'b0;
    wait (done_o);
    if (!error_o || (memory[3] != 32'h0002_0004)) begin
      $fatal(1, "AXI error was not written back: err=%b code=%h wb=%h", error_o, error_code_o,
             memory[3]);
    end
    $display("SDIO DMA descriptor, tail, and 4 KiB split test passed");
    $finish;
  end
endmodule
