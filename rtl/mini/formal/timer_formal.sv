// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.

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

  ribp_if rib ();

  (* anyseq *)logic        f_rib_valid;
  (* anyseq *)logic [31:0] f_rib_addr;
  (* anyseq *)logic [31:0] f_rib_wdata;
  (* anyseq *)logic [ 3:0] f_rib_wstrb;
  (* anyseq *)logic        f_debug_halted;

  assign rib.valid      = f_rib_valid;
  assign rib.addr       = f_rib_addr;
  assign rib.wdata      = f_rib_wdata;
  assign rib.wstrb      = f_rib_wstrb;

  assign rib_valid      = rib.valid;
  assign rib_addr       = rib.addr;
  assign rib_wdata      = rib.wdata;
  assign rib_wstrb      = rib.wstrb;
  assign rib_ready      = rib.ready;
  assign rib_resp_err   = rib.resp_err;
  assign debug_halted   = f_debug_halted;
  assign active         = u_dut.s_enable;
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
  assign intr_enable    = u_dut.u_timer_reg.s_intr_enable_q;

  ribp_timer u_dut (
      .clk_i         (clk_i),
      .rst_n_i       (rst_n_i),
      .debug_halted_i(f_debug_halted),
      .ribp          (rib),
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
