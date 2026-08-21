`timescale 1ns / 1ps

module sdio_clock_tb;
  logic          clk_i = 1'b0;
  logic          rst_n_i = 1'b0;
  logic          enable_i = 1'b0;
  logic   [15:0] half_period_i = 16'd2;
  logic          sck_o;
  logic          launch_tick_o;
  logic          sample_tick_o;
  logic          running_o;
  integer        launch_count;
  integer        sample_count;

  always #1 clk_i = ~clk_i;

  sdio_clock u_sdio_clock (
      .clk_i        (clk_i),
      .rst_n_i      (rst_n_i),
      .enable_i     (enable_i),
      .half_period_i(half_period_i),
      .sck_o        (sck_o),
      .launch_tick_o(launch_tick_o),
      .sample_tick_o(sample_tick_o),
      .running_o    (running_o)
  );

  always @(posedge clk_i) begin
    if (launch_tick_o) launch_count = launch_count + 1;
    if (sample_tick_o) sample_count = sample_count + 1;
  end

  initial begin
    launch_count = 0;
    sample_count = 0;
    repeat (2) @(posedge clk_i);
    rst_n_i  = 1'b1;
    enable_i = 1'b1;
    repeat (8) @(posedge clk_i);
    if ((launch_count != 2) || (sample_count != 2) || !running_o) begin
      $fatal(1, "phase counts mismatch: launch=%0d sample=%0d running=%b", launch_count,
             sample_count, running_o);
    end
    enable_i = 1'b0;
    repeat (4) @(posedge clk_i);
    if (sck_o || running_o) begin
      $fatal(1, "clock did not stop on a complete low phase");
    end
    $display("SDIO phase clock test passed");
    $finish;
  end
endmodule
