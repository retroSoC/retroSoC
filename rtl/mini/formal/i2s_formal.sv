// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.

module i2s_formal_design (
    input  logic        clk_i,
    output logic        rst_n_i,
    output logic        f_past_valid,
    output logic        rib_valid,
    output logic [31:0] rib_addr,
    output logic [31:0] rib_wdata,
    output logic [ 3:0] rib_wstrb,
    output logic        rib_ready,
    output logic        rib_resp_err,
    output logic [ 3:0] intr_state,
    output logic [ 3:0] intr_enable,
    output logic        irq
);
  apb4_if apb4 (
      .pclk   (clk_i),
      .presetn(rst_n_i)
  );
  (* anyseq *) logic f_apb_sel;
  (* anyseq *) logic [31:0] f_apb_addr, f_apb_wdata;
  (* anyseq *) logic [3:0] f_apb_pstrb;
  (* anyseq *) logic f_tx_full, f_tx_empty, f_rx_full, f_rx_empty;
  (* anyseq *) logic [7:0] f_tx_level, f_rx_level;
  (* anyseq *) logic f_tx_flush_busy, f_rx_flush_busy;
  (* anyseq *) logic f_tx_underrun, f_rx_overrun;
  assign apb4.psel    = f_apb_sel;
  assign apb4.penable = f_apb_sel;
  assign apb4.pwrite  = |f_apb_pstrb;
  assign apb4.paddr   = f_apb_addr;
  assign apb4.pwdata  = f_apb_wdata;
  assign apb4.pstrb   = f_apb_pstrb;
  assign apb4.pprot   = 3'b000;
  assign rib_valid    = apb4.psel;
  assign rib_addr     = apb4.paddr;
  assign rib_wdata    = apb4.pwdata;
  assign rib_wstrb    = apb4.pstrb;
  assign rib_ready    = apb4.pready;
  assign rib_resp_err = apb4.pslverr;
  assign intr_state   = u_dut.s_intr_stat_q;
  assign intr_enable  = u_dut.s_intr_en_q;
  i2s_reg u_dut (
      .clk_i             (clk_i),
      .rst_n_i           (rst_n_i),
      .apb4              (apb4),
      .tx_full_i         (f_tx_full),
      .tx_empty_i        (f_tx_empty),
      .tx_level_i        (f_tx_level),
      .rx_full_i         (f_rx_full),
      .rx_empty_i        (f_rx_empty),
      .rx_level_i        (f_rx_level),
      .tx_flush_busy_i   (f_tx_flush_busy),
      .rx_flush_busy_i   (f_rx_flush_busy),
      .tx_underrun_i     (f_tx_underrun),
      .rx_overrun_i      (f_rx_overrun),
      .tx_push_valid_o   (),
      .tx_push_data_o    (),
      .rx_pop_valid_o    (),
      .rx_pop_data_i     (32'd0),
      .cfg_o             (),
      .cmd_tx_flush_o    (),
      .cmd_rx_flush_o    (),
      .cmd_valid_o       (),
      .cmd_ready_i       (1'b1),
      .stream_tx_enable_o(),
      .stream_rx_enable_o(),
      .dma_tx_stall_o    (),
      .dma_rx_stall_o    (),
      .irq_o             (irq)
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
