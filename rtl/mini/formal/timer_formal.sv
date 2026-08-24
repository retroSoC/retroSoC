// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

module timer_formal_design (
    // verilog_format: off
    input  logic        clk_i,
    output logic        rst_n_i,
    output logic        f_past_valid,
    output logic        rib_valid,
    output logic [31:0] rib_addr,
    output logic [31:0] rib_wdata,
    output logic [ 3:0] rib_wstrb,
    output logic        rib_ready,
    output logic        rib_resp_err,
    output logic        debug_halted,
    output logic        active,
    output logic        debug_frozen,
    output logic [31:0] value,
    output logic        start,
    output logic        stop,
    output logic        load_now,
    output logic        timeout_event,
    output logic        compare0_event,
    output logic        compare1_event,
    output logic        one_shot_done,
    output logic [ 2:0] intr_state,
    output logic [ 2:0] intr_enable,
    output logic        irq
    // verilog_format: on
);

  apb4_if apb4 (
      .pclk   (clk_i),
      .presetn(rst_n_i)
  );

  (* anyseq *)logic        f_apb_sel;
  (* anyseq *)logic [31:0] f_apb_addr;
  (* anyseq *)logic [31:0] f_apb_wdata;
  (* anyseq *)logic [ 3:0] f_apb_pstrb;
  (* anyseq *)logic        f_debug_halted;

  assign apb4.psel      = f_apb_sel;
  assign apb4.penable   = f_apb_sel;
  assign apb4.pwrite    = |f_apb_pstrb;
  assign apb4.paddr     = f_apb_addr;
  assign apb4.pwdata    = f_apb_wdata;
  assign apb4.pstrb     = f_apb_pstrb;
  assign apb4.pprot     = 3'b000;

  assign rib_valid      = apb4.psel;
  assign rib_addr       = apb4.paddr;
  assign rib_wdata      = apb4.pwdata;
  assign rib_wstrb      = apb4.pstrb;
  assign rib_ready      = apb4.pready;
  assign rib_resp_err   = apb4.pslverr;
  assign debug_halted   = f_debug_halted;
  assign active         = u_dut.s_en;
  assign debug_frozen   = u_dut.s_debug_frozen;
  assign value          = u_dut.s_value;
  assign start          = u_dut.s_start;
  assign stop           = u_dut.s_stop;
  assign load_now       = u_dut.s_load_now;
  assign timeout_event  = u_dut.s_timeout_event;
  assign compare0_event = u_dut.s_compare0_event;
  assign compare1_event = u_dut.s_compare1_event;
  assign one_shot_done  = u_dut.s_one_shot_done;
  assign intr_state     = u_dut.u_timer_reg.s_intr_state_q;
  assign intr_enable    = u_dut.u_timer_reg.s_intr_en_q;

  apb4_timer u_dut (
      .clk_i         (clk_i),
      .rst_n_i       (rst_n_i),
      .debug_halted_i(f_debug_halted),
      .apb4          (apb4),
      .irq_o         (irq)
  );

  initial begin
    rst_n_i      = 1'b0;
    f_past_valid = 1'b0;
  end

  always_ff @(posedge clk_i) begin
    rst_n_i      <= 1'b1;
    f_past_valid <= 1'b1;
  end

endmodule
