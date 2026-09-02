`timescale 1ns / 1ps

module clock_frequency_monitor_tb;
  logic       ref_clk_i = 1'b0;
  logic       monitored_clk_i = 1'b0;
  logic       rst_n_i = 1'b0;
  logic       clear_fault_i = 1'b0;
  logic       run_monitored = 1'b1;
  logic       alive_o;
  logic       fault_o;
  logic [7:0] edge_delta_o;

  always #5 ref_clk_i = ~ref_clk_i;
  always begin
    #2;
    if (run_monitored) monitored_clk_i = ~monitored_clk_i;
    else monitored_clk_i = 1'b0;
  end

  clock_frequency_monitor #(
      .CounterWidth(8),
      .WindowCycles(8)
  ) u_dut (
      .ref_clk_i        (ref_clk_i),
      .ref_rst_n_i      (rst_n_i),
      .monitored_clk_i  (monitored_clk_i),
      .monitored_rst_n_i(rst_n_i),
      .clear_fault_i    (clear_fault_i),
      .alive_o          (alive_o),
      .fault_o          (fault_o),
      .edge_delta_o     (edge_delta_o)
  );

  initial begin
    repeat (2) @(posedge ref_clk_i);
    rst_n_i = 1'b1;
    repeat (20) @(posedge ref_clk_i);
    if (!alive_o || fault_o || (edge_delta_o == 8'd0)) begin
      $fatal(1, "running clock was not measured as alive");
    end

    run_monitored = 1'b0;
    wait (fault_o);
    if (alive_o) $fatal(1, "stopped clock remained alive");
    @(negedge ref_clk_i);
    clear_fault_i = 1'b1;
    @(negedge ref_clk_i);
    clear_fault_i = 1'b0;
    @(negedge ref_clk_i);
    if (fault_o) $fatal(1, "clock fault did not clear");
    run_monitored = 1'b1;
    repeat (12) @(posedge ref_clk_i);
    if (!alive_o) $fatal(1, "restarted clock did not recover activity status");

    $display("Clock frequency activity and sticky fault test passed");
    $finish;
  end
endmodule
