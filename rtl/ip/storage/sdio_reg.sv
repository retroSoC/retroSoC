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

`include "sdio_define.svh"

module sdio_reg (
    // verilog_format: off -- preserve the APB and protocol port column groups
    input  logic                          clk_i,
    input  logic                          rst_n_i,
    input  logic                          busy_i,
    input  logic [31:0]                   status_i,
    input  logic [31:0]                   clock_actual_i,
    input  logic [31:0]                   cmd_status_i,
    input  logic [135:0]                  response_i,
    input  logic [31:0]                   data_status_i,
    input  logic [31:0]                   fifo_status_i,
    input  logic [31:0]                   dma_status_i,
    input  logic [31:0]                   current_desc_i,
    input  logic [31:0]                   bytes_done_i,
    input  logic [31:0]                   dma_error_addr_i,
    input  logic [31:0]                   dma_error_i,
    input  logic [31:0]                   error_status_i,
    input  logic [5:0]                    last_cmd_i,
    input  logic [31:0]                   crc_error_count_i,
    input  logic [31:0]                   timeout_count_i,
    input  logic [31:0]                   axi_error_count_i,
    input  logic [31:0]                   stall_count_i,
    input  logic [7:0]                    irq_event_i,
    input  logic [31:0]                   pio_rdata_i,
    input  logic                          pio_valid_i,
    input  logic                          pio_ready_i,
    output logic                          host_enable_o,
    output logic                          host_irq_enable_o,
    output logic                          clock_enable_o,
    output logic [15:0]                   half_period_o,
    output logic [1:0]                    bus_width_o,
    output logic [31:0]                   timeout_cmd_o,
    output logic [31:0]                   timeout_data_o,
    output logic [31:0]                   timeout_busy_o,
    output logic [5:0]                    cmd_index_o,
    output logic [31:0]                   cmd_arg_o,
    output sdio_pkg::sdio_resp_type_e     cmd_resp_type_o,
    output logic                          cmd_crc_check_o,
    output logic                          cmd_index_check_o,
    output logic                          cmd_start_o,
    output logic [15:0]                   block_size_o,
    output logic [15:0]                   block_count_o,
    output logic                          data_direction_o,
    output logic                          data_dma_enable_o,
    output logic                          data_block_mode_o,
    output logic                          data_fixed_addr_o,
    output logic                          data_start_o,
    output logic                          pio_wvalid_o,
    output logic [31:0]                   pio_wdata_o,
    output logic [3:0]                    pio_wstrb_o,
    output logic                          pio_read_consume_o,
    output logic [31:0]                   desc_base_o,
    output logic [15:0]                   desc_count_o,
    output logic                          dma_start_o,
    output logic                          dma_abort_o,
    output logic                          host_abort_o,
    output logic                          irq_dat1_enable_o,
    output logic                          irq_o,
    apb4_if.slave                         apb4
    // verilog_format: on
);
  import sdio_pkg::*;

  logic s_apb4_ready_d, s_apb4_ready_q;
  logic [31:0] s_apb4_rdata_d, s_apb4_rdata_q;
  logic s_apb4_resp_err_d, s_apb4_resp_err_q;
  logic        s_req_accept;
  logic        s_write_access;
  logic        s_write_known;
  logic        s_write_error;
  logic        s_pio_write_wait;
  logic        s_pio_write_direction_error;
  logic [31:0] s_read_data;
  logic        s_read_error;
  logic [ 2:0] s_host_ctrl_q;
  logic        s_clock_en_q;
  logic [15:0] s_half_period_q;
  logic [ 1:0] s_bus_width_q;
  logic [31:0] s_timeout_cmd_q;
  logic [31:0] s_timeout_data_q;
  logic [31:0] s_timeout_busy_q;
  logic [ 5:0] s_cmd_index_q;
  logic [31:0] s_cmd_arg_q;
  logic [ 5:0] s_cmd_cfg_q;
  logic [15:0] s_block_size_q;
  logic [15:0] s_block_count_q;
  logic [ 6:0] s_data_cfg_q;
  logic [31:0] s_desc_base_q;
  logic [15:0] s_desc_count_q;
  logic [ 7:0] s_irq_stat_q;
  logic [ 7:0] s_irq_en_q;
  logic [31:0] s_err_stat_q;

  assign s_pio_write_direction_error = (s_data_cfg_q[0] == 1'b0);
  assign s_pio_write_wait = apb4.psel && apb4.penable && apb4.pwrite &&
                            (apb4.paddr[11:0] == `APB4_SDIO__PIO_DATA) && !pio_ready_i &&
                            !s_pio_write_direction_error;
  assign s_req_accept = apb4.psel && apb4.penable && !s_apb4_ready_q && !s_pio_write_wait;
  assign s_write_access = s_req_accept && apb4.pwrite;
  assign apb4.pready = s_apb4_ready_q;
  assign apb4.prdata = s_apb4_rdata_q;
  assign apb4.pslverr = s_apb4_resp_err_q;

  assign host_enable_o = s_host_ctrl_q[0];
  assign host_irq_enable_o = s_host_ctrl_q[2];
  assign clock_enable_o = s_clock_en_q;
  assign half_period_o = s_half_period_q;
  assign bus_width_o = s_bus_width_q;
  assign timeout_cmd_o = s_timeout_cmd_q;
  assign timeout_data_o = s_timeout_data_q;
  assign timeout_busy_o = s_timeout_busy_q;
  assign cmd_index_o = s_cmd_index_q;
  assign cmd_arg_o = s_cmd_arg_q;
  assign cmd_resp_type_o = sdio_resp_type_e'(s_cmd_cfg_q[3:0]);
  assign cmd_crc_check_o = s_cmd_cfg_q[4];
  assign cmd_index_check_o = s_cmd_cfg_q[5];
  assign block_size_o = s_block_size_q;
  assign block_count_o = s_block_count_q;
  assign data_direction_o = s_data_cfg_q[0];
  assign data_dma_enable_o = s_data_cfg_q[4];
  assign data_block_mode_o = s_data_cfg_q[5];
  assign data_fixed_addr_o = s_data_cfg_q[6];
  assign desc_base_o = s_desc_base_q;
  assign desc_count_o = s_desc_count_q;
  assign irq_dat1_enable_o = s_irq_en_q[6];
  assign irq_o = (s_irq_stat_q & s_irq_en_q) != 8'd0;
  assign pio_read_consume_o = s_req_accept && !apb4.pwrite &&
                              (apb4.paddr[11:0] == `APB4_SDIO__PIO_DATA) && pio_valid_i;

  always_comb begin
    s_read_data  = '0;
    s_read_error = 1'b0;
    unique case (apb4.paddr[11:0])
      `APB4_SDIO__IP_ID:           s_read_data = 32'h5344_494F;
      `APB4_SDIO__IP_VERSION:      s_read_data = 32'h0001_0000;
      `APB4_SDIO__CAPABILITY:      s_read_data = 32'h0000_01FF;
      `APB4_SDIO__HOST_CTRL:       s_read_data = {29'd0, s_host_ctrl_q[2], 1'b0, s_host_ctrl_q[0]};
      `APB4_SDIO__CLOCK_CTRL:      s_read_data = {8'd0, s_half_period_q, 7'd0, s_clock_en_q};
      `APB4_SDIO__CLOCK_ACTUAL:    s_read_data = clock_actual_i;
      `APB4_SDIO__BUS_CTRL:        s_read_data = {30'd0, s_bus_width_q};
      `APB4_SDIO__TIMEOUT_CMD:     s_read_data = s_timeout_cmd_q;
      `APB4_SDIO__TIMEOUT_DATA:    s_read_data = s_timeout_data_q;
      `APB4_SDIO__TIMEOUT_BUSY:    s_read_data = s_timeout_busy_q;
      `APB4_SDIO__STATUS:          s_read_data = status_i;
      `APB4_SDIO__PRESENT:         s_read_data = 32'h0000_0001;
      `APB4_SDIO__CMD_ARG:         s_read_data = s_cmd_arg_q;
      `APB4_SDIO__CMD_CFG:         s_read_data = {26'd0, s_cmd_cfg_q};
      `APB4_SDIO__CMD_STATUS:      s_read_data = cmd_status_i;
      `APB4_SDIO__RESP0:           s_read_data = response_i[31:0];
      `APB4_SDIO__RESP1:           s_read_data = response_i[63:32];
      `APB4_SDIO__RESP2:           s_read_data = response_i[95:64];
      `APB4_SDIO__RESP3:           s_read_data = response_i[127:96];
      `APB4_SDIO__RESP4:           s_read_data = {24'd0, response_i[135:128]};
      `APB4_SDIO__BLOCK_SIZE:      s_read_data = {16'd0, s_block_size_q};
      `APB4_SDIO__BLOCK_COUNT:     s_read_data = {16'd0, s_block_count_q};
      `APB4_SDIO__DATA_CFG:        s_read_data = {25'd0, s_data_cfg_q};
      `APB4_SDIO__DATA_START:      s_read_data = data_status_i;
      `APB4_SDIO__PIO_DATA: begin
        s_read_data  = pio_rdata_i;
        s_read_error = !pio_valid_i;
      end
      `APB4_SDIO__FIFO_STATUS:     s_read_data = fifo_status_i;
      `APB4_SDIO__FIFO_WATERMARK:  s_read_data = 32'd1;
      `APB4_SDIO__DESC_BASE:       s_read_data = s_desc_base_q;
      `APB4_SDIO__DESC_COUNT:      s_read_data = {16'd0, s_desc_count_q};
      `APB4_SDIO__DMA_CTRL:        s_read_data = 32'd0;
      `APB4_SDIO__DMA_STATUS:      s_read_data = dma_status_i;
      `APB4_SDIO__CURRENT_DESC:    s_read_data = current_desc_i;
      `APB4_SDIO__BYTES_DONE:      s_read_data = bytes_done_i;
      `APB4_SDIO__DMA_ERROR_ADDR:  s_read_data = dma_error_addr_i;
      `APB4_SDIO__DMA_ERROR:       s_read_data = dma_error_i;
      `APB4_SDIO__IRQ_STATUS:      s_read_data = {24'd0, s_irq_stat_q};
      `APB4_SDIO__IRQ_ENABLE:      s_read_data = {24'd0, s_irq_en_q};
      `APB4_SDIO__ERROR_STATUS:    s_read_data = s_err_stat_q;
      `APB4_SDIO__LAST_CMD:        s_read_data = {26'd0, last_cmd_i};
      `APB4_SDIO__CRC_ERROR_COUNT: s_read_data = crc_error_count_i;
      `APB4_SDIO__TIMEOUT_COUNT:   s_read_data = timeout_count_i;
      `APB4_SDIO__AXI_ERROR_COUNT: s_read_data = axi_error_count_i;
      `APB4_SDIO__STALL_COUNT:     s_read_data = stall_count_i;
      `APB4_SDIO__DEBUG:           s_read_data = {30'd0, pio_ready_i, pio_valid_i};
      default:                     s_read_error = 1'b1;
    endcase
  end

  always_comb begin
    s_write_known = 1'b1;
    s_write_error = 1'b0;
    unique case (apb4.paddr[11:0])
      `APB4_SDIO__HOST_CTRL,
      `APB4_SDIO__CLOCK_CTRL,
      `APB4_SDIO__BUS_CTRL,
      `APB4_SDIO__TIMEOUT_CMD,
      `APB4_SDIO__TIMEOUT_DATA,
      `APB4_SDIO__TIMEOUT_BUSY,
      `APB4_SDIO__CMD_ARG,
      `APB4_SDIO__CMD_CFG,
      `APB4_SDIO__BLOCK_SIZE,
      `APB4_SDIO__BLOCK_COUNT,
      `APB4_SDIO__DATA_CFG,
      `APB4_SDIO__DESC_BASE,
      `APB4_SDIO__DESC_COUNT,
      `APB4_SDIO__IRQ_ENABLE: begin
        if (busy_i && (apb4.paddr[11:0] != `APB4_SDIO__HOST_CTRL)) begin
          s_write_error = 1'b1;
        end
      end
      `APB4_SDIO__CMD_START: begin
        s_write_error = (apb4.pstrb[0] == 1'b0) || (apb4.pwdata[31:1] != 31'd0) || busy_i;
      end
      `APB4_SDIO__DATA_START: begin
        s_write_error = (apb4.pstrb[0] == 1'b0) || (apb4.pwdata[31:1] != 31'd0) || busy_i;
      end
      `APB4_SDIO__PIO_DATA: begin
        s_write_error = (busy_i == 1'b0) || s_pio_write_direction_error;
      end
      `APB4_SDIO__DMA_CTRL: begin
        s_write_error = (apb4.pwdata[31:2] != 30'd0) ||
                        (apb4.pwdata[0] && !s_data_cfg_q[4]) ||
                        (busy_i && apb4.pwdata[0]);
      end
      `APB4_SDIO__IRQ_STATUS, `APB4_SDIO__IRQ_TEST, `APB4_SDIO__ERROR_STATUS: begin
        s_write_error = apb4.pstrb[0] == 1'b0;
      end
      default: begin
        s_write_known = 1'b0;
        s_write_error = 1'b1;
      end
    endcase
  end

  always_comb begin
    s_apb4_ready_d    = s_req_accept;
    s_apb4_rdata_d    = s_apb4_rdata_q;
    s_apb4_resp_err_d = s_apb4_resp_err_q;
    if (s_req_accept) begin
      s_apb4_rdata_d    = s_read_data;
      s_apb4_resp_err_d = s_read_error;
      if (s_write_access) begin
        s_apb4_resp_err_d = !s_write_known || s_write_error;
      end
    end
  end

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      s_apb4_ready_q    <= 1'b0;
      s_apb4_rdata_q    <= '0;
      s_apb4_resp_err_q <= 1'b0;
      s_host_ctrl_q     <= '0;
      s_clock_en_q      <= 1'b0;
      s_half_period_q   <= 16'd90;
      s_bus_width_q     <= 2'd0;
      s_timeout_cmd_q   <= 32'd100000;
      s_timeout_data_q  <= 32'd1000000;
      s_timeout_busy_q  <= 32'd1000000;
      s_cmd_index_q     <= '0;
      s_cmd_arg_q       <= '0;
      s_cmd_cfg_q       <= 6'd0;
      s_block_size_q    <= 16'd512;
      s_block_count_q   <= 16'd1;
      s_data_cfg_q      <= '0;
      s_desc_base_q     <= '0;
      s_desc_count_q    <= 16'd1;
      s_irq_stat_q      <= '0;
      s_irq_en_q        <= '0;
      s_err_stat_q      <= '0;
      cmd_start_o       <= 1'b0;
      data_start_o      <= 1'b0;
      pio_wvalid_o      <= 1'b0;
      pio_wdata_o       <= '0;
      pio_wstrb_o       <= '0;
      dma_start_o       <= 1'b0;
      dma_abort_o       <= 1'b0;
      host_abort_o      <= 1'b0;
    end else begin
      s_apb4_ready_q    <= s_apb4_ready_d;
      s_apb4_rdata_q    <= s_apb4_rdata_d;
      s_apb4_resp_err_q <= s_apb4_resp_err_d;
      cmd_start_o       <= 1'b0;
      data_start_o      <= 1'b0;
      pio_wvalid_o      <= 1'b0;
      dma_start_o       <= 1'b0;
      dma_abort_o       <= 1'b0;
      host_abort_o      <= 1'b0;

      s_irq_stat_q      <= (s_irq_stat_q & ~irq_event_i) | irq_event_i;
      s_err_stat_q      <= s_err_stat_q | error_status_i;
      if (s_req_accept && apb4.pwrite && !s_write_error) begin
        unique case (apb4.paddr[11:0])
          `APB4_SDIO__HOST_CTRL: begin
            if (apb4.pstrb[0]) begin
              s_host_ctrl_q[0] <= apb4.pwdata[0];
              s_host_ctrl_q[2] <= apb4.pwdata[2];
              if (apb4.pwdata[1]) begin
                host_abort_o <= 1'b1;
              end
            end
          end
          `APB4_SDIO__CLOCK_CTRL: begin
            if (apb4.pstrb[0]) s_clock_en_q <= apb4.pwdata[0];
            if (apb4.pstrb[1]) s_half_period_q[7:0] <= apb4.pwdata[15:8];
            if (apb4.pstrb[2]) s_half_period_q[15:8] <= apb4.pwdata[23:16];
          end
          `APB4_SDIO__BUS_CTRL: if (apb4.pstrb[0]) s_bus_width_q <= apb4.pwdata[1:0];
          `APB4_SDIO__TIMEOUT_CMD: s_timeout_cmd_q <= apb4.pwdata;
          `APB4_SDIO__TIMEOUT_DATA: s_timeout_data_q <= apb4.pwdata;
          `APB4_SDIO__TIMEOUT_BUSY: s_timeout_busy_q <= apb4.pwdata;
          `APB4_SDIO__CMD_ARG: s_cmd_arg_q <= apb4.pwdata;
          `APB4_SDIO__CMD_CFG: begin
            if (apb4.pstrb[0]) s_cmd_index_q <= apb4.pwdata[5:0];
            if (apb4.pstrb[1]) s_cmd_cfg_q <= apb4.pwdata[13:8];
          end
          `APB4_SDIO__CMD_START: cmd_start_o <= 1'b1;
          `APB4_SDIO__BLOCK_SIZE: s_block_size_q <= apb4.pwdata[15:0];
          `APB4_SDIO__BLOCK_COUNT: s_block_count_q <= apb4.pwdata[15:0];
          `APB4_SDIO__DATA_CFG: if (apb4.pstrb[0]) s_data_cfg_q <= apb4.pwdata[6:0];
          `APB4_SDIO__DATA_START: data_start_o <= 1'b1;
          `APB4_SDIO__PIO_DATA: begin
            pio_wvalid_o <= 1'b1;
            pio_wdata_o  <= apb4.pwdata;
            pio_wstrb_o  <= apb4.pstrb;
          end
          `APB4_SDIO__DESC_BASE: s_desc_base_q <= apb4.pwdata;
          `APB4_SDIO__DESC_COUNT: s_desc_count_q <= apb4.pwdata[15:0];
          `APB4_SDIO__DMA_CTRL: begin
            dma_start_o <= apb4.pwdata[0];
            dma_abort_o <= apb4.pwdata[1];
            if (apb4.pwdata[0]) begin
              data_start_o <= 1'b1;
            end
          end
          `APB4_SDIO__IRQ_ENABLE: if (apb4.pstrb[0]) s_irq_en_q <= apb4.pwdata[7:0];
          `APB4_SDIO__IRQ_STATUS: s_irq_stat_q <= (s_irq_stat_q & ~apb4.pwdata[7:0]) | irq_event_i;
          `APB4_SDIO__IRQ_TEST:
          s_irq_stat_q <= ((s_irq_stat_q & ~irq_event_i) | irq_event_i) | apb4.pwdata[7:0];
          `APB4_SDIO__ERROR_STATUS: s_err_stat_q <= (s_err_stat_q & ~apb4.pwdata) | error_status_i;
          default: begin
          end
        endcase
      end
    end
  end

endmodule
