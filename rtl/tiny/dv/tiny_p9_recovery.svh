// Copyright (c) 2026 Yuchi Miao; SPDX-License-Identifier: MulanPSL-2.0
// Verification board control. Observe firmware UART writes; only change the
// external board population and camera model, never a DUT signal or register.
string  s_p9_recovery_line = "";
integer s_p9_recovery_controls = 0;
bit     s_p9_recovery_reported = 0;
always @(posedge s_clk) begin
  if ($test$plusargs("tiny_p9_recovery") && u_dut.s_test_done && !s_p9_recovery_reported) begin
    s_p9_recovery_reported = 1;
    $display("P9_RECOVERY_BOARD controls=%0d audio_cases=%0d", s_p9_recovery_controls,
             s_p6_wire_cases);
  end
end
always @(posedge u_dut.u_soc.s_uart0_clk) begin
  if ($test$plusargs(
          "tiny_p9_recovery"
      ) && u_dut.u_soc.s_uart0_rst_n && u_dut.u_soc.u_uart0.u_uart_reg.s_tx_push &&
          !u_dut.u_soc.u_uart0.s_loopback) begin
    if (u_dut.u_soc.u_uart0_apb4_if.pwdata[7:0] == 8'd10) begin
      if (s_p9_recovery_line == "P9_CTRL camera") begin
        s_p9_camera_population = 1;
        s_p9_recovery_controls++;
      end else if (s_p9_recovery_line == "P9_CTRL audio") begin
        s_p9_camera_population = 0;
        s_p9_recovery_controls++;
      end else if (s_p9_recovery_line == "P9_CTRL stop_low") begin
        u_dvp_camera.recovery_pause = 1;
        s_p9_recovery_controls++;
      end else if (s_p9_recovery_line == "P9_CTRL stop_high") begin
        u_dvp_camera.recovery_pause = 2;
        s_p9_recovery_controls++;
      end else if (s_p9_recovery_line == "P9_CTRL resume") begin
        u_dvp_camera.recovery_pause = 0;
        s_p9_recovery_controls++;
      end
      s_p9_recovery_line = "";
    end else if (u_dut.u_soc.u_uart0_apb4_if.pwdata[7:0] != 8'd13) begin
      if (s_p9_recovery_line.len() >= 256) $fatal(1, "SIM_TEST_FAIL recovery UART record overflow");
      s_p9_recovery_line = {
        s_p9_recovery_line, $sformatf("%c", u_dut.u_soc.u_uart0_apb4_if.pwdata[7:0])
      };
    end
  end
end
