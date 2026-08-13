// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.

module dvp_formal_design (
    input  logic        clk_i,
    output logic        rst_n_i,
    output logic        f_past_valid,
    output logic        rib_valid,
    output logic [31:0] rib_addr,
    output logic [31:0] rib_wdata,
    output logic [ 3:0] rib_wstrb,
    output logic        rib_ready,
    output logic        rib_resp_err,
    output logic [ 6:0] intr_state,
    output logic [ 6:0] intr_enable,
    output logic        irq
);
  ribp_if rib ();
  (* anyseq *) logic f_rib_valid;
  (* anyseq *) logic [31:0] f_rib_addr, f_rib_wdata;
  (* anyseq *) logic [3:0] f_rib_wstrb;
  (* anyseq *) logic f_active, f_fifo_empty, f_fifo_full;
  (* anyseq *)logic [  5:0] f_error_flags;
  (* anyseq *)logic [127:0] f_frame_stats;
  (* anyseq *)logic         f_frame_stats_valid;
  assign rib.valid    = f_rib_valid;
  assign rib.addr     = f_rib_addr;
  assign rib.wdata    = f_rib_wdata;
  assign rib.wstrb    = f_rib_wstrb;
  assign rib_valid    = rib.valid;
  assign rib_addr     = rib.addr;
  assign rib_wdata    = rib.wdata;
  assign rib_wstrb    = rib.wstrb;
  assign rib_ready    = rib.ready;
  assign rib_resp_err = rib.resp_err;
  assign intr_state   = u_dut.s_intr_stat_q;
  assign intr_enable  = u_dut.s_intr_en_q;
  dvp_reg u_dut (
      .clk_i              (clk_i),
      .rst_n_i            (rst_n_i),
      .ribp               (rib),
      .active_i           (f_active),
      .fifo_empty_i       (f_fifo_empty),
      .fifo_full_i        (f_fifo_full),
      .rx_data_i          (32'd0),
      .frame_start_i      (1'b0),
      .line_done_i        (1'b0),
      .frame_done_i       (1'b0),
      .error_event_i      (|f_error_flags),
      .error_flags_i      (f_error_flags),
      .frame_stats_i      (f_frame_stats),
      .frame_stats_valid_i(f_frame_stats_valid),
      .config_o           (),
      .config_valid_o     (),
      .config_ready_i     (1'b1),
      .command_abort_o    (),
      .command_flush_o    (),
      .command_valid_o    (),
      .command_ready_i    (1'b1),
      .rx_pop_o           (),
      .stream_enable_o    (),
      .irq_o              (irq)
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
