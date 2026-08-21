// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of the Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// INCLUDING, BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY OR FITNESS FOR A
// PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

`timescale 1ns / 1ps
`include "axi4_define.svh"

module sdio_dma_stress_tb;
  logic          clk_i = 1'b0;
  logic          rst_n_i = 1'b0;
  logic          start_i = 1'b0;
  logic          abort_i = 1'b0;
  logic          direction_i = 1'b1;
  logic   [31:0] desc_base_i = 32'd0;
  logic   [15:0] desc_count_i = 16'd1;
  logic   [31:0] total_bytes_i = 32'd0;
  logic          data_in_valid_i = 1'b0;
  logic          data_in_ready_o;
  logic   [31:0] data_in_i = 32'd0;
  logic   [ 3:0] data_in_strb_i = 4'hF;
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
  integer        output_count;
  integer        guard;
  logic          done_seen;
  integer        abort_read_bursts;

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

  sdio_axi_memory_responder #(
      .DepthWords(16384)
  ) u_memory (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .axi4   (dma_axi4)
  );

  sdio_dma u_sdio_dma (
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

  always @(posedge clk_i) begin
    if (data_out_valid_o && data_out_ready_i) begin
      output_count = output_count + 1;
    end
    if (done_o) begin
      done_seen = 1'b1;
    end
  end

  task automatic pulse_start;
    begin
      @(negedge clk_i);
      start_i = 1'b1;
      @(negedge clk_i);
      start_i = 1'b0;
    end
  endtask

  task automatic wait_done;
    logic seen_busy;
    begin
      guard     = 0;
      seen_busy = busy_o;
      while ((!seen_busy || !done_o) && (guard < 200000)) begin
        @(posedge clk_i);
        guard     = guard + 1;
        seen_busy = seen_busy || busy_o;
      end
      if (guard >= 200000) begin
        $fatal(1, "SDIO DMA stress transfer did not complete");
      end
    end
  endtask

  task automatic clear_run_state;
    begin
      rst_n_i = 1'b0;
      repeat (3) @(posedge clk_i);
      rst_n_i          = 1'b1;
      start_i          = 1'b0;
      abort_i          = 1'b0;
      direction_i      = 1'b1;
      data_out_ready_i = 1'b1;
      data_in_valid_i  = 1'b0;
      output_count     = 0;
      done_seen        = 1'b0;
      u_memory.clear_errors();
      u_memory.set_backpressure(0, 0, 0, 0);
    end
  endtask

  initial begin
    u_memory.clear_memory();
    u_memory.write_word(32'h0000_0000, 32'h0000_0100);
    u_memory.write_word(32'h0000_0004, 32'd64);
    u_memory.write_word(32'h0000_0008, 32'd0);
    u_memory.write_word(32'h0000_000C, 32'h0000_0005);
    for (integer index = 0; index < 16; index++) begin
      u_memory.write_word(32'h0000_0100 + (index * 4), 32'h1000_0000 + index);
    end
    repeat (3) @(posedge clk_i);
    rst_n_i       = 1'b1;
    done_seen     = 1'b0;

    // A full 16-beat payload burst under independent channel backpressure.
    total_bytes_i = 32'd64;
    $display("DMA STRESS full burst");
    u_memory.set_backpressure(2, 3, 2, 2);
    pulse_start();
    wait_done();
    if (error_o || (output_count != 16) || (u_memory.max_read_beats != 16)) begin
      $fatal(1, "16-beat DMA contract failed err=%b outputs=%0d max=%0d", error_o, output_count,
             u_memory.max_read_beats);
    end

    // The same payload geometry split at the 4 KiB boundary.
    clear_run_state();
    u_memory.write_word(32'h0000_0000, 32'h0000_0FFC);
    u_memory.write_word(32'h0000_0004, 32'd8);
    u_memory.write_word(32'h0000_0008, 32'd0);
    u_memory.write_word(32'h0000_000C, 32'h0000_0005);
    u_memory.write_word(32'h0000_0FFC, 32'hAAAA_0001);
    u_memory.write_word(32'h0000_1000, 32'hAAAA_0002);
    total_bytes_i = 32'd8;
    $display("DMA STRESS split");
    pulse_start();
    wait_done();
    if (error_o || (u_memory.read_burst_count < 3)) begin
      $fatal(1, "4 KiB split DMA contract failed err=%b bursts=%0d", error_o,
             u_memory.read_burst_count);
    end

    // A bounded two-descriptor chain must write DONE/clear OWN on both
    // descriptors before the terminal event.
    clear_run_state();
    u_memory.write_word(32'h0000_0000, 32'h0000_0100);
    u_memory.write_word(32'h0000_0004, 32'd4);
    u_memory.write_word(32'h0000_0008, 32'h0000_0020);
    u_memory.write_word(32'h0000_000C, 32'h0000_0003);
    u_memory.write_word(32'h0000_0020, 32'h0000_0110);
    u_memory.write_word(32'h0000_0024, 32'd4);
    u_memory.write_word(32'h0000_0028, 32'd0);
    u_memory.write_word(32'h0000_002C, 32'h0000_0005);
    u_memory.write_word(32'h0000_0100, 32'h1111_0001);
    u_memory.write_word(32'h0000_0110, 32'h2222_0002);
    desc_count_i  = 16'd2;
    total_bytes_i = 32'd8;
    pulse_start();
    wait_done();
    if (error_o || (output_count != 2) || (u_memory.read_word(
            32'h0000_000C
        ) != 32'h0001_0002) || (u_memory.read_word(
            32'h0000_002C
        ) != 32'h0001_0004)) begin
      $fatal(1, "descriptor chain/writeback contract failed");
    end

    // A target read error is converted into descriptor ERROR writeback.
    clear_run_state();
    u_memory.write_word(32'h0000_0000, 32'h0000_0200);
    u_memory.write_word(32'h0000_0004, 32'd4);
    u_memory.write_word(32'h0000_0008, 32'd0);
    u_memory.write_word(32'h0000_000C, 32'h0000_0005);
    u_memory.inject_read_error(32'h0000_0200);
    total_bytes_i = 32'd4;
    $display("DMA STRESS error");
    pulse_start();
    wait_done();
    if (!error_o || (u_memory.read_word(32'h0000_000C) != 32'h0002_0004)) begin
      $fatal(1, "AXI read error did not reach descriptor writeback");
    end

    // Abort with a stalled stream drains the accepted AXI response and
    // terminates through the same bounded writeback path.
    clear_run_state();
    u_memory.clear_memory();
    u_memory.write_word(32'h0000_0000, 32'h0000_0300);
    u_memory.write_word(32'h0000_0004, 32'd128);
    u_memory.write_word(32'h0000_0008, 32'd0);
    u_memory.write_word(32'h0000_000C, 32'h0000_0005);
    total_bytes_i = 32'd128;
    $display("DMA STRESS abort");
    data_out_ready_i = 1'b0;
    pulse_start();
    wait (u_sdio_dma.s_state_q == 4'd5);
    wait (u_sdio_dma.s_read_busy);
    @(posedge clk_i);
    abort_read_bursts = u_memory.read_burst_count;
    repeat (5) @(posedge clk_i);
    @(negedge clk_i);
    abort_i = 1'b1;
    repeat (4) @(posedge clk_i);
    abort_i = 1'b0;
    if (!done_seen) begin
      wait_done();
    end
    if (!error_o) begin
      $fatal(1, "DMA abort did not drain/write back error");
    end
    if (busy_o || (u_memory.read_burst_count != abort_read_bursts) || (u_memory.read_word(
            32'h0000_000C
        ) != 32'h0002_0004)) begin
      $fatal(1, "DMA abort left an accepted AXI read active or issued a new request");
    end

    // Abort during descriptor fetch still drains the accepted four-beat read
    // and writes ERROR/clears OWN on the fetched active descriptor.
    clear_run_state();
    u_memory.write_word(32'h0000_0000, 32'h0000_0400);
    u_memory.write_word(32'h0000_0004, 32'd4);
    u_memory.write_word(32'h0000_0008, 32'd0);
    u_memory.write_word(32'h0000_000C, 32'h0000_0005);
    total_bytes_i = 32'd4;
    u_memory.set_backpressure(0, 3, 0, 0);
    pulse_start();
    wait (u_sdio_dma.s_state_q == 4'd2);
    wait (u_sdio_dma.s_read_busy);
    @(negedge clk_i);
    abort_i = 1'b1;
    @(negedge clk_i);
    abort_i = 1'b0;
    wait_done();
    if (!error_o || (u_memory.read_word(
            32'h0000_000C
        ) != 32'h0002_0004) || u_memory.s_read_active_q) begin
      $fatal(1, "descriptor-fetch abort did not drain/write back correctly");
    end

    // Abort while an AXI write response is stalled must wait for B before
    // terminalizing the descriptor.
    clear_run_state();
    direction_i = 1'b0;
    u_memory.write_word(32'h0000_0000, 32'h0000_0500);
    u_memory.write_word(32'h0000_0004, 32'd4);
    u_memory.write_word(32'h0000_0008, 32'd0);
    u_memory.write_word(32'h0000_000C, 32'h0000_0005);
    total_bytes_i = 32'd4;
    u_memory.set_backpressure(0, 0, 0, 5);
    pulse_start();
    wait (u_sdio_dma.s_state_q == 4'd7);
    data_in_i       = 32'hDDCC_BBAA;
    data_in_strb_i  = 4'hF;
    data_in_last_i  = 1'b1;
    data_in_valid_i = 1'b1;
    @(posedge clk_i);
    data_in_valid_i = 1'b0;
    @(negedge clk_i);
    abort_i = 1'b1;
    @(negedge clk_i);
    abort_i = 1'b0;
    wait_done();
    if (!error_o || (u_memory.read_word(
            32'h0000_000C
        ) != 32'h0002_0004) || u_memory.s_write_active_q) begin
      $fatal(1, "write-response abort did not drain/write back correctly");
    end

    $display("SDIO AXI 16-beat, 4 KiB split, error, and abort test passed");
    $finish;
  end
endmodule
