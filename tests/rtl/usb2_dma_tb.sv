`timescale 1ns / 1ps

module usb2_dma_tb;
  logic          clk_i = 1'b0;
  logic          rst_n_i = 1'b0;
  logic          start_i = 1'b0;
  logic          abort_i = 1'b0;
  logic          memory_to_packet_i = 1'b1;
  logic          allow_short_i = 1'b0;
  logic   [31:0] desc_base_i = 32'd0;
  logic   [15:0] desc_limit_i = 16'd1;
  logic   [31:0] transfer_bytes_i = 32'd5;
  logic          packet_in_valid_i = 1'b0;
  logic          packet_in_ready_o;
  logic   [31:0] packet_in_data_i = '0;
  logic   [ 3:0] packet_in_strb_i = '0;
  logic          packet_in_last_i = 1'b0;
  logic          packet_out_valid_o;
  logic          packet_out_ready_i = 1'b1;
  logic   [31:0] packet_out_data_o;
  logic   [ 3:0] packet_out_strb_o;
  logic          packet_out_last_o;
  logic          busy_o;
  logic          done_o;
  logic          error_o;
  logic   [ 7:0] error_code_o;
  logic   [31:0] current_desc_o;
  logic   [31:0] next_desc_o;
  logic   [31:0] bytes_done_o;
  logic   [31:0] frame_o;
  logic          descriptor_irq_o;
  logic          abort_done_o;
  integer        output_count;
  logic   [31:0] output_data               [0:1];
  logic   [ 3:0] output_strb               [0:1];
  logic          output_last               [0:1];
  logic          descriptor_irq_seen;

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

  always_ff @(posedge clk_i) begin
    if (!rst_n_i) begin
      output_count        <= 0;
      descriptor_irq_seen <= 1'b0;
    end else begin
      if (packet_out_valid_o && packet_out_ready_i) begin
        output_data[output_count] <= packet_out_data_o;
        output_strb[output_count] <= packet_out_strb_o;
        output_last[output_count] <= packet_out_last_o;
        output_count              <= output_count + 1;
      end
      if (descriptor_irq_o) begin
        descriptor_irq_seen <= 1'b1;
      end
    end
  end

  usb2_dma #(
      .AddrWidth     (32),
      .DataWidth     (32),
      .MaxDescriptors(16)
  ) u_usb2_dma (
      .clk_i             (clk_i),
      .rst_n_i           (rst_n_i),
      .start_i           (start_i),
      .abort_i           (abort_i),
      .memory_to_packet_i(memory_to_packet_i),
      .allow_short_i     (allow_short_i),
      .desc_base_i       (desc_base_i),
      .desc_limit_i      (desc_limit_i),
      .transfer_bytes_i  (transfer_bytes_i),
      .packet_in_valid_i (packet_in_valid_i),
      .packet_in_ready_o (packet_in_ready_o),
      .packet_in_data_i  (packet_in_data_i),
      .packet_in_strb_i  (packet_in_strb_i),
      .packet_in_last_i  (packet_in_last_i),
      .packet_out_valid_o(packet_out_valid_o),
      .packet_out_ready_i(packet_out_ready_i),
      .packet_out_data_o (packet_out_data_o),
      .packet_out_strb_o (packet_out_strb_o),
      .packet_out_last_o (packet_out_last_o),
      .busy_o            (busy_o),
      .done_o            (done_o),
      .error_o           (error_o),
      .error_code_o      (error_code_o),
      .current_desc_o    (current_desc_o),
      .next_desc_o       (next_desc_o),
      .bytes_done_o      (bytes_done_o),
      .frame_o           (frame_o),
      .descriptor_irq_o  (descriptor_irq_o),
      .abort_done_o      (abort_done_o),
      .dma_axi4          (dma_axi4)
  );

  sdio_axi_memory_responder #(
      .DepthWords(16384)
  ) u_memory (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .axi4   (dma_axi4)
  );

  task automatic reset_dut;
    begin
      rst_n_i = 1'b0;
      repeat (4) @(posedge clk_i);
      rst_n_i = 1'b1;
      @(posedge clk_i);
    end
  endtask

  task automatic start_dma;
    begin
      @(negedge clk_i);
      start_i = 1'b1;
      @(negedge clk_i);
      start_i = 1'b0;
    end
  endtask

  task automatic send_packet_word(input logic [31:0] data_i, input logic [3:0] strb_i,
                                  input logic last_i);
    begin
      @(negedge clk_i);
      packet_in_data_i  = data_i;
      packet_in_strb_i  = strb_i;
      packet_in_last_i  = last_i;
      packet_in_valid_i = 1'b1;
      while (!packet_in_ready_o) @(negedge clk_i);
      @(negedge clk_i);
      packet_in_valid_i = 1'b0;
    end
  endtask

  initial begin
    u_memory.clear_memory();
    reset_dut();

    // Memory-to-packet transfer splits at 4 KiB and finishes with one valid byte.
    u_memory.write_word(32'h0000_0000, 32'h0000_0FFC);
    u_memory.write_word(32'h0000_0004, 32'd5);
    u_memory.write_word(32'h0000_0008, 32'd0);
    u_memory.write_word(32'h0000_000C, 32'h0000_000D);
    u_memory.write_word(32'h0000_0010, 32'd0);
    u_memory.write_word(32'h0000_0014, 32'd0);
    u_memory.write_word(32'h0000_0018, 32'd0);
    u_memory.write_word(32'h0000_001C, 32'd0);
    u_memory.write_word(32'h0000_0FFC, 32'h4433_2211);
    u_memory.write_word(32'h0000_1000, 32'h0000_0055);
    memory_to_packet_i = 1'b1;
    start_dma();
    wait (done_o || error_o);
    @(posedge clk_i);
    if (error_o || (bytes_done_o != 32'd5) || (output_count != 2) ||
        (output_data[0] != 32'h4433_2211) || (output_strb[0] != 4'hF) || output_last[0] ||
        (output_data[1] != 32'h0000_0055) || (output_strb[1] != 4'h1) || !output_last[1] ||
        (u_memory.read_burst_count != 3) || (u_memory.max_read_beats > 16) ||
        (u_memory.read_word(
            32'h0000_0010
        ) != 32'd5) || (u_memory.read_word(
            32'h0000_0014
        ) != 32'h0001_0000) || (u_memory.read_word(
            32'h0000_000C
        ) != 32'h0000_000C) || !descriptor_irq_seen) begin
      $fatal(1, "memory-to-packet DMA failed err=%b code=%h bytes=%0d outputs=%0d", error_o,
             error_code_o, bytes_done_o, output_count);
    end

    // Packet-to-memory transfer preserves tail strobes and commits OWN last.
    reset_dut();
    u_memory.write_word(32'h0000_0000, 32'h0000_0200);
    u_memory.write_word(32'h0000_0004, 32'd5);
    u_memory.write_word(32'h0000_0008, 32'd0);
    u_memory.write_word(32'h0000_000C, 32'h0000_000D);
    u_memory.write_word(32'h0000_0010, 32'd0);
    u_memory.write_word(32'h0000_0014, 32'd0);
    u_memory.write_word(32'h0000_0018, 32'd0);
    u_memory.write_word(32'h0000_001C, 32'd0);
    u_memory.write_word(32'h0000_0200, 32'd0);
    u_memory.write_word(32'h0000_0204, 32'd0);
    memory_to_packet_i = 1'b0;
    start_dma();
    send_packet_word(32'h8877_6655, 4'hF, 1'b0);
    send_packet_word(32'h0000_0099, 4'h1, 1'b1);
    wait (done_o || error_o);
    @(posedge clk_i);
    if (error_o || (bytes_done_o != 32'd5) || (u_memory.read_word(
            32'h0000_0200
        ) != 32'h8877_6655) || (u_memory.read_word(
            32'h0000_0204
        ) != 32'h0000_0099) || (u_memory.read_word(
            32'h0000_0010
        ) != 32'd5) || (u_memory.read_word(
            32'h0000_0014
        ) != 32'h0001_0000) || (u_memory.read_word(
            32'h0000_000C
        ) != 32'h0000_000C) || !descriptor_irq_seen) begin
      $fatal(1, "packet-to-memory DMA failed err=%b code=%h bytes=%0d data=%h tail=%h", error_o,
             error_code_o, bytes_done_o, u_memory.read_word(32'h0000_0200), u_memory.read_word(
             32'h0000_0204));
    end

    $display("USB2 descriptor DMA test passed");
    $finish;
  end
endmodule
