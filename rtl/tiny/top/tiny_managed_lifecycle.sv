// Copyright (c) 2026 Yuchi Miao
// SPDX-License-Identifier: MulanPSL-2.0

// Product lifecycle observations for managed register-only endpoints. Track
// only successful APB writes, respecting byte enables. This conservative
// mirror never infers idle from quiet output pins or a missing clock. PWM
// requires explicit global/capture disable; CRC requires FINISH or ABORT.
module tiny_managed_lifecycle (
    input  logic        clk_i,
    input  logic        pwm_rst_n_i,
    input  logic        crc_rst_n_i,
    input  logic        pwm_write_i,
    input  logic [11:0] pwm_addr_i,
    input  logic [31:0] pwm_data_i,
    input  logic        crc_write_i,
    input  logic [11:0] crc_addr_i,
    input  logic [31:0] crc_data_i,
    output logic        pwm_idle_o,
    output logic        crc_idle_o
);
  logic [1:0] s_pwm_d, s_pwm_q;
  logic s_crc_d, s_crc_q;
  always_comb begin
    s_pwm_d = s_pwm_q;
    if (pwm_write_i) begin
      if (pwm_addr_i == 12'h000) s_pwm_d[0] = pwm_data_i[0];
      if (pwm_addr_i == 12'h400) s_pwm_d[1] = pwm_data_i[0];
    end
    s_crc_d = s_crc_q;
    if (crc_write_i && crc_addr_i == 12'h000) begin
      if (crc_data_i[2:0] == 3'b001) s_crc_d = 1'b1;
      if (crc_data_i[2:0] == 3'b010 || crc_data_i[2:0] == 3'b100) s_crc_d = 1'b0;
    end
  end
  dffr #(
      .DATA_WIDTH(2)
  ) u_pwm_state (
      .clk_i  (clk_i),
      .rst_n_i(pwm_rst_n_i),
      .dat_i  (s_pwm_d),
      .dat_o  (s_pwm_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_crc_state (
      .clk_i  (clk_i),
      .rst_n_i(crc_rst_n_i),
      .dat_i  (s_crc_d),
      .dat_o  (s_crc_q)
  );
  assign pwm_idle_o = s_pwm_q == 0;
  assign crc_idle_o = !s_crc_q;
endmodule
