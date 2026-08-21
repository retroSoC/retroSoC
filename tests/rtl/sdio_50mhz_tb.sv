// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of the Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

`timescale 1ns / 1ps

module sdio_50mhz_tb;
  logic          clk_i = 1'b0;
  logic          rst_n_i = 1'b0;
  logic          enable_i = 1'b0;
  logic   [15:0] half_period_i = 16'd1;
  logic          sck_o;
  logic          launch_tick_o;
  logic          sample_tick_o;
  logic          running_o;
  integer        rising_count;
  integer        falling_count;
  logic          previous_sck;

  always #5 clk_i = ~clk_i;

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
    if (rst_n_i && (sck_o != previous_sck)) begin
      if (sck_o) begin
        rising_count = rising_count + 1;
      end else begin
        falling_count = falling_count + 1;
      end
    end
    previous_sck = sck_o;
  end

  initial begin
    rising_count  = 0;
    falling_count = 0;
    previous_sck  = 1'b0;
    repeat (2) @(posedge clk_i);
    rst_n_i  = 1'b1;
    enable_i = 1'b1;
    repeat (12) @(posedge clk_i);
    if ((rising_count < 5) || (falling_count < 5) ||
        (rising_count > falling_count + 1) ||
        (falling_count > rising_count + 1) || !running_o) begin
      $fatal(1, "50 MHz phase count mismatch rise=%0d fall=%0d running=%b", rising_count,
             falling_count, running_o);
    end
    enable_i = 1'b0;
    repeat (3) @(posedge clk_i);
    if (sck_o || running_o) begin
      $fatal(1, "50 MHz clock did not stop low");
    end
    $display("SDIO 100 MHz to 50 MHz SDCLK test passed");
    $finish;
  end
endmodule
