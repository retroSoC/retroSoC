// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.

`include "ribp_uart_define.svh"

module uart_reg #(
    parameter int TX_FIFO_DEPTH     = 64,
    parameter int RX_FIFO_DEPTH     = 64,
    parameter int TX_FIFO_LOG_DEPTH = $clog2(TX_FIFO_DEPTH),
    parameter int RX_FIFO_LOG_DEPTH = $clog2(RX_FIFO_DEPTH)
) (
    // verilog_format: off
    input  logic        clk_i,
    input  logic        rst_n_i,
    ribp_if.slave       ribp,
    output logic [23:0] baud_int_o,
    output logic [ 7:0] baud_frac_o,
    output logic [ 1:0] data_bits_o,
    output logic        stop2_o,
    output logic [ 1:0] parity_o,
    output logic        tx_enable_o,
    output logic        rx_enable_o,
    output logic        loopback_o,
    output logic        break_o,
    output logic        auto_cts_enable_o,
    output logic        auto_rts_enable_o,
    output logic [ 6:0] rts_assert_level_o,
    output logic [ 6:0] rts_deassert_level_o,
    output logic        tx_data_valid_o,
    output logic [ 7:0] tx_data_o,
    output logic [ 6:0] rx_level_o,
    input  logic        tx_data_pop_i,
    input  logic        tx_busy_i,
    input  logic        tx_done_i,
    input  logic        rx_active_i,
    input  logic        rx_data_valid_i,
    input  logic [11:0] rx_data_i,
    input  logic        bit_tick_i,
    input  logic        cts_asserted_i,
    input  logic        rts_asserted_i,
    input  logic        tx_flow_blocked_i,
    input  logic        cts_change_i,
    output logic        dma_tx_stall_o,
    output logic        dma_rx_stall_o,
    output logic        irq_o
    // verilog_format: on
);

  localparam logic [31:0] TX_WATERMARK_RESET = 32'd16;
  localparam logic [31:0] RX_WATERMARK_RESET = 32'd32;
  localparam logic [31:0] RX_TIMEOUT_RESET = 32'd32;
  localparam logic [31:0] LINE_CTRL_RESET = 32'd3;
  localparam logic [31:0] RTS_ASSERT_LEVEL_RESET = 32'd32;
  localparam logic [31:0] RTS_DEASSERT_LEVEL_RESET = 32'd48;
  localparam logic [31:0] IP_VERSION = 32'h0003_0000;
  localparam logic [31:0] CAPABILITY = 32'h03FF_4040;

  logic s_req;
  logic s_write;
  logic s_req_accept;
  logic s_access_err;
  logic s_ribp_ready_d, s_ribp_ready_q;
  logic s_ribp_resp_err_d, s_ribp_resp_err_q;
  logic [31:0] s_ribp_rdata_d, s_ribp_rdata_q;

  logic s_baud_int_en;
  logic [23:0] s_baud_int_d, s_baud_int_q;
  logic s_baud_frac_en;
  logic [7:0] s_baud_frac_d, s_baud_frac_q;
  logic s_line_ctrl_en;
  logic [4:0] s_line_ctrl_d, s_line_ctrl_q;
  logic s_ctrl_en;
  logic [3:0] s_ctrl_d, s_ctrl_q;
  logic s_tx_watermark_en;
  logic [6:0] s_tx_watermark_d, s_tx_watermark_q;
  logic s_rx_watermark_en;
  logic [6:0] s_rx_watermark_d, s_rx_watermark_q;
  logic s_rx_timeout_en;
  logic [15:0] s_rx_timeout_d, s_rx_timeout_q;
  logic s_intr_en_en;
  logic [6:0] s_intr_en_d, s_intr_en_q;
  logic s_dma_ctrl_en;
  logic [1:0] s_dma_ctrl_d, s_dma_ctrl_q;
  logic s_flow_ctrl_en;
  logic [1:0] s_flow_ctrl_d, s_flow_ctrl_q;
  logic s_rts_watermark_en;
  logic [6:0] s_rts_assert_level_d, s_rts_assert_level_q;
  logic [6:0] s_rts_deassert_level_d, s_rts_deassert_level_q;

  logic                       s_tx_flush;
  logic                       s_tx_push;
  logic                       s_tx_empty;
  logic                       s_tx_full;
  logic [                7:0] s_tx_pop_data;
  logic [TX_FIFO_LOG_DEPTH:0] s_tx_count;
  logic                       s_rx_flush;
  logic                       s_rx_push;
  logic                       s_rx_pop;
  logic                       s_rx_empty;
  logic                       s_rx_full;
  logic [               11:0] s_rx_pop_data;
  logic [RX_FIFO_LOG_DEPTH:0] s_rx_count;

  logic [6:0] s_err_stat_d, s_err_stat_q;
  logic [6:0] s_intr_state_d, s_intr_state_q;
  logic [6:0] s_err_clear;
  logic [6:0] s_intr_clear;
  logic [6:0] s_intr_test;
  logic       s_config_err_event;
  logic       s_cmd_err_event;
  logic       s_overrun_event;
  logic       s_rx_err_event;
  logic       s_rx_timeout_event;
  logic [15:0] s_rx_timeout_count_d, s_rx_timeout_count_q;

  logic [31:0] s_stat;
  logic [31:0] s_fifo_level;
  logic [31:0] s_merge_value;
  logic        s_config_valid;
  logic        s_tx_dma_req;
  logic        s_rx_dma_req;
  logic        s_tx_watermark_active;
  logic        s_rx_watermark_active;

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
    if ((TX_FIFO_DEPTH != 64) || (RX_FIFO_DEPTH != 64)) begin
      $fatal(1, "uart_reg: UART V3 requires 64-entry FIFOs");
    end
  end

  assign s_req = ribp.valid && !s_ribp_ready_q;
  assign s_write = |ribp.wstrb;
  assign ribp.ready = s_ribp_ready_q;
  assign ribp.resp_err = s_ribp_resp_err_q;
  assign ribp.rdata = s_ribp_rdata_q;

  assign baud_int_o = s_baud_int_q;
  assign baud_frac_o = s_baud_frac_q;
  assign data_bits_o = s_line_ctrl_q[1:0];
  assign stop2_o = s_line_ctrl_q[`UART_LINE_STOP2];
  assign parity_o = s_line_ctrl_q[4:3];
  assign tx_enable_o = s_ctrl_q[`UART_CTRL_TX_ENABLE];
  assign rx_enable_o = s_ctrl_q[`UART_CTRL_RX_ENABLE];
  assign loopback_o = s_ctrl_q[`UART_CTRL_LOOPBACK];
  assign break_o = s_ctrl_q[`UART_CTRL_TX_BREAK];
  assign auto_cts_enable_o = s_flow_ctrl_q[`UART_FLOW_AUTO_CTS_ENABLE];
  assign auto_rts_enable_o = s_flow_ctrl_q[`UART_FLOW_AUTO_RTS_ENABLE];
  assign rts_assert_level_o = s_rts_assert_level_q;
  assign rts_deassert_level_o = s_rts_deassert_level_q;
  assign tx_data_valid_o = !s_tx_empty;
  assign tx_data_o = s_tx_pop_data;
  assign rx_level_o = 7'(s_rx_count);

  assign s_config_valid = (s_baud_int_q >= 24'd16) && (s_line_ctrl_q[4:3] != 2'd3);
  assign s_tx_dma_req = s_dma_ctrl_q[`UART_DMA_TX_ENABLE] && tx_enable_o &&
                        s_config_valid && !s_tx_full;
  assign s_rx_dma_req = s_dma_ctrl_q[`UART_DMA_RX_ENABLE] && rx_enable_o && !s_rx_empty;
  assign dma_tx_stall_o = !s_tx_dma_req;
  assign dma_rx_stall_o = !s_rx_dma_req;
  assign s_tx_watermark_active = tx_enable_o && (s_tx_count <= s_tx_watermark_q);
  assign s_rx_watermark_active = rx_enable_o && (s_rx_count >= s_rx_watermark_q);
  assign irq_o = |(s_intr_state_q & s_intr_en_q);

  always_comb begin
    s_stat                               = '0;
    s_stat[`UART_STATUS_TX_ENABLED]      = tx_enable_o;
    s_stat[`UART_STATUS_RX_ENABLED]      = rx_enable_o;
    s_stat[`UART_STATUS_TX_BUSY]         = tx_busy_i;
    s_stat[`UART_STATUS_RX_ACTIVE]       = rx_active_i;
    s_stat[`UART_STATUS_TX_EMPTY]        = s_tx_empty;
    s_stat[`UART_STATUS_TX_FULL]         = s_tx_full;
    s_stat[`UART_STATUS_RX_EMPTY]        = s_rx_empty;
    s_stat[`UART_STATUS_RX_FULL]         = s_rx_full;
    s_stat[`UART_STATUS_CONFIG_VALID]    = s_config_valid;
    s_stat[`UART_STATUS_BREAK_ACTIVE]    = break_o;
    s_stat[`UART_STATUS_TX_DMA_REQ]      = s_tx_dma_req;
    s_stat[`UART_STATUS_RX_DMA_REQ]      = s_rx_dma_req;
    s_stat[`UART_STATUS_CTS_ASSERTED]    = cts_asserted_i;
    s_stat[`UART_STATUS_RTS_ASSERTED]    = rts_asserted_i;
    s_stat[`UART_STATUS_TX_FLOW_BLOCKED] = tx_flow_blocked_i;
    s_fifo_level                         = '0;
    s_fifo_level[6:0]                    = 7'(s_tx_count);
    s_fifo_level[22:16]                  = 7'(s_rx_count);
  end

  always_comb begin
    s_req_accept           = s_req;
    s_access_err           = 1'b0;
    s_baud_int_en          = 1'b0;
    s_baud_frac_en         = 1'b0;
    s_line_ctrl_en         = 1'b0;
    s_ctrl_en              = 1'b0;
    s_tx_watermark_en      = 1'b0;
    s_rx_watermark_en      = 1'b0;
    s_rx_timeout_en        = 1'b0;
    s_intr_en_en           = 1'b0;
    s_dma_ctrl_en          = 1'b0;
    s_flow_ctrl_en         = 1'b0;
    s_rts_watermark_en     = 1'b0;
    s_baud_int_d           = s_baud_int_q;
    s_baud_frac_d          = s_baud_frac_q;
    s_line_ctrl_d          = s_line_ctrl_q;
    s_ctrl_d               = s_ctrl_q;
    s_tx_watermark_d       = s_tx_watermark_q;
    s_rx_watermark_d       = s_rx_watermark_q;
    s_rx_timeout_d         = s_rx_timeout_q;
    s_intr_en_d            = s_intr_en_q;
    s_dma_ctrl_d           = s_dma_ctrl_q;
    s_flow_ctrl_d          = s_flow_ctrl_q;
    s_rts_assert_level_d   = s_rts_assert_level_q;
    s_rts_deassert_level_d = s_rts_deassert_level_q;
    s_tx_flush             = 1'b0;
    s_rx_flush             = 1'b0;
    s_tx_push              = 1'b0;
    s_rx_pop               = 1'b0;
    s_err_clear            = '0;
    s_intr_clear           = '0;
    s_intr_test            = '0;
    s_config_err_event     = 1'b0;
    s_cmd_err_event        = 1'b0;
    s_ribp_rdata_d         = '0;
    s_merge_value          = '0;

    if (s_req) begin
      if ((ribp.addr[11:8] != 4'd0) || (ribp.addr[1:0] != 2'b00)) begin
        s_access_err = 1'b1;
      end else if (s_write) begin
        unique case (ribp.addr[7:0])
          `RIBP_UART_BAUD_INT: begin
            s_merge_value = merge_wstrb({8'd0, s_baud_int_q}, ribp.wdata, ribp.wstrb);
            if (tx_enable_o || rx_enable_o || tx_busy_i || rx_active_i ||
                (s_merge_value[31:24] != 8'd0) || (s_merge_value[23:0] < 24'd16)) begin
              s_access_err       = 1'b1;
              s_config_err_event = 1'b1;
            end else begin
              s_baud_int_en = 1'b1;
              s_baud_int_d  = s_merge_value[23:0];
            end
          end
          `RIBP_UART_BAUD_FRAC: begin
            s_merge_value = merge_wstrb({24'd0, s_baud_frac_q}, ribp.wdata, ribp.wstrb);
            if (tx_enable_o || rx_enable_o || tx_busy_i || rx_active_i ||
                (s_merge_value[31:8] != 24'd0)) begin
              s_access_err       = 1'b1;
              s_config_err_event = 1'b1;
            end else begin
              s_baud_frac_en = 1'b1;
              s_baud_frac_d  = s_merge_value[7:0];
            end
          end
          `RIBP_UART_LINE_CTRL: begin
            s_merge_value = merge_wstrb({27'd0, s_line_ctrl_q}, ribp.wdata, ribp.wstrb);
            if (tx_enable_o || rx_enable_o || tx_busy_i || rx_active_i ||
                (s_merge_value[31:5] != 27'd0) || (s_merge_value[4:3] == 2'd3)) begin
              s_access_err       = 1'b1;
              s_config_err_event = 1'b1;
            end else begin
              s_line_ctrl_en = 1'b1;
              s_line_ctrl_d  = s_merge_value[4:0];
            end
          end
          `RIBP_UART_CTRL: begin
            s_merge_value = merge_wstrb({28'd0, s_ctrl_q}, ribp.wdata, ribp.wstrb);
            if ((s_merge_value[31:4] != 28'd0) ||
                ((s_merge_value[1:0] != 2'd0) && !s_config_valid) ||
                (s_merge_value[`UART_CTRL_TX_BREAK] && tx_busy_i) ||
                ((s_merge_value[`UART_CTRL_LOOPBACK] != loopback_o) &&
                 (tx_busy_i || rx_active_i))) begin
              s_access_err       = 1'b1;
              s_config_err_event = 1'b1;
            end else begin
              s_ctrl_en = 1'b1;
              s_ctrl_d  = s_merge_value[3:0];
            end
          end
          `RIBP_UART_TXDATA: begin
            if (!ribp.wstrb[0] ||
                (|(ribp.wdata[31:8] & {{8{ribp.wstrb[3]}}, {8{ribp.wstrb[2]}},
                                        {8{ribp.wstrb[1]}}}))) begin
              s_access_err    = 1'b1;
              s_cmd_err_event = 1'b1;
            end else if (s_tx_full && tx_enable_o && s_config_valid) begin
              s_req_accept = 1'b0;
            end else if (s_tx_full) begin
              s_access_err    = 1'b1;
              s_cmd_err_event = 1'b1;
            end else begin
              s_tx_push = 1'b1;
            end
          end
          `RIBP_UART_FIFO_CTRL: begin
            if (!ribp.wstrb[0] || (ribp.wdata[31:2] != 30'd0) ||
                (ribp.wdata[1:0] == 2'd0) ||
                (ribp.wdata[`UART_FIFO_CTRL_TX_FLUSH] && (tx_enable_o || tx_busy_i)) ||
                (ribp.wdata[`UART_FIFO_CTRL_RX_FLUSH] && (rx_enable_o || rx_active_i))) begin
              s_access_err    = 1'b1;
              s_cmd_err_event = 1'b1;
            end else begin
              s_tx_flush = ribp.wdata[`UART_FIFO_CTRL_TX_FLUSH];
              s_rx_flush = ribp.wdata[`UART_FIFO_CTRL_RX_FLUSH];
            end
          end
          `RIBP_UART_TX_WATERMARK: begin
            s_merge_value = merge_wstrb({25'd0, s_tx_watermark_q}, ribp.wdata, ribp.wstrb);
            if ((s_merge_value[31:7] != 25'd0) || (s_merge_value[6:0] >= 7'(TX_FIFO_DEPTH))) begin
              s_access_err    = 1'b1;
              s_cmd_err_event = 1'b1;
            end else begin
              s_tx_watermark_en = 1'b1;
              s_tx_watermark_d  = s_merge_value[6:0];
            end
          end
          `RIBP_UART_RX_WATERMARK: begin
            s_merge_value = merge_wstrb({25'd0, s_rx_watermark_q}, ribp.wdata, ribp.wstrb);
            if ((s_merge_value[31:7] != 25'd0) || (s_merge_value[6:0] == 7'd0) ||
                (s_merge_value[6:0] > 7'(RX_FIFO_DEPTH))) begin
              s_access_err    = 1'b1;
              s_cmd_err_event = 1'b1;
            end else begin
              s_rx_watermark_en = 1'b1;
              s_rx_watermark_d  = s_merge_value[6:0];
            end
          end
          `RIBP_UART_RX_TIMEOUT_BITS: begin
            s_merge_value = merge_wstrb({16'd0, s_rx_timeout_q}, ribp.wdata, ribp.wstrb);
            if (s_merge_value[31:16] != 16'd0) begin
              s_access_err    = 1'b1;
              s_cmd_err_event = 1'b1;
            end else begin
              s_rx_timeout_en = 1'b1;
              s_rx_timeout_d  = s_merge_value[15:0];
            end
          end
          `RIBP_UART_ERROR_STATUS: begin
            if (!ribp.wstrb[0] || (ribp.wdata[31:7] != 25'd0)) begin
              s_access_err = 1'b1;
            end else begin
              s_err_clear = ribp.wdata[6:0];
            end
          end
          `RIBP_UART_INTR_STATE: begin
            if (!ribp.wstrb[0] || (ribp.wdata[31:7] != 25'd0)) begin
              s_access_err = 1'b1;
            end else begin
              s_intr_clear = ribp.wdata[6:0];
            end
          end
          `RIBP_UART_INTR_ENABLE: begin
            s_merge_value = merge_wstrb({25'd0, s_intr_en_q}, ribp.wdata, ribp.wstrb);
            if (s_merge_value[31:7] != 25'd0) begin
              s_access_err = 1'b1;
            end else begin
              s_intr_en_en = 1'b1;
              s_intr_en_d  = s_merge_value[6:0];
            end
          end
          `RIBP_UART_INTR_TEST: begin
            if (!ribp.wstrb[0] || (ribp.wdata[31:7] != 25'd0)) begin
              s_access_err = 1'b1;
            end else begin
              s_intr_test = ribp.wdata[6:0];
            end
          end
          `RIBP_UART_DMA_CTRL: begin
            s_merge_value = merge_wstrb({30'd0, s_dma_ctrl_q}, ribp.wdata, ribp.wstrb);
            if (s_merge_value[31:2] != 30'd0) begin
              s_access_err    = 1'b1;
              s_cmd_err_event = 1'b1;
            end else begin
              s_dma_ctrl_en = 1'b1;
              s_dma_ctrl_d  = s_merge_value[1:0];
            end
          end
          `RIBP_UART_FLOW_CTRL: begin
            s_merge_value = merge_wstrb({30'd0, s_flow_ctrl_q}, ribp.wdata, ribp.wstrb);
            if (tx_enable_o || rx_enable_o || tx_busy_i || rx_active_i ||
                (s_merge_value[31:2] != 30'd0)) begin
              s_access_err       = 1'b1;
              s_config_err_event = 1'b1;
            end else begin
              s_flow_ctrl_en = 1'b1;
              s_flow_ctrl_d  = s_merge_value[1:0];
            end
          end
          `RIBP_UART_RTS_WATERMARK: begin
            s_merge_value = merge_wstrb({9'd0, s_rts_deassert_level_q, 9'd0, s_rts_assert_level_q},
                                        ribp.wdata, ribp.wstrb);
            if (tx_enable_o || rx_enable_o || tx_busy_i || rx_active_i ||
                (s_merge_value[31:23] != 9'd0) || (s_merge_value[15:7] != 9'd0) ||
                (s_merge_value[22:16] > 7'(RX_FIFO_DEPTH)) ||
                (s_merge_value[6:0] >= s_merge_value[22:16])) begin
              s_access_err       = 1'b1;
              s_config_err_event = 1'b1;
            end else begin
              s_rts_watermark_en     = 1'b1;
              s_rts_assert_level_d   = s_merge_value[6:0];
              s_rts_deassert_level_d = s_merge_value[22:16];
            end
          end
          default: s_access_err = 1'b1;
        endcase
      end else begin
        unique case (ribp.addr[7:0])
          `RIBP_UART_BAUD_INT: s_ribp_rdata_d = {8'd0, s_baud_int_q};
          `RIBP_UART_BAUD_FRAC: s_ribp_rdata_d = {24'd0, s_baud_frac_q};
          `RIBP_UART_LINE_CTRL: s_ribp_rdata_d = {27'd0, s_line_ctrl_q};
          `RIBP_UART_CTRL: s_ribp_rdata_d = {28'd0, s_ctrl_q};
          `RIBP_UART_RXDATA: begin
            if (s_rx_empty) begin
              s_access_err    = 1'b1;
              s_cmd_err_event = 1'b1;
            end else begin
              s_ribp_rdata_d = {20'd0, s_rx_pop_data};
              s_rx_pop       = 1'b1;
            end
          end
          `RIBP_UART_STATUS: s_ribp_rdata_d = s_stat;
          `RIBP_UART_FIFO_LEVEL: s_ribp_rdata_d = s_fifo_level;
          `RIBP_UART_TX_WATERMARK: s_ribp_rdata_d = {25'd0, s_tx_watermark_q};
          `RIBP_UART_RX_WATERMARK: s_ribp_rdata_d = {25'd0, s_rx_watermark_q};
          `RIBP_UART_RX_TIMEOUT_BITS: s_ribp_rdata_d = {16'd0, s_rx_timeout_q};
          `RIBP_UART_ERROR_STATUS: s_ribp_rdata_d = {25'd0, s_err_stat_q};
          `RIBP_UART_INTR_STATE: s_ribp_rdata_d = {25'd0, s_intr_state_q};
          `RIBP_UART_INTR_ENABLE: s_ribp_rdata_d = {25'd0, s_intr_en_q};
          `RIBP_UART_INTR_STATUS: s_ribp_rdata_d = {25'd0, (s_intr_state_q & s_intr_en_q)};
          `RIBP_UART_DMA_CTRL: s_ribp_rdata_d = {30'd0, s_dma_ctrl_q};
          `RIBP_UART_FLOW_CTRL: s_ribp_rdata_d = {30'd0, s_flow_ctrl_q};
          `RIBP_UART_RTS_WATERMARK:
          s_ribp_rdata_d = {9'd0, s_rts_deassert_level_q, 9'd0, s_rts_assert_level_q};
          `RIBP_UART_IP_VERSION: s_ribp_rdata_d = IP_VERSION;
          `RIBP_UART_CAPABILITY: s_ribp_rdata_d = CAPABILITY;
          default: begin
            s_access_err   = 1'b1;
            s_ribp_rdata_d = '0;
          end
        endcase
      end
    end
  end

  assign s_ribp_ready_d    = s_req_accept;
  assign s_ribp_resp_err_d = s_access_err;
  assign s_rx_push         = rx_data_valid_i && !s_rx_full;
  assign s_overrun_event   = rx_data_valid_i && s_rx_full;
  assign s_rx_err_event    = s_rx_push && (|rx_data_i[11:8]);

  dffr #(
      .DATA_WIDTH(1)
  ) u_ribp_ready_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_ribp_ready_d),
      .dat_o  (s_ribp_ready_q)
  );
  dffer #(
      .DATA_WIDTH(1)
  ) u_ribp_resp_err_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_req_accept),
      .dat_i  (s_ribp_resp_err_d),
      .dat_o  (s_ribp_resp_err_q)
  );
  dffer #(
      .DATA_WIDTH(32)
  ) u_ribp_rdata_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_req_accept),
      .dat_i  (s_ribp_rdata_d),
      .dat_o  (s_ribp_rdata_q)
  );

  dffer #(
      .DATA_WIDTH(24)
  ) u_baud_int_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_baud_int_en),
      .dat_i  (s_baud_int_d),
      .dat_o  (s_baud_int_q)
  );
  dffer #(
      .DATA_WIDTH(8)
  ) u_baud_frac_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_baud_frac_en),
      .dat_i  (s_baud_frac_d),
      .dat_o  (s_baud_frac_q)
  );
  dfferc #(
      .DATA_WIDTH(5),
      .RESET_VAL (5'(LINE_CTRL_RESET))
  ) u_line_ctrl_dfferc (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_line_ctrl_en),
      .dat_i  (s_line_ctrl_d),
      .dat_o  (s_line_ctrl_q)
  );
  dffer #(
      .DATA_WIDTH(4)
  ) u_ctrl_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_ctrl_en),
      .dat_i  (s_ctrl_d),
      .dat_o  (s_ctrl_q)
  );
  dfferc #(
      .DATA_WIDTH(7),
      .RESET_VAL (7'(TX_WATERMARK_RESET))
  ) u_tx_watermark_dfferc (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_tx_watermark_en),
      .dat_i  (s_tx_watermark_d),
      .dat_o  (s_tx_watermark_q)
  );
  dfferc #(
      .DATA_WIDTH(7),
      .RESET_VAL (7'(RX_WATERMARK_RESET))
  ) u_rx_watermark_dfferc (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_rx_watermark_en),
      .dat_i  (s_rx_watermark_d),
      .dat_o  (s_rx_watermark_q)
  );
  dfferc #(
      .DATA_WIDTH(16),
      .RESET_VAL (16'(RX_TIMEOUT_RESET))
  ) u_rx_timeout_dfferc (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_rx_timeout_en),
      .dat_i  (s_rx_timeout_d),
      .dat_o  (s_rx_timeout_q)
  );
  dffer #(
      .DATA_WIDTH(7)
  ) u_intr_enable_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_intr_en_en),
      .dat_i  (s_intr_en_d),
      .dat_o  (s_intr_en_q)
  );
  dffer #(
      .DATA_WIDTH(2)
  ) u_dma_ctrl_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_dma_ctrl_en),
      .dat_i  (s_dma_ctrl_d),
      .dat_o  (s_dma_ctrl_q)
  );
  dffer #(
      .DATA_WIDTH(2)
  ) u_flow_ctrl_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_flow_ctrl_en),
      .dat_i  (s_flow_ctrl_d),
      .dat_o  (s_flow_ctrl_q)
  );
  dfferc #(
      .DATA_WIDTH(7),
      .RESET_VAL (7'(RTS_ASSERT_LEVEL_RESET))
  ) u_rts_assert_level_dfferc (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_rts_watermark_en),
      .dat_i  (s_rts_assert_level_d),
      .dat_o  (s_rts_assert_level_q)
  );
  dfferc #(
      .DATA_WIDTH(7),
      .RESET_VAL (7'(RTS_DEASSERT_LEVEL_RESET))
  ) u_rts_deassert_level_dfferc (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_rts_watermark_en),
      .dat_i  (s_rts_deassert_level_d),
      .dat_o  (s_rts_deassert_level_q)
  );

  fifo #(
      .DATA_WIDTH      (8),
      .BUFFER_DEPTH    (TX_FIFO_DEPTH),
      .LOG_BUFFER_DEPTH(TX_FIFO_LOG_DEPTH)
  ) u_tx_fifo (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .flush_i(s_tx_flush),
      .push_i (s_tx_push),
      .full_o (s_tx_full),
      .dat_i  (ribp.wdata[7:0]),
      .pop_i  (tx_data_pop_i),
      .empty_o(s_tx_empty),
      .dat_o  (s_tx_pop_data),
      .cnt_o  (s_tx_count)
  );

  fifo #(
      .DATA_WIDTH      (12),
      .BUFFER_DEPTH    (RX_FIFO_DEPTH),
      .LOG_BUFFER_DEPTH(RX_FIFO_LOG_DEPTH)
  ) u_rx_fifo (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .flush_i(s_rx_flush),
      .push_i (s_rx_push),
      .full_o (s_rx_full),
      .dat_i  (rx_data_i),
      .pop_i  (s_rx_pop),
      .empty_o(s_rx_empty),
      .dat_o  (s_rx_pop_data),
      .cnt_o  (s_rx_count)
  );

  always_comb begin
    s_rx_timeout_count_d = s_rx_timeout_count_q;
    s_rx_timeout_event   = 1'b0;
    if (s_rx_empty || s_rx_push || s_rx_pop || (s_rx_timeout_q == 16'd0)) begin
      s_rx_timeout_count_d = '0;
    end else if (bit_tick_i) begin
      if (s_rx_timeout_count_q >= (s_rx_timeout_q - 1'b1)) begin
        s_rx_timeout_count_d = '0;
        s_rx_timeout_event   = 1'b1;
      end else begin
        s_rx_timeout_count_d = s_rx_timeout_count_q + 1'b1;
      end
    end
  end
  dffr #(
      .DATA_WIDTH(16)
  ) u_rx_timeout_count_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_rx_timeout_count_d),
      .dat_o  (s_rx_timeout_count_q)
  );

  always_comb begin
    s_err_stat_d = s_err_stat_q & ~s_err_clear;
    if (s_overrun_event) s_err_stat_d[`UART_ERROR_OVERRUN] = 1'b1;
    if (s_rx_push && rx_data_i[`UART_RXDATA_PARITY_ERROR]) s_err_stat_d[`UART_ERROR_PARITY] = 1'b1;
    if (s_rx_push && rx_data_i[`UART_RXDATA_FRAME_ERROR]) s_err_stat_d[`UART_ERROR_FRAME] = 1'b1;
    if (s_rx_push && rx_data_i[`UART_RXDATA_BREAK]) s_err_stat_d[`UART_ERROR_BREAK] = 1'b1;
    if (s_rx_push && rx_data_i[`UART_RXDATA_NOISE]) s_err_stat_d[`UART_ERROR_NOISE] = 1'b1;
    if (s_config_err_event) s_err_stat_d[`UART_ERROR_CONFIG] = 1'b1;
    if (s_cmd_err_event) s_err_stat_d[`UART_ERROR_COMMAND] = 1'b1;
  end
  dffr #(
      .DATA_WIDTH(7)
  ) u_error_status_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_err_stat_d),
      .dat_o  (s_err_stat_q)
  );

  always_comb begin
    s_intr_state_d = (s_intr_state_q & ~s_intr_clear) | s_intr_test;
    if (s_rx_watermark_active) s_intr_state_d[`UART_INTR_RX_WATERMARK] = 1'b1;
    if (s_rx_timeout_event) s_intr_state_d[`UART_INTR_RX_TIMEOUT] = 1'b1;
    if (s_tx_watermark_active) s_intr_state_d[`UART_INTR_TX_WATERMARK] = 1'b1;
    if (tx_done_i && s_tx_empty) s_intr_state_d[`UART_INTR_TX_DONE] = 1'b1;
    if (s_rx_err_event || s_overrun_event) s_intr_state_d[`UART_INTR_RX_ERROR] = 1'b1;
    if (s_rx_push && rx_data_i[`UART_RXDATA_BREAK]) s_intr_state_d[`UART_INTR_BREAK] = 1'b1;
    if (cts_change_i) s_intr_state_d[`UART_INTR_CTS_CHANGE] = 1'b1;
  end
  dffr #(
      .DATA_WIDTH(7)
  ) u_intr_state_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_intr_state_d),
      .dat_o  (s_intr_state_q)
  );

`ifndef SYNTHESIS
`ifdef SIMU_VERILATOR
  always_ff @(posedge clk_i) begin
    if (s_tx_push && !loopback_o) begin
      $write("%c", ribp.wdata[7:0]);
    end
  end
`endif
`endif

endmodule
