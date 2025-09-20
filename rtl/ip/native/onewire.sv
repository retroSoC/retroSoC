
`ifndef ONEWIRE_DEF_SV
`define ONEWIRE_DEF_SV

// verilog_format: off
// `define SIMP_GPIO_NUM  8
`define ONEWIRE_CLKDIV  8'h00
`define ONEWIRE_ZEROCNT 8'h04
`define ONEWIRE_ONECNT  8'h08
`define ONEWIRE_RSTNUM  8'h0C
`define ONEWIRE_TXDATA  8'h10
`define ONEWIRE_CTRL    8'h14
// verilog_format: on

`endif

interface onewire_if ();
  logic dat_o;

  modport dut(output dat_o);
endinterface

// generate 1250ns for ws2812x only
module nmi_onewire (
    // verilog_format: off
    input logic    clk_i,
    input logic    rst_n_i,
    nmi_if.slave   nmi,
    onewire_if.dut onewire
    // verilog_format: on
);

  logic s_nmi_wr_hdshk, s_nmi_rd_hdshk;
  logic s_nmi_ready_d, s_nmi_ready_q;
  logic s_nmi_rdata_en;
  logic [31:0] s_nmi_rdata_d, s_nmi_rdata_q;

  logic s_clkdiv_en;
  logic [7:0] s_clkdiv_d, s_clkdiv_q;
  logic s_zerocnt_en;
  logic [7:0] s_zerocnt_d, s_zerocnt_q;
  logic s_onecnt_en;
  logic [7:0] s_onecnt_d, s_onecnt_q;
  logic s_rstnum_en;
  logic [7:0] s_rstnum_d, s_rstnum_q;
  logic s_txdata_en;
  logic [23:0] s_txdata_d, s_txdata_q;
  logic s_ctrl_en;
  logic [1:0] s_ctrl_d, s_ctrl_q;


  assign s_nmi_wr_hdshk = nmi.valid && (~s_nmi_ready_q) && (|nmi.wstrb);
  assign s_nmi_rd_hdshk = nmi.valid && (~s_nmi_ready_q) && (~(|nmi.wstrb));
  assign nmi.ready      = s_nmi_ready_q;
  assign nmi.rdata      = s_nmi_rdata_q;


  assign s_clkdiv_en    = s_nmi_wr_hdshk && nmi.addr[7:0] == `ONEWIRE_CLKDIV;
  assign s_clkdiv_d     = nmi.wdata[7:0];
  dffer #(8) u_clkdiv_dffer (
      clk_i,
      rst_n_i,
      s_clkdiv_en,
      s_clkdiv_d,
      s_clkdiv_q
  );

  assign s_zerocnt_en = s_nmi_wr_hdshk && nmi.addr[7:0] == `ONEWIRE_ZEROCNT;
  assign s_zerocnt_d  = nmi.wdata[7:0];
  dffer #(8) u_zerocnt_dffer (
      clk_i,
      rst_n_i,
      s_zerocnt_en,
      s_zerocnt_d,
      s_zerocnt_q
  );

  assign s_onecnt_en = s_nmi_wr_hdshk && nmi.addr[7:0] == `ONEWIRE_ONECNT;
  assign s_onecnt_d  = nmi.wdata[7:0];
  dffer #(8) u_onecnt_dffer (
      clk_i,
      rst_n_i,
      s_onecnt_en,
      s_onecnt_d,
      s_onecnt_q
  );

  assign s_rstnum_en = s_nmi_wr_hdshk && nmi.addr[7:0] == `ONEWIRE_RSTNUM;
  assign s_rstnum_d  = nmi.wdata[7:0];
  dffer #(8) u_rstnum_dffer (
      clk_i,
      rst_n_i,
      s_rstnum_en,
      s_rstnum_d,
      s_rstnum_q
  );

  // TXDATA

  assign s_ctrl_en = s_nmi_wr_hdshk && nmi.addr[7:0] == `ONEWIRE_CTRL;

  assign s_ctrl_d  = nmi.wdata[1:0];
  dffer #(2) u_ctrl_dffer (
      clk_i,
      rst_n_i,
      s_ctrl_en,
      s_ctrl_d,
      s_ctrl_q
  );


  onewire_core u_onewire_core (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .onewire(onewire)
  );
endmodule
