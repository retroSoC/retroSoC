`timescale 1ns / 1ps

module tiny_clock_reset_subsystem_tb;
  logic       ref_clk_i = 1'b0;
  logic       rst_n_i = 1'b0;
  logic [1:0] profile = 2'd0;
  logic       apply = 1'b0;
  logic [1:0] current_profile;
  logic busy, fault;
  logic sys_clk, mem_clk, pclk;
  logic sys_rst_n, mem_rst_n, pclk_rst_n;
  logic [31:0] xin_hz, ref_hz, sys_hz, mem_hz, pclk_hz;

  always #5 ref_clk_i = !ref_clk_i;

  tiny_clock_reset_subsystem #(
      .RefClkHz(24_000_000),
      .HavePll (1'b0)
  ) u_dut (
      .ref_clk_i        (ref_clk_i),
      .rst_n_i          (rst_n_i),
      .profile_i        (profile),
      .apply_i          (apply),
      .idle_i           (1'b1),
      .clients_idle_i   (1'b1),
      .warm_reset_i     (1'b0),
      .timeout_i        (32'd512),
      .system_request_i (1'b0),
      .command_ack_i    (1'b1),
      .fault_code_o     (),
      .done_o           (),
      .block_o          (),
      .ref_clk_o        (),
      .ref_rst_n_o      (),
      .system_reset_n_o (),
      .pll_locked_o     (),
      .pll_selected_o   (),
      .current_profile_o(current_profile),
      .busy_o           (busy),
      .fault_o          (fault),
      .sys_clk_o        (sys_clk),
      .mem_clk_o        (mem_clk),
      .pclk_o           (pclk),
      .sys_rst_n_o      (sys_rst_n),
      .mem_rst_n_o      (mem_rst_n),
      .pclk_rst_n_o     (pclk_rst_n),
      .xin_hz_o         (xin_hz),
      .ref_hz_o         (ref_hz),
      .sys_hz_o         (sys_hz),
      .mem_hz_o         (mem_hz),
      .pclk_hz_o        (pclk_hz)
  );

  task automatic apply_profile(input logic [1:0] requested);
    begin
      @(negedge ref_clk_i);
      profile = requested;
      apply   = 1'b1;
      @(negedge ref_clk_i);
      apply = 1'b0;
      repeat (600) @(negedge ref_clk_i);
    end
  endtask

  initial begin
    repeat (5) @(negedge ref_clk_i);
    rst_n_i = 1'b1;
    repeat (32) @(negedge ref_clk_i);
    if (current_profile != 0 || sys_hz != 24_000_000 || mem_hz != 24_000_000 ||
        pclk_hz != 24_000_000 || !sys_rst_n || !mem_rst_n || !pclk_rst_n) begin
      $fatal(1, "SAFE24 backend state mismatch");
    end
    apply_profile(2'd1);
    if (current_profile != 1 || fault || sys_hz != 24_000_000) begin
      $fatal(1, "external profile handling mismatch");
    end
    apply_profile(2'd2);
    if (!fault || current_profile != 1) $fatal(1, "unsupported PLL was accepted");
    $display("SIM_TEST_PASS Tiny clock/reset backend");
    $finish;
  end

  initial begin
    #100000;
    $fatal(1, "SIM_TEST_TIMEOUT Tiny clock/reset backend");
  end
endmodule
