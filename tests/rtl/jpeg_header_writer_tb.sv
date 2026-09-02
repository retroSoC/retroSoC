`timescale 1ns / 1ps

module jpeg_header_writer_tb;
  logic           clk = 1'b0;
  logic           rst_n = 1'b0;
  logic           start;
  logic   [511:0] luma_quant;
  logic   [511:0] chroma_quant;
  logic   [  7:0] output_byte;
  logic           output_valid;
  logic           output_ready;
  logic           done;
  logic           error_flag;
  logic   [  7:0] expected      [0:1023];
  logic   [  7:0] luma_values   [  0:63];
  logic   [  7:0] chroma_values [  0:63];
  integer         expected_size;
  integer         output_index;
  string          header_path;
  string          luma_path;
  string          chroma_path;

  always #5 clk = ~clk;

  jpeg_header_writer u_dut (
      .clk_i             (clk),
      .rst_n_i           (rst_n),
      .start_i           (start),
      .width_i           (16'd17),
      .height_i          (16'd15),
      .sampling_i        (2'd3),
      .restart_interval_i(16'd1),
      .luma_quant_i      (luma_quant),
      .chroma_quant_i    (chroma_quant),
      .start_ready_o     (),
      .byte_o            (output_byte),
      .byte_valid_o      (output_valid),
      .byte_ready_i      (output_ready),
      .done_o            (done),
      .error_o           (error_flag)
  );

  always @(posedge clk) begin
    if (rst_n && output_valid && output_ready) begin
      if (output_byte != expected[output_index]) begin
        $fatal(1, "header byte mismatch at %0d: got=%h expected=%h", output_index, output_byte,
               expected[output_index]);
      end
      output_index <= output_index + 1;
    end
  end

  initial begin
    if (!$value$plusargs(
            "header_hex=%s", header_path
        ) || !$value$plusargs(
            "luma_hex=%s", luma_path
        ) || !$value$plusargs(
            "chroma_hex=%s", chroma_path
        ) || !$value$plusargs(
            "header_size=%d", expected_size
        )) begin
      $fatal(1, "header writer test requires header and quantization plusargs");
    end
    $readmemh(header_path, expected);
    $readmemh(luma_path, luma_values);
    $readmemh(chroma_path, chroma_values);
    luma_quant   = '0;
    chroma_quant = '0;
    for (int index = 0; index < 64; index++) begin
      luma_quant[index*8+:8]   = luma_values[index];
      chroma_quant[index*8+:8] = chroma_values[index];
    end
    start        = 1'b0;
    output_ready = 1'b0;
    output_index = 0;
    repeat (3) @(posedge clk);
    rst_n = 1'b1;
    @(negedge clk);
    start = 1'b1;
    @(negedge clk);
    start = 1'b0;
    repeat (2) @(negedge clk);
    if (!output_valid || output_byte != 8'hff) begin
      $fatal(1, "header output changed under backpressure");
    end
    output_ready = 1'b1;
    while (!done) @(negedge clk);
    if (error_flag || output_index != expected_size) begin
      $fatal(1, "header completion mismatch: err=%0d bytes=%0d expected=%0d", error_flag,
             output_index, expected_size);
    end
    $display("JPEG header writer tests passed");
    $finish;
  end
endmodule
