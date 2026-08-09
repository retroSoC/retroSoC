// Copyright (c) 2023-2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

`include "ws2812_define.svh"

module ws2812_reg #(
    parameter int TX_FIFO_DEPTH     = 16,
    parameter int TX_FIFO_LOG_DEPTH = $clog2(TX_FIFO_DEPTH)
) (
    // verilog_format: off
    input  logic        clk_i,
    input  logic        rst_n_i,
    ribp_if.slave       ribp,
    output logic [15:0] bit_cycles_o,
    output logic [15:0] t0h_cycles_o,
    output logic [15:0] t1h_cycles_o,
    output logic [31:0] reset_cycles_o,
    output logic [31:0] frame_words_o,
    output logic        start_o,
    output logic        abort_o,
    output logic        data_valid_o,
    output logic [23:0] data_o,
    input  logic        data_pop_i,
    input  logic        core_fifo_flush_i,
    input  logic        core_busy_i,
    input  logic        core_reset_active_i,
    input  logic [31:0] core_remaining_words_i,
    input  logic        core_done_i,
    input  logic        core_underflow_i,
    input  logic        core_aborted_i,
    output logic        irq_o
    // verilog_format: on
);

  localparam logic [31:0] FIFO_WATERMARK_RESET = (TX_FIFO_DEPTH > 4) ? 32'd4 : TX_FIFO_DEPTH - 1;
  localparam logic [7:0] FIFO_DEPTH_INFO = TX_FIFO_DEPTH[7:0];
  localparam logic [31:0] IP_INFO = {8'd24, FIFO_DEPTH_INFO, 8'd1, 8'd0};

  logic s_req;
  logic s_write;
  logic s_req_accept;
  logic s_access_error;
  logic s_ribp_ready_d, s_ribp_ready_q;
  logic s_ribp_resp_err_d, s_ribp_resp_err_q;
  logic [31:0] s_ribp_rdata_d, s_ribp_rdata_q;

  logic s_bit_cycles_en;
  logic [15:0] s_bit_cycles_d, s_bit_cycles_q;
  logic s_t0h_cycles_en;
  logic [15:0] s_t0h_cycles_d, s_t0h_cycles_q;
  logic s_t1h_cycles_en;
  logic [15:0] s_t1h_cycles_d, s_t1h_cycles_q;
  logic s_reset_cycles_en;
  logic [31:0] s_reset_cycles_d, s_reset_cycles_q;
  logic s_frame_words_en;
  logic [31:0] s_frame_words_d, s_frame_words_q;
  logic s_fifo_watermark_en;
  logic [31:0] s_fifo_watermark_d, s_fifo_watermark_q;
  logic s_intr_enable_en;
  logic [3:0] s_intr_enable_d, s_intr_enable_q;

  logic        s_fifo_flush_cmd;
  logic        s_tx_push;
  logic [23:0] s_tx_push_data;
  logic s_tx_empty, s_tx_full;
  logic [               23:0] s_tx_pop_data;
  logic [TX_FIFO_LOG_DEPTH:0] s_tx_count;

  logic [31:0] s_load_remaining_d, s_load_remaining_q;
  logic [2:0] s_error_status_d, s_error_status_q;
  logic [3:0] s_intr_state_d, s_intr_state_q;
  logic [ 2:0] s_error_clear;
  logic [ 3:0] s_intr_clear;
  logic [ 3:0] s_intr_test;
  logic        s_config_error_event;
  logic        s_command_error_event;
  logic        s_fifo_low;
  logic        s_config_valid;
  logic [31:0] s_status;
  logic [31:0] s_fifo_level;
  logic [31:0] s_watermark_write_value;

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

  assign s_req = ribp.valid && !s_ribp_ready_q;
  assign s_write = |ribp.wstrb;
  assign ribp.ready = s_ribp_ready_q;
  assign ribp.resp_err = s_ribp_resp_err_q;
  assign ribp.rdata = s_ribp_rdata_q;
  assign bit_cycles_o = s_bit_cycles_q;
  assign t0h_cycles_o = s_t0h_cycles_q;
  assign t1h_cycles_o = s_t1h_cycles_q;
  assign reset_cycles_o = s_reset_cycles_q;
  assign frame_words_o = s_frame_words_q;
  assign data_valid_o = !s_tx_empty;
  assign data_o = s_tx_pop_data;
  assign irq_o = |(s_intr_state_q & s_intr_enable_q);
  assign s_fifo_level = {{(31 - TX_FIFO_LOG_DEPTH) {1'b0}}, s_tx_count};
  assign s_watermark_write_value = merge_wstrb(s_fifo_watermark_q, ribp.wdata, ribp.wstrb);
  assign s_config_valid            = (s_bit_cycles_q != 16'd0) &&
                                     (s_t0h_cycles_q != 16'd0) &&
                                     (s_t1h_cycles_q != 16'd0) &&
                                     (s_t0h_cycles_q < s_t1h_cycles_q) &&
                                     (s_t1h_cycles_q < s_bit_cycles_q) &&
                                     (s_reset_cycles_q != 32'd0);
  assign s_fifo_low                = core_busy_i && (s_load_remaining_q != 32'd0) &&
                                     (s_fifo_level <= s_fifo_watermark_q);

  always_comb begin
    s_status                              = '0;
    s_status[`WS2812_STATUS_BUSY]         = core_busy_i;
    s_status[`WS2812_STATUS_FIFO_EMPTY]   = s_tx_empty;
    s_status[`WS2812_STATUS_FIFO_FULL]    = s_tx_full;
    s_status[`WS2812_STATUS_CONFIG_VALID] = s_config_valid;
    s_status[`WS2812_STATUS_RESET_ACTIVE] = core_reset_active_i;
  end

  always_comb begin
    s_req_accept          = s_req;
    s_access_error        = 1'b0;
    s_bit_cycles_en       = 1'b0;
    s_t0h_cycles_en       = 1'b0;
    s_t1h_cycles_en       = 1'b0;
    s_reset_cycles_en     = 1'b0;
    s_frame_words_en      = 1'b0;
    s_fifo_watermark_en   = 1'b0;
    s_intr_enable_en      = 1'b0;
    s_bit_cycles_d        = s_bit_cycles_q;
    s_t0h_cycles_d        = s_t0h_cycles_q;
    s_t1h_cycles_d        = s_t1h_cycles_q;
    s_reset_cycles_d      = s_reset_cycles_q;
    s_frame_words_d       = s_frame_words_q;
    s_fifo_watermark_d    = s_fifo_watermark_q;
    s_intr_enable_d       = s_intr_enable_q;
    s_fifo_flush_cmd      = 1'b0;
    s_tx_push             = 1'b0;
    s_tx_push_data        = ribp.wdata[23:0];
    start_o               = 1'b0;
    abort_o               = 1'b0;
    s_error_clear         = '0;
    s_intr_clear          = '0;
    s_intr_test           = '0;
    s_config_error_event  = 1'b0;
    s_command_error_event = 1'b0;
    s_ribp_rdata_d        = '0;

    if (s_req) begin
      if ((ribp.addr[11:8] != 4'd0) || (ribp.addr[1:0] != 2'b00)) begin
        s_access_error = 1'b1;
      end else if (s_write) begin
        unique case (ribp.addr[7:0])
          `RIBP_WS2812_BIT_CYCLES: begin
            s_bit_cycles_en = 1'b1;
            s_bit_cycles_d  = 16'(merge_wstrb({16'd0, s_bit_cycles_q}, ribp.wdata, ribp.wstrb));
          end
          `RIBP_WS2812_T0H_CYCLES: begin
            s_t0h_cycles_en = 1'b1;
            s_t0h_cycles_d  = 16'(merge_wstrb({16'd0, s_t0h_cycles_q}, ribp.wdata, ribp.wstrb));
          end
          `RIBP_WS2812_T1H_CYCLES: begin
            s_t1h_cycles_en = 1'b1;
            s_t1h_cycles_d  = 16'(merge_wstrb({16'd0, s_t1h_cycles_q}, ribp.wdata, ribp.wstrb));
          end
          `RIBP_WS2812_RESET_CYCLES: begin
            s_reset_cycles_en = 1'b1;
            s_reset_cycles_d  = merge_wstrb(s_reset_cycles_q, ribp.wdata, ribp.wstrb);
          end
          `RIBP_WS2812_TXDATA: begin
            if (ribp.wstrb != 4'hF || (core_busy_i && (s_load_remaining_q == 32'd0))) begin
              s_access_error        = 1'b1;
              s_command_error_event = 1'b1;
            end else if (s_tx_full && core_busy_i) begin
              s_req_accept = 1'b0;
            end else if (s_tx_full && !core_busy_i) begin
              s_access_error        = 1'b1;
              s_command_error_event = 1'b1;
            end else begin
              s_tx_push = 1'b1;
            end
          end
          `RIBP_WS2812_CTRL: begin
            if (!ribp.wstrb[0]) begin
              s_access_error        = 1'b1;
              s_command_error_event = 1'b1;
            end else begin
              unique case (ribp.wdata[2:0])
                3'b001: begin
                  if (core_busy_i || (s_frame_words_q == 32'd0) || s_tx_empty ||
                      (s_fifo_level > s_frame_words_q)) begin
                    s_access_error        = 1'b1;
                    s_command_error_event = 1'b1;
                  end else if (!s_config_valid) begin
                    s_access_error       = 1'b1;
                    s_config_error_event = 1'b1;
                  end else begin
                    start_o = 1'b1;
                  end
                end
                3'b010: begin
                  if (!core_busy_i) begin
                    s_access_error        = 1'b1;
                    s_command_error_event = 1'b1;
                  end else begin
                    abort_o = 1'b1;
                  end
                end
                3'b100: begin
                  if (core_busy_i) begin
                    s_access_error        = 1'b1;
                    s_command_error_event = 1'b1;
                  end else begin
                    s_fifo_flush_cmd = 1'b1;
                  end
                end
                default: begin
                  s_access_error        = 1'b1;
                  s_command_error_event = 1'b1;
                end
              endcase
            end
          end
          `RIBP_WS2812_FRAME_WORDS: begin
            s_frame_words_en = 1'b1;
            s_frame_words_d  = merge_wstrb(s_frame_words_q, ribp.wdata, ribp.wstrb);
          end
          `RIBP_WS2812_FIFO_WATERMARK: begin
            if (s_watermark_write_value >= TX_FIFO_DEPTH) begin
              s_access_error        = 1'b1;
              s_command_error_event = 1'b1;
            end else begin
              s_fifo_watermark_en = 1'b1;
              s_fifo_watermark_d  = s_watermark_write_value;
            end
          end
          `RIBP_WS2812_ERROR_STATUS: begin
            if (!ribp.wstrb[0]) begin
              s_access_error = 1'b1;
            end else begin
              s_error_clear = ribp.wdata[2:0];
            end
          end
          `RIBP_WS2812_INTR_STATE: begin
            if (!ribp.wstrb[0]) begin
              s_access_error = 1'b1;
            end else begin
              s_intr_clear = ribp.wdata[3:0];
            end
          end
          `RIBP_WS2812_INTR_ENABLE: begin
            s_intr_enable_en = 1'b1;
            s_intr_enable_d  = 4'(merge_wstrb({28'd0, s_intr_enable_q}, ribp.wdata, ribp.wstrb));
          end
          `RIBP_WS2812_INTR_TEST: begin
            if (!ribp.wstrb[0]) begin
              s_access_error = 1'b1;
            end else begin
              s_intr_test = ribp.wdata[3:0];
            end
          end
          default: s_access_error = 1'b1;
        endcase
      end else begin
        unique case (ribp.addr[7:0])
          `RIBP_WS2812_BIT_CYCLES:      s_ribp_rdata_d = {16'd0, s_bit_cycles_q};
          `RIBP_WS2812_T0H_CYCLES:      s_ribp_rdata_d = {16'd0, s_t0h_cycles_q};
          `RIBP_WS2812_T1H_CYCLES:      s_ribp_rdata_d = {16'd0, s_t1h_cycles_q};
          `RIBP_WS2812_RESET_CYCLES:    s_ribp_rdata_d = s_reset_cycles_q;
          `RIBP_WS2812_STATUS:          s_ribp_rdata_d = s_status;
          `RIBP_WS2812_FRAME_WORDS:     s_ribp_rdata_d = s_frame_words_q;
          `RIBP_WS2812_FIFO_LEVEL:      s_ribp_rdata_d = s_fifo_level;
          `RIBP_WS2812_FIFO_WATERMARK:  s_ribp_rdata_d = s_fifo_watermark_q;
          `RIBP_WS2812_REMAINING_WORDS: s_ribp_rdata_d = core_remaining_words_i;
          `RIBP_WS2812_ERROR_STATUS:    s_ribp_rdata_d = {29'd0, s_error_status_q};
          `RIBP_WS2812_INTR_STATE:      s_ribp_rdata_d = {28'd0, s_intr_state_q};
          `RIBP_WS2812_INTR_ENABLE:     s_ribp_rdata_d = {28'd0, s_intr_enable_q};
          `RIBP_WS2812_IP_INFO:         s_ribp_rdata_d = IP_INFO;
          default: begin
            s_ribp_rdata_d = '0;
            s_access_error = 1'b1;
          end
        endcase
      end
    end
  end

  assign s_ribp_ready_d    = s_req_accept;
  assign s_ribp_resp_err_d = s_access_error;

  dffr #(1) u_ribp_ready_dffr (
      clk_i,
      rst_n_i,
      s_ribp_ready_d,
      s_ribp_ready_q
  );
  dffer #(1) u_ribp_resp_err_dffer (
      clk_i,
      rst_n_i,
      s_req_accept,
      s_ribp_resp_err_d,
      s_ribp_resp_err_q
  );
  dffer #(32) u_ribp_rdata_dffer (
      clk_i,
      rst_n_i,
      s_req_accept,
      s_ribp_rdata_d,
      s_ribp_rdata_q
  );

  dffer #(16) u_bit_cycles_dffer (
      clk_i,
      rst_n_i,
      s_bit_cycles_en,
      s_bit_cycles_d,
      s_bit_cycles_q
  );
  dffer #(16) u_t0h_cycles_dffer (
      clk_i,
      rst_n_i,
      s_t0h_cycles_en,
      s_t0h_cycles_d,
      s_t0h_cycles_q
  );
  dffer #(16) u_t1h_cycles_dffer (
      clk_i,
      rst_n_i,
      s_t1h_cycles_en,
      s_t1h_cycles_d,
      s_t1h_cycles_q
  );
  dffer #(32) u_reset_cycles_dffer (
      clk_i,
      rst_n_i,
      s_reset_cycles_en,
      s_reset_cycles_d,
      s_reset_cycles_q
  );
  dffer #(32) u_frame_words_dffer (
      clk_i,
      rst_n_i,
      s_frame_words_en,
      s_frame_words_d,
      s_frame_words_q
  );
  dfferc #(
      .DATA_WIDTH(32),
      .RESET_VAL (FIFO_WATERMARK_RESET)
  ) u_fifo_watermark_dfferc (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_fifo_watermark_en),
      .dat_i  (s_fifo_watermark_d),
      .dat_o  (s_fifo_watermark_q)
  );
  dffer #(4) u_intr_enable_dffer (
      clk_i,
      rst_n_i,
      s_intr_enable_en,
      s_intr_enable_d,
      s_intr_enable_q
  );

  fifo #(
      .DATA_WIDTH      (24),
      .BUFFER_DEPTH    (TX_FIFO_DEPTH),
      .LOG_BUFFER_DEPTH(TX_FIFO_LOG_DEPTH)
  ) u_tx_fifo (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .flush_i(s_fifo_flush_cmd || core_fifo_flush_i),
      .push_i (s_tx_push),
      .full_o (s_tx_full),
      .dat_i  (s_tx_push_data),
      .pop_i  (data_pop_i),
      .empty_o(s_tx_empty),
      .dat_o  (s_tx_pop_data),
      .cnt_o  (s_tx_count)
  );

  always_comb begin
    s_load_remaining_d = s_load_remaining_q;
    if (start_o) begin
      s_load_remaining_d = s_frame_words_q - s_fifo_level;
    end else if (core_done_i || core_underflow_i || core_aborted_i) begin
      s_load_remaining_d = '0;
    end else if (s_tx_push && core_busy_i) begin
      s_load_remaining_d = s_load_remaining_q - 1'b1;
    end
  end
  dffr #(32) u_load_remaining_dffr (
      clk_i,
      rst_n_i,
      s_load_remaining_d,
      s_load_remaining_q
  );

  always_comb begin
    s_error_status_d = s_error_status_q & ~s_error_clear;
    if (s_config_error_event) begin
      s_error_status_d[`WS2812_ERROR_CONFIG] = 1'b1;
    end
    if (core_underflow_i) begin
      s_error_status_d[`WS2812_ERROR_UNDERFLOW] = 1'b1;
    end
    if (s_command_error_event) begin
      s_error_status_d[`WS2812_ERROR_COMMAND] = 1'b1;
    end
  end
  dffr #(3) u_error_status_dffr (
      clk_i,
      rst_n_i,
      s_error_status_d,
      s_error_status_q
  );

  always_comb begin
    s_intr_state_d = (s_intr_state_q & ~s_intr_clear) | s_intr_test;
    if (core_done_i) begin
      s_intr_state_d[`WS2812_INTR_DONE] = 1'b1;
    end
    if (s_fifo_low) begin
      s_intr_state_d[`WS2812_INTR_FIFO_LOW] = 1'b1;
    end
    if (s_config_error_event || s_command_error_event || core_underflow_i) begin
      s_intr_state_d[`WS2812_INTR_ERROR] = 1'b1;
    end
    if (core_aborted_i) begin
      s_intr_state_d[`WS2812_INTR_ABORTED] = 1'b1;
    end
  end
  dffr #(4) u_intr_state_dffr (
      clk_i,
      rst_n_i,
      s_intr_state_d,
      s_intr_state_q
  );

endmodule
