// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.

interface psram_if ();
  logic       sck_o;
  logic [3:0] nss_o;
  logic [3:0] io_oe_o;
  logic [3:0] io_di_i;
  logic [3:0] io_do_o;
  logic       irq_o;

  modport dut(
      output sck_o,
      output nss_o,
      output io_oe_o,
      input io_di_i,
      output io_do_o,
      output irq_o
  );
endinterface

module apb4_psram (
    // verilog_format: off -- preserve reviewed port alignment
    input logic    clk_i,
    input logic    rst_n_i,
    apb4_if.slave  cfg_apb4,
    axi4_if.slave  mem_axi4,
    psram_if.dut   psram
    // verilog_format: on
);

  import psram_pkg::*;

  logic                 s_controller_en;
  logic                 s_memory_en;
  logic                 s_auto_init;
  logic                 s_wrap32;
  logic         [  3:0] s_chip_en;
  logic         [ 15:0] s_half_period;
  logic                 s_above_84mhz;
  logic         [ 31:0] s_powerup_cycles;
  logic         [ 15:0] s_cs_setup_cycles;
  logic         [ 15:0] s_cs_high_cycles;
  logic         [ 15:0] s_cs_hold_cycles;
  logic         [ 31:0] s_cs_max_low_cycles;
  logic         [ 31:0] s_access_timeout_cycles;
  logic                 s_init_start;
  logic                 s_recover_start;
  logic         [  1:0] s_recover_chip;
  logic                 s_abort;
  logic         [  3:0] s_chip_err_clear;

  logic                 s_init_busy;
  logic                 s_axi_busy;
  logic                 s_indirect_busy;
  logic                 s_phy_busy;
  logic                 s_quiesced;
  logic                 s_global_ready;
  logic         [  3:0] s_chip_present;
  logic         [  3:0] s_chip_ready;
  logic         [  3:0] s_chip_qpi;
  logic         [  3:0] s_chip_wrap32;
  logic         [  3:0] s_chip_err;
  logic         [ 47:0] s_chip0_id;
  logic         [ 47:0] s_chip1_id;
  logic         [ 47:0] s_chip2_id;
  logic         [ 47:0] s_chip3_id;
  psram_error_e         s_last_err;
  logic         [  1:0] s_last_err_chip;
  logic         [ 31:0] s_last_err_addr;

  logic                 s_indirect_start;
  psram_cmd_e           s_indirect_cmd;
  logic         [  1:0] s_indirect_chip;
  logic         [ 22:0] s_indirect_addr;
  logic         [  3:0] s_indirect_len;
  logic         [ 63:0] s_indirect_wdata;
  logic         [ 63:0] s_indirect_rdata;

  logic                 s_mem_req_valid;
  logic                 s_mem_req_ready;
  logic                 s_mem_req_write;
  logic         [  1:0] s_mem_req_chip;
  logic         [ 22:0] s_mem_req_addr;
  logic         [  2:0] s_mem_req_len;
  logic         [ 31:0] s_mem_req_wdata;
  logic                 s_mem_rsp_valid;
  logic                 s_mem_rsp_ready;
  logic                 s_mem_rsp_err;
  logic         [ 31:0] s_mem_rsp_rdata;

  logic                 s_phy_req_valid;
  logic                 s_phy_req_ready;
  psram_cmd_e           s_phy_req_cmd;
  logic         [  1:0] s_phy_req_chip;
  logic                 s_phy_req_qpi;
  logic         [ 22:0] s_phy_req_addr;
  logic         [  5:0] s_phy_req_len;
  logic         [ 63:0] s_phy_req_wdata;
  logic                 s_phy_done;
  logic                 s_phy_err;
  logic         [255:0] s_phy_rdata;

  logic                 s_init_done_event;
  logic                 s_indirect_done_event;
  logic                 s_err_event;
  logic                 s_timeout_event;
  logic         [  2:0] s_perf_read_byte_event;
  logic         [  2:0] s_perf_write_byte_event;
  logic                 s_perf_cmd_event;
  logic                 s_perf_split_event;
  logic                 s_perf_stall_event;
  logic                 s_perf_err_event;

  psram_reg u_psram_reg (
      .clk_i                  (clk_i),
      .rst_n_i                (rst_n_i),
      .apb4                   (cfg_apb4),
      .init_busy_i            (s_init_busy),
      .axi_busy_i             (s_axi_busy),
      .indirect_busy_i        (s_indirect_busy),
      .phy_busy_i             (s_phy_busy),
      .quiesced_i             (s_quiesced),
      .global_ready_i         (s_global_ready),
      .chip_present_i         (s_chip_present),
      .chip_ready_i           (s_chip_ready),
      .chip_qpi_i             (s_chip_qpi),
      .chip_wrap32_i          (s_chip_wrap32),
      .chip_error_i           (s_chip_err),
      .chip0_id_i             (s_chip0_id),
      .chip1_id_i             (s_chip1_id),
      .chip2_id_i             (s_chip2_id),
      .chip3_id_i             (s_chip3_id),
      .last_error_i           (s_last_err),
      .last_error_chip_i      (s_last_err_chip),
      .last_error_addr_i      (s_last_err_addr),
      .indirect_rdata_i       (s_indirect_rdata),
      .init_done_event_i      (s_init_done_event),
      .indirect_done_event_i  (s_indirect_done_event),
      .error_event_i          (s_err_event),
      .timeout_event_i        (s_timeout_event),
      .perf_read_byte_event_i (s_perf_read_byte_event),
      .perf_write_byte_event_i(s_perf_write_byte_event),
      .perf_command_event_i   (s_perf_cmd_event),
      .perf_split_event_i     (s_perf_split_event),
      .perf_stall_event_i     (s_perf_stall_event),
      .perf_error_event_i     (s_perf_err_event),
      .controller_enable_o    (s_controller_en),
      .memory_enable_o        (s_memory_en),
      .auto_init_o            (s_auto_init),
      .wrap32_o               (s_wrap32),
      .chip_enable_o          (s_chip_en),
      .half_period_o          (s_half_period),
      .above_84mhz_o          (s_above_84mhz),
      .powerup_cycles_o       (s_powerup_cycles),
      .cs_setup_cycles_o      (s_cs_setup_cycles),
      .cs_high_cycles_o       (s_cs_high_cycles),
      .cs_hold_cycles_o       (s_cs_hold_cycles),
      .cs_max_low_cycles_o    (s_cs_max_low_cycles),
      .access_timeout_cycles_o(s_access_timeout_cycles),
      .init_start_o           (s_init_start),
      .recover_start_o        (s_recover_start),
      .recover_chip_o         (s_recover_chip),
      .abort_o                (s_abort),
      .chip_error_clear_o     (s_chip_err_clear),
      .indirect_start_o       (s_indirect_start),
      .indirect_command_o     (s_indirect_cmd),
      .indirect_chip_o        (s_indirect_chip),
      .indirect_addr_o        (s_indirect_addr),
      .indirect_length_o      (s_indirect_len),
      .indirect_wdata_o       (s_indirect_wdata),
      .irq_o                  (psram.irq_o)
  );

  psram_axi4 u_psram_axi4 (
      .clk_i          (clk_i),
      .rst_n_i        (rst_n_i),
      .accept_enable_i(!s_quiesced),
      .busy_o         (s_axi_busy),
      .stall_event_o  (s_perf_stall_event),
      .split_event_o  (s_perf_split_event),
      .axi4           (mem_axi4),
      .mem_req_valid_o(s_mem_req_valid),
      .mem_req_ready_i(s_mem_req_ready),
      .mem_req_write_o(s_mem_req_write),
      .mem_req_chip_o (s_mem_req_chip),
      .mem_req_addr_o (s_mem_req_addr),
      .mem_req_len_o  (s_mem_req_len),
      .mem_req_wdata_o(s_mem_req_wdata),
      .mem_rsp_valid_i(s_mem_rsp_valid),
      .mem_rsp_ready_o(s_mem_rsp_ready),
      .mem_rsp_error_i(s_mem_rsp_err),
      .mem_rsp_rdata_i(s_mem_rsp_rdata)
  );

  psram_core u_psram_core (
      .clk_i                  (clk_i),
      .rst_n_i                (rst_n_i),
      .controller_enable_i    (s_controller_en),
      .memory_enable_i        (s_memory_en),
      .auto_init_i            (s_auto_init),
      .wrap32_i               (s_wrap32),
      .chip_enable_i          (s_chip_en),
      .powerup_cycles_i       (s_powerup_cycles),
      .init_start_i           (s_init_start),
      .recover_start_i        (s_recover_start),
      .recover_chip_i         (s_recover_chip),
      .abort_i                (s_abort),
      .chip_error_clear_i     (s_chip_err_clear),
      .init_busy_o            (s_init_busy),
      .indirect_busy_o        (s_indirect_busy),
      .quiesced_o             (s_quiesced),
      .global_ready_o         (s_global_ready),
      .chip_present_o         (s_chip_present),
      .chip_ready_o           (s_chip_ready),
      .chip_qpi_o             (s_chip_qpi),
      .chip_wrap32_o          (s_chip_wrap32),
      .chip_error_o           (s_chip_err),
      .chip0_id_o             (s_chip0_id),
      .chip1_id_o             (s_chip1_id),
      .chip2_id_o             (s_chip2_id),
      .chip3_id_o             (s_chip3_id),
      .last_error_o           (s_last_err),
      .last_error_chip_o      (s_last_err_chip),
      .last_error_addr_o      (s_last_err_addr),
      .init_done_event_o      (s_init_done_event),
      .indirect_done_event_o  (s_indirect_done_event),
      .error_event_o          (s_err_event),
      .timeout_event_o        (s_timeout_event),
      .indirect_start_i       (s_indirect_start),
      .indirect_command_i     (s_indirect_cmd),
      .indirect_chip_i        (s_indirect_chip),
      .indirect_addr_i        (s_indirect_addr),
      .indirect_length_i      (s_indirect_len),
      .indirect_wdata_i       (s_indirect_wdata),
      .indirect_rdata_o       (s_indirect_rdata),
      .mem_req_valid_i        (s_mem_req_valid),
      .mem_req_ready_o        (s_mem_req_ready),
      .mem_req_write_i        (s_mem_req_write),
      .mem_req_chip_i         (s_mem_req_chip),
      .mem_req_addr_i         (s_mem_req_addr),
      .mem_req_len_i          (s_mem_req_len),
      .mem_req_wdata_i        (s_mem_req_wdata),
      .mem_rsp_valid_o        (s_mem_rsp_valid),
      .mem_rsp_ready_i        (s_mem_rsp_ready),
      .mem_rsp_error_o        (s_mem_rsp_err),
      .mem_rsp_rdata_o        (s_mem_rsp_rdata),
      .perf_read_byte_event_o (s_perf_read_byte_event),
      .perf_write_byte_event_o(s_perf_write_byte_event),
      .perf_command_event_o   (s_perf_cmd_event),
      .perf_error_event_o     (s_perf_err_event),
      .axi_busy_i             (s_axi_busy),
      .phy_req_valid_o        (s_phy_req_valid),
      .phy_req_ready_i        (s_phy_req_ready),
      .phy_req_command_o      (s_phy_req_cmd),
      .phy_req_chip_o         (s_phy_req_chip),
      .phy_req_qpi_o          (s_phy_req_qpi),
      .phy_req_addr_o         (s_phy_req_addr),
      .phy_req_length_o       (s_phy_req_len),
      .phy_req_wdata_o        (s_phy_req_wdata),
      .phy_busy_i             (s_phy_busy),
      .phy_done_i             (s_phy_done),
      .phy_error_i            (s_phy_err),
      .phy_rdata_i            (s_phy_rdata)
  );

  psram_phy u_psram_phy (
      .clk_i               (clk_i),
      .rst_n_i             (rst_n_i),
      .abort_i             (s_abort),
      .req_valid_i         (s_phy_req_valid),
      .req_ready_o         (s_phy_req_ready),
      .req_command_i       (s_phy_req_cmd),
      .req_chip_i          (s_phy_req_chip),
      .req_qpi_i           (s_phy_req_qpi),
      .req_addr_i          (s_phy_req_addr),
      .req_length_i        (s_phy_req_len),
      .req_wdata_i         (s_phy_req_wdata),
      .busy_o              (s_phy_busy),
      .done_o              (s_phy_done),
      .error_o             (s_phy_err),
      .rdata_o             (s_phy_rdata),
      .cfg_half_period_i   (s_half_period),
      .cfg_cs_setup_i      (s_cs_setup_cycles),
      .cfg_cs_high_i       (s_cs_high_cycles),
      .cfg_cs_hold_i       (s_cs_hold_cycles),
      .cfg_cs_max_low_i    (s_cs_max_low_cycles),
      .cfg_access_timeout_i(s_access_timeout_cycles),
      .psram_sclk_o        (psram.sck_o),
      .psram_nss_o         (psram.nss_o),
      .psram_io_oe_o       (psram.io_oe_o),
      .psram_io_di_i       (psram.io_di_i),
      .psram_io_do_o       (psram.io_do_o)
  );

  logic unused_above_84mhz;
  assign unused_above_84mhz = s_above_84mhz;

endmodule
