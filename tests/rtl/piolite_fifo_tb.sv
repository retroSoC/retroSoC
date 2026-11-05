`timescale 1ns / 1ps
module piolite_fifo_tb;
  logic          clk_i = 1'b0;
  logic          rst_n_i = 1'b0;
  logic          flush_i = 1'b0;
  logic          push_i = 1'b0;
  logic   [31:0] push_data_i = 32'd0;
  logic          pop_i = 1'b0;
  logic   [31:0] pop_data_o;
  logic          push_accept_o;
  logic          pop_accept_o;
  logic          full_o;
  logic          empty_o;
  logic   [ 3:0] count_o;
  logic   [31:0] ref_items           [0:7];
  logic   [31:0] random_state;
  integer        ref_count;
  integer        ref_read;
  integer        ref_write;
  always #5 clk_i = ~clk_i;

  piolite_fifo u_dut (
      .clk_i        (clk_i),
      .rst_n_i      (rst_n_i),
      .flush_i      (flush_i),
      .push_i       (push_i),
      .push_data_i  (push_data_i),
      .pop_i        (pop_i),
      .pop_data_o   (pop_data_o),
      .push_accept_o(push_accept_o),
      .pop_accept_o (pop_accept_o),
      .full_o       (full_o),
      .empty_o      (empty_o),
      .count_o      (count_o)
  );

  task automatic drive(input logic push, input logic pop, input logic [31:0] word);
    @(negedge clk_i);
    push_i      = push;
    pop_i       = pop;
    push_data_i = word;
    #1;
    if (push_accept_o !== (push && !full_o)) $fatal(1, "PIOLITE FIFO push admission");
    if (pop_accept_o !== (pop && !empty_o)) $fatal(1, "PIOLITE FIFO pop admission");
    @(negedge clk_i);
    push_i = 1'b0;
    pop_i  = 1'b0;
  endtask

  task automatic expect_count(input logic [3:0] expected);
    if (count_o !== expected)
      $fatal(1, "PIOLITE FIFO count got=%0d expected=%0d", count_o, expected);
    if ((count_o > 8) || (full_o !== (count_o == 8)) || (empty_o !== (count_o == 0)))
      $fatal(1, "PIOLITE FIFO bounds flags");
  endtask

  task automatic random_fifo;
    logic push;
    logic pop;
    logic take_push;
    logic take_pop;
    ref_count    = 0;
    ref_read     = 0;
    ref_write    = 0;
    random_state = 32'h50494f36;
    for (integer iteration = 0; iteration < 512; iteration++) begin
      random_state = (random_state >> 1) ^ (random_state[0] ? 32'h8020_0003 : 32'd0);
      push         = random_state[0];
      pop          = random_state[1];
      take_push    = push && (ref_count < 8);
      take_pop     = pop && (ref_count > 0);
      if (ref_count > 0 && pop_data_o !== ref_items[ref_read])
        $fatal(1, "PIOLITE random FIFO head mismatch iteration=%0d", iteration);
      drive(push, pop, random_state);
      if (take_pop) ref_read = (ref_read + 1) & 7;
      if (take_push) begin
        ref_items[ref_write] = random_state;
        ref_write            = (ref_write + 1) & 7;
      end
      case ({
        take_push, take_pop
      })
        2'b10:   ref_count++;
        2'b01:   ref_count--;
        default: ;
      endcase
      expect_count(ref_count[3:0]);
      if (ref_count > 0 && pop_data_o !== ref_items[ref_read])
        $fatal(1, "PIOLITE random FIFO post-edge ordering iteration=%0d", iteration);
    end
    $display("PIOLITE_P2_COVER PL-V06 randomized-preedge-fifo-conservation");
  endtask

  initial begin
    repeat (3) @(negedge clk_i);
    rst_n_i = 1'b1;
    repeat (2) @(negedge clk_i);
    expect_count(0);
    drive(1'b1, 1'b1, 32'd0);
    expect_count(1);
    drive(1'b0, 1'b1, 32'd0);
    expect_count(0);
    for (integer index = 0; index < 8; index++) drive(1'b1, 1'b0, 32'(index + 1));
    expect_count(8);
    if (pop_data_o !== 1) $fatal(1, "PIOLITE FIFO oldest head");
    drive(1'b1, 1'b1, 32'd99);
    expect_count(7);
    for (integer index = 1; index < 8; index++) begin
      if (pop_data_o !== 32'(index + 1)) $fatal(1, "PIOLITE full pre-edge ordering");
      drive(1'b0, 1'b1, 32'd0);
    end
    expect_count(0);
    drive(1'b1, 1'b0, 32'd10);
    drive(1'b1, 1'b0, 32'd11);
    drive(1'b1, 1'b0, 32'd12);
    if (pop_data_o !== 10) $fatal(1, "PIOLITE FIFO intermediate head");
    drive(1'b1, 1'b1, 32'd13);
    expect_count(3);
    if (pop_data_o !== 11) $fatal(1, "PIOLITE simultaneous pop was not old head");
    flush_i = 1'b1;
    @(negedge clk_i);
    flush_i = 1'b0;
    expect_count(0);
    random_fifo();
    $display("PIOLITE_P2_PASS piolite_fifo_tb");
    $finish;
  end

  initial begin
    #100000;
    $fatal(1, "SIM_TEST_TIMEOUT PIOLITE FIFO");
  end
endmodule
