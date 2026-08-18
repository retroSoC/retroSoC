// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

`include "dma_define.svh"

module dma_reg #(
    parameter int NumChannels       = 4,
    parameter int ChannelIndexWidth = (NumChannels > 1) ? $clog2(NumChannels) : 1,
    parameter int DataWidth         = 32,
    parameter int MaxBurstBeats     = 16
) (
    // verilog_format: off -- APB4/configuration and status vector groups follow the register ABI.
    input  logic                           clk_i,
    input  logic                           rst_n_i,
    apb4_if.slave                          apb4,
    output logic [NumChannels*32-1:0]      ch_cfg_o,
    output logic [NumChannels*32-1:0]      src_addr_o,
    output logic [NumChannels*32-1:0]      dst_addr_o,
    output logic [NumChannels*32-1:0]      byte_count_o,
    output logic [NumChannels*32-1:0]      request_sel_o,
    output logic [NumChannels*32-1:0]      burst_cfg_o,
    output logic [NumChannels-1:0]         start_o,
    output logic [NumChannels-1:0]         suspend_o,
    output logic [NumChannels-1:0]         resume_o,
    output logic [NumChannels-1:0]         abort_o,
    output logic [NumChannels-1:0]         channel_reset_o,
    output logic [NumChannels*3-1:0]       event_clear_o,
    output logic                           global_reset_o,
    output logic                           global_error_clear_o,
    input  logic [NumChannels-1:0]         busy_i,
    input  logic [NumChannels-1:0]         suspended_i,
    input  logic [NumChannels-1:0]         done_i,
    input  logic [NumChannels-1:0]         aborted_i,
    input  logic [NumChannels-1:0]         error_i,
    input  logic [NumChannels-1:0]         stream_last_i,
    input  logic [NumChannels*3-1:0]       event_status_i,
    input  logic [NumChannels*32-1:0]      error_status_i,
    input  logic [NumChannels*32-1:0]      error_addr_i,
    input  logic [NumChannels*32-1:0]      current_src_i,
    input  logic [NumChannels*32-1:0]      current_dst_i,
    input  logic [NumChannels*32-1:0]      remaining_i,
    input  logic [NumChannels*32-1:0]      bytes_done_i,
    input  logic [NumChannels*32-1:0]      stall_cycles_lo_i,
    input  logic [NumChannels*32-1:0]      stall_cycles_hi_i,
    input  logic                           first_error_valid_i,
    input  logic [ChannelIndexWidth-1:0]   first_error_channel_i,
    input  logic [8:0]                     first_error_status_i,
    input  logic [15:0]                    first_error_addr_hi_i,
    input  logic [15:0]                    request_status_i,
    output logic                           irq_o
    // verilog_format: on
);
  localparam logic [31:0] IpId = 32'h444D_4134;
  localparam logic [31:0] IpVersion = 32'h0001_0000;
  localparam logic [31:0] ChannelBase = {20'd0, `APB4_DMA__CH_BASE};
  localparam logic [31:0] ChannelStride = {20'd0, `APB4_DMA__CH_STRIDE};

  logic [   NumChannels*32-1:0] s_ch_cfg_q;
  logic [   NumChannels*32-1:0] s_src_addr_q;
  logic [   NumChannels*32-1:0] s_dst_addr_q;
  logic [   NumChannels*32-1:0] s_byte_count_q;
  logic [   NumChannels*32-1:0] s_req_sel_q;
  logic [   NumChannels*32-1:0] s_burst_cfg_q;
  logic [   NumChannels*32-1:0] s_evt_en_q;
  logic [      NumChannels-1:0] s_irq_en_q;
  logic [      NumChannels-1:0] s_irq_test_q;
  logic [      NumChannels-1:0] s_irq_source;
  logic [      NumChannels-1:0] s_irq_state;

  logic                         s_access;
  logic                         s_write;
  logic [                 11:0] s_offset;
  logic [                 31:0] s_offset_ext;
  logic                         s_global_valid;
  logic                         s_channel_valid;
  logic [ChannelIndexWidth-1:0] s_channel_index;
  logic [                  6:0] s_channel_offset;
  logic                         s_channel_read_only;
  logic                         s_channel_config_write;
  logic                         s_low_byte_only_write;
  logic                         s_access_err;
  logic [                 31:0] s_read_data;
  logic [      NumChannels-1:0] s_irq_en_write;
  logic [      NumChannels-1:0] s_irq_test_write;

  function automatic logic [31:0] merge_bytes(
      input logic [31:0] current_i, input logic [31:0] write_i, input logic [3:0] strobe_i);
    logic [31:0] result;

    result = current_i;
    for (int unsigned byte_index = 0; byte_index < 4; byte_index++) begin
      if (strobe_i[byte_index]) begin
        result[(byte_index*8)+:8] = write_i[(byte_index*8)+:8];
      end
    end
    merge_bytes = result;
  endfunction

`ifndef SYNTHESIS
  initial begin
    if ((NumChannels < 2) || (NumChannels > 8) || (DataWidth != 32) ||
        (MaxBurstBeats < 1) || (MaxBurstBeats > 16)) begin
      $fatal(1, "dma_reg: unsupported DMA register geometry");
    end
  end
`endif

  assign s_access = apb4.psel && apb4.penable;
  assign s_write = s_access && apb4.pwrite;
  assign s_offset = apb4.paddr[11:0];
  assign s_offset_ext = {20'd0, s_offset};
  assign s_global_valid = (s_offset == `APB4_DMA__IP_ID) ||
                          (s_offset == `APB4_DMA__IP_VERSION) ||
                          (s_offset == `APB4_DMA__CAPABILITY) ||
                          (s_offset == `APB4_DMA__GLOBAL_CTRL) ||
                          (s_offset == `APB4_DMA__GLOBAL_STATUS) ||
                          (s_offset == `APB4_DMA__IRQ_STATE) ||
                          (s_offset == `APB4_DMA__IRQ_ENABLE) ||
                          (s_offset == `APB4_DMA__IRQ_TEST) ||
                          (s_offset == `APB4_DMA__ERROR_SUMMARY) ||
                          (s_offset == `APB4_DMA__REQUEST_STATUS);
  assign s_channel_valid = (s_offset_ext >= ChannelBase) &&
                           (s_offset_ext < (ChannelBase + (NumChannels * ChannelStride)));
  assign s_channel_index = ChannelIndexWidth'((s_offset_ext - ChannelBase) >> 7);
  assign s_channel_offset = s_offset[6:0];
  assign s_channel_read_only = (s_channel_offset == `APB4_DMA__CH_STATUS) ||
                               (s_channel_offset == `APB4_DMA__CH_ERROR_STATUS) ||
                               (s_channel_offset == `APB4_DMA__CH_ERROR_ADDR) ||
                               (s_channel_offset == `APB4_DMA__CH_CURRENT_SRC) ||
                               (s_channel_offset == `APB4_DMA__CH_CURRENT_DST) ||
                               (s_channel_offset == `APB4_DMA__CH_REMAINING) ||
                               (s_channel_offset == `APB4_DMA__CH_BYTES_DONE) ||
                               (s_channel_offset == `APB4_DMA__CH_STALL_CYCLES_LO) ||
                               (s_channel_offset == `APB4_DMA__CH_STALL_CYCLES_HI);
  assign s_channel_config_write = (s_channel_offset == `APB4_DMA__CH_CFG) ||
                                  (s_channel_offset == `APB4_DMA__CH_SRC_ADDR) ||
                                  (s_channel_offset == `APB4_DMA__CH_DST_ADDR) ||
                                  (s_channel_offset == `APB4_DMA__CH_BYTE_COUNT) ||
                                  (s_channel_offset == `APB4_DMA__CH_REQUEST_SEL) ||
                                  (s_channel_offset == `APB4_DMA__CH_BURST_CFG);
  assign s_low_byte_only_write =
      s_write &&
      (((s_offset == `APB4_DMA__GLOBAL_CTRL) ||
        (s_offset == `APB4_DMA__IRQ_STATE) ||
        (s_offset == `APB4_DMA__IRQ_ENABLE) ||
        (s_offset == `APB4_DMA__IRQ_TEST) ||
        (s_offset == `APB4_DMA__ERROR_SUMMARY)) ||
       (s_channel_valid &&
        ((s_channel_offset == `APB4_DMA__CH_CTRL) ||
         (s_channel_offset == `APB4_DMA__CH_EVENT_STATUS))));

  always_comb begin
    s_access_err = s_access && !(s_global_valid || s_channel_valid);
    if (s_low_byte_only_write && !apb4.pstrb[0]) begin
      s_access_err = 1'b1;
    end
    if (s_write && s_global_valid &&
        ((s_offset == `APB4_DMA__IP_ID) || (s_offset == `APB4_DMA__IP_VERSION) ||
         (s_offset == `APB4_DMA__CAPABILITY) || (s_offset == `APB4_DMA__GLOBAL_STATUS) ||
         (s_offset == `APB4_DMA__REQUEST_STATUS))) begin
      s_access_err = 1'b1;
    end
    if (s_write && s_channel_valid &&
        (s_channel_read_only ||
         ((s_channel_offset != `APB4_DMA__CH_CTRL) &&
          (s_channel_offset != `APB4_DMA__CH_CFG) &&
          (s_channel_offset != `APB4_DMA__CH_SRC_ADDR) &&
          (s_channel_offset != `APB4_DMA__CH_DST_ADDR) &&
          (s_channel_offset != `APB4_DMA__CH_BYTE_COUNT) &&
          (s_channel_offset != `APB4_DMA__CH_REQUEST_SEL) &&
          (s_channel_offset != `APB4_DMA__CH_BURST_CFG) &&
          (s_channel_offset != `APB4_DMA__CH_EVENT_ENABLE) &&
          (s_channel_offset != `APB4_DMA__CH_EVENT_STATUS)))) begin
      s_access_err = 1'b1;
    end
    if (s_write && s_channel_valid && s_channel_config_write && busy_i[s_channel_index]) begin
      s_access_err = 1'b1;
    end
    if (s_write && s_channel_valid && (s_channel_offset == `APB4_DMA__CH_CTRL) &&
        apb4.pwdata[`APB4_DMA__CH_CTRL_START] && busy_i[s_channel_index]) begin
      s_access_err = 1'b1;
    end
    if (s_write && (s_offset == `APB4_DMA__GLOBAL_CTRL) &&
        apb4.pwdata[`APB4_DMA__GLOBAL_CTRL_RESET] && (busy_i != '0)) begin
      s_access_err = 1'b1;
    end
    if (s_write && s_channel_valid && (s_channel_offset == `APB4_DMA__CH_CTRL) &&
        apb4.pwdata[`APB4_DMA__CH_CTRL_RESET] && busy_i[s_channel_index]) begin
      s_access_err = 1'b1;
    end
  end

  assign apb4.pready  = s_access;
  assign apb4.pslverr = s_access_err;
  assign apb4.prdata  = s_read_data;
  always_comb begin
    s_irq_en_write   = s_irq_en_q;
    s_irq_test_write = s_irq_test_q;
    if (apb4.pstrb[0]) begin
      s_irq_en_write   = apb4.pwdata[NumChannels-1:0];
      s_irq_test_write = apb4.pwdata[NumChannels-1:0];
    end
  end

  always_comb begin
    start_o = '0;
    suspend_o = '0;
    resume_o = '0;
    abort_o = '0;
    channel_reset_o = '0;
    event_clear_o = '0;
    global_reset_o = s_write && !s_access_err &&
                     (s_offset == `APB4_DMA__GLOBAL_CTRL) &&
                     apb4.pwdata[`APB4_DMA__GLOBAL_CTRL_RESET];
    global_error_clear_o = s_write && !s_access_err &&
                           (s_offset == `APB4_DMA__ERROR_SUMMARY) && apb4.pwdata[0];
    if (s_write && !s_access_err && s_channel_valid) begin
      if (s_channel_offset == `APB4_DMA__CH_CTRL) begin
        start_o[s_channel_index]         = apb4.pwdata[`APB4_DMA__CH_CTRL_START];
        suspend_o[s_channel_index]       = apb4.pwdata[`APB4_DMA__CH_CTRL_SUSPEND];
        resume_o[s_channel_index]        = apb4.pwdata[`APB4_DMA__CH_CTRL_RESUME];
        abort_o[s_channel_index]         = apb4.pwdata[`APB4_DMA__CH_CTRL_ABORT];
        channel_reset_o[s_channel_index] = apb4.pwdata[`APB4_DMA__CH_CTRL_RESET];
      end
      if (s_channel_offset == `APB4_DMA__CH_EVENT_STATUS) begin
        event_clear_o[(s_channel_index*3)+:3] = apb4.pwdata[2:0];
      end
    end
  end

  always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
      s_ch_cfg_q     <= '0;
      s_src_addr_q   <= '0;
      s_dst_addr_q   <= '0;
      s_byte_count_q <= '0;
      s_req_sel_q    <= '0;
      s_burst_cfg_q  <= '0;
      s_evt_en_q     <= '0;
      s_irq_en_q     <= '0;
      s_irq_test_q   <= '0;
    end else if (global_reset_o) begin
      s_ch_cfg_q     <= '0;
      s_src_addr_q   <= '0;
      s_dst_addr_q   <= '0;
      s_byte_count_q <= '0;
      s_req_sel_q    <= '0;
      s_burst_cfg_q  <= '0;
      s_evt_en_q     <= '0;
      s_irq_en_q     <= '0;
      s_irq_test_q   <= '0;
    end else if (s_write && !s_access_err) begin
      if (s_offset == `APB4_DMA__IRQ_ENABLE) begin
        s_irq_en_q <= s_irq_en_write;
      end
      if (s_offset == `APB4_DMA__IRQ_TEST) begin
        s_irq_test_q <= s_irq_test_write;
      end
      if (s_offset == `APB4_DMA__IRQ_STATE) begin
        s_irq_test_q <= s_irq_test_q & ~apb4.pwdata[NumChannels-1:0];
      end
      if (s_channel_valid) begin
        unique case (s_channel_offset)
          `APB4_DMA__CH_CFG: begin
            s_ch_cfg_q[(s_channel_index*32)+:32] <=
                merge_bytes(s_ch_cfg_q[(s_channel_index*32)+:32], apb4.pwdata, apb4.pstrb);
          end
          `APB4_DMA__CH_SRC_ADDR: begin
            s_src_addr_q[(s_channel_index*32)+:32] <=
                merge_bytes(s_src_addr_q[(s_channel_index*32)+:32], apb4.pwdata, apb4.pstrb);
          end
          `APB4_DMA__CH_DST_ADDR: begin
            s_dst_addr_q[(s_channel_index*32)+:32] <=
                merge_bytes(s_dst_addr_q[(s_channel_index*32)+:32], apb4.pwdata, apb4.pstrb);
          end
          `APB4_DMA__CH_BYTE_COUNT: begin
            s_byte_count_q[(s_channel_index*32)+:32] <=
                merge_bytes(s_byte_count_q[(s_channel_index*32)+:32], apb4.pwdata, apb4.pstrb);
          end
          `APB4_DMA__CH_REQUEST_SEL: begin
            s_req_sel_q[(s_channel_index*32)+:32] <=
                merge_bytes(s_req_sel_q[(s_channel_index*32)+:32], apb4.pwdata, apb4.pstrb);
          end
          `APB4_DMA__CH_BURST_CFG: begin
            s_burst_cfg_q[(s_channel_index*32)+:32] <=
                merge_bytes(s_burst_cfg_q[(s_channel_index*32)+:32], apb4.pwdata, apb4.pstrb);
          end
          `APB4_DMA__CH_EVENT_ENABLE: begin
            s_evt_en_q[(s_channel_index*32)+:32] <=
                merge_bytes(s_evt_en_q[(s_channel_index*32)+:32], apb4.pwdata, apb4.pstrb);
          end
          default: begin
          end
        endcase
      end
    end
  end

  always_comb begin
    s_irq_source = '0;
    for (int unsigned channel = 0; channel < NumChannels; channel++) begin
      s_irq_source[channel] = |(event_status_i[(channel*3)+:3] & s_evt_en_q[(channel*32)+:3]);
    end
    s_irq_state = s_irq_test_q | (s_irq_en_q & s_irq_source);
    irq_o       = |s_irq_state;
  end

  always_comb begin
    s_read_data = 32'd0;
    unique case (s_offset)
      `APB4_DMA__IP_ID: s_read_data = IpId;
      `APB4_DMA__IP_VERSION: s_read_data = IpVersion;
      `APB4_DMA__CAPABILITY:
      s_read_data = {1'b0, 3'd3, 4'(MaxBurstBeats), 8'(DataWidth), 8'(NumChannels), 8'd0};
      `APB4_DMA__GLOBAL_CTRL: s_read_data = 32'd0;
      `APB4_DMA__GLOBAL_STATUS: s_read_data = {31'd0, |busy_i};
      `APB4_DMA__IRQ_STATE: s_read_data = {{(32 - NumChannels) {1'b0}}, s_irq_state};
      `APB4_DMA__IRQ_ENABLE: s_read_data = {{(32 - NumChannels) {1'b0}}, s_irq_en_q};
      `APB4_DMA__IRQ_TEST: s_read_data = {{(32 - NumChannels) {1'b0}}, s_irq_test_q};
      `APB4_DMA__ERROR_SUMMARY:
      s_read_data = {
        first_error_addr_hi_i,
        first_error_status_i,
        3'd0,
        {{(3 - ChannelIndexWidth) {1'b0}}, first_error_channel_i},
        first_error_valid_i
      };
      `APB4_DMA__REQUEST_STATUS: s_read_data = {16'd0, request_status_i};
      default: begin
        if (s_channel_valid) begin
          unique case (s_channel_offset)
            `APB4_DMA__CH_CFG: s_read_data = s_ch_cfg_q[(s_channel_index*32)+:32];
            `APB4_DMA__CH_SRC_ADDR: s_read_data = s_src_addr_q[(s_channel_index*32)+:32];
            `APB4_DMA__CH_DST_ADDR: s_read_data = s_dst_addr_q[(s_channel_index*32)+:32];
            `APB4_DMA__CH_BYTE_COUNT: s_read_data = s_byte_count_q[(s_channel_index*32)+:32];
            `APB4_DMA__CH_REQUEST_SEL: s_read_data = s_req_sel_q[(s_channel_index*32)+:32];
            `APB4_DMA__CH_BURST_CFG: s_read_data = s_burst_cfg_q[(s_channel_index*32)+:32];
            `APB4_DMA__CH_EVENT_ENABLE: s_read_data = s_evt_en_q[(s_channel_index*32)+:32];
            `APB4_DMA__CH_STATUS:
            s_read_data = {
              26'd0,
              stream_last_i[s_channel_index],
              error_i[s_channel_index],
              aborted_i[s_channel_index],
              done_i[s_channel_index],
              suspended_i[s_channel_index],
              busy_i[s_channel_index]
            };
            `APB4_DMA__CH_EVENT_STATUS:
            s_read_data = {29'd0, event_status_i[(s_channel_index*3)+:3]};
            `APB4_DMA__CH_ERROR_STATUS: s_read_data = error_status_i[(s_channel_index*32)+:32];
            `APB4_DMA__CH_ERROR_ADDR: s_read_data = error_addr_i[(s_channel_index*32)+:32];
            `APB4_DMA__CH_CURRENT_SRC: s_read_data = current_src_i[(s_channel_index*32)+:32];
            `APB4_DMA__CH_CURRENT_DST: s_read_data = current_dst_i[(s_channel_index*32)+:32];
            `APB4_DMA__CH_REMAINING: s_read_data = remaining_i[(s_channel_index*32)+:32];
            `APB4_DMA__CH_BYTES_DONE: s_read_data = bytes_done_i[(s_channel_index*32)+:32];
            `APB4_DMA__CH_STALL_CYCLES_LO:
            s_read_data = stall_cycles_lo_i[(s_channel_index*32)+:32];
            `APB4_DMA__CH_STALL_CYCLES_HI:
            s_read_data = stall_cycles_hi_i[(s_channel_index*32)+:32];
            default: s_read_data = 32'd0;
          endcase
        end
      end
    endcase
  end

  assign ch_cfg_o      = s_ch_cfg_q;
  assign src_addr_o    = s_src_addr_q;
  assign dst_addr_o    = s_dst_addr_q;
  assign byte_count_o  = s_byte_count_q;
  assign request_sel_o = s_req_sel_q;
  assign burst_cfg_o   = s_burst_cfg_q;
endmodule
