// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.

`include "ribp_i2c_define.svh"

module i2c_reg #(
    parameter int CMD_FIFO_DEPTH     = 16,
    parameter int RX_FIFO_DEPTH      = 16,
    parameter int CMD_FIFO_LOG_DEPTH = $clog2(CMD_FIFO_DEPTH),
    parameter int RX_FIFO_LOG_DEPTH  = $clog2(RX_FIFO_DEPTH)
) (
    // verilog_format: off
    input  logic        clk_i,
    input  logic        rst_n_i,
    ribp_if.slave       ribp,
    output logic        enable_o,
    output logic [15:0] scl_low_cycles_o,
    output logic [15:0] scl_high_cycles_o,
    output logic [15:0] start_hold_cycles_o,
    output logic [15:0] start_setup_cycles_o,
    output logic [15:0] data_hold_cycles_o,
    output logic [15:0] data_setup_cycles_o,
    output logic [15:0] stop_setup_cycles_o,
    output logic [15:0] bus_free_cycles_o,
    output logic [ 3:0] scl_filter_cycles_o,
    output logic [ 3:0] sda_filter_cycles_o,
    output logic [23:0] stretch_timeout_o,
    output logic [23:0] bus_idle_timeout_o,
    output logic [23:0] command_timeout_o,
    output logic [ 9:0] target_addr_o,
    output logic        ten_bit_o,
    output logic        abort_o,
    output logic        recover_o,
    output logic        cmd_valid_o,
    output logic [11:0] cmd_data_o,
    input  logic        cmd_pop_i,
    input  logic        core_cmd_flush_i,
    input  logic        rx_push_i,
    input  logic [ 7:0] rx_data_i,
    output logic        rx_full_o,
    input  logic        busy_i,
    input  logic        recovery_active_i,
    input  logic        scl_i,
    input  logic        sda_i,
    input  logic        done_event_i,
    input  logic        addr_nack_event_i,
    input  logic        data_nack_event_i,
    input  logic        arb_lost_event_i,
    input  logic        stretch_timeout_event_i,
    input  logic        bus_timeout_event_i,
    input  logic        command_timeout_event_i,
    input  logic        command_error_event_i,
    input  logic        rx_overflow_event_i,
    input  logic        aborted_event_i,
    input  logic        recovery_done_event_i,
    input  logic        recovery_failed_event_i,
    output logic        dma_tx_stall_o,
    output logic        dma_rx_stall_o,
    output logic        irq_o
    // verilog_format: on
);

  localparam logic [31:0] IP_VERSION = 32'h0002_0000;
  localparam logic [7:0] CMD_DEPTH_INFO = 8'(CMD_FIFO_DEPTH);
  localparam logic [7:0] RX_DEPTH_INFO = 8'(RX_FIFO_DEPTH);
  localparam logic [31:0] CAPABILITY = {9'd0, 7'h7F, RX_DEPTH_INFO, CMD_DEPTH_INFO};
  localparam logic [31:0] CMD_WATERMARK_RESET = (CMD_FIFO_DEPTH > 4) ? 32'd4 : CMD_FIFO_DEPTH - 1;
  localparam logic [31:0] RX_WATERMARK_RESET = (RX_FIFO_DEPTH > 8) ? 32'd8 : RX_FIFO_DEPTH;

  logic s_req;
  logic s_write;
  logic s_req_accept;
  logic s_access_error;
  logic s_ribp_ready_d, s_ribp_ready_q;
  logic s_ribp_resp_err_d, s_ribp_resp_err_q;
  logic [31:0] s_ribp_rdata_d, s_ribp_rdata_q;

  logic s_enable_en;
  logic s_enable_d, s_enable_q;
  logic s_scl_timing_en;
  logic [31:0] s_scl_timing_d, s_scl_timing_q;
  logic s_start_timing_en;
  logic [31:0] s_start_timing_d, s_start_timing_q;
  logic s_data_timing_en;
  logic [31:0] s_data_timing_d, s_data_timing_q;
  logic s_stop_timing_en;
  logic [31:0] s_stop_timing_d, s_stop_timing_q;
  logic s_filter_en;
  logic [11:0] s_filter_d, s_filter_q;
  logic s_stretch_timeout_en;
  logic [23:0] s_stretch_timeout_d, s_stretch_timeout_q;
  logic s_bus_idle_timeout_en;
  logic [23:0] s_bus_idle_timeout_d, s_bus_idle_timeout_q;
  logic s_command_timeout_en;
  logic [23:0] s_command_timeout_d, s_command_timeout_q;
  logic s_target_addr_en;
  logic [10:0] s_target_addr_d, s_target_addr_q;
  logic s_cmd_watermark_en;
  logic [7:0] s_cmd_watermark_d, s_cmd_watermark_q;
  logic s_rx_watermark_en;
  logic [7:0] s_rx_watermark_d, s_rx_watermark_q;
  logic s_intr_enable_en;
  logic [7:0] s_intr_enable_d, s_intr_enable_q;

  logic                        s_cmd_push;
  logic                        s_cmd_flush_cmd;
  logic                        s_cmd_empty;
  logic                        s_cmd_full;
  logic [                11:0] s_cmd_pop_data;
  logic [CMD_FIFO_LOG_DEPTH:0] s_cmd_count;
  logic                        s_rx_pop;
  logic                        s_rx_flush_cmd;
  logic                        s_rx_empty;
  logic                        s_rx_full;
  logic [                 7:0] s_rx_pop_data;
  logic [ RX_FIFO_LOG_DEPTH:0] s_rx_count;

  logic [10:0] s_error_status_d, s_error_status_q;
  logic [7:0] s_intr_state_d, s_intr_state_q;
  logic [10:0] s_error_clear;
  logic [ 7:0] s_intr_clear;
  logic [ 7:0] s_intr_test;
  logic        s_config_error_event;
  logic        s_sw_command_error_event;
  logic        s_timeout_event;
  logic        s_error_event;
  logic        s_cmd_watermark_active;
  logic        s_rx_watermark_active;
  logic        s_tx_dma_req;
  logic        s_rx_dma_req;
  logic        s_config_valid;
  logic [31:0] s_status;
  logic [31:0] s_fifo_level;
  logic [31:0] s_line_state;
  logic [31:0] s_merge_value;

  function automatic logic [31:0] merge_wstrb(input logic [31:0] current, input logic [31:0] value,
                                              input logic [3:0] strobe);
    logic   [31:0] merged;
    integer        byte_index;
    begin
      merged = current;
      for (byte_index = 0; byte_index < 4; byte_index = byte_index + 1) begin
        if (strobe[byte_index]) begin
          merged[byte_index*8+:8] = value[byte_index*8+:8];
        end
      end
      return merged;
    end
  endfunction

  initial begin
    if ((CMD_FIFO_DEPTH > 255) || (RX_FIFO_DEPTH > 255)) begin
      $fatal(1, "i2c_reg: FIFO depths must fit CAPABILITY fields");
    end
  end

  assign s_req = ribp.valid && !s_ribp_ready_q;
  assign s_write = |ribp.wstrb;
  assign ribp.ready = s_ribp_ready_q;
  assign ribp.resp_err = s_ribp_resp_err_q;
  assign ribp.rdata = s_ribp_rdata_q;
  assign enable_o = s_enable_q;
  assign scl_low_cycles_o = s_scl_timing_q[15:0];
  assign scl_high_cycles_o = s_scl_timing_q[31:16];
  assign start_hold_cycles_o = s_start_timing_q[15:0];
  assign start_setup_cycles_o = s_start_timing_q[31:16];
  assign data_hold_cycles_o = s_data_timing_q[15:0];
  assign data_setup_cycles_o = s_data_timing_q[31:16];
  assign stop_setup_cycles_o = s_stop_timing_q[15:0];
  assign bus_free_cycles_o = s_stop_timing_q[31:16];
  assign scl_filter_cycles_o = s_filter_q[3:0];
  assign sda_filter_cycles_o = s_filter_q[11:8];
  assign stretch_timeout_o = s_stretch_timeout_q;
  assign bus_idle_timeout_o = s_bus_idle_timeout_q;
  assign command_timeout_o = s_command_timeout_q;
  assign target_addr_o = s_target_addr_q[9:0];
  assign ten_bit_o = s_target_addr_q[10];
  assign cmd_valid_o = !s_cmd_empty;
  assign cmd_data_o = s_cmd_pop_data;
  assign rx_full_o = s_rx_full;

  assign s_config_valid = (s_scl_timing_q[15:0] != 16'd0) &&
                          (s_scl_timing_q[31:16] != 16'd0) &&
                          (s_start_timing_q[15:0] != 16'd0) &&
                          (s_start_timing_q[31:16] != 16'd0) &&
                          (s_data_timing_q[15:0] < s_scl_timing_q[15:0]) &&
                          (s_data_timing_q[31:16] != 16'd0) &&
                          (s_data_timing_q[31:16] <= s_scl_timing_q[15:0]) &&
                          (s_stop_timing_q[15:0] != 16'd0) &&
                          (s_stop_timing_q[31:16] != 16'd0) &&
                          (s_target_addr_q[10] || (s_target_addr_q[9:7] == 3'd0));
  assign s_cmd_watermark_active = s_enable_q && (8'(s_cmd_count) <= s_cmd_watermark_q);
  assign s_rx_watermark_active = s_enable_q && (8'(s_rx_count) >= s_rx_watermark_q);
  assign s_tx_dma_req = s_enable_q && s_config_valid && !s_cmd_full;
  assign s_rx_dma_req = s_enable_q && !s_rx_empty;
  assign dma_tx_stall_o = !s_tx_dma_req;
  assign dma_rx_stall_o = !s_rx_dma_req;
  assign irq_o = |(s_intr_state_q & s_intr_enable_q);

  always_comb begin
    s_status                              = '0;
    s_status[`I2C_STATUS_ENABLE]          = s_enable_q;
    s_status[`I2C_STATUS_BUSY]            = busy_i;
    s_status[`I2C_STATUS_BUS_BUSY]        = !(scl_i && sda_i);
    s_status[`I2C_STATUS_CMD_EMPTY]       = s_cmd_empty;
    s_status[`I2C_STATUS_CMD_FULL]        = s_cmd_full;
    s_status[`I2C_STATUS_RX_EMPTY]        = s_rx_empty;
    s_status[`I2C_STATUS_RX_FULL]         = s_rx_full;
    s_status[`I2C_STATUS_CONFIG_VALID]    = s_config_valid;
    s_status[`I2C_STATUS_RECOVERY_ACTIVE] = recovery_active_i;
    s_status[`I2C_STATUS_SCL]             = scl_i;
    s_status[`I2C_STATUS_SDA]             = sda_i;
    s_status[`I2C_STATUS_TX_DMA_REQ]      = s_tx_dma_req;
    s_status[`I2C_STATUS_RX_DMA_REQ]      = s_rx_dma_req;
    s_fifo_level                          = '0;
    s_fifo_level[7:0]                     = 8'(s_cmd_count);
    s_fifo_level[23:16]                   = 8'(s_rx_count);
    s_line_state                          = '0;
    s_line_state[`I2C_LINE_SCL]           = scl_i;
    s_line_state[`I2C_LINE_SDA]           = sda_i;
    s_line_state[`I2C_LINE_BUS_FREE]      = scl_i && sda_i;
  end

  always_comb begin
    s_req_accept             = s_req;
    s_access_error           = 1'b0;
    s_enable_en              = 1'b0;
    s_scl_timing_en          = 1'b0;
    s_start_timing_en        = 1'b0;
    s_data_timing_en         = 1'b0;
    s_stop_timing_en         = 1'b0;
    s_filter_en              = 1'b0;
    s_stretch_timeout_en     = 1'b0;
    s_bus_idle_timeout_en    = 1'b0;
    s_command_timeout_en     = 1'b0;
    s_target_addr_en         = 1'b0;
    s_cmd_watermark_en       = 1'b0;
    s_rx_watermark_en        = 1'b0;
    s_intr_enable_en         = 1'b0;
    s_enable_d               = s_enable_q;
    s_scl_timing_d           = s_scl_timing_q;
    s_start_timing_d         = s_start_timing_q;
    s_data_timing_d          = s_data_timing_q;
    s_stop_timing_d          = s_stop_timing_q;
    s_filter_d               = s_filter_q;
    s_stretch_timeout_d      = s_stretch_timeout_q;
    s_bus_idle_timeout_d     = s_bus_idle_timeout_q;
    s_command_timeout_d      = s_command_timeout_q;
    s_target_addr_d          = s_target_addr_q;
    s_cmd_watermark_d        = s_cmd_watermark_q;
    s_rx_watermark_d         = s_rx_watermark_q;
    s_intr_enable_d          = s_intr_enable_q;
    s_cmd_push               = 1'b0;
    s_rx_pop                 = 1'b0;
    s_cmd_flush_cmd          = 1'b0;
    s_rx_flush_cmd           = 1'b0;
    abort_o                  = 1'b0;
    recover_o                = 1'b0;
    s_error_clear            = '0;
    s_intr_clear             = '0;
    s_intr_test              = '0;
    s_config_error_event     = 1'b0;
    s_sw_command_error_event = 1'b0;
    s_ribp_rdata_d           = '0;
    s_merge_value            = '0;

    if (s_req) begin
      if ((ribp.addr[11:8] != 4'd0) || (ribp.addr[1:0] != 2'b00)) begin
        s_access_error = 1'b1;
      end else if (s_write) begin
        unique case (ribp.addr[7:0])
          `RIBP_I2C_CTRL: begin
            s_merge_value = merge_wstrb({31'd0, s_enable_q}, ribp.wdata, ribp.wstrb);
            if ((s_merge_value[31:1] != 31'd0) ||
                (s_merge_value[0] && !s_config_valid) ||
                (!s_merge_value[0] && (busy_i || recovery_active_i))) begin
              s_access_error       = 1'b1;
              s_config_error_event = 1'b1;
            end else begin
              s_enable_en = 1'b1;
              s_enable_d  = s_merge_value[0];
            end
          end
          `RIBP_I2C_SCL_TIMING: begin
            if (s_enable_q || busy_i || recovery_active_i) begin
              s_access_error       = 1'b1;
              s_config_error_event = 1'b1;
            end else begin
              s_scl_timing_en = 1'b1;
              s_scl_timing_d  = merge_wstrb(s_scl_timing_q, ribp.wdata, ribp.wstrb);
            end
          end
          `RIBP_I2C_START_TIMING: begin
            if (s_enable_q || busy_i || recovery_active_i) begin
              s_access_error       = 1'b1;
              s_config_error_event = 1'b1;
            end else begin
              s_start_timing_en = 1'b1;
              s_start_timing_d  = merge_wstrb(s_start_timing_q, ribp.wdata, ribp.wstrb);
            end
          end
          `RIBP_I2C_DATA_TIMING: begin
            if (s_enable_q || busy_i || recovery_active_i) begin
              s_access_error       = 1'b1;
              s_config_error_event = 1'b1;
            end else begin
              s_data_timing_en = 1'b1;
              s_data_timing_d  = merge_wstrb(s_data_timing_q, ribp.wdata, ribp.wstrb);
            end
          end
          `RIBP_I2C_STOP_TIMING: begin
            if (s_enable_q || busy_i || recovery_active_i) begin
              s_access_error       = 1'b1;
              s_config_error_event = 1'b1;
            end else begin
              s_stop_timing_en = 1'b1;
              s_stop_timing_d  = merge_wstrb(s_stop_timing_q, ribp.wdata, ribp.wstrb);
            end
          end
          `RIBP_I2C_FILTER: begin
            s_merge_value = merge_wstrb({20'd0, s_filter_q}, ribp.wdata, ribp.wstrb);
            if (s_enable_q || busy_i || recovery_active_i ||
                (s_merge_value[31:12] != 20'd0) || (s_merge_value[7:4] != 4'd0)) begin
              s_access_error       = 1'b1;
              s_config_error_event = 1'b1;
            end else begin
              s_filter_en = 1'b1;
              s_filter_d  = s_merge_value[11:0];
            end
          end
          `RIBP_I2C_STRETCH_TIMEOUT: begin
            s_merge_value = merge_wstrb({8'd0, s_stretch_timeout_q}, ribp.wdata, ribp.wstrb);
            if (s_enable_q || busy_i || recovery_active_i || (s_merge_value[31:24] != 8'd0)) begin
              s_access_error       = 1'b1;
              s_config_error_event = 1'b1;
            end else begin
              s_stretch_timeout_en = 1'b1;
              s_stretch_timeout_d  = s_merge_value[23:0];
            end
          end
          `RIBP_I2C_BUS_IDLE_TIMEOUT: begin
            s_merge_value = merge_wstrb({8'd0, s_bus_idle_timeout_q}, ribp.wdata, ribp.wstrb);
            if (s_enable_q || busy_i || recovery_active_i || (s_merge_value[31:24] != 8'd0)) begin
              s_access_error       = 1'b1;
              s_config_error_event = 1'b1;
            end else begin
              s_bus_idle_timeout_en = 1'b1;
              s_bus_idle_timeout_d  = s_merge_value[23:0];
            end
          end
          `RIBP_I2C_COMMAND_TIMEOUT: begin
            s_merge_value = merge_wstrb({8'd0, s_command_timeout_q}, ribp.wdata, ribp.wstrb);
            if (s_enable_q || busy_i || recovery_active_i || (s_merge_value[31:24] != 8'd0)) begin
              s_access_error       = 1'b1;
              s_config_error_event = 1'b1;
            end else begin
              s_command_timeout_en = 1'b1;
              s_command_timeout_d  = s_merge_value[23:0];
            end
          end
          `RIBP_I2C_TARGET_ADDR: begin
            s_merge_value = merge_wstrb({21'd0, s_target_addr_q}, ribp.wdata, ribp.wstrb);
            if (busy_i || recovery_active_i || !s_cmd_empty ||
                (s_merge_value[31:11] != 21'd0) ||
                (!s_merge_value[10] && (s_merge_value[9:7] != 3'd0))) begin
              s_access_error       = 1'b1;
              s_config_error_event = 1'b1;
            end else begin
              s_target_addr_en = 1'b1;
              s_target_addr_d  = s_merge_value[10:0];
            end
          end
          `RIBP_I2C_DATA_CMD: begin
            if ((ribp.wstrb != 4'hF) || (ribp.wdata[31:12] != 20'd0) ||
                (!ribp.wdata[`I2C_DATA_CMD_READ] &&
                 ribp.wdata[`I2C_DATA_CMD_NACK_LAST]) ||
                (ribp.wdata[`I2C_DATA_CMD_READ] && ribp.wdata[`I2C_DATA_CMD_STOP] &&
                 !ribp.wdata[`I2C_DATA_CMD_NACK_LAST])) begin
              s_access_error           = 1'b1;
              s_sw_command_error_event = 1'b1;
            end else if (s_cmd_full && s_enable_q && s_config_valid) begin
              s_req_accept = 1'b0;
            end else if (s_cmd_full) begin
              s_access_error           = 1'b1;
              s_sw_command_error_event = 1'b1;
            end else begin
              s_cmd_push = 1'b1;
            end
          end
          `RIBP_I2C_COMMAND: begin
            if (!ribp.wstrb[0] || (ribp.wdata[31:4] != 28'd0) || (ribp.wdata[3:0] == 4'd0)) begin
              s_access_error           = 1'b1;
              s_sw_command_error_event = 1'b1;
            end else if (ribp.wdata[`I2C_COMMAND_ABORT]) begin
              if ((ribp.wdata[3:0] != 4'b0001) || (!busy_i && !recovery_active_i)) begin
                s_access_error           = 1'b1;
                s_sw_command_error_event = 1'b1;
              end else begin
                abort_o = 1'b1;
              end
            end else if (ribp.wdata[`I2C_COMMAND_RECOVER]) begin
              if ((ribp.wdata[3:0] != 4'b0010) || !s_enable_q || !s_config_valid ||
                  busy_i || recovery_active_i || !s_cmd_empty) begin
                s_access_error           = 1'b1;
                s_sw_command_error_event = 1'b1;
              end else begin
                recover_o = 1'b1;
              end
            end else if (busy_i || recovery_active_i || (ribp.wdata[1:0] != 2'd0)) begin
              s_access_error           = 1'b1;
              s_sw_command_error_event = 1'b1;
            end else begin
              s_cmd_flush_cmd = ribp.wdata[`I2C_COMMAND_CMD_FLUSH];
              s_rx_flush_cmd  = ribp.wdata[`I2C_COMMAND_RX_FLUSH];
            end
          end
          `RIBP_I2C_CMD_WATERMARK: begin
            s_merge_value = merge_wstrb({24'd0, s_cmd_watermark_q}, ribp.wdata, ribp.wstrb);
            if ((s_merge_value[31:8] != 24'd0) || (s_merge_value[7:0] >= CMD_DEPTH_INFO)) begin
              s_access_error           = 1'b1;
              s_sw_command_error_event = 1'b1;
            end else begin
              s_cmd_watermark_en = 1'b1;
              s_cmd_watermark_d  = s_merge_value[7:0];
            end
          end
          `RIBP_I2C_RX_WATERMARK: begin
            s_merge_value = merge_wstrb({24'd0, s_rx_watermark_q}, ribp.wdata, ribp.wstrb);
            if ((s_merge_value[31:8] != 24'd0) || (s_merge_value[7:0] == 8'd0) ||
                (s_merge_value[7:0] > RX_DEPTH_INFO)) begin
              s_access_error           = 1'b1;
              s_sw_command_error_event = 1'b1;
            end else begin
              s_rx_watermark_en = 1'b1;
              s_rx_watermark_d  = s_merge_value[7:0];
            end
          end
          `RIBP_I2C_ERROR_STATUS: begin
            if (!ribp.wstrb[0] || (ribp.wdata[31:11] != 21'd0)) begin
              s_access_error = 1'b1;
            end else begin
              s_error_clear = ribp.wdata[10:0];
            end
          end
          `RIBP_I2C_INTR_STATE: begin
            if (!ribp.wstrb[0] || (ribp.wdata[31:8] != 24'd0)) begin
              s_access_error = 1'b1;
            end else begin
              s_intr_clear = ribp.wdata[7:0];
            end
          end
          `RIBP_I2C_INTR_ENABLE: begin
            s_merge_value = merge_wstrb({24'd0, s_intr_enable_q}, ribp.wdata, ribp.wstrb);
            if (s_merge_value[31:8] != 24'd0) begin
              s_access_error = 1'b1;
            end else begin
              s_intr_enable_en = 1'b1;
              s_intr_enable_d  = s_merge_value[7:0];
            end
          end
          `RIBP_I2C_INTR_TEST: begin
            if (!ribp.wstrb[0] || (ribp.wdata[31:8] != 24'd0)) begin
              s_access_error = 1'b1;
            end else begin
              s_intr_test = ribp.wdata[7:0];
            end
          end
          default: s_access_error = 1'b1;
        endcase
      end else begin
        unique case (ribp.addr[7:0])
          `RIBP_I2C_CTRL:             s_ribp_rdata_d = {31'd0, s_enable_q};
          `RIBP_I2C_SCL_TIMING:       s_ribp_rdata_d = s_scl_timing_q;
          `RIBP_I2C_START_TIMING:     s_ribp_rdata_d = s_start_timing_q;
          `RIBP_I2C_DATA_TIMING:      s_ribp_rdata_d = s_data_timing_q;
          `RIBP_I2C_STOP_TIMING:      s_ribp_rdata_d = s_stop_timing_q;
          `RIBP_I2C_FILTER:           s_ribp_rdata_d = {20'd0, s_filter_q};
          `RIBP_I2C_STRETCH_TIMEOUT:  s_ribp_rdata_d = {8'd0, s_stretch_timeout_q};
          `RIBP_I2C_BUS_IDLE_TIMEOUT: s_ribp_rdata_d = {8'd0, s_bus_idle_timeout_q};
          `RIBP_I2C_COMMAND_TIMEOUT:  s_ribp_rdata_d = {8'd0, s_command_timeout_q};
          `RIBP_I2C_TARGET_ADDR:      s_ribp_rdata_d = {21'd0, s_target_addr_q};
          `RIBP_I2C_RXDATA: begin
            if (s_rx_empty) begin
              s_access_error           = 1'b1;
              s_sw_command_error_event = 1'b1;
            end else begin
              s_ribp_rdata_d = {24'd0, s_rx_pop_data};
              s_rx_pop       = 1'b1;
            end
          end
          `RIBP_I2C_STATUS:           s_ribp_rdata_d = s_status;
          `RIBP_I2C_FIFO_LEVEL:       s_ribp_rdata_d = s_fifo_level;
          `RIBP_I2C_CMD_WATERMARK:    s_ribp_rdata_d = {24'd0, s_cmd_watermark_q};
          `RIBP_I2C_RX_WATERMARK:     s_ribp_rdata_d = {24'd0, s_rx_watermark_q};
          `RIBP_I2C_ERROR_STATUS:     s_ribp_rdata_d = {21'd0, s_error_status_q};
          `RIBP_I2C_INTR_STATE:       s_ribp_rdata_d = {24'd0, s_intr_state_q};
          `RIBP_I2C_INTR_ENABLE:      s_ribp_rdata_d = {24'd0, s_intr_enable_q};
          `RIBP_I2C_INTR_STATUS:      s_ribp_rdata_d = {24'd0, (s_intr_state_q & s_intr_enable_q)};
          `RIBP_I2C_LINE_STATE:       s_ribp_rdata_d = s_line_state;
          `RIBP_I2C_IP_VERSION:       s_ribp_rdata_d = IP_VERSION;
          `RIBP_I2C_CAPABILITY:       s_ribp_rdata_d = CAPABILITY;
          default: begin
            s_access_error = 1'b1;
            s_ribp_rdata_d = '0;
          end
        endcase
      end
    end
  end

  assign s_ribp_ready_d    = s_req_accept;
  assign s_ribp_resp_err_d = s_access_error;

  dffr #(1) u_ribp_ready_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_ribp_ready_d),
      .dat_o  (s_ribp_ready_q)
  );
  dffer #(1) u_ribp_resp_err_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_req_accept),
      .dat_i  (s_ribp_resp_err_d),
      .dat_o  (s_ribp_resp_err_q)
  );
  dffer #(32) u_ribp_rdata_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_req_accept),
      .dat_i  (s_ribp_rdata_d),
      .dat_o  (s_ribp_rdata_q)
  );

  dffer #(1) u_enable_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_enable_en),
      .dat_i  (s_enable_d),
      .dat_o  (s_enable_q)
  );
  dffer #(32) u_scl_timing_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_scl_timing_en),
      .dat_i  (s_scl_timing_d),
      .dat_o  (s_scl_timing_q)
  );
  dffer #(32) u_start_timing_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_start_timing_en),
      .dat_i  (s_start_timing_d),
      .dat_o  (s_start_timing_q)
  );
  dffer #(32) u_data_timing_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_data_timing_en),
      .dat_i  (s_data_timing_d),
      .dat_o  (s_data_timing_q)
  );
  dffer #(32) u_stop_timing_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_stop_timing_en),
      .dat_i  (s_stop_timing_d),
      .dat_o  (s_stop_timing_q)
  );
  dfferc #(
      .DATA_WIDTH(12),
      .RESET_VAL (12'h202)
  ) u_filter_dfferc (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_filter_en),
      .dat_i  (s_filter_d),
      .dat_o  (s_filter_q)
  );
  dffer #(24) u_stretch_timeout_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_stretch_timeout_en),
      .dat_i  (s_stretch_timeout_d),
      .dat_o  (s_stretch_timeout_q)
  );
  dffer #(24) u_bus_idle_timeout_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_bus_idle_timeout_en),
      .dat_i  (s_bus_idle_timeout_d),
      .dat_o  (s_bus_idle_timeout_q)
  );
  dffer #(24) u_command_timeout_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_command_timeout_en),
      .dat_i  (s_command_timeout_d),
      .dat_o  (s_command_timeout_q)
  );
  dffer #(11) u_target_addr_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_target_addr_en),
      .dat_i  (s_target_addr_d),
      .dat_o  (s_target_addr_q)
  );
  dfferc #(
      .DATA_WIDTH(8),
      .RESET_VAL (8'(CMD_WATERMARK_RESET))
  ) u_cmd_watermark_dfferc (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_cmd_watermark_en),
      .dat_i  (s_cmd_watermark_d),
      .dat_o  (s_cmd_watermark_q)
  );
  dfferc #(
      .DATA_WIDTH(8),
      .RESET_VAL (8'(RX_WATERMARK_RESET))
  ) u_rx_watermark_dfferc (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_rx_watermark_en),
      .dat_i  (s_rx_watermark_d),
      .dat_o  (s_rx_watermark_q)
  );
  dffer #(8) u_intr_enable_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_intr_enable_en),
      .dat_i  (s_intr_enable_d),
      .dat_o  (s_intr_enable_q)
  );

  fifo #(
      .DATA_WIDTH      (12),
      .BUFFER_DEPTH    (CMD_FIFO_DEPTH),
      .LOG_BUFFER_DEPTH(CMD_FIFO_LOG_DEPTH)
  ) u_cmd_fifo (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .flush_i(s_cmd_flush_cmd || core_cmd_flush_i),
      .push_i (s_cmd_push),
      .full_o (s_cmd_full),
      .dat_i  (ribp.wdata[11:0]),
      .pop_i  (cmd_pop_i),
      .empty_o(s_cmd_empty),
      .dat_o  (s_cmd_pop_data),
      .cnt_o  (s_cmd_count)
  );

  fifo #(
      .DATA_WIDTH      (8),
      .BUFFER_DEPTH    (RX_FIFO_DEPTH),
      .LOG_BUFFER_DEPTH(RX_FIFO_LOG_DEPTH)
  ) u_rx_fifo (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .flush_i(s_rx_flush_cmd),
      .push_i (rx_push_i && !s_rx_full),
      .full_o (s_rx_full),
      .dat_i  (rx_data_i),
      .pop_i  (s_rx_pop),
      .empty_o(s_rx_empty),
      .dat_o  (s_rx_pop_data),
      .cnt_o  (s_rx_count)
  );

  assign s_timeout_event = stretch_timeout_event_i || bus_timeout_event_i ||
                           command_timeout_event_i;
  assign s_error_event = addr_nack_event_i || data_nack_event_i || arb_lost_event_i ||
                         s_timeout_event || command_error_event_i ||
                         s_sw_command_error_event || rx_overflow_event_i ||
                         s_config_error_event || aborted_event_i || recovery_failed_event_i;

  always_comb begin
    s_error_status_d = s_error_status_q & ~s_error_clear;
    if (addr_nack_event_i) s_error_status_d[`I2C_ERROR_ADDR_NACK] = 1'b1;
    if (data_nack_event_i) s_error_status_d[`I2C_ERROR_DATA_NACK] = 1'b1;
    if (arb_lost_event_i) s_error_status_d[`I2C_ERROR_ARB_LOST] = 1'b1;
    if (stretch_timeout_event_i) s_error_status_d[`I2C_ERROR_STRETCH_TIMEOUT] = 1'b1;
    if (bus_timeout_event_i) s_error_status_d[`I2C_ERROR_BUS_TIMEOUT] = 1'b1;
    if (command_timeout_event_i) s_error_status_d[`I2C_ERROR_COMMAND_TIMEOUT] = 1'b1;
    if (command_error_event_i || s_sw_command_error_event)
      s_error_status_d[`I2C_ERROR_COMMAND] = 1'b1;
    if (rx_overflow_event_i) s_error_status_d[`I2C_ERROR_RX_OVERFLOW] = 1'b1;
    if (s_config_error_event) s_error_status_d[`I2C_ERROR_CONFIG] = 1'b1;
    if (aborted_event_i) s_error_status_d[`I2C_ERROR_ABORTED] = 1'b1;
    if (recovery_failed_event_i) s_error_status_d[`I2C_ERROR_RECOVERY_FAILED] = 1'b1;
  end
  dffr #(11) u_error_status_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_error_status_d),
      .dat_o  (s_error_status_q)
  );

  always_comb begin
    s_intr_state_d = (s_intr_state_q & ~s_intr_clear) | s_intr_test;
    if (done_event_i) s_intr_state_d[`I2C_INTR_DONE] = 1'b1;
    if (s_cmd_watermark_active) s_intr_state_d[`I2C_INTR_CMD_WATERMARK] = 1'b1;
    if (s_rx_watermark_active) s_intr_state_d[`I2C_INTR_RX_WATERMARK] = 1'b1;
    if (addr_nack_event_i || data_nack_event_i) s_intr_state_d[`I2C_INTR_NACK] = 1'b1;
    if (arb_lost_event_i) s_intr_state_d[`I2C_INTR_ARB_LOST] = 1'b1;
    if (s_timeout_event) s_intr_state_d[`I2C_INTR_TIMEOUT] = 1'b1;
    if (s_error_event) s_intr_state_d[`I2C_INTR_ERROR] = 1'b1;
    if (recovery_done_event_i) s_intr_state_d[`I2C_INTR_RECOVERY_DONE] = 1'b1;
  end
  dffr #(8) u_intr_state_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_intr_state_d),
      .dat_o  (s_intr_state_q)
  );

endmodule
