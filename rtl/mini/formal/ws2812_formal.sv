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

  apb4_if apb4 (
      .pclk   (clk_i),
      .presetn(rst_n_i)
  );
  ws2812_if ws2812 ();

  (* anyseq *)logic        f_apb_sel;
  (* anyseq *)logic [31:0] f_apb_addr;
  (* anyseq *)logic [31:0] f_apb_wdata;
  (* anyseq *)logic [ 3:0] f_apb_pstrb;

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
  assign error_status   = u_dut.u_ws2812_reg.s_err_stat_q;
  assign intr_state     = u_dut.u_ws2812_reg.s_intr_state_q;
  assign intr_enable    = u_dut.u_ws2812_reg.s_intr_en_q;

  apb4_ws2812 u_dut (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .apb4   (apb4),
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
