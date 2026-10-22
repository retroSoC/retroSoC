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
  logic s_halted_pclk, s_halted_ref, s_rtc_wake_sys;
  logic s_core_rst_n, s_cpu_bus_idle, s_cpu_quiesce;
  logic        s_cpu_clock_idle;
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
  logic s_rtc_func_rst_n, s_wdg_func_rst_n;
  logic [31:0] s_xin_hz, s_ref_hz, s_sys_hz, s_mem_hz, s_pclk_hz, s_clint_hz;
  logic [1:0] s_rcu_current;
  logic       s_rcu_busy;
  logic       s_clock_apply;
  logic [1:0] s_clock_profile;
  logic s_backend_busy, s_backend_fault;
  logic s_backend_sys_clk, s_backend_mem_clk, s_backend_pclk;
  logic s_backend_sys_rst_n, s_backend_mem_rst_n, s_backend_pclk_rst_n;
  logic [31:0] s_backend_xin_hz, s_backend_ref_hz, s_backend_sys_hz;
  logic [31:0] s_backend_mem_hz, s_backend_pclk_hz;
  logic                                  s_exec_clk;
  logic                                  s_ref_clk;
  logic [`RETROSOC_TINY__LEAF_COUNT-1:0] s_leaf_clk;
  logic [`RETROSOC_TINY__LEAF_COUNT-2:0] s_apb_cdc_idle, s_apb_cdc_ready;
  logic [                             2:0] s_owner_idle;
  logic [`RETROSOC_TINY__TARGET_COUNT-1:0] s_target_idle;
  logic                                    s_clock_safe;
  logic                                    s_xpi_cdc_busy;
  logic                                    s_dma_cdc_busy;
  logic s_dma_done_pending_d, s_dma_done_pending_q;
  logic s_dma_done_ready, s_dma_done_mem;
  logic [ 1:0] s_xpi_stall_pclk;
  logic [31:0] s_irq_async;
  logic        s_cpu_boot_ready;
  logic s_dma_cdc_ready, s_dma_ready_sys, s_xpi_cdc_ready;
  logic s_rcu_link_ready;
  logic s_clock_block, s_block_sys, s_block_pclk;
  logic s_clock_done, s_system_reset, s_backend_reset_n, s_pll_locked, s_pll_selected;
  logic s_rcu_irq;
  logic s_hart_reset, s_hart_seen_d, s_hart_seen_q, s_hart_pending_d, s_hart_pending_q;
  logic s_hart_ack, s_hart_reset_ref;
  logic [31:0] s_pclk_report_d, s_pclk_report_q, s_sys_report_d, s_sys_report_q;
  logic [31:0] s_pclk_snapshot, s_sys_snapshot;
  logic s_pclk_snapshot_valid, s_sys_snapshot_valid;
  logic s_rate_ref_pclk_rst_n, s_rate_pclk_rst_n;
  logic s_rate_ref_sys_rst_n, s_rate_sys_rst_n;
  logic [31:0] s_clkout_control;
  logic s_clkout, s_clkout_enable;
  logic s_clkout_idle_ref;
  logic [16:0] s_gate_request, s_local_reset, s_actual_gate, s_reset_held, s_reset_ready;
  logic [16:0] s_gate_ref, s_held_ref, s_ready_ref, s_disabled_sys;
  logic s_periph_apply, s_periph_reset_command, s_periph_block, s_periph_done;
  logic [16:0] s_periph_request, s_periph_reset_done;
  logic [4:0] s_periph_fault;
  logic       s_bus_idle_ref;
  logic s_boot_release_d, s_boot_release_q;
  logic s_wfi_gate_sys;
  logic [16:0] s_periph_idle, s_periph_idle_ref;
  logic s_xpi_idle, s_xpi_idle_ref;
  logic s_pwm_write, s_crc_write;
  logic [ 4:0] s_clock_fault;
  logic [31:0] s_clock_timeout;
  logic [ 1:0] s_backend_current;
  logic s_dma_admission_idle, s_dma_idle_sys, s_sdio_admission_idle;
  logic s_rng_en, s_rng_ready, s_rng_valid, s_rng_qualified, s_rng_fault, s_rng_irq;
  logic [31:0] s_rng_data;
  logic s_crypto_irq, s_crypto_input_ready, s_crypto_output_ready;
  logic s_i2s_tx_stall, s_i2s_rx_stall;
  logic s_i2s_reset_ready;
  logic s_dvp_irq, s_dvp_idle, s_dvp_reset_ready;
  logic s_spi_sck, s_spi_mosi, s_spi_cs_n, s_spi_output_enable, s_spi_miso;
  logic s_spi_irq, s_spi_session_owned, s_spi_lifecycle_idle;
  logic [1:0] s_spi_origin;
  logic [2:0] s_spi_channel;
  logic [31:0] s_gpio_user_select, s_gpio_user_handoff, s_gpio_alt_enable;
  logic [31:0] s_gpio_alt_select, s_gpio_output_enable, s_gpio_open_drain;
  logic [1:0] s_spi_credit_valid, s_spi_credit_retire, s_spi_dma_start_pending;
  logic [3:0] s_spi_dma_status;
  logic       s_spi_dma_error;
  // Commit strobes are register-visible inside the SPI shell; the SoC has no consumer yet.
  /* verilator lint_off UNUSEDSIGNAL */
  logic [1:0] s_spi_credit_commit;
  /* verilator lint_on UNUSEDSIGNAL */
  logic [4:0] s_spi_request;
  logic s_done_pclk_rst_n, s_done_mem_rst_n;
  `include "tiny_apb_interfaces.svh"
ahbl_if u_cpu_ahbl_if[2] (
      .hclk   (s_exec_clk),
      .hresetn(s_core_rst_n)
  );
  tiny_sram_port_if u_cpu_local_if[2] ();
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .USER_WIDTH(4)
  ) u_sram_axi4_if[4] (
      .aclk   (s_exec_clk),
      .aresetn(s_sram_rst_n)
  );
  uart_if u_uart0_if ();
  i2c_if u_i2c0_if ();
  pwm_if u_pwm_if ();
  clint_if u_clint_if ();
  gpio_if u_gpio_if ();
  user_gpio_if u_user_gpio_if ();
  dma_req_if u_dma_req_if ();
  i2s_if u_i2s_if ();
  dvp_if u_dvp_if ();
  ws2812_if u_ws2812_if ();
  sdio_if u_sdio_if ();
  rtc_if u_rtc_if (
      .rtc_clk_i  (s_ref_clk),
      .rtc_rst_n_i(s_rtc_func_rst_n)
  );
  // The watchdog reset pulse must survive resetting the bus/CPU. Its timer
  // resets after the AON backend retains the watchdog request.
  wdg_if u_wdg_if (
      .wdg_clk_i  (s_ref_clk),
      .wdg_rst_n_i(s_wdg_func_rst_n)
  );
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .USER_WIDTH(4)
  ) u_masters_axi4_if[3] (
      .aclk   (s_exec_clk),
      .aresetn(s_master_rst_n)
  );
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .USER_WIDTH(4)
  ) u_dma_pclk_axi4_if (
      .aclk   (s_dma_clk),
      .aresetn(s_dma_rst_n)
  );
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .USER_WIDTH(4)
  ) u_dma_admitted_axi4_if (
      .aclk   (s_backend_pclk),
      .aresetn(s_dma_rst_n)
  );
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .USER_WIDTH(4)
  ) u_sdio_sys_axi4_if (
      .aclk   (s_sdio_clk),
      .aresetn(s_sdio_rst_n)
  );
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .USER_WIDTH(4)
  ) u_targets_axi4_if[`RETROSOC_TINY__TARGET_COUNT] (
      .aclk   (s_exec_clk),
      .aresetn(s_target_rst_n)
  );
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .USER_WIDTH(4)
  ) u_xpi_mem_axi4_if (
      .aclk   (s_backend_mem_clk),
      .aresetn(s_backend_mem_rst_n)
  );
  axi4_stream_if #(
      .DATA_WIDTH(32)
  ) u_i2s_tx_axis_if (
      .aclk   (s_dma_clk),
      .aresetn(s_dma_rst_n)
  );
  axi4_stream_if #(
      .DATA_WIDTH(32)
  ) u_i2s_rx_axis_if (
      .aclk   (s_dma_clk),
      .aresetn(s_dma_rst_n)
  );
  axi4_stream_if #(
      .DATA_WIDTH(32)
  ) u_dvp_rx_axis_if (
      .aclk   (s_dma_clk),
      .aresetn(s_dma_rst_n)
  );
  axi4_stream_if #(
      .DATA_WIDTH(32)
  ) u_crypto_tx_axis_if (
      .aclk   (s_dma_clk),
      .aresetn(s_dma_rst_n)
  );
  axi4_stream_if #(
      .DATA_WIDTH(32)
  ) u_crypto_rx_axis_if (
      .aclk   (s_dma_clk),
      .aresetn(s_dma_rst_n)
  );
  cdc_sync #(
      .STAGE     (2),
      .DATA_WIDTH(1)
  ) u_debug_pclk_sync (
      .clk_i  (s_backend_pclk),
      .rst_n_i(s_backend_pclk_rst_n),
      .dat_i  (s_debug_halted),
      .dat_o  (s_halted_pclk)
  );
  cdc_sync #(
      .STAGE     (2),
      .DATA_WIDTH(1)
  ) u_debug_ref_sync (
      .clk_i  (s_ref_clk),
      .rst_n_i(s_por_rst_n),
      .dat_i  (s_debug_halted),
      .dat_o  (s_halted_ref)
  );
  cdc_sync #(
      .STAGE     (2),
      .DATA_WIDTH(1)
  ) u_rtc_wake_sync (
      .clk_i  (s_exec_clk),
      .rst_n_i(s_fabric_rst_n),
      .dat_i  (u_rtc_if.wake_o),
      .dat_o  (s_rtc_wake_sys)
  );
  rst_sync #(
      .STAGE(5)
  ) u_rtc_func_reset (
      .clk_i  (s_ref_clk),
      .rst_n_i(s_por_rst_n && s_backend_reset_n),
      .rst_n_o(s_rtc_func_rst_n)
  );
  rst_sync #(
      .STAGE(5)
  ) u_wdg_func_reset (
      .clk_i  (s_ref_clk),
      .rst_n_i(s_por_rst_n && s_backend_reset_n),
      .rst_n_o(s_wdg_func_rst_n)
  );
  assign s_hart_seen_d    = s_hart_reset;
  assign s_hart_pending_d = (s_hart_reset && !s_hart_seen_q) || (s_hart_pending_q && !s_hart_ack);
  dffr #(
      .DATA_WIDTH(2)
  ) u_hart_event (
      .clk_i  (s_exec_clk),
      .rst_n_i(rst_n_i),
      .dat_i  ({s_hart_pending_d, s_hart_seen_d}),
      .dat_o  ({s_hart_pending_q, s_hart_seen_q})
  );
  cdc_2phase #(
      .DATA_WIDTH(1)
  ) u_hart_event_cdc (
      .src_clk_i  (s_exec_clk),
      .src_rst_n_i(rst_n_i),
      .src_valid_i(s_hart_pending_q),
      .src_ready_o(s_hart_ack),
      .src_data_i (1'b1),
      .dst_clk_i  (s_ref_clk),
      .dst_rst_n_i(s_por_rst_n),
      .dst_valid_o(s_hart_reset_ref),
      .dst_ready_i(1'b1),
      .dst_data_o ()
  );
  cdc_reset_barrier #(
      .STAGES(5)
  ) u_pclk_rate_barrier (
      .clk_a_i  (s_ref_clk),
      .clk_b_i  (s_backend_pclk),
      .rst_n_i  (s_por_rst_n && s_backend_pclk_rst_n),
      .release_i(1'b1),
      .rst_a_n_o(s_rate_ref_pclk_rst_n),
      .rst_b_n_o(s_rate_pclk_rst_n)
  );
  cdc_reset_barrier #(
      .STAGES(5)
  ) u_sys_rate_barrier (
      .clk_a_i  (s_ref_clk),
      .clk_b_i  (s_exec_clk),
      .rst_n_i  (s_por_rst_n && s_backend_sys_rst_n),
      .release_i(1'b1),
      .rst_a_n_o(s_rate_ref_sys_rst_n),
      .rst_b_n_o(s_rate_sys_rst_n)
  );
  cdc_2phase #(
      .DATA_WIDTH(32)
  ) u_pclk_rate_cdc (
      .src_clk_i  (s_ref_clk),
      .src_rst_n_i(s_rate_ref_pclk_rst_n),
      .src_data_i (s_backend_pclk_hz),
      .src_valid_i(1'b1),
      .src_ready_o(),
      .dst_clk_i  (s_backend_pclk),
      .dst_rst_n_i(s_rate_pclk_rst_n),
      .dst_data_o (s_pclk_snapshot),
      .dst_valid_o(s_pclk_snapshot_valid),
      .dst_ready_i(1'b1)
  );
  cdc_2phase #(
      .DATA_WIDTH(32)
  ) u_sys_rate_cdc (
      .src_clk_i  (s_ref_clk),
      .src_rst_n_i(s_rate_ref_sys_rst_n),
      .src_data_i (s_backend_sys_hz),
      .src_valid_i(1'b1),
      .src_ready_o(),
      .dst_clk_i  (s_exec_clk),
      .dst_rst_n_i(s_rate_sys_rst_n),
      .dst_data_o (s_sys_snapshot),
      .dst_valid_o(s_sys_snapshot_valid),
      .dst_ready_i(1'b1)
  );
  assign s_pclk_report_d = s_pclk_snapshot_valid ? s_pclk_snapshot : s_pclk_report_q;
  assign s_sys_report_d  = s_sys_snapshot_valid ? s_sys_snapshot : s_sys_report_q;
  dffrc #(
      .DATA_WIDTH(32),
      .RESET_VAL (32'd24_000_000)
  ) u_pclk_report (
      .clk_i  (s_backend_pclk),
      .rst_n_i(s_backend_pclk_rst_n),
      .dat_i  (s_pclk_report_d),
      .dat_o  (s_pclk_report_q)
  );
  dffrc #(
      .DATA_WIDTH(32),
      .RESET_VAL (32'd24_000_000)
  ) u_sys_report (
      .clk_i  (s_exec_clk),
      .rst_n_i(s_backend_sys_rst_n),
      .dat_i  (s_sys_report_d),
      .dat_o  (s_sys_report_q)
  );
  cdc_sync #(
      .STAGE     (2),
      .DATA_WIDTH(1)
  ) u_clkout_idle_sync (
      .clk_i  (s_ref_clk),
      .rst_n_i(s_por_rst_n),
      .dat_i  (!s_clkout_enable),
      .dat_o  (s_clkout_idle_ref)
  );
  tiny_clock_output u_clock_output (
      .clk_ref_i   (s_ref_clk),
      .clk_sys_i   (s_exec_clk),
      .clk_mem_i   (s_backend_mem_clk),
      .clk_periph_i(s_backend_pclk),
      .rst_n_i     (s_por_rst_n && s_backend_reset_n),
      .control_i   (s_clkout_control),
      .clk_o       (s_clkout),
      .enable_o    (s_clkout_enable)
  );
  cdc_sync #(
      .STAGE     (2),
      .DATA_WIDTH(1)
  ) u_wfi_gate_sync (
      .clk_i  (s_exec_clk),
      .rst_n_i(s_fabric_rst_n),
      .dat_i  (s_gate_request[0]),
      .dat_o  (s_wfi_gate_sys)
  );
  assign s_reset_held[0]   = 1'b0;
  assign s_reset_ready[0]  = 1'b0;
  assign s_actual_gate[15] = 1'b0;
  assign s_reset_held[15]  = 1'b0;
  assign s_reset_ready[15] = 1'b0;
  cdc_sync #(
      .STAGE     (2),
      .DATA_WIDTH(17)
  ) u_gate_feedback (
      .clk_i  (s_ref_clk),
      .rst_n_i(s_por_rst_n),
      .dat_i  (s_actual_gate),
      .dat_o  (s_gate_ref)
  );
  cdc_sync #(
      .STAGE     (2),
      .DATA_WIDTH(17)
  ) u_held_feedback (
      .clk_i  (s_ref_clk),
      .rst_n_i(s_por_rst_n),
      .dat_i  (s_reset_held),
      .dat_o  (s_held_ref)
  );
  cdc_sync #(
      .STAGE     (2),
      .DATA_WIDTH(17)
  ) u_ready_feedback (
      .clk_i  (s_ref_clk),
      .rst_n_i(s_por_rst_n),
      .dat_i  (s_reset_ready),
      .dat_o  (s_ready_ref)
  );
  cdc_sync #(
      .STAGE     (2),
      .DATA_WIDTH(17)
  ) u_disabled_sync (
      .clk_i  (s_exec_clk),
      .rst_n_i(s_fabric_rst_n),
      .dat_i  (s_gate_request | s_local_reset),
      .dat_o  (s_disabled_sys)
  );
  cdc_sync #(
      .STAGE     (2),
      .DATA_WIDTH(1)
  ) u_bus_idle_ref (
      .clk_i  (s_ref_clk),
      .rst_n_i(s_por_rst_n),
      .dat_i  (s_clock_safe),
      .dat_o  (s_bus_idle_ref)
  );
  tiny_peripheral_control u_peripheral_control (
      .clk_i          (s_ref_clk),
      .rst_n_i        (s_por_rst_n),
      .warm_reset_i   (!s_backend_reset_n),
      .apply_i        (s_periph_apply),
      .reset_command_i(s_periph_reset_command),
      .request_i      (s_periph_request),
      .idle_i         (s_periph_idle_ref),
      .bus_idle_i     (s_bus_idle_ref),
      .gate_actual_i  (s_gate_ref),
      .reset_held_i   (s_held_ref),
      .reset_ready_i  (s_ready_ref),
      .timeout_i      (s_clock_timeout),
      .gate_o         (s_gate_request),
      .reset_o        (s_local_reset),
      .block_o        (s_periph_block),
      .done_o         (s_periph_done),
      .fault_o        (s_periph_fault),
      .reset_done_o   (s_periph_reset_done)
  );
  assign s_pwm_write = u_pwm_apb4_if.psel && u_pwm_apb4_if.penable && u_pwm_apb4_if.pready &&
      u_pwm_apb4_if.pwrite && !u_pwm_apb4_if.pslverr && u_pwm_apb4_if.pstrb[0];
  assign s_crc_write = u_crc_apb4_if.psel && u_crc_apb4_if.penable && u_crc_apb4_if.pready &&
      u_crc_apb4_if.pwrite && !u_crc_apb4_if.pslverr && u_crc_apb4_if.pstrb[0];
  tiny_managed_lifecycle u_managed_lifecycle (
      .clk_i      (s_backend_pclk),
      .pwm_rst_n_i(s_pwm_rst_n),
      .crc_rst_n_i(s_crc_rst_n),
      .pwm_write_i(s_pwm_write),
      .pwm_addr_i (u_pwm_apb4_if.paddr[11:0]),
      .pwm_data_i (u_pwm_apb4_if.pwdata),
      .crc_write_i(s_crc_write),
      .crc_addr_i (u_crc_apb4_if.paddr[11:0]),
      .crc_data_i (u_crc_apb4_if.pwdata),
      .pwm_idle_o (s_periph_idle[6]),
      .crc_idle_o (s_periph_idle[12])
  );
  assign s_periph_idle[0]  = s_cpu_bus_idle;
  assign s_periph_idle[1]  = !s_spi_session_owned && !(|s_gpio_user_select);
  assign s_periph_idle[11] = !s_rng_en && !s_rng_valid;
  assign s_periph_idle[15] = 1'b1;
  assign s_periph_idle[16] = s_spi_lifecycle_idle;
  assign s_spi_request     = u_spi_apb4_if.pwrite ? 5'd16 : 5'd17;
  cdc_sync #(
      .STAGE     (2),
      .DATA_WIDTH(17)
  ) u_periph_idle_sync (
      .clk_i  (s_ref_clk),
      .rst_n_i(s_por_rst_n),
      .dat_i  (s_periph_idle),
      .dat_o  (s_periph_idle_ref)
  );
  cdc_sync #(
      .STAGE     (2),
      .DATA_WIDTH(1)
  ) u_xpi_idle_sync (
      .clk_i  (s_ref_clk),
      .rst_n_i(s_por_rst_n),
      .dat_i  (s_xpi_idle),
      .dat_o  (s_xpi_idle_ref)
  );
  assign s_exec_clk    = s_backend_sys_clk;
  assign s_leaf_clk[0] = s_exec_clk;
  cdc_sync #(
      .STAGE     (2),
      .DATA_WIDTH(1)
  ) u_dma_ready_sync (
      .clk_i  (s_exec_clk),
      .rst_n_i(s_fabric_rst_n),
      .dat_i  (s_dma_cdc_ready),
      .dat_o  (s_dma_ready_sys)
  );
  assign s_boot_release_d = s_boot_release_q || (s_cpu_ready_rst_n &&
      (&s_apb_cdc_ready) && s_xpi_cdc_ready && s_dma_ready_sys && s_rcu_link_ready);
  dffr #(
      .DATA_WIDTH(1)
  ) u_boot_release (
      .clk_i  (s_exec_clk),
      .rst_n_i(s_fabric_rst_n),
      .dat_i  (s_boot_release_d),
      .dat_o  (s_boot_release_q)
  );
  rst_sync #(
      .STAGE(5)
  ) u_boot_reset (
      .clk_i  (s_exec_clk),
      .rst_n_i(s_cpu_ready_rst_n && s_boot_release_q),
      .rst_n_o(s_cpu_boot_ready)
  );
  cdc_sync #(
      .STAGE     (2),
      .DATA_WIDTH(2)
  ) u_xpi_stall_sync (
      .clk_i  (s_dma_clk),
      .rst_n_i(s_dma_rst_n),
      .dat_i  (s_dma_stall[1:0]),
      .dat_o  (s_xpi_stall_pclk)
  );
  // Central DMA emits one completion pulse. Retain it until MEM acknowledges;
  // a new completion coincident with acknowledgement wins over clearing.
  assign s_dma_done_pending_d = s_dma_done || (s_dma_done_pending_q && !s_dma_done_ready);
  dffr #(
      .DATA_WIDTH(1)
  ) u_dma_done_pending (
      .clk_i  (s_dma_clk),
      .rst_n_i(s_dma_rst_n),
      .dat_i  (s_dma_done_pending_d),
      .dat_o  (s_dma_done_pending_q)
  );
  cdc_reset_barrier #(
      .STAGES(5)
  ) u_dma_done_barrier (
      .clk_a_i  (s_dma_clk),
      .clk_b_i  (s_backend_mem_clk),
      .rst_n_i  (s_dma_rst_n && s_xpi_rst_n),
      .release_i(1'b1),
      .rst_a_n_o(s_done_pclk_rst_n),
      .rst_b_n_o(s_done_mem_rst_n)
  );
  cdc_2phase #(
      .DATA_WIDTH(1)
  ) u_dma_done_cdc (
      .src_clk_i  (s_dma_clk),
      .src_rst_n_i(s_done_pclk_rst_n),
      .src_valid_i(s_dma_done_pending_q),
      .src_ready_o(s_dma_done_ready),
      .src_data_i (1'b1),
      .dst_clk_i  (s_backend_mem_clk),
      .dst_rst_n_i(s_done_mem_rst_n),
      .dst_valid_o(s_dma_done_mem),
      .dst_ready_i(1'b1),
      .dst_data_o ()
  );
  assign s_clock_safe = s_cpu_clock_idle && (&s_owner_idle) && (&s_target_idle) &&
      (&s_apb_cdc_idle) && s_dma_idle_sys && s_sdio_admission_idle && !s_xpi_cdc_busy;
  cdc_sync #(
      .STAGE     (2),
      .DATA_WIDTH(1)
  ) u_block_sys (
      .clk_i  (s_exec_clk),
      .rst_n_i(s_fabric_rst_n),
      .dat_i  (s_clock_block || s_periph_block),
      .dat_o  (s_block_sys)
  );
  cdc_sync #(
      .STAGE     (2),
      .DATA_WIDTH(1)
  ) u_block_pclk (
      .clk_i  (s_dma_clk),
      .rst_n_i(s_dma_rst_n),
      .dat_i  (s_clock_block || s_periph_block),
      .dat_o  (s_block_pclk)
  );
  cdc_sync #(
      .STAGE     (2),
      .DATA_WIDTH(1)
  ) u_dma_idle_sync (
      .clk_i  (s_exec_clk),
      .rst_n_i(s_fabric_rst_n),
      .dat_i  (s_dma_admission_idle && !s_dma_done_pending_q && s_dma_done_ready),
      .dat_o  (s_dma_idle_sys)
  );
  assign s_fabric_rst_n = s_leaf_rst_n[0];
  assign s_master_rst_n = '{s_cpu_ready_rst_n, s_fabric_rst_n, s_sdio_rst_n};
  // The fabric-side XPI target is SYS-clocked; only the MEM endpoint uses the
  // XPI leaf reset. The async bridge invalidates accepted work if MEM resets.
  assign s_target_rst_n[4] = s_fabric_rst_n;
  assign s_target_rst_n[`RETROSOC_TINY__DECODE_ERROR] = s_fabric_rst_n;
  assign s_target_rst_n[`RETROSOC_TINY__PROTOCOL_ERROR] = s_fabric_rst_n;
  tiny_reset_tree #(
      .LeafCount   (`RETROSOC_TINY__LEAF_COUNT),
      .SplitDomains(1'b1)
  ) u_reset_tree (
      .clk_i               (s_exec_clk),
      .por_clk_i           (s_ref_clk),
      .leaf_clk_i          (s_leaf_clk),
      .backend_reset_n_i   (s_backend_reset_n),
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
      .clk_i  (s_ref_clk),
      .rst_n_i(s_clint_rst_n),
      .dat_i  (s_tick_count_d),
      .dat_o  (s_tick_count_q)
  );
  tiny_cpu_wrapper #(
      .ExternalIrqCount(30),
      .EnableAtomics   (1'b0),
      .ResetSyncStages (5),
      .EnableWfiGate   (1'b1),
      .PreserveDebug   (1'b1)
  ) u_cpu (
      .clk_i         (s_exec_clk),
      .rst_n_i       (s_cpu_boot_ready),
      .debug_rst_n_i (rst_n_i),
      .hart_reset_o  (s_hart_reset),
      .irq_i         (s_irq),
      .jtag_tck_i    (jtag_tck_i),
      .jtag_tms_i    (jtag_tms_i),
      .jtag_tdi_i    (jtag_tdi_i),
      .jtag_trst_n_i (jtag_trst_n_i),
      .jtag_tdo_o    (jtag_tdo_o),
      .debug_halted_o(s_debug_halted),
      .bus_idle_i    (s_cpu_bus_idle),
      .wfi_gate_i    (s_wfi_gate_sys),
      .gated_o       (s_actual_gate[0]),
      .core_rst_n_o  (s_core_rst_n),
      .quiesce_o     (s_cpu_quiesce),
      .cpu           (u_cpu_ahbl_if)
  );
  tiny_cpu_mem #(
      .ClockPause(1'b1)
  ) u_cpu_mem (
      .clk_i              (s_exec_clk),
      .rst_n_i            (s_core_rst_n),
      .quiesce_i          (s_cpu_quiesce),
      .clock_pause_i      (s_block_sys),
      .clock_idle_o       (s_cpu_clock_idle),
      .idle_o             (s_cpu_bus_idle),
      .local_fault_valid_o(s_local_fault_valid),
      .local_fault_addr_o (s_local_fault_addr),
      .local_fault_write_o(s_local_fault_write),
      .cpu                (u_cpu_ahbl_if),
      .local_ports        (u_cpu_local_if),
      .slow_axi4          (u_masters_axi4_if[0])
  );
  tiny_axi4_fabric u_fabric (
      .clk_i              (s_exec_clk),
      .rst_n_i            (s_fabric_rst_n),
      .target_rst_n_i     (s_target_rst_n),
      .masters            (u_masters_axi4_if),
      .targets            (u_targets_axi4_if),
      .perf_enable_i      (s_perf_enable),
      .perf_clear_i       (s_perf_clear),
      .fault_valid_o      (s_external_fault_valid),
      .fault_addr_o       (s_external_fault_addr),
      .fault_resp_o       (s_external_fault_resp),
      .fault_instruction_o(s_external_fault_instruction),
      .owner_idle_o       (s_owner_idle),
      .target_idle_o      (s_target_idle),
      .cpu_wait_o         (s_cpu_wait),
      .dma_wait_o         (s_dma_wait)
  );
  for (genvar group = 0; group < 4; group++) begin : gen_sram_attachment
    assign s_target_rst_n[group] = s_sram_rst_n;
    axi4_connector u_connector (
        .source(u_targets_axi4_if[group]),
        .sink  (u_sram_axi4_if[group])
    );
  end
  tiny_sram u_sram (
      .clk_i         (s_exec_clk),
      .rst_n_i       (s_sram_rst_n),
      .local_ports   (u_cpu_local_if),
      .external_ports(u_sram_axi4_if),
      .cfg_apb4      (u_sram_apb4_if),
      .perf_enable_i (s_perf_enable),
      .perf_clear_i  (s_perf_clear)
  );
  tiny_axi4_async_bridge #(
      .DataWidth(32),
      .IdWidth  (1),
      .UserWidth(4)
  ) u_dma_cdc (
      .src_clk_i   (s_dma_clk),
      .src_rst_n_i (s_dma_rst_n),
      .dst_clk_i   (s_exec_clk),
      .dst_rst_n_i (s_fabric_rst_n),
      .clear_i     (1'b0),
      .clear_busy_o(s_dma_cdc_busy),
      .ready_o     (s_dma_cdc_ready),
      .epoch_o     (),
      .src_axi4    (u_dma_admitted_axi4_if),
      .dst_axi4    (u_masters_axi4_if[1])
  );
  tiny_axi4_admission u_dma_admission (
      .clk_i  (s_dma_clk),
      .rst_n_i(s_dma_rst_n),
      .block_i(s_block_pclk),
      .idle_o (s_dma_admission_idle),
      .source (u_dma_pclk_axi4_if),
      .sink   (u_dma_admitted_axi4_if)
  );
  tiny_axi4_admission u_sdio_admission (
      .clk_i  (s_sdio_clk),
      .rst_n_i(s_sdio_rst_n),
      .block_i(s_block_sys),
      .idle_o (s_sdio_admission_idle),
      .source (u_sdio_sys_axi4_if),
      .sink   (u_masters_axi4_if[2])
  );
  tiny_axi4_async_bridge #(
      .DataWidth(32),
      .IdWidth  (1),
      .UserWidth(4)
  ) u_xpi_mem_cdc (
      .src_clk_i   (s_exec_clk),
      .src_rst_n_i (s_fabric_rst_n),
      .dst_clk_i   (s_backend_mem_clk),
      .dst_rst_n_i (s_xpi_rst_n),
      .clear_i     (1'b0),
      .clear_busy_o(s_xpi_cdc_busy),
      .ready_o     (s_xpi_cdc_ready),
      .epoch_o     (),
      .src_axi4    (u_targets_axi4_if[4]),
      .dst_axi4    (u_xpi_mem_axi4_if)
  );
  apb4_xpi u_xpi (
      .lifecycle_idle_o(s_xpi_idle),
      .clk_i           (s_backend_mem_clk),
      .rst_n_i         (s_xpi_rst_n),
      .mem_axi4        (u_xpi_mem_axi4_if),
      .apb4            (u_xpi_apb4_if),
      .xpi             (xpi),
      .dma_xfer_done_i (s_dma_done_mem),
      .dma_tx_stall_o  (s_dma_stall[0]),
      .dma_rx_stall_o  (s_dma_stall[1]),
      .irq_o           (s_xpi_irq)
  );
  `include "tiny_apb_bridges.svh"
axi4_error_slave #(
      .Response(2'b11)
  ) u_decode_error (
      .clk_i  (s_exec_clk),
      .rst_n_i(s_fabric_rst_n),
      .axi4   (u_targets_axi4_if[`RETROSOC_TINY__DECODE_ERROR])
  );
  axi4_error_slave #(
      .Response(2'b10)
  ) u_protocol_error (
      .clk_i  (s_exec_clk),
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
`ifdef HAVE_PLL
  localparam bit TinyPllPresent = 1'b1;
`else
  localparam bit TinyPllPresent = 1'b0;
`endif
  tiny_sysctrl #(
      .PllPresent (TinyPllPresent),
      .PllProfiles(TinyPllPresent),
      .XinHzValue (`SOC_EXT_CLK_HZ),
      .TargetMask (17'h17fff)
  ) u_sysctrl (
      .clk_i           (s_exec_clk),
      .rst_n_i         (s_sysctrl_rst_n),
      .clk_ref_i       (s_ref_clk),
      .rst_ref_n_i     (s_por_rst_n),
      .rcu_link_ready_o(s_rcu_link_ready),
      .apb4            (u_sysctrl_apb4_if),
      .fault_valid_i   (s_fault_count != 4'd0),
      .fault_count_i   (s_fault_count),
      .fault_addr_i    (s_fault_addr),
      .fault_write_i   (s_fault_write),
      .fault_master_i  (s_fault_master),
      .fault_resp_i    (s_fault_resp),
      .cpu_wait_i      (s_cpu_wait),
      .dma_wait_i      (s_dma_wait),
      .rtc_wake_i      (s_rtc_wake_sys),
      .clock_done_i    (s_clock_done),
      .periph_done_i   (s_periph_done),
      .periph_fault_i  (s_periph_fault),
      .gate_actual_i   (s_gate_ref),
      .reset_done_i    (s_periph_reset_done),
      .periph_apply_o  (s_periph_apply),
      .periph_reset_o  (s_periph_reset_command),
      .periph_request_o(s_periph_request),
      .clkout_control_o(s_clkout_control),
      .clkout_idle_i   (s_clkout_idle_ref),
      .clock_fault_i   (s_clock_fault),
      .clock_current_i (s_backend_current),
      .pll_locked_i    (s_pll_locked),
      .pll_selected_i  (s_pll_selected),
      .warm_reset_i    (!s_backend_reset_n),
      .system_reset_o  (s_system_reset),
      .watchdog_reset_i(u_wdg_if.reset_req_o),
      .hart_reset_i    (s_hart_reset_ref),
      .rcu_irq_o       (s_rcu_irq),
      .clock_timeout_o (s_clock_timeout),
      .perf_enable_o   (s_perf_enable),
      .perf_clear_o    (s_perf_clear),
      .test_done_o     (test_done_o),
      .test_pass_o     (test_pass_o),
      .test_code_o     (test_code_o),
      .xin_hz_o        (s_xin_hz),
      .ref_hz_o        (s_ref_hz),
      .sys_hz_o        (s_sys_hz),
      .mem_hz_o        (s_mem_hz),
      .pclk_hz_o       (s_pclk_hz),
      .clint_hz_o      (s_clint_hz),
      .rcu_current_o   (s_rcu_current),
      .rcu_busy_o      (s_rcu_busy),
      .clock_apply_o   (s_clock_apply),
      .clock_profile_o (s_clock_profile)
  );
  tiny_clock_reset_subsystem #(
      .RefClkHz(`SOC_EXT_CLK_HZ),
      .HavePll (TinyPllPresent)
  ) u_clock_backend (
      .ref_clk_i        (clk_i),
      .rst_n_i          (rst_n_i),
      .idle_i           (s_clock_safe),
      .clients_idle_i   ((&s_periph_idle_ref[16:1]) && s_xpi_idle_ref),
      .warm_reset_i     (u_wdg_if.reset_req_o),
      .system_request_i (s_system_reset),
      .command_ack_i    (s_cpu_clock_idle && s_target_idle[`RETROSOC_TINY__TARGET_SYSCTRL]),
      .timeout_i        (s_clock_timeout),
      .ref_clk_o        (s_ref_clk),
      .ref_rst_n_o      (),
      .system_reset_n_o (s_backend_reset_n),
      .block_o          (s_clock_block),
      .done_o           (s_clock_done),
      .fault_code_o     (s_clock_fault),
      .pll_locked_o     (s_pll_locked),
      .pll_selected_o   (s_pll_selected),
      .profile_i        (s_clock_profile),
      .apply_i          (s_clock_apply),
      .current_profile_o(s_backend_current),
      .busy_o           (s_backend_busy),
      .fault_o          (s_backend_fault),
      .sys_clk_o        (s_backend_sys_clk),
      .mem_clk_o        (s_backend_mem_clk),
      .pclk_o           (s_backend_pclk),
      .sys_rst_n_o      (s_backend_sys_rst_n),
      .mem_rst_n_o      (s_backend_mem_rst_n),
      .pclk_rst_n_o     (s_backend_pclk_rst_n),
      .xin_hz_o         (s_backend_xin_hz),
      .ref_hz_o         (s_backend_ref_hz),
      .sys_hz_o         (s_backend_sys_hz),
      .mem_hz_o         (s_backend_mem_hz),
      .pclk_hz_o        (s_backend_pclk_hz)
  );
  tiny_archinfo u_archinfo (
      .clk_i  (s_ref_clk),
      .rst_n_i(s_archinfo_rst_n),
      .apb4   (u_archinfo_apb4_if)
  );
  apb4_gpio #(
      .HasInputCmos(gpio_pad_caps_pkg::HasInputCmos),
      .HasPullUp   (gpio_pad_caps_pkg::HasPullUp),
      .HasPullDown (gpio_pad_caps_pkg::HasPullDown)
  ) u_gpio (
      .clk_i          (s_gpio_clk),
      .rst_n_i        (s_gpio_rst_n),
      .apb4           (u_gpio_apb4_if),
      .gpio           (u_gpio_if),
      .user_gpio      (u_user_gpio_if),
      .user_select_o  (s_gpio_user_select),
      .user_handoff_o (s_gpio_user_handoff),
      .alt_enable_o   (s_gpio_alt_enable),
      .alt_select_o   (s_gpio_alt_select),
      .output_enable_o(s_gpio_output_enable),
      .open_drain_o   (s_gpio_open_drain)
  );
  apb4_spi #(
      .EnableDma(1'b1)
  ) u_spi (
      .clk_i              (s_spi_clk),
      .rst_n_i            (s_spi_rst_n),
      .clock_hz_i         (s_pclk_report_q),
      .origin_i           (s_spi_origin),
      .request_i          (s_spi_request),
      .channel_i          (s_spi_channel),
      .credit_valid_i     (s_spi_credit_valid),
      .credit_retire_i    (s_spi_credit_retire),
      .dma_status_i       (s_spi_dma_status),
      .dma_start_pending_i(s_spi_dma_start_pending),
      .dma_error_i        (s_spi_dma_error),
      .user_select_i      (s_gpio_user_select),
      .handoff_i          (s_gpio_user_handoff),
      .alt_enable_i       (s_gpio_alt_enable),
      .alt_select_i       (s_gpio_alt_select),
      .output_enable_i    (s_gpio_output_enable),
      .open_drain_i       (s_gpio_open_drain),
      .gpio_ready_i       (s_gpio_rst_n && s_apb_cdc_ready[0]),
      .miso_i             (s_spi_miso),
      .sck_o              (s_spi_sck),
      .mosi_o             (s_spi_mosi),
      .cs_n_o             (s_spi_cs_n),
      .output_enable_o    (s_spi_output_enable),
      .irq_o              (s_spi_irq),
      .credit_commit_o    (s_spi_credit_commit),
      .session_owned_o    (s_spi_session_owned),
      .lifecycle_idle_o   (s_spi_lifecycle_idle),
      .apb4               (u_spi_apb4_if)
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
  assign u_wdg_if.debug_halted_i = s_halted_ref;
  `include "tiny_gpio.svh"
  `include "tiny_irq.svh"
cdc_sync #(
      .STAGE     (2),
      .DATA_WIDTH(32)
  ) u_irq_sync (
      .clk_i  (s_exec_clk),
      .rst_n_i(s_fabric_rst_n),
      .dat_i  (s_irq_async),
      .dat_o  (s_irq)
  );
  apb4_uart u_uart0 (
      .lifecycle_idle_o(s_periph_idle[2]),
      .clk_i           (s_uart0_clk),
      .rst_n_i         (s_uart0_rst_n),
      .apb4            (u_uart0_apb4_if),
      .uart            (u_uart0_if),
      .dma_tx_stall_o  (s_dma_stall[2]),
      .dma_rx_stall_o  (s_dma_stall[3])
  );
  apb4_i2c u_i2c0 (
      .lifecycle_idle_o(s_periph_idle[3]),
      .clk_i           (s_i2c0_clk),
      .rst_n_i         (s_i2c0_rst_n),
      .apb4            (u_i2c0_apb4_if),
      .i2c             (u_i2c0_if),
      .dma_tx_stall_o  (s_dma_stall[4]),
      .dma_rx_stall_o  (s_dma_stall[5])
  );
  apb4_timer u_timer0 (
      .lifecycle_idle_o(s_periph_idle[4]),
      .clk_i           (s_timer0_clk),
      .rst_n_i         (s_timer0_rst_n),
      .debug_halted_i  (s_halted_pclk),
      .apb4            (u_timer0_apb4_if),
      .irq_o           (s_timer0_irq)
  );
  apb4_timer u_timer1 (
      .lifecycle_idle_o(s_periph_idle[5]),
      .clk_i           (s_timer1_clk),
      .rst_n_i         (s_timer1_rst_n),
      .debug_halted_i  (s_halted_pclk),
      .apb4            (u_timer1_apb4_if),
      .irq_o           (s_timer1_irq)
  );
  apb4_clint u_clint (
      .clk_i          (s_ref_clk),
      .rst_n_i        (s_clint_rst_n),
      .timebase_tick_i(s_tick),
      .apb4           (u_clint_apb4_if),
      .clint          (u_clint_if)
  );
  apb4_pwm #(
      .PCLK_HZ          (24_000_000),
      .UseRuntimeClockHz(1'b1)
  ) u_pwm (
      .debug_halted_i(s_halted_pclk),
      .apb4          (u_pwm_apb4_if),
      .pwm           (u_pwm_if),
      .pclk_hz_i     (s_pclk_report_q)
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
  axi4s_dvp u_dvp (
      .clk_i                  (s_dvp_clk),
      .rst_n_i                (s_dvp_rst_n),
      .apb4                   (u_dvp_apb4_if),
      .rx_axis                (u_dvp_rx_axis_if),
      .dvp                    (u_dvp_if),
      .irq_o                  (s_dvp_irq),
      .lifecycle_idle_o       (s_dvp_idle),
      .lifecycle_reset_ready_o(s_dvp_reset_ready)
  );
  apb4_dma #(
      .NumChannels          (8),
      .MaxBurstBeats        (16),
      .FifoDepth            (32),
      .RequestMask          (32'h0003_39ff),
      .SupportedRequests    (32'h0003_39ff),
      .IpVersion            (32'h0002_0002),
      .EnableStreams        (1'b1),
      .EnableSpi            (1'b1),
      .EnableOriginQualifier(1'b1),
      .SpiTxAddress         (32'h1001_d054),
      .SpiRxAddress         (32'h1001_d058)
  ) u_dma (
      .lifecycle_idle_o   (s_periph_idle[9]),
      .clk_i              (s_dma_clk),
      .rst_n_i            (s_dma_rst_n),
      .dma_xfer_done_o    (s_dma_done),
      .irq_o              (s_dma_irq),
      .hw_trg             (u_dma_req_if),
      .apb4               (u_dma_apb4_if),
      .axi4               (u_dma_pclk_axi4_if),
      .i2s_tx_axis        (u_i2s_tx_axis_if),
      .i2s_rx_axis        (u_i2s_rx_axis_if),
      .dvp_rx_axis        (u_dvp_rx_axis_if),
      .crypto_in_axis     (u_crypto_tx_axis_if),
      .crypto_out_axis    (u_crypto_rx_axis_if),
      .spi_credit_valid_o (s_spi_credit_valid),
      .spi_credit_retire_o(s_spi_credit_retire),
      .spi_start_pending_o(s_spi_dma_start_pending),
      .spi_status_o       (s_spi_dma_status),
      .spi_error_o        (s_spi_dma_error)
  );
  assign u_dma_req_if.i2s_tx_proc     = !s_i2s_tx_stall;
  assign u_dma_req_if.i2s_rx_proc     = !s_i2s_rx_stall;
  assign u_dma_req_if.crypto_in_proc  = s_crypto_input_ready;
  assign u_dma_req_if.crypto_out_proc = s_crypto_output_ready;
  assign u_dma_req_if.qspi_tx_proc    = !s_xpi_stall_pclk[0];
  assign u_dma_req_if.qspi_rx_proc    = !s_xpi_stall_pclk[1];
  assign u_dma_req_if.uart_tx_proc    = !s_dma_stall[2];
  assign u_dma_req_if.uart_rx_proc    = !s_dma_stall[3];
  assign u_dma_req_if.i2c0_tx_proc    = !s_dma_stall[4];
  assign u_dma_req_if.i2c0_rx_proc    = !s_dma_stall[5];
  assign u_dma_req_if.i2c1_tx_proc    = 1'b0;
  assign u_dma_req_if.i2c1_rx_proc    = 1'b0;
  assign s_periph_idle[14]            = s_dvp_idle && s_dma_idle_sys;

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
      .lifecycle_reset_ready_o(s_i2s_reset_ready),
      .lifecycle_idle_o       (s_periph_idle[7]),
      .clk_i                  (s_i2s_clk),
      .rst_n_i                (s_i2s_rst_n),
      .clk_aud_i              (s_audio_clk),
      .rst_aud_n_i            (s_audio_rst_n),
      .dma_tx_stall_o         (s_i2s_tx_stall),
      .dma_rx_stall_o         (s_i2s_rx_stall),
      .tx_underrun_evt_o      (),                   // Sticky status and IRQ retain these events.
      .rx_overrun_evt_o       (),
      .rx_flush_busy_o        (),                   // No APU consumer in Tiny.
      .apb4                   (u_i2s_apb4_if),
      .tx_axis                (u_i2s_tx_axis_if),
      .rx_axis                (u_i2s_rx_axis_if),
      .i2s                    (u_i2s_if)
  );
  apb4_sdio #(
      .InputClockHz     (24_000_000),
      .UseRuntimeClockHz(1'b1)
  ) u_sdio (
      .lifecycle_idle_o(s_periph_idle[8]),
      .clk_i           (s_sdio_clk),
      .rst_n_i         (s_sdio_rst_n),
      .apb4            (u_sdio_apb4_if),
      .dma_axi4        (u_sdio_sys_axi4_if),
      .sdio            (u_sdio_if),
      .clock_hz_i      (s_sys_report_q)
  );
  apb4_ws2812 u_ws2812 (
      .lifecycle_idle_o(s_periph_idle[10]),
      .clk_i           (s_ws2812_clk),
      .rst_n_i         (s_ws2812_rst_n),
      .apb4            (u_ws2812_apb4_if),
      .ws2812          (u_ws2812_if)
  );
  apb4_crypto u_crypto (
      .lifecycle_idle_o (s_periph_idle[13]),
      .clk_i            (s_crypto_clk),
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
      .clk_i      (s_rng_clk),
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
