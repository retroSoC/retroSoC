`timescale 1ns / 1ps
module tiny_r2_fifo_reset_tb;
  logic s_clk = 0, s_reset_n = 1, s_watchdog = 0;
  logic s_por_n, s_system_n, s_ready_n;
  logic [16:0] s_leaf_n;
  logic s_flush = 0, s_push = 0, s_pop = 0, s_full, s_empty;
  logic [7:0] s_input = 0, s_output;
  logic [2:0] s_count;
  logic [7:0] s_model [4];
  int s_head = 0, s_tail = 0, s_used = 0;
  logic [31:0] s_random = 32'h12345678;
  tiny_reset_tree u_tree (
      .clk_i               (s_clk),
      .rst_n_i             (s_reset_n),
      .watchdog_reset_req_i(s_watchdog),
      .por_rst_n_o         (s_por_n),
      .system_rst_n_o      (s_system_n),
      .leaf_rst_n_o        (s_leaf_n),
      .cpu_ready_rst_n_o   (s_ready_n)
  );
  fifo #(
      .DATA_WIDTH  (8),
      .BUFFER_DEPTH(4)
  ) u_fifo (
      .clk_i  (s_clk),
      .rst_n_i(s_leaf_n[6]),
      .flush_i(s_flush),
      .push_i (s_push),
      .full_o (s_full),
      .dat_i  (s_input),
      .pop_i  (s_pop),
      .empty_o(s_empty),
      .dat_o  (s_output),
      .cnt_o  (s_count)
  );

  task automatic check_visible;
    if (s_count !== 3'(s_used) || s_empty !== (s_used == 0) || s_full !== (s_used == 4))
      $fatal(1, "FIFO control disagrees with independent queue");
    if (s_output !== ((s_used == 0) ? 8'd0 : s_model[s_head]))
      $fatal(1, "stale or incorrect FIFO payload became visible");
  endtask

  task automatic cycle;
    bit take_push, take_pop;
    take_push = s_push && ((s_used < 4) || (s_pop && s_used != 0));
    take_pop  = s_pop && s_used != 0;
    if (!s_leaf_n[6] || s_flush) begin
      s_head = 0;
      s_tail = 0;
      s_used = 0;
    end else begin
      if (take_pop) begin
        s_head = (s_head + 1) % 4;
        s_used--;
      end
      if (take_push) begin
        s_model[s_tail] = s_input;
        s_tail          = (s_tail + 1) % 4;
        s_used++;
      end
    end
    #5 s_clk = 1;
    #1;
    check_visible();
    #4 s_clk = 0;
  endtask

  initial begin
    #1 s_reset_n = 0;
    #1 s_reset_n = 1;
    repeat (16) cycle();
    s_push = 1;
    for (int value = 1; value <= 4; value++) begin
      s_input = 8'(value);
      cycle();
    end
    s_pop   = 1;
    s_input = 8'h55;
    cycle();  // Full simultaneous pop/push must accept replacement.
    s_flush = 1;
    cycle();  // Flush wins over both operations; data output becomes zero.
    s_flush = 0;
    s_pop   = 0;
    s_input = 8'ha5;
    cycle();
    #2 s_watchdog = 1;
    #1;
    s_head = 0;
    s_tail = 0;
    s_used = 0;
    check_visible();
    #50;  // Reset and empty masking must not need a running clock.
    check_visible();
    s_watchdog = 0;
    s_push     = 0;
    repeat (11) cycle();
    for (int trial = 0; trial < 1024; trial++) begin
      s_random ^= s_random << 13;
      s_random ^= s_random >> 17;
      s_random ^= s_random << 5;
      s_push  = s_random[0];
      s_pop   = s_random[1];
      s_flush = (s_random[7:2] == 0);
      s_input = s_random[15:8];
      cycle();
    end
    $display("SIM_TEST_PASS Tiny R2 FIFO reset");
    $finish;
  end
  initial begin
    #20000;
    $fatal(1, "SIM_TEST_TIMEOUT Tiny R2 FIFO reset");
  end
endmodule
