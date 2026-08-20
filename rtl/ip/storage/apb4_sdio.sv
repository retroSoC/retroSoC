// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

`timescale 1ns / 1ps

module apb4_sdio #(
    parameter int InputClockHz = 72_000_000,
    parameter int AddrWidth    = 32,
    parameter int DataWidth    = 32,
    parameter int DescCount    = 16
) (
    // verilog_format: off -- preserve the APB, AXI, and pad column alignment
    input logic                         clk_i,
    input logic                         rst_n_i,
    apb4_if.slave                       apb4,
    axi4_if.master                      dma_axi4,
    sdio_if.dut                         sdio
    // verilog_format: on
);
  logic                              s_busy;
  logic                              s_host_enable;
  logic                              s_host_irq_enable;
  logic                              s_clock_enable;
  logic                      [ 15:0] s_half_period;
  logic                      [  1:0] s_bus_width;
  logic                      [ 31:0] s_timeout_cmd;
  logic                      [ 31:0] s_timeout_data;
  logic                      [ 31:0] s_timeout_busy;
  logic                      [  5:0] s_cmd_index;
  logic                      [ 31:0] s_cmd_arg;
  sdio_pkg::sdio_resp_type_e         s_cmd_resp_type;
  logic                              s_cmd_crc_check;
  logic                              s_cmd_index_check;
  logic                              s_cmd_start;
  logic                      [ 15:0] s_block_size;
  logic                      [ 15:0] s_block_count;
  logic                              s_data_direction;
  logic                              s_data_dma_enable;
  logic                              s_data_block_mode;
  logic                              s_data_fixed_addr;
  logic                              s_data_start;
  logic                              s_pio_wvalid;
  logic                      [ 31:0] s_pio_wdata;
  logic                      [  3:0] s_pio_wstrb;
  logic                      [ 31:0] s_desc_base;
  logic                      [ 15:0] s_desc_count;
  logic                              s_dma_start;
  logic                              s_dma_abort;
  logic                              s_host_abort;
  logic                              s_irq_dat1_enable;
  logic                              s_irq;
  logic                      [ 31:0] s_status;
  logic                      [ 31:0] s_clock_actual;
  logic                      [ 31:0] s_cmd_status;
  logic                      [135:0] s_response;
  logic                      [ 31:0] s_data_status;
  logic                      [ 31:0] s_fifo_status;
  logic                      [ 31:0] s_dma_status;
  logic                      [ 31:0] s_current_desc;
  logic                      [ 31:0] s_bytes_done;
  logic                      [ 31:0] s_dma_err_addr;
  logic                      [ 31:0] s_dma_err;
  logic                      [ 31:0] s_err_stat;
  logic                      [  5:0] s_last_cmd;
  logic                      [ 31:0] s_crc_err_count;
  logic                      [ 31:0] s_timeout_count;
  logic                      [ 31:0] s_axi_err_count;
  logic                      [ 31:0] s_stall_count;
  logic                      [  7:0] s_irq_event;
  logic                      [ 31:0] s_pio_rdata;
  logic                              s_pio_valid;
  logic                              s_pio_ready;
  logic                              s_pio_read_consume;
  sdio_if u_sdio_core_if ();

  assign u_sdio_core_if.cmd_di_i = sdio.cmd_di_i;
  assign u_sdio_core_if.dat_di_i = sdio.dat_di_i;
  assign sdio.sck_o              = u_sdio_core_if.sck_o;
  assign sdio.cmd_oe_o           = u_sdio_core_if.cmd_oe_o;
  assign sdio.cmd_do_o           = u_sdio_core_if.cmd_do_o;
  assign sdio.dat_oe_o           = u_sdio_core_if.dat_oe_o;
  assign sdio.dat_do_o           = u_sdio_core_if.dat_do_o;

  sdio_reg u_sdio_reg (
      .clk_i             (clk_i),
      .rst_n_i           (rst_n_i),
      .busy_i            (s_busy),
      .status_i          (s_status),
      .clock_actual_i    (s_clock_actual),
      .cmd_status_i      (s_cmd_status),
      .response_i        (s_response),
      .data_status_i     (s_data_status),
      .fifo_status_i     (s_fifo_status),
      .dma_status_i      (s_dma_status),
      .current_desc_i    (s_current_desc),
      .bytes_done_i      (s_bytes_done),
      .dma_error_addr_i  (s_dma_err_addr),
      .dma_error_i       (s_dma_err),
      .error_status_i    (s_err_stat),
      .last_cmd_i        (s_last_cmd),
      .crc_error_count_i (s_crc_err_count),
      .timeout_count_i   (s_timeout_count),
      .axi_error_count_i (s_axi_err_count),
      .stall_count_i     (s_stall_count),
      .irq_event_i       (s_irq_event),
      .pio_rdata_i       (s_pio_rdata),
      .pio_valid_i       (s_pio_valid),
      .pio_ready_i       (s_pio_ready),
      .pio_read_consume_o(s_pio_read_consume),
      .host_enable_o     (s_host_enable),
      .host_irq_enable_o (s_host_irq_enable),
      .clock_enable_o    (s_clock_enable),
      .half_period_o     (s_half_period),
      .bus_width_o       (s_bus_width),
      .timeout_cmd_o     (s_timeout_cmd),
      .timeout_data_o    (s_timeout_data),
      .timeout_busy_o    (s_timeout_busy),
      .cmd_index_o       (s_cmd_index),
      .cmd_arg_o         (s_cmd_arg),
      .cmd_resp_type_o   (s_cmd_resp_type),
      .cmd_crc_check_o   (s_cmd_crc_check),
      .cmd_index_check_o (s_cmd_index_check),
      .cmd_start_o       (s_cmd_start),
      .block_size_o      (s_block_size),
      .block_count_o     (s_block_count),
      .data_direction_o  (s_data_direction),
      .data_dma_enable_o (s_data_dma_enable),
      .data_block_mode_o (s_data_block_mode),
      .data_fixed_addr_o (s_data_fixed_addr),
      .data_start_o      (s_data_start),
      .pio_wvalid_o      (s_pio_wvalid),
      .pio_wdata_o       (s_pio_wdata),
      .pio_wstrb_o       (s_pio_wstrb),
      .desc_base_o       (s_desc_base),
      .desc_count_o      (s_desc_count),
      .dma_start_o       (s_dma_start),
      .dma_abort_o       (s_dma_abort),
      .host_abort_o      (s_host_abort),
      .irq_dat1_enable_o (s_irq_dat1_enable),
      .irq_o             (s_irq),
      .apb4              (apb4)
  );

  sdio_core #(
      .InputClockHz(InputClockHz),
      .AddrWidth   (AddrWidth),
      .DataWidth   (DataWidth),
      .DescCount   (DescCount)
  ) u_sdio_core (
      .clk_i             (clk_i),
      .rst_n_i           (rst_n_i),
      .host_enable_i     (s_host_enable),
      .host_irq_enable_i (s_host_irq_enable),
      .clock_enable_i    (s_clock_enable),
      .half_period_i     (s_half_period),
      .bus_width_i       (s_bus_width),
      .timeout_cmd_i     (s_timeout_cmd),
      .timeout_data_i    (s_timeout_data),
      .timeout_busy_i    (s_timeout_busy),
      .cmd_index_i       (s_cmd_index),
      .cmd_arg_i         (s_cmd_arg),
      .cmd_resp_type_i   (s_cmd_resp_type),
      .cmd_crc_check_i   (s_cmd_crc_check),
      .cmd_index_check_i (s_cmd_index_check),
      .cmd_start_i       (s_cmd_start),
      .block_size_i      (s_block_size),
      .block_count_i     (s_block_count),
      .data_direction_i  (s_data_direction),
      .data_dma_enable_i (s_data_dma_enable),
      .data_block_mode_i (s_data_block_mode),
      .data_fixed_addr_i (s_data_fixed_addr),
      .data_start_i      (s_data_start),
      .pio_wvalid_i      (s_pio_wvalid),
      .pio_wdata_i       (s_pio_wdata),
      .pio_wstrb_i       (s_pio_wstrb),
      .desc_base_i       (s_desc_base),
      .desc_count_i      (s_desc_count),
      .dma_start_i       (s_dma_start),
      .dma_abort_i       (s_dma_abort),
      .host_abort_i      (s_host_abort),
      .irq_dat1_enable_i (s_irq_dat1_enable),
      .status_o          (s_status),
      .clock_actual_o    (s_clock_actual),
      .cmd_status_o      (s_cmd_status),
      .response_o        (s_response),
      .data_status_o     (s_data_status),
      .fifo_status_o     (s_fifo_status),
      .dma_status_o      (s_dma_status),
      .current_desc_o    (s_current_desc),
      .bytes_done_o      (s_bytes_done),
      .dma_error_addr_o  (s_dma_err_addr),
      .dma_error_o       (s_dma_err),
      .error_status_o    (s_err_stat),
      .last_cmd_o        (s_last_cmd),
      .crc_error_count_o (s_crc_err_count),
      .timeout_count_o   (s_timeout_count),
      .axi_error_count_o (s_axi_err_count),
      .stall_count_o     (s_stall_count),
      .irq_event_o       (s_irq_event),
      .pio_rdata_o       (s_pio_rdata),
      .pio_valid_o       (s_pio_valid),
      .pio_ready_o       (s_pio_ready),
      .pio_read_consume_i(s_pio_read_consume),
      .busy_o            (s_busy),
      .sdio              (u_sdio_core_if),
      .dma_axi4          (dma_axi4)
  );

  assign sdio.irq_o = s_irq;
endmodule
