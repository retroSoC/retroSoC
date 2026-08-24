// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.
// See LICENSE for the complete license text.

`timescale 1ns / 1ps

module apb4_spisd #(
    parameter int InputClockHz = 72_000_000,
    parameter int AddrWidth    = 32,
    parameter int DataWidth    = 32,
    parameter int DescCount    = 16,
    parameter int FifoDepth    = 16
) (
    // verilog_format: off -- preserve the reviewed APB, AXI, and SPI port alignment
    input  logic    clk_i,
    input  logic    rst_n_i,
    apb4_if.slave   apb4,
    axi4_if.master  dma_axi4,
    spi_if.dut      spi
    // verilog_format: on
);
  logic s_busy, s_host_en, s_clock_en, s_clock_train;
  logic [15:0] s_half_period;
  logic [31:0] s_timeout_cmd, s_timeout_data, s_timeout_busy;
  logic                        [ 5:0] s_cmd_index;
  logic                        [31:0] s_cmd_arg;
  spisd_pkg::spisd_resp_type_e        s_cmd_resp_type;
  logic s_cmd_stuff_byte, s_cmd_data_present, s_cmd_auto_stop, s_cmd_start;
  logic [15:0] s_block_size, s_block_count;
  logic s_data_direction, s_data_dma_en, s_data_multi_block, s_data_crc_check;
  logic s_pio_wvalid, s_pio_write_ready, s_pio_valid, s_pio_read_consume;
  logic [31:0] s_pio_wdata, s_pio_rdata;
  logic [ 3:0] s_pio_wstrb;
  logic [31:0] s_desc_base;
  logic [15:0] s_desc_count;
  logic s_dma_start, s_dma_abort, s_host_abort, s_irq;
  logic [31:0] s_stat, s_clock_actual, s_cmd_stat, s_data_stat;
  logic [39:0] s_resp;
  logic [31:0] s_fifo_stat, s_dma_stat, s_current_desc, s_bytes_done;
  logic [31:0] s_dma_err_addr, s_dma_err, s_err_stat;
  logic [5:0] s_last_cmd;
  logic [31:0] s_crc_err_count, s_timeout_count, s_axi_err_count, s_stall_count;
  logic [6:0] s_irq_event;

  assign spi.irq_o = s_irq;

  spisd_reg u_spisd_reg (
      .clk_i             (clk_i),
      .rst_n_i           (rst_n_i),
      .busy_i            (s_busy),
      .status_i          (s_stat),
      .clock_actual_i    (s_clock_actual),
      .cmd_status_i      (s_cmd_stat),
      .response_i        (s_resp),
      .data_status_i     (s_data_stat),
      .fifo_status_i     (s_fifo_stat),
      .dma_status_i      (s_dma_stat),
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
      .pio_write_ready_i (s_pio_write_ready),
      .pio_read_consume_o(s_pio_read_consume),
      .pio_wvalid_o      (s_pio_wvalid),
      .pio_wdata_o       (s_pio_wdata),
      .pio_wstrb_o       (s_pio_wstrb),
      .host_enable_o     (s_host_en),
      .clock_enable_o    (s_clock_en),
      .clock_train_o     (s_clock_train),
      .half_period_o     (s_half_period),
      .timeout_cmd_o     (s_timeout_cmd),
      .timeout_data_o    (s_timeout_data),
      .timeout_busy_o    (s_timeout_busy),
      .cmd_index_o       (s_cmd_index),
      .cmd_arg_o         (s_cmd_arg),
      .cmd_resp_type_o   (s_cmd_resp_type),
      .cmd_stuff_byte_o  (s_cmd_stuff_byte),
      .cmd_data_present_o(s_cmd_data_present),
      .cmd_auto_stop_o   (s_cmd_auto_stop),
      .cmd_start_o       (s_cmd_start),
      .block_size_o      (s_block_size),
      .block_count_o     (s_block_count),
      .data_direction_o  (s_data_direction),
      .data_dma_enable_o (s_data_dma_en),
      .data_multi_block_o(s_data_multi_block),
      .data_crc_check_o  (s_data_crc_check),
      .desc_base_o       (s_desc_base),
      .desc_count_o      (s_desc_count),
      .dma_start_o       (s_dma_start),
      .dma_abort_o       (s_dma_abort),
      .host_abort_o      (s_host_abort),
      .irq_o             (s_irq),
      .apb4              (apb4)
  );

  spisd_core #(
      .InputClockHz(InputClockHz),
      .AddrWidth   (AddrWidth),
      .DataWidth   (DataWidth),
      .DescCount   (DescCount),
      .FifoDepth   (FifoDepth)
  ) u_spisd_core (
      .clk_i             (clk_i),
      .rst_n_i           (rst_n_i),
      .host_enable_i     (s_host_en),
      .clock_enable_i    (s_clock_en),
      .clock_train_i     (s_clock_train),
      .half_period_i     (s_half_period),
      .timeout_cmd_i     (s_timeout_cmd),
      .timeout_data_i    (s_timeout_data),
      .timeout_busy_i    (s_timeout_busy),
      .cmd_index_i       (s_cmd_index),
      .cmd_arg_i         (s_cmd_arg),
      .cmd_resp_type_i   (s_cmd_resp_type),
      .cmd_stuff_byte_i  (s_cmd_stuff_byte),
      .cmd_data_present_i(s_cmd_data_present),
      .cmd_auto_stop_i   (s_cmd_auto_stop),
      .cmd_start_i       (s_cmd_start),
      .block_size_i      (s_block_size),
      .block_count_i     (s_block_count),
      .data_direction_i  (s_data_direction),
      .data_dma_enable_i (s_data_dma_en),
      .data_multi_block_i(s_data_multi_block),
      .data_crc_check_i  (s_data_crc_check),
      .pio_wvalid_i      (s_pio_wvalid),
      .pio_wdata_i       (s_pio_wdata),
      .pio_wstrb_i       (s_pio_wstrb),
      .desc_base_i       (s_desc_base),
      .desc_count_i      (s_desc_count),
      .dma_start_i       (s_dma_start),
      .dma_abort_i       (s_dma_abort),
      .host_abort_i      (s_host_abort),
      .pio_read_consume_i(s_pio_read_consume),
      .pio_write_ready_o (s_pio_write_ready),
      .pio_rdata_o       (s_pio_rdata),
      .pio_valid_o       (s_pio_valid),
      .status_o          (s_stat),
      .clock_actual_o    (s_clock_actual),
      .cmd_status_o      (s_cmd_stat),
      .response_o        (s_resp),
      .data_status_o     (s_data_stat),
      .fifo_status_o     (s_fifo_stat),
      .dma_status_o      (s_dma_stat),
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
      .busy_o            (s_busy),
      .sck_o             (spi.sck_o),
      .nss_o             (spi.nss_o),
      .mosi_o            (spi.mosi_o),
      .miso_i            (spi.miso_i),
      .dma_axi4          (dma_axi4)
  );
endmodule
