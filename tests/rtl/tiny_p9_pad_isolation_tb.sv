// Copyright (c) 2026 Yuchi Miao
// SPDX-License-Identifier: MulanPSL-2.0
`timescale 1ns / 1ps
`include "dvp_define.svh"
`include "pad_dvp_interface.svh"

module tiny_p9_pad_isolation_tb;
  logic s_ref_clk = 0;
  always #20.833 s_ref_clk = !s_ref_clk;
  // Supply only the two inputs used by the actual P6 startup check.
  tiny_p9_pad_boot_fixture u_dut (.clk_i(s_ref_clk));
  `include "tiny_tb_gpio.svh"
  `include "pad_audio_startup.svh"
  `include "pad_audio_drivers.svh"

  wire s_dvp_pclk, s_dvp_href, s_dvp_vsync;
  wire  [7:0] s_camera_data;
  logic [7:0] s_sweep_data = 0;
  logic       s_codec_data = 0;
  wire  [7:0] s_dvp_data = $test$plusargs("sweep") ? s_sweep_data : s_camera_data;
  tiny_dvp_camera u_camera (
      .pclk_o (s_dvp_pclk),
      .href_o (s_dvp_href),
      .vsync_o(s_dvp_vsync),
      .dat_o  (s_camera_data)
  );
  `include "pad_camera_drivers.svh"
  assign s_gpio_14 = !$test$plusargs("tiny_p9_camera") ? s_codec_data : 1'bz;
  // Negative control reproduces the old, simultaneously populated codec.
  assign s_gpio_17 = ($test$plusargs(
      "legacy_conflict"
  ) || $test$plusargs(
      "legacy_clock"
  )) ? s_p6_audio_reference : 1'bz;
  assign s_gpio_15 = $test$plusargs("legacy_conflict") ? s_gpio_14 : 1'bz;

  wire [7:0] s_pad_data;
  wire s_pad_clk, s_pad_href, s_pad_vsync;
  tiny_p9_pad_fixture u_pads (
      .data_o (s_pad_data),
      .clk_o  (s_pad_clk),
      .href_o (s_pad_href),
      .vsync_o(s_pad_vsync),
      `include "pad_tb_bindings.svh"
  );
  logic         s_reset_n = 0;
  logic [127:0] s_config = 0;
  logic         s_config_valid = 0;
  wire s_push_valid, s_stats_valid;
  wire    [                            41:0] s_push_data;
  wire    [                             5:0] s_errors;
  wire    [`APB4_DVP__FRAME_STATS_WIDTH-1:0] s_stats;
  integer                                    s_words = 0;
  dvp_core u_core (
      .clk_i               (s_pad_clk),
      .rst_n_i             (s_reset_n),
      .cfg_i               (s_config),
      .cfg_valid_i         (s_config_valid),
      .cfg_cancel_i        (1'b0),
      .cmd_i               (2'b00),
      .error_clear_i       (6'd0),
      .cfg_ready_o         (),
      .push_ready_i        (1'b1),
      .push_valid_o        (s_push_valid),
      .push_data_o         (s_push_data),
      .active_o            (),
      .capture_idle_o      (),
      .frame_start_toggle_o(),
      .line_done_toggle_o  (),
      .frame_done_toggle_o (),
      .error_toggle_o      (),
      .error_flags_o       (s_errors),
      .error_events_o      (),
      .frame_stats_o       (s_stats),
      .frame_stats_valid_o (s_stats_valid),
      .frame_stats_ready_i (1'b1),
      .href_i              (s_pad_href),
      .vsync_i             (s_pad_vsync),
      .dat_i               (s_pad_data)
  );

  function automatic logic [31:0] expected_word(input integer index);
    logic [7:0] first;
    first = 8'((index % 8) * 4 + (index / 8) * 3);
    return {8'(first + 2), 8'(first + 3), first, 8'(first + 1)};
  endfunction

  always @(posedge s_pad_clk) begin
    if (s_reset_n && $test$plusargs("capture") && s_push_valid) begin
      if (s_words >= 64 || s_push_data[31:0] !== expected_word(s_words))
        $fatal(
            1,
            "SIM_TEST_FAIL P9 DVP word=%0d got=%h expected=%h",
            s_words,
            s_push_data[31:0],
            expected_word(
                s_words
            )
        );
      if (s_words == 0) $display("P9_PAD_FIRST_WORD value=%h", s_push_data[31:0]);
      s_words++;
    end
  end

  initial begin
    #1000000;
    $fatal(1, "SIM_TEST_TIMEOUT P9 pad fixture");
  end
  initial begin
    if ($test$plusargs("capture")) begin
      s_config[15:0]  = 16;
      s_config[31:16] = 8;
      s_config[79:64] = 16;
      s_config[95:80] = 8;
      s_config[97:96] = 2'b11;
      #2000;
      @(negedge s_pad_clk);
      s_reset_n      = 1;
      s_config_valid = 1;
      repeat (2) @(negedge s_pad_clk);
      s_config_valid = 0;
      wait (s_stats_valid);
      @(negedge s_pad_clk);
      if (s_errors !== 0 || s_words != 64 || s_stats[31:0] != 1)
        $fatal(1, "SIM_TEST_FAIL P9 pad frame accounting");
      $display("SIM_TEST_PASS Tiny P9 pad capture words=%0d", s_words);
      $finish;
    end else if ($test$plusargs("tiny_p9_camera")) begin
      wait (s_p6_audio_running);
      // Hold each external audio level while sweeping all camera bytes.
      s_p6_audio_running = 0;
      for (int audio = 0; audio < 2; audio++) begin
        s_p6_audio_reference = 1'(audio);
        for (int value = 0; value < 256; value++) begin
          s_sweep_data = 8'(value);
          #100;
          if (s_pad_data !== s_sweep_data)
            $fatal(
                1,
                "SIM_TEST_FAIL P9 pad mismatch expected=%h got=%h audio=%0d",
                s_sweep_data,
                s_pad_data,
                audio
            );
        end
      end
      $display("SIM_TEST_PASS Tiny P9 pad sweep bytes=512");
      $finish;
    end else begin
      // No camera: retain the actual delayed audio-clock startup and loopback.
      #100;
      if (s_p6_audio_running !== 0 || s_gpio_17 !== 0)
        $fatal(1, "SIM_TEST_FAIL P6 premature audio reference");
      wait (s_p6_audio_running);
      repeat (8) begin
        @(posedge s_p6_audio_reference);
        s_codec_data = 1;
        #5;
        if (s_gpio_17 !== 1 || s_gpio_15 !== 1 || s_pad_data[3] !== 1)
          $fatal(1, "SIM_TEST_FAIL P6 audio high/loopback");
        @(negedge s_p6_audio_reference);
        s_codec_data = 0;
        #5;
        if (s_gpio_17 !== 0 || s_gpio_15 !== 0 || s_pad_data[3] !== 0)
          $fatal(1, "SIM_TEST_FAIL P6 audio low/loopback");
      end
      $display("SIM_TEST_PASS Tiny P6 audio pad compatibility");
      $finish;
    end
  end
endmodule

module tiny_p9_pad_fixture (
    output wire [7:0] data_o,
    output wire       clk_o,
    href_o,
    vsync_o,
    `include "pad_ports.svh"
);
  gpio_if u_gpio_if ();
  dvp_if u_dvp_if ();
  assign u_gpio_if.oe_o = 0;
  assign u_gpio_if.do_o = 0;
  assign u_gpio_if.pu_o = 0;
  assign u_gpio_if.pd_o = 0;
  assign u_gpio_if.cs_o = '1;
  `define RETROSOC_PAD_POWER_CONNECTIONS
  `include "pad_instances.svh"
  `undef RETROSOC_PAD_POWER_CONNECTIONS
  `include "pad_dvp_routes.svh"
  assign data_o  = u_dvp_if.dat_i;
  assign clk_o   = u_dvp_if.pclk_i;
  assign href_o  = u_dvp_if.href_i;
  assign vsync_o = u_dvp_if.vsync_i;
endmodule

module tiny_p9_pad_boot_fixture (
    input logic clk_i
);
  tiny_p9_pad_boot_soc_fixture u_soc (.clk_i(clk_i));
endmodule
module tiny_p9_pad_boot_soc_fixture (
    input logic clk_i
);
  wire s_ref_clk = clk_i;
  wire s_cpu_ready_rst_n = 1'b1;
endmodule
