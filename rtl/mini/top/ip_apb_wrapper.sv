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
`include "pwm_define.svh"
`include "ps2_define.svh"
`include "user_extensions.svh"
`include "soc_irq_config.svh"
`include "archinfo_integration_metadata.svh"

module ip_apb_wrapper (
    // verilog_format: off -- preserve reviewed column alignment
    input  logic                          clk_i,
    input  logic                          rst_n_i,
    input  logic                          clk_aud_i,
    input  logic                          rst_aud_n_i,
    input  logic                          debug_halted_i,
    axi4_if.slave                         axi4,
    pwm_if.dut                            pwm,
    ps2_if.dut                            ps2,
    input  logic [`USER_IPSEL_WIDTH-1:0]  ip_sel_i,
    user_gpio_if.user_ip                  user_gpio,
    output logic                          rtc_wake_o,
    output logic                          wdg_reset_req_o,
    output logic [`SOC_IRQ_APB_WIDTH-1:0] irq_o
    // verilog_format: on
);

  localparam logic [7:0] ARCHINFO_MGMT_HART_COUNT = 8'd1;
  localparam logic [7:0] ARCHINFO_USER_CORE_COUNT = `USER_CORE_COUNT;
  localparam logic [7:0] ARCHINFO_GPIO_COUNT = 8'd32;
  localparam logic [7:0] ARCHINFO_IRQ_COUNT = `SOC_IRQ_VECTOR_WIDTH;
  localparam logic [31:0] ARCHINFO_TOPOLOGY = {
    ARCHINFO_IRQ_COUNT, ARCHINFO_GPIO_COUNT, ARCHINFO_USER_CORE_COUNT, ARCHINFO_MGMT_HART_COUNT
  };

`ifdef HAVE_PLL
  localparam logic ARCHINFO_HAVE_PLL = 1'b1;
`else
  localparam logic ARCHINFO_HAVE_PLL = 1'b0;
`endif
`ifdef HAVE_SRAM_IF
  localparam logic ARCHINFO_HAVE_SRAM_IF = 1'b1;
  localparam logic [31:0] ARCHINFO_SRAM_BYTES = 32'd131_072;
`else
  localparam logic ARCHINFO_HAVE_SRAM_IF = 1'b0;
  localparam logic [31:0] ARCHINFO_SRAM_BYTES = 32'd0;
`endif
`ifdef HAVE_SRAM_MACRO
  localparam logic ARCHINFO_HAVE_SRAM_MACRO = 1'b1;
`else
  localparam logic ARCHINFO_HAVE_SRAM_MACRO = 1'b0;
`endif

  localparam logic [31:0] ARCHINFO_FEATURES0 =
      32'h0000_FFF8 | {31'd0, ARCHINFO_HAVE_PLL} |
      ({31'd0, ARCHINFO_HAVE_SRAM_IF} << 1) | ({31'd0, ARCHINFO_HAVE_SRAM_MACRO} << 2);

  logic        s_rng_entropy_en;
  logic        s_rng_entropy_ready;
  logic        s_rng_entropy_valid;
  logic [31:0] s_rng_entropy_data;
  logic        s_rng_entropy_qualified;
  logic        s_rng_entropy_fault;
  logic        s_rng_irq;

`ifdef PDK_IHP130
  localparam logic [31:0] ARCHINFO_TECHNOLOGY = 32'h0201_0082;
`elsif PDK_GF180
  localparam logic [31:0] ARCHINFO_TECHNOLOGY = 32'h0202_00B4;
`elsif PDK_SKY130
  localparam logic [31:0] ARCHINFO_TECHNOLOGY = 32'h0203_0082;
`elsif PDK_ICS55
  localparam logic [31:0] ARCHINFO_TECHNOLOGY = 32'h0204_0037;
`else
  localparam logic [31:0] ARCHINFO_TECHNOLOGY = 32'h0000_0000;
`endif

  // Generated timed and pure scalar APB interfaces preserve FPGA compatibility.
  `include "soc_apb_interfaces.svh"

  // Low-frequency peripherals retain their dedicated interfaces.
  rtc_if u_rtc_if (
      .rtc_clk_i  (clk_aud_i),
      .rtc_rst_n_i(rst_aud_n_i)
  );
  wdg_if u_wdg_if (
      .wdg_clk_i     (clk_aud_i),
      .wdg_rst_n_i   (rst_aud_n_i),
      .debug_halted_i(debug_halted_i)
  );
  `include "soc_apb_bridges.svh"

  // verilog_format: off -- preserve reviewed column alignment
  apb4_archinfo #(
      .VENDOR_ID         (32'h0000_0000),
      .SOC_REVISION      (32'h0001_0000),
      .BUILD_ID          (`ARCHINFO_INTEGRATION_BUILD_ID),
      .CONFIG_ID         (`ARCHINFO_INTEGRATION_CONFIG_ID),
      .BUILD_STATUS      (`ARCHINFO_INTEGRATION_BUILD_STATUS),
      .REFERENCE_CLOCK_HZ(`SOC_EXT_CLK_HZ),
      .SRAM_BYTES        (ARCHINFO_SRAM_BYTES),
      .TOPOLOGY          (ARCHINFO_TOPOLOGY),
      .FEATURES0         (ARCHINFO_FEATURES0),
      .TECHNOLOGY        (ARCHINFO_TECHNOLOGY)
  ) u_apb4_archinfo (
      .device_id_i            (128'h0000_0000_0000_0000_0000_0000_0000_0000),
      .device_id_valid_i      (1'b0),
      .device_id_read_enable_i(1'b0),
      .apb4                   (u_archinfo_apb_if)
  );
  // verilog_format: on

  rng_deterministic_source u_rng_deterministic_source (
      .clk_i      (clk_i),
      .rst_n_i    (rst_n_i),
      .enable_i   (s_rng_entropy_en),
      .ready_i    (s_rng_entropy_ready),
      .valid_o    (s_rng_entropy_valid),
      .data_o     (s_rng_entropy_data),
      .qualified_o(s_rng_entropy_qualified),
      .fault_o    (s_rng_entropy_fault)
  );

  apb4_rng #(
      .FIFO_DEPTH(8)
  ) u_apb4_rng (
      .entropy_enable_o   (s_rng_entropy_en),
      .entropy_ready_o    (s_rng_entropy_ready),
      .entropy_valid_i    (s_rng_entropy_valid),
      .entropy_data_i     (s_rng_entropy_data),
      .entropy_qualified_i(s_rng_entropy_qualified),
      .entropy_fault_i    (s_rng_entropy_fault),
      .irq_o              (s_rng_irq),
      .apb4               (u_rng_apb_if)
  );

  apb4_pwm #(
      .PCLK_HZ(`SOC_EXT_CLK_HZ)
  ) u_apb4_pwm (
      .debug_halted_i(debug_halted_i),
      .apb4          (u_pwm_apb_if),
      .pwm           (pwm)
  );

  apb4_ps2 #(
      .PCLK_HZ      (`SOC_EXT_CLK_HZ),
      .RX_FIFO_DEPTH(16),
      .TX_FIFO_DEPTH(16)
  ) u_apb4_ps2 (
      .apb4(u_ps2_apb_if),
      .ps2 (ps2)
  );

  apb4_rtc #(
      .RTC_CLOCK_HZ(`SOC_AUD_CLK_HZ)
  ) u_apb4_rtc (
      .apb4(u_rtc_apb_if),
      .rtc (u_rtc_if)
  );

  assign rtc_wake_o = u_rtc_if.wake_o;

  apb4_wdg #(
      .WDG_CLOCK_HZ      (`SOC_AUD_CLK_HZ),
      .RESET_PULSE_CYCLES(8)
  ) u_apb4_wdg (
      .apb4(u_wdg_apb_if),
      .wdg (u_wdg_if)
  );

  assign wdg_reset_req_o = u_wdg_if.reset_req_o;

  apb4_crc u_apb4_crc (.apb4(u_crc_apb_if));

  // Generated IRQ ownership and core-vector bit assignments are topology checked.
  `include "soc_apb_irq_bindings.svh"

axi42apb u_axi42apb (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .axi4   (axi4),
      `include "soc_apb_connections.svh"
  );

  user_ip_wrapper u_user_ip_wrapper (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .sel_i  (ip_sel_i),
      .gpio   (user_gpio),
      .apb    (u_user_ip_apb_if)
  );

endmodule
