// Copyright (c) 2026 Yuchi Miao
// SPDX-License-Identifier: MulanPSL-2.0
`include "mmap_define.svh"

module retrosoc_tiny (
    input  logic                 clk_i,
    input  logic                 rst_n_i,
    input  logic                 jtag_tck_i,
    input  logic                 jtag_tms_i,
    input  logic                 jtag_tdi_i,
    input  logic                 jtag_trst_n_i,
    output logic                 jtag_tdo_o,
    input  logic                 uart0_rx_i,
    output logic                 uart0_tx_o,
    input  logic                 uart1_rx_i,
    output logic                 uart1_tx_o,
           gpio_if.soc_pad       gpio,
           xpi_if.dut            xpi,
    output logic                 test_done_o,
    output logic                 test_pass_o,
    output logic           [7:0] test_code_o
);
  logic s_por_rst_n, s_rst_n;
  logic        s_debug_halted;
  logic [31:0] s_irq;
  logic s_fault_valid, s_fault_master, s_fault_write;
  logic [31:0] s_fault_addr;
  logic [ 1:0] s_fault_resp;
  logic s_perf_enable, s_perf_clear;
  logic [63:0] s_cpu_wait, s_dma_wait;
  logic s_timer0_irq, s_timer1_irq, s_xpi_irq, s_dma_irq;
  logic       s_dma_done;
  logic [7:0] s_dma_stall;
  logic [4:0] s_tick_count_d, s_tick_count_q;
  logic s_tick;
  logic s_unused_uart1_tx_stall, s_unused_uart1_rx_stall;
  uart_if u_uart0_if ();
  uart_if u_uart1_if ();
  i2c_if u_i2c0_if ();
  i2c_if u_i2c1_if ();
  pwm_if u_pwm_if ();
  clint_if u_clint_if ();
  gpio_if u_gpio_if ();
  user_gpio_if u_user_gpio_if ();
  dma_req_if u_dma_req_if ();
  rtc_if u_rtc_if (
      .rtc_clk_i  (clk_i),
      .rtc_rst_n_i(s_rst_n)
  );
  // The watchdog reset pulse must survive resetting the bus/CPU. Its timer
  // uses POR reset while its APB register domain uses the system reset.
  wdg_if u_wdg_if (
      .wdg_clk_i  (clk_i),
      .wdg_rst_n_i(s_por_rst_n)
  );
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .USER_WIDTH(1)
  ) u_masters_axi4_if[2] (
      .aclk   (clk_i),
      .aresetn(s_rst_n)
  );
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .USER_WIDTH(1)
  ) u_targets_axi4_if[5] (
      .aclk   (clk_i),
      .aresetn(s_rst_n)
  );
  axi4_stream_if #(
      .DATA_WIDTH(32)
  ) u_i2s_tx_axis_if (
      .aclk   (clk_i),
      .aresetn(s_rst_n)
  );
  axi4_stream_if #(
      .DATA_WIDTH(32)
  ) u_i2s_rx_axis_if (
      .aclk   (clk_i),
      .aresetn(s_rst_n)
  );
  axi4_stream_if #(
      .DATA_WIDTH(32)
  ) u_dvp_rx_axis_if (
      .aclk   (clk_i),
      .aresetn(s_rst_n)
  );
  axi4_stream_if #(
      .DATA_WIDTH(32)
  ) u_crypto_tx_axis_if (
      .aclk   (clk_i),
      .aresetn(s_rst_n)
  );
  axi4_stream_if #(
      .DATA_WIDTH(32)
  ) u_crypto_rx_axis_if (
      .aclk   (clk_i),
      .aresetn(s_rst_n)
  );
  `include "tiny_apb_interfaces.svh"

rst_sync u_por_rst_sync (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .rst_n_o(s_por_rst_n)
  );
  rst_sync u_system_rst_sync (
      .clk_i  (clk_i),
      .rst_n_i(s_por_rst_n && !u_wdg_if.reset_req_o),
      .rst_n_o(s_rst_n)
  );
  assign s_tick         = s_tick_count_q == 5'd23;
  assign s_tick_count_d = s_tick ? 5'd0 : (s_tick_count_q + 5'd1);
  dffr #(
      .DATA_WIDTH(5)
  ) u_tick_reg (
      .clk_i  (clk_i),
      .rst_n_i(s_rst_n),
      .dat_i  (s_tick_count_d),
      .dat_o  (s_tick_count_q)
  );
  mgmt_core_wrapper #(
      .ExternalIrqCount (30),
      .EnableAtomics    (1'b0),
      .TwoCycleBusErrors(1'b1)
  ) u_cpu (
      .clk_i         (clk_i),
      .rst_n_i       (s_rst_n),
      .irq_i         (s_irq),
      .jtag_tck_i    (jtag_tck_i),
      .jtag_tms_i    (jtag_tms_i),
      .jtag_tdi_i    (jtag_tdi_i),
      .jtag_trst_n_i (jtag_trst_n_i),
      .jtag_tdo_o    (jtag_tdo_o),
      .debug_halted_o(s_debug_halted),
      .axi4          (u_masters_axi4_if[0])
  );
  tiny_axi4_fabric u_fabric (
      .clk_i         (clk_i),
      .rst_n_i       (s_rst_n),
      .masters       (u_masters_axi4_if),
      .targets       (u_targets_axi4_if),
      .perf_enable_i (s_perf_enable),
      .perf_clear_i  (s_perf_clear),
      .fault_valid_o (s_fault_valid),
      .fault_addr_o  (s_fault_addr),
      .fault_master_o(s_fault_master),
      .fault_write_o (s_fault_write),
      .fault_resp_o  (s_fault_resp),
      .cpu_wait_o    (s_cpu_wait),
      .dma_wait_o    (s_dma_wait)
  );
  onchip_ram #(
      .CapacityKiB(128),
      .DataWidth  (32),
      .IdWidth    (1)
  ) u_sram (
      .clk_i        (clk_i),
      .rst_n_i      (s_rst_n),
      .mem_axi4     (u_targets_axi4_if[0]),
      .cfg_apb4     (u_sram_apb4_if),
      .perf_enable_i(s_perf_enable),
      .perf_clear_i (s_perf_clear)
  );
  apb4_xpi u_xpi (
      .clk_i          (clk_i),
      .rst_n_i        (s_rst_n),
      .mem_axi4       (u_targets_axi4_if[1]),
      .apb4           (u_xpi_apb4_if),
      .xpi            (xpi),
      .dma_xfer_done_i(s_dma_done),
      .dma_tx_stall_o (s_dma_stall[0]),
      .dma_rx_stall_o (s_dma_stall[1]),
      .irq_o          (s_xpi_irq)
  );
  tiny_axi42apb4 u_apb_bridge (
      .clk_i  (clk_i),
      .rst_n_i(s_rst_n),
      .axi4   (u_targets_axi4_if[2]),
      `include "tiny_apb_connections.svh"
  );
  axi4_error_slave #(
      .Response(2'b11)
  ) u_decode_error (
      .clk_i  (clk_i),
      .rst_n_i(s_rst_n),
      .axi4   (u_targets_axi4_if[3])
  );
  axi4_error_slave #(
      .Response(2'b10)
  ) u_protocol_error (
      .clk_i  (clk_i),
      .rst_n_i(s_rst_n),
      .axi4   (u_targets_axi4_if[4])
  );
  tiny_sysctrl u_sysctrl (
      .clk_i         (clk_i),
      .rst_n_i       (s_rst_n),
      .apb4          (u_sysctrl_apb4_if),
      .fault_valid_i (s_fault_valid),
      .fault_addr_i  (s_fault_addr),
      .fault_write_i (s_fault_write),
      .fault_master_i(s_fault_master),
      .fault_resp_i  (s_fault_resp),
      .cpu_wait_i    (s_cpu_wait),
      .dma_wait_i    (s_dma_wait),
      .rtc_wake_i    (u_rtc_if.wake_o),
      .perf_enable_o (s_perf_enable),
      .perf_clear_o  (s_perf_clear),
      .test_done_o   (test_done_o),
      .test_pass_o   (test_pass_o),
      .test_code_o   (test_code_o)
  );
  tiny_archinfo u_archinfo (
      .clk_i  (clk_i),
      .rst_n_i(s_rst_n),
      .apb4   (u_archinfo_apb4_if)
  );
  apb4_gpio u_gpio (
      .clk_i    (clk_i),
      .rst_n_i  (s_rst_n),
      .apb4     (u_gpio_apb4_if),
      .gpio     (u_gpio_if),
      .user_gpio(u_user_gpio_if)
  );
  gpio_pad_bridge u_gpio_pads (
      .inner(u_gpio_if),
      .outer(gpio)
  );
  assign u_user_gpio_if.do_o     = '0;
  assign u_user_gpio_if.oe_o     = '0;
  assign u_uart0_if.rx_i         = uart0_rx_i;
  assign uart0_tx_o              = u_uart0_if.tx_o;
  assign u_uart1_if.rx_i         = uart1_rx_i;
  assign u_uart1_if.cts_n_i      = 1'b0;
  assign uart1_tx_o              = u_uart1_if.tx_o;
  assign u_wdg_if.debug_halted_i = s_debug_halted;
  `include "tiny_gpio.svh"
  `include "tiny_irq.svh"
apb4_uart u_uart0 (
      .clk_i         (clk_i),
      .rst_n_i       (s_rst_n),
      .apb4          (u_uart0_apb4_if),
      .uart          (u_uart0_if),
      .dma_tx_stall_o(s_dma_stall[2]),
      .dma_rx_stall_o(s_dma_stall[3])
  );
  apb4_i2c u_i2c0 (
      .clk_i         (clk_i),
      .rst_n_i       (s_rst_n),
      .apb4          (u_i2c0_apb4_if),
      .i2c           (u_i2c0_if),
      .dma_tx_stall_o(s_dma_stall[4]),
      .dma_rx_stall_o(s_dma_stall[5])
  );
  apb4_timer u_timer0 (
      .clk_i         (clk_i),
      .rst_n_i       (s_rst_n),
      .debug_halted_i(s_debug_halted),
      .apb4          (u_timer0_apb4_if),
      .irq_o         (s_timer0_irq)
  );
  apb4_uart u_uart1 (
      .clk_i         (clk_i),
      .rst_n_i       (s_rst_n),
      .apb4          (u_uart1_apb4_if),
      .uart          (u_uart1_if),
      .dma_tx_stall_o(s_unused_uart1_tx_stall),
      .dma_rx_stall_o(s_unused_uart1_rx_stall)
  );
  apb4_i2c u_i2c1 (
      .clk_i         (clk_i),
      .rst_n_i       (s_rst_n),
      .apb4          (u_i2c1_apb4_if),
      .i2c           (u_i2c1_if),
      .dma_tx_stall_o(s_dma_stall[6]),
      .dma_rx_stall_o(s_dma_stall[7])
  );
  apb4_timer u_timer1 (
      .clk_i         (clk_i),
      .rst_n_i       (s_rst_n),
      .debug_halted_i(s_debug_halted),
      .apb4          (u_timer1_apb4_if),
      .irq_o         (s_timer1_irq)
  );
  apb4_clint u_clint (
      .clk_i          (clk_i),
      .rst_n_i        (s_rst_n),
      .timebase_tick_i(s_tick),
      .apb4           (u_clint_apb4_if),
      .clint          (u_clint_if)
  );
  apb4_pwm #(
      .PCLK_HZ(24_000_000)
  ) u_pwm (
      .debug_halted_i(s_debug_halted),
      .apb4          (u_pwm_apb4_if),
      .pwm           (u_pwm_if)
  );
  apb4_rtc #(
      .RTC_CLOCK_HZ(24_000_000)
  ) u_rtc (
      .apb4(u_rtc_apb4_if),
      .rtc (u_rtc_if)
  );
  apb4_wdg #(
      .WDG_CLOCK_HZ      (24_000_000),
      .RESET_PULSE_CYCLES(8)
  ) u_watchdog (
      .apb4(u_wdg_apb4_if),
      .wdg (u_wdg_if)
  );
  apb4_dma #(
      .NumChannels  (4),
      .MaxBurstBeats(16),
      .FifoDepth    (32),
      .RequestMask  (16'h07f9),
      .EnableStreams(1'b0)
  ) u_dma (
      .clk_i          (clk_i),
      .rst_n_i        (s_rst_n),
      .dma_xfer_done_o(s_dma_done),
      .irq_o          (s_dma_irq),
      .hw_trg         (u_dma_req_if),
      .apb4           (u_dma_apb4_if),
      .axi4           (u_masters_axi4_if[1]),
      .i2s_tx_axis    (u_i2s_tx_axis_if),
      .i2s_rx_axis    (u_i2s_rx_axis_if),
      .dvp_rx_axis    (u_dvp_rx_axis_if),
      .crypto_in_axis (u_crypto_tx_axis_if),
      .crypto_out_axis(u_crypto_rx_axis_if)
  );
  assign u_dma_req_if.i2s_tx_proc     = 1'b0;
  assign u_dma_req_if.i2s_rx_proc     = 1'b0;
  assign u_dma_req_if.crypto_in_proc  = 1'b0;
  assign u_dma_req_if.crypto_out_proc = 1'b0;
  assign u_dma_req_if.qspi_tx_proc    = !s_dma_stall[0];
  assign u_dma_req_if.qspi_rx_proc    = !s_dma_stall[1];
  assign u_dma_req_if.uart_tx_proc    = !s_dma_stall[2];
  assign u_dma_req_if.uart_rx_proc    = !s_dma_stall[3];
  assign u_dma_req_if.i2c0_tx_proc    = !s_dma_stall[4];
  assign u_dma_req_if.i2c0_rx_proc    = !s_dma_stall[5];
  assign u_dma_req_if.i2c1_tx_proc    = !s_dma_stall[6];
  assign u_dma_req_if.i2c1_rx_proc    = !s_dma_stall[7];
  assign u_i2s_rx_axis_if.tvalid      = '0;
  assign u_i2s_rx_axis_if.tdata       = '0;
  assign u_i2s_rx_axis_if.tstrb       = '0;
  assign u_i2s_rx_axis_if.tkeep       = '0;
  assign u_i2s_rx_axis_if.tlast       = '0;
  assign u_i2s_rx_axis_if.tid         = '0;
  assign u_i2s_rx_axis_if.tdest       = '0;
  assign u_i2s_rx_axis_if.tuser       = '0;
  assign u_dvp_rx_axis_if.tvalid      = '0;
  assign u_dvp_rx_axis_if.tdata       = '0;
  assign u_dvp_rx_axis_if.tstrb       = '0;
  assign u_dvp_rx_axis_if.tkeep       = '0;
  assign u_dvp_rx_axis_if.tlast       = '0;
  assign u_dvp_rx_axis_if.tid         = '0;
  assign u_dvp_rx_axis_if.tdest       = '0;
  assign u_dvp_rx_axis_if.tuser       = '0;
  assign u_crypto_rx_axis_if.tvalid   = '0;
  assign u_crypto_rx_axis_if.tdata    = '0;
  assign u_crypto_rx_axis_if.tstrb    = '0;
  assign u_crypto_rx_axis_if.tkeep    = '0;
  assign u_crypto_rx_axis_if.tlast    = '0;
  assign u_crypto_rx_axis_if.tid      = '0;
  assign u_crypto_rx_axis_if.tdest    = '0;
  assign u_crypto_rx_axis_if.tuser    = '0;
  assign u_i2s_tx_axis_if.tready      = 1'b0;
  assign u_crypto_tx_axis_if.tready   = 1'b0;
endmodule
