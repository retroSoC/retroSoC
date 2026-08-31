`timescale 1ns / 1ps

module jpeg_table_store_tb;
  logic        clk = 1'b0;
  logic        rst_n = 1'b0;
  logic [ 1:0] portal_context;
  logic [ 3:0] portal_kind;
  logic [ 7:0] portal_index;
  logic [31:0] portal_write_data;
  logic        portal_write;
  logic        portal_commit;
  logic        portal_default;
  logic        portal_clear;
  logic [31:0] portal_read_data;
  logic [31:0] portal_status;
  logic        lookup;
  logic [ 1:0] lookup_context;
  logic [ 3:0] lookup_kind;
  logic [ 7:0] lookup_index;
  logic [31:0] lookup_data;
  logic        lookup_valid;
  logic        lookup_err;

  always #5 clk = ~clk;

  jpeg_table_store u_dut (
      .clk_i              (clk),
      .rst_n_i            (rst_n),
      .portal_context_i   (portal_context),
      .portal_kind_i      (portal_kind),
      .portal_index_i     (portal_index),
      .portal_write_data_i(portal_write_data),
      .portal_write_i     (portal_write),
      .portal_commit_i    (portal_commit),
      .portal_default_i   (portal_default),
      .portal_clear_i     (portal_clear),
      .portal_read_data_o (portal_read_data),
      .portal_status_o    (portal_status),
      .lookup_i           (lookup),
      .lookup_context_i   (lookup_context),
      .lookup_kind_i      (lookup_kind),
      .lookup_index_i     (lookup_index),
      .lookup_data_o      (lookup_data),
      .lookup_valid_o     (lookup_valid),
      .lookup_err_o       (lookup_err)
  );

  task automatic portal_pulse(input logic write_i, input logic commit_i, input logic clear_i);
    begin
      @(negedge clk);
      portal_write  = write_i;
      portal_commit = commit_i;
      portal_clear  = clear_i;
      @(negedge clk);
      portal_write  = 1'b0;
      portal_commit = 1'b0;
      portal_clear  = 1'b0;
    end
  endtask

  task automatic lookup_word(input logic [1:0] context_i, input logic [3:0] kind_i,
                             input logic [7:0] index_i, input logic [31:0] expected_i);
    begin
      @(negedge clk);
      lookup_context = context_i;
      lookup_kind    = kind_i;
      lookup_index   = index_i;
      lookup         = 1'b1;
      @(negedge clk);
      lookup = 1'b0;
      if (!lookup_valid || lookup_err || lookup_data != expected_i) begin
        $fatal(1, "lookup mismatch: valid=%0d err=%0d data=%h", lookup_valid, lookup_err,
               lookup_data);
      end
    end
  endtask

  initial begin
    portal_context    = 2'd0;
    portal_kind       = 4'd0;
    portal_index      = 8'd0;
    portal_write_data = 32'd0;
    portal_write      = 1'b0;
    portal_commit     = 1'b0;
    portal_default    = 1'b0;
    portal_clear      = 1'b0;
    lookup            = 1'b0;
    lookup_context    = 2'd0;
    lookup_kind       = 4'd0;
    lookup_index      = 8'd0;
    repeat (3) @(posedge clk);
    rst_n             = 1'b1;

    portal_context    = 2'd2;
    portal_kind       = 4'd0;
    portal_index      = 8'd7;
    portal_write_data = 32'h01020304;
    portal_pulse(1'b1, 1'b0, 1'b0);
    portal_pulse(1'b0, 1'b1, 1'b0);
    if (!portal_status[3]) $fatal(1, "context commit did not set valid");
    lookup_word(2'd2, 4'd0, 8'd7, 32'h01020304);

    portal_context    = 2'd3;
    portal_kind       = 4'd11;
    portal_index      = 8'd255;
    portal_write_data = 32'ha5a55a5a;
    portal_pulse(1'b1, 1'b0, 1'b0);
    portal_pulse(1'b0, 1'b1, 1'b0);
    lookup_word(2'd3, 4'd11, 8'd255, 32'ha5a55a5a);

    portal_kind  = 4'd0;
    portal_index = 8'd64;
    portal_pulse(1'b1, 1'b0, 1'b0);
    if (!portal_status[11]) $fatal(1, "invalid portal index was not recorded");
    portal_pulse(1'b0, 1'b0, 1'b1);
    if (portal_status[11] || portal_status[3]) $fatal(1, "context clear failed");
    $display("JPEG table store tests passed");
    $finish;
  end
endmodule
