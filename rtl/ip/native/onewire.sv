
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
`define ONEWIRE_STATUS  8'h18
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
  logic [1:0] s_ctrl_d, s_ctrl_q;
  logic [2:0] s_status_d, s_status_q;
  // fifo
  logic s_tx_push_valid, s_tx_empty, s_tx_full;
  logic s_tx_pop_valid, s_tx_pop_ready;
  logic [23:0] s_tx_push_data, s_tx_pop_data;

  logic s_done;

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

  always_comb begin
    s_tx_push_valid = 1'b0;
    s_tx_push_data  = '0;
    if (s_nmi_wr_hdshk && nmi.addr[7:0] == `ONEWIRE_TXDATA) begin
      s_tx_push_valid = 1'b1;
      if(nmi.wstrb[0]) s_tx_push_data[7:0] = nmi.wdata[7:0];
      if(nmi.wstrb[1]) s_tx_push_data[15:8] = nmi.wdata[15:8];
      if(nmi.wstrb[2]) s_tx_push_data[23:16] = nmi.wdata[23:16];
    end
  end

  assign s_tx_pop_ready = ~s_tx_empty;
  fifo #(
      .DATA_WIDTH  (24),
      .BUFFER_DEPTH(8)
  ) u_tx_fifo (
      .clk_i  (clk_i),
      .rst_n_i(rst_n_i),
      .flush_i(s_ctrl_q[0]),
      .cnt_o  (),
      .push_i (s_tx_push_valid),
      .full_o (s_tx_full),
      .dat_i  (s_tx_push_data),
      .pop_i  (s_tx_pop_valid),
      .empty_o(s_tx_empty),
      .dat_o  (s_tx_pop_data)
  );


  // [0] clear fifo [1] start
  always_comb begin
    if (s_nmi_wr_hdshk && nmi.addr[7:0] == `ONEWIRE_CTRL) begin
      s_ctrl_d = nmi.wdata[1:0];
    end else begin
      s_ctrl_d = '0;
    end
  end
  dffr #(2) u_ctrl_dffr (
      clk_i,
      rst_n_i,
      s_ctrl_d,
      s_ctrl_q
  );


  // [0] xfer done [1] fifo full, [2] fifo empty
  always_comb begin
    s_status_d    = s_status_q;
    s_status_d[1] = s_tx_full;
    s_status_d[2] = s_tx_empty;
    if (s_done) begin
      s_status_d[0] = 1'b1;
    end else if (s_nmi_rd_hdshk && nmi.addr[7:0] == `ONEWIRE_STATUS) begin
      s_status_d[0] = 1'b0;
    end
  end
  dffr #(3) u_status_dffr (
      clk_i,
      rst_n_i,
      s_status_d,
      s_status_q
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
      `ONEWIRE_CLKDIV:  s_nmi_rdata_d = {24'd0, s_clkdiv_q};
      `ONEWIRE_ZEROCNT: s_nmi_rdata_d = {24'd0, s_zerocnt_q};
      `ONEWIRE_ONECNT:  s_nmi_rdata_d = {24'd0, s_onecnt_q};
      `ONEWIRE_RSTNUM:  s_nmi_rdata_d = {24'd0, s_rstnum_q};
      `ONEWIRE_STATUS:  s_nmi_rdata_d = {29'd0, s_status_q};
      default:          s_nmi_rdata_d = s_nmi_rdata_q;
    endcase
  end
  dffer #(32) u_nmi_rdata_dffer (
      clk_i,
      rst_n_i,
      s_nmi_rdata_en,
      s_nmi_rdata_d,
      s_nmi_rdata_q
  );

  onewire_core u_onewire_core (
      .clk_i     (clk_i),
      .rst_n_i   (rst_n_i),
      .clkdiv_i  (s_clkdiv_q),
      .zerocnt_i (s_zerocnt_q),
      .onecnt_i  (s_onecnt_q),
      .rstnum_i  (s_rstnum_q),
      .start_i   (s_ctrl_q[1]),
      .data_req_o(s_tx_pop_valid),
      .data_rdy_i(s_tx_pop_ready),
      .data_i    (s_tx_pop_data),
      .done_o    (s_done),
      .onewire   (onewire)
  );
endmodule
