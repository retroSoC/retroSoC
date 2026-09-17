`timescale 1ns / 1ps

// Scripted unit test for npu_vector: bias preload, lane-masked checked
// accumulation against TB-computed golden sums, exactly-once drain with
// backpressure, scalar aux max/sum (including all-negative and ties), aux and
// accumulation overflow faults, and clear_i release.
module npu_vector_tb;
  logic                     clk_i = 1'b0;
  logic                     rst_n_i = 1'b0;
  logic                     clear_i = 1'b0;
  logic                     start_valid_i = 1'b0;
  logic                     start_ready_o;
  logic        [ 7:0][31:0] start_bias_i = '0;
  logic                     dw_valid_i = 1'b0;
  logic                     dw_ready_o;
  logic        [ 7:0][ 7:0] dw_a_bytes_i = '0;
  logic        [ 7:0][ 7:0] dw_w_bytes_i = '0;
  logic signed [ 7:0]       dw_in_zero_i = 8'd0;
  logic        [ 7:0]       dw_lane_valid_i = 8'd0;
  logic                     aux_valid_i = 1'b0;
  logic        [ 1:0]       aux_op_i = 2'd0;
  logic signed [ 7:0]       aux_data_i = 8'd0;
  logic                     drain_valid_i = 1'b0;
  logic                     drain_data_valid_o;
  logic                     drain_data_ready_i = 1'b0;
  logic signed [31:0]       drain_data_o;
  logic                     drain_last_o;
  logic signed [31:0]       aux_result_o;
  logic                     busy_o;
  logic                     fault_sticky_o;
  logic        [ 2:0]       fault_lane_o;
  integer                   checks = 0;
  logic signed [63:0]       tb_sum                    [0:7];

  always #5 clk_i = ~clk_i;

  npu_vector u_npu_vector (
      .clk_i             (clk_i),
      .rst_n_i           (rst_n_i),
      .clear_i           (clear_i),
      .start_valid_i     (start_valid_i),
      .start_ready_o     (start_ready_o),
      .start_bias_i      (start_bias_i),
      .dw_valid_i        (dw_valid_i),
      .dw_ready_o        (dw_ready_o),
      .dw_a_bytes_i      (dw_a_bytes_i),
      .dw_w_bytes_i      (dw_w_bytes_i),
      .dw_in_zero_i      (dw_in_zero_i),
      .dw_lane_valid_i   (dw_lane_valid_i),
      .aux_valid_i       (aux_valid_i),
      .aux_op_i          (aux_op_i),
      .aux_data_i        (aux_data_i),
      .drain_valid_i     (drain_valid_i),
      .drain_data_valid_o(drain_data_valid_o),
      .drain_data_ready_i(drain_data_ready_i),
      .drain_data_o      (drain_data_o),
      .drain_last_o      (drain_last_o),
      .aux_result_o      (aux_result_o),
      .busy_o            (busy_o),
      .fault_sticky_o    (fault_sticky_o),
      .fault_lane_o      (fault_lane_o)
  );

  task automatic vec_start(input logic signed [31:0] bias_i[0:7]);
    @(negedge clk_i);
    start_valid_i = 1'b1;
    for (int lane = 0; lane < 8; lane++) begin
      start_bias_i[lane] = bias_i[lane];
      // Explicit sign extension: sv2v drops task-argument signedness.
      tb_sum[lane]       = {{32{bias_i[lane][31]}}, bias_i[lane]};
    end
    @(negedge clk_i);
    start_valid_i = 1'b0;
    if (busy_o !== 1'b1) $fatal(1, "busy not set after start");
    if (dw_ready_o !== 1'b1) $fatal(1, "dw_ready not set after start");
    if (aux_result_o !== 32'd0) $fatal(1, "aux sum register not cleared at start");
    checks = checks + 1;
  endtask

  task automatic dw_row(input logic [63:0] a_i, input logic [63:0] w_i,
                        input logic signed [7:0] zero_i, input logic [7:0] lanes_i);
    logic signed [ 8:0] a9;
    logic signed [ 7:0] w8;
    logic signed [31:0] prod;
    @(negedge clk_i);
    dw_valid_i      = 1'b1;
    dw_a_bytes_i    = a_i;
    dw_w_bytes_i    = w_i;
    dw_in_zero_i    = zero_i;
    dw_lane_valid_i = lanes_i;
    @(negedge clk_i);
    dw_valid_i      = 1'b0;
    dw_lane_valid_i = 8'd0;
    for (int lane = 0; lane < 8; lane++) begin
      if (lanes_i[lane]) begin
        a9           = 9'($signed(a_i[lane*8+:8])) - 9'($signed(zero_i));
        w8           = $signed(w_i[lane*8+:8]);
        prod         = a9 * w8;
        tb_sum[lane] = tb_sum[lane] + prod;
        if ((tb_sum[lane] > 64'sd2147483647) || (tb_sum[lane] < -64'sd2147483648)) begin
          $fatal(1, "TB golden overflow lane %0d", lane);
        end
      end
    end
    checks = checks + 1;
  endtask

  // Drives a row that must raise the sticky fault: the DUT freezes the sums,
  // so the golden model intentionally does not update.
  task automatic dw_row_fault(input logic [63:0] a_i, input logic [63:0] w_i,
                              input logic signed [7:0] zero_i, input logic [7:0] lanes_i);
    @(negedge clk_i);
    dw_valid_i      = 1'b1;
    dw_a_bytes_i    = a_i;
    dw_w_bytes_i    = w_i;
    dw_in_zero_i    = zero_i;
    dw_lane_valid_i = lanes_i;
    @(negedge clk_i);
    dw_valid_i      = 1'b0;
    dw_lane_valid_i = 8'd0;
    checks          = checks + 1;
  endtask

  task automatic drain_check;
    integer idx;
    logic   stalled;
    @(negedge clk_i);
    drain_valid_i = 1'b1;
    @(negedge clk_i);
    drain_valid_i = 1'b0;
    if (drain_data_valid_o !== 1'b1) $fatal(1, "drain did not start");
    idx     = 0;
    stalled = 1'b0;
    while (idx < 8) begin
      if (drain_data_o !== 32'(tb_sum[idx])) begin
        $fatal(1, "drain data mismatch lane=%0d got=%h expected=%h", idx, drain_data_o,
               32'(tb_sum[idx]));
      end
      if (drain_last_o !== (idx == 7)) $fatal(1, "drain_last mismatch at beat %0d", idx);
      if ((idx % 3 == 1) && !stalled) begin
        drain_data_ready_i = 1'b0;
        @(negedge clk_i);
        if (drain_data_valid_o !== 1'b1) $fatal(1, "drain valid dropped during stall");
        if (drain_data_o !== 32'(tb_sum[idx])) $fatal(1, "drain data changed during stall");
        stalled = 1'b1;
      end else begin
        drain_data_ready_i = 1'b1;
        stalled            = 1'b0;
        idx                = idx + 1;
        @(negedge clk_i);
      end
    end
    drain_data_ready_i = 1'b0;
    if (drain_data_valid_o !== 1'b0) $fatal(1, "drain did not complete");
    if (busy_o !== 1'b0) $fatal(1, "context not freed after final drain handshake");
    if (start_ready_o !== 1'b1) $fatal(1, "start_ready not restored after drain");
    checks = checks + 1;
  endtask

  task automatic aux_op(input logic [1:0] op_i, input logic signed [7:0] data_i);
    @(negedge clk_i);
    aux_valid_i = 1'b1;
    aux_op_i    = op_i;
    aux_data_i  = data_i;
    @(negedge clk_i);
    aux_valid_i = 1'b0;
    aux_op_i    = 2'd0;
    checks      = checks + 1;
  endtask

  task automatic aux_check(input logic signed [31:0] expected_i);
    if (aux_result_o !== expected_i) begin
      $fatal(1, "aux result mismatch got=%0d expected=%0d", aux_result_o, expected_i);
    end
    checks = checks + 1;
  endtask

  task automatic vec_clear;
    @(negedge clk_i);
    clear_i = 1'b1;
    @(negedge clk_i);
    clear_i = 1'b0;
    if (busy_o !== 1'b0) $fatal(1, "busy stuck after clear_i");
    if (fault_sticky_o !== 1'b0) $fatal(1, "fault stuck after clear_i");
    if (start_ready_o !== 1'b1) $fatal(1, "start_ready low after clear_i");
    if (aux_result_o !== 32'd0) $fatal(1, "aux not cleared by clear_i");
    checks = checks + 1;
  endtask

  initial begin
    logic signed [31:0] bias[0:7];
    repeat (4) @(negedge clk_i);
    rst_n_i = 1'b1;
    @(negedge clk_i);
    if (start_ready_o !== 1'b1) $fatal(1, "start_ready low after reset");
    if (busy_o !== 1'b0) $fatal(1, "busy high after reset");
    if (fault_sticky_o !== 1'b0) $fatal(1, "fault high after reset");
    if (dw_ready_o !== 1'b0) $fatal(1, "dw_ready high in Idle");
    if (drain_data_valid_o !== 1'b0) $fatal(1, "drain valid in Idle");

    // ---- scalar aux in Idle: max with negatives and ties, then sum ----
    aux_op(2'd1, 8'sd3);
    aux_check(32'd3);
    aux_op(2'd1, -8'sd5);
    aux_check(32'd3);
    aux_op(2'd1, 8'sd3);
    aux_check(32'd3);
    aux_op(2'd1, -8'sd128);
    aux_check(32'd3);
    aux_op(2'd1, 8'sd7);
    aux_check(32'd7);
    aux_op(2'd0, 8'sd100);
    aux_check(32'd7);
    aux_op(2'd2, 8'sd10);
    aux_check(32'd10);
    aux_op(2'd2, -8'sd20);
    aux_check(-32'd10);
    aux_op(2'd2, 8'sd100);
    aux_check(32'd90);

    // ---- bias preload and lane-masked accumulation ----
    bias = '{-32'd5, 32'd0, 32'd100, -32'd1000, 32'd7, 32'd64, -32'd1, 32'd255};
    vec_start(bias);
    if (aux_result_o !== 32'd0) $fatal(1, "start did not re-initialize aux");
    dw_row(64'h0102030405060708, 64'h0202020202020202, 8'sd0, 8'hff);
    dw_row(64'h7f80817f0080807f, 64'h8080808080808080, 8'sd0, 8'ha5);
    dw_row(64'h0000000000000000, 64'h7f7f7f7f7f7f7f7f, -8'sd128, 8'h0f);
    dw_row(64'hffffffffffffffff, 64'h0101010101010101, 8'sd127, 8'h00);
    dw_row(64'h8080808080808080, 64'h8181818181818181, 8'sd127, 8'hff);
    drain_check;

    // ---- second context: extreme centering and single-lane rows ----
    bias = '{32'd0, -32'd32640, 32'd32640, 32'd1, -32'd1, 32'd1000000, -32'd999, 32'd42};
    vec_start(bias);
    dw_row(64'h0000000000000080, 64'h0000000000000080, 8'sd127, 8'h80);
    dw_row(64'h000000000000007f, 64'h0000000000000080, -8'sd128, 8'h01);
    drain_check;

    // ---- accumulation overflow: single faulting lane ----
    bias = '{32'd0, 32'd0, 32'd0, 32'h7ffffff0, 32'd0, 32'd0, 32'd0, 32'd0};
    vec_start(bias);
    dw_row_fault(64'h0000000064000000, 64'h0000000064000000, 8'sd0, 8'h08);
    if (fault_sticky_o !== 1'b1) $fatal(1, "accumulation overflow fault missing");
    if (fault_lane_o !== 3'd3) $fatal(1, "fault lane %0d != 3", fault_lane_o);
    if (busy_o !== 1'b1) $fatal(1, "fault context not busy");
    if (dw_ready_o !== 1'b0) $fatal(1, "dw_ready high in Fault");
    @(negedge clk_i);
    drain_valid_i = 1'b1;
    @(negedge clk_i);
    drain_valid_i = 1'b0;
    if (drain_data_valid_o !== 1'b0) $fatal(1, "drain accepted in Fault");
    vec_clear;

    // ---- accumulation overflow: lowest of two faulting lanes wins ----
    bias = '{32'd0, 32'h7fffffff, 32'd0, 32'd0, 32'd0, 32'h7ffffffe, 32'd0, 32'd0};
    vec_start(bias);
    dw_row_fault(64'h0000010000000100, 64'h0000020000000100, 8'sd0, 8'h22);
    if (fault_sticky_o !== 1'b1) $fatal(1, "two-lane overflow fault missing");
    if (fault_lane_o !== 3'd1) $fatal(1, "lowest fault lane %0d != 1", fault_lane_o);
    vec_clear;

    // ---- aux sum positive overflow: dedicated fault-lane encoding ----
    bias = '{32'd0, 32'd0, 32'd0, 32'd0, 32'd0, 32'd0, 32'd0, 32'd0};
    vec_start(bias);
    aux_op(2'd2, 8'sd127);
    aux_check(32'd127);
    force u_npu_vector.s_aux_sum_q = 32'h7ffffff8;
    @(negedge clk_i);
    release u_npu_vector.s_aux_sum_q;
    aux_op(2'd2, 8'sd127);
    if (fault_sticky_o !== 1'b1) $fatal(1, "aux positive overflow fault missing");
    if (fault_lane_o !== 3'd7) $fatal(1, "aux fault lane encoding %0d != 7", fault_lane_o);
    vec_clear;

    // ---- aux sum negative overflow ----
    vec_start(bias);
    force u_npu_vector.s_aux_sum_q = -32'h7ffffff8;
    @(negedge clk_i);
    release u_npu_vector.s_aux_sum_q;
    aux_op(2'd2, -8'sd128);
    if (fault_sticky_o !== 1'b1) $fatal(1, "aux negative overflow fault missing");
    if (fault_lane_o !== 3'd7) $fatal(1, "aux fault lane encoding %0d != 7", fault_lane_o);
    vec_clear;

    // ---- drain request in Idle is ignored ----
    @(negedge clk_i);
    drain_valid_i = 1'b1;
    @(negedge clk_i);
    drain_valid_i = 1'b0;
    if (drain_data_valid_o !== 1'b0) $fatal(1, "drain accepted in Idle");
    if (busy_o !== 1'b0) $fatal(1, "Idle drain request disturbed the context");

    $display("NPU_VECTOR_PASS checks=%0d", checks);
    $finish;
  end

  initial begin
    #2000000;
    $fatal(1, "npu_vector_tb timeout");
  end
endmodule
