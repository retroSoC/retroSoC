`timescale 1ns / 1ps

module spill_register_tb;
  logic          clk_i = 1'b0;
  logic          rst_n_i = 1'b0;
  logic          flush_i = 1'b0;
  logic          valid_i = 1'b0;
  logic          ready_o;
  logic   [31:0] data_i = '0;
  logic          valid_o;
  logic          ready_i = 1'b0;
  logic   [31:0] data_o;

  logic   [31:0] expected             [0:511];
  integer        head = 0;
  integer        tail = 0;
  integer        cycle;
  logic          held_valid = 1'b0;
  logic   [31:0] held_data = '0;
  logic   [31:0] lfsr = 32'h1ACE_B00C;

  always #5 clk_i = ~clk_i;

  spill_register #(
      .DATA_WIDTH(32),
      .BYPASS    (1'b0)
  ) u_dut (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .flush_i(flush_i),
      .valid_i(valid_i),
      .ready_o(ready_o),
      .data_i (data_i),
      .valid_o(valid_o),
      .ready_i(ready_i),
      .data_o (data_o)
  );

  task automatic check_cycle;
    begin
      @(posedge clk_i);
      if (held_valid && (!valid_o || (data_o !== held_data))) begin
        $fatal(1, "spill register changed output while stalled");
      end
      if (valid_o && ready_i) begin
        if (head == tail || data_o !== expected[head]) begin
          $fatal(1, "spill register output ordering failure");
        end
        head = head + 1;
      end
      if (valid_i && ready_o) begin
        expected[tail] = data_i;
        tail           = tail + 1;
      end
      if (flush_i) begin
        head = tail;
      end
      held_valid = valid_o && !ready_i && !flush_i;
      held_data  = data_o;
    end
  endtask

  initial begin
    repeat (2) @(posedge clk_i);
    @(negedge clk_i);
    rst_n_i = 1'b1;

    // Sustained one-word-per-cycle traffic exercises simultaneous push/pop.
    for (cycle = 0; cycle < 16; cycle = cycle + 1) begin
      valid_i = 1'b1;
      ready_i = 1'b1;
      data_i  = 32'h1000_0000 + cycle;
      check_cycle();
      @(negedge clk_i);
    end

    // Fill both entries, hold the output, and check stability under pressure.
    ready_i = 1'b0;
    for (cycle = 0; cycle < 8; cycle = cycle + 1) begin
      valid_i = 1'b1;
      data_i  = 32'h2000_0000 + cycle;
      check_cycle();
      @(negedge clk_i);
    end

    valid_i = 1'b0;
    flush_i = 1'b1;
    check_cycle();
    @(negedge clk_i);
    flush_i = 1'b0;

    // Deterministic randomized backpressure covers all occupancy transitions.
    for (cycle = 0; cycle < 256; cycle = cycle + 1) begin
      lfsr    = {lfsr[30:0], lfsr[31] ^ lfsr[21] ^ lfsr[1] ^ lfsr[0]};
      valid_i = lfsr[0] | lfsr[3];
      ready_i = lfsr[1] | lfsr[5];
      data_i  = 32'h3000_0000 + cycle;
      check_cycle();
      @(negedge clk_i);
    end

    valid_i = 1'b0;
    ready_i = 1'b1;
    while (head != tail || valid_o) begin
      check_cycle();
      @(negedge clk_i);
    end

    $display("spill register ready/valid test passed");
    $finish;
  end

endmodule
