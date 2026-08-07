// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.

module ws2812_formal_design (
    input  logic        clk_i,
    output logic        rst_n_i,
    output logic        f_past_valid,
    output logic        rib_valid,
    output logic [31:0] rib_addr,
    output logic [31:0] rib_wdata,
    output logic [ 3:0] rib_wstrb,
    output logic        rib_ready,
    output logic        rib_resp_err,
    output logic        dat,
    output logic        irq,
    output logic        busy,
    output logic        reset_active,
    output logic        start,
    output logic        abort_cmd,
    output logic        data_valid,
    output logic        data_pop,
    output logic        done,
    output logic        underflow,
    output logic        aborted,
    output logic [ 4:0] fifo_level,
    output logic [31:0] load_remaining,
    output logic [ 2:0] error_status,
    output logic [ 3:0] intr_state,
    output logic [ 3:0] intr_enable
);

  ribp_if rib ();
  ws2812_if ws2812 ();

  (* anyseq *)logic        f_rib_valid;
  (* anyseq *)logic [31:0] f_rib_addr;
  (* anyseq *)logic [31:0] f_rib_wdata;
  (* anyseq *)logic [ 3:0] f_rib_wstrb;

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
  assign dat            = ws2812.dat_o;
  assign irq            = ws2812.irq_o;
  assign busy           = u_dut.s_busy;
  assign reset_active   = u_dut.s_reset_active;
  assign start          = u_dut.s_start;
  assign abort_cmd      = u_dut.s_abort;
  assign data_valid     = u_dut.s_data_valid;
  assign data_pop       = u_dut.s_data_pop;
  assign done           = u_dut.s_done;
  assign underflow      = u_dut.s_underflow;
  assign aborted        = u_dut.s_aborted;
  assign fifo_level     = u_dut.u_ws2812_reg.s_tx_count;
  assign load_remaining = u_dut.u_ws2812_reg.s_load_remaining_q;
  assign error_status   = u_dut.u_ws2812_reg.s_error_status_q;
  assign intr_state     = u_dut.u_ws2812_reg.s_intr_state_q;
  assign intr_enable    = u_dut.u_ws2812_reg.s_intr_enable_q;

  ribp_ws2812 u_dut (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .ribp   (rib),
      .ws2812 (ws2812)
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
