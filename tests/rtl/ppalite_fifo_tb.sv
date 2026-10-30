`timescale 1ns / 1ps
module ppalite_fifo_tb;
  logic          clk_i = 1'b0;
  logic          rst_n_i = 1'b0;
  logic          flush_i = 1'b0;
  logic          push_i = 1'b0;
  logic   [31:0] push_data_i = 32'd0;
  logic          pop_i = 1'b0;
  logic   [31:0] pop_data_o;
  logic          full_o;
  logic          empty_o;
  logic   [ 3:0] count_o;
  logic   [31:0] ref_items           [0:7];
  logic   [31:0] random_state;
  integer        ref_count;
  integer        ref_read;
  integer        ref_write;
  always #5 clk_i = ~clk_i;

  ppalite_fifo #(
      .DataWidth  (32),
      .BufferDepth(8)
  ) u_dut (
      .clk_i      (clk_i),
      .rst_n_i    (rst_n_i),
      .flush_i    (flush_i),
      .push_i     (push_i),
      .push_data_i(push_data_i),
      .pop_i      (pop_i),
      .pop_data_o (pop_data_o),
      .full_o     (full_o),
      .empty_o    (empty_o),
      .count_o    (count_o)
  );

  task automatic drive(input logic push, input logic pop, input logic [31:0] word);
    @(negedge clk_i);
    push_i      = push;
    pop_i       = pop;
    push_data_i = word;
    @(negedge clk_i);
    push_i = 1'b0;
    pop_i  = 1'b0;
  endtask

  task automatic expect_count(input logic [3:0] expected);
    if (count_o !== expected)
      $fatal(1, "PPALITE FIFO count got=%0d expected=%0d", count_o, expected);
    if ((count_o > 8) || (full_o !== (count_o == 8)) || (empty_o !== (count_o == 0)))
      $fatal(1, "PPALITE FIFO bounds flags");
  endtask

  initial begin
    repeat (3) @(negedge clk_i);
    rst_n_i = 1'b1;
    repeat (2) @(negedge clk_i);
    expect_count(0);
    drive(1'b1, 1'b1, 32'h11);
    expect_count(1);
    drive(1'b0, 1'b1, 32'd0);
    expect_count(0);
    for (integer index = 0; index < 8; index++) drive(1'b1, 1'b0, 32'(index + 1));
    expect_count(8);
    drive(1'b1, 1'b1, 32'hff);
    expect_count(7);
    if (pop_data_o !== 32'd2) $fatal(1, "PPALITE full push must not look ahead");
    for (integer index = 2; index <= 8; index++) begin
      if (pop_data_o !== 32'(index)) $fatal(1, "PPALITE FIFO ordering");
      drive(1'b0, 1'b1, 32'd0);
    end
    expect_count(0);
    ref_count    = 0;
    ref_read     = 0;
    ref_write    = 0;
    random_state = 32'h5050_4131;
    for (integer iteration = 0; iteration < 512; iteration++) begin
      random_state = (random_state >> 1) ^ (random_state[0] ? 32'h8020_0003 : 32'd0);
      if (ref_count > 0 && pop_data_o !== ref_items[ref_read])
        $fatal(1, "PPALITE random FIFO head mismatch iteration=%0d", iteration);
      drive(random_state[0], random_state[1], random_state);
      if (random_state[1] && (ref_count > 0)) ref_read = (ref_read + 1) & 7;
      if (random_state[0] && (ref_count < 8)) begin
        ref_items[ref_write] = random_state;
        ref_write            = (ref_write + 1) & 7;
      end
      case ({
        random_state[0] && (ref_count < 8), random_state[1] && (ref_count > 0)
      })
        2'b10:   ref_count++;
        2'b01:   ref_count--;
        default: ;
      endcase
      expect_count(ref_count[3:0]);
      if (ref_count > 0 && pop_data_o !== ref_items[ref_read])
        $fatal(1, "PPALITE random FIFO post-edge ordering iteration=%0d", iteration);
    end
    flush_i = 1'b1;
    @(negedge clk_i);
    flush_i = 1'b0;
    expect_count(0);
    $display("PPALITE_P1_COVER PPL-V07 randomized-preedge-fifo-conservation");
    $display("PPALITE_P1_PASS ppalite_fifo_tb");
    $finish;
  end

  initial begin
    #100000;
    $fatal(1, "SIM_TEST_TIMEOUT PPALITE FIFO");
  end
endmodule
