// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

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
  apb4_if apb4 (
      .pclk   (clk_i),
      .presetn(rst_n_i)
  );
  (* anyseq *) logic f_apb_sel;
  (* anyseq *) logic [31:0] f_apb_addr, f_apb_wdata;
  (* anyseq *) logic [3:0] f_apb_pstrb;
  (* anyseq *) logic f_active, f_fifo_empty, f_fifo_full;
  (* anyseq *)logic [  5:0] f_error_flags;
  (* anyseq *)logic [127:0] f_frame_stats;
  (* anyseq *)logic         f_frame_stats_valid;
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
  dvp_reg u_dut (
      .clk_i              (clk_i),
      .rst_n_i            (rst_n_i),
      .apb4               (apb4),
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
      .cfg_o              (),
      .cfg_valid_o        (),
      .cfg_ready_i        (1'b1),
      .cmd_abort_o        (),
      .cmd_flush_o        (),
      .cmd_valid_o        (),
      .cmd_ready_i        (1'b1),
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
