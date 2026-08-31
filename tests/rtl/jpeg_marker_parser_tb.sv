`timescale 1ns / 1ps

module jpeg_marker_parser_tb;
  logic          clk = 1'b0;
  logic          rst_n = 1'b0;
  logic          start;
  logic   [ 7:0] byte_data;
  logic          byte_valid;
  logic          byte_ready;
  logic   [ 3:0] table_kind;
  logic   [ 7:0] table_index;
  logic   [31:0] table_data;
  logic          table_write;
  logic          table_commit;
  logic          header_valid;
  logic          header_ready;
  logic          entropy;
  logic   [15:0] width;
  logic   [15:0] height;
  logic   [ 1:0] sampling;
  logic   [ 1:0] component_count;
  logic   [15:0] restart_interval;
  logic          error_flag;
  logic   [ 4:0] error_code;
  logic   [ 7:0] input_bytes      [0:4095];
  integer        input_size;
  integer        input_index;
  integer        table_writes;
  integer        table_commits;
  logic          quant_zero_seen;
  logic          dc_zero_seen;
  logic   [31:0] actual_tables    [0:3071];
  logic   [31:0] expected_tables  [0:3071];
  string         hex_path;
  string         tables_path;

  always #5 clk = ~clk;

  assign byte_data  = input_bytes[input_index];
  assign byte_valid = input_index < input_size;

  jpeg_marker_parser u_dut (
      .clk_i             (clk),
      .rst_n_i           (rst_n),
      .start_i           (start),
      .table_context_i   (2'd2),
      .byte_i            (byte_data),
      .byte_valid_i      (byte_valid),
      .byte_ready_o      (byte_ready),
      .table_context_o   (),
      .table_kind_o      (table_kind),
      .table_index_o     (table_index),
      .table_data_o      (table_data),
      .table_write_o     (table_write),
      .table_commit_o    (table_commit),
      .header_valid_o    (header_valid),
      .header_ready_i    (header_ready),
      .entropy_o         (entropy),
      .width_o           (width),
      .height_o          (height),
      .sampling_o        (sampling),
      .component_count_o (component_count),
      .component_id_o    (),
      .component_factor_o(),
      .quant_table_o     (),
      .dc_table_o        (),
      .ac_table_o        (),
      .restart_interval_o(restart_interval),
      .marker_count_o    (),
      .error_o           (error_flag),
      .error_code_o      (error_code)
  );

  always @(posedge clk) begin
    if (rst_n && byte_valid && byte_ready) begin
      input_index <= input_index + 1;
    end
    if (rst_n && table_write) begin
      actual_tables[(table_kind*256)+table_index] <= table_data;
      table_writes                                <= table_writes + 1;
      if ((table_kind == 4'd0) && (table_index == 8'd0) && (table_data[7:0] == 8'd8)) begin
        quant_zero_seen <= 1'b1;
      end
      if ((table_kind == 4'd4) && (table_index == 8'd0) && (table_data == 32'h00020000)) begin
        dc_zero_seen <= 1'b1;
      end
    end
    if (rst_n && table_commit) begin
      table_commits <= table_commits + 1;
    end
  end

  initial begin
    if (!$value$plusargs(
            "jpeg_hex=%s", hex_path
        ) || !$value$plusargs(
            "tables_hex=%s", tables_path
        ) || !$value$plusargs(
            "jpeg_size=%d", input_size
        )) begin
      $fatal(1, "JPEG parser test requires jpeg_hex and jpeg_size plusargs");
    end
    $readmemh(hex_path, input_bytes);
    $readmemh(tables_path, expected_tables);
    input_index     = 0;
    table_writes    = 0;
    table_commits   = 0;
    quant_zero_seen = 1'b0;
    dc_zero_seen    = 1'b0;
    for (int index = 0; index < 3072; index++) begin
      actual_tables[index] = 32'd0;
    end
    start        = 1'b0;
    header_ready = 1'b0;
    repeat (3) @(posedge clk);
    rst_n = 1'b1;
    @(negedge clk);
    start = 1'b1;
    @(negedge clk);
    start = 1'b0;
    while (!header_valid && !error_flag) @(negedge clk);
    if (error_flag)
      $fatal(1, "header parser failed with code %0d at byte %0d", error_code, input_index);
    if (width != 16'd17 || height != 16'd15 || sampling != 2'd3 ||
        component_count != 2'd3 || restart_interval != 16'd1 || table_writes != 476 ||
        table_commits != 1 || !quant_zero_seen || !dc_zero_seen) begin
      $fatal(
          1,
          "header result mismatch: %0dx%0d sampling=%0d components=%0d restart=%0d writes=%0d commits=%0d q=%0d dc=%0d",
          width, height, sampling, component_count, restart_interval, table_writes, table_commits,
          quant_zero_seen, dc_zero_seen);
    end
    for (int index = 0; index < 3072; index++) begin
      if (actual_tables[index] != expected_tables[index]) begin
        $fatal(1, "expanded table mismatch at %0d: got=%h expected=%h", index,
               actual_tables[index], expected_tables[index]);
      end
    end
    header_ready = 1'b1;
    @(negedge clk);
    if (!entropy) $fatal(1, "parser did not enter entropy mode");
    $display("JPEG marker parser tests passed");
    $finish;
  end
endmodule
