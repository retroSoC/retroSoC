// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.

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

  ribp_if ribp ();
  uart_if uart ();

  (* anyseq *)logic        f_rib_valid;
  (* anyseq *)logic [31:0] f_rib_addr;
  (* anyseq *)logic [31:0] f_rib_wdata;
  (* anyseq *)logic [ 3:0] f_rib_wstrb;
  (* anyseq *)logic        f_uart_rx;
  (* anyseq *)logic        f_uart_cts_n;

  assign ribp.valid       = f_rib_valid;
  assign ribp.addr        = f_rib_addr;
  assign ribp.wdata       = f_rib_wdata;
  assign ribp.wstrb       = f_rib_wstrb;
  assign uart.rx_i        = f_uart_rx;
  assign uart.cts_n_i     = f_uart_cts_n;

  assign rib_valid        = ribp.valid;
  assign rib_addr         = ribp.addr;
  assign rib_wdata        = ribp.wdata;
  assign rib_wstrb        = ribp.wstrb;
  assign rib_ready        = ribp.ready;
  assign rib_resp_err     = ribp.resp_err;
  assign tx_count         = u_dut.u_uart_reg.s_tx_count;
  assign rx_count         = u_dut.u_uart_reg.s_rx_count;
  assign error_status     = u_dut.u_uart_reg.s_error_status_q;
  assign intr_state       = u_dut.u_uart_reg.s_intr_state_q;
  assign intr_enable      = u_dut.u_uart_reg.s_intr_enable_q;
  assign tx_enable        = u_dut.s_tx_enable;
  assign rx_enable        = u_dut.s_rx_enable;
  assign tx_busy          = u_dut.s_tx_busy;
  assign rx_active        = u_dut.s_rx_active;
  assign break_active     = u_dut.s_break;
  assign auto_cts_enable  = u_dut.s_auto_cts_enable;
  assign auto_rts_enable  = u_dut.s_auto_rts_enable;
  assign cts_asserted     = u_dut.s_cts_asserted;
  assign rts_asserted     = u_dut.s_rts_asserted;
  assign tx_start_allowed = u_dut.s_tx_start_allowed;
  assign tx_flow_blocked  = u_dut.s_tx_flow_blocked;
  assign tx_data_pop      = u_dut.s_tx_data_pop;
  assign tx               = uart.tx_o;
  assign rts_n            = uart.rts_n_o;
  assign irq              = uart.irq_o;

  ribp_uart u_dut (
      .clk_i         (clk_i),
      .rst_n_i       (rst_n_i),
      .dma_tx_stall_o(tx_dma_stall),
      .dma_rx_stall_o(rx_dma_stall),
      .ribp          (ribp),
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
