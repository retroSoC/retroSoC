// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

`include "timer_define.svh"

module timer_reg (
    // verilog_format: off -- preserve reviewed column alignment
    input  logic        clk_i,
    input  logic        rst_n_i,
    apb4_if.slave       apb4,
    input  logic [31:0] value_i,
    input  logic        debug_frozen_i,
    input  logic        timeout_event_i,
    input  logic        compare0_event_i,
    input  logic        compare1_event_i,
    input  logic        one_shot_done_i,
    output logic        enable_o,
    output logic [1:0]  mode_o,
    output logic        direction_o,
    output logic        debug_freeze_enable_o,
    output logic        compare0_enable_o,
    output logic        compare1_enable_o,
    output logic [15:0] prescale_o,
    output logic [31:0] load_o,
    output logic [31:0] compare0_o,
    output logic [31:0] compare1_o,
    output logic        start_o,
    output logic        stop_o,
    output logic        load_now_o,
    output logic        irq_o
    // verilog_format: on
);

  localparam logic [1:0] MODE_RESERVED = 2'b11;
  localparam logic [31:0] IP_VERSION = 32'h0002_0000;
  localparam logic [31:0] CAPABILITY = 32'h00F2_1020;
  localparam logic [31:0] CTRL_ENABLE_MASK = 32'b1 << `TIMER_CTRL_ENABLE;
  localparam logic [31:0] CTRL_MODE_MASK = 32'b11 << `TIMER_CTRL_MODE;
  localparam logic [31:0] CTRL_DIRECTION_MASK = 32'b1 << `TIMER_CTRL_DIRECTION;
  localparam logic [31:0] CTRL_DEBUG_FREEZE_MASK = 32'b1 << `TIMER_CTRL_DEBUG_FREEZE;
  localparam logic [31:0] CTRL_COMPARE0_ENABLE_MASK = 32'b1 << `TIMER_CTRL_COMPARE0_ENABLE;
  localparam logic [31:0] CTRL_COMPARE1_ENABLE_MASK = 32'b1 << `TIMER_CTRL_COMPARE1_ENABLE;
  localparam logic [31:0] CTRL_WRITABLE_MASK =
      CTRL_ENABLE_MASK | CTRL_MODE_MASK | CTRL_DIRECTION_MASK | CTRL_DEBUG_FREEZE_MASK |
      CTRL_COMPARE0_ENABLE_MASK | CTRL_COMPARE1_ENABLE_MASK;
  localparam logic [31:0] CTRL_ACTIVE_IMMUTABLE_MASK = CTRL_MODE_MASK | CTRL_DIRECTION_MASK;
  logic        s_req;
  logic        s_write;
  logic        s_req_accept;
  logic [11:0] s_offset;
  logic        s_aligned;
  logic        s_access_err;
  logic s_apb4_ready_d, s_apb4_ready_q;
  logic s_apb4_resp_err_d, s_apb4_resp_err_q;
  logic [31:0] s_apb4_rdata_d, s_apb4_rdata_q;

  logic [31:0] s_ctrl_write_value;
  logic [31:0] s_load_write_value;
  logic [31:0] s_bgload_write_value;
  logic [15:0] s_prescale_write_value;
  logic [31:0] s_compare0_write_value;
  logic [31:0] s_compare1_write_value;
  logic [ 2:0] s_intr_en_write_value;
  logic [ 2:0] s_intr_clear;
  logic [ 2:0] s_intr_set;
  logic [ 2:0] s_intr_state_d;
  logic [ 2:0] s_intr_state_q;
  logic [ 2:0] s_intr_en_d;
  logic [ 2:0] s_intr_en_q;
  logic [31:0] s_ctrl_d, s_ctrl_q;
  logic [31:0] s_load_d, s_load_q;
  logic [15:0] s_prescale_d, s_prescale_q;
  logic [31:0] s_compare0_d, s_compare0_q;
  logic [31:0] s_compare1_d, s_compare1_q;

  function automatic logic [31:0] merge_wstrb(input logic [31:0] current, input logic [31:0] value,
                                              input logic [3:0] strobe);
    logic [31:0] merged;
    begin
      merged = current;
      for (int byte_index = 0; byte_index < 4; byte_index++) begin
        if (strobe[byte_index]) begin
          merged[byte_index*8+:8] = value[byte_index*8+:8];
        end
      end
      return merged;
    end
  endfunction

  assign s_req = apb4.psel && apb4.penable && !s_apb4_ready_q;
  assign s_write = apb4.pwrite;
  assign s_req_accept = s_req;
  assign s_offset = apb4.paddr[11:0];
  assign s_aligned = apb4.paddr[1:0] == 2'b00;

  assign apb4.pready = s_apb4_ready_q;
  assign apb4.prdata = s_apb4_rdata_q;
  assign apb4.pslverr = s_apb4_resp_err_q;

  assign s_ctrl_write_value = merge_wstrb(s_ctrl_q, apb4.pwdata, apb4.pstrb) & CTRL_WRITABLE_MASK;
  assign s_load_write_value = merge_wstrb(s_load_q, apb4.pwdata, apb4.pstrb);
  assign s_bgload_write_value = merge_wstrb(s_load_q, apb4.pwdata, apb4.pstrb);
  assign s_prescale_write_value = 16'(merge_wstrb({16'd0, s_prescale_q}, apb4.pwdata, apb4.pstrb));
  assign s_compare0_write_value = merge_wstrb(s_compare0_q, apb4.pwdata, apb4.pstrb);
  assign s_compare1_write_value = merge_wstrb(s_compare1_q, apb4.pwdata, apb4.pstrb);
  assign s_intr_en_write_value = 3'(merge_wstrb({29'd0, s_intr_en_q}, apb4.pwdata, apb4.pstrb));

  always_comb begin
    s_access_err   = !s_aligned;
    s_apb4_rdata_d = '0;
    if (s_aligned) begin
      unique case (s_offset)
        `APB4_TIMER_CTRL: begin
          s_apb4_rdata_d = s_ctrl_q;
          if (s_write) begin
            s_access_err =
                (s_ctrl_write_value[2:1] == MODE_RESERVED) ||
                (enable_o && (|((s_ctrl_write_value ^ s_ctrl_q) & CTRL_ACTIVE_IMMUTABLE_MASK)));
          end
        end
        `APB4_TIMER_LOAD:        s_apb4_rdata_d = s_load_q;
        `APB4_TIMER_VALUE: begin
          s_apb4_rdata_d = value_i;
          s_access_err   = s_write;
        end
        `APB4_TIMER_BGLOAD:      s_apb4_rdata_d = s_load_q;
        `APB4_TIMER_PRESCALE: begin
          s_apb4_rdata_d = {16'd0, s_prescale_q};
          s_access_err   = s_write && enable_o;
        end
        `APB4_TIMER_COMPARE0:    s_apb4_rdata_d = s_compare0_q;
        `APB4_TIMER_COMPARE1:    s_apb4_rdata_d = s_compare1_q;
        `APB4_TIMER_STATUS: begin
          s_apb4_rdata_d = {30'd0, debug_frozen_i, enable_o};
          s_access_err   = s_write;
        end
        `APB4_TIMER_INTR_STATE:  s_apb4_rdata_d = {29'd0, s_intr_state_q};
        `APB4_TIMER_INTR_ENABLE: s_apb4_rdata_d = {29'd0, s_intr_en_q};
        `APB4_TIMER_INTR_STATUS: begin
          s_apb4_rdata_d = {29'd0, s_intr_state_q & s_intr_en_q};
          s_access_err   = s_write;
        end
        `APB4_TIMER_INTR_TEST:   s_access_err = !s_write;
        `APB4_TIMER_IP_VERSION: begin
          s_apb4_rdata_d = IP_VERSION;
          s_access_err   = s_write;
        end
        `APB4_TIMER_CAPABILITY: begin
          s_apb4_rdata_d = CAPABILITY;
          s_access_err   = s_write;
        end
        default:                 s_access_err = 1'b1;
      endcase
    end
  end

  assign start_o = s_req_accept && s_write && !s_access_err &&
                   (s_offset == `APB4_TIMER_CTRL) && !enable_o &&
                   s_ctrl_write_value[`TIMER_CTRL_ENABLE];
  assign stop_o = s_req_accept && s_write && !s_access_err &&
                  (s_offset == `APB4_TIMER_CTRL) && enable_o &&
                  !s_ctrl_write_value[`TIMER_CTRL_ENABLE];
  assign load_now_o = s_req_accept && s_write && !s_access_err && (s_offset == `APB4_TIMER_LOAD);

  always_comb begin
    s_ctrl_d = s_ctrl_q;
    if (s_req_accept && s_write && !s_access_err && (s_offset == `APB4_TIMER_CTRL)) begin
      s_ctrl_d = s_ctrl_write_value;
    end
    if (one_shot_done_i) begin
      s_ctrl_d[`TIMER_CTRL_ENABLE] = 1'b0;
    end
  end
  dffr #(
      .DATA_WIDTH(32)
  ) u_ctrl_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_ctrl_d),
      .dat_o  (s_ctrl_q)
  );

  always_comb begin
    s_load_d = s_load_q;
    if (s_req_accept && s_write && !s_access_err) begin
      if (s_offset == `APB4_TIMER_LOAD) s_load_d = s_load_write_value;
      else if (s_offset == `APB4_TIMER_BGLOAD) s_load_d = s_bgload_write_value;
    end
  end
  dffr #(
      .DATA_WIDTH(32)
  ) u_load_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_load_d),
      .dat_o  (s_load_q)
  );

  always_comb begin
    s_prescale_d = s_prescale_q;
    if (s_req_accept && s_write && !s_access_err && (s_offset == `APB4_TIMER_PRESCALE)) begin
      s_prescale_d = s_prescale_write_value;
    end
  end
  dffr #(
      .DATA_WIDTH(16)
  ) u_prescale_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_prescale_d),
      .dat_o  (s_prescale_q)
  );

  always_comb begin
    s_compare0_d = s_compare0_q;
    s_compare1_d = s_compare1_q;
    if (s_req_accept && s_write && !s_access_err) begin
      if (s_offset == `APB4_TIMER_COMPARE0) s_compare0_d = s_compare0_write_value;
      if (s_offset == `APB4_TIMER_COMPARE1) s_compare1_d = s_compare1_write_value;
    end
  end
  dffr #(
      .DATA_WIDTH(32)
  ) u_compare0_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_compare0_d),
      .dat_o  (s_compare0_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_compare1_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_compare1_d),
      .dat_o  (s_compare1_q)
  );

  always_comb begin
    s_intr_en_d = s_intr_en_q;
    if (s_req_accept && s_write && !s_access_err && (s_offset == `APB4_TIMER_INTR_ENABLE)) begin
      s_intr_en_d = s_intr_en_write_value;
    end
  end
  dffr #(
      .DATA_WIDTH(3)
  ) u_intr_enable_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_intr_en_d),
      .dat_o  (s_intr_en_q)
  );

  always_comb begin
    s_intr_clear = '0;
    s_intr_set   = {compare1_event_i, compare0_event_i, timeout_event_i};
    if (s_req_accept && s_write && !s_access_err) begin
      if ((s_offset == `APB4_TIMER_INTR_STATE) && apb4.pstrb[0]) begin
        s_intr_clear = apb4.pwdata[2:0];
      end
      if ((s_offset == `APB4_TIMER_INTR_TEST) && apb4.pstrb[0]) begin
        s_intr_set = s_intr_set | apb4.pwdata[2:0];
      end
    end
    s_intr_state_d = (s_intr_state_q & ~s_intr_clear) | s_intr_set;
  end
  dffr #(
      .DATA_WIDTH(3)
  ) u_intr_state_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_intr_state_d),
      .dat_o  (s_intr_state_q)
  );

  assign enable_o = s_ctrl_q[`TIMER_CTRL_ENABLE];
  assign mode_o = s_ctrl_q[2:1];
  assign direction_o = s_ctrl_q[`TIMER_CTRL_DIRECTION];
  assign debug_freeze_enable_o = s_ctrl_q[`TIMER_CTRL_DEBUG_FREEZE];
  assign compare0_enable_o = s_ctrl_q[`TIMER_CTRL_COMPARE0_ENABLE];
  assign compare1_enable_o = s_ctrl_q[`TIMER_CTRL_COMPARE1_ENABLE];
  assign prescale_o = s_prescale_q;
  assign load_o = (s_req_accept && s_write && !s_access_err &&
                   ((s_offset == `APB4_TIMER_LOAD) ||
                    (s_offset == `APB4_TIMER_BGLOAD))) ?
                      (s_offset == `APB4_TIMER_LOAD ?
                           s_load_write_value : s_bgload_write_value) :
                      s_load_q;
  assign compare0_o = s_compare0_q;
  assign compare1_o = s_compare1_q;
  assign irq_o = |(s_intr_state_q & s_intr_en_q);

  assign s_apb4_ready_d = s_req_accept;
  assign s_apb4_resp_err_d = s_access_err;

  dffr #(
      .DATA_WIDTH(1)
  ) u_apb4_ready_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_apb4_ready_d),
      .dat_o  (s_apb4_ready_q)
  );
  dffer #(
      .DATA_WIDTH(1)
  ) u_apb4_resp_err_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_req_accept),
      .dat_i  (s_apb4_resp_err_d),
      .dat_o  (s_apb4_resp_err_q)
  );
  dffer #(
      .DATA_WIDTH(32)
  ) u_apb4_rdata_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_req_accept),
      .dat_i  (s_apb4_rdata_d),
      .dat_o  (s_apb4_rdata_q)
  );

endmodule
