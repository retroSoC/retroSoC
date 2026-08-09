// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.

`include "timer_define.svh"

module timer_reg (
    // verilog_format: off
    input  logic        clk_i,
    input  logic        rst_n_i,
    ribp_if.slave       ribp,
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
  logic        s_access_error;
  logic s_ribp_ready_d, s_ribp_ready_q;
  logic s_ribp_resp_err_d, s_ribp_resp_err_q;
  logic [31:0] s_ribp_rdata_d, s_ribp_rdata_q;

  logic [31:0] s_ctrl_write_value;
  logic [31:0] s_load_write_value;
  logic [31:0] s_bgload_write_value;
  logic [15:0] s_prescale_write_value;
  logic [31:0] s_compare0_write_value;
  logic [31:0] s_compare1_write_value;
  logic [ 2:0] s_intr_enable_write_value;
  logic [ 2:0] s_intr_clear;
  logic [ 2:0] s_intr_set;
  logic [ 2:0] s_intr_state_d;
  logic [ 2:0] s_intr_state_q;
  logic [ 2:0] s_intr_enable_d;
  logic [ 2:0] s_intr_enable_q;
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

  assign s_req = ribp.valid && !s_ribp_ready_q;
  assign s_write = |ribp.wstrb;
  assign s_req_accept = s_req;
  assign s_offset = ribp.addr[11:0];
  assign s_aligned = ribp.addr[1:0] == 2'b00;

  assign ribp.ready = s_ribp_ready_q;
  assign ribp.rdata = s_ribp_rdata_q;
  assign ribp.resp_err = s_ribp_resp_err_q;

  assign s_ctrl_write_value = merge_wstrb(s_ctrl_q, ribp.wdata, ribp.wstrb) & CTRL_WRITABLE_MASK;
  assign s_load_write_value = merge_wstrb(s_load_q, ribp.wdata, ribp.wstrb);
  assign s_bgload_write_value = merge_wstrb(s_load_q, ribp.wdata, ribp.wstrb);
  assign s_prescale_write_value = 16'(merge_wstrb({16'd0, s_prescale_q}, ribp.wdata, ribp.wstrb));
  assign s_compare0_write_value = merge_wstrb(s_compare0_q, ribp.wdata, ribp.wstrb);
  assign s_compare1_write_value = merge_wstrb(s_compare1_q, ribp.wdata, ribp.wstrb);
  assign s_intr_enable_write_value = 3'(merge_wstrb(
      {29'd0, s_intr_enable_q}, ribp.wdata, ribp.wstrb
  ));

  always_comb begin
    s_access_error = !s_aligned;
    s_ribp_rdata_d = '0;
    if (s_aligned) begin
      unique case (s_offset)
        `RIBP_TIMER_CTRL: begin
          s_ribp_rdata_d = s_ctrl_q;
          if (s_write) begin
            s_access_error =
                (s_ctrl_write_value[2:1] == MODE_RESERVED) ||
                (enable_o && (|((s_ctrl_write_value ^ s_ctrl_q) & CTRL_ACTIVE_IMMUTABLE_MASK)));
          end
        end
        `RIBP_TIMER_LOAD:        s_ribp_rdata_d = s_load_q;
        `RIBP_TIMER_VALUE: begin
          s_ribp_rdata_d = value_i;
          s_access_error = s_write;
        end
        `RIBP_TIMER_BGLOAD:      s_ribp_rdata_d = s_load_q;
        `RIBP_TIMER_PRESCALE: begin
          s_ribp_rdata_d = {16'd0, s_prescale_q};
          s_access_error = s_write && enable_o;
        end
        `RIBP_TIMER_COMPARE0:    s_ribp_rdata_d = s_compare0_q;
        `RIBP_TIMER_COMPARE1:    s_ribp_rdata_d = s_compare1_q;
        `RIBP_TIMER_STATUS: begin
          s_ribp_rdata_d = {30'd0, debug_frozen_i, enable_o};
          s_access_error = s_write;
        end
        `RIBP_TIMER_INTR_STATE:  s_ribp_rdata_d = {29'd0, s_intr_state_q};
        `RIBP_TIMER_INTR_ENABLE: s_ribp_rdata_d = {29'd0, s_intr_enable_q};
        `RIBP_TIMER_INTR_STATUS: begin
          s_ribp_rdata_d = {29'd0, s_intr_state_q & s_intr_enable_q};
          s_access_error = s_write;
        end
        `RIBP_TIMER_INTR_TEST:   s_access_error = !s_write;
        `RIBP_TIMER_IP_VERSION: begin
          s_ribp_rdata_d = IP_VERSION;
          s_access_error = s_write;
        end
        `RIBP_TIMER_CAPABILITY: begin
          s_ribp_rdata_d = CAPABILITY;
          s_access_error = s_write;
        end
        default:                 s_access_error = 1'b1;
      endcase
    end
  end

  assign start_o = s_req_accept && s_write && !s_access_error &&
                   (s_offset == `RIBP_TIMER_CTRL) && !enable_o &&
                   s_ctrl_write_value[`TIMER_CTRL_ENABLE];
  assign stop_o = s_req_accept && s_write && !s_access_error &&
                  (s_offset == `RIBP_TIMER_CTRL) && enable_o &&
                  !s_ctrl_write_value[`TIMER_CTRL_ENABLE];
  assign load_now_o = s_req_accept && s_write && !s_access_error && (s_offset == `RIBP_TIMER_LOAD);

  always_comb begin
    s_ctrl_d = s_ctrl_q;
    if (s_req_accept && s_write && !s_access_error && (s_offset == `RIBP_TIMER_CTRL)) begin
      s_ctrl_d = s_ctrl_write_value;
    end
    if (one_shot_done_i) begin
      s_ctrl_d[`TIMER_CTRL_ENABLE] = 1'b0;
    end
  end
  dffr #(32) u_ctrl_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_ctrl_d),
      .dat_o  (s_ctrl_q)
  );

  always_comb begin
    s_load_d = s_load_q;
    if (s_req_accept && s_write && !s_access_error) begin
      if (s_offset == `RIBP_TIMER_LOAD) s_load_d = s_load_write_value;
      else if (s_offset == `RIBP_TIMER_BGLOAD) s_load_d = s_bgload_write_value;
    end
  end
  dffr #(32) u_load_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_load_d),
      .dat_o  (s_load_q)
  );

  always_comb begin
    s_prescale_d = s_prescale_q;
    if (s_req_accept && s_write && !s_access_error && (s_offset == `RIBP_TIMER_PRESCALE)) begin
      s_prescale_d = s_prescale_write_value;
    end
  end
  dffr #(16) u_prescale_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_prescale_d),
      .dat_o  (s_prescale_q)
  );

  always_comb begin
    s_compare0_d = s_compare0_q;
    s_compare1_d = s_compare1_q;
    if (s_req_accept && s_write && !s_access_error) begin
      if (s_offset == `RIBP_TIMER_COMPARE0) s_compare0_d = s_compare0_write_value;
      if (s_offset == `RIBP_TIMER_COMPARE1) s_compare1_d = s_compare1_write_value;
    end
  end
  dffr #(32) u_compare0_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_compare0_d),
      .dat_o  (s_compare0_q)
  );
  dffr #(32) u_compare1_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_compare1_d),
      .dat_o  (s_compare1_q)
  );

  always_comb begin
    s_intr_enable_d = s_intr_enable_q;
    if (s_req_accept && s_write && !s_access_error && (s_offset == `RIBP_TIMER_INTR_ENABLE)) begin
      s_intr_enable_d = s_intr_enable_write_value;
    end
  end
  dffr #(3) u_intr_enable_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_intr_enable_d),
      .dat_o  (s_intr_enable_q)
  );

  always_comb begin
    s_intr_clear = '0;
    s_intr_set   = {compare1_event_i, compare0_event_i, timeout_event_i};
    if (s_req_accept && s_write && !s_access_error) begin
      if ((s_offset == `RIBP_TIMER_INTR_STATE) && ribp.wstrb[0]) begin
        s_intr_clear = ribp.wdata[2:0];
      end
      if ((s_offset == `RIBP_TIMER_INTR_TEST) && ribp.wstrb[0]) begin
        s_intr_set = s_intr_set | ribp.wdata[2:0];
      end
    end
    s_intr_state_d = (s_intr_state_q & ~s_intr_clear) | s_intr_set;
  end
  dffr #(3) u_intr_state_dffr (
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
  assign load_o = (s_req_accept && s_write && !s_access_error &&
                   ((s_offset == `RIBP_TIMER_LOAD) ||
                    (s_offset == `RIBP_TIMER_BGLOAD))) ?
                      (s_offset == `RIBP_TIMER_LOAD ?
                           s_load_write_value : s_bgload_write_value) :
                      s_load_q;
  assign compare0_o = s_compare0_q;
  assign compare1_o = s_compare1_q;
  assign irq_o = |(s_intr_state_q & s_intr_enable_q);

  assign s_ribp_ready_d = s_req_accept;
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

endmodule
