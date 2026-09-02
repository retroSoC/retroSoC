`timescale 1ns / 1ps

module jpeg_mcu_reconstructor_tb;
  logic         clk = 1'b0;
  logic         rst_n = 1'b0;
  logic         start;
  logic [511:0] block_data;
  logic         block_valid;
  logic         block_ready;
  logic         done;
  logic         error_flag;
  int           block_index;
  int           beat_count;
  int           line_count;

  axi4_stream_if #(
      .DATA_WIDTH(64)
  ) pixel_axis (
      .aclk   (clk),
      .aresetn(rst_n)
  );

  always #5 clk = ~clk;

  jpeg_mcu_reconstructor u_dut (
      .clk_i         (clk),
      .rst_n_i       (rst_n),
      .start_i       (start),
      .sampling_i    (2'd3),
      .format_i      (3'd2),
      .valid_width_i (5'd16),
      .valid_height_i(5'd16),
      .block_i       (block_data),
      .block_valid_i (block_valid),
      .block_ready_o (block_ready),
      .start_ready_o (),
      .pixel_axis    (pixel_axis),
      .done_o        (done),
      .error_o       (error_flag)
  );

  always @(posedge clk) begin
    if (rst_n && block_valid && block_ready) begin
      block_index <= block_index + 1;
    end
    if (rst_n && pixel_axis.tvalid && pixel_axis.tready) begin
      if (pixel_axis.tkeep != 8'h3f || pixel_axis.tdata[47:0] != 48'h808080808080) begin
        $fatal(1, "RGB888 raster output mismatch");
      end
      if (pixel_axis.tuser != (beat_count == 0)) begin
        $fatal(1, "SOF marker mismatch at beat %0d", beat_count);
      end
      if (pixel_axis.tlast) begin
        line_count <= line_count + 1;
      end
      beat_count <= beat_count + 1;
    end
  end

  initial begin
    start             = 1'b0;
    block_data        = {64{8'd128}};
    block_valid       = 1'b0;
    pixel_axis.tready = 1'b0;
    block_index       = 0;
    beat_count        = 0;
    line_count        = 0;
    repeat (3) @(posedge clk);
    rst_n = 1'b1;
    @(negedge clk);
    start = 1'b1;
    @(negedge clk);
    start       = 1'b0;
    block_valid = 1'b1;
    while (block_index < 6) @(negedge clk);
    block_valid = 1'b0;
    repeat (2) @(negedge clk);
    if (!pixel_axis.tvalid || pixel_axis.tdata[47:0] != 48'h808080808080) begin
      $fatal(1, "pixel output not stable during backpressure");
    end
    pixel_axis.tready = 1'b1;
    while (!done) @(negedge clk);
    if (error_flag || beat_count != 128 || line_count != 16) begin
      $fatal(1, "MCU completion mismatch: err=%0d beats=%0d lines=%0d", error_flag, beat_count,
             line_count);
    end
    $display("JPEG MCU reconstructor tests passed");
    $finish;
  end
endmodule
