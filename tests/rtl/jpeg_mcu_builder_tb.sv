`timescale 1ns / 1ps

module jpeg_mcu_builder_tb;
  logic         clk = 1'b0;
  logic         rst_n = 1'b0;
  logic         start;
  logic [511:0] block_data;
  logic         block_valid;
  logic         block_last;
  logic         done;
  logic         error_flag;
  logic [511:0] expected_block;
  int           input_beats;
  int           output_blocks;
  int           timeout_cycles;

  axi4_stream_if #(
      .DATA_WIDTH(64)
  ) pixel_axis (
      .aclk   (clk),
      .aresetn(rst_n)
  );

  always #5 clk = ~clk;

  always_comb begin
    expected_block = {64{8'd128}};
    if (output_blocks < 4) begin
      for (int sample = 0; sample < 64; sample ++) begin
        expected_block[sample*8+:8] = 8'((((output_blocks >> 1) * 8 + (sample >> 3)) * 16) +
                                                ((output_blocks & 1) * 8) + (sample & 7));
      end
    end
  end

  jpeg_mcu_builder u_dut (
      .clk_i         (clk),
      .rst_n_i       (rst_n),
      .start_i       (start),
      .sampling_i    (2'd3),
      .format_i      (3'd2),
      .valid_width_i (5'd16),
      .valid_height_i(5'd16),
      .pixel_axis    (pixel_axis),
      .start_ready_o (),
      .block_o       (block_data),
      .block_valid_o (block_valid),
      .block_ready_i (1'b1),
      .block_last_o  (block_last),
      .done_o        (done),
      .error_o       (error_flag)
  );

  always @(posedge clk) begin
    if (rst_n && pixel_axis.tvalid && pixel_axis.tready) begin
      input_beats <= input_beats + 1;
    end
    if (rst_n && block_valid) begin
      if (block_data !== expected_block || (block_last != (output_blocks == 5))) begin
        $fatal(1, "generated block mismatch at %0d: %h", output_blocks, block_data);
      end
      output_blocks <= output_blocks + 1;
    end
  end

  initial begin
    start             = 1'b0;
    pixel_axis.tdata  = '0;
    pixel_axis.tkeep  = 8'hff;
    pixel_axis.tstrb  = 8'hff;
    pixel_axis.tlast  = 1'b0;
    pixel_axis.tid    = '0;
    pixel_axis.tdest  = '0;
    pixel_axis.tuser  = '0;
    pixel_axis.tvalid = 1'b0;
    input_beats       = 0;
    output_blocks     = 0;
    repeat (3) @(posedge clk);
    rst_n = 1'b1;
    @(negedge clk);
    start = 1'b1;
    @(negedge clk);
    start             = 1'b0;
    pixel_axis.tvalid = 1'b1;
    for (int lane = 0; lane < 8; lane++) begin
      pixel_axis.tdata[lane*8+:8] = 8'(lane / 3);
    end
    while (input_beats < 96) begin
      @(negedge clk);
      pixel_axis.tlast = input_beats == 95;
      for (int lane = 0; lane < 8; lane++) begin
        pixel_axis.tdata[lane*8+:8] = 8'(((input_beats * 8) + lane) / 3);
      end
    end
    pixel_axis.tvalid = 1'b0;
    pixel_axis.tlast  = 1'b0;
    timeout_cycles    = 2000;
    while (!done && (timeout_cycles > 0)) begin
      @(negedge clk);
      timeout_cycles--;
    end
    if (timeout_cycles == 0) begin
      $fatal(1, "MCU builder timeout: state=%0d block=%0d sample=%0d", u_dut.s_state_q,
             u_dut.s_block_cnt_q, u_dut.s_sample_cnt_q);
    end
    if (error_flag || output_blocks != 6) begin
      $fatal(1, "MCU builder completion mismatch: err=%0d blocks=%0d", error_flag, output_blocks);
    end
    $display("JPEG MCU builder tests passed");
    $finish;
  end
endmodule
