`timescale 1ns / 1ps

module jpeg_encode_core_tb;
  logic            clk = 1'b0;
  logic            rst_n = 1'b0;
  logic            start;
  logic   [ 511:0] luma_quant;
  logic   [1599:0] luma_reciprocal;
  logic   [ 191:0] luma_dc_code;
  logic   [  59:0] luma_dc_length;
  logic   [4095:0] luma_ac_code;
  logic   [1279:0] luma_ac_length;
  logic   [ 511:0] chroma_quant;
  logic   [1599:0] chroma_reciprocal;
  logic   [ 191:0] chroma_dc_code;
  logic   [  59:0] chroma_dc_length;
  logic   [4095:0] chroma_ac_code;
  logic   [1279:0] chroma_ac_length;
  logic            busy;
  logic            done;
  logic            error_flag;
  logic   [   7:0] expected             [0:2047];
  logic   [   7:0] luma_quant_values    [  0:63];
  logic   [   7:0] chroma_quant_values  [  0:63];
  logic   [  31:0] luma_dc_entries      [  0:11];
  logic   [  31:0] chroma_dc_entries    [  0:11];
  logic   [  31:0] luma_ac_entries      [ 0:255];
  logic   [  31:0] chroma_ac_entries    [ 0:255];
  integer          expected_size;
  integer          output_index;
  integer          input_beats;
  integer          expected_input_beats;
  integer          test_width;
  integer          test_height;
  integer          cycle_count;
  integer          timeout_cycles;
  string           expected_path;
  string           luma_quant_path;
  string           chroma_quant_path;
  string           luma_dc_path;
  string           chroma_dc_path;
  string           luma_ac_path;
  string           chroma_ac_path;

  axi4_stream_if #(
      .DATA_WIDTH(64)
  ) pixel_axis (
      .aclk   (clk),
      .aresetn(rst_n)
  );
  axi4_stream_if #(
      .DATA_WIDTH(64)
  ) bitstream_axis (
      .aclk   (clk),
      .aresetn(rst_n)
  );

  always #5 clk = ~clk;

  jpeg_encode_core u_dut (
      .clk_i              (clk),
      .rst_n_i            (rst_n),
      .start_i            (start),
      .width_i            (test_width[15:0]),
      .height_i           (test_height[15:0]),
      .sampling_i         (2'd3),
      .input_format_i     (3'd2),
      .restart_interval_i (16'd0),
      .luma_quant_i       (luma_quant),
      .luma_reciprocal_i  (luma_reciprocal),
      .luma_dc_code_i     (luma_dc_code),
      .luma_dc_length_i   (luma_dc_length),
      .luma_ac_code_i     (luma_ac_code),
      .luma_ac_length_i   (luma_ac_length),
      .chroma_quant_i     (chroma_quant),
      .chroma_reciprocal_i(chroma_reciprocal),
      .chroma_dc_code_i   (chroma_dc_code),
      .chroma_dc_length_i (chroma_dc_length),
      .chroma_ac_code_i   (chroma_ac_code),
      .chroma_ac_length_i (chroma_ac_length),
      .pixel_axis         (pixel_axis),
      .bitstream_axis     (bitstream_axis),
      .start_ready_o      (),
      .busy_o             (busy),
      .done_o             (done),
      .error_o            (error_flag)
  );

  always @(posedge clk) begin
    if (rst_n && busy) begin
      cycle_count <= cycle_count + 1;
    end
    if (rst_n && pixel_axis.tvalid && pixel_axis.tready) begin
      input_beats <= input_beats + 1;
    end
    if (rst_n && bitstream_axis.tvalid && bitstream_axis.tready) begin
      for (int lane = 0; lane < 8; lane++) begin
        if (bitstream_axis.tkeep[lane]) begin
          if (bitstream_axis.tdata[lane*8+:8] != expected[output_index]) begin
            $fatal(1, "encoded byte mismatch at %0d: got=%h expected=%h", output_index,
                   bitstream_axis.tdata[lane*8+:8], expected[output_index]);
          end
          output_index = output_index + 1;
        end
      end
      if (bitstream_axis.tlast != (output_index == expected_size)) begin
        $fatal(1, "encoded TLAST mismatch");
      end
    end
  end

  initial begin
    if (!$value$plusargs(
            "expected_hex=%s", expected_path
        ) || !$value$plusargs(
            "expected_size=%d", expected_size
        ) || !$value$plusargs(
            "luma_quant_hex=%s", luma_quant_path
        ) || !$value$plusargs(
            "chroma_quant_hex=%s", chroma_quant_path
        ) || !$value$plusargs(
            "luma_dc_hex=%s", luma_dc_path
        ) || !$value$plusargs(
            "chroma_dc_hex=%s", chroma_dc_path
        ) || !$value$plusargs(
            "luma_ac_hex=%s", luma_ac_path
        ) || !$value$plusargs(
            "chroma_ac_hex=%s", chroma_ac_path
        )) begin
      $fatal(1, "encode core test requires JPEG and table plusargs");
    end
    test_width = 16;
    test_height = 16;
    expected_input_beats = 96;
    void'($value$plusargs("test_width=%d", test_width));
    void'($value$plusargs("test_height=%d", test_height));
    void'($value$plusargs("input_beats=%d", expected_input_beats));
    $readmemh(expected_path, expected);
    $readmemh(luma_quant_path, luma_quant_values);
    $readmemh(chroma_quant_path, chroma_quant_values);
    $readmemh(luma_dc_path, luma_dc_entries);
    $readmemh(chroma_dc_path, chroma_dc_entries);
    $readmemh(luma_ac_path, luma_ac_entries);
    $readmemh(chroma_ac_path, chroma_ac_entries);
    luma_quant        = '0;
    luma_reciprocal   = '0;
    chroma_quant      = '0;
    chroma_reciprocal = '0;
    luma_dc_code      = '0;
    luma_dc_length    = '0;
    chroma_dc_code    = '0;
    chroma_dc_length  = '0;
    luma_ac_code      = '0;
    luma_ac_length    = '0;
    chroma_ac_code    = '0;
    chroma_ac_length  = '0;
    for (int index = 0; index < 64; index++) begin
      luma_quant[index*8+:8] = luma_quant_values[index];
      chroma_quant[index*8+:8] = chroma_quant_values[index];
      luma_reciprocal[index*25+:25] =
          (25'd16777216 + luma_quant_values[index] - 1'b1) / luma_quant_values[index];
      chroma_reciprocal[index*25+:25] =
          (25'd16777216 + chroma_quant_values[index] - 1'b1) / chroma_quant_values[index];
    end
    for (int index = 0; index < 12; index++) begin
      luma_dc_code[index*16+:16]   = luma_dc_entries[index][15:0];
      luma_dc_length[index*5+:5]   = luma_dc_entries[index][20:16];
      chroma_dc_code[index*16+:16] = chroma_dc_entries[index][15:0];
      chroma_dc_length[index*5+:5] = chroma_dc_entries[index][20:16];
    end
    for (int index = 0; index < 256; index++) begin
      luma_ac_code[index*16+:16]   = luma_ac_entries[index][15:0];
      luma_ac_length[index*5+:5]   = luma_ac_entries[index][20:16];
      chroma_ac_code[index*16+:16] = chroma_ac_entries[index][15:0];
      chroma_ac_length[index*5+:5] = chroma_ac_entries[index][20:16];
    end
    start                 = 1'b0;
    pixel_axis.tdata      = {8{8'd128}};
    pixel_axis.tkeep      = 8'hff;
    pixel_axis.tstrb      = 8'hff;
    pixel_axis.tlast      = 1'b0;
    pixel_axis.tid        = '0;
    pixel_axis.tdest      = '0;
    pixel_axis.tuser      = '0;
    pixel_axis.tvalid     = 1'b0;
    bitstream_axis.tready = 1'b1;
    output_index          = 0;
    input_beats           = 0;
    cycle_count           = 0;
    repeat (3) @(posedge clk);
    rst_n = 1'b1;
    @(negedge clk);
    start = 1'b1;
    @(negedge clk);
    start             = 1'b0;
    pixel_axis.tvalid = 1'b1;
    while (input_beats < expected_input_beats) begin
      @(negedge clk);
      pixel_axis.tlast = input_beats + 1 == expected_input_beats;
    end
    pixel_axis.tvalid = 1'b0;
    pixel_axis.tlast = 1'b0;
    timeout_cycles = 3000;
    while (!done && (timeout_cycles > 0)) begin
      @(negedge clk);
      timeout_cycles--;
    end
    if (timeout_cycles == 0) begin
      $fatal(1, "encode timeout: core=%0d builder=%0d block=%0d", u_dut.s_state_q,
             u_dut.u_mcu_builder.s_state_q, u_dut.u_block_encoder.s_state_q);
    end
    if (error_flag || output_index != expected_size) begin
      $fatal(1, "encode completion mismatch: err=%0d bytes=%0d expected=%0d", error_flag,
             output_index, expected_size);
    end
    $display("JPEG encode core tests passed cycles=%0d", cycle_count);
    $finish;
  end
endmodule
