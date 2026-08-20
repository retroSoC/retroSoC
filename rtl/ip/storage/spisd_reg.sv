// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// See LICENSE for the complete license text.

`timescale 1ns / 1ps

`include "spisd_define.svh"

module spisd_reg (
    // verilog_format: off -- preserve the reviewed APB/control/status port groups
    input  logic                           clk_i,
    input  logic                           rst_n_i,
    input  logic                           busy_i,
    input  logic [31:0]                    status_i,
    input  logic [31:0]                    clock_actual_i,
    input  logic [31:0]                    cmd_status_i,
    input  logic [39:0]                    response_i,
    input  logic [31:0]                    data_status_i,
    input  logic [31:0]                    fifo_status_i,
    input  logic [31:0]                    dma_status_i,
    input  logic [31:0]                    current_desc_i,
    input  logic [31:0]                    bytes_done_i,
    input  logic [31:0]                    dma_error_addr_i,
    input  logic [31:0]                    dma_error_i,
    input  logic [31:0]                    error_status_i,
    input  logic [5:0]                     last_cmd_i,
    input  logic [31:0]                    crc_error_count_i,
    input  logic [31:0]                    timeout_count_i,
    input  logic [31:0]                    axi_error_count_i,
    input  logic [31:0]                    stall_count_i,
    input  logic [6:0]                     irq_event_i,
    input  logic [31:0]                    pio_rdata_i,
    input  logic                           pio_valid_i,
    input  logic                           pio_write_ready_i,
    output logic                           pio_read_consume_o,
    output logic                           pio_wvalid_o,
    output logic [31:0]                    pio_wdata_o,
    output logic [3:0]                     pio_wstrb_o,
    output logic                           host_enable_o,
    output logic                           clock_enable_o,
    output logic                           clock_train_o,
    output logic [15:0]                    half_period_o,
    output logic [31:0]                    timeout_cmd_o,
    output logic [31:0]                    timeout_data_o,
    output logic [31:0]                    timeout_busy_o,
    output logic [5:0]                     cmd_index_o,
    output logic [31:0]                    cmd_arg_o,
    output spisd_pkg::spisd_resp_type_e    cmd_resp_type_o,
    output logic                           cmd_stuff_byte_o,
    output logic                           cmd_data_present_o,
    output logic                           cmd_auto_stop_o,
    output logic                           cmd_start_o,
    output logic [15:0]                    block_size_o,
    output logic [15:0]                    block_count_o,
    output logic                           data_direction_o,
    output logic                           data_dma_enable_o,
    output logic                           data_multi_block_o,
    output logic                           data_crc_check_o,
    output logic [31:0]                    desc_base_o,
    output logic [15:0]                    desc_count_o,
    output logic                           dma_start_o,
    output logic                           dma_abort_o,
    output logic                           host_abort_o,
    output logic                           irq_o,
    apb4_if.slave                          apb4
    // verilog_format: on
);
  localparam logic [31:0] IpId = 32'h5350_4953;
  localparam logic [31:0] IpVersion = 32'h0001_0000;
  localparam logic [31:0] Capability = 32'h0000_00FF;
  localparam logic [31:0] ClockReset = 32'h0000_5A00;
  localparam logic [31:0] CmdTimeout = 32'd72_000_000;
  localparam logic [31:0] DataTimeout = 32'd72_000_000;
  localparam logic [31:0] BusyTimeout = 32'd360_000_000;

  logic [31:0] s_host_ctrl_d, s_host_ctrl_q;
  logic [31:0] s_clock_ctrl_d, s_clock_ctrl_q;
  logic [31:0] s_timeout_cmd_d, s_timeout_cmd_q;
  logic [31:0] s_timeout_data_d, s_timeout_data_q;
  logic [31:0] s_timeout_busy_d, s_timeout_busy_q;
  logic [31:0] s_cmd_arg_d, s_cmd_arg_q;
  logic [31:0] s_cmd_cfg_d, s_cmd_cfg_q;
  logic [31:0] s_block_size_d, s_block_size_q;
  logic [31:0] s_block_count_d, s_block_count_q;
  logic [31:0] s_data_cfg_d, s_data_cfg_q;
  logic [31:0] s_desc_base_d, s_desc_base_q;
  logic [31:0] s_desc_count_d, s_desc_count_q;
  logic [31:0] s_irq_stat_d, s_irq_stat_q;
  logic [31:0] s_irq_en_d, s_irq_en_q;
  logic [31:0] s_err_stat_d, s_err_stat_q;
  logic s_setup_busy_d, s_setup_busy_q;

  logic s_apb_access, s_apb_accept, s_apb_write, s_apb_read;
  logic s_pio_write_sel, s_pio_read_sel;
  logic s_offset_valid, s_write_allowed, s_busy_write_allowed, s_busy_fields_allowed;
  logic [11:0] s_offset;
  logic [31:0] s_write_data;
  logic [31:0] s_irq_clear, s_irq_test, s_err_clear;

  function automatic logic [31:0] apply_wstrb(input logic [31:0] prior_i, input logic [31:0] data_i,
                                              input logic [3:0] strb_i);
    logic [31:0] value;
    begin
      value = prior_i;
      for (int lane = 0; lane < 4; lane++) begin
        if (strb_i[lane]) value[lane*8+:8] = data_i[lane*8+:8];
      end
      return value;
    end
  endfunction

  function automatic logic offset_valid(input logic [11:0] offset_i);
    unique case (offset_i)
      `APB4_SPISD__IP_ID,
      `APB4_SPISD__IP_VERSION,
      `APB4_SPISD__CAPABILITY,
      `APB4_SPISD__HOST_CTRL,
      `APB4_SPISD__CLOCK_CTRL,
      `APB4_SPISD__CLOCK_ACTUAL,
      `APB4_SPISD__TIMEOUT_CMD,
      `APB4_SPISD__TIMEOUT_DATA,
      `APB4_SPISD__TIMEOUT_BUSY,
      `APB4_SPISD__STATUS,
      `APB4_SPISD__CMD_ARG,
      `APB4_SPISD__CMD_CFG,
      `APB4_SPISD__CMD_START,
      `APB4_SPISD__CMD_STATUS,
      `APB4_SPISD__RESP0,
      `APB4_SPISD__RESP1,
      `APB4_SPISD__BLOCK_SIZE,
      `APB4_SPISD__BLOCK_COUNT,
      `APB4_SPISD__DATA_CFG,
      `APB4_SPISD__PIO_DATA,
      `APB4_SPISD__DATA_STATUS,
      `APB4_SPISD__FIFO_STATUS,
      `APB4_SPISD__DESC_BASE,
      `APB4_SPISD__DESC_COUNT,
      `APB4_SPISD__DMA_CTRL,
      `APB4_SPISD__DMA_STATUS,
      `APB4_SPISD__CURRENT_DESC,
      `APB4_SPISD__BYTES_DONE,
      `APB4_SPISD__DMA_ERROR_ADDR,
      `APB4_SPISD__DMA_ERROR,
      `APB4_SPISD__IRQ_STATUS,
      `APB4_SPISD__IRQ_ENABLE,
      `APB4_SPISD__IRQ_TEST,
      `APB4_SPISD__ERROR_STATUS,
      `APB4_SPISD__LAST_CMD,
      `APB4_SPISD__CRC_ERROR_COUNT,
      `APB4_SPISD__TIMEOUT_COUNT,
      `APB4_SPISD__AXI_ERROR_COUNT,
      `APB4_SPISD__STALL_COUNT:
      return 1'b1;
      default: return 1'b0;
    endcase
  endfunction

  function automatic logic write_allowed(input logic [11:0] offset_i);
    unique case (offset_i)
      `APB4_SPISD__HOST_CTRL,
      `APB4_SPISD__CLOCK_CTRL,
      `APB4_SPISD__TIMEOUT_CMD,
      `APB4_SPISD__TIMEOUT_DATA,
      `APB4_SPISD__TIMEOUT_BUSY,
      `APB4_SPISD__CMD_ARG,
      `APB4_SPISD__CMD_CFG,
      `APB4_SPISD__CMD_START,
      `APB4_SPISD__BLOCK_SIZE,
      `APB4_SPISD__BLOCK_COUNT,
      `APB4_SPISD__DATA_CFG,
      `APB4_SPISD__PIO_DATA,
      `APB4_SPISD__DESC_BASE,
      `APB4_SPISD__DESC_COUNT,
      `APB4_SPISD__DMA_CTRL,
      `APB4_SPISD__IRQ_STATUS,
      `APB4_SPISD__IRQ_ENABLE,
      `APB4_SPISD__IRQ_TEST,
      `APB4_SPISD__ERROR_STATUS:
      return 1'b1;
      default: return 1'b0;
    endcase
  endfunction

  function automatic logic busy_write_allowed(input logic [11:0] offset_i);
    unique case (offset_i)
      `APB4_SPISD__HOST_CTRL,
      `APB4_SPISD__PIO_DATA,
      `APB4_SPISD__DMA_CTRL,
      `APB4_SPISD__IRQ_STATUS,
      `APB4_SPISD__IRQ_ENABLE,
      `APB4_SPISD__IRQ_TEST,
      `APB4_SPISD__ERROR_STATUS:
      return 1'b1;
      default: return 1'b0;
    endcase
  endfunction

  assign s_offset             = apb4.paddr[11:0];
  assign s_apb_access         = apb4.psel && apb4.penable;
  assign s_apb_write          = s_apb_access && apb4.pwrite;
  assign s_apb_read           = s_apb_access && !apb4.pwrite;
  assign s_pio_write_sel      = s_apb_write && (s_offset == `APB4_SPISD__PIO_DATA);
  assign s_pio_read_sel       = s_apb_read && (s_offset == `APB4_SPISD__PIO_DATA);
  assign s_offset_valid       = offset_valid(s_offset);
  assign s_write_allowed      = write_allowed(s_offset);
  assign s_busy_write_allowed = busy_write_allowed(s_offset);
  always_comb begin
    unique case (s_offset)
      `APB4_SPISD__HOST_CTRL:
      s_busy_fields_allowed = (s_write_data[31:3] == 29'd0) &&
                              (!apb4.pstrb[0] ||
                               (apb4.pwdata[`APB4_SPISD__HOST_CTRL_ENABLE] ==
                                s_host_ctrl_q[`APB4_SPISD__HOST_CTRL_ENABLE]));
      `APB4_SPISD__DMA_CTRL:
      s_busy_fields_allowed = (s_write_data & ~(32'd1 << `APB4_SPISD__DMA_CTRL_ABORT)) == 32'd0;
      default: s_busy_fields_allowed = 1'b1;
    endcase
  end
  assign apb4.pready = s_pio_write_sel ? pio_write_ready_i : (s_pio_read_sel ? pio_valid_i : 1'b1);
  assign s_apb_accept = s_apb_access && apb4.pready;
  assign apb4.pslverr = s_apb_accept &&
                        (!s_offset_valid || (apb4.pwrite && !s_write_allowed) ||
                         (apb4.pwrite && s_setup_busy_q &&
                          (!s_busy_write_allowed || !s_busy_fields_allowed)));
  assign s_write_data = apply_wstrb(32'd0, apb4.pwdata, apb4.pstrb);

  assign pio_read_consume_o = s_pio_read_sel && s_apb_accept;
  assign pio_wvalid_o = s_pio_write_sel && s_apb_accept && !apb4.pslverr;
  assign pio_wdata_o = apb4.pwdata;
  assign pio_wstrb_o = apb4.pstrb;
  assign cmd_start_o = s_apb_write && s_apb_accept && !apb4.pslverr &&
                       (s_offset == `APB4_SPISD__CMD_START) && s_write_data[0];
  assign dma_start_o = s_apb_write && s_apb_accept && !apb4.pslverr &&
                       (s_offset == `APB4_SPISD__DMA_CTRL) &&
                       s_write_data[`APB4_SPISD__DMA_CTRL_START];
  assign dma_abort_o = s_apb_write && s_apb_accept && !apb4.pslverr &&
                       (s_offset == `APB4_SPISD__DMA_CTRL) &&
                       s_write_data[`APB4_SPISD__DMA_CTRL_ABORT];
  assign host_abort_o = s_apb_write && s_apb_accept && !apb4.pslverr &&
                        (s_offset == `APB4_SPISD__HOST_CTRL) &&
                        s_write_data[`APB4_SPISD__HOST_CTRL_ABORT];

  assign host_enable_o = s_host_ctrl_q[`APB4_SPISD__HOST_CTRL_ENABLE];
  assign clock_enable_o = s_clock_ctrl_q[`APB4_SPISD__CLOCK_CTRL_ENABLE];
  assign clock_train_o = s_apb_write && s_apb_accept && !apb4.pslverr &&
                         (s_offset == `APB4_SPISD__CLOCK_CTRL) &&
                         s_write_data[`APB4_SPISD__CLOCK_CTRL_TRAIN];
  assign half_period_o = s_clock_ctrl_q[23:8];
  assign timeout_cmd_o = s_timeout_cmd_q;
  assign timeout_data_o = s_timeout_data_q;
  assign timeout_busy_o = s_timeout_busy_q;
  assign cmd_index_o = s_cmd_cfg_q[5:0];
  assign cmd_arg_o = s_cmd_arg_q;
  assign cmd_resp_type_o = spisd_pkg::spisd_resp_type_e'(s_cmd_cfg_q[10:8]);
  assign cmd_stuff_byte_o = s_cmd_cfg_q[`APB4_SPISD__CMD_CFG_STUFF_BYTE];
  assign cmd_data_present_o = s_cmd_cfg_q[`APB4_SPISD__CMD_CFG_DATA_PRESENT];
  assign cmd_auto_stop_o = s_cmd_cfg_q[`APB4_SPISD__CMD_CFG_AUTO_STOP];
  assign block_size_o = s_block_size_q[15:0];
  assign block_count_o = s_block_count_q[15:0];
  assign data_direction_o = s_data_cfg_q[`APB4_SPISD__DATA_CFG_DIRECTION];
  assign data_dma_enable_o = s_data_cfg_q[`APB4_SPISD__DATA_CFG_DMA];
  assign data_multi_block_o = s_data_cfg_q[`APB4_SPISD__DATA_CFG_MULTI_BLOCK];
  assign data_crc_check_o = s_data_cfg_q[`APB4_SPISD__DATA_CFG_CRC_CHECK];
  assign desc_base_o = s_desc_base_q;
  assign desc_count_o = s_desc_count_q[15:0];
  assign irq_o = s_host_ctrl_q[`APB4_SPISD__HOST_CTRL_IRQ] && (|(s_irq_stat_q & s_irq_en_q));

  assign s_irq_clear = (s_apb_write && s_apb_accept &&
                        (s_offset == `APB4_SPISD__IRQ_STATUS)) ? s_write_data : 32'd0;
  assign s_irq_test = (s_apb_write && s_apb_accept &&
                       (s_offset == `APB4_SPISD__IRQ_TEST)) ? s_write_data : 32'd0;
  assign s_err_clear = (s_apb_write && s_apb_accept &&
                          (s_offset == `APB4_SPISD__ERROR_STATUS)) ? s_write_data : 32'd0;

  always_comb begin
    s_setup_busy_d = s_setup_busy_q;
    if (apb4.psel && !apb4.penable) begin
      s_setup_busy_d = busy_i;
    end else if (!apb4.psel) begin
      s_setup_busy_d = 1'b0;
    end
  end

  always_comb begin
    s_host_ctrl_d    = s_host_ctrl_q;
    s_clock_ctrl_d   = s_clock_ctrl_q;
    s_timeout_cmd_d  = s_timeout_cmd_q;
    s_timeout_data_d = s_timeout_data_q;
    s_timeout_busy_d = s_timeout_busy_q;
    s_cmd_arg_d      = s_cmd_arg_q;
    s_cmd_cfg_d      = s_cmd_cfg_q;
    s_block_size_d   = s_block_size_q;
    s_block_count_d  = s_block_count_q;
    s_data_cfg_d     = s_data_cfg_q;
    s_desc_base_d    = s_desc_base_q;
    s_desc_count_d   = s_desc_count_q;
    s_irq_en_d       = s_irq_en_q;
    if (s_apb_write && s_apb_accept && !apb4.pslverr) begin
      unique case (s_offset)
        `APB4_SPISD__HOST_CTRL: begin
          s_host_ctrl_d = apply_wstrb(s_host_ctrl_q, apb4.pwdata, apb4.pstrb);
          s_host_ctrl_d[`APB4_SPISD__HOST_CTRL_ABORT] = 1'b0;
        end
        `APB4_SPISD__CLOCK_CTRL: begin
          s_clock_ctrl_d = apply_wstrb(s_clock_ctrl_q, apb4.pwdata, apb4.pstrb);
          s_clock_ctrl_d[`APB4_SPISD__CLOCK_CTRL_TRAIN] = 1'b0;
        end
        `APB4_SPISD__TIMEOUT_CMD:
        s_timeout_cmd_d = apply_wstrb(s_timeout_cmd_q, apb4.pwdata, apb4.pstrb);
        `APB4_SPISD__TIMEOUT_DATA:
        s_timeout_data_d = apply_wstrb(s_timeout_data_q, apb4.pwdata, apb4.pstrb);
        `APB4_SPISD__TIMEOUT_BUSY:
        s_timeout_busy_d = apply_wstrb(s_timeout_busy_q, apb4.pwdata, apb4.pstrb);
        `APB4_SPISD__CMD_ARG: s_cmd_arg_d = apply_wstrb(s_cmd_arg_q, apb4.pwdata, apb4.pstrb);
        `APB4_SPISD__CMD_CFG: s_cmd_cfg_d = apply_wstrb(s_cmd_cfg_q, apb4.pwdata, apb4.pstrb);
        `APB4_SPISD__BLOCK_SIZE:
        s_block_size_d = apply_wstrb(s_block_size_q, apb4.pwdata, apb4.pstrb);
        `APB4_SPISD__BLOCK_COUNT:
        s_block_count_d = apply_wstrb(s_block_count_q, apb4.pwdata, apb4.pstrb);
        `APB4_SPISD__DATA_CFG: s_data_cfg_d = apply_wstrb(s_data_cfg_q, apb4.pwdata, apb4.pstrb);
        `APB4_SPISD__DESC_BASE: s_desc_base_d = apply_wstrb(s_desc_base_q, apb4.pwdata, apb4.pstrb);
        `APB4_SPISD__DESC_COUNT:
        s_desc_count_d = apply_wstrb(s_desc_count_q, apb4.pwdata, apb4.pstrb);
        `APB4_SPISD__IRQ_ENABLE: s_irq_en_d = apply_wstrb(s_irq_en_q, apb4.pwdata, apb4.pstrb);
        default: begin
        end
      endcase
    end
  end

  always_comb begin
    s_irq_stat_d = (s_irq_stat_q & ~s_irq_clear) | {25'd0, irq_event_i} | s_irq_test;
    s_err_stat_d = (s_err_stat_q & ~s_err_clear) | error_status_i;
  end

  always_comb begin
    unique case (s_offset)
      `APB4_SPISD__IP_ID:           apb4.prdata = IpId;
      `APB4_SPISD__IP_VERSION:      apb4.prdata = IpVersion;
      `APB4_SPISD__CAPABILITY:      apb4.prdata = Capability;
      `APB4_SPISD__HOST_CTRL:       apb4.prdata = s_host_ctrl_q;
      `APB4_SPISD__CLOCK_CTRL:      apb4.prdata = s_clock_ctrl_q;
      `APB4_SPISD__CLOCK_ACTUAL:    apb4.prdata = clock_actual_i;
      `APB4_SPISD__TIMEOUT_CMD:     apb4.prdata = s_timeout_cmd_q;
      `APB4_SPISD__TIMEOUT_DATA:    apb4.prdata = s_timeout_data_q;
      `APB4_SPISD__TIMEOUT_BUSY:    apb4.prdata = s_timeout_busy_q;
      `APB4_SPISD__STATUS:          apb4.prdata = status_i;
      `APB4_SPISD__CMD_ARG:         apb4.prdata = s_cmd_arg_q;
      `APB4_SPISD__CMD_CFG:         apb4.prdata = s_cmd_cfg_q;
      `APB4_SPISD__CMD_STATUS:      apb4.prdata = cmd_status_i;
      `APB4_SPISD__RESP0:           apb4.prdata = response_i[31:0];
      `APB4_SPISD__RESP1:           apb4.prdata = {24'd0, response_i[39:32]};
      `APB4_SPISD__BLOCK_SIZE:      apb4.prdata = s_block_size_q;
      `APB4_SPISD__BLOCK_COUNT:     apb4.prdata = s_block_count_q;
      `APB4_SPISD__DATA_CFG:        apb4.prdata = s_data_cfg_q;
      `APB4_SPISD__PIO_DATA:        apb4.prdata = pio_rdata_i;
      `APB4_SPISD__DATA_STATUS:     apb4.prdata = data_status_i;
      `APB4_SPISD__FIFO_STATUS:     apb4.prdata = fifo_status_i;
      `APB4_SPISD__DESC_BASE:       apb4.prdata = s_desc_base_q;
      `APB4_SPISD__DESC_COUNT:      apb4.prdata = s_desc_count_q;
      `APB4_SPISD__DMA_STATUS:      apb4.prdata = dma_status_i;
      `APB4_SPISD__CURRENT_DESC:    apb4.prdata = current_desc_i;
      `APB4_SPISD__BYTES_DONE:      apb4.prdata = bytes_done_i;
      `APB4_SPISD__DMA_ERROR_ADDR:  apb4.prdata = dma_error_addr_i;
      `APB4_SPISD__DMA_ERROR:       apb4.prdata = dma_error_i;
      `APB4_SPISD__IRQ_STATUS:      apb4.prdata = s_irq_stat_q;
      `APB4_SPISD__IRQ_ENABLE:      apb4.prdata = s_irq_en_q;
      `APB4_SPISD__ERROR_STATUS:    apb4.prdata = s_err_stat_q;
      `APB4_SPISD__LAST_CMD:        apb4.prdata = {26'd0, last_cmd_i};
      `APB4_SPISD__CRC_ERROR_COUNT: apb4.prdata = crc_error_count_i;
      `APB4_SPISD__TIMEOUT_COUNT:   apb4.prdata = timeout_count_i;
      `APB4_SPISD__AXI_ERROR_COUNT: apb4.prdata = axi_error_count_i;
      `APB4_SPISD__STALL_COUNT:     apb4.prdata = stall_count_i;
      default:                      apb4.prdata = 32'd0;
    endcase
  end

  dffr #(
      .DATA_WIDTH(32)
  ) u_host_ctrl_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_host_ctrl_d),
      .dat_o  (s_host_ctrl_q)
  );
  dffr u_setup_busy_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_setup_busy_d),
      .dat_o  (s_setup_busy_q)
  );
  dffrc #(
      .DATA_WIDTH(32),
      .RESET_VAL (ClockReset)
  ) u_clock_ctrl_dffrc (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_clock_ctrl_d),
      .dat_o  (s_clock_ctrl_q)
  );
  dffrc #(
      .DATA_WIDTH(32),
      .RESET_VAL (CmdTimeout)
  ) u_timeout_cmd_dffrc (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_timeout_cmd_d),
      .dat_o  (s_timeout_cmd_q)
  );
  dffrc #(
      .DATA_WIDTH(32),
      .RESET_VAL (DataTimeout)
  ) u_timeout_data_dffrc (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_timeout_data_d),
      .dat_o  (s_timeout_data_q)
  );
  dffrc #(
      .DATA_WIDTH(32),
      .RESET_VAL (BusyTimeout)
  ) u_timeout_busy_dffrc (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_timeout_busy_d),
      .dat_o  (s_timeout_busy_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_cmd_arg_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_cmd_arg_d),
      .dat_o  (s_cmd_arg_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_cmd_cfg_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_cmd_cfg_d),
      .dat_o  (s_cmd_cfg_q)
  );
  dffrc #(
      .DATA_WIDTH(32),
      .RESET_VAL (32'd512)
  ) u_block_size_dffrc (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_block_size_d),
      .dat_o  (s_block_size_q)
  );
  dffrc #(
      .DATA_WIDTH(32),
      .RESET_VAL (32'd1)
  ) u_block_count_dffrc (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_block_count_d),
      .dat_o  (s_block_count_q)
  );
  dffrc #(
      .DATA_WIDTH(32),
      .RESET_VAL (32'h0000_0040)
  ) u_data_cfg_dffrc (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_data_cfg_d),
      .dat_o  (s_data_cfg_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_desc_base_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_desc_base_d),
      .dat_o  (s_desc_base_q)
  );
  dffrc #(
      .DATA_WIDTH(32),
      .RESET_VAL (32'd1)
  ) u_desc_count_dffrc (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_desc_count_d),
      .dat_o  (s_desc_count_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_irq_status_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_irq_stat_d),
      .dat_o  (s_irq_stat_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_irq_enable_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_irq_en_d),
      .dat_o  (s_irq_en_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_error_status_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_err_stat_d),
      .dat_o  (s_err_stat_q)
  );
endmodule
