/* Simple 32-bit counter-timer for ravenna. */


`ifndef SIMP_TIMER_DEF_SV
`define SIMP_TIMER_DEF_SV

// verilog_format: off
`define SIMP_TIMER_CFG 8'h00
`define SIMP_TIMER_VAL 8'h04
`define SIMP_TIMER_DAT 8'h08
// verilog_format: on

`endif

module simple_timer (
    // verilog_format: off
    input  logic clk_i,
    input  logic rst_n_i,
    nmi_if.slave nmi,
    output logic irq_o
    // verilog_format: on
);

  logic s_irq_d, s_irq_q;
  logic s_nmi_wr_hdshk, s_nmi_rd_hdshk;
  logic s_nmi_ready_d, s_nmi_ready_q;
  logic s_nmi_rdata_en;
  logic [31:0] s_nmi_rdata_d, s_nmi_rdata_q;

  logic s_tim_cfg_en;
  logic [3:0] s_tim_cfg_d, s_tim_cfg_q;
  logic s_tim_val_en;
  logic [31:0] s_tim_val_d, s_tim_val_q;
  logic [31:0] s_tim_dat_d, s_tim_dat_q;
  // enable (start) the counter/timer
  // set s_bit_oneshot (1) mode or continuous (0) mode
  // count up (1) or down (0)
  // enable interrupt on timeout
  logic s_bit_en, s_bit_oneshot;
  logic s_bit_updown, s_bit_irq_en;


  assign irq_o          = s_irq_q;

  assign s_nmi_wr_hdshk = nmi.valid && (~s_nmi_ready_q) && (|nmi.wstrb);
  assign s_nmi_rd_hdshk = nmi.valid && (~s_nmi_ready_q) && (~(|nmi.wstrb));
  assign nmi.ready      = s_nmi_ready_q;
  assign nmi.rdata      = s_nmi_rdata_q;

  assign s_bit_en       = s_tim_cfg_q[0];
  assign s_bit_oneshot  = s_tim_cfg_q[1];
  assign s_bit_updown   = s_tim_cfg_q[2];
  assign s_bit_irq_en   = s_tim_cfg_q[3];


  assign s_tim_cfg_en   = s_nmi_wr_hdshk && nmi.addr[7:0] == `SIMP_TIMER_CFG;
  assign s_tim_cfg_d    = nmi.wdata[3:0];
  dffer #(4) u_tim_cfg_dffer (
      clk_i,
      rst_n_i,
      s_tim_cfg_en && nmi.wstrb[0],
      s_tim_cfg_d,
      s_tim_cfg_q
  );


  assign s_tim_val_en = s_nmi_wr_hdshk && nmi.addr[7:0] == `SIMP_TIMER_VAL;
  always_comb begin
    s_tim_val_d = s_tim_val_q;
    if (nmi.wstrb[0]) s_tim_val_d[7:0] = nmi.wdata[7:0];
    if (nmi.wstrb[1]) s_tim_val_d[15:8] = nmi.wdata[15:8];
    if (nmi.wstrb[2]) s_tim_val_d[23:16] = nmi.wdata[23:16];
    if (nmi.wstrb[3]) s_tim_val_d[31:24] = nmi.wdata[31:24];
  end
  dffer #(32) u_tim_val_dffer (
      clk_i,
      rst_n_i,
      s_tim_val_en,
      s_tim_val_d,
      s_tim_val_q
  );


  always_comb begin
    s_tim_dat_d = s_tim_dat_q;
    s_irq_d     = s_irq_q;
    if (s_nmi_wr_hdshk && nmi.addr[7:0] == `SIMP_TIMER_DAT) begin
      if (nmi.wstrb[0]) s_tim_dat_d[7:0] = nmi.wdata[7:0];
      if (nmi.wstrb[1]) s_tim_dat_d[15:8] = nmi.wdata[15:8];
      if (nmi.wstrb[2]) s_tim_dat_d[23:16] = nmi.wdata[23:16];
      if (nmi.wstrb[3]) s_tim_dat_d[31:24] = nmi.wdata[31:24];
    end else if (s_bit_en) begin
      if (s_bit_updown) begin
        if (s_tim_dat_q == s_tim_val_q) begin
          if (~s_bit_oneshot) s_tim_dat_d = '0;
          s_irq_d = s_bit_irq_en;
        end else begin
          s_tim_dat_d = s_tim_dat_q + 1'b1;
          s_irq_d     = '0;
        end
      end else begin
        if (s_tim_dat_q == '0) begin
          if (~s_bit_oneshot) s_tim_dat_d = s_tim_val_q;
          s_irq_d = s_bit_irq_en;
        end else begin
          s_tim_dat_d = s_tim_dat_q - 1'b1;
          s_irq_d     = '0;
        end
      end
    end
  end
  dffr #(32) u_tim_dat_dffr (
      clk_i,
      rst_n_i,
      s_tim_dat_d,
      s_tim_dat_q
  );

  dffr #(1) u_irq_dffr (
      clk_i,
      rst_n_i,
      s_irq_d,
      s_irq_q
  );


  assign s_nmi_ready_d = nmi.valid && (~s_nmi_ready_q);
  dffr #(1) u_nmi_ready_dffr (
      clk_i,
      rst_n_i,
      s_nmi_ready_d,
      s_nmi_ready_q
  );

  assign s_nmi_rdata_en = s_nmi_rd_hdshk;
  always_comb begin
    s_nmi_rdata_d = s_nmi_rdata_q;
    unique case (nmi.addr[7:0])
      `SIMP_TIMER_CFG: s_nmi_rdata_d = {28'd0, s_tim_cfg_q};
      `SIMP_TIMER_VAL: s_nmi_rdata_d = s_tim_val_q;
      `SIMP_TIMER_DAT: s_nmi_rdata_d = s_tim_dat_q;
      default:         s_nmi_rdata_d = s_nmi_rdata_q;
    endcase
  end
  dffer #(32) u_nmi_rdata_dffer (
      clk_i,
      rst_n_i,
      s_nmi_rdata_en,
      s_nmi_rdata_d,
      s_nmi_rdata_q
  );

endmodule
