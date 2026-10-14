`timescale 1ns / 1ps
module tiny_clock_output_tb;
  logic ref_clk = 0, sys_clk = 0, mem_clk = 0, pclk = 0, rst_n = 0;
  logic [31:0] control = 0;
  wire clk_out, enabled;
  always #20 ref_clk = !ref_clk;
  always #2.5 sys_clk = !sys_clk;
  always #5 mem_clk = !mem_clk;
  always #10 pclk = !pclk;
  tiny_clock_output u_dut (
      .clk_ref_i   (ref_clk),
      .clk_sys_i   (sys_clk),
      .clk_mem_i   (mem_clk),
      .clk_periph_i(pclk),
      .rst_n_i     (rst_n),
      .control_i   (control),
      .clk_o       (clk_out),
      .enable_o    (enabled)
  );
  task automatic measure(input integer source, divisor, input realtime expected);
    realtime previous_edge;
    @(negedge ref_clk);
    control = (divisor << 8) | source;
    repeat (12) @(negedge ref_clk);
    if (!enabled) $fatal(1, "CLKOUT enable missing");
    @(posedge clk_out);
    previous_edge = $realtime;
    repeat (8) begin
      @(posedge clk_out);
      if ($realtime - previous_edge < expected - 0.001 ||
          $realtime - previous_edge > expected + 0.001)
        $fatal(1, "CLKOUT source/divisor period mismatch source=%0d", source);
      previous_edge = $realtime;
    end
    @(negedge ref_clk);
    control = 0;
    repeat (12) @(negedge ref_clk);
    if (enabled || clk_out) $fatal(1, "CLKOUT disable not acknowledged low");
  endtask
  initial begin
    repeat (4) @(negedge ref_clk);
    rst_n = 1;
    repeat (4) @(negedge ref_clk);
    if (enabled || clk_out) $fatal(1, "CLKOUT active at cold reset");
    measure(1, 1, 80.0);
    measure(2, 5, 50.0);
    measure(3, 3, 60.0);
    measure(4, 2, 80.0);
    $display("SIM_TEST_PASS Tiny CLKOUT measured sources/divisors/off");
    $finish;
  end
  initial begin
    #100000;
    $fatal(1, "SIM_TEST_TIMEOUT CLKOUT");
  end
endmodule
