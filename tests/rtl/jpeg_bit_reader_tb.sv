`timescale 1ns / 1ps

module jpeg_bit_reader_tb;
  logic        clk = 1'b0;
  logic        rst_n = 1'b0;
  logic [ 7:0] byte_data;
  logic        byte_valid;
  logic        byte_ready;
  logic        byte_last;
  logic [ 5:0] bit_consume;
  logic        bit_consume_valid;
  logic        align_bits;
  logic [31:0] bit_window;
  logic [ 5:0] bit_count;
  logic        marker_valid;
  logic [ 7:0] marker;
  logic        marker_ready;
  logic        unpack_error;
  logic        reader_error;

  axi4_stream_if #(
      .DATA_WIDTH(64)
  ) input_axis (
      .aclk   (clk),
      .aresetn(rst_n)
  );

  always #5 clk = ~clk;

  jpeg_byte_unpacker u_unpacker (
      .clk_i       (clk),
      .rst_n_i     (rst_n),
      .input_axis  (input_axis),
      .byte_o      (byte_data),
      .byte_valid_o(byte_valid),
      .byte_ready_i(byte_ready),
      .byte_last_o (byte_last),
      .error_o     (unpack_error)
  );

  jpeg_bit_reader u_reader (
      .clk_i              (clk),
      .rst_n_i            (rst_n),
      .byte_i             (byte_data),
      .byte_valid_i       (byte_valid),
      .byte_ready_o       (byte_ready),
      .byte_last_i        (byte_last),
      .bit_consume_i      (bit_consume),
      .bit_consume_valid_i(bit_consume_valid),
      .align_i            (align_bits),
      .bit_window_o       (bit_window),
      .bit_count_o        (bit_count),
      .marker_valid_o     (marker_valid),
      .marker_o           (marker),
      .marker_ready_i     (marker_ready),
      .error_o            (reader_error)
  );

  initial begin
    input_axis.tdata  = 64'hd9ff7fd0ffaf00ff;
    input_axis.tkeep  = 8'hff;
    input_axis.tstrb  = 8'hff;
    input_axis.tlast  = 1'b1;
    input_axis.tid    = '0;
    input_axis.tdest  = '0;
    input_axis.tuser  = '0;
    input_axis.tvalid = 1'b0;
    bit_consume       = 6'd0;
    bit_consume_valid = 1'b0;
    align_bits        = 1'b0;
    marker_ready      = 1'b0;
    repeat (3) @(posedge clk);
    rst_n = 1'b1;
    @(negedge clk);
    input_axis.tvalid = 1'b1;
    #1;
    if (!input_axis.tready) $fatal(1, "input AXIS beat was not accepted");
    @(negedge clk);
    input_axis.tvalid = 1'b0;

    while (!marker_valid) @(negedge clk);
    if (marker != 8'hd0 || bit_count != 6'd16 || bit_window[31:16] != 16'hffaf) begin
      $fatal(1, "restart boundary mismatch: marker=%h count=%0d window=%h", marker, bit_count,
             bit_window);
    end
    bit_consume       = 6'd12;
    bit_consume_valid = 1'b1;
    @(negedge clk);
    bit_consume_valid = 1'b0;
    if (bit_count != 6'd4 || bit_window[31:28] != 4'hf) begin
      $fatal(1, "bit consumption mismatch");
    end
    align_bits   = 1'b1;
    marker_ready = 1'b1;
    @(negedge clk);
    align_bits   = 1'b0;
    marker_ready = 1'b0;

    while (!marker_valid) @(negedge clk);
    if (marker != 8'hd9 || bit_count != 6'd8 || bit_window[31:24] != 8'h7f) begin
      $fatal(1, "EOI boundary mismatch: marker=%h count=%0d window=%h", marker, bit_count,
             bit_window);
    end
    align_bits   = 1'b1;
    marker_ready = 1'b1;
    @(negedge clk);
    if (unpack_error || reader_error) $fatal(1, "unexpected byte/bit reader error");
    $display("JPEG byte unpacker and bit reader tests passed");
    $finish;
  end
endmodule
