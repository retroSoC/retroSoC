// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// SPDX-License-Identifier: MulanPSL-2.0

`include "hp_mailbox_define.svh"

module apb4_hp_mailbox (
    // verilog_format: off -- preserve APB and interrupt alignment
    input  logic  clk_i,
    input  logic  rst_n_i,
    apb4_if.slave apb4,
    output logic  lp_irq_o,
    output logic  hp_irq_o
    // verilog_format: on
);
  localparam logic [31:0] IpVersion = 32'h0001_0000;
  localparam logic [31:0] Capability = 32'h0000_0007;

  logic        s_req_accept;
  logic        s_write;
  logic [11:0] s_offset;
  logic        s_access_err;
  logic s_ready_d, s_ready_q;
  logic s_resp_err_d, s_resp_err_q;
  logic [31:0] s_rdata_d, s_rdata_q;
  logic [31:0] s_lp_cmd_d, s_lp_cmd_q;
  logic [31:0] s_lp_arg0_d, s_lp_arg0_q;
  logic [31:0] s_lp_sequence_d, s_lp_sequence_q;
  logic [31:0] s_hp_event_d, s_hp_event_q;
  logic [31:0] s_hp_arg0_d, s_hp_arg0_q;
  logic [31:0] s_hp_sequence_d, s_hp_sequence_q;
  logic s_lp_intr_state_d, s_lp_intr_state_q;
  logic s_lp_intr_en_d, s_lp_intr_en_q;
  logic s_hp_intr_state_d, s_hp_intr_state_q;
  logic s_hp_intr_en_d, s_hp_intr_en_q;

  function automatic logic [31:0] merge_wstrb(input logic [31:0] current, input logic [31:0] value,
                                              input logic [3:0] strobe);
    logic [31:0] merged;
    begin
      merged = current;
      for (int byte_index = 0; byte_index < 4; byte_index++) begin
        if (strobe[byte_index]) merged[byte_index*8+:8] = value[byte_index*8+:8];
      end
      return merged;
    end
  endfunction

  assign s_req_accept = apb4.psel && apb4.penable && !s_ready_q;
  assign s_write      = apb4.pwrite;
  assign s_offset     = apb4.paddr[11:0];
  assign apb4.pready  = s_ready_q;
  assign apb4.pslverr = s_resp_err_q;
  assign apb4.prdata  = s_rdata_q;
  assign lp_irq_o     = s_lp_intr_state_q && s_lp_intr_en_q;
  assign hp_irq_o     = s_hp_intr_state_q && s_hp_intr_en_q;

  always_comb begin
    s_access_err = 1'b0;
    s_rdata_d    = '0;
    unique case (s_offset)
      `APB4_HP_MAILBOX__IP_VERSION:     s_rdata_d = IpVersion;
      `APB4_HP_MAILBOX__CAPABILITY:     s_rdata_d = Capability;
      `APB4_HP_MAILBOX__LP_COMMAND:     s_rdata_d = s_lp_cmd_q;
      `APB4_HP_MAILBOX__LP_ARG0:        s_rdata_d = s_lp_arg0_q;
      `APB4_HP_MAILBOX__LP_SEQUENCE:    s_rdata_d = s_lp_sequence_q;
      `APB4_HP_MAILBOX__HP_EVENT:       s_rdata_d = s_hp_event_q;
      `APB4_HP_MAILBOX__HP_ARG0:        s_rdata_d = s_hp_arg0_q;
      `APB4_HP_MAILBOX__HP_SEQUENCE:    s_rdata_d = s_hp_sequence_q;
      `APB4_HP_MAILBOX__LP_INTR_STATE:  s_rdata_d = {31'd0, s_lp_intr_state_q};
      `APB4_HP_MAILBOX__LP_INTR_ENABLE: s_rdata_d = {31'd0, s_lp_intr_en_q};
      `APB4_HP_MAILBOX__LP_INTR_STATUS: s_rdata_d = {31'd0, lp_irq_o};
      `APB4_HP_MAILBOX__HP_INTR_STATE:  s_rdata_d = {31'd0, s_hp_intr_state_q};
      `APB4_HP_MAILBOX__HP_INTR_ENABLE: s_rdata_d = {31'd0, s_hp_intr_en_q};
      `APB4_HP_MAILBOX__HP_INTR_STATUS: s_rdata_d = {31'd0, hp_irq_o};
      `APB4_HP_MAILBOX__LP_DOORBELL, `APB4_HP_MAILBOX__HP_DOORBELL,
      `APB4_HP_MAILBOX__LP_INTR_TEST, `APB4_HP_MAILBOX__HP_INTR_TEST: begin
        s_access_err = !s_write;
      end
      default:                          s_access_err = 1'b1;
    endcase
  end

  always_comb begin
    s_lp_cmd_d        = s_lp_cmd_q;
    s_lp_arg0_d       = s_lp_arg0_q;
    s_lp_sequence_d   = s_lp_sequence_q;
    s_hp_event_d      = s_hp_event_q;
    s_hp_arg0_d       = s_hp_arg0_q;
    s_hp_sequence_d   = s_hp_sequence_q;
    s_lp_intr_state_d = s_lp_intr_state_q;
    s_lp_intr_en_d    = s_lp_intr_en_q;
    s_hp_intr_state_d = s_hp_intr_state_q;
    s_hp_intr_en_d    = s_hp_intr_en_q;
    if (s_req_accept && s_write && !s_access_err) begin
      unique case (s_offset)
        `APB4_HP_MAILBOX__LP_COMMAND: s_lp_cmd_d = merge_wstrb(s_lp_cmd_q, apb4.pwdata, apb4.pstrb);
        `APB4_HP_MAILBOX__LP_ARG0: s_lp_arg0_d = merge_wstrb(s_lp_arg0_q, apb4.pwdata, apb4.pstrb);
        `APB4_HP_MAILBOX__LP_SEQUENCE:
        s_lp_sequence_d = merge_wstrb(s_lp_sequence_q, apb4.pwdata, apb4.pstrb);
        `APB4_HP_MAILBOX__LP_DOORBELL: s_hp_intr_state_d = 1'b1;
        `APB4_HP_MAILBOX__HP_EVENT:
        s_hp_event_d = merge_wstrb(s_hp_event_q, apb4.pwdata, apb4.pstrb);
        `APB4_HP_MAILBOX__HP_ARG0: s_hp_arg0_d = merge_wstrb(s_hp_arg0_q, apb4.pwdata, apb4.pstrb);
        `APB4_HP_MAILBOX__HP_SEQUENCE:
        s_hp_sequence_d = merge_wstrb(s_hp_sequence_q, apb4.pwdata, apb4.pstrb);
        `APB4_HP_MAILBOX__HP_DOORBELL: s_lp_intr_state_d = 1'b1;
        `APB4_HP_MAILBOX__LP_INTR_STATE:
        if (apb4.pstrb[0] && apb4.pwdata[0]) s_lp_intr_state_d = 1'b0;
        `APB4_HP_MAILBOX__LP_INTR_ENABLE: if (apb4.pstrb[0]) s_lp_intr_en_d = apb4.pwdata[0];
        `APB4_HP_MAILBOX__LP_INTR_TEST:
        if (apb4.pstrb[0] && apb4.pwdata[0]) s_lp_intr_state_d = 1'b1;
        `APB4_HP_MAILBOX__HP_INTR_STATE:
        if (apb4.pstrb[0] && apb4.pwdata[0]) s_hp_intr_state_d = 1'b0;
        `APB4_HP_MAILBOX__HP_INTR_ENABLE: if (apb4.pstrb[0]) s_hp_intr_en_d = apb4.pwdata[0];
        `APB4_HP_MAILBOX__HP_INTR_TEST:
        if (apb4.pstrb[0] && apb4.pwdata[0]) s_hp_intr_state_d = 1'b1;
        default: begin
        end
      endcase
    end
  end

  assign s_ready_d    = s_req_accept;
  assign s_resp_err_d = s_req_accept && s_access_err;

  dffr #(
      .DATA_WIDTH(1)
  ) u_ready_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_ready_d),
      .dat_o  (s_ready_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_resp_err_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_resp_err_d),
      .dat_o  (s_resp_err_q)
  );
  dffer #(
      .DATA_WIDTH(32)
  ) u_rdata_dffer (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .en_i   (s_req_accept && !s_write),
      .dat_i  (s_rdata_d),
      .dat_o  (s_rdata_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_lp_command_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_lp_cmd_d),
      .dat_o  (s_lp_cmd_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_lp_arg0_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_lp_arg0_d),
      .dat_o  (s_lp_arg0_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_lp_sequence_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_lp_sequence_d),
      .dat_o  (s_lp_sequence_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_hp_event_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_hp_event_d),
      .dat_o  (s_hp_event_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_hp_arg0_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_hp_arg0_d),
      .dat_o  (s_hp_arg0_q)
  );
  dffr #(
      .DATA_WIDTH(32)
  ) u_hp_sequence_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_hp_sequence_d),
      .dat_o  (s_hp_sequence_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_lp_intr_state_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_lp_intr_state_d),
      .dat_o  (s_lp_intr_state_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_lp_intr_enable_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_lp_intr_en_d),
      .dat_o  (s_lp_intr_en_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_hp_intr_state_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_hp_intr_state_d),
      .dat_o  (s_hp_intr_state_q)
  );
  dffr #(
      .DATA_WIDTH(1)
  ) u_hp_intr_enable_dffr (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .dat_i  (s_hp_intr_en_d),
      .dat_o  (s_hp_intr_en_q)
  );
endmodule

