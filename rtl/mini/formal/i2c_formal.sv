// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.

module i2c_formal_design (
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
    output logic [ 4:0] command_count,
    output logic [ 4:0] rx_count,
    output logic [10:0] error_status,
    output logic [ 7:0] intr_state,
    output logic [ 7:0] intr_enable,
    output logic        command_valid,
    output logic        command_pop,
    output logic        rx_full,
    output logic        rx_push,
    output logic        busy,
    output logic        recovery_active,
    output logic        scl_o,
    output logic        sda_o,
    output logic        scl_oe,
    output logic        sda_oe,
    output logic        tx_dma_stall,
    output logic        rx_dma_stall,
    output logic        irq
    // verilog_format: on
);

  ribp_if ribp ();
  i2c_if i2c ();

  (* anyseq *)logic        f_rib_valid;
  (* anyseq *)logic [31:0] f_rib_addr;
  (* anyseq *)logic [31:0] f_rib_wdata;
  (* anyseq *)logic [ 3:0] f_rib_wstrb;
  (* anyseq *)logic        f_scl;
  (* anyseq *)logic        f_sda;

  assign ribp.valid      = f_rib_valid;
  assign ribp.addr       = f_rib_addr;
  assign ribp.wdata      = f_rib_wdata;
  assign ribp.wstrb      = f_rib_wstrb;
  assign i2c.scl_i       = f_scl;
  assign i2c.sda_i       = f_sda;

  assign rib_valid       = ribp.valid;
  assign rib_addr        = ribp.addr;
  assign rib_wdata       = ribp.wdata;
  assign rib_wstrb       = ribp.wstrb;
  assign rib_ready       = ribp.ready;
  assign rib_resp_err    = ribp.resp_err;
  assign command_count   = u_dut.u_i2c_reg.s_cmd_count;
  assign rx_count        = u_dut.u_i2c_reg.s_rx_count;
  assign error_status    = u_dut.u_i2c_reg.s_error_status_q;
  assign intr_state      = u_dut.u_i2c_reg.s_intr_state_q;
  assign intr_enable     = u_dut.u_i2c_reg.s_intr_enable_q;
  assign command_valid   = u_dut.s_cmd_valid;
  assign command_pop     = u_dut.s_cmd_pop;
  assign rx_full         = u_dut.s_rx_full;
  assign rx_push         = u_dut.s_rx_push;
  assign busy            = u_dut.s_busy;
  assign recovery_active = u_dut.s_recovery_active;
  assign scl_o           = i2c.scl_o;
  assign sda_o           = i2c.sda_o;
  assign scl_oe          = i2c.scl_oe_o;
  assign sda_oe          = i2c.sda_oe_o;
  assign irq             = i2c.irq_o;

  ribp_i2c u_dut (
      .clk_i         (clk_i),
      .rst_n_i       (rst_n_i),
      .dma_tx_stall_o(tx_dma_stall),
      .dma_rx_stall_o(rx_dma_stall),
      .ribp          (ribp),
      .i2c           (i2c)
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
