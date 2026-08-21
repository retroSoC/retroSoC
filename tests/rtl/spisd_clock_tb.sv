`timescale 1ns / 1ps

module spisd_clock_tb;
  logic          clk_i = 1'b0;
  logic          rst_n_i = 1'b0;
  logic          enable_i = 1'b0;
  logic          pause_i = 1'b0;
  logic   [15:0] half_period_i = 16'd2;
  logic          sck_o;
  logic          rise_tick_o;
  logic          fall_tick_o;
  logic          running_o;
  integer        s_rise_count;
  integer        s_fall_count;

  always #1 clk_i = ~clk_i;

  spisd_clock u_spisd_clock (
      .clk_i        (clk_i),
      .rst_n_i      (rst_n_i),
      .enable_i     (enable_i),
      .pause_i      (pause_i),
      .half_period_i(half_period_i),
      .sck_o        (sck_o),
      .rise_tick_o  (rise_tick_o),
      .fall_tick_o  (fall_tick_o),
      .running_o    (running_o)
  );

  always @(posedge clk_i) begin
    if (rise_tick_o) s_rise_count = s_rise_count + 1;
    if (fall_tick_o) s_fall_count = s_fall_count + 1;
    if (rise_tick_o && fall_tick_o) $fatal(1, "both SPI phases asserted");
  end

  initial begin
    s_rise_count = 0;
    s_fall_count = 0;
    repeat (2) @(posedge clk_i);
    rst_n_i  = 1'b1;
    enable_i = 1'b1;
    repeat (16) @(posedge clk_i);
    if ((s_rise_count != 4) || (s_fall_count != 4) || !running_o) begin
      $fatal(1, "phase counts mismatch: rise=%0d fall=%0d", s_rise_count, s_fall_count);
    end
    wait (!sck_o);
    pause_i = 1'b1;
    repeat (8) @(posedge clk_i);
    if (sck_o || !running_o || (s_rise_count != 4) || (s_fall_count != 4)) begin
      $fatal(1, "low-phase pause failed");
    end
    pause_i = 1'b0;
    wait (sck_o);
    enable_i = 1'b0;
    repeat (6) @(posedge clk_i);
    if (sck_o || running_o || (s_rise_count != 5) || (s_fall_count != 5)) begin
      $fatal(1, "clock did not finish the active phase before stopping");
    end
    half_period_i = 16'd0;
    enable_i      = 1'b1;
    repeat (4) @(posedge clk_i);
    if ((s_rise_count != 7) || (s_fall_count != 7)) begin
      $fatal(1, "zero divider did not map to one cycle");
    end
    $display("SPISD phase clock and low-only pause test passed");
    $finish;
  end
endmodule
