// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of the Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// INCLUDING, BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY OR FITNESS FOR A
// PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

`timescale 1ns / 1ps
`include "axi4_define.svh"

module sdio_formal_design (
    // verilog_format: off -- scalar observations mirror the APB and AXI contracts
    input  logic        clk_i,
    input  logic        rst_n_i,
    input  logic        apb_psel_i,
    input  logic        apb_penable_i,
    input  logic        apb_pwrite_i,
    input  logic [31:0] apb_paddr_i,
    input  logic [31:0] apb_pwdata_i,
    input  logic [ 3:0] apb_pstrb_i,
    input  logic [ 7:0] irq_event_i,
    input  logic        axi_awready_i,
    input  logic        axi_wready_i,
    input  logic        axi_bvalid_i,
    input  logic        axi_bid_i,
    input  logic [ 1:0] axi_bresp_i,
    input  logic        axi_arready_i,
    input  logic        axi_rvalid_i,
    input  logic        axi_rid_i,
    input  logic [31:0] axi_rdata_i,
    input  logic [ 1:0] axi_rresp_i,
    input  logic        axi_rlast_i,
    input  logic        dma_data_out_ready_i,
    output logic        apb_pready_o,
    output logic [31:0] apb_prdata_o,
    output logic        apb_pslverr_o,
    output logic        irq_o,
    output logic        sck_o,
    output logic        launch_tick_o,
    output logic        sample_tick_o,
    output logic        clock_running_o,
    output logic        dma_busy_o,
    output logic        dma_done_o,
    output logic        dma_error_o,
    output logic [ 7:0] dma_error_code_o,
    output logic [31:0] dma_current_desc_o,
    output logic [31:0] dma_bytes_done_o,
    output logic [31:0] dma_error_addr_o,
    output logic        dma_data_out_valid_o,
    output logic [31:0] dma_data_out_o,
    output logic [ 3:0] dma_data_out_strb_o,
    output logic        dma_data_out_last_o,
    output logic        axi_awvalid_o,
    output logic [31:0] axi_awaddr_o,
    output logic [ 7:0] axi_awlen_o,
    output logic [ 2:0] axi_awsize_o,
    output logic [ 1:0] axi_awburst_o,
    output logic        axi_wvalid_o,
    output logic [31:0] axi_wdata_o,
    output logic [ 3:0] axi_wstrb_o,
    output logic        axi_wlast_o,
    output logic        axi_bready_o,
    output logic        axi_arvalid_o,
    output logic [31:0] axi_araddr_o,
    output logic [ 7:0] axi_arlen_o,
    output logic [ 2:0] axi_arsize_o,
    output logic [ 1:0] axi_arburst_o,
    output logic        axi_rready_o,
    output logic        host_enable_o,
    output logic        clock_enable_o,
    output logic [15:0] half_period_o,
    output logic [ 1:0] bus_width_o,
    output logic [15:0] desc_count_o,
    output logic        dma_start_o,
    output logic        dma_abort_o
    // verilog_format: on
);
  apb4_if apb4 (
      .pclk   (clk_i),
      .presetn(rst_n_i)
  );
  axi4_if #(
      .ADDR_WIDTH(32),
      .DATA_WIDTH(32),
      .ID_WIDTH  (1),
      .USER_WIDTH(1)
  ) dma_axi4 (
      .aclk   (clk_i),
      .aresetn(rst_n_i)
  );

  logic                              s_dma_busy;
  logic                              s_dma_done;
  logic                              s_dma_error;
  logic                      [  7:0] s_dma_error_code;
  logic                      [ 31:0] s_dma_current_desc;
  logic                      [ 31:0] s_dma_bytes_done;
  logic                      [ 31:0] s_dma_error_addr;
  logic                              s_data_out_valid;
  logic                      [ 31:0] s_data_out;
  logic                      [  3:0] s_data_out_strb;
  logic                              s_data_out_last;
  logic                              s_data_direction;
  logic                              s_data_dma_enable;
  logic                      [ 15:0] s_block_size;
  logic                      [ 15:0] s_block_count;
  logic                      [ 31:0] s_desc_base;
  logic                              s_clock_enable;
  logic                      [ 15:0] s_half_period;
  logic                              s_host_enable;
  logic                              s_dma_start;
  logic                              s_dma_abort;
  logic                              s_host_irq_enable;
  logic                              s_irq_dat1_enable;
  logic                      [ 31:0] s_status;
  logic                      [ 31:0] s_clock_actual;
  logic                      [ 31:0] s_cmd_status;
  logic                      [135:0] s_response;
  logic                      [ 31:0] s_data_status;
  logic                      [ 31:0] s_fifo_status;
  logic                      [ 31:0] s_dma_status;
  logic                      [ 31:0] s_dma_error_addr_reg;
  logic                      [ 31:0] s_dma_error_reg;
  logic                      [ 31:0] s_error_status;
  logic                      [  5:0] s_last_cmd;
  logic                      [ 31:0] s_crc_error_count;
  logic                      [ 31:0] s_timeout_count;
  logic                      [ 31:0] s_axi_error_count;
  logic                      [ 31:0] s_stall_count;
  logic                      [ 31:0] s_pio_rdata;
  logic                              s_pio_valid;
  logic                              s_pio_ready;
  logic                              s_data_start;
  logic                              s_cmd_start;
  logic                      [  5:0] s_cmd_index;
  logic                      [ 31:0] s_cmd_arg;
  sdio_pkg::sdio_resp_type_e         s_cmd_resp_type;
  logic                              s_cmd_crc_check;
  logic                              s_cmd_index_check;
  logic                      [ 15:0] s_desc_count_q;

  assign apb4.psel        = apb_psel_i;
  assign apb4.penable     = apb_penable_i;
  assign apb4.pwrite      = apb_pwrite_i;
  assign apb4.paddr       = apb_paddr_i;
  assign apb4.pwdata      = apb_pwdata_i;
  assign apb4.pstrb       = apb_pstrb_i;
  assign apb_pready_o     = apb4.pready;
  assign apb_prdata_o     = apb4.prdata;
  assign apb_pslverr_o    = apb4.pslverr;

  assign dma_axi4.awready = axi_awready_i;
  assign dma_axi4.wready  = axi_wready_i;
  assign dma_axi4.bvalid  = axi_bvalid_i;
  assign dma_axi4.bid     = axi_bid_i;
  assign dma_axi4.bresp   = axi_bresp_i;
  assign dma_axi4.buser   = '0;
  assign dma_axi4.arready = axi_arready_i;
  assign dma_axi4.rvalid  = axi_rvalid_i;
  assign dma_axi4.rid     = axi_rid_i;
  assign dma_axi4.rdata   = axi_rdata_i;
  assign dma_axi4.rresp   = axi_rresp_i;
  assign dma_axi4.rlast   = axi_rlast_i;
  assign dma_axi4.ruser   = '0;

  assign axi_awvalid_o    = dma_axi4.awvalid;
  assign axi_awaddr_o     = dma_axi4.awaddr;
  assign axi_awlen_o      = dma_axi4.awlen;
  assign axi_awsize_o     = dma_axi4.awsize;
  assign axi_awburst_o    = dma_axi4.awburst;
  assign axi_wvalid_o     = dma_axi4.wvalid;
  assign axi_wdata_o      = dma_axi4.wdata;
  assign axi_wstrb_o      = dma_axi4.wstrb;
  assign axi_wlast_o      = dma_axi4.wlast;
  assign axi_bready_o     = dma_axi4.bready;
  assign axi_arvalid_o    = dma_axi4.arvalid;
  assign axi_araddr_o     = dma_axi4.araddr;
  assign axi_arlen_o      = dma_axi4.arlen;
  assign axi_arsize_o     = dma_axi4.arsize;
  assign axi_arburst_o    = dma_axi4.arburst;
  assign axi_rready_o     = dma_axi4.rready;

  sdio_reg u_sdio_reg (
      .clk_i            (clk_i),
      .rst_n_i          (rst_n_i),
      .busy_i           (s_dma_busy),
      .status_i         (s_status),
      .clock_actual_i   (s_clock_actual),
      .cmd_status_i     (s_cmd_status),
      .response_i       (s_response),
      .data_status_i    (s_data_status),
      .fifo_status_i    (s_fifo_status),
      .dma_status_i     (s_dma_status),
      .current_desc_i   (s_dma_current_desc),
      .bytes_done_i     (s_dma_bytes_done),
      .dma_error_addr_i (s_dma_error_addr_reg),
      .dma_error_i      (s_dma_error_reg),
      .error_status_i   (s_error_status),
      .last_cmd_i       (s_last_cmd),
      .crc_error_count_i(s_crc_error_count),
      .timeout_count_i  (s_timeout_count),
      .axi_error_count_i(s_axi_error_count),
      .stall_count_i    (s_stall_count),
      .irq_event_i      (irq_event_i),
      .pio_rdata_i      (s_pio_rdata),
      .pio_valid_i      (s_pio_valid),
      .pio_ready_i      (s_pio_ready),
      .host_enable_o    (s_host_enable),
      .host_irq_enable_o(s_host_irq_enable),
      .clock_enable_o   (s_clock_enable),
      .half_period_o    (s_half_period),
      .bus_width_o      (bus_width_o),
      .timeout_cmd_o    (),
      .timeout_data_o   (),
      .timeout_busy_o   (),
      .cmd_index_o      (s_cmd_index),
      .cmd_arg_o        (s_cmd_arg),
      .cmd_resp_type_o  (s_cmd_resp_type),
      .cmd_crc_check_o  (s_cmd_crc_check),
      .cmd_index_check_o(s_cmd_index_check),
      .cmd_start_o      (s_cmd_start),
      .block_size_o     (s_block_size),
      .block_count_o    (s_block_count),
      .data_direction_o (s_data_direction),
      .data_dma_enable_o(s_data_dma_enable),
      .data_block_mode_o(),
      .data_fixed_addr_o(),
      .data_start_o     (s_data_start),
      .pio_wvalid_o     (),
      .pio_wdata_o      (),
      .pio_wstrb_o      (),
      .desc_base_o      (s_desc_base),
      .desc_count_o     (s_desc_count_q),
      .dma_start_o      (s_dma_start),
      .dma_abort_o      (s_dma_abort),
      .irq_dat1_enable_o(s_irq_dat1_enable),
      .irq_o            (irq_o),
      .apb4             (apb4)
  );

  assign host_enable_o        = s_host_enable;
  assign clock_enable_o       = s_clock_enable;
  assign half_period_o        = s_half_period;
  assign desc_count_o         = s_desc_count_q;
  assign dma_start_o          = s_dma_start;
  assign dma_abort_o          = s_dma_abort;
  assign s_clock_actual       = 32'd0;
  assign s_status             = 32'd0;
  assign s_cmd_status         = 32'd0;
  assign s_response           = '0;
  assign s_data_status        = 32'd0;
  assign s_fifo_status        = 32'd0;
  assign s_dma_status         = 32'd0;
  assign s_dma_error_addr_reg = s_dma_error_addr;
  assign s_dma_error_reg      = {24'd0, s_dma_error_code};
  assign s_error_status       = {24'd0, s_dma_error};
  assign s_last_cmd           = 6'd0;
  assign s_crc_error_count    = 32'd0;
  assign s_timeout_count      = 32'd0;
  assign s_axi_error_count    = 32'd0;
  assign s_stall_count        = 32'd0;
  assign s_pio_rdata          = 32'd0;
  assign s_pio_valid          = 1'b0;
  assign s_pio_ready          = 1'b1;

  sdio_clock u_sdio_clock (
      .clk_i        (clk_i),
      .rst_n_i      (rst_n_i),
      .enable_i     (s_host_enable && s_clock_enable),
      .half_period_i(s_half_period),
      .sck_o        (sck_o),
      .launch_tick_o(launch_tick_o),
      .sample_tick_o(sample_tick_o),
      .running_o    (clock_running_o)
  );

  sdio_dma u_sdio_dma (
      .clk_i           (clk_i),
      .rst_n_i         (rst_n_i),
      .start_i         (s_dma_start),
      .abort_i         (s_dma_abort),
      .direction_i     (s_data_direction),
      .desc_base_i     (s_desc_base),
      .desc_count_i    (s_desc_count_q),
      .total_bytes_i   ({16'd0, s_block_size} * {16'd0, s_block_count}),
      .data_in_valid_i (1'b0),
      .data_in_ready_o (),
      .data_in_i       ('0),
      .data_in_strb_i  ('0),
      .data_in_last_i  (1'b0),
      .data_out_valid_o(s_data_out_valid),
      .data_out_ready_i(dma_data_out_ready_i),
      .data_out_o      (s_data_out),
      .data_out_strb_o (s_data_out_strb),
      .data_out_last_o (s_data_out_last),
      .busy_o          (s_dma_busy),
      .done_o          (s_dma_done),
      .error_o         (s_dma_error),
      .error_code_o    (s_dma_error_code),
      .current_desc_o  (s_dma_current_desc),
      .bytes_done_o    (s_dma_bytes_done),
      .error_addr_o    (s_dma_error_addr),
      .dma_axi4        (dma_axi4)
  );

  assign dma_busy_o           = s_dma_busy;
  assign dma_done_o           = s_dma_done;
  assign dma_error_o          = s_dma_error;
  assign dma_error_code_o     = s_dma_error_code;
  assign dma_current_desc_o   = s_dma_current_desc;
  assign dma_bytes_done_o     = s_dma_bytes_done;
  assign dma_error_addr_o     = s_dma_error_addr;
  assign dma_data_out_valid_o = s_data_out_valid;
  assign dma_data_out_o       = s_data_out;
  assign dma_data_out_strb_o  = s_data_out_strb;
  assign dma_data_out_last_o  = s_data_out_last;
endmodule
