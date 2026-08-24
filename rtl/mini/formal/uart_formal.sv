// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.
// You can use this software according to the terms and conditions of the Mulan PSL v2.
// You may obtain a copy of Mulan PSL v2 at:
//             http://license.coscl.org.cn/MulanPSL2
// THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
// EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE.
// See the Mulan PSL v2 for more details.

module uart_formal_design (
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
    output logic [ 6:0] tx_count,
    output logic [ 6:0] rx_count,
    output logic [ 6:0] error_status,
    output logic [ 6:0] intr_state,
    output logic [ 6:0] intr_enable,
    output logic        tx_enable,
    output logic        rx_enable,
    output logic        tx_busy,
    output logic        rx_active,
    output logic        break_active,
    output logic        auto_cts_enable,
    output logic        auto_rts_enable,
    output logic        cts_asserted,
    output logic        rts_asserted,
    output logic        tx_start_allowed,
    output logic        tx_flow_blocked,
    output logic        tx_data_pop,
    output logic        tx_dma_stall,
    output logic        rx_dma_stall,
    output logic        tx,
    output logic        rts_n,
    output logic        irq
    // verilog_format: on
);

  apb4_if apb4 (
      .pclk   (clk_i),
      .presetn(rst_n_i)
  );
  uart_if uart ();

  (* anyseq *)logic        f_apb_sel;
  (* anyseq *)logic [31:0] f_apb_addr;
  (* anyseq *)logic [31:0] f_apb_wdata;
  (* anyseq *)logic [ 3:0] f_apb_pstrb;
  (* anyseq *)logic        f_uart_rx;
  (* anyseq *)logic        f_uart_cts_n;

  assign apb4.psel        = f_apb_sel;
  assign apb4.penable     = f_apb_sel;
  assign apb4.pwrite      = |f_apb_pstrb;
  assign apb4.paddr       = f_apb_addr;
  assign apb4.pwdata      = f_apb_wdata;
  assign apb4.pstrb       = f_apb_pstrb;
  assign apb4.pprot       = 3'b000;
  assign uart.rx_i        = f_uart_rx;
  assign uart.cts_n_i     = f_uart_cts_n;

  assign rib_valid        = apb4.psel;
  assign rib_addr         = apb4.paddr;
  assign rib_wdata        = apb4.pwdata;
  assign rib_wstrb        = apb4.pstrb;
  assign rib_ready        = apb4.pready;
  assign rib_resp_err     = apb4.pslverr;
  assign tx_count         = u_dut.u_uart_reg.s_tx_count;
  assign rx_count         = u_dut.u_uart_reg.s_rx_count;
  assign error_status     = u_dut.u_uart_reg.s_err_stat_q;
  assign intr_state       = u_dut.u_uart_reg.s_intr_state_q;
  assign intr_enable      = u_dut.u_uart_reg.s_intr_en_q;
  assign tx_enable        = u_dut.s_tx_en;
  assign rx_enable        = u_dut.s_rx_en;
  assign tx_busy          = u_dut.s_tx_busy;
  assign rx_active        = u_dut.s_rx_active;
  assign break_active     = u_dut.s_break;
  assign auto_cts_enable  = u_dut.s_auto_cts_en;
  assign auto_rts_enable  = u_dut.s_auto_rts_en;
  assign cts_asserted     = u_dut.s_cts_asserted;
  assign rts_asserted     = u_dut.s_rts_asserted;
  assign tx_start_allowed = u_dut.s_tx_start_allowed;
  assign tx_flow_blocked  = u_dut.s_tx_flow_blocked;
  assign tx_data_pop      = u_dut.s_tx_data_pop;
  assign tx               = uart.tx_o;
  assign rts_n            = uart.rts_n_o;
  assign irq              = uart.irq_o;

  apb4_uart u_dut (
      .clk_i         (clk_i),
      .rst_n_i       (rst_n_i),
      .dma_tx_stall_o(tx_dma_stall),
      .dma_rx_stall_o(rx_dma_stall),
      .apb4          (apb4),
      .uart          (uart)
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
