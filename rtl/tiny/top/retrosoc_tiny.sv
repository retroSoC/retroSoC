// Copyright (c) 2026 Yuchi Miao
// SPDX-License-Identifier: MulanPSL-2.0
`include "mmap_define.svh"
`include "tiny_topology.svh"

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
  logic [`RETROSOC_TINY__LEAF_COUNT-1:0] s_leaf_rst_n;
  logic s_fabric_rst_n, s_cpu_ready_rst_n;
  logic s_master_rst_n [                           3];
  logic s_target_rst_n [`RETROSOC_TINY__TARGET_COUNT];
  logic s_debug_halted;
  logic s_core_rst_n, s_cpu_bus_idle, s_cpu_quiesce;
  logic [31:0] s_irq;
  logic        s_fault_write;
  logic [ 1:0] s_fault_master;
  logic [ 3:0] s_fault_count;
  logic [5:0] s_external_fault_valid, s_external_fault_instruction;
  logic [5:0][31:0] s_external_fault_addr;
  logic [5:0][ 1:0] s_external_fault_resp;
  logic [1:0] s_local_fault_valid, s_local_fault_write;
  logic [ 1:0][31:0] s_local_fault_addr;
  logic [31:0]       s_fault_addr;
  logic [ 1:0]       s_fault_resp;
  logic s_perf_enable, s_perf_clear;
  logic [63:0] s_cpu_wait, s_dma_wait;
  logic s_timer0_irq, s_timer1_irq, s_xpi_irq, s_dma_irq;
  logic       s_dma_done;
  logic [5:0] s_dma_stall;
  logic [4:0] s_tick_count_d, s_tick_count_q;
  logic s_tick;
  logic s_audio_pad_clk, s_audio_clk, s_audio_rst_n;
  logic s_rng_en, s_rng_ready, s_rng_valid, s_rng_qualified, s_rng_fault, s_rng_irq;
  logic [31:0] s_rng_data;
  logic s_crypto_irq, s_crypto_input_ready, s_crypto_output_ready;
  logic s_i2s_tx_stall, s_i2s_rx_stall;
  ahbl_if u_cpu_ahbl_if[2] (
      .hclk   (clk_i),
      .hresetn(s_core_rst_n)
  );
  tiny_sram_port_if u_cpu_local_if[2] ();
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .USER_WIDTH(1)
  ) u_sram_axi4_if[4] (
      .aclk   (clk_i),
      .aresetn(s_sram_rst_n)
  );
  `include "tiny_apb_interfaces.svh"
uart_if u_uart0_if ();
  i2c_if u_i2c0_if ();
  pwm_if u_pwm_if ();
  clint_if u_clint_if ();
  gpio_if u_gpio_if ();
  user_gpio_if u_user_gpio_if ();
  dma_req_if u_dma_req_if ();
  i2s_if u_i2s_if ();
  ws2812_if u_ws2812_if ();
  sdio_if u_sdio_if ();
  rtc_if u_rtc_if (
      .rtc_clk_i  (clk_i),
      .rtc_rst_n_i(s_rtc_rst_n)
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
  ) u_masters_axi4_if[3] (
      .aclk   (clk_i),
      .aresetn(s_master_rst_n)
  );
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .USER_WIDTH(1)
  ) u_targets_axi4_if[`RETROSOC_TINY__TARGET_COUNT] (
      .aclk   (clk_i),
      .aresetn(s_target_rst_n)
  );
  axi4_stream_if #(
      .DATA_WIDTH(32)
  ) u_i2s_tx_axis_if (
      .aclk   (clk_i),
      .aresetn(s_dma_rst_n)
  );
  axi4_stream_if #(
      .DATA_WIDTH(32)
  ) u_i2s_rx_axis_if (
      .aclk   (clk_i),
      .aresetn(s_dma_rst_n)
  );
  axi4_stream_if #(
      .DATA_WIDTH(32)
  ) u_dvp_rx_axis_if (
      .aclk   (clk_i),
      .aresetn(s_dma_rst_n)
  );
  axi4_stream_if #(
      .DATA_WIDTH(32)
  ) u_crypto_tx_axis_if (
      .aclk   (clk_i),
      .aresetn(s_dma_rst_n)
  );
  axi4_stream_if #(
      .DATA_WIDTH(32)
  ) u_crypto_rx_axis_if (
      .aclk   (clk_i),
      .aresetn(s_dma_rst_n)
  );
  assign s_fabric_rst_n = s_leaf_rst_n[0];
  assign s_master_rst_n = '{s_cpu_ready_rst_n, s_dma_rst_n, s_sdio_rst_n};
  assign s_target_rst_n[4] = s_xpi_rst_n;
  assign s_target_rst_n[`RETROSOC_TINY__DECODE_ERROR] = s_fabric_rst_n;
  assign s_target_rst_n[`RETROSOC_TINY__PROTOCOL_ERROR] = s_fabric_rst_n;
  tiny_reset_tree #(
      .LeafCount(`RETROSOC_TINY__LEAF_COUNT)
  ) u_reset_tree (
      .clk_i               (clk_i),
      .rst_n_i             (rst_n_i),
      .watchdog_reset_req_i(u_wdg_if.reset_req_o),
      .por_rst_n_o         (s_por_rst_n),
      .system_rst_n_o      (s_rst_n),
      .leaf_rst_n_o        (s_leaf_rst_n),
      .cpu_ready_rst_n_o   (s_cpu_ready_rst_n)
  );
  assign s_tick         = s_tick_count_q == 5'd23;
  assign s_tick_count_d = s_tick ? 5'd0 : (s_tick_count_q + 5'd1);
  dffr #(
      .DATA_WIDTH(5)
  ) u_tick_reg (
      .clk_i  (clk_i),
      .rst_n_i(s_fabric_rst_n),
      .dat_i  (s_tick_count_d),
      .dat_o  (s_tick_count_q)
  );
  tiny_cpu_wrapper #(
      .ExternalIrqCount(30),
      .EnableAtomics   (1'b0),
      .ResetSyncStages (5)
  ) u_cpu (
      .clk_i         (clk_i),
      .rst_n_i       (s_cpu_ready_rst_n),
      .irq_i         (s_irq),
      .jtag_tck_i    (jtag_tck_i),
      .jtag_tms_i    (jtag_tms_i),
      .jtag_tdi_i    (jtag_tdi_i),
      .jtag_trst_n_i (jtag_trst_n_i),
      .jtag_tdo_o    (jtag_tdo_o),
      .debug_halted_o(s_debug_halted),
      .bus_idle_i    (s_cpu_bus_idle),
      .core_rst_n_o  (s_core_rst_n),
      .quiesce_o     (s_cpu_quiesce),
      .cpu           (u_cpu_ahbl_if)
  );
  tiny_cpu_mem u_cpu_mem (
      .clk_i              (clk_i),
      .rst_n_i            (s_core_rst_n),
      .quiesce_i          (s_cpu_quiesce),
      .idle_o             (s_cpu_bus_idle),
      .local_fault_valid_o(s_local_fault_valid),
      .local_fault_addr_o (s_local_fault_addr),
      .local_fault_write_o(s_local_fault_write),
      .cpu                (u_cpu_ahbl_if),
      .local_ports        (u_cpu_local_if),
      .slow_axi4          (u_masters_axi4_if[0])
  );
  tiny_axi4_fabric u_fabric (
      .clk_i(clk_i),
      .rst_n_i(s_fabric_rst_n),
      .target_rst_n_i(s_target_rst_n),
      .masters(u_masters_axi4_if),
      .targets(u_targets_axi4_if),
      .perf_enable_i(s_perf_enable),
      .perf_clear_i(s_perf_clear),
      .fault_valid_o(s_external_fault_valid),
      .fault_addr_o(s_external_fault_addr),
      .fault_resp_o(s_external_fault_resp),
      .fault_instruction_o(s_external_fault_instruction),
      .owner_idle_o(),  // Reserved lifecycle observations; RCU remains P7.
      .target_idle_o(),  // The P5 testbench checks all accepted-work barriers.
      .cpu_wait_o(s_cpu_wait),
      .dma_wait_o(s_dma_wait)
  );
  for (genvar group = 0; group < 4; group++) begin : gen_sram_attachment
    assign s_target_rst_n[group] = s_sram_rst_n;
    axi4_connector u_connector (
        .source(u_targets_axi4_if[group]),
        .sink  (u_sram_axi4_if[group])
    );
  end
  tiny_sram u_sram (
      .clk_i         (clk_i),
      .rst_n_i       (s_sram_rst_n),
      .local_ports   (u_cpu_local_if),
      .external_ports(u_sram_axi4_if),
      .cfg_apb4      (u_sram_apb4_if),
      .perf_enable_i (s_perf_enable),
      .perf_clear_i  (s_perf_clear)
  );
  apb4_xpi u_xpi (
      .clk_i          (clk_i),
      .rst_n_i        (s_xpi_rst_n),
      .mem_axi4       (u_targets_axi4_if[4]),
      .apb4           (u_xpi_apb4_if),
      .xpi            (xpi),
      .dma_xfer_done_i(s_dma_done),
      .dma_tx_stall_o (s_dma_stall[0]),
      .dma_rx_stall_o (s_dma_stall[1]),
      .irq_o          (s_xpi_irq)
  );
  `include "tiny_apb_bridges.svh"
axi4_error_slave #(
      .Response(2'b11)
  ) u_decode_error (
      .clk_i  (clk_i),
      .rst_n_i(s_fabric_rst_n),
      .axi4   (u_targets_axi4_if[`RETROSOC_TINY__DECODE_ERROR])
  );
  axi4_error_slave #(
      .Response(2'b10)
  ) u_protocol_error (
      .clk_i  (clk_i),
      .rst_n_i(s_fabric_rst_n),
      .axi4   (u_targets_axi4_if[`RETROSOC_TINY__PROTOCOL_ERROR])
  );
  tiny_fault_collector u_fault_collector (
      .local_valid_i         (s_local_fault_valid),
      .local_addr_i          (s_local_fault_addr),
      .local_write_i         (s_local_fault_write),
      .external_valid_i      (s_external_fault_valid),
      .external_addr_i       (s_external_fault_addr),
      .external_resp_i       (s_external_fault_resp),
      .external_instruction_i(s_external_fault_instruction),
      .count_o               (s_fault_count),
      .addr_o                (s_fault_addr),
      .master_o              (s_fault_master),
      .write_o               (s_fault_write),
      .resp_o                (s_fault_resp)
  );
  tiny_sysctrl u_sysctrl (
      .clk_i         (clk_i),
      .rst_n_i       (s_sysctrl_rst_n),
      .apb4          (u_sysctrl_apb4_if),
      .fault_valid_i (s_fault_count != 4'd0),
      .fault_count_i (s_fault_count),
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
      .rst_n_i(s_archinfo_rst_n),
      .apb4   (u_archinfo_apb4_if)
  );
  apb4_gpio #(
      .HasInputCmos(gpio_pad_caps_pkg::HasInputCmos),
      .HasPullUp   (gpio_pad_caps_pkg::HasPullUp),
      .HasPullDown (gpio_pad_caps_pkg::HasPullDown)
  ) u_gpio (
      .clk_i    (clk_i),
      .rst_n_i  (s_gpio_rst_n),
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
  assign uart0_tx_o              = u_uart0_if.tx_o;
  // Legacy ASIC observation pads are retained, not a Gen1 package binding.
  assign uart1_tx_o              = 1'b1;
  assign u_uart0_if.cts_n_i      = 1'b0;
  assign u_wdg_if.debug_halted_i = s_debug_halted;
  `include "tiny_gpio.svh"
  `include "tiny_irq.svh"
apb4_uart u_uart0 (
      .clk_i         (clk_i),
      .rst_n_i       (s_uart0_rst_n),
      .apb4          (u_uart0_apb4_if),
      .uart          (u_uart0_if),
      .dma_tx_stall_o(s_dma_stall[2]),
      .dma_rx_stall_o(s_dma_stall[3])
  );
  apb4_i2c u_i2c0 (
      .clk_i         (clk_i),
      .rst_n_i       (s_i2c0_rst_n),
      .apb4          (u_i2c0_apb4_if),
      .i2c           (u_i2c0_if),
      .dma_tx_stall_o(s_dma_stall[4]),
      .dma_rx_stall_o(s_dma_stall[5])
  );
  apb4_timer u_timer0 (
      .clk_i         (clk_i),
      .rst_n_i       (s_timer0_rst_n),
      .debug_halted_i(s_debug_halted),
      .apb4          (u_timer0_apb4_if),
      .irq_o         (s_timer0_irq)
  );
  apb4_timer u_timer1 (
      .clk_i         (clk_i),
      .rst_n_i       (s_timer1_rst_n),
      .debug_halted_i(s_debug_halted),
      .apb4          (u_timer1_apb4_if),
      .irq_o         (s_timer1_irq)
  );
  apb4_clint u_clint (
      .clk_i          (clk_i),
      .rst_n_i        (s_clint_rst_n),
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
      .NumChannels  (8),
      .MaxBurstBeats(16),
      .FifoDepth    (32),
      .RequestMask  (16'h31ff),
      .EnableStreams(1'b1)
  ) u_dma (
      .clk_i          (clk_i),
      .rst_n_i        (s_dma_rst_n),
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
  assign u_dma_req_if.i2s_tx_proc     = !s_i2s_tx_stall;
  assign u_dma_req_if.i2s_rx_proc     = !s_i2s_rx_stall;
  assign u_dma_req_if.crypto_in_proc  = s_crypto_input_ready;
  assign u_dma_req_if.crypto_out_proc = s_crypto_output_ready;
  assign u_dma_req_if.qspi_tx_proc    = !s_dma_stall[0];
  assign u_dma_req_if.qspi_rx_proc    = !s_dma_stall[1];
  assign u_dma_req_if.uart_tx_proc    = !s_dma_stall[2];
  assign u_dma_req_if.uart_rx_proc    = !s_dma_stall[3];
  assign u_dma_req_if.i2c0_tx_proc    = !s_dma_stall[4];
  assign u_dma_req_if.i2c0_rx_proc    = !s_dma_stall[5];
  assign u_dma_req_if.i2c1_tx_proc    = 1'b0;
  assign u_dma_req_if.i2c1_rx_proc    = 1'b0;
  assign u_dvp_rx_axis_if.tvalid      = '0;
  assign u_dvp_rx_axis_if.tdata       = '0;
  assign u_dvp_rx_axis_if.tstrb       = '0;
  assign u_dvp_rx_axis_if.tkeep       = '0;
  assign u_dvp_rx_axis_if.tlast       = '0;
  assign u_dvp_rx_axis_if.tid         = '0;
  assign u_dvp_rx_axis_if.tdest       = '0;
  assign u_dvp_rx_axis_if.tuser       = '0;

  // Host logic remains SAFE24. Audio reset waits for its own clock, never CPU boot.
  tc_clk_buf u_audio_clock_buffer (
      .clk_i(s_audio_pad_clk),
      .clk_o(s_audio_clk)
  );
  rst_sync #(
      .STAGE(5)
  ) u_audio_rst_sync (
      .clk_i  (s_audio_clk),
      .rst_n_i(s_i2s_rst_n),
      .rst_n_o(s_audio_rst_n)
  );
  apb4_i2s u_i2s (
      .clk_i            (clk_i),
      .rst_n_i          (s_i2s_rst_n),
      .clk_aud_i        (s_audio_clk),
      .rst_aud_n_i      (s_audio_rst_n),
      .dma_tx_stall_o   (s_i2s_tx_stall),
      .dma_rx_stall_o   (s_i2s_rx_stall),
      .tx_underrun_evt_o(),                  // Sticky status and IRQ retain these events.
      .rx_overrun_evt_o (),
      .rx_flush_busy_o  (),                  // No APU consumer in Tiny.
      .apb4             (u_i2s_apb4_if),
      .tx_axis          (u_i2s_tx_axis_if),
      .rx_axis          (u_i2s_rx_axis_if),
      .i2s              (u_i2s_if)
  );
  apb4_sdio #(
      .InputClockHz(24_000_000)
  ) u_sdio (
      .clk_i   (clk_i),
      .rst_n_i (s_sdio_rst_n),
      .apb4    (u_sdio_apb4_if),
      .dma_axi4(u_masters_axi4_if[2]),
      .sdio    (u_sdio_if)
  );
  apb4_ws2812 u_ws2812 (
      .clk_i  (clk_i),
      .rst_n_i(s_ws2812_rst_n),
      .apb4   (u_ws2812_apb4_if),
      .ws2812 (u_ws2812_if)
  );
  apb4_crypto u_crypto (
      .clk_i            (clk_i),
      .rst_n_i          (s_crypto_rst_n),
      .dma_input_proc_o (s_crypto_input_ready),
      .dma_output_proc_o(s_crypto_output_ready),
      .irq_o            (s_crypto_irq),
      .apb4             (u_crypto_apb4_if),
      .crypto_in_axis   (u_crypto_tx_axis_if),
      .crypto_out_axis  (u_crypto_rx_axis_if)
  );
  apb4_crc u_crc (.apb4(u_crc_apb4_if));
  rng_deterministic_source u_rng_source (
      .clk_i      (clk_i),
      .rst_n_i    (s_rng_rst_n),
      .enable_i   (s_rng_en),
      .ready_i    (s_rng_ready),
      .valid_o    (s_rng_valid),
      .data_o     (s_rng_data),
      .qualified_o(s_rng_qualified),
      .fault_o    (s_rng_fault)
  );
  apb4_rng #(
      .FIFO_DEPTH(8)
  ) u_rng (
      .entropy_enable_o   (s_rng_en),
      .entropy_ready_o    (s_rng_ready),
      .entropy_valid_i    (s_rng_valid),
      .entropy_data_i     (s_rng_data),
      .entropy_qualified_i(s_rng_qualified),
      .entropy_fault_i    (s_rng_fault),
      .irq_o              (s_rng_irq),
      .apb4               (u_rng_apb4_if)
  );
endmodule
