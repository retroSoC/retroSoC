// Copyright (c) 2026 Yuchi Miao <miaoyuchi@ict.ac.cn>
// retroSoC is licensed under Mulan PSL v2.

module clint_formal_design (
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
    output logic        tick,
    output logic [63:0] mtime,
    output logic        mtime_load,
    output logic [63:0] mtime_load_value,
    output logic [ 1:0] msip,
    output logic [ 1:0] timer_irq_next,
    output logic [ 1:0] timer_irq
    // verilog_format: on
);

  apb4_if apb4 (
      .pclk   (clk_i),
      .presetn(rst_n_i)
  );
  (* anyseq *)logic        f_apb_sel;
  (* anyseq *)logic [31:0] f_apb_addr;
  (* anyseq *)logic [31:0] f_apb_wdata;
  (* anyseq *)logic [ 3:0] f_apb_pstrb;
  (* anyseq *)logic        f_tick;
  logic        s_mtime_load;
  logic [63:0] s_mtime_load_value;
  logic [63:0] s_mtime;
  logic [ 1:0] s_msip;
  logic [63:0] s_mtimecmp         [0:1];
  logic [ 1:0] s_timer_irq;

  assign apb4.psel         = f_apb_sel;
  assign apb4.penable      = f_apb_sel;
  assign apb4.pwrite       = |f_apb_pstrb;
  assign apb4.paddr        = f_apb_addr;
  assign apb4.pwdata       = f_apb_wdata;
  assign apb4.pstrb        = f_apb_pstrb;
  assign apb4.pprot        = 3'b000;

  assign rib_valid         = apb4.psel;
  assign rib_addr          = apb4.paddr;
  assign rib_wdata         = apb4.pwdata;
  assign rib_wstrb         = apb4.pstrb;
  assign rib_ready         = apb4.pready;
  assign rib_resp_err      = apb4.pslverr;
  assign tick              = f_tick;
  assign mtime             = s_mtime;
  assign mtime_load        = s_mtime_load;
  assign mtime_load_value  = s_mtime_load_value;
  assign msip              = s_msip;
  assign timer_irq_next[0] = s_mtime >= s_mtimecmp[0];
  assign timer_irq_next[1] = s_mtime >= s_mtimecmp[1];
  assign timer_irq         = s_timer_irq;

  clint_reg #(
      .HartNum(2)
  ) u_clint_reg (
      .clk_i             (clk_i),
      .rst_n_i           (rst_n_i),
      .apb4              (apb4),
      .mtime_i           (s_mtime),
      .mtime_load_o      (s_mtime_load),
      .mtime_load_value_o(s_mtime_load_value),
      .msip_o            (s_msip),
      .mtimecmp_o        (s_mtimecmp)
  );

  clint_core #(
      .HartNum(2)
  ) u_clint_core (
      .clk_i             (clk_i),
      .rst_n_i           (rst_n_i),
      .tick_i            (f_tick),
      .mtime_load_i      (s_mtime_load),
      .mtime_load_value_i(s_mtime_load_value),
      .mtimecmp_i        (s_mtimecmp),
      .mtime_o           (s_mtime),
      .timer_irq_o       (s_timer_irq)
  );

  initial begin
    rst_n_i      = 1'b1;
    f_past_valid = 1'b0;
  end

  always_ff @(posedge clk_i) begin
    rst_n_i      <= f_past_valid;
    f_past_valid <= 1'b1;
  end

endmodule
