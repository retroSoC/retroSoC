// Copyright (c) 2026 Yuchi Miao; SPDX-License-Identifier: MulanPSL-2.0
`timescale 1ns / 1ps
module tiny_p9_audio_observer_tb;
  logic [31:0] s_gpio = 0;
  logic        audio_enable = 0;
  logic        audio_wide = 0;
  `include "audio_observer.svh"
  task automatic sample (input logic [15:0] word);
    for (int bit_index = 15; bit_index >= 0; bit_index--) begin
      s_gpio[12] = 0;
      s_gpio[14] = word[bit_index];
      if (bit_index == 0) s_gpio[13] = !s_gpio[13];
      #5;
      s_gpio[12] = 1;
      #5;
    end
  endtask
  initial begin
    #20;
    for (int session = 0; session < 2; session++) begin
      audio_enable = 1;
      for (int index = 0; index < ($test$plusargs("tiny_p9_recovery") ? 8 : 512); index++) begin
        if ($test$plusargs("corrupt") && index == 3) sample (16'hdead);
        else sample ($test$plusargs("tiny_p9_recovery") ? 16'h1234 : 16'(16'h2020 + index));
      end
      s_gpio[12]   = 0;
      audio_enable = 0;
      #10;
      s_gpio[13] = 0;
    end
    if (s_p6_wire_cases != 2) $fatal(1, "SIM_TEST_FAIL missing audio wire sessions");
    $display("SIM_TEST_PASS audio observer sessions=2");
    $finish;
  end
endmodule
