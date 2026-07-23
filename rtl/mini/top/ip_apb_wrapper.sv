// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

`include "mmap_define.svh"
`include "uart_define.svh"
`include "pwm_define.svh"
`include "ps2_define.svh"
`include "mdd_config.svh"

module ip_apb_wrapper (
    // verilog_format: off
    input  logic                        clk_i,
    input  logic                        rst_n_i,
    input  logic                        clk_aud_i,
    input  logic                        rst_aud_n_i,
    input  logic                        tmr_capch_i,
    nmi_if.slave                        nmi,
    uart_if.dut                         uart,
    pwm_if.dut                          pwm,
    ps2_if.dut                          ps2,
`ifdef IP_MDD
    input logic [`USER_IPSEL_WIDTH-1:0] ip_sel_i,
    user_gpio_if.user_ip                user_gpio,
`endif
    output logic [ 6:0]                 irq_o
    // verilog_format: on
);

  // Generated timed and pure scalar APB interfaces preserve FPGA compatibility.
  `include "soc_apb_interfaces.svh"

  // Low-frequency peripherals retain their dedicated interfaces.
  rtc_if u_rtc_if (
      clk_aud_i,
      rst_aud_n_i
  );
  wdg_if u_wdg_if (clk_aud_i);
  tmr_if u_tmr_if (clk_aud_i);

  assign u_tmr_if.capch_i = tmr_capch_i;

  `include "soc_apb_bridges.svh"

  // verilog_format: off
  apb4_archinfo                u_apb4_archinfo (u_archinfo_apb_if);
  apb4_rng                     u_apb4_rng      (u_rng_apb_if);
  apb4_uart #(.FIFO_DEPTH(32)) u_apb4_uart     (u_uart1_apb_if, uart);
  apb4_pwm                     u_apb4_pwm      (u_pwm_apb_if, pwm);
  apb4_ps2                     u_apb4_ps2      (u_ps2_apb_if, ps2);
  apb4_rtc                     u_apb4_rtc      (u_rtc_apb_if, u_rtc_if);
  apb4_wdg                     u_apb4_wdg      (u_wdg_apb_if, u_wdg_if);
  apb4_crc                     u_apb4_crc      (u_crc_apb_if);
  apb4_tmr                     u_apb4_tmr      (u_tmr_apb_if, u_tmr_if);
  // verilog_format: on

  // handle irq signals
  assign irq_o[0] = uart.irq_o;
  assign irq_o[1] = pwm.irq_o;
  assign irq_o[2] = ps2.irq_o;
  assign irq_o[3] = u_rtc_if.irq_o;
  assign irq_o[4] = u_wdg_if.rst_o;
  assign irq_o[5] = u_tmr_if.irq_o;
  assign irq_o[6] = 1'b0;

  nmi2apb u_nmi2apb (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .nmi    (nmi),
      `include "soc_apb_connections.svh"
  );

`ifdef IP_MDD
  user_ip_wrapper u_user_ip_wrapper (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .sel_i  (ip_sel_i),
      .gpio   (user_gpio),
      .apb    (u_user_ip_apb_if)
  );
`endif

endmodule
