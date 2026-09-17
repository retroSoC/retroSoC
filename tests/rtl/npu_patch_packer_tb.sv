`timescale 1ns / 1ps

// Vector-driven unit test for npu_patch_packer. Raw contents and expected
// packed rows come from $readmemh files selected by plusargs; the raw read
// port is modeled behaviorally with one-cycle synchronous latency and the
// packed write port is captured and compared row by row.
module npu_patch_packer_tb;
  logic                         clk_i = 1'b0;
  logic                         rst_n_i = 1'b0;
  logic                         start_valid_i = 1'b0;
  logic                         start_ready_o;
  npu_pkg::pack_mode_e          start_mode_i = npu_pkg::PackDense;
  logic                [  10:0] start_k_i = 11'd1;
  logic                [   3:0] start_positions_i = 4'd1;
  logic                [   3:0] start_channels_i = 4'd1;
  logic signed         [   7:0] start_in_zero_i = 8'd0;
  logic                         busy_o;
  logic                         done_pulse_o;
  logic                         raw_read_valid_o;
  logic                [  12:0] raw_read_addr_o;
  logic                [  31:0] raw_read_data_i;
  logic                         pack_write_valid_o;
  logic                [  12:0] pack_write_addr_o;
  logic                [  63:0] pack_write_data_o;
  logic                [   7:0] pack_write_strb_o;

  logic                [  31:0] raw_mem                           [0:2047];
  logic                [  31:0] raw_data_q = 32'd0;
  logic                [  63:0] expected_mem                      [0:1023];
  logic                [  63:0] actual_mem                        [0:1023];
  logic                [1023:0] written = 1024'd0;
  integer                       write_count = 0;
  integer                       done_count = 0;
  integer                       mode = 0;
  integer                       k_value = 1;
  integer                       m_value = 1;
  integer                       channels_value = 1;
  integer                       in_zero_value = 0;
  integer                       rows = 0;
  string                        raw_path;
  string                        expected_path;

  always #5 clk_i = ~clk_i;

  npu_patch_packer u_npu_patch_packer (
      .clk_i             (clk_i),
      .rst_n_i           (rst_n_i),
      .start_valid_i     (start_valid_i),
      .start_ready_o     (start_ready_o),
      .start_mode_i      (start_mode_i),
      .start_k_i         (start_k_i),
      .start_positions_i (start_positions_i),
      .start_channels_i  (start_channels_i),
      .start_in_zero_i   (start_in_zero_i),
      .busy_o            (busy_o),
      .done_pulse_o      (done_pulse_o),
      .raw_read_valid_o  (raw_read_valid_o),
      .raw_read_addr_o   (raw_read_addr_o),
      .raw_read_data_i   (raw_read_data_i),
      .pack_write_valid_o(pack_write_valid_o),
      .pack_write_addr_o (pack_write_addr_o),
      .pack_write_data_o (pack_write_data_o),
      .pack_write_strb_o (pack_write_strb_o)
  );

  // Raw gather half behavioral model: one-cycle synchronous read.
  assign raw_read_data_i = raw_data_q;
  always_ff @(posedge clk_i) begin
    if (raw_read_valid_o) begin
      raw_data_q <= raw_mem[raw_read_addr_o[12:2]];
    end
  end

  // Packed write capture with protocol checks.
  always_ff @(posedge clk_i) begin
    if (pack_write_valid_o) begin
      if (pack_write_strb_o !== 8'hff) $fatal(1, "pack write strobe not full");
      if (pack_write_addr_o[2:0] != 3'd0) $fatal(1, "pack write misaligned");
      if (written[pack_write_addr_o[12:3]]) $fatal(1, "duplicate pack write row");
      written[pack_write_addr_o[12:3]]    <= 1'b1;
      actual_mem[pack_write_addr_o[12:3]] <= pack_write_data_o;
      write_count                         <= write_count + 1;
    end
    if (done_pulse_o) begin
      done_count <= done_count + 1;
    end
  end

  initial begin
    integer cycles;
    if (!$value$plusargs("MODE=%d", mode)) $fatal(1, "MODE plusarg missing");
    if (!$value$plusargs("K=%d", k_value)) $fatal(1, "K plusarg missing");
    if (!$value$plusargs("M=%d", m_value)) $fatal(1, "M plusarg missing");
    if (!$value$plusargs("CHANNELS=%d", channels_value)) $fatal(1, "CHANNELS plusarg missing");
    if (!$value$plusargs("IN_ZERO=%d", in_zero_value)) $fatal(1, "IN_ZERO plusarg missing");
    if (!$value$plusargs("ROWS=%d", rows)) $fatal(1, "ROWS plusarg missing");
    if (!$value$plusargs("RAW=%s", raw_path)) $fatal(1, "RAW plusarg missing");
    if (!$value$plusargs("EXPECTED=%s", expected_path)) $fatal(1, "EXPECTED plusarg missing");
    $readmemh(raw_path, raw_mem);
    $readmemh(expected_path, expected_mem);

    repeat (4) @(negedge clk_i);
    rst_n_i = 1'b1;
    @(negedge clk_i);
    if (start_ready_o !== 1'b1) $fatal(1, "start_ready low in Idle");
    if (busy_o !== 1'b0) $fatal(1, "busy high in Idle");

    start_valid_i     = 1'b1;
    start_mode_i      = (mode == 0) ? npu_pkg::PackDense : npu_pkg::PackDepthwise;
    start_k_i         = 11'(k_value);
    start_positions_i = 4'(m_value);
    start_channels_i  = 4'(channels_value);
    start_in_zero_i   = 8'(in_zero_value);
    @(negedge clk_i);
    start_valid_i = 1'b0;
    if (busy_o !== 1'b1) $fatal(1, "busy not raised after start");
    if (start_ready_o !== 1'b0) $fatal(1, "start_ready high while running");

    cycles = 0;
    while ((done_pulse_o !== 1'b1) && (cycles < 400000)) begin
      @(negedge clk_i);
      cycles = cycles + 1;
    end
    if (done_pulse_o !== 1'b1) $fatal(1, "packer timeout after %0d cycles", cycles);
    @(negedge clk_i);
    if (busy_o !== 1'b0) $fatal(1, "busy stuck after done");
    if (done_count != 1) $fatal(1, "done pulse count %0d != 1", done_count);
    if (start_ready_o !== 1'b1) $fatal(1, "start_ready not restored");
    if (write_count != rows) $fatal(1, "row count %0d != expected %0d", write_count, rows);
    for (int row = 0; row < rows; row++) begin
      if (written[row] !== 1'b1) $fatal(1, "row %0d never written", row);
      if (actual_mem[row] !== expected_mem[row]) begin
        $fatal(1, "row %0d mismatch actual=%h expected=%h", row, actual_mem[row],
               expected_mem[row]);
      end
    end

    $display("NPU_PATCH_PACKER_PASS mode=%0d k=%0d m=%0d ch=%0d zero=%0d rows=%0d cycles=%0d",
             mode, k_value, m_value, channels_value, in_zero_value, rows, cycles);
    $finish;
  end
endmodule
