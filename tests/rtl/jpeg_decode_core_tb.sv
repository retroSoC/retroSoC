`timescale 1ns / 1ps

module jpeg_decode_core_tb;
  logic          clk = 1'b0;
  logic          rst_n = 1'b0;
  logic          start;
  logic          busy;
  logic          done;
  logic   [15:0] width;
  logic   [15:0] height;
  logic   [ 1:0] sampling;
  logic          error_flag;
  logic   [ 4:0] error_code;
  logic   [ 7:0] input_bytes   [0:2047];
  logic   [ 7:0] expected_rgb  [0:4095];
  integer        input_size;
  integer        expected_size;
  integer        output_index;
  string         input_path;
  string         expected_path;

  axi4_stream_if #(
      .DATA_WIDTH(64)
  ) bitstream_axis (
      .aclk   (clk),
      .aresetn(rst_n)
  );
  axi4_stream_if #(
      .DATA_WIDTH(64)
  ) pixel_axis (
      .aclk   (clk),
      .aresetn(rst_n)
  );

  always #5 clk = ~clk;

  jpeg_decode_core u_dut (
      .clk_i          (clk),
      .rst_n_i        (rst_n),
      .start_i        (start),
      .output_format_i(3'd2),
      .bitstream_axis (bitstream_axis),
      .pixel_axis     (pixel_axis),
      .start_ready_o  (),
      .busy_o         (busy),
      .done_o         (done),
      .width_o        (width),
      .height_o       (height),
      .sampling_o     (sampling),
      .error_o        (error_flag),
      .error_code_o   (error_code)
  );

  task automatic send_input_beat(input integer offset_i);
    logic [63:0] data;
    logic [ 7:0] keep;
    begin
      data = '0;
      keep = '0;
      for (int lane = 0; lane < 8; lane++) begin
        if ((offset_i + lane) < input_size) begin
          data[lane*8+:8] = input_bytes[offset_i+lane];
          keep[lane]      = 1'b1;
        end
      end
      @(negedge clk);
      bitstream_axis.tdata  = data;
      bitstream_axis.tkeep  = keep;
      bitstream_axis.tstrb  = keep;
      bitstream_axis.tlast  = (offset_i + 8) >= input_size;
      bitstream_axis.tvalid = 1'b1;
      @(posedge clk);
      while (!bitstream_axis.tready) @(posedge clk);
      @(negedge clk);
      bitstream_axis.tvalid = 1'b0;
    end
  endtask

  always @(posedge clk) begin
    if (rst_n && pixel_axis.tvalid && pixel_axis.tready) begin
      for (int lane = 0; lane < 8; lane++) begin
        if (pixel_axis.tkeep[lane]) begin
          if (pixel_axis.tdata[lane*8+:8] != expected_rgb[output_index]) begin
            $fatal(1, "decoded byte mismatch at %0d: got=%h expected=%h", output_index,
                   pixel_axis.tdata[lane*8+:8], expected_rgb[output_index]);
          end
          output_index = output_index + 1;
        end
      end
    end
  end

  initial begin
    if (!$value$plusargs(
            "input_hex=%s", input_path
        ) || !$value$plusargs(
            "input_size=%d", input_size
        ) || !$value$plusargs(
            "expected_rgb_hex=%s", expected_path
        ) || !$value$plusargs(
            "expected_rgb_size=%d", expected_size
        )) begin
      $fatal(1, "decode core test requires JPEG and RGB plusargs");
    end
    $readmemh(input_path, input_bytes);
    $readmemh(expected_path, expected_rgb);
    start                 = 1'b0;
    bitstream_axis.tdata  = '0;
    bitstream_axis.tkeep  = '0;
    bitstream_axis.tstrb  = '0;
    bitstream_axis.tlast  = 1'b0;
    bitstream_axis.tid    = '0;
    bitstream_axis.tdest  = '0;
    bitstream_axis.tuser  = '0;
    bitstream_axis.tvalid = 1'b0;
    pixel_axis.tready     = 1'b1;
    output_index          = 0;
    repeat (3) @(posedge clk);
    rst_n = 1'b1;
    @(negedge clk);
    start = 1'b1;
    @(negedge clk);
    start = 1'b0;
    for (int offset = 0; offset < input_size; offset += 8) begin
      send_input_beat(offset);
    end
    for (int cycle = 0; cycle < 200000 && !done && !error_flag; cycle++) begin
      @(negedge clk);
    end
    if (error_flag || !done || width != 16'd16 || height != 16'd16 || sampling != 2'd3 ||
        output_index != expected_size) begin
      $fatal(1,
             "decode completion mismatch: done=%0d err=%0d code=%0d size=%0dx%0d sampling=%0d bytes=%0d expected=%0d",
             done, error_flag, error_code, width, height, sampling, output_index, expected_size);
    end
    $display("JPEG decode core tests passed");
    $finish;
  end
endmodule
